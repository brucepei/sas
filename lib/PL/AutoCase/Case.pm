package PL::AutoCase::Case;
use strict;
use warnings;
use Data::Dumper;
use PL;
use PL::AutoCase::Case::TA;
use PL::AutoCase::Case::TC;
use PL::AutoCase::Case::TS;
use PL::AutoCase::Case::TB;

our @ISA = qw(PL);

sub new {
    my $package = shift;
    my $obj = $package->SUPER::new(TA => {}, TC => {}, TS => {}, @_);
    $obj->debug("construct '$package' object!");
    $obj;
}

sub print {
    my $self = shift;
    if (ref $self->{template}) {
        return $self->{template}->interpret($self);
    }
    else {
        local $Data::Dumper::Terse = 1;
        return Dumper($self);
    }
}

sub load_excel {
    my ( $self, $excel, $var_interpret, @sheets ) = @_;
    $self->fatal("require 'PL::Excel' object when load_excel!") unless ref $excel eq 'PL::Excel';
    $self->fatal("require 'PL::AutoCase::Variable' object when load_excel!") unless ref $var_interpret eq 'PL::AutoCase::Variable';
    $self->fatal("require sheet names when load_excel!") unless @sheets;
    my %sheet_options = @sheets;
    foreach my $sheet_name (qw(TA TC TS TB)) {
        if ($sheet_name eq 'TA' && $sheet_options{$sheet_name}) {
            $self->debug("load TA sheet '$sheet_options{$sheet_name}'");
            $excel->sheet($sheet_options{$sheet_name});
            my $row = [map {lc $_} $excel->row(1)];
            my $rows = $excel->rows(rows => [qw(2-max)], cols => $row);
            $self->_load_ta($rows, $var_interpret, template => $sheet_options{TA_Template});
        }
        elsif ($sheet_name eq 'TC' && $sheet_options{$sheet_name}) {
            $self->debug("load TC sheet '$sheet_options{$sheet_name}'");
            $excel->sheet($sheet_options{$sheet_name});
            my $row = [map {lc $_} $excel->row(1)];
            $row->[$_] = 'tc_' . $row->[$_] foreach (1..3);
            my $rows = $excel->rows(rows => [qw(2-max)], cols => $row);
            $self->_load_tc($rows, $var_interpret, template => $sheet_options{TC_Template});
        }
        elsif ($sheet_name eq 'TS' && $sheet_options{$sheet_name}) {
            $self->debug("load TS sheet '$sheet_options{$sheet_name}'");
            $excel->sheet($sheet_options{$sheet_name});
            my $row = [map {lc $_} $excel->row(1)];
            $row->[$_] = 'ts_' . $row->[$_] foreach (1..6);
            $row->[$_] = 'tc_' . $row->[$_] foreach (8..10);
            my $rows = $excel->rows(rows => [qw(2-max)], cols => $row);
            #print $self->debug("sheetints: " . Dumper($rows));
            $self->_load_ts($rows, $var_interpret, template => $sheet_options{TS_Template});
        }
        elsif ($sheet_name eq 'TB' && $sheet_options{$sheet_name}) {
            $self->debug("load TB sheet '$sheet_options{$sheet_name}'");
            $excel->sheet($sheet_options{$sheet_name});
            my $row = [map {lc $_} $excel->row(1)];
            $row->[$_] = 'tb_' . $row->[$_] foreach (1..1);
            $row->[$_] = 'ts_' . $row->[$_] foreach (3..8);
            $row->[$_] = 'tc_' . $row->[$_] foreach (10..12);
            my $rows = $excel->rows(rows => [qw(2-max)], cols => $row);
            #print $self->debug("sheetints: " . Dumper($rows));
            $self->_load_tb($rows, $var_interpret, template => $sheet_options{TB_Template});
        }
    }
}

