package ev3mock;

use strict;
use warnings;

BEGIN {
    use FindBin qw($Bin);

    use lib "$Bin/../lib";
    $ENV{LD_LIBRARY_PATH} //= "";
    $ENV{LD_LIBRARY_PATH} = "$Bin/../lib:$ENV{LD_LIBRARY_PATH}";
}

use ev3;
use Test::MockModule;

sub new  {
    my $class = shift;
    my $args  = $_[0] && ref $_[0] eq 'HASH' ? $_[0] : {};

    $args->{'__mock'} = Test::MockModule->new('ev3');

    my $self = bless $args, $class;

    $self->_setup_mocks;

    return $self;
}

sub mock_obj { shift->{'__mock'} }

sub _setup_mocks {
    my $self = shift;

    $self->mock_obj->mock('ev3_init' => sub {
        return 1;
    });
}

sub DESTROY {
    my $self = shift;

    $self->mock_obj->unmock_all();
}

1;
