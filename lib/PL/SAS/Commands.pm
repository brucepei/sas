package PL::SAS::Commands;
use strict;
use warnings;
use Data::Dumper;
use Scalar::Util qw( weaken );
use POE qw( Wheel );
use PL;

our @ISA = qw(PL POE::Wheel);

our $VERSION = eval '0.0001';

use constant {
    SELF_COMMANDS                   => 0,
    SELF_RUNNING_COMMAND            => 1,
    SELF_EVENT_ERROR                => 2,
    SELF_EVENT_RUN_CMD              => 3,
    SELF_UNIQUE_ID                  => 4,
    SELF_STATE_MONITOR_COMMAND      => 5,
    SELF_STATE_PREPARE_COMMAND      => 6,
    SELF_STATE_COMPLETE_COMMAND     => 7, #emit by user->put
    
    MONITOR_CMD_INTERVAL            => 1,
};

sub new {
    my ( $class, %option ) = @_;
    die "wheels no longer require a kernel reference as their first parameter"
        if (@_ && (ref($_[0]) eq 'POE::Kernel'));
    die "$class requires a working Kernel"
        unless defined $poe_kernel;
    die "ErrorEvent is required!" #it can be optional
        unless defined $option{ErrorEvent};
    die "RunCmdEvent is required!"
        unless defined $option{RunCmdEvent};

    my $commands = $option{Commands};
    die "Commands must be an HASH reference"
        unless ref($commands) eq "HASH";

    my $self = bless [
        $commands,                       #SELF_COMMANDS
        undef,                           #SELF_RUNNING_COMMAND
        $option{ErrorEvent},             #SELF_EVENT_ERROR
        $option{RunCmdEvent},            #SELF_EVENT_RUN_CMD
        POE::Wheel::allocate_wheel_id(), #SELF_UNIQUE_ID
        'monitor_command',               #SELF_STATE_MONITOR_COMMAND
        'prepare_command',               #SELF_STATE_PREPARE_COMMAND
        'complete_command',              #SELF_STATE_COMPLETE_COMMAND
    ], (ref $class || $class);
    $self->_define_self_state;
    $poe_kernel->yield( $self->[SELF_STATE_MONITOR_COMMAND] );
    return $self;
}

sub event {
    my $self = shift;
    push(@_, undef) if (scalar(@_) & 1);
    while (@_) {
        my ($name, $event) = splice(@_, 0, 2);
        if ($name eq 'ErrorEvent') {
            if (defined $event) {
                $self->[SELF_EVENT_ERROR] = $event;
            }
            else {
                die "ErrorEvent requires an event name, ignoring undef";
            }
        }
        elsif ($name eq 'RunCmdEvent') {
            if (defined $event) {
                $self->[SELF_EVENT_RUN_CMD] = $event;
            }
            else {
                die "RunCmdEvent requires an event name, ignoring undef";
            }
        }
        else {
            die "ignoring unknown event name '$name'";
        }
    }
}

sub ID {
    return $_[0]->[SELF_UNIQUE_ID];
}

sub put {
    my ($self, $cmd_name) = @_;
    $poe_kernel->yield( $self->[SELF_STATE_COMPLETE_COMMAND], $cmd_name );
}

sub _define_self_state {
    my $self = shift;
    my $self_state_prefix     = ref($self) . "(" . $self->[SELF_UNIQUE_ID] . ") ->";
    $self->[SELF_STATE_MONITOR_COMMAND]  .= $self_state_prefix;
    $self->[SELF_STATE_PREPARE_COMMAND]  .= $self_state_prefix;
    $self->[SELF_STATE_COMPLETE_COMMAND] .= $self_state_prefix;

    my $event_run_cmd = \$self->[SELF_EVENT_RUN_CMD];
    my $event_error = \$self->[SELF_EVENT_ERROR];
    weaken($self);#it does NOT a class method, and no 'OBJECT' in @_
    $poe_kernel->state( $self->[SELF_STATE_MONITOR_COMMAND],
        sub {
            my ( $kernel, $session ) = @_[KERNEL, SESSION];
            my $run_command;
            while (my ($cmd_name, $info) = each(%{$self->[SELF_COMMANDS]})) {
                #$self->debug("check '$command' if exists $info->{path}");
                if (-e $info->{monitor}) {
                    $self->debug("Detect command file, try to run '$cmd_name'!");
                    $run_command = $cmd_name;
                    last;
                }
            }
            if ($run_command) {
                $kernel->yield( $self->[SELF_STATE_PREPARE_COMMAND], $run_command );
            }
            $kernel->delay($self->[SELF_STATE_MONITOR_COMMAND], MONITOR_CMD_INTERVAL);
        }
    );
    $poe_kernel->state( $self->[SELF_STATE_COMPLETE_COMMAND],
        sub {
            $self->debug("Command '". $self->[SELF_RUNNING_COMMAND] . "' is done, clear it!");
            undef($self->[SELF_RUNNING_COMMAND]);
        }
    );
    $poe_kernel->state( $self->[SELF_STATE_PREPARE_COMMAND],
        sub {
            my ( $kernel, $session, $cmd_name ) = @_[KERNEL, SESSION, ARG0];
            my $command = $self->[SELF_COMMANDS]->{$cmd_name};
            my ($need_clear, $need_run);
            if ($command->{enable}) {
                my $type = $command->{type};
                if( $type eq 'nop' ) {
                    $need_clear = 1;
                }
                elsif ($self->[SELF_RUNNING_COMMAND]) {
                    $self->debug("Command '". $self->[SELF_RUNNING_COMMAND]. "' is still running, so '$cmd_name' have to wait for it!");
                }
                else {
                    $need_run = 1;
                    $need_clear = 1;
                }
            }
            else {
                $need_clear = 1;
                $self->debug("cmd '$cmd_name' is disabled, so ignore it!");
            }
            if ($need_clear) {
                unlink $command->{monitor};
                if ( -e $command->{monitor} ) {
                    my $err_msg = "cannot clear cmd '$cmd_name'(delete '$command->{monitor}'), permission denied?";
                    $self->error($err_msg);
                    $kernel->yield($$event_error, $cmd_name, $err_msg);
                }
                else {
                    $self->debug("Clear cmd '$cmd_name', so delete the command file!");
                    if ($need_run) {
                        $self->[SELF_RUNNING_COMMAND] = $cmd_name;
                        $kernel->yield($$event_run_cmd, $cmd_name);
                        $self->debug("Need run cmd '$cmd_name', so emit '$$event_run_cmd'!");
                    }
                }
            }
        }
    );
}


sub DESTROY {
    my $self = shift;
    foreach ( SELF_STATE_MONITOR_COMMAND..SELF_STATE_COMPLETE_COMMAND ) {
        if ($self->[$_]) {
            $poe_kernel->state($self->[$_]);
            undef $self->[$_];
        }
    }
    &POE::Wheel::free_wheel_id($self->[SELF_UNIQUE_ID]);
    $self->info( "Wheel for SAS Commmands destroyed!" );
}

1;
