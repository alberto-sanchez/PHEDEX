package PHEDEX::Web::Core;

=pod
=head1 NAME

PHEDEX::Web::Core - fetch, format, and return PhEDEx data

=head1 DESCRIPTION

This is the core module of the PhEDEx Data Service, a framework to
serve PhEDEx data in multiple formats for machine consumption.

=head2 URL Format

Calls to the PhEDEx data service should be made using the following URL format:

C<http://host.cern.ch/phedex/datasvc/FORMAT/INSTANCE/CALL?OPTIONS>

 FORMAT    the desired output format (e.g. xml, json, or perl)
 INSTANCE  the PhEDEx database instance from which to fetch the data
           (e.g. prod, debug, dev)
 CALL      the API call to make (see below)
 OPTIONS   the options to the CALL, in standard query string format

=head2 Output

Each response will have the following data in its "top level"
attributes.  With the XML format, these attributes appear in the
top-level "phedex" element.

 request_timestamp  unix timestamp, time of request
 request_date       human-readable time of request
 request_call       name of API call
 instance           PhEDEx DB instance
 call_time          time it took to serve call
 request_url        the full URL of the request

=head2 Errors

Currently all errors are returned in XML format, with a single <error>
element containing a text description of what went wrong.  For example:

C<http://host.cern.ch/phedex/datasvc/xml/prod/foobar>

   <error>
   API call 'foobar' is not defined.  Check the URL
   </error>

=head2 Multi-Value filters

Filters with multiple values follow some common rules for all calls,
unless otherwise specified:

 * by default the multiple-value filters form an "or" statement
 * by specifying another option, 'op=name:and', the filters will form an "and" statement
 * filter values beginning with '!' look for negated matches
 * filter values may contain the wildcard character '*'

examples:

 ...?node=A&node=B&node=C
    node matches A, B, or C; but not D, E, or F
 ...?node=foo*&op=node:and&node=!foobar
    node matches 'foobaz', 'foochump', but not 'foobar'

=head1 Calls

=cut

use warnings;
use strict;

use base 'PHEDEX::Web::SQL';
use PHEDEX::Web::Util;
use PHEDEX::Web::Cache;
use PHEDEX::Core::Loader;
use PHEDEX::Core::Timing;
use PHEDEX::Web::Format;
use HTML::Entities; # for encoding XML

# TODO: When call-specific SQL is removed from PHEDEX::Web::SQL and
# something more modular is used, stop using these libraries and just
# use our base SQL class, PHEDEX::Web::SQL
use PHEDEX::Core::SQL;
#use PHEDEX::Web::SQL; # already used as a base class above...

our (%params);
%params = ( VERSION => undef,
            DBCONFIG => undef,
	    INSTANCE => undef,
	    REQUEST_URL => undef,
	    REQUEST_TIME => undef,
	    SECMOD => undef,
	    DEBUG => 0,
	    CACHE_CONFIG => undef,
	    );

# A map of API calls to data sources
our $call_data = { };

# Data source parameters
our $data_sources = { };

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = ref($proto) ? $class->SUPER::new(@_) : {};
    
    my %args = (@_);
    map {
        $self->{$_} = defined($args{$_}) ? $args{$_} : $params{$_}
    } keys %params; 

    $self->{REQUEST_TIME} ||= &mytimeofday();

    bless $self, $class;

    # Set up database connection
    my $t1 = &mytimeofday();
    $self->connectToDatabase(0);
    my $t2 = &mytimeofday();
    warn "db connection time ", sprintf('%.6f s', $t2-$t1), "\n" if $self->{DEBUG};

    $self->{CACHE} = PHEDEX::Web::Cache->new( %{$self->{CACHE_CONFIG}} );

    return $self;
}

sub AUTOLOAD
{
    my $self = shift;
    my $attr = our $AUTOLOAD;
    $attr =~ s/.*:://;
    if ( exists($params{$attr}) )
    {
	$self->{$attr} = shift if @_;
	return $self->{$attr};
    }
    my $parent = "SUPER::" . $attr;
    $self->$parent(@_);
}

sub DESTROY
{
}

