package server;

use strict;
use warnings;

#use parent qw(Net::Server::PreForkSimple);
use parent qw(Net::Server::HTTP);

use CGI::Lite;
use Data::Debug;
use JSON::XS;
use Data::Dumper;

use ev3;

sub new {
    my $class = shift;
    my $args  = ref $_[0] eq 'HASH' ? $_[0] : {};
    $args->{'port'} //= 8080;

    my $self = bless $args, $class;

    $self->_build_routing;

    return $self;
}

sub is_listening { return shift->{'__listening'} }

sub json { return JSON::XS->new->pretty->utf8->canonical; }

sub run {
    my $self = shift;

    $self->{'__listening'} = 1;

    return $self->SUPER::run({
        port => $self->{'port'},
    });
}

sub process_http_request {
    my $self = shift;
    my $args = shift || {}; # if we are manually calling this method

    $self->_debug_trace("Start process_http_request " . " at line " . __LINE__);

    my ($path, $method, $form);
    if ($self->is_listening) {
        $path   = $ENV{'PATH_INFO'};
        $method = $ENV{'REQUEST_METHOD'};
        $form   = CGI::Lite->new->parse_form_data();
    } else {
        $path   = '/' . $args->{'method'};
        $method = '';
        $form   = $args;
    }

    my $response;
    if (my $route = $self->routes->{$path}) {
        $response = $route->($form);
    }
    else {
        $response = {
            success => 0,
            error   => 'Invalid request',
        };
    }

    if ($form->{'debug'}) {
        $response->{'_request'} //= {
            path   => $path,
            method => $method,
            env    => \%ENV,
            params => $form,
        };

        $response->{'_trace'} //= $self->_debug_trace;
    }

    $response = $self->json->encode($response);

    if ($self->is_listening) {
        print "Content-type: text/json\n\n";
        print $response;
    }

    return $response;
}

sub routes { shift->{'routes'} }

sub validate {
    my $self    = shift;
    my $request = shift;
    my $method  = ref $request eq 'HASH' && $request->{'method'} ? $request->{'method'} : shift;

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

    $self->_debug_trace("Start run_method $method " . " at line " . __LINE__);

    if (my $method_sub = $self->can("__$method")) {
        my $init_info = $self->_ev3_init;

        $self->_debug_trace("EV3 initialized, tacho count $init_info->{tacho_count} " . " at line " . __LINE__) if $init_info;

        my $resp = eval { $self->$method_sub($request) } || $@;

        if (ref $resp) {
            $resp->{'success'} = 1;

            return $resp;
        } else {
            return {
                success => 0,
                error   => $resp,
            };
        }

        $self->_ev3_uninit;
    }

    return {
        success => 0,
        error   => 'Method not found',
    };
}

####---- request methods ----####

sub __hello__meta {
    return {
        description => 'Simple hello method for testing purposes',
    };
}

sub __available_motors__meta {
    return {
        description => 'Returns list of available motors',
    };
}

sub __available_motors {
    my $self    = shift;
    my $request = shift;

    $self->_debug_trace("Start __available_motors " . " at line " . __LINE__);

    my %resp;
    for ( my $i = 0; $i < $ev3::TACHO_DESC__LIMIT_; $i++ ) {
        my $type_inx = ev3::ev3_tacho_desc_type_inx( $i );
        $self->_debug_trace("Tacho type $type_inx found for sequence number $i" . " at line " . __LINE__) if $type_inx != $ev3::TACHO_TYPE__NONE_;

        if ($type_inx != $ev3::TACHO_TYPE__NONE_) {
            my $port_type = ev3::ev3_tacho_type ( $type_inx );
            my $port_name = ev3::ev3_tacho_port_name( $i );
            $resp{'motor - $i'} = {
                sequence_number => $i,
                port_type       => $port_type,
                port_name       => $port_name,
            };
        }
    }

    return \%resp;
}


sub __hello {
    my $self    = shift;
    my $request = shift;

    return {
        hello => time,
    };
}

sub __set_left_motor__meta {
    return {
        description => 'Set the left motor for movement control',
        port        => {
            description => 'The port number the left motor is connected to',
            test        => sub {
                my $data = shift;

                die "Not a valid port" unless defined $data && $data =~ /^\d$/;
            },
        },
    };
}

sub __set_left_motor {
    my $self    = shift;
    my $request = shift;

    my $fh;
    open $fh, '>', $self->_left_motor_file || die 'Could not open left motor file for writing';
    print $fh $request->{'port'};
    close $fh;

    return {
        l_motor => $request->{'port'},
    };
}

