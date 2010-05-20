package PHEDEX::Namespace::posix;
use strict;
use warnings;
no strict 'refs';
use base 'PHEDEX::Namespace::Common'; # All interface packages must do this
use PHEDEX::Core::Loader;
use Data::Dumper;
use Getopt::Long;

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %h = @_;
  my ($help,%params,%options);

# Params and options are interface-specific. If you need to set an environment
# variable or something, that parameter should be declared in %params, accepted
# as an input argument in %options, and used where necessary in the package.

  %params = (
		VERBOSE => 0,
		DEBUG   => 0,
                CACHE    => undef,
                NOCACHE  => 1,
            );
  %options = (
		'help'		=> \$help,
		'verbose!'	=> \$params{VERBOSE},
		'debug+'	=> \$params{DEBUG},
                'nocache'       => \$params{NOCACHE},
             );
  GetOptions(%options);
  my $self = \%params;
  bless($self, $class);
  $self->SUPER::_init( NAMESPACE => __PACKAGE__ );
  map { $self->{$_} = $h{$_} } keys %h;
  if (exists($self->{AGENT}->{NOCACHE})) { $self->{NOCACHE} = $self->{AGENT}->{NOCACHE}; }

# This is where the interface-specific modules are loaded. The modules are
# passed a reference to this object when they are loaded/created, so they
# can pick out the parameters you define above.

  $self->SUPER::_init_commands;
  print Dumper($self) if $self->{DEBUG};
  $self->Help if $help;
  return $self;
}

sub Help
{
# This function should describe any module-specific parameters, but the rest of
# it should remain unaltered.

  my $self = shift;
  print "\n Usage for ",__PACKAGE__,"\n";
  print <<EOF;

 This module takes the standard options:
 --nocache to disable the caching mechanism
 --help, --(no)debug, --(no)verbose

 Commands known to this module:
EOF

  $self->SUPER::_help();
}

1;