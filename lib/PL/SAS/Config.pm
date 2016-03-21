package PL::SAS::Config;
use strict;
use warnings;
use Data::Dumper;
use Scalar::Util qw( weaken );
use File::stat;
use POE qw( Wheel );
use XML::Simple qw(XMLin);
use PL;

our @ISA = qw(PL POE::Wheel);

our $VERSION = eval '0.0001';

use constant {
    SELF_CONFIG                     => 0,
    SELF_CONF_LAST_MODIFIED         => 1,
    SELF_CONF_RESULT                => 2,
    SELF_EVENT_ERROR                => 3,
    SELF_EVENT_CHANGE               => 4,
    SELF_EVENT_DONE                 => 5,
    SELF_UNIQUE_ID                  => 6,
    SELF_STATE_MONITOR_CONFIG       => 7,
    SELF_STATE_LOAD_CONFIG          => 8, #emit by user->put
    
    MONITOR_CONF_INTERVAL           => 1,
    CONF_XSD                        => File::Spec->catfile('conf', 'SAS.xsd'),
};

sub new {
    my ( $class, %option ) = @_;
    die "wheels no longer require a kernel reference as their first parameter"
        if (@_ && (ref($_[0]) eq 'POE::Kernel'));
    die "$class requires a working Kernel"
        unless defined $poe_kernel;
    die "ErrorEvent is required!" #it can be optional
        unless defined $option{ErrorEvent};
    die "DoneEvent is required!"
        unless defined $option{DoneEvent};
    die "ChangeEvent is required!"
        unless defined $option{ChangeEvent};
        
    my $config = $option{Config};
    die "Config '$config' cannot be found!"
        unless -e $config;

    my $self = bless [
        $config,                         #SELF_CONFIG
        undef,                           #SELF_CONF_LAST_MODIFIED
        {},                              #SELF_CONF_RESULT
        $option{ErrorEvent},             #SELF_EVENT_ERROR
        $option{ChangeEvent},            #SELF_EVENT_CHANGE
        $option{DoneEvent},              #SELF_EVENT_DONE
        POE::Wheel::allocate_wheel_id(), #SELF_UNIQUE_ID
        'monitor_config',                #SELF_STATE_MONITOR_CONFIG
        'load_config',                   #SELF_STATE_LOAD_CONFIG
    ], (ref $class || $class);
    $self->_define_self_state;
    return $self;
}

