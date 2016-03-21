package PL::POE::Wheel::Process;
use warnings;
use strict;
use Data::Dumper;
use Errno qw(ESRCH EPERM);
use Scalar::Util qw( weaken );
use POE qw( Wheel );
use PL;

our @ISA = qw(PL POE::Wheel);

our $VERSION = eval '0.0002';

use constant {
    SELF_PROGRAM             => 0,
    SELF_PROGRAM_ARGS        => 1,
    SELF_PROGRAM_TIMEOUT     => 2,
    SELF_PROGRAM_START       => 3,
    SELF_PROGRAM_EXIT_CODE   => 4,
    SELF_PROGRAM_EXIT_ARGS   => 5,
    SELF_EVENT_ERROR         => 6,
    SELF_EVENT_EXIT          => 7,
    SELF_EVENT_TIMEOUT       => 8,
    SELF_UNIQUE_ID           => 9,
    SELF_PROCESS_OBJ         => 10,
    SELF_PID                 => 11,
    SELF_STATE_TASK_CHECK    => 12,
    
    IS_WIN32                 => $^O eq 'MSWin32',
    #Win32 Constant
    STILL_ACTIVE             => 259,
    NORMAL_PRIORITY_CLASS    => 32,
    CREATE_NEW_CONSOLE       => 16,
};

if(IS_WIN32) {
    require Win32::Process;
    require Win32;
}
else {
    require POE::Wheel::Run;
}

