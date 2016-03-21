package PL::AutoCase::Case::TC;
use strict;
use warnings;
use Data::Dumper;
use PL::AutoCase::Case;

our @ISA = qw(PL::AutoCase::Case);

sub new {
    my $package = shift;
    my $obj = $package->PL::new(ta => [], @_);
    $obj->debug("construct '$package' object!");
    $obj->fatal("require 'name' when construct '$package'!") unless $obj->{name};
    $obj;
}

sub clone {
    my $self = shift;
    my %old_tc = %{$self};
    my $old_ta = delete $old_tc{ta};
    my $obj = ref($self)->new(%old_tc);
    foreach my $ta (@$old_ta) {
        $obj->add_ta($ta->clone);
    }
    return $obj;
}

sub add_ta {
    my ($self, $ta) = @_;
    $self->fatal("add_ta rquire a TA object!") unless ref $ta eq 'PL::AutoCase::Case::TA';
    push @{$self->{ta}}, $ta;
}

sub has_ta {
    my ($self, $ta_name, $index) = @_;
    $self->fatal("has_ta requires a TA name!") unless $ta_name;
    my $match_num = 1;
    if ($index && $index > 1) {
        $match_num = $index;
        $self->debug("has TA '$ta_name' at index $index!");
    }
    foreach (@{$self->{ta}}) {
        if ($_->{name} eq $ta_name) {
            $match_num--;
            if ($match_num > 0) {
                $self->debug("has TA '$ta_name' but remain $match_num times!");
            }
            else {
                return $_;
            }
        }
    }
    return;
}

sub insert_ta {
    my ($self, $ta, $offset) = @_;
    $self->fatal("insert_ta rquire a TA object!") unless ref $ta eq 'PL::AutoCase::Case::TA';
    if ($offset < 0) {
        push @{$self->{ta}}, $ta;
    }
    elsif ($offset == 0) {
        unshift @{$self->{ta}}, $ta;
    }
    else {
        $self->fatal("insert_ta doesn't support positive offset now!");
    }
}

sub update_ta {
    my ($self, $ta, $index) = @_;
    $self->fatal("update_ta rquire a TA object!") unless ref $ta eq 'PL::AutoCase::Case::TA';
    my $match_num = 1;
    if ($index && $index > 1) {
        $match_num = $index;
    }
    $self->debug("Try to update TA '$ta->{name}' at index $match_num!");
    foreach (@{$self->{ta}}) {
        if ($_->{name} eq $ta->{name}) {
            $match_num--;
            if ($match_num > 0) {
                $self->debug("update TA '$ta->{name}' in TC '$self->{name}' but remain $match_num times!");
            }
            else {
                $_->update($ta);
                $self->debug("update TA '$ta->{name}' in TC '$self->{name}' done!");
                return 1;
            }
        }
    }
    return;
}

1;