sub _load_ta {
    my ( $self, $vars, $var_interpret, @ta_options ) = @_;
    $self->fatal("load_ta() need a hash reference argument!") unless ref $vars;
    $self->fatal("load_ta() need 'PL::AutoCase::Variable' object!") unless ref $var_interpret eq 'PL::AutoCase::Variable';
    my $done;
    foreach my $var (@$vars) {
        next unless $var->{ta_name};
        my $ta_name = delete $var->{ta_name};
        $self->fatal("TA '$ta_name' has new line char!") if $ta_name =~ /\n/;
        if (exists($self->{TA}->{$ta_name})) {
            $self->warn("Found duplicate TA_NAME '$ta_name', ignore it!");
        }
        else {
            $self->debug("load TA_NAME: '$ta_name' into TA container");
            my $ta = PL::AutoCase::Case::TA->new(name => $ta_name, @ta_options);
            $self->{TA}->{$ta_name} = $ta;
            my (@para, @val);
            while (my ($name, $def_val) = each %$var) {
                $def_val = $var_interpret->interpret($def_val);
                if ($name =~ /^parameter(\d+)/) {
                    $ta->para($1, $def_val);
                }
                elsif ($name =~ /^value(\d+)/) {
                    $ta->val($1, $def_val);
                }
                else {
                    $ta->{$name} = $def_val;
                }
            }
            $self->debug("Found TA '$ta_name'");
            #unless($done) {
            #    $done = $self->{TA}->{$ta_name};
            #    $self->warn(Dumper($done));
            #}
        }
    }
}


sub _load_tc {
    my ( $self, $vars, $var_interpret, @tc_options ) = @_;
    $self->fatal("load_tc() need a hash reference argument!") unless ref $vars;
    my $done;
    my $tc_name;
    #$self->debug("load table: " . Dumper($vars));
    foreach my $var (@$vars) {
        if ($var->{tc_name}) {
            $tc_name = delete $var->{tc_name};
            $self->fatal("TC '$tc_name' has new line char!") if $tc_name =~ /\n/;
            if( exists($self->{TC}->{$tc_name}) ) {
                $self->warn("Found duplicate TC_NAME '$tc_name', ignore it!");
                undef $tc_name;
                next;
            }
            else {
                $self->debug("load TC_NAME: '$tc_name' into TC container");
                $self->{TC}->{$tc_name} = PL::AutoCase::Case::TC->new(name => $tc_name, @tc_options);
            }
        }
        elsif (!$tc_name) {
            next;
        }
        my $tc = $self->{TC}->{$tc_name};
        my ($ta, @val);
        if ($var->{ta_name}) {
            if (exists $self->{TA}->{$var->{ta_name}}) {
                 $ta = $self->{TA}->{delete $var->{ta_name}}->clone;
            }
            else {
                #$self->debug("ALL TA: " . Dumper($self->{TA}));
                $self->error("Unknown TA_NAME '$var->{ta_name}' in TC '$tc_name'!");
            }
        }
        while (my ($name, $def_val) = each %$var) {
            $def_val = $var_interpret->interpret($def_val);
            if ($name =~ s/^tc_//) {
                $tc->{$name} = $def_val if defined($def_val); #tc may have multiple lines
            }
            elsif($ta) {
                if ($name =~ /^parameter(\d+)/) {
                    $ta->val($1, $def_val) if defined $def_val;
                }
                else {
                    $ta->{$name} = $def_val if defined $def_val;
                }
            }
        }
        $tc->add_ta($ta) if $ta;
        #unless($done) {
        #    $done = $tc;
        #    $self->warn(Dumper($done));
        #}
    }
    #$self->debug(Dumper($self->{TC}));
}