sub new {
    my ( $class, %option ) = @_;
    die "wheels no longer require a kernel reference as their first parameter"
        if (@_ && (ref($_[0]) eq 'POE::Kernel'));
    die "$class requires a working Kernel"
        unless defined $poe_kernel;
    #die "ErrorEvent is required!" #it can be optional
    #    unless defined $option{ErrorEvent};
    die "ExitEvent is required!"
        unless defined $option{ExitEvent};
    die "TimeoutEvent is required when set ProgramTimeout!"
        if $option{ProgramTimeout} && !defined $option{TimeoutEvent};

    my $program = $option{Program};
    die "$class needs a Program parameter"
        unless defined $program;
    die "Program cannot be found!"
        unless -e $program;

    my $prog_args = $option{ProgramArgs};
    $prog_args = [] unless defined $prog_args;
    die "ProgramArgs must be an ARRAY reference"
        unless ref($prog_args) eq "ARRAY";

    my $prog_sig_args = $option{ExitArgs};
    $prog_sig_args = [] unless defined $prog_sig_args;
    die "ExitArgs must be an ARRAY reference"
        unless ref($prog_sig_args) eq "ARRAY"; 
    
    my $prog_timeout = $option{ProgramTimeout};
    $prog_timeout = 0 unless defined $prog_timeout;
    die "ProgramTimeout must be an integer"
        unless $prog_timeout =~ /^\d+$/;
    
    my $self = bless [
        $program,                        #SELF_PROGRAM
        $prog_args,                      #SELF_PROGRAM_ARGS
        $prog_timeout,                   #SELF_PROGRAM_TIMEOUT
        undef,                           #SELF_PROGRAM_START
        undef,                           #SELF_PROGRAM_EXIT_CODE
        $prog_sig_args,                  #SELF_PROGRAM_EXIT_ARGS
        $option{ErrorEvent},             #SELF_EVENT_ERROR
        $option{ExitEvent},              #SELF_EVENT_EXIT
        $option{TimeoutEvent},           #SELF_EVENT_TIMEOUT
        POE::Wheel::allocate_wheel_id(), #SELF_UNIQUE_ID
        undef,                           #SELF_PROCESS_OBJ
        undef,                           #SELF_PID
        'task check',                    #SELF_STATE_TASK_CHECK
    ], (ref $class || $class);
    $self->_define_self_state;
    $self->_start_process;
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
        elsif ($name eq 'ExitEvent') {
            if (defined $event) {
                $self->[SELF_EVENT_EXIT] = $event;
            }
            else {
                die "ExitEvent requires an event name, ignoring undef";
            }
        }
        elsif ($name eq 'TimeoutEvent') {
            if (defined $event) {
                $self->[SELF_EVENT_TIMEOUT] = $event;
            }
            else {
                die "TimeoutEvent requires an event name, ignoring undef";
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

sub PID {
    return $_[0]->[SELF_PID];
}

sub process {
    return $_[0]->[SELF_PROCESS_OBJ];
}

sub ErrorReport{
    my $err = Win32::FormatMessage( Win32::GetLastError() );
    $err =~ s/\s+$//;
    $err;
}
    
sub _start_process {
    my ( $self, $task ) = @_;
    my $event_error = \$self->[SELF_EVENT_ERROR];
    if (IS_WIN32) {
        my $child_process;
        my $program_name = $self->[SELF_PROGRAM];
        $program_name =~ /([^\\\/\.]+)(?:\.[^\\\/\.]*)?$/;
        $program_name = $1;
        my $program_with_args = $program_name . ' ' . join(' ', @{$self->[SELF_PROGRAM_ARGS]});
        my $is_success = Win32::Process::Create(
                $child_process, $self->[SELF_PROGRAM], $program_with_args, 0,
                    NORMAL_PRIORITY_CLASS | CREATE_NEW_CONSOLE, '.' ); #'.' set cwd
        if ($is_success) {
            $self->[SELF_PID] = $child_process->GetProcessID;
            $self->[SELF_PROCESS_OBJ] = $child_process;
        }
        else {
            if( $$event_error ) {
                $poe_kernel->yield( $$event_error, ErrorReport() );
                $self->error( "Start Program '@{[ $self->[SELF_PROGRAM] ]}' failed, so yield error event '$$event_error'!" );
            }
            else {
                $self->error( "Start Program '@{[ $self->[SELF_PROGRAM] ]}' failed, and no error event defined" );
            }
            return;
        }
    }
    else {
        $self->[SELF_PROCESS_OBJ] = POE::Wheel::Run->new(
            Program      => $self->[SELF_PROGRAM],
            ProgramArgs  => $self->[SELF_PROGRAM_ARGS],
        );
        $self->[SELF_PID] = $self->[SELF_PROCESS_OBJ]->PID;
        $poe_kernel->sig_child($self->[SELF_PID], $self->[SELF_EVENT_EXIT], @{$self->[SELF_PROGRAM_EXIT_ARGS]});
    }
    $self->[SELF_PROGRAM_START] = time;
    $self->debug( "Start Process with pid " . $self->[SELF_PID] . " at " . localtime($self->[SELF_PROGRAM_START]) );

    $poe_kernel->yield( $self->[SELF_STATE_TASK_CHECK] );
}

sub _is_alive {
    my ( $self ) = @_;
    if( IS_WIN32 && $self->[SELF_PROCESS_OBJ] ) {
        my $exit_code;
        $self->[SELF_PROCESS_OBJ]->GetExitCode( $exit_code );
        if( STILL_ACTIVE == $exit_code ) {
            return 1;
        }
        else {
            $exit_code = $exit_code & 0xffffffff;
            my $sign = $exit_code >> 31;
            $self->[SELF_PROGRAM_EXIT_CODE] = $sign ? -((~$exit_code & 0xffffffff) + 1) : $exit_code;
            return 0;
        }
    }
    elsif( $self->[SELF_PID] ) {
        if( CORE::kill 0 => $self->[SELF_PID] ) {
            return 1;
        }
        elsif( defined($!) ) {
            if( $! == EPERM) {
                $self->warn( "No permission to control pid '" . $self->[SELF_PID] . "'!" );
            }
            elsif( $! == ESRCH) {
                $self->warn( "No such process!" );
            }
            else {
                $self->warn( "Unexpect error: $! when kill 0 to pid '" . $self->[SELF_PID] . "'!" );
            }
            return undef;
        }
        else {
            return 0;
        }
    }
    else {
        $self->warn( "Failed to check alive, since program '" . $self->[SELF_PROGRAM] . "' has not been started!" );
        return undef;
    }
}

sub _define_self_state {
    my $self = shift;
    my $self_state_prefix     = ref($self) . "(" . $self->[SELF_UNIQUE_ID] . ") ->";
    $self->[SELF_STATE_TASK_CHECK] .= $self_state_prefix;

    my $event_exit = \$self->[SELF_EVENT_EXIT];
    my $event_timeout = \$self->[SELF_EVENT_TIMEOUT];
    weaken($self);#it does NOT a class method, and no 'OBJECT' in @_
    $poe_kernel->state( $self->[SELF_STATE_TASK_CHECK],
        sub {
            my ( $kernel, $session ) = @_[KERNEL, SESSION];
            $self->trace( "check '" . $self->[SELF_PROGRAM] . "(" . $self->[SELF_PID] . ")' if it is alive" );
            my $status = $self->_is_alive;
            if( defined($status) ) {
                if( $status ) {
                    if( $self->[SELF_PROGRAM_TIMEOUT] && ( time - $self->[SELF_PROGRAM_START] ) > $self->[SELF_PROGRAM_TIMEOUT] ) {
                        $self->info( "Program '" . $self->[SELF_PROGRAM] . "(" . $self->[SELF_PID] . ")' has been timeout, and try to kill it!" );
                        if (IS_WIN32) {
                            $self->[SELF_PROCESS_OBJ]->Kill(-1);#it might be failed
                        }
                        else {
                            kill(9, $self->[SELF_PID]);
                        }
                        $$event_timeout && $kernel->yield( $$event_timeout, $self->[SELF_PID], @{$self->[SELF_PROGRAM_EXIT_ARGS]} );
                    }
                }
                elsif(IS_WIN32) {
                    $self->info( "'" . $self->[SELF_PROGRAM] . "(" . $self->[SELF_PID] . ")' has been done, yield '$$event_exit' event!" );
                    $kernel->yield( $$event_exit, 'CHLD', $self->[SELF_PID], $self->[SELF_PROGRAM_EXIT_CODE], @{$self->[SELF_PROGRAM_EXIT_ARGS]} );
                }
            }
            else {
                $self->warn( "'" . $self->[SELF_PROGRAM] . "(" . $self->[SELF_PID] . ")' failed to get alive status!" );
            }
            $kernel->delay( $self->[SELF_STATE_TASK_CHECK] => 1 ) if $status;
        }
    );
}


sub DESTROY {
    my $self = shift;
    foreach ( SELF_STATE_TASK_CHECK ) {
        if ($self->[$_]) {
            $poe_kernel->state($self->[$_]);
            undef $self->[$_];
        }
    }
    undef $self->[SELF_PROCESS_OBJ];
    &POE::Wheel::free_wheel_id($self->[SELF_UNIQUE_ID]);
    $self->info( "Wheel Process for '" . $self->[SELF_PROGRAM] . "(" . $self->[SELF_PID] . ")' destroyed!" );
}

1;