sub call
{
    my ($self, $call, %args) = @_;
    no strict 'refs';
    my ($obj,$stdout);
    if (!$call) {
	$self->error("No API call provided.  Check the URL");
	return;
    }

    my ($t1,$t2,$loader,$module);
    $loader = PHEDEX::Core::Loader->new( NAMESPACE => 'PHEDEX::Web::API' );
    $module = $loader->Load($call);

    $t1 = &mytimeofday();
    &process_args(\%args);

    $obj = $self->getData($call, %args);
    if ( ! $obj )
    {
      eval {
        open (local *STDOUT,'>',\$stdout); # capture STDOUT of $call
$DB::single=1;
        $obj = $module->invoke($self, %args);
	$obj = { $call => $obj };
      };
      if ($@) {
          $self->error("Error when making call '$call':  $@");
          return;
      }
      $t2 = &mytimeofday();
      warn "api call '$call' complete in ", sprintf('%.6f s',$t2-$t1), "\n" if $self->{DEBUG};
      my $duration = 0;
      $duration = $module->duration() if $module->can('duration');
      $self->{CACHE}->set( $call, \%args, $obj, $duration ); # unless $args{nocache};
    }

#   wrap the object in a phedexData element
    $obj->{stdout} = $stdout;
    $obj->{instance} = $self->{INSTANCE};
    $obj->{request_version} = $self->{VERSION};
    $obj->{request_url} = $self->{REQUEST_URL};
    $obj->{request_call} = $call;
    $obj->{request_timestamp} = $self->{REQUEST_TIME};
    $obj->{request_date} = &formatTime($self->{REQUEST_TIME}, 'stamp');
    $obj->{call_time} = sprintf('%.5f', $t2 - $t1);
    $obj = { phedex => $obj };

    $t1 = &mytimeofday();
    if (grep $_ eq $args{format}, qw( xml json perl )) {
        &PHEDEX::Web::Format::output(*STDOUT, $args{format}, $obj);
    } else {
        $self->error("return format requested is unknown or undefined");
    }
    $t2 = &mytimeofday();
    warn "api call '$call' delivered in ", sprintf('%.6f s', $t2-$t1), "\n" if $self->{DEBUG};

    return $obj;
}

# API Calls 

=pod

=head2 blockReplicas

Return block replicas with the following structure:

  <block>
     <replica/>
     <replica/>
      ...
  </block>
   ...

where <block> represents a block of files and <replica> represents a
copy of that block at some node.  An empty response means that no
block replicas exist for the given options.

=head3 options

 block          block name, can be multiple (*)
 node           node name, can be multiple (*)
 se             storage element name, can be multiple (*)
 update_since  unix timestamp, only return replicas updated since this
                time
 create_since   unix timestamp, only return replicas created since this
                time
 complete       y or n, whether or not to require complete or incomplete
                blocks. Default is to return either

 (*) See the rules of multi-value filters above

=head3 <block> attributes

 name     block name
 id       PhEDEx block id
 files    files in block
 bytes    bytes in block
 is_open  y or n, if block is open

=head3 <replica> attributes

 node         PhEDEx node name
 node_id      PhEDEx node id
 se           storage element name
 files        files at node
 bytes        bytes of block replica at node
 complete     y or n, if complete
 time_create  unix timestamp of creation
 time_update  unix timestamp of last update

=cut

=pod

=head2 fileReplicas

Return file replicas with the following structure:

  <block>
     <file>
       <replica/>
       <replica/>
       ...
     </file>
     ...
  </block>
   ...

where <block> represents a block of files, <file> represents a file
and <replica> represents a copy of that file at some node.  <block>
and <file> will always be present if any file replicas match the given
options.  <file> elements with no <replica> children represent files
which are part of the block, butno file replicas match
the given options.  An empty response means no file replicas matched
the given options.

=head3 options

 block          block name, with '*' wildcards, can be multiple (*).  required.
 node           node name, can be multiple (*)
 se             storage element name, can be multiple (*)
 update_since  unix timestamp, only return replicas updated since this
                time
 create_since   unix timestamp, only return replicas created since this
                time
 complete       y or n. if y, return only file replicas from complete block
                replicas.  if n only return file replicas from incomplete block
                replicas.  default is to return either.
 dist_complete  y or n.  if y, return only file replicas from blocks
                where all file replicas are available at some node. if
                n, return only file replicas from blocks which have
                file replicas not available at any node.  default is
                to return either.

 (*) See the rules of multi-value filters above

=head3 <block> attributes

 name     block name
 id       PhEDEx block id
 files    files in block
 bytes    bytes in block
 is_open  y or n, if block is open

=head3 <file> attributes

 name         logical file name
 id           PhEDEx file id
 bytes        bytes in the file
 checksum     checksum of the file
 origin_node  node name of the place of origin for this file
 time_create  time that this file was born in PhEDEx

=head3 <replica> attributes
 node         PhEDEx node name
 node_id      PhEDEx node id
 se           storage element name
 time_create  unix timestamp

=cut

=pod

=head2 nodes

A simple dump of PhEDEx nodes.

