package PL::AutoCase::Case::TA;
use strict;
use warnings;
use Data::Dumper;
use PL::AutoCase::Case;

our @ISA = qw(PL::AutoCase::Case);

sub new {
    my $package = shift;
    my $obj = $package->PL::new(para => [], val => [], para_val => {}, @_);#avoid inherit parent's attributes
    $obj->debug("construct '$package' object!");
    $obj->fatal("require 'name' when construct '$package'!") unless $obj->{name};
    $obj;
}


sub clone {
    my $self = shift;
    my %old_ta = %{$self};
    my $old_para = delete $old_ta{para};
    my $old_val = delete $old_ta{val};
    my $old_para_val = delete $old_ta{para_val};
    my $obj = ref($self)->new(%old_ta);
    $obj->{para} = [@{$old_para}];
    $obj->{val} = [@{$old_val}];
    $obj->{para_val} = {%{$old_para_val}};
    return $obj;
}

sub get_para {
    my ($self, $para_name) = @_;
    if (exists $self->{para_val}->{$para_name}) {
        return $self->{para_val}->{$para_name};
    }
    else {
        foreach (0..$#{$self->{para}}) {
            if ($para_name eq $self->{para}->[$_]) {
                return $self->{para_val}->{$para_name} = $self->{val}->[$_];
            }
        }
        return;
    }
}

sub para {
    my ($self, $index, $para_name) = @_;
    if ($index) {
        $self->fatal("para index should be a positive integer!") unless $index >= 1;
        $index--;
        if (defined $para_name) {
            $self->{para}->[$index] = $para_name;
        }
        else {
            return $self->{para}->[$index];
        }
    }
    else {
        return $self->{para};
    }
}

sub val {
    my ($self, $index, $value) = @_;
    if ($index) {
        $self->fatal("val index should be a positive integer!") unless $index >= 1;
        $index--;
        if (defined $value) {
            $self->{val}->[$index] = $value;
        }
        else {
            return $self->{val}->[$index];
        }
    }
    else {
        return $self->{val};
    }
}

sub update {
    my ($self, $ta) = @_;
    $self->fatal("update rquire a TA object!") unless ref $ta eq ref($self);
    if ($self->{name} eq $ta->{name}) {
        $self->debug("update TA '$ta->{name}'!");
        foreach my $key (keys %{$ta}) {
            if ($key eq 'para') {
                foreach my $i (0..$#{$ta->{para}}) {
                    my $ta_p = $ta->para($i+1);
                    $self->para($i+1, $ta_p) if defined $ta_p;
                }
            }
            elsif ($key eq 'val') {
                foreach my $i (0..$#{$ta->{val}}) {
                    my $ta_v = $ta->val($i+1);
                    $self->val($i+1, $ta_v) if defined $ta_v;
                }
            }
            elsif ($key eq 'para_val') {
                $self->{$key} = {};
            }
            elsif(defined $ta->{$key}) {
                $self->{$key} = $ta->{$key};
            }
        }
    }
}

1;