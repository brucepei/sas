package PL::Excel;
use strict;
use warnings;
use Exporter 'import';
use Data::Dumper;
use Cwd qw(abs_path getcwd);
use File::Spec;
use PL::Excel::Reader;
use PL;

our @ISA = qw(PL);
our @EXPORT_OK = qw(

);

use constant {

};

sub new {
    my $package = shift;
    my $obj = $package->SUPER::new(@_);
    $obj->debug("construct '$package' object!");
    $obj;
}

sub sheet {
    my ($self, $sheet_name) = @_;
    unless( $self->{Active_Book} ) {
        $self->warn("Have not read any excel book, return undef!");
        return;
    }
    return $self->{Sheet} unless defined($sheet_name);
    $self->fatal("Not found sheet name '$sheet_name'!") unless exists($self->{Sheet}->{$sheet_name});
    $self->{Active_Sheet} = $self->{Sheet}->{$sheet_name};
}

#sheet index start from 1, not 0!
sub sheet_index {
    my ($self, $sheet_index) = @_;
    unless( $self->{Active_Book} ) {
        $self->warn("Have not read any excel book, return undef!");
        return;
    }
    return $self->{Sheet_List} unless defined($sheet_index);
    $self->fatal("sheet_index() require a positive integer!") unless $sheet_index && $sheet_index =~ /^\d+$/ && $sheet_index >= 1;
    my $max_sheet_index = @{$self->{Sheet_List}};
    $self->fatal("sheet index($sheet_index) exceeds the max sheet index '$max_sheet_index'!") unless $sheet_index <= $max_sheet_index;
    $self->{Active_Sheet} = $self->{Sheet_List}->[$sheet_index-1];
}

#row index start from 1, not 0!
sub row {
    my ($self, $row_index) = @_;
    unless( $self->{Active_Book} ) {
        $self->warn("Have not read any excel book, return undef!");
        return;
    }
    unless( $self->{Active_Sheet} ) {
        $self->warn("Have not actived any excel sheet, return undef!");
        return;
    }
    $self->fatal("row() require a positive integer!") unless $row_index && $row_index =~ /^\d+$/ && $row_index >= 1;
    my $max_row = $self->{Active_Sheet}->{max_row};
    if (($row_index - 1) > $max_row) {
        $self->warn("the row_index($row_index) exceeds the max row number($max_row), return undef!");
        return;
    }
    my @row_list = @{$self->{Active_Sheet}->{cells}->[$row_index-1]};
    wantarray ? @row_list : \@row_list;
}

#col index start from A, also can be, 'b', 'c', 'AB'!
sub col {
    my ($self, $col_index) = @_;
    unless( $self->{Active_Book} ) {
        $self->warn("Have not read any excel book, return undef!");
        return;
    }
    unless( $self->{Active_Sheet} ) {
        $self->warn("Have not actived any excel sheet, return undef!");
        return;
    }
    $self->fatal("col() require a 'a'/'b'/..'z' style column index!") unless $col_index && $col_index =~ /^[a-zA-Z]+$/;
    my $col = $self->col_2_index($col_index);
    my $max_col = $self->{Active_Sheet}->{max_col};
    my $max_col_index = $self->index_2_col($max_col);
    if ($col > $max_col) {
        $self->warn("the col_index($col_index) exceeds the max column($max_col_index), return undef!");
        return;
    }
    my @col_list = ();
    foreach my $row (0..$self->{Active_Sheet}->{max_row}) {
        push @col_list, $self->{Active_Sheet}->{cells}->[$row][$col];
    }
    wantarray ? @col_list : \@col_list;
}

sub cell {
    my ($self, $row_index, $col_index) = @_;
    unless( $self->{Active_Book} ) {
        $self->warn("Have not read any excel book, return undef!");
        return;
    }
    unless( $self->{Active_Sheet} ) {
        $self->warn("Have not actived any excel sheet, return undef!");
        return;
    }
    $self->fatal("row() require a positive integer!") unless $row_index && $row_index =~ /^\d+$/ && $row_index >= 1;
    $self->fatal("col() require a 'a'/'b'/..'z' style column index!") unless $col_index && $col_index =~ /^[a-zA-Z]+$/;
    my $max_row = $self->{Active_Sheet}->{max_row};
    if (($row_index - 1) > $max_row) {
        $self->warn("the row_index($row_index) exceeds the max row number($max_row), return undef!");
        return;
    }
    my $col = $self->col_2_index($col_index);
    my $max_col = $self->{Active_Sheet}->{max_col};
    my $max_col_index = $self->index_2_col($max_col);
    if ($col > $max_col) {
        $self->warn("the col_index($col_index) exceeds the max column($max_col_index), return undef!");
        return;
    }
    $self->{Active_Sheet}->{cells}->[$row_index - 1][$col];
}

