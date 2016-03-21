package PL::AutoCase::Case::TS;
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
    my %old_ts = %{$self};
    my $old_tc = delete $old_ts{tc};
    my $obj = ref($self)->new(%old_ts);
    foreach my $tc (@$old_tc) {
        $obj->add_tc($tc->clone);
    }
    return $obj;
}

sub add_tc {
    my ($self, $tc) = @_;
    $self->fatal("add_tc rquire a TC object!") unless ref $tc eq 'PL::AutoCase::Case::TC';
    push @{$self->{tc}}, $tc;
}

sub has_tc {
    my ($self, $tc_name, $index) = @_;
    $self->fatal("has_ta requires a TC name!") unless $tc_name;
    my $match_num = 1;
    if ($index && $index > 1) {
        $match_num = $index;
        $self->debug("has TC '$tc_name' at index $index!");
    }
    foreach (@{$self->{tc}}) {
        if ($_->{name} eq $tc_name) {
            $match_num--;
            if ($match_num > 0) {
                $self->debug("has TC '$tc_name' but remain $match_num times!");
            }
            else {
                return $_;
            }
        }
    }
    return;
}

sub update_tc {
    my ($self, $tc, $index) = @_;
    $self->fatal("update_ta rquire a TC object!") unless ref $tc eq 'PL::AutoCase::Case::TC';
    my $match_num = 1;
    if ($index && $index > 1) {
        $match_num = $index;
    }
    $self->debug("Try to update TC '$tc->{name}' at index $match_num!");
    foreach (@{$self->{tc}}) {
        if ($_->{name} eq $tc->{name}) {
            $match_num--;
            if ($match_num > 0) {
                $self->debug("update TC '$tc->{name}' in TC '$self->{name}' but remain $match_num times!");
            }
            else {
                $_ = $tc->clone;
                $self->debug("update TC '$tc->{name}' in TC '$self->{name}' done!");
                return 1;
            }
        }
    }
    return;
}

1;