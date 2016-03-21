package PL::SAS;
use strict;
use warnings;
use XML::LibXML;
use Data::Dumper;
use File::Spec;
use File::stat;
use Config;
use Storable qw(freeze thaw);
use POE;
use PL::POE::Wheel::Process;
use PL::SAS::Commands;
use PL::SAS::Services;
use PL::SAS::Config;
use PL;


use constant {
    WORKER_TYPE_CMD         => 'commands',
    WORKER_TYPE_SVC         => 'services',
    MAX_WORKER_TIMEOUT      => 600,
};

our @ISA = qw(PL);

sub new {
    my $package = shift;
    my $obj = $package->SUPER::new(@_);
    $obj->debug("construct '$package' object, and create session for it");
    POE::Session->create(
        object_states => [
            $obj => [qw(_start init_sas
                     err_cmd run_cmd
                     err_svc run_svc
                     start_sas chg_conf err_conf
                     worker_sig_child start_worker worker_timeout worker_done
                     )],
        ],
    );
    $obj;
}

sub init_sas {
    my ($kernel, $heap, $self, $xml_doc, $last_mtime) = @_[KERNEL, HEAP, OBJECT, ARG0, ARG1];
    $self->debug("Initialize SAS environment!");
    $heap->{queue_svc} = [];
    $heap->{config_wheel}->put($xml_doc, $last_mtime); #initilize config result
}

sub start_sas {
    my ($kernel, $heap, $self, $conf_result) = @_[KERNEL, HEAP, OBJECT, ARG0];
    $self->debug("Complete SAS environment, and start SAS!");
    $self->debug("config: " . Dumper($conf_result));
    $heap->{commands} = $conf_result->{commands};
    $heap->{services} = $conf_result->{services};
    $heap->{commands_wheel} = PL::SAS::Commands->new(
        Commands    => $heap->{commands},
        ErrorEvent  => 'err_cmd',
        RunCmdEvent => 'run_cmd',
    );
    $heap->{services_wheel} = PL::SAS::Services->new(
        Services    => $heap->{services},
        ErrorEvent  => 'err_svc',
        RunSvcEvent => 'run_svc',
    );
    $heap->{config_wheel}->monitor;
}

sub run_cmd {
    my ($kernel, $heap, $self, $cmd_name) = @_[KERNEL, HEAP, OBJECT, ARG0];
    my $info = $heap->{commands}->{$cmd_name};
    if ($info->{enable}) {
        $self->debug("notify worker to run cmd '$cmd_name'!");
        $kernel->yield('start_worker', WORKER_TYPE_CMD, $cmd_name);
    }
    else {
        $self->error("cmd '$cmd_name' is disabled, why I can receive it?!");
        $kernel->yield('worker_done', WORKER_TYPE_CMD, $cmd_name);
    }

}

sub err_cmd {
    my ($kernel, $self, $command, $msg) = @_[KERNEL, OBJECT, ARG0, ARG1];
    $self->error("Failed to run cmd '$command': $msg!");
}

sub run_svc {
    my ($kernel, $heap, $self, $svc_name) = @_[KERNEL, HEAP, OBJECT, ARG0];
    my $info = $heap->{services}->{$svc_name};
    if ($info->{enable}) {
        $self->debug("notify worker to run svc '$svc_name'!");
        $kernel->yield('start_worker', WORKER_TYPE_SVC, $svc_name);
    }
    else {
        $self->error("svc '$svc_name' is disabled, why I can receive it?!");
        $kernel->yield('worker_done', WORKER_TYPE_SVC, $svc_name);
    }
}

sub err_svc {
    my ($kernel, $self, $svc_name, $msg) = @_[KERNEL, OBJECT, ARG0, ARG1];
    $self->error("Failed to run svc '$svc_name': $msg!");
}

sub process_program_args {
    my ($file_type, $path, @args) = @_;
    if ($^O eq 'MSWin32') {
        process_program_args_win32($file_type, $path, @args);
    }
    else {
        process_program_args_linux($file_type, $path, @args);
    }
}

sub process_program_args_win32 {
    my ($file_type, $path, @args) = @_;
    unless (-e $path) {
        die "cannot find path '$path' for file type '$file_type'!";
    }
    my ($program, @extra_args);
    if($file_type eq 'bat') {
        $program = "c:\\windows\\system32\\cmd.exe";
        push @extra_args,  '/c', $path;
    }
    elsif($file_type eq 'perl') {
        $program = $Config{perlpath};
        push @extra_args, $path;
    }
    elsif($file_type eq 'exe') {
        $program = $path;
    }
    else {
        die "Unknown file type '$file_type' for '$path'";
    }
    unless (-e $program) {
        die "cannot find program '$program' for file type '$file_type'!";
    }
    return ($program, @extra_args, @args);
}

sub process_program_args_linux {
    my ($file_type, $path, @args) = @_;
    $path =~ s/\\/\//g;
    unless (-e $path) {
        die "cannot find path '$path' for file type '$file_type'!";
    }
    my ($program, @extra_args);
    if ($file_type eq 'shell') {
        $program = '/bin/bash';
        push @extra_args, $path;
    }
    elsif($file_type eq 'perl') {
        $program = $Config{perlpath};
        push @extra_args, $path;
    }
    elsif($file_type eq 'exe') {
        $program = $path;
    }
    else {
        die "Unknown file type '$file_type' for '$path'";
    }
    unless (-e $program) {
        die "cannot find program '$program' for file type '$file_type'!";
    }
    return ($program, @extra_args, @args);
}