sub _load_ts {
    my ( $self, $vars, $var_interpret, @ts_options ) = @_;
    $self->fatal("load_ts() need a hash reference argument!") unless ref $vars;
    my $done;
    my ($ts_name, $tc_name, $tc, $ta_index);
    foreach my $var (@$vars) {
        if ($var->{ts_name}) {
            $ts_name = delete $var->{ts_name};
            $self->fatal("TS '$ts_name' has new line char!") if $ts_name =~ /\n/;
            undef $tc_name;
            undef $tc;
            if( exists($self->{TS}->{$ts_name}) ) {
                $self->warn("Found duplicate TS_NAME '$ts_name', ignore it!");
                undef $ts_name;
                next;
            }
            else {
                $self->debug("load TS_NAME: '$ts_name' into TS container");
                $self->{TS}->{$ts_name} = PL::AutoCase::Case::TS->new(name => $ts_name, @ts_options);
            }
        }
        elsif (!$ts_name) {
            next;
        }
        
        my $ts = $self->{TS}->{$ts_name};
        if ($var->{tc_name}) {
            $ta_index = {};
            $tc_name = delete $var->{tc_name};
            $self->debug("Find TC: '$tc_name' in TS '$ts_name'");
            if( exists($self->{TC}->{$tc_name}) ) {
                #$self->debug(Dumper $self->{TC}->{$tc_name});
                $tc = $self->{TC}->{$tc_name}->clone;
                $ts->add_tc($tc);
            }
            else {
                #$self->debug("ALL TC: " . Dumper($self->{TC}));
                $self->error("Unknown TC_NAME '$tc_name' in TS '$ts_name'!");
                undef $tc_name;
                undef $tc;
                undef $ta_index;
            }
        }
        my $ta;
        if ($tc && $var->{ta_name}) {
            my $ta_name = delete $var->{ta_name};
            $self->debug("Find TA: '$ta_name', in TS '$ts_name'->TC: '$tc_name'");
            $ta_index->{$ta_name}++;
            if (my $has_ta = $tc->has_ta($ta_name, $ta_index->{$ta_name})) {
                $ta = $has_ta->clone;
            }
            else {
                $self->error("Unknown TA_NAME '$ta_name'(index $ta_index->{$ta_name}) in TS '$ts_name'->TC '$tc_name'!");
            }
        }
        while (my ($name, $def_val) = each %$var) {
            $def_val = $var_interpret->interpret($def_val);
            if ($name =~ s/^ts_//) {
                $ts->{$name} = $def_val if defined($def_val); #ts may have multiple lines
            }
            elsif ($name =~ s/^tc_//) {
                $tc->{$name} = $def_val if defined($def_val); #tc may have multiple lines
            }
            elsif($ta) {
                if ($name =~ /^parameter(\d+)/) {
                    $ta->val($1, $def_val) if defined $def_val;
                }
                else {
                    $ta->{$name} = $def_val if defined $def_val;
                }
            }
        }
        $tc->update_ta($ta, $ta_index->{$ta->{name}}) if $ta;
        #unless($done) {
        #    $done = $tc;
        #    $self->warn(Dumper($done));
        #}
    }
    #$self->debug(Dumper($self->{TS}));
}

