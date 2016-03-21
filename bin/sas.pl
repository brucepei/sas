use FindBin qw($Bin);
use lib "$Bin/../lib";
use lib '/usr/lib/perl5';
use lib '/usr/share/perl5';
use lib 'lib';
use strict;
use warnings;
use Logger;
use File::Spec;
use PL::SAS;
use File::Path qw(make_path);

make_path(File::Spec->catfile($Bin, '..', 'log'));
Logger->new(path => File::Spec->catfile($Bin, '..', 'log', 'sas.log'), rotate => 1);
#Logger->new();
my $conf = shift @ARGV || File::Spec->catfile($Bin, '..', 'conf', 'SAS.xml');
my $sas = PL::SAS->new(alias => 'sas', conf => $conf, append => 0);
$sas->run;