sub __set_right_motor__meta {
    return {
        description => 'Set the right motor for movement control',
        port        => {
            description => 'The port number the right motor is connected to',
            test        => sub {
                my $data = shift;

                die "Not a valid port" unless defined $data && $data =~ /^\d$/;
            },
        },
    };
}

sub __set_right_motor {
    my $self    = shift;
    my $request = shift;

    my $fh;
    open $fh, '>', $self->_right_motor_file || die 'Could not open right motor file for writing';
    print $fh $request->{'port'};
    close $fh;

    return {
        r_motor => $request->{'port'},
    };
}

sub __position__meta {
    my $self = shift;

    my ($r_motor, $l_motor) = @{ $self->_get_large_motors };
    $r_motor = defined $r_motor ? $r_motor : -1;
    $l_motor = defined $l_motor ? $l_motor : -1;

    return {
        description => 'Get motor position',
        port        => {
            description => 'The port number the motor is connected to',
            test        => sub {
                my $data = shift;

                die "Not a valid port" unless
                    defined $data &&
                    $data =~ /^\d$/ &&
                    ( $data == $r_motor || $data == $l_motor );
            },
        },
    };
}

sub __position {
    my $self    = shift;
    my $request = shift;

    return {
        position => $self->_call_ev3(get_tacho_position => [ $request->{'port'} ])->[0],
    };
}

