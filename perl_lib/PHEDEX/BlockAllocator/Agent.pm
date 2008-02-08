package PHEDEX::BlockAllocator::Agent;

=head1 NAME

PHEDEX::BlockAllocator::Agent - the Block Allocator agent.

=head1 SYNOPSIS

pending...

=head1 DESCRIPTION

pending...

=head1 SEE ALSO...

L<PHEDEX::Core::Agent|PHEDEX::Core::Agent> 

=cut

use strict;
use warnings;
use base 'PHEDEX::Core::Agent', 'PHEDEX::BlockAllocator::Core';
use PHEDEX::Core::Logging;
use PHEDEX::Core::Timing;

our %params =
	(
	  MYNODE    => undef,           # my TMDB nodename
    	  DBCONFIG  => undef,		# Database configuration file
	  WAITTIME  => 300,		# Agent cycle time
	  DUMMY     => 0,		# Dummy the updates
	  ONCE      => 0,		# Quit after one run

	  BLOCK_LIMIT => 5000,		# Number of blocks to process at once (memory safeguard)

	 VERBOSE	=> 0,
	 DEBUG		=> 0,
	 TERSE		=> 0
	);

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $self = $class->SUPER::new(%params,@_);

  bless $self, $class;
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
  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods
  my $parent = "SUPER::" . $attr;
  $self->$parent(@_);
}

# Update statistics.
sub idle
{
  my ($self, @pending) = @_;
  my $dbh = undef;

  my $t0 = time();

  eval
  {
    $dbh = &connectToDatabase ($self);
    my $now = &mytimeofday ();

        my @stats1 = $self->subscriptions();
        my @stats2 = $self->allocate();
        my @stats3 = $self->blockDestinations();
        $dbh->commit();
        if (grep $_->[1] != 0, @stats1, @stats2, @stats3) {
            $self->printStats('allocation stats', @stats1, @stats2, @stats3);
        } else {
            &logmsg('nothing to do');
        }
    };
    do { chomp ($@); &alert ("database error: $@");
         eval { $dbh->rollback() } if $dbh; } if $@;

    # Disconnect from the database
    &disconnectFromDatabase ($self, $dbh);

    # Have a nap.
    $self->doStop() if $self->{ONCE};
    $self->nap ($self->{WAITTIME});
}

sub IsInvalid
{
  my $self = shift;
  my $errors = $self->SUPER::isInvalid
                (
                  REQUIRED => [ qw / MYNODE DROPDIR DBCONFIG / ],
                );
#  if ( defined($self->{BLOCK_LIMIT}) && $self->{BLOCK_LIMIT} < 1000 )
#  {
#    $errors++;
#    print __PACKAGE__,": BLOCK_LIMIT < 1000 is nuts, forget it...\n";
#  }
  return $errors;
}

1;
