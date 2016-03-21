package PL::SAS::Services;
use strict;
use warnings;
use Data::Dumper;
use Scalar::Util qw( weaken );
use POE qw( Wheel );
use PL;

our @ISA = qw(PL POE::Wheel);

our $VERSION = eval '0.0001';

use constant {
    SELF_SERVICES                   => 0,
    SELF_SVC_QUEUE                  => 1,
    SELF_EVENT_ERROR                => 2,
    SELF_EVENT_RUN_SVC              => 3,
    SELF_UNIQUE_ID                  => 4,
    SELF_STATE_MONITOR_SERVICE      => 5,
    SELF_STATE_QUEUE_SERVICE        => 6,
    SELF_STATE_CLASSIFY_SERVICE     => 7,
    SELF_STATE_COMPLETE_SERVICE     => 8, #emit by user->put
    
    MONITOR_SVC_INTERVAL            => 1,
};

sub new {
    my ( $class, %option ) = @_;
    die "wheels no longer require a kernel reference as their first parameter"
        if (@_ && (ref($_[0]) eq 'POE::Kernel'));
    die "$class requires a working Kernel"
        unless defined $poe_kernel;
    die "ErrorEvent is required!" #it can be optional
        unless defined $option{ErrorEvent};
    die "RunSvcEvent is required!"
        unless defined $option{RunSvcEvent};

    my $services = $option{Services};
    die "Services must be an HASH reference"
        unless ref($services) eq "HASH";

    my $self = bless [
        $services,                       #SELF_SERVICES
        [],                              #SELF_SVC_QUEUE
        $option{ErrorEvent},             #SELF_EVENT_ERROR
        $option{RunSvcEvent},            #SELF_EVENT_RUN_SVC
        POE::Wheel::allocate_wheel_id(), #SELF_UNIQUE_ID
        'monitor_service',               #SELF_STATE_MONITOR_SERVICE
        'queue_service',                 #SELF_STATE_QUEUE_SERVICE
        'classify_service',              #SELF_STATE_CLASSIFY_SERVICE
        'complete_service',              #SELF_STATE_COMPLETE_SERVICE
    ], (ref $class || $class);
    $self->_define_self_state;
    $poe_kernel->yield( $self->[SELF_STATE_CLASSIFY_SERVICE] );
    $poe_kernel->yield( $self->[SELF_STATE_MONITOR_SERVICE] );
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
        elsif ($name eq 'RunSvcEvent') {
            if (defined $event) {
                $self->[SELF_EVENT_RUN_SVC] = $event;
            }
            else {
                die "RunSvcEvent requires an event name, ignoring undef";
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
    my ($self, $svc_name) = @_;
    $poe_kernel->yield( $self->[SELF_STATE_COMPLETE_SERVICE], $svc_name );
}

sub _define_self_state {
    my $self = shift;
    my $self_state_prefix     = ref($self) . "(" . $self->[SELF_UNIQUE_ID] . ") ->";
    $self->[SELF_STATE_MONITOR_SERVICE]  .= $self_state_prefix;
    $self->[SELF_STATE_QUEUE_SERVICE]  .= $self_state_prefix;
    $self->[SELF_STATE_CLASSIFY_SERVICE] .= $self_state_prefix;
    $self->[SELF_STATE_COMPLETE_SERVICE] .= $self_state_prefix;

    my $event_run_svc = \$self->[SELF_EVENT_RUN_SVC];
    my $event_error = \$self->[SELF_EVENT_ERROR];
    weaken($self);#it does NOT a class method, and no 'OBJECT' in @_
    $poe_kernel->state( $self->[SELF_STATE_MONITOR_SERVICE],
        sub {
            my ( $kernel, $session ) = @_[KERNEL, SESSION];
            if (ref $self->[SELF_SVC_QUEUE] && @{$self->[SELF_SVC_QUEUE]}) {
                my $svc_name = shift @{$self->[SELF_SVC_QUEUE]};
                $self->debug("queue out svc, ready to run '$svc_name'");
                my $svc = $self->[SELF_SERVICES]->{$svc_name};
                if ($svc->{enable}) {
                    $kernel->yield($$event_run_svc, $svc_name);
                }
                else {
                    $self->debug("svc '$svc_name' is disabled, so ignore it!");
                }
            }
            $kernel->delay($self->[SELF_STATE_MONITOR_SERVICE], MONITOR_SVC_INTERVAL);
        }
    );
    $poe_kernel->state( $self->[SELF_STATE_QUEUE_SERVICE],
        sub {
            my ( $kernel, $session, $svc_name ) = @_[KERNEL, SESSION, ARG0];
            $self->debug("Push svc '$svc_name' into queue!");
            push @{$self->[SELF_SVC_QUEUE]}, $svc_name;
        }
    );
    $poe_kernel->state( $self->[SELF_STATE_CLASSIFY_SERVICE],
        sub {
            my ( $kernel, $session, $cmd_name ) = @_[KERNEL, SESSION, ARG0];
            foreach my $svc_name (keys %{$self->[SELF_SERVICES]}) {
                my $svc = $self->[SELF_SERVICES]->{$svc_name};
                if (defined $svc->{interval}) {
                    $self->debug("service '$svc_name' defined interval $svc->{interval}, so queue it!");
                    $kernel->yield($self->[SELF_STATE_QUEUE_SERVICE] => $svc_name);
                }
                else {
                    $self->debug("service '$svc_name' not defined interval $svc->{interval}, so ignore it!");
                }
            }
        }
    );
    $poe_kernel->state( $self->[SELF_STATE_COMPLETE_SERVICE],
        sub {
            my ( $kernel, $session, $svc_name ) = @_[KERNEL, SESSION, ARG0];
            my $svc = $self->[SELF_SERVICES]->{$svc_name};
            if( $svc->{interval} ) {
                $self->debug("svc '$svc_name' done, and need to delay $svc->{interval} to queue svc again!");
                $kernel->delay_set($self->[SELF_STATE_QUEUE_SERVICE] => $svc->{interval}, $svc_name);
            }
        }
    );
}


sub DESTROY {
    my $self = shift;
    foreach ( SELF_STATE_MONITOR_SERVICE..SELF_STATE_CLASSIFY_SERVICE ) {
        if ($self->[$_]) {
            $poe_kernel->state($self->[$_]);
            undef $self->[$_];
        }
    }
    &POE::Wheel::free_wheel_id($self->[SELF_UNIQUE_ID]);
    $self->info( "Wheel for SAS Commmands destroyed!" );
}

1;
