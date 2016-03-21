package PL::AutoCase::Case::TB;
use strict;
use warnings;
use Data::Dumper;
use PL::AutoCase::Case;

our @ISA = qw(PL::AutoCase::Case);

sub new {
    my $package = shift;
    my $obj = $package->PL::new(tc => [], @_);
    $obj->debug("construct '$package' object!");
    $obj->fatal("require 'name' when construct '$package'!") unless $obj->{name};
    $obj;
}

sub clone {
    my $self = shift;
    my %old_tb = %{$self};
    my $old_ts = delete $old_tb{ts};
    my $obj = ref($self)->new(%old_tb);
    foreach my $ts (@$old_ts) {
        $obj->add_ts($ts->clone);
    }
    return $obj;
}

sub add_ts {
    my ($self, $ts) = @_;
    $self->fatal("add_ts rquire a TS object!") unless ref $ts eq 'PL::AutoCase::Case::TS';
    push @{$self->{ts}}, $ts;
}

1;