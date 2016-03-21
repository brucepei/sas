package PL::AutoCase::Variable;
use strict;
use warnings;
use Data::Dumper;
use PL;

our @ISA = qw(PL);

sub new {
    my $package = shift;
    my $obj = $package->SUPER::new(VAR => {}, @_);
    $obj->debug("construct '$package' object!");
    $obj;
}

sub load_excel {
    my ( $self, $excel, @sheet_names ) = @_;
    $self->fatal("require 'PL::Excel' object when load_excel!") unless ref $excel eq 'PL::Excel';
    $self->fatal("require sheet name list when load_excel!") unless @sheet_names;
    foreach my $sheet_name (@sheet_names) {
        $excel->sheet($sheet_name);
        my $rows = $excel->rows(rows => [qw(2-max)], cols => {a => 'name', b => 'key', c => 'val'});
        $self->load($rows);
    }
}

sub load {
    my ( $self, $vars ) = @_;
    $self->fatal("load() need a hash reference argument!") unless ref $vars;
    my $key;
    foreach my $var (@$vars) {
        my $curr_key = $var->{name} ? lc $var->{name} : '';
        my $curr_sub_key = $var->{key} ? lc $var->{key} : '';
        $key = $curr_key if $curr_key;
        next unless $key && $curr_sub_key;
        if (exists($self->{VAR}->{$key})) {
            if (exists($self->{VAR}->{$key}->{$curr_sub_key})) {
                $self->warn("Found duplicate variable: '\$$key\->{$curr_sub_key}', override it!");
            }
        }
        else {
            $self->{VAR}->{$key} = {};
        }
        $self->{VAR}->{$key}->{$curr_sub_key} = $self->interpret($var->{val});
    }
    #print Dumper($self->{VAR});
}

sub inc_var {
    my ( $self, $str ) = @_;
    $str =~ /\$[a-zA-Z]\w*\-\>\{[^{}]+\}/;
}

sub interpret {
    my ( $self, $str ) = @_;
    return $str unless $str;
    my $max_loop = 100;
    while( $str =~ /\$([a-zA-Z]\w*)\-\>\{([^{}]+)\}/ ) {
        my ($name, $key) = ($1, $2);
        my ($lc_name, $lc_key) = (lc $name, lc $key);
        my $val = '';
        if (exists($self->{VAR}->{$lc_name}) && exists($self->{VAR}->{$lc_name}->{$lc_key})) {
            $val = $self->{VAR}->{$lc_name}->{$lc_key} || '';
        }
        else {
            $self->error("Not defined variable '\$$name\->{$key}'!");
        }
        $str =~ s/\$$name\-\>\{$key\}/$val/;
        $self->debug("interpret \$$name\->{$key}='$val'");
        $max_loop--;
        if( $max_loop < 0 ) {
            $self->error("Too many variable in '$str', maybe in dead loop!");
            last;
        }
    }
    return $str;
}

sub clear {
    my $self = shift;
    $self->{VAR} = {};
}

sub delete {
    my ( $self, $var_name ) = @_;
    delete $self->{VAR}->{$var_name};
}

1;