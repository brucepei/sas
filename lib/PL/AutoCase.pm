package PL::AutoCase;
use strict;
use warnings;
use Data::Dumper;
use PL;
use PL::Excel;
use PL::AutoCase::Variable;
use PL::AutoCase::Case;

our @ISA = qw(PL);

sub new {
    my $package = shift;
    my $obj = $package->SUPER::new(@_);
    $obj->debug("construct '$package' object!");
    $obj;
}

sub load {
    my ( $self, $excel_file, @excel_args ) = @_;
    $self->fatal("require excel file when load!") unless defined $excel_file;
    $self->fatal("require excel arguments which should be even number!") if @excel_args % 2;
    my %excel_options = @excel_args;
    my $excel = PL::Excel->new;
    $excel->read($excel_file);
    my $var = PL::AutoCase::Variable->new;
    $var->load_excel($excel, @{$excel_options{Variable}});
    my $case = PL::AutoCase::Case->new;
    $case->load_excel($excel, $var,
        TA => $excel_options{TA}, TA_Template => $excel_options{TA_Template},
        TC => $excel_options{TC}, TC_Template => $excel_options{TC_Template}, 
        TS => $excel_options{TS}, TS_Template => $excel_options{TS_Template}, 
        TB => $excel_options{TB}, TB_Template => $excel_options{TB_Template}, 
    );
    $self->{Case} = $case;
}


sub ta {
    my ( $self, $ta_name ) = @_;
    $self->{Case}->ta($ta_name);
}

sub tc {
    my ( $self, $tc_name ) = @_;
    $self->{Case}->tc($tc_name);
}

sub ts {
    my ( $self, $ts_name ) = @_;
    $self->{Case}->ts($ts_name);
}

sub tb {
    my ( $self, $tb_name ) = @_;
    $self->{Case}->tb($tb_name);
}

1;