=head3 options

 node     PhEDex node names to filter on, can be multiple (*)
 noempty  filter out nodes which do not host any data

 (*) See the rules of multi-value filters above

=head3 <node> attributes

 name        PhEDEx node name
 se          storage element
 kind        node type, e.g. 'Disk' or 'MSS'
 technology  node technology, e.g. 'Castor'
 id          node id

=cut

=pod

=head2 tfc

Show the TFC published to TMDB for a given node

=head3 options

  node  PhEDEx node name. Required

=head3 <lfn-to-pfn> or <pfn-to-lfn> attributes

See TFC documentation.

=cut

=pod

=head2 lfn2pfn

Translate LFNs to PFNs using the TFC published to TMDB.

=head3 options

 node          PhEDex node names, can be multiple (*), required
 lfn           Logical file name, can be multiple (*), required
 protocol      Transfer protocol, required
 destination   Destination node
 
 (*) See the rules of multi-value filters above

=head3 <mapping> attributes

 lfn          Logical file name
 pfn          Physical file name
 node         Node name
 protocol     Transfer protocol
 destination  Destination node

=cut

# Cache controls

sub refreshCache
{
    my ($self, $call) = @_;
die "are you sure you want to be here?\n"; 
    foreach my $name (@{ $call_data->{$call} }) {
	my $datasource = $data_sources->{$name}->{DATASOURCE};
	my $duration   = $data_sources->{$name}->{DURATION};
	my $data = &{$datasource}($self);
	$self->{CACHE}->set( $name, $data, $duration.' s' );
    }
}

sub getData
{
    my ($self, $name, %h) = @_;
    my ($t1,$t2,$data);

    return undef unless exists $data_sources->{$name};

    $t1 = &mytimeofday();
    $data = $self->{CACHE}->get( $name, \%h );
    return undef unless $data;
    $t2 = &mytimeofday();
    warn "got '$name' from cache in ", sprintf('%.6f s', $t2-$t1), "\n" if $self->{DEBUG};

    return $data;
}

sub getData_thisIsObsolete
{
    my ($self, $name, %h) = @_;
die "are you sure you want to be here?\n"; 

    my $datasource = $data_sources->{$name}->{DATASOURCE};
    my $duration   = $data_sources->{$name}->{DURATION};

    my $t1 = &mytimeofday();

    my $from_cache;
    my $data;
    $data = $self->{CACHE}->get( $name ) unless $h{nocache};
    if (!defined $data) {
	$data = &{$datasource}($self, %h);
	$self->{CACHE}->set( $name, $data, $duration.' s') unless $h{nocache};
	$from_cache = 0;
    } else {
	$from_cache = 1;
    }

    my $t2 = &mytimeofday();

    warn "got '$name' from ",
    ($from_cache ? 'cache' : 'DB'),
    " in ", sprintf('%.6f s', $t2-$t1), "\n" if $self->{DEBUG};

    return wantarray ? ($data, $from_cache) : $data;
}


# Returns the cache duration for a API call.  If there are multiple
# data sources in an API call then the one with the lowest duration is
# returned
sub getCacheDuration
{
    my ($self, $call) = @_;
    my $min;
    foreach my $name (@{ $call_data->{$call} }) {
	my $duration   = $data_sources->{$name}->{DURATION};
	$min ||= $duration;
	$min = $duration if $duration < $min;
    }
    return $min;
}


=pod

=head2 checkAuth

enforce that the user is authenticated by a certificate. Returns the same
output as C<< getAuth >>

=cut

sub checkAuth
{
  my ($self,%args) = @_;
  die "bad call to checkAuth\n" unless $self->{SECMOD};
  my $secmod = $self->{SECMOD};
  $secmod->reqAuthnCert();
  return getAuth();
}

=pod

=head2 getAuth

Return a has of the users' authentication state. The hash contains keys for
the STATE (cert|passwd|failed), the DN, the ROLES (from sitedb) and the
NODES (from TMDB) that the user is allowed to operate on.

=cut

sub getAuth
{
  my $self = shift;
  my ($secmod,$auth);

  $secmod = $self->{SECMOD};
  $auth = {
            STATE  => $secmod->getAuthnState(),
            ROLES  => $secmod->getRoles(),
            DN     => $secmod->getDN(),
          };
  $auth->{NODES} = $self->fetch_nodes(%{$auth}, with_ids => 1);

  return $auth;
}

=pod

=head2 inject

Inject data into TMDB, returning the statistics on how many files, blocks, and datasets
were injected etc.

=cut

=pod

=head2 bounce

Return the URL OPTIONS as a hash, so you can see what the server has done
to your request.

=cut

1;
