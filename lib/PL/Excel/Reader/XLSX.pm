package PL::Excel::Reader::XLSX;
use strict;
use warnings;
use Data::Dumper;
use File::Spec;
use Spreadsheet::XLSX;
use Mojo::Util qw(html_unescape);
#use Text::Iconv;
use PL;

our @ISA = qw(PL);


sub read {
    my $self = shift;
    my $excel_file = shift;
    my $result = [];
    #my $converter = Text::Iconv -> new ("utf-8", "windows-1251");
    my $excel = Spreadsheet::XLSX->new($excel_file);
    foreach my $sheet (@{$excel -> {Worksheet}}) {
        $sheet->{MaxRow} ||= $sheet->{MinRow};
        $sheet->{MaxCol} ||= $sheet->{MinCol};
        my $sh = {name => $sheet->{Name}, max_row => $sheet->{MaxRow}, max_col => $sheet->{MaxCol}, cells => []};
        my $cells = $sh->{cells};
        $self->debug("Read sheet: '$sheet->{Name}', rows($sheet->{MinRow}, $sheet->{MaxRow}), cols($sheet->{MinCol}, $sheet->{MaxCol})");
        foreach my $row ($sheet->{MinRow} .. $sheet->{MaxRow}) {
            foreach my $col ($sheet->{MinCol} ..  $sheet->{MaxCol}) {
                my $cell = $sheet->{Cells}[$row][$col];
                if ($cell) {
                    $cells->[$row][$col] = html_unescape($cell->{Val});
                    $cells->[$row][$col] =~ s/^\s+|\s+$//g;
                }
            }
        }
        push @$result, $sh;
    }
    return $result;
}

1;

