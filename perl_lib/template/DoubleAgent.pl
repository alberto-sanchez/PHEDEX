#! /usr/bin/env perl
use strict;

#
# This is a template agent. All the complexity of the agent behaviour should
# be implemented in the agent's modules, so this main program should be very
# simple. Command-line arguments are processed (minimally), the agent is
# started, and the "process" method is called. That's it.
#
# The arguments are not validated in this main program. The agent is expected
# to validate itself in the "isInvalid" method. See template/Agent.pm for
# details.
#
# Note also that any unused arguments are passed to the constructor, as well
# as the processed/recognised arguments. This allows you to pass arbitrary
# arguments on the command line, overriding anything that you hadn't foreseen
# the need to provide a hook for. The processed arguments provide standard
# handling, especially useful for historically-named arguments which are
# represented by hash-keys with different names.
#
# To prevent passing arguments to the GetOptions routine, use a '--' on the
# command-line. Strings following that will be ignored by GetOptions, and will
# remain in @ARGS. So you can pass the same argument in more than one way:
#
# ./Agent.pl --MYNODE myhost --log /path/to/log
#
# or
#
# ./Agent.pl -- NODE myhost LOGFILE /path/to/log
#
# This is particulrly useful for passing things like WAITTIME, to reduce the
# agent sleep-time during debugging cycles.
#

##H template agent
##H
##H Usage:
##H   Agent.pl args, where args are up to you!
##H
##H Certain arguments are obligatory, you'll discover that if you run
##H the agent and don't define them. They aren't listed here because that
##H would couple this help file to the internals of PHEDEX::Core::Agent,
##H and I don't want to do that. Specify them on the command-line as 
##H follows:
##H
##H Agent.pl -- OPTION1 value1 OPTION2 value2
##H ...with no leading dashes before the options.
##H
##H E.g:
##H  Agent.pl -- MYNODE asdf DBCONFIG fds DROPDIR a/ NODAEMON 1 WAITTIME 2
##H

######################################################################
my ($agentset,@agents,$agent,$config,%h,%m,%args);
my ($Agent,$Config);
use Getopt::Long;
use PHEDEX::Core::Help;
use PHEDEX::Core::Config;
use POE;
#use template::Agent;

&GetOptions (
             "state=s"   => \$args{DROPDIR},
             "log=s"     => \$args{LOGFILE},
             "db=s"      => \$args{DBCONFIG},
             "config=s"  => \$config,
             "node=s"    => \$args{MYNODE},
	     "help|h"    => sub { &usage() },
	     "agent=s@"  => \@agents,
	     );
$Config = PHEDEX::Core::Config->new( PARANOID => 1 );
$Config->readConfig( $config );

$args{NODAEMON} = 1;
foreach $agent ( @agents )
{
  print "Create agent \"$agent\"\n";
  $Agent = $Config->select_agents( $agent );

# Paranoia!
  if ( $agent ne $Agent->LABEL )
  {
    die "given \"$agent\", but found \"",$Agent->LABEL,"\"\n";
  }

  my $module = $Agent->PROGRAM;
  print "$agent is in $module\n";
  if ( !exists($m{$module}) )
  {
    print "Attempt to load $module\n";
    eval("use $module");
    do { chomp ($@); die "Failed to load module $module: $@\n" } if $@;
    $m{$module}++;
  }
  my %a = %args;
  $a{DROPDIR} .= '/' . $agent;
  $a{ME} = $agent;
  my $opts = $Agent->OPTIONS;
  map { $a{$_} = $opts->{$_} } keys %{$opts};
$DB::single=1;
  $h{$agent} = eval("new $module(%a,@ARGV)");
  do { chomp ($@); die "Failed to create agent $module: $@\n" } if $@;
}

#my $agent = new template::Agent(%args,@ARGV);
#$agent->process();
POE::Kernel->run();
print "The POE kernel run has ended, now I shoot myself\n";
exit 0;
