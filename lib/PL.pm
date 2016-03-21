package PL;
use strict;
use warnings;
use Exporter 'import';
use Logger;
$Logger::Called_Depth++; #all log api have called 'eval'
our @EXPORT_OK = qw( get_logger );

my $logger;

sub new {
    my $package = shift;
    $logger = get_logger();
    bless {
        #logger => get_logger(),
        @_,
    }, ref $package || $package;
}

sub get_logger {
    my $package = shift || __PACKAGE__;
    Logger->is_init ? Logger->new : (die "Please init Logger module before use $package!");
}

sub trace {
    my $self = shift;
    eval {
        $logger->trace(@_);
    };
    if ($@) {
        print "Failed to write 'trace' log: [@_], error: $@";
    }
}

my ($last_debug_msg, $last_debug_reminder);
sub debug {
    my $self = shift;
    my $need_debug = 1;
    if ($last_debug_msg) {
        my $cur_debug_msg = join('',@_);
        if ($last_debug_msg eq $cur_debug_msg) {
            unless( $last_debug_reminder ) {
                eval {
                    $logger->debug("Duplicate with last log lines...");
                };
                if ($@) {
                    print "Failed to write 'debug' log: [Duplicate with last log lines...], error: $@";
                }
            }
            $need_debug = 0;
            $last_debug_reminder = 1;
        }
        else {
            $last_debug_msg = $cur_debug_msg;
            $last_debug_reminder = 0;
        }
    }
    else {
        $last_debug_msg = join('',@_);
    }
    if ($need_debug) {
        eval {
            $logger->debug(@_);
        };
        if ($@) {
            print "Failed to write 'debug' log: [@_], error: $@";
        }
    }
}

sub info  {
    my $self = shift;
    eval {
        $logger->info(@_);
    };
    if ($@) {
        print "Failed to write 'info' log: [@_], error: $@";
    }
}

sub warn  {
    my $self = shift;
    eval {
        $logger->warn(@_);
    };
    if ($@) {
        print "Failed to write 'warn' log: [@_], error: $@";
    }
    else {
        print STDERR $logger->{history}->[-1] if $logger->{path};
    }
}

sub error {
    my $self = shift;
    eval {
        $logger->error(@_);
    };
    if ($@) {
        print "Failed to write 'error' log: [@_], error: $@";
    }
    else {
        print STDERR $logger->{history}->[-1] if $logger->{path};
    }
}

sub fatal {
    my $self = shift;
    eval {
        $logger->fatal(@_);
    };
    if ($@) {
        print "Failed to write 'fatal' log: [@_], error: $@";
    }
    die "Fatal error happend, exit!";
}



1;
