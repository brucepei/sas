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
use PL::AutoCase;
use Mojo::Util qw(spurt);

use constant {
    EXCEL_OUTPUT => File::Spec->catfile('testcase', 'xml'),
    EXCEL_CASE   => 'CNSS SnS x86 testplan.xlsx',
};
#Logger->new(path => '', level => 'debug');
my $logger = Logger->new(path => File::Spec->catfile($Bin, '..', 'log', 'auto_case.log'), level => 'debug', max_history_size => 1, append => 0);

process_args(@ARGV);

sub process_args {
    my ($args_str) = @_;
    $args_str=~s/../chr(hex($&))/eg;
    my $args;
    eval {
        $args = thaw($args_str);
    };
    if ($@) {
        logger( fatal => "Cannot thaw the arguments: '$_[0]',\n\tError: $@" );
    }
    else {
        logger( debug => 'Run with args ' . Dumper($args) . "!");
        if (ref $args && ref $args->{project}) {
            my $prj_args = {};
            foreach my $prj_name (keys %{$args->{project}}) {
                my $prj = $args->{project}->{$prj_name};
                my $conf = $prj->{conf};
                my $enable = $prj->{enable};
                logger( debug => "Generate case for project '$prj_name': " );
                logger( debug => "'$prj_name' enable: $enable" );
                logger( debug => "'$prj_name' conf: $conf" );
                unless ($enable) {
                    logger( error => "Project '$prj_name' is disabled, so ignore it!" );
                    next;
                }
                if (-e $conf) {
                    my $conf_path = $conf;
                    $conf_path =~ s/[\\\/]?([^\\\/]+)$//g;
                    my $doc;
                    eval {
                        my $parser = XML::LibXML->new;
                        $doc    = $parser->parse_file($conf);
                    };
                    if ( $@ ) {
                        logger( error => "read xml file '$conf' with error: $@" );
                        next;
                    }
                    $prj_args->{$prj_name}->{path} = $conf_path;
                    foreach my $dut ($doc->findnodes('/STA_Global/Project/DUT')) {
                        my $dut_id = $dut->getAttribute('id');
                        my $dut_path = $dut->getAttribute('conf');
                        $dut_path =~ s/[\\\/]?([^\\\/]+)$//g;
                        $dut_path = File::Spec->catfile($conf_path, $dut_path);
                        logger( debug => "Find DUT '$dut_id' path $dut_path!" );
                        if ( -d $dut_path ) {
                            logger( debug => "The path for DUT $dut_id exists!" );
                            $prj_args->{$prj_name}->{dut}->{$dut_id} = $dut_path;
                        }
                    }
                }
                else {
                    logger( error => "Failed to find conf '$conf' for project '$prj_name'!" );
                    next;
                }
            }
            logger( debug => 'Run with project args ' . Dumper($prj_args) . "!");
            auto_case_batch($prj_args, $args->{args});
        }
    }
}

sub auto_case_batch {
    my ($project_args, $auto_case_args) = @_;
    foreach my $prj_name (keys %$project_args) {
        my $project = $project_args->{$prj_name};
        logger( debug => "Run auto case for project '$prj_name':" );
        foreach my $dut_name (keys %{$project->{dut}}) {
            my $dut_excel = File::Spec->catfile($project->{dut}->{$dut_name}, EXCEL_CASE);
            my $dut_excel_output = File::Spec->catfile($project->{dut}->{$dut_name}, EXCEL_OUTPUT);
            if (-e $dut_excel) {
                logger( debug => "Run auto case for DUT '$dut_name', output: '$dut_excel_output'" );
                auto_case($dut_excel, $dut_excel_output)
            }
            else {
                logger( debug => "Not fond excel case, so ignore to run auto case for DUT '$dut_name'!" );
            }
        }
    }
}

sub auto_case {
    my ($random_excel, $output) = @_;
    die "Failed to find the excel file '$random_excel'!" unless -e $random_excel;
    my $ta_temp = PL::Template->new;
    $ta_temp->compile(File::Spec->catfile('Phoenix', 'testaction.xml.st'));
    my $tc_temp = PL::Template->new;
    $tc_temp->compile(File::Spec->catfile('Phoenix', 'testcase.xml.st'));
    my $ts_temp = PL::Template->new;
    $ts_temp->compile(File::Spec->catfile('Phoenix', 'testsuite.xml.st'));
    
    my $auto_case = PL::AutoCase->new;
    $auto_case->load($random_excel,
        Variable => ['GLOBAL_CONFIG', 'VARIABLE'],
        TA => 'TA_DETAIL', TA_Template => $ta_temp,
        TC => 'TC_DETAIL', TC_Template => $tc_temp,
        TS => 'TEST_SUITE', TS_Template => $ts_temp,
    );
    
    my $ts_list = $auto_case->ts;
    make_path($output) unless -d $output;
    foreach my $ts_name (keys %{$ts_list}) {
        my $file_name = $ts_name;
        $file_name =~ s/\W/_/g;
        $file_name = File::Spec->catfile($output,  "$file_name.xml");
        print "TS: '$ts_name' write to '$file_name'\n";
        spurt($ts_list->{$ts_name}->print, $file_name);
    }
}

sub logger {
    my $level = shift;
    $Logger::Called_Depth -= 1;
    $logger->$level( @_ );
    $Logger::Called_Depth += 1;
}
