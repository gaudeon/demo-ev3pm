package server;

use strict;
use warnings;

#use parent qw(Net::Server::PreForkSimple);
use parent qw(Net::Server::HTTP);

use CGI::Lite;
use Data::Debug;
use JSON::XS;
use Data::Dumper;
use File::Spec;

use ev3;

sub new {
    my $class = shift;
    my $args  = ref $_[0] eq 'HASH' ? $_[0] : {};
    $args->{'port'} //= 8080;
    $args->{'min_servers'} //= 1;
    $args->{'max_servers'} //= 1;
    $args->{'min_spare_servers'} //= 0;
    $args->{'max_spare_servers'} //= 0;

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
        port              => $self->{'port'},
        min_servers       => $self->{'min_servers'},
        max_servers       => $self->{'max_servers'},
        min_spare_servers => $self->{'min_spare_servers'},
        max_spare_servers => $self->{'max_spare_servers'},
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

sub __hello {
    my $self    = shift;
    my $request = shift;

    return {
        hello => time,
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

            push @{$resp{"motors"}}, {
                sequence_number => $i,
                port_type       => $port_type,
                port_name       => $port_name,
            };
        }
    }

    return \%resp;
}

sub __max_speed__meta {
    my $self = shift;

    return {
        description => 'Get motor max speed in tacho counds per second',
        sequence_number  => {
            description => 'The sequence number the motor is identified as',
            test        => sub {
                my $data = shift;

                die "Not a valid sequence_number" unless defined $data && $data =~ /^\d+$/;
            },
        },
    };
}

sub __max_speed {
    my $self    = shift;
    my $request = shift;
    my $sn      = $request->{'sequence_number'};

    my $max_speed_file = File::Spec->catfile($self->_tacho_sys_dir, "motor$sn", 'max_speed');

    open my $fh, '<', $max_speed_file || die "Could not open $max_speed_file $1";
    my @lines = <$fh>;
    close $fh;

    my $data = join "\n", @lines;
    chomp $data;

    return {
        speed => $data,
    };
}

sub __position__meta {
    my $self = shift;

    return {
        description => 'Get motor position',
        sequence_number  => {
            description => 'The sequence number the motor is identified as',
            test        => sub {
                my $data = shift;

                die "Not a valid sequence_number" unless defined $data && $data =~ /^\d+$/;
            },
        },
    };
}

sub __position {
    my $self    = shift;
    my $request = shift;

    my $position = ev3::get_tacho_position($request->{'sequence_number'});

    return {
        position => $position,
    };
}

sub __move__meta {
    return {
        description => 'Move the robot forward some distance at some speed',
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

    my @motors;
    for my $sn ( @{ $self->_large_motors } ) {
        $self->_debug_trace("Setting movement for motor $sn" . " at line " . __LINE__);

        # set the speed
        ev3::set_tacho_duty_cycle_sp( $sn, $request->{'speed'} );
        $self->_debug_trace("Speed set to $request->{speed} for motor $sn" . " at line " . __LINE__);

        # disable ramp up and ramp down
        ev3::set_tacho_ramp_up_sp( $sn, 0 );
        ev3::set_tacho_ramp_down_sp( $sn, 0 );
        $self->_debug_trace("Ramp up / Ramp down set to zero for motor $sn" . " at line " . __LINE__);

        # track the starting position of each motor
        my $position = ev3::get_tacho_position( $sn );
        $self->_debug_trace("Current position at $position for motor $sn" . " at line " . __LINE__);

        ev3::set_tacho_command_inx( $sn, $ev3::TACHO_RUN_FOREVER );

        push @motors, {
            sequence_number => $sn,
            position        => $position,
        };
    }

    return {
        motors => \@motors,
    };
}

sub __turn__meta {
    return {
        description => 'Turn the robot some amount based on motor degrees and at some speed',
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
    for my $sn ( @{ $self->_large_motors } ) {
        # set the speed
        ev3::set_tacho_duty_cycle_sp( $sn, $speed );

        # disable ramp up and ramp down
        ev3::set_tacho_ramp_up_sp( $sn, 0 );
        ev3::set_tacho_ramp_down_sp( $sn, 0 );

        # track the starting position of each motor
        $position->{$sn} = ev3::get_tacho_position( $sn );

        # run command
        ev3::set_tacho_command_inx( $sn, $ev3::TACHO_RUN_FOREVER );

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

    for my $sn ( @{ $self->_large_motors } ) {
        # run command
        ev3::set_tacho_command_inx( $sn, $ev3::TACHO_STOP );
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

        +{
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

sub _large_motors {
    my $self = shift;

    return $self->{'_large_motors'} //= do {
        my @motors;
        for ( my $i = 0; $i < $ev3::TACHO_DESC__LIMIT_; $i++ ) {
            my $type_inx = ev3::ev3_tacho_desc_type_inx( $i );

            push @motors, $i if $type_inx != $ev3::TACHO_TYPE__NONE_;
        }

        \@motors;
    };
}

sub _degrees_to_tacho_count {
    my $self    = shift;
    my $degrees = shift || die 'degrees required';

    my $ONE_ROTATION = 360; # degrees

    my $tacho_count = ev3::get_tacho_count_per_rot();

    return $degrees * $tacho_count / $ONE_ROTATION;
}

1;