sub start_worker {
    my ($kernel, $self, $heap, $worker_type, $worker_name) = @_[KERNEL, OBJECT, HEAP, ARG0..$#_];
    my $worker = $heap->{$worker_type}->{$worker_name};
    my ($program, @args);
    eval {
        ($program, @args) = process_program_args($worker->{type}, $worker->{path});
    };
    if ($@) {
        $self->error("$worker_type worker '$worker_name' arguments error: $@!");
        $kernel->yield('worker_done', $worker_type, $worker_name);
        return;
    }
    my $project = {};
    foreach my $prj_name (keys %{$worker->{project}}) {
        my $prj = $worker->{project}->{$prj_name};
        if ($prj->{enable}) {
            $project->{$prj_name} = $prj;
        }
        else {
            $self->debug("Ignore disabled project '' for $worker_type worker '$worker_name'!");
        }
    }
    my $args_str = freeze({args => $worker->{args}, project => $project});
    $args_str =~s/./sprintf('%02x',ord($&))/esg;
    $self->debug( "line args: $args_str!" );
    my $process = PL::POE::Wheel::Process->new(
        Program        => $program,
        ProgramArgs    => [@args, $args_str],
        ProgramTimeout => MAX_WORKER_TIMEOUT,
        TimeoutEvent   => 'worker_timeout',
        ExitArgs       => [$worker_type, $worker_name],
        ExitEvent      => 'worker_sig_child',
    );
    my $pid = $process->PID;
    if ($pid) {
        $self->debug("$worker_type worker '$worker_name'($program @args) run with PID $pid!");
    }
    else {
        $self->error("Failed to start $worker_type worker '$worker_name'($program @args)");
        $kernel->yield('worker_done', $worker_type, $worker_name);
        return;
    }
    $heap->{run_pid}->{$pid} = $process;
}

sub worker_timeout {
    my ($kernel, $heap, $self, $pid, $worker_type, $worker_name) = @_[KERNEL, HEAP, OBJECT, ARG0..$#_];
    $self->debug("worker $worker_type '$worker_name'($pid) timeout!");
}

sub worker_sig_child {
    my ($kernel, $self, $heap, $sig, $pid, $exit_val, $worker_type, $worker_name) = @_[KERNEL, OBJECT, HEAP, ARG0..$#_];
    delete $heap->{run_pid}->{$pid};
    $self->debug("capture $worker_type '$worker_name'(pid: $pid) signal $sig, exit value: $exit_val!");
    $kernel->yield('worker_done', $worker_type, $worker_name);
}

sub worker_done {
    my ($heap, $self, $worker_type, $worker_name) = @_[HEAP, OBJECT, ARG0, ARG1];
    $self->debug("$worker_type worker '$worker_name' done, notify its wheel!");
    if ($worker_type eq WORKER_TYPE_SVC) {
        $heap->{services_wheel}->put($worker_name);
    }
    elsif($worker_type eq WORKER_TYPE_CMD) {
        $heap->{commands_wheel}->put($worker_name);
    }
}

sub _start {
    my ($kernel, $heap, $self) = @_[KERNEL, HEAP, OBJECT];
    my $class = ref $self;
    $kernel->alias_set($self->{alias}) if $self->{alias};
    $self->debug("$class session '$self->{alias}' started, prepare before controller really start");

    my ($path, $conf_file_name);
    if( $self->{conf} ) {
        $self->debug("start controller '$class' with configuration '$self->{conf}'");
        $path = $self->{conf};
        $path =~ s/[\\\/]?([^\\\/]+)$//g;
        $conf_file_name = $1;
        $self->fatal("Unexpected regex error when try to parse global file name!") unless $conf_file_name;
        my $doc;
        eval {
            $doc = PL::SAS::Config::_read_config($self->{conf});
        };
        $self->fatal("Failed to read config when initialized: $@") if $@;
        my $conf_last_modified;
        if( my $conf_stat = stat($self->{conf}) ) {
            $conf_last_modified = $conf_stat->mtime;
        }
        else {
            $self->fatal("Failed to get modify time for '$self->{conf}' when _start");
        }
        $heap->{config_wheel} = PL::SAS::Config->new(
            Config      => $self->{conf},
            ErrorEvent  => 'err_conf',
            ChangeEvent => 'chg_conf',
            DoneEvent   => 'start_sas',
        );
        $kernel->yield('init_sas', $doc, $conf_last_modified);
    }
    else {
        $self->fatal("'conf' is required when $class->new!");
    }
}

sub chg_conf {
    my ($kernel, $heap, $self, $xml_doc, $last_mtime) = @_[KERNEL, HEAP, OBJECT, ARG0, ARG1];
    $self->debug("SAS config changed, re-initialize SAS!");
    $kernel->yield( 'init_sas', $xml_doc, $last_mtime );
}

sub err_conf {
    my ($kernel, $self, $msg) = @_[KERNEL, OBJECT, ARG0];
    $self->error("Failed to process conf: $msg!");
}

sub run {
    shift->debug("POE kernel start...");
    POE::Kernel->run();
}

1;
