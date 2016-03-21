package PL::Excel::Reader;
use strict;
use warnings;
use Data::Dumper;
use File::Spec;
use PL;

our @ISA = qw(PL);

use constant {
    IS_WIN32                => $^O eq 'MSWin32',
};

sub read {
    my ( $self, $excel_file ) = @_;
    my $package = ref($self);
    if ($excel_file =~ /\.xml$/i) {
        $self->{Engine_Name} = $package . '::XML';
        eval "use $self->{Engine_Name}";
        $self->debug("Read excel with XML format, so load '$self->{Engine_Name}'");
        
    }
    elsif($excel_file =~ /\.xlsx/i) {
        $self->{Engine_Name} = $package . '::XLSX';
        eval "use $self->{Engine_Name}";
        $self->debug("Read excel with XLSX format, so load '$self->{Engine_Name}'");
    }
    elsif($self->{Engine_Name}) {
        my $user_defined_engine = $self->{Engine_Name};
        $self->{Engine_Name} = $package . '::' . $user_defined_engine unless $user_defined_engine =~ /::/;
        eval "use $self->{Engine_Name}";
        if ($@) {
            $self->fatal("User defined engineer '$user_defined_engine', but failed to load '$self->{Engine_Name}': $@ !");
        }
        else {
            $self->debug("Read excel with user defined engineer '$user_defined_engine', so load '$self->{Engine_Name}'");
        }
    }
    elsif(IS_WIN32) {
        $self->{Engine_Name} = $package . '::OLE';
        eval "use $self->{Engine_Name}";
        if ($@) {
            $self->fatal("Read excel on Win32, but failed to load '$self->{Engine_Name}': $@ !");
        }
        else {
            $self->debug("Read excel on Win32, so load '$self->{Engine_Name}'");
        }
    }
    else {
        $self->fatal("Unsupport to read excel '$excel_file'!");
    }
    $self->{Engine} = $self->{Engine_Name}->new;
    return $self->{Engine}->read($excel_file);
}

1;