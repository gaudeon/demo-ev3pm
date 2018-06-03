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

$ev3::DESC_LIMIT = 1; # set to only have one port

sub new  {
    my $class = shift;
    my $args  = $_[0] && ref $_[0] eq 'HASH' ? $_[0] : {};

    $args->{'__mock'} = Test::MockModule->new('ev3');

    my $self = bless $args, $class;

    $self->_setup_mocks;

    return $self;
}

sub mock_obj { shift->{'__mock'} }

sub reset_mock {
    my $self = shift;
    my $sub  = shift;
    my $code = shift || $self->_mock_defaults->{$sub} || sub {};

    die 'not a code reference' unless ref $code eq 'CODE';

    $self->mock_obj->mock($sub => $code);
}

sub _setup_mocks {
    my $self = shift;

    my $defaults = $self->_mock_defaults();

    for my $sub (keys %$defaults) {
        $self->mock_obj->mock($sub => $defaults->{$sub});
    }
}

sub _mock_defaults {
    my $self = shift;

    return {
        ev3_init => sub {
            return 1;
        },

        ev3_tacho_init => sub {
            return 1;
        },

        get_tacho_count_per_rot => sub {
            return 360;
        },

        get_tacho_position => sub {
            return 1;
        },

        set_tacho_duty_cycle_sp => sub {
            return 1;
        },

        set_tacho_ramp_up_sp => sub {
            return 1;
        },

        set_tacho_ramp_down_sp => sub {
            return 1;
        },

        ev3_search_tacho => sub {
            return (1, 1234);
        },

        set_tacho_command_inx => sub {
            return 1;
        },

        ev3_tacho_desc_type_inx => sub {
            return $ev3::LEGO_EV3_L_MOTOR;
        },

        ev3_tacho_type => sub {
            return 'type';
        },

        ev3_tacho_port_name => sub {
            return 'name';
        },
    };
}

sub DESTROY {
    my $self = shift;

    $self->mock_obj->unmock_all();
}

1;
