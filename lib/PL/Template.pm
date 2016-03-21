package PL::Template;
use strict;
use warnings;
use Data::Dumper;
use File::Spec;
use Mojo::Template;
use Mojo::Util qw(monkey_patch encode decode slurp);
use PL;

our @ISA = qw(PL);
use constant {
    TEMPLATE_PATH           => 'template',
    DEFAULT_TAG             => [qw(include indent)],
};

sub new {
    my $package = shift;
    my $obj = $package->SUPER::new(
        mt => Mojo::Template->new,
        @_
    );
    $obj->debug("construct '$package' object!");
    $obj->import_tag(@{ &DEFAULT_TAG });
    $obj;
}

sub add_func {
    my ($self, $func_name, $func_handler) = @_;
    monkey_patch(
        $self->{mt}->namespace,
        $func_name => sub {
            $func_handler->(@_);
        },
    );
}

sub import_tag {
    my $self = shift;
    my $package = ref $self;
    my $tag_sub = {
        include => sub {
            my $file_name = shift;
            my $indent = pop;
            my $inc_mt = $package->new;
            $inc_mt->compile($file_name);
            my $output = $inc_mt->interpret({@_});
            $output =~ s/\n/$&$indent/g;
            $output;
        },
        indent => sub {
            my ($output, $indent) = @_;
            $output =~ s/\n/$&$indent/g;
            $output;
        },
    };
    foreach my $func_name (@_) {
        if (exists $tag_sub->{$func_name}) {
            $self->debug("Import tag '$func_name' for template used!");
            $self->add_func($func_name, $tag_sub->{$func_name});
        }
        else {
            $self->warn("Failed import tag '$func_name', it is not defined by default!");
        }
    }
}

#$self->compile('test.ep', '$a, $b, @c');
sub compile {
    my ($self, $file_name) = @_;
    my $t_file = File::Spec->catfile(TEMPLATE_PATH, $file_name);
    $self->fatal("Failed to find template file '$file_name' in '" . TEMPLATE_PATH . "' directory!") unless -e $t_file;
    $self->{mt}->name($t_file);
    my $template = slurp( $t_file );
    my $encoding = $self->{mt}->encoding;
    if( $encoding && !defined($template = decode $encoding, $template) ) {
        $self->fatal("Template '$t_file' has invalid encoding '$encoding'");
    }
    $self->trace("Read template '$file_name' content:\n'$template'");
    my $compile_result = $self->{mt}->parse($template)->build->compile;
    if (ref $compile_result) {
        $self->fatal("compile failed: $compile_result!");
    }
    $self->trace("Compile template '$file_name' code:\n'" . $self->{mt}->code . "'");
}

sub interpret {
    my $self = shift;
    my $compiled = $self->{mt}->compiled;
    $self->fatal("Cannot interpret template which has not been compiled!") unless $compiled;
    $self->trace("Before compiled: " . Dumper($self->{mt}));
    $self->trace("Ready to interpret template with arguments: " . Dumper(@_));
    my $output = $self->{mt}->interpret(@_);
    if (ref $output) {
        $self->fatal("interpret failed: $output!");
    }
    else {
        $self->trace("interpret successfully: '$output'");
    }
    chomp($output);
    return $output;
}

1;