#rows_with_name(
# rows => [qw(2 3-10 15-max)], #index start from 1
# cols => {
#    a => 'c1'
#    d => 'c2',
#    e => 'c3',
#    f => 'c4'
#})
# return [
#            {c1 => 'xx', c2 => 'xx', c3 => 'xx', c4 => 'xx'},
#            {c1 => 'yy', c2 => 'yy', c3 => 'yy', c4 => 'yy'},
#            {c1 => 'zz', c2 => 'zz', c3 => 'zz', c4 => 'zz'},
#            ...
#        ]
sub rows_with_name {
    my $self = shift;
    my %options = @_;
    unless( $self->{Active_Book} ) {
        $self->warn("Have not read any excel book, return undef!");
        return;
    }
    unless( $self->{Active_Sheet} ) {
        $self->warn("Have not actived any excel sheet, return undef!");
        return;
    }
    $self->fatal("rows_with_name() require a hash reference to defined column name!") unless %options && ref $options{cols};
    my $cols = {};
    if (ref $options{cols} eq 'HASH') {
        foreach my $col_index (keys %{$options{cols}}) {
            $self->fatal("the argument of 'cols' should have the key: 'a'/'b'/..'z' as column index!") unless $col_index && $col_index =~ /^[a-zA-Z]+$/;
            my $col = $self->col_2_index($col_index);
            $self->fatal("Found duplicate column in 'cols': '$col_index'!") if exists($cols->{$col});
            $cols->{$col} = $options{cols}->{$col_index};
        }
    }
    elsif(ref $options{cols} eq 'ARRAY') {
        foreach my $col (0..$#{$options{cols}}) {
            $cols->{$col} = $options{cols}->[$col];
        }
    }
    else {
        $self->fatal("Unsupport cols option type!");
    }
    my $max_col = $self->{Active_Sheet}->{max_col};
    my $max_col_index = $self->index_2_col($max_col);
    my $rows = [];
    my $max_row = $self->{Active_Sheet}->{max_row};
    if (ref $options{rows}) {
        my @ext_row = map {s/\d+/$&-1/eg; $_} @{$options{rows}};
        @ext_row = map {s/max/$max_row/i; $_} @ext_row;
        $self->debug("only return rows: @ext_row!");
        my $row_list = $self->rows_extend_list(@ext_row);
        foreach my $row (@$row_list) {
            my $cur_row = {};
            foreach my $col (keys %$cols) {
                $cur_row->{$cols->{$col}} = $self->{Active_Sheet}->{cells}->[$row][$col];
            }
            push @$rows, $cur_row;
        }
    }
    else {
        $self->debug("return all rows: 0-$max_row");
        foreach my $row (0..$self->{Active_Sheet}->{max_row}) {
            foreach my $col (keys %$cols) {
                $rows->[$row]->{$cols->{$col}} = $self->{Active_Sheet}->{cells}->[$row][$col];
            }
        }
    }

    return $rows;
}

sub rows {
    my $self = shift;
    my %options = @_;
    unless( $self->{Active_Book} ) {
        $self->warn("Have not read any excel book, return undef!");
        return;
    }
    unless( $self->{Active_Sheet} ) {
        $self->warn("Have not actived any excel sheet, return undef!");
        return;
    }
    if( %options ) {
        if(ref $options{cols}) {
            $self->debug("has cols option, so call rows_with_name instead!");
            return $self->rows_with_name(@_);
        }
        elsif (ref $options{rows}) {
            my $max_row = $self->{Active_Sheet}->{max_row};
            my @ext_row = map {s/\d+/$&-1/eg; $_} @{$options{rows}};
            @ext_row = map {s/max/$max_row/i; $_} @ext_row;
            $self->debug("has rows option, so only return rows: @ext_row!");
            my $row_list = $self->rows_extend_list(@ext_row);
            my $rows = [];
            foreach my $row (@$row_list) {
                push @$rows, $self->{Active_Sheet}->{cells}->[$row];
            }
            return $rows;
        }
        else {
            $self->fatal("Unsupport options for rows: '@_'");
        }
    }
    else {
        $self->debug("No option, so return all rows!");
        return $self->{Active_Sheet}->{cells};
    }
}

sub read {
    my $self = shift;
    my $excel_file = shift;
    if (-e $excel_file) {
        $self->debug("Load reader to read excel file: '$excel_file'");
        $self->{Reader} = PL::Excel::Reader->new(@_);
        my $result = $self->{Reader}->read($excel_file);
        if (ref $result && @$result) {
            $self->{Sheet_Num} = @$result;
            foreach my $sheet (@{$result}) {
                push @{$self->{Sheet_List}}, $sheet;
                $self->{Sheet}->{$sheet->{name}} = $sheet;
            }
        }
        else {
            $self->fatal("Failed to read the excel file: '$excel_file': '$result'!");
        }
        $self->{Active_Book} = $excel_file;
        $self->{Active_Sheet} = $self->{Sheet_List}->[0];
        $self->debug("The reader '$self->{Reader}->{Engine_Name}' have read the excel file completely!");
    }
    else {
        $self->fatal("Failed to find the excel file: '$excel_file'!");
    }
}