sub __move__meta {
    return {
        description => 'Move the robot forward some distance at some speed',
        degrees => {
            description => 'How far, in degrees of rotation of the motor, to move the robot. Pass -1 to run until a stop movement request is made.',
            test        => sub {
                my $data = shift;

                die "Not valid amount of degrees" unless defined $data && $data =~ /^[-]?\d+$/;

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

    my $position = {};
    for my $sn ( @{ $self->_get_large_motors } ) {
        # set the speed
        $self->_call_ev3(set_tacho_duty_cycle_sp => [ $sn, $request->{'speed'} ]);

        # disable ramp up and ramp down
        $self->_call_ev3(set_tacho_ramp_up_sp => [ $sn, 0 ]);
        $self->_call_ev3(set_tacho_ramp_down_sp => [ $sn, 0 ]);

        # track the starting position of each motor
        $position->{$sn} = $self->_call_ev3(get_tacho_position => [ $sn ])->[0];

        if ($request->{'degrees'} == -1) {
            # run command
            $self->_call_ev3(set_tacho_command_inx => [ $sn, $ev3::TACHO_RUN_FOREVER ]);

            $position->{$sn} = 'nil'; # since we move until a stop request we don't know the distance
        } else {
            my $tacho_count = $self->_degrees_to_tacho_count($request->{'degrees'});

            # set target relative position
            $self->_call_ev3(set_tacho_position_sp => [ $sn, $tacho_count ]);

            # run command
            $self->_call_ev3(set_tacho_command_inx => [ $sn, $ev3::TACHO_RUN_TO_REL_POS ]);
        }
    }

    return {
        position => $position,
    };
}

sub __turn__meta {
    return {
        description => 'Turn the robot some amount based on motor degrees and at some speed',
        degrees => {
            description => 'How far, in degrees of rotation of the motor, to turn the robot.',
            test        => sub {
                my $data = shift;

                die "Not valid amount of degrees" unless defined $data && $data =~ /^\d+$/;
            },
        },
        speed => {
            description => 'How fast, between -100 and 100, to move the robot.',
            test        => sub {
                my $data = shift;

                die "Not a valid speed" unless defined $data && $data =~ /^\d+$/ && $data >= -100 && $data <= 100;
            },
        },
    };
}

sub __turn {
    my $self    = shift;
    my $request = shift;

    my $position = {};
    my $speed = $request->{'speed'}; # alternate speed between positive and negative values for each motor
    for my $sn ( @{ $self->_get_large_motors } ) {
        # set the speed
        $self->_call_ev3(set_tacho_duty_cycle_sp => [ $sn, $speed ]);

        # disable ramp up and ramp down
        $self->_call_ev3(set_tacho_ramp_up_sp => [ $sn, 0 ]);
        $self->_call_ev3(set_tacho_ramp_down_sp => [ $sn, 0 ]);

        # track the starting position of each motor
        $position->{$sn} = $self->_call_ev3(get_tacho_position => [ $sn ])->[0];

        my $tacho_count = $self->_degrees_to_tacho_count($request->{'degrees'});

        # set target relative position
        $self->_call_ev3(set_tacho_position_sp => [ $sn, $tacho_count ]);

        # run command
        $self->_call_ev3(set_tacho_command_inx => [ $sn, $ev3::TACHO_RUN_TO_REL_POS ]);

        # since we are turning speed must be negated so that the next motors speed is opposite this motor's speed
        $speed = -$speed;
    }

    return {
        position => $position,
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

####---- private subs ----####

sub _debug_trace {
    my $self = shift;
    my $line = shift;

    $self->{'__trace'} //= [];

    push @{$self->{'__trace'}}, $line if $line;

    return $self->{'__trace'};
}

sub _build_routing {
    my $self = shift;

    my $method_map = $self->_map_request_endpoints;

    $self->{'routes'}{'/'} = sub {
        my $form = shift || {};

        my %methods;

        for my $method (keys %$method_map) {
            $methods{"/$method"} = $method_map->{$method}->{'meta'};
        }

        $methods{"/"} = {
            description => "Returns the list of available methods.",
        };

        return \%methods;
    };

    for my $method (keys %$method_map) {
        $self->{'routes'}{"/$method"} = sub {
            my $form = shift || {};

            my $response;

            if ( eval { $self->validate($form => $method) } ) {
                $response = $self->run_method($method => $form);
            } else {
                $response = {
                    success => 0,
                    error   => $@ || 'Invalid request',
                };
            }

            return $response;
        };
    }
}

sub _map_request_endpoints {
    my $self = shift;

    my %map;

    NO_STRICT_REFS: {
        no strict 'refs';

        for my $symbol (keys %{__PACKAGE__ . '::'}) {
            next unless $symbol =~ /^(.+)__meta$/;

            my $request_sub = $1;
            my $meta_sub    = $symbol;
            my $request     = $request_sub;
            $request        =~ s/^__//;

            my $request_code = *{${__PACKAGE__ . '::'}{$request_sub}}{CODE};
            my $meta_code    = *{${__PACKAGE__ . '::'}{$meta_sub}}{CODE};

            next unless $request_code && $meta_code;

            $map{$request} = {
                code => $request_code,
                meta => $self->_scrub_meta($self->$meta_code),
            };
        }
    }

    return \%map;
}

sub _scrub_meta {
    my $self = shift;
    my $data = shift;

    return $data unless ref $data eq 'HASH';

    for my $key (keys %$data) {
        if (ref $data->{$key} && ref $data->{$key} ne 'HASH') {
            delete $data->{$key};
            next;
        }

        $data->{$key} = $self->_scrub_meta($data->{$key});
    }

    return $data;
}

sub _tacho_sys_dir { $ev3::TACHO_DIR }

sub _ev3_init {
    my $self = shift;

    return $self->{'_ev3_init'} //= do {
        ev3::ev3_init() != -1 || die 'failed to initialized ev3';

        my $tacho_count;
        while ( $tacho_count = ev3::ev3_tacho_init() < 1 ) {
            sleep 1;
        }

        {
            tacho_count => $tacho_count,
        };
    };
}

sub _ev3_uninit {
    my $self = shift;

    if ($self->{'_ev3_init'}) {
        ev3::ev3_unint();
    }
}

sub _call_ev3 {
    my $self   = shift;
    my $method = shift;
    my $args   = shift || [];

    die 'args are not an arrayref' unless $args && ref $args eq 'ARRAY';

    die 'invalid method' unless $method;

    NO_STRICT_REFS: {
        no strict 'refs';

        die 'invalid method' unless ${'ev3::'}{$method};

        my @result = ( eval { ${'ev3::'}{$method}( @$args ) } );

        return \@result || $@;
    }
}

sub _left_motor_file { './LEFTMOTOR.txt' }

sub _right_motor_file { './RIGHTMOTOR.txt' }

sub _has_large_motors_set {
    my $self = shift;

    return defined $self->_get_large_motors->[0] && defined $self->_get_large_motors->[1];
}

sub _get_large_motors {
    my $self = shift;

    return [] unless -f $self->_left_motor_file && -f $self->_right_motor_file;

    return $self->{'_large_motors'} //= do {
        my ($l_motor, $r_motor);

        my $fh;
        open $fh, '<', $self->_left_motor_file || die 'Could not open left motor file for reading';
        $l_motor = <$fh>;
        close $fh;

        die 'Left motor not defined' unless defined $l_motor;

        open $fh, '<', $self->_right_motor_file || die 'Could not open right motor file for reading';
        $r_motor = <$fh>;
        close $fh;

        die 'Right motor not defined' unless defined $r_motor;

        [ $l_motor, $r_motor ];
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