sub _load_tb {
    my ( $self, $vars, $var_interpret, @tb_options ) = @_;
    $self->fatal("load_tb() need a hash reference argument!") unless ref $vars;
    my $done;
    my ($tb_name, $ts_name, $ts, $tc_name, $tc, $tc_index, $ta_index);
    foreach my $var (@$vars) {
        if ($var->{tb_name}) {
            $tb_name = delete $var->{tb_name};
            $self->fatal("TB '$tb_name' has new line char!") if $tb_name =~ /\n/;
            $ts->update_tc($tc, $tc_index->{$tc_name}) if $ts && $tc;
            undef $ts_name;
            undef $ts;
            undef $tc_name;
            undef $tc;
            undef $tc_index;
            undef $ta_index;
            if( exists($self->{TB}->{$tb_name}) ) {
                $self->warn("Found duplicate TB_NAME '$tb_name', ignore it!");
                undef $tb_name;
                next;
            }
            else {
                $self->debug("load TB_NAME: '$tb_name' into TB container");
                $self->{TB}->{$tb_name} = PL::AutoCase::Case::TB->new(name => $tb_name, @tb_options);
            }
        }
        elsif (!$tb_name) {
            next;
        }
        my $tb = $self->{TB}->{$tb_name};
        
        #################Add TS#################
        if ($var->{ts_name}) {
            $ts->update_tc($tc, $tc_index->{$tc_name}) if $ts && $tc;
            undef $ts;
            undef $tc_name;
            undef $tc;
            $tc_index = {};
            $ts_name = delete $var->{ts_name};
            $self->fatal("TS '$ts_name' has new line char!") if $ts_name =~ /\n/;
            $self->debug("Find TS_NAME: '$ts_name' in TB '$tb_name'");
            if( exists($self->{TS}->{$ts_name}) ) {
                $ts = $self->{TS}->{$ts_name}->clone;
                $tb->add_ts($ts);
            }
            else {
                $self->error("Unknown TS_NAME '$ts_name' in TB '$tb_name'!");
                undef $ts_name;
                undef $tc_index;
            }
        }
        elsif (!$ts_name) {
            next;
        }
        
        
        #################check TC update#################
        if ($ts && $var->{tc_name}) {
            $ts->update_tc($tc, $tc_index->{$tc_name}) if $ts && $tc;
            $ta_index = {};
            $tc_name = delete $var->{tc_name};
            $tc_index->{$tc_name}++;
            $self->debug("Find TC: '$tc_name'(index $tc_index->{$tc_name}) in TB '$tb_name'->TS '$ts_name'");
            if (my $has_tc = $ts->has_tc($tc_name, $tc_index->{$tc_name})) {
                $tc = $has_tc->clone;
            }
            else {
                $self->error("Unknown TC_NAME '$tc_name' in TB '$tb_name'->TS '$ts_name'!");
                undef $tc_name;
                undef $tc;
                undef $ta_index;
            }
        }
        
        #################check TA update#################
        my $ta;
        my $ta_op = 'update'; #unshift, push or update(default)
        if ($tc && $var->{ta_name}) {
            my $ta_name = delete $var->{ta_name};
            if( exists($self->{TA}->{$ta_name}) ) {
                $ta = $self->{TA}->{$ta_name}->clone;
                $ta_op = $var->{ta_op} if $var->{ta_op};
                $self->debug("Find TA: '$ta_name' with operation: $ta_op, in TB '$tb_name'->TS '$ts_name'->TC '$tc_name'");
                if ($ta_op eq 'push') {
                    $self->debug("Pushing TA: '$ta_name' at the last position");
                    $tc->insert_ta($ta, -1);
                }
                elsif ($ta_op eq 'unshift') {
                    $self->debug("Unshifting TA: '$ta_name' at the first position");
                    $tc->insert_ta($ta, 0);
                }
                else {
                    $ta_index->{$ta_name}++;
                    $self->debug("Updating TA: '$ta_name' at index $ta_index->{$ta_name}");
                    if (my $has_ta = $tc->has_ta($ta_name, $ta_index->{$ta_name})) {
                        $ta = $has_ta->clone;
                    }
                    else {
                        $self->error("Unknown TA_NAME '$ta_name'(index $ta_index->{$ta_name}) in TB '$tb_name'->TS '$ts_name'->TC '$tc_name'!");
                        undef $ta;
                    }
                }
            }
            else {
                $self->error("Unknown TA_NAME '$ts_name' in TA container!");
            }
        }
        
        #################check TA/TC/TS/TB attributes update#################
        while (my ($name, $def_val) = each %$var) {
            $def_val = $var_interpret->interpret($def_val);
            if ($name =~ s/^tb_//) {
                $tb->{$name} = $def_val if defined($def_val); #tb may have multiple lines
            }
            elsif ($name =~ s/^ts_//) {
                $ts->{$name} = $def_val if defined($def_val); #ts may have multiple lines
            }
            elsif ($name =~ s/^tc_//) {
                $tc->{$name} = $def_val if defined($def_val); #tc may have multiple lines
            }
            elsif($ta) {
                if ($name =~ /^parameter(\d+)/) {
                    $ta->val($1, $def_val) if defined $def_val;
                }
                else {
                    $ta->{$name} = $def_val if defined $def_val;
                }
            }
        }
        if ($ta && $ta_op eq 'update') {
            $tc->update_ta($ta, $ta_index->{$ta->{name}});
        }
    }
}

sub ta {
    my ( $self, $ta_name ) = @_;
    $ta_name ? $self->{TA}->{$ta_name} : $self->{TA};
}

sub tc {
    my ( $self, $tc_name ) = @_;
    $tc_name ? $self->{TC}->{$tc_name} : $self->{TC};
}

sub ts {
    my ( $self, $ts_name ) = @_;
    $ts_name ? $self->{TS}->{$ts_name} : $self->{TS};
}

sub tb {
    my ( $self, $tb_name ) = @_;
    $tb_name ? $self->{TB}->{$tb_name} : $self->{TB};
}

1;