sub monitor {
    my ($self, $xml_doc) = @_;
    $poe_kernel->yield( $self->[SELF_STATE_MONITOR_CONFIG] );
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
        elsif ($name eq 'ChangeEvent') {
            if (defined $event) {
                $self->[SELF_EVENT_CHANGE] = $event;
            }
            else {
                die "ChangeEvent requires an event name, ignoring undef";
            }
        }
        elsif ($name eq 'DoneEvent') {
            if (defined $event) {
                $self->[SELF_EVENT_DONE] = $event;
            }
            else {
                die "DoneEvent requires an event name, ignoring undef";
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
    my ($self, $xml_doc, $last_mtime) = @_;
    $self->debug("user required to load config with mtime $last_mtime!");
    $poe_kernel->yield( $self->[SELF_STATE_LOAD_CONFIG], $xml_doc, $last_mtime );
}

sub _define_self_state {
    my $self = shift;
    my $self_state_prefix     = ref($self) . "(" . $self->[SELF_UNIQUE_ID] . ") ->";
    $self->[SELF_STATE_MONITOR_CONFIG]  .= $self_state_prefix;
    $self->[SELF_STATE_LOAD_CONFIG]     .= $self_state_prefix;

    my $event_change = \$self->[SELF_EVENT_CHANGE];
    my $event_done = \$self->[SELF_EVENT_DONE];
    my $event_error = \$self->[SELF_EVENT_ERROR];
    weaken($self);#it does NOT a class method, and no 'OBJECT' in @_
    $poe_kernel->state( $self->[SELF_STATE_MONITOR_CONFIG],
        sub {
            my ( $kernel, $session ) = @_[KERNEL, SESSION];
            my $last_Modified_Time;
            if( my $conf_stat = stat($self->[SELF_CONFIG]) ) {
                $last_Modified_Time = $conf_stat->mtime;
            }
            else {
                $self->error("Failed to get modify time for conf file '$self->{conf}'");
                return;
            }
            unless( $self->[SELF_CONF_LAST_MODIFIED] && $last_Modified_Time == $self->[SELF_CONF_LAST_MODIFIED] ) {
                $self->info("conf file changed, so reload config!");
                $self->[SELF_CONF_LAST_MODIFIED] = $last_Modified_Time;
                my $doc;
                eval {
                    $doc = _read_config($self->[SELF_CONFIG]);
                };
                if ($@) {
                    my $err_msg = "load config with error: $@";
                    $self->error($err_msg);
                    $kernel->yield($$event_error, $err_msg);
                    $kernel->delay( $self->[SELF_STATE_MONITOR_CONFIG], MONITOR_CONF_INTERVAL );
                }
                else {
                    $kernel->yield($$event_change, $doc, $last_Modified_Time);
                }
            }
            else {
                $self->trace("conf file not changed");
                $kernel->delay( $self->[SELF_STATE_MONITOR_CONFIG], MONITOR_CONF_INTERVAL );
            }
        }
    );
    $poe_kernel->state( $self->[SELF_STATE_LOAD_CONFIG],
        sub {
            my ( $kernel, $session, $xml_doc, $last_mtime ) = @_[KERNEL, SESSION, ARG0, ARG1];
            $self->[SELF_CONF_LAST_MODIFIED] = $last_mtime if defined $last_mtime;
            $self->[SELF_CONF_RESULT] = {};
            $self->debug("load all configurations: services, commands!");
            my @results = $xml_doc->findnodes( '/c:SAS/c:Global/c:Commands' );
            my $commands = $results[0];
            foreach my $cmd ($commands->findnodes( './c:cmd' )) {
                my @results = $cmd->findnodes( './c:para' );
                my $para = $results[0];
                $self->add_cmd( $cmd, $commands->findnodes('./@*'), $para ? $para->findnodes( './@*' ) : () );
            }
            @results = $xml_doc->findnodes( '/c:SAS/c:Global/c:Services' );
            my $services = $results[0];
            foreach my $svc ($services->findnodes( './c:svc' )) {
                my @results = $svc->findnodes( './c:para' );
                my $para = $results[0];
                $self->add_svc( $svc, $para ? $para->findnodes( './@*' ) : ());
            }
            foreach my $prj ($xml_doc->findnodes( '/c:SAS/c:Project' )) {
                my ($prj_name, $prj_conf) = ($prj->getAttribute('name'), $prj->getAttribute('conf'));
                $self->debug("Travel project: '$prj_name'");
                foreach my $register ($prj->findnodes( './c:Register' )) {
                    my $type = $register->getAttribute('type');
                    if ($type eq 'cmd') {
                        $self->debug("Got a cmd for project: '$prj_name'");
                        $self->register_cmd($register, $prj_name, $prj_conf);
                    }
                    elsif ($type eq 'svc') {
                        $self->debug("Got a svc for project: '$prj_name'");
                        $self->register_svc($register, $prj_name, $prj_conf);
                    }
                    else {
                        $self->error("Unsupport register type '$type'!");
                    }
                }
            }
            $kernel->yield($$event_done, $self->[SELF_CONF_RESULT]);
        }
    );
}

sub add_cmd {
    my ($self, $cmd, @attrs) = @_;
    my ($name, $type, $path, $enable) = ($cmd->getAttribute('name'), $cmd->getAttribute('type'), $cmd->getAttribute('path'), $cmd->getAttribute('enable'));
    $self->debug("Add global command: '$name', enable='$enable', path='$path'");
    $self->[SELF_CONF_RESULT]->{commands}->{$name}->{project} = {};
    $self->[SELF_CONF_RESULT]->{commands}->{$name}->{type} = $type;
    $self->[SELF_CONF_RESULT]->{commands}->{$name}->{path} = $path;
    $self->[SELF_CONF_RESULT]->{commands}->{$name}->{enable} = $enable;
    foreach my $attr (@attrs) {
        my ($key, $val) = ($attr->nodeName, $attr->getValue);
        $self->[SELF_CONF_RESULT]->{commands}->{$name}->{args}->{$key} = $val;
        $self->debug("global cmd '$name' with attrs: " . $attr->nodeName . '='.  $attr->getValue);
    }
    $self->[SELF_CONF_RESULT]->{commands}->{$name}->{monitor} = File::Spec->catfile(delete $self->[SELF_CONF_RESULT]->{commands}->{$name}->{args}->{monitor}, "$name\.txt");
}

sub add_svc {
    my ($self, $svc, @attrs) = @_;
    my ($name, $type, $path, $enable, $interval) = ($svc->getAttribute('name'),
                                         $svc->getAttribute('type'),
                                         $svc->getAttribute('path'),
                                         $svc->getAttribute('enable'),
                                         $svc->getAttribute('interval'),
                                         );
    $self->debug("Add global service: '$name', enable='$enable', path='$path'");
    $self->[SELF_CONF_RESULT]->{services}->{$name}->{project} = {};
    $self->[SELF_CONF_RESULT]->{services}->{$name}->{type} = $type;
    $self->[SELF_CONF_RESULT]->{services}->{$name}->{path} = $path;
    $self->[SELF_CONF_RESULT]->{services}->{$name}->{enable} = $enable;
    $self->[SELF_CONF_RESULT]->{services}->{$name}->{interval} = $interval;
    foreach my $attr (@attrs) {
        my ($key, $val) = ($attr->nodeName, $attr->getValue);
        $self->[SELF_CONF_RESULT]->{services}->{$name}->{args}->{$key} = $val;
        $self->debug("global svc '$name' with attrs: '$key'='$val'");
    }
}

sub register_cmd {
    my ($self, $cmd, $project_name, $project_conf) = @_;
    if ($project_name) {
        my ($name, $enable) = ($cmd->getAttribute('name'), $cmd->getAttribute('enable'));
        if (exists $self->[SELF_CONF_RESULT]->{commands}->{$name}) {
            $self->debug("Register command: '$name', enable='$enable' for project='$project_name'");
            $self->[SELF_CONF_RESULT]->{commands}->{$name}->{project}->{$project_name}->{enable} = $enable;
            $self->[SELF_CONF_RESULT]->{commands}->{$name}->{project}->{$project_name}->{conf} = $project_conf;
            if ($cmd->hasChildNodes) {
                my $xml_str = '<args>';
                $xml_str .= $_->toString for $cmd->childNodes;
                $xml_str .= '</args>';
                my $args = XMLin($xml_str);
                $self->debug("Register cmd $xml_str as args: " . Dumper($args));
                $self->[SELF_CONF_RESULT]->{commands}->{$name}->{project}->{$project_name}->{args} = $args;
            }
        }
        else {
            $self->error("Register command failed: no global command '$name' for project='$project_name'");
        }
    }
}

sub register_svc {
    my ($self, $svc, $project_name, $project_conf) = @_;
    if ($project_name) {
        my ($name, $enable) = ($svc->getAttribute('name'), $svc->getAttribute('enable'));
        if (exists $self->[SELF_CONF_RESULT]->{services}->{$name}) {
            $self->debug("Register service: '$name', enable='$enable' for project='$project_name'");
            $self->[SELF_CONF_RESULT]->{services}->{$name}->{project}->{$project_name}->{enable} = $enable;
            $self->[SELF_CONF_RESULT]->{services}->{$name}->{project}->{$project_name}->{conf} = $project_conf;
            if ($svc->hasChildNodes) {
                my $xml_str = '<args>';
                $xml_str .= $_->toString for $svc->childNodes;
                $xml_str .= '</args>';
                my $args = XMLin($xml_str);
                $self->debug("Register svc $xml_str as args: " . Dumper($args));
                $self->[SELF_CONF_RESULT]->{services}->{$name}->{project}->{$project_name}->{args} = $args;
            }
        }
        else {
            $self->error("Register service failed: no global service '$name' for project='$project_name'");
        }
    }
}

sub _read_config {
    my ($xml_file, $xsd_file) = @_;
    $xsd_file ||= CONF_XSD;
    my $doc;
    eval {
        my $schema = XML::LibXML::Schema->new( location => $xsd_file );
        my $parser = XML::LibXML->new;
        $doc    = $parser->parse_file($xml_file);
        $schema->validate($doc);
    };
    die "read xml with error: $@" if $@;
    return $doc;
}

sub DESTROY {
    my $self = shift;
    foreach ( SELF_STATE_MONITOR_CONFIG..SELF_STATE_LOAD_CONFIG ) {
        if ($self->[$_]) {
            $poe_kernel->state($self->[$_]);
            undef $self->[$_];
        }
    }
    &POE::Wheel::free_wheel_id($self->[SELF_UNIQUE_ID]);
    $self->info( "Wheel for SAS Services destroyed!" );
}

1;



