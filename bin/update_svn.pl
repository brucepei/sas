use FindBin qw($Bin);
use lib "$Bin/../lib";
use lib '/usr/lib/perl5';
use lib '/usr/share/perl5';
use strict;
use warnings;
use Logger;
use Data::Dumper;
use File::Spec;
use File::Copy qw(copy);
use File::stat;
use XML::LibXML;
use Storable qw(thaw);

#my $logger = Logger->new(path => '', level => 'debug');
my $logger = Logger->new(path => File::Spec->catfile($Bin, '..', 'log', 'update_svn.log'), level => 'debug', max_history_size => 1, append => 0);

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
            #auto_case('CNSS SnS x86 testplan.xlsx');
        }
    }
}


sub logger {
    my $level = shift;
    $Logger::Called_Depth -= 1;
    $logger->$level( @_ );
    $Logger::Called_Depth += 1;
}


print "before: update_svn!\n";
process_args(@ARGV);
print "after: update_svn!\n";
<STDIN>;