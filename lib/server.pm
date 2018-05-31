package server;

use strict;
use warnings;

use parent qw(Net::Server::PreForkSimple);

use Data::Debug;
use JSON::XS;

sub new {
    my $class = shift;
    my $args  = ref $_[0] eq 'HASH' ? $_[0] : {};

    return bless $args, $class;
}

sub process_request {
    my $self = shift;

    my $data;
    if ($self->is_listening) {
        $data = <STDIN>;
    } else {
        $data = shift;
    }

    my $request = eval { decode_json($data) };

    my $response;
    if ($request) {
        if ( eval { $self->validate($request) } ) {
            $response = $self->run_method($request->{'method'} => $request);
        } else {
            $response = {
                success => 0,
                error   => $@ || 'Invalid request',
                request => $request,
            };
        }
    } else {
        $response = {
            success => 0,
            error   => "Parsing Error, $@",
            request => $request,
        };
    }

    $response = encode_json($response);

    if ($self->is_listening) {
        print $response;
    }

    return $response;
}

sub validate {
    my $self    = shift;
    my $request = shift;
    my $method  = ref $request eq 'HASH' ? $request->{'method'} : undef;

    die "Not a valid method\n" unless $method && $self->can("__${method}");

    if (my $method_meta = $self->can("__${method}__meta")) {
        my $meta = $self->$method_meta;

        if (ref $meta eq "HASH") {
            for my $key (keys %$meta) {
                next if $key =~ /^(desc|description|test)$/ix; # special keys for overall description / validation

                next unless ref $meta->{$key} eq 'HASH';

                next unless ref $meta->{$key}->{'test'} eq 'CODE';

                my $success = eval { $meta->{$key}->{'test'}->($request->{$key}) };
                my $error   = $@;

                die $error unless $success;
            }
        }
    }

    return 1;
}

sub run_method {
    my $self    = shift;
    my $method  = shift;
    my $request = shift;

    if (my $method_sub = $self->can("__$method")) {
        my $resp = eval { $self->$method_sub($request) } || $@;

        if (ref $resp) {
            $resp->{'success'} = 1;
            $resp->{'request'} = $request;

            return $resp;
        } else {
            return {
                success => 0,
                error   => $resp,
                request => $request,
            };
        }

    }

    return {
        success => 0,
        error   => 'Method not found',
        request => $request,
    };
}

sub __hello__meta {
    return {
        description => 'Simple hello method for testing purposes',
    };
}

sub __hello {
    my $self    = shift;
    my $request = shift;

    return {
        hello => time,
    };
}

sub __move__meta {
    return {
        description => 'Move the robot forward some distance at some speed',
        degrees => {
            description => 'How far, in degrees of rotation of the motor, to move the robot. Pass -1 to run until a stop movement request is made.',
            test        => sub {
                my $data = shift;

                die "Not valid amount of degrees" unless $data && $data =~ /^[-]?\d+$/;

                die "Not valid amount of degrees" unless $data == -1 || $data >= 0;
            },
        },
        speed => {
            description => 'How fast, between -100 and 100, to move the robot.',
            test        => sub {
                my $data = shift;


                die "Not a valid speed" unless $data && $data =~ /^\d+$/ && $data >= -100 && $data <= 100;
            },
        },
    };
}

sub __move {
    my $self    = shift;
    my $request = shift;

    my $distance = {};
    for my $sn ( @{ $self->_get_large_motors } ) {
        # set the speed
        $self->_call_ev3(set_tacho_duty_cycle_sp => [ $sn, $request->{'speed'} ]);

        # disable ramp up and ramp down
        $self->_call_ev3(set_tacho_ramp_up_sp => [ $sn, 0 ]);
        $self->_call_ev3(set_tacho_ramp_down_sp => [ $sn, 0 ]);

        if ($request->{'degrees'} == -1) {
            # run command
            $self->_call_ev3(set_tacho_command_inx => [ $sn, $ev3::TACHO_RUN_FOREVER ]);

            $distance->{$sn} = 'nil'; # since we move until a stop request we don't know the distance
        } else {
            my $tacho_count = $self->_degrees_to_tacho_count($request->{'degrees'});

            my $start_pos   = $self->_call_ev3(get_tacho_position => [])->[0];
            my $current_pos = $start_pos;

            # set target relative position
            $self->_call_ev3(set_tacho_position_sp => [ $sn, $tacho_count ]);

            # run command
            $self->_call_ev3(set_tacho_command_inx => [ $sn, $ev3::TACHO_RUN_TO_REL_POS ]);

            for (my $loop = 0; $loop < $tacho_count / 2; $loop++) {
                sleep(0.5);
                $current_pos = $self->_call_ev3(get_tacho_position => [])->[0];
                last if $current_pos < $start_pos + $tacho_count;
            }

            my $end_pos = $self->_call_ev3(get_tacho_position => [])->[0];

            $distance->{$sn} = $end_pos - $start_pos;
        }
    }

    return {
        distance => $distance
    };
}

sub __stop__meta {
    return {
        description => 'Stop the robot',
    };
}

sub __stop {
    my $self    = shift;
    my $request = shift;

    for my $sn ( @{ $self->_get_large_motors } ) {
        # run command
        $self->_call_ev3(set_tacho_command_inx => [ $sn, $ev3::TACHO_STOP ]);
    }

    return {};
}

sub run {
    my $self = shift;

    my $retval = $self->SUPER::run(@_);

    $self->{'__listing'}  = 1 if $retval;

    return $retval;
}

sub is_listening { return shift->{'__listening'} }

sub _call_ev3 {
    my $self   = shift;
    my $method = shift;
    my $args   = shift || [];

    $self->{'_ev3_initialized'} //= do {
        ev3::ev3_init() != -1 || die 'failed to initialized ev3';

        while ( ev3::ev3_tacho_init() < 1 ) {
            sleep 1;
        }

        1;
    };

    die 'args are not an arrayref' unless $args && ref $args eq 'ARRAY';

    die 'invalid method' unless $method;

    NO_STRICT_REFS: {
        no strict 'refs';

        die 'invalid method' unless ${'ev3::'}{$method};

        my @result = ( eval { ${'ev3::'}{$method}( @$args ) } );

        return \@result || $@;
    }
}

sub _get_large_motors {
    my $self = shift;

    return $self->{'tacho_lg_motors'} //= do {
        my @motors;

        for ( my $sn = 0; $sn < $ev3::DESC_LIMIT; $sn++ ) {
            my $type = $self->_call_ev3(ev3_tacho_desc_type_inx => [ $sn ])->[0];

            if ( $type == $ev3::LEGO_EV3_L_MOTOR) {
                push @motors, $sn;
            }
        }

        \@motors;
    };
}

sub _degrees_to_tacho_count {
    my $self    = shift;
    my $degrees = shift || die 'degrees required';

    my $ONE_ROTATION = 360; # degrees

    my $tacho_count = $self->_call_ev3(get_tacho_count_per_rot => [])->[0];

    return $degrees * $tacho_count / $ONE_ROTATION;
}

1;