sub write_book {
    my $self = shift;
    my $excel_file = shift;
    eval 'use Win32::OLE';
    my $Excel = Win32::OLE->GetActiveObject('Excel.Application') || Win32::OLE->new('Excel.Application');
    $Excel->{'Visible'} = 1;
    $Excel->{DisplayAlerts}=0;
    my $Book;
    if (-e $excel_file) {
        $excel_file = abs_path($excel_file);
        $self->debug("Exists excel book '$excel_file', open it!");
        $Book = $Excel->Workbooks->Open($excel_file);
    }
    else {
        $excel_file = File::Spec->catfile(getcwd(), $excel_file);
        $self->debug("Not found excel book '$excel_file', so create a new book!");
        $Excel->{SheetsInNewWorkBook} = 1;
        $Book = $Excel->Workbooks->Add();
        $Book->SaveAs({Filename => $excel_file});
    }
    return $Book;
}

sub _filter_invisible {
    my $str = shift;
    return unless defined $str;
    $str =~ s/[^\x{20}-\x{7E}]//g;
    $str =~ s/^\s+|\s+$|\?//g; #? Win32::OLE would read failed-decoded char as '?'
    $str;
}

#col_2_index('A') == 0
sub col_2_index {
    my ( $self, $col ) = @_;
    $col = lc( $col );
    my $length = length( $col );
    my $index = 0;
    my $inc_base = ord( 'a' );
    while( $col =~ /([a-z])/g ) {
        $index += ( ord( $1 ) - $inc_base + 1 ) * 26 ** ( $length - 1 );
        $length--;
    }
    return $index - 1;
}

#index_2_col(0) == 'a'
sub index_2_col {
    my ( $self, $index ) = @_;
    my @col;
    my @all_col = ( 'a'..'z' );
    while( my $next_index = int( $index / @all_col ) ) {
        unshift @col, $all_col[$index % @all_col];
        #Except the first byte, For all the other bytes 'a' indicated '1', not 0
        $index = $next_index - 1;
    }
    unshift @col, $all_col[$index];
    return join '', @col;
}

#rows_extend_list('1', '3-10') == 1, 3,4,5...,10
sub rows_extend_list {
    my ( $self, @rows ) = @_;
    my @rows_list;
    my %check_duplicatd;
    foreach my $rg ( @rows ) {
        my $range = lc( $rg );
        if( $range =~ /^(\d+)\-(\d+)$/ ) {
            my ( $from_index, $to_index ) = ( $1, $2 );
            die "'$from_index' cannot greater than '$to_index' in range rows '$range'!" if $to_index < $from_index;
            foreach ( $from_index..$to_index ) {
                if( exists( $check_duplicatd{$_} ) ) {
                    die "Duplicated row '$_' found when parse range rows '$range'!";
                }else {
                    $check_duplicatd{$_}++;
                    push @rows_list, $_;
                }
            }
        }elsif( $range =~ /^\d+$/ ) {
            if( exists( $check_duplicatd{$range} ) ) {
                die "Duplicated column '$range' found when parse single row '$range'!";
            }else {
                $check_duplicatd{$range}++;
                push @rows_list, $range;
            }
        }else {
            die "Invalid data '$range' to parse excel rows to index!";
        }
    }
    return wantarray ? @rows_list : \@rows_list;
}

#cols_extend_list('A', 'c-e') == A, c, d, e
sub cols_extend_list {
    my ( $self, @cols ) = @_;
    my @cols_list;
    my %check_duplicatd;
    foreach my $rg ( @cols ) {
        my $range = lc( $rg );
        if( $range =~ /^([a-z]+)\-([a-z]+)$/ ) {
            my ( $from, $to ) = ( $1, $2 );
            my $from_index = $self->col_2_index( $from );
            my $to_index = $self->col_2_index( $to );
            die "'$from' cannot greater than '$to' in range cols '$range'!" if $to_index < $from_index;
            foreach ( $from..$to ) {
                if( exists( $check_duplicatd{$_} ) ) {
                    die "Duplicated column '$_' found when parse range cols '$range'!";
                }else {
                    $check_duplicatd{$_}++;
                    push @cols_list, $_;
                }
            }
        }elsif( $range =~ /^[a-z]+$/ ) {
            if( exists( $check_duplicatd{$range} ) ) {
                die "Duplicated column '$range' found when parse single col '$range'!";
            }else {
                $check_duplicatd{$range}++;
                push @cols_list, $range;
            }
        }else {
            die "Invalid data '$range' to parse excel columns to index!";
        }
    }
    return wantarray ? @cols_list : \@cols_list;
}

#cols_2_index_list('A', 'c-e') == 0, 2, 3, 4
sub cols_2_index_list {
    my ( $self, @cols ) = @_;
    my @index_list;
    foreach my $col ( $self->cols_extend_list( @cols ) ) {
        push @index_list, $self->col_2_index( $col );
    }
    return wantarray ? @index_list : \@index_list;
}

#cols_2_seq_hash('A', 'c-e') == {a => 0, c => 1, d => 2, e => 3}
sub cols_2_seq_hash {
    my ( $self, @cols ) = @_;
    my @extend_list = $self->cols_extend_list( @cols );
    my %index_hash;
    foreach ( 0..$#extend_list ) {
        $index_hash{ $extend_list[$_] } = $_;
    }
    return wantarray ? %index_hash : \%index_hash;
}

1;