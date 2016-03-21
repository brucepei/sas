use FindBin qw($Bin);
use lib "$Bin/../lib";
use lib '/usr/lib/perl5';
use lib '/usr/share/perl5';
use strict;
use warnings;
use Logger;
use File::Path qw(make_path);
use File::Spec;
use PL::Template;
use Data::Dumper;
use XML::LibXML;
use Storable qw(thaw);
use Cwd qw(getcwd);
use PL::AutoCase;
use Mojo::Util qw(spurt);

use constant {
    EXCEL_OUTPUT => File::Spec->catfile('testcase', 'xml'),
    EXCEL_CASE   => File::Spec->catfile(getcwd(), 'case_support_testBatch.xlsx'),
};
#Logger->new(path => '', level => 'debug');
my $logger = Logger->new(path => File::Spec->catfile($Bin, '..', 'log', 'et.log'), level => 'debug', max_history_size => 1, append => 0);

sub auto_case {
    my ($random_excel, $output) = @_;
    die "Failed to find the excel file '$random_excel'!" unless -e $random_excel;
    my $ta_temp = PL::Template->new;
    $ta_temp->compile(File::Spec->catfile('Phoenix', 'testaction.xml.st'));
    my $tc_temp = PL::Template->new;
    $tc_temp->compile(File::Spec->catfile('Phoenix', 'testcase.xml.st'));
    my $ts_temp = PL::Template->new;
    $ts_temp->compile(File::Spec->catfile('Phoenix', 'testsuite.xml.st'));
    my $tb_temp = PL::Template->new;
    $tb_temp->compile(File::Spec->catfile('Phoenix', 'testbatch.xml.st'));
    
    my $auto_case = PL::AutoCase->new;
    $auto_case->load($random_excel,
        Variable => ['GLOBAL_CONFIG', 'VARIABLE'],
        TA => 'TA_DETAIL', TA_Template => $ta_temp,
        TC => 'TC_DETAIL', TC_Template => $tc_temp,
        TS => 'TEST_SUITE', TS_Template => $ts_temp,
        TB => 'TEST_BATCH', TB_Template => $tb_temp,
    );
    
    my $tb_list = $auto_case->tb;
    make_path($output) unless -d $output;
    foreach my $tb_name (keys %{$tb_list}) {
        my $file_name = $tb_name;
        $file_name =~ s/\W/_/g;
        $file_name = File::Spec->catfile($output,  "$file_name.xml");
        print "TB: '$tb_name' write to '$file_name'\n";
        spurt($tb_list->{$tb_name}->print, $file_name);
    }
}

sub logger {
    my $level = shift;
    $Logger::Called_Depth -= 1;
    $logger->$level( @_ );
    $Logger::Called_Depth += 1;
}

auto_case(EXCEL_CASE, EXCEL_OUTPUT);
