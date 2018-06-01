#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    use FindBin qw($Bin);

    use lib "$Bin/lib";
    use lib "$Bin/../lib";
    $ENV{LD_LIBRARY_PATH} //= "";
    $ENV{LD_LIBRARY_PATH} = "$Bin/../lib:$ENV{LD_LIBRARY_PATH}";
}

use Data::Debug;
use JSON::XS;

use ev3mock;

use Test::More tests => 21;

my $ev3mock = ev3mock->new();

use_ok('server');

my $server = server->new();

ok($server, 'we have a server obj');

ok($server->can('run'), 'server can run');

my $resp = decode_json($server->process_request('{
    "method": "shouldfail"
}'));

ok($resp->{'success'} == 0, 'invalid method returns error');

CALL_EV3: {
    eval { $server->_call_ev3(this_should_fail => []) };

    ok($@, '_call_ev3 dies on invalid methods');

    my $resp = $server->_call_ev3(ev3_init => []);

    ok($resp && $server->{'_ev3_initialized'}, '_call_ev3 initializes ev3');
}

DEGREES_TO_TACHO_COUNT: {
    ok($server->_degrees_to_tacho_count(90), '_degrees_to_tacho_count returns a value');
}

GET_LARGE_MOTORS: {
    ok($server->_get_large_motors, '_get_large_motors returns a value');
}

HELLO: {
    $resp = decode_json($server->process_request('{
        "method": "hello"
    }'));

    ok($resp->{'hello'}, 'hello method returned successfully');
}

MOVE: {
    $resp = decode_json($server->process_request('{
        "method": "move"
    }'));

    ok(!$resp->{'success'}, 'move fails without degrees');

    $resp = decode_json($server->process_request('{
        "method": "move",
        "degrees": -2
    }'));

    ok(!$resp->{'success'}, 'move fails with invalid degrees');

    $resp = decode_json($server->process_request('{
        "method": "move",
        "degrees": -1,
        "speed": 200
    }'));

    ok(!$resp->{'success'}, 'move fails with invalid speed');

    my $pos_responses = [ 0, 45, 90, 100 ];
    $ev3mock->reset_mock(get_tacho_position => sub {
        return @$pos_responses > 1 ? shift @$pos_responses : $pos_responses->[0];
    });

    $resp = decode_json($server->process_request('{
        "method": "move",
        "degrees": 90,
        "speed": 100
    }'));

    ok($resp->{'success'}, 'move is successful when valid amount of degrees is passed');
    ok(defined $resp->{'distance'}, 'move, when successful, returns a distance traveled');

    $ev3mock->reset_mock('get_tacho_position'); # reset get_tacho_position back to default

    $resp = decode_json($server->process_request('{
            "method": "move",
            "degrees": -1,
            "speed": 100
    }'));

    ok($resp->{'success'}, 'move is successful when unlimited value for degrees is passed');
}

STOP: {
    $resp = decode_json($server->process_request('{
        "method": "stop"
    }'));

    ok($resp->{'success'}, 'stop method returned successfully');
}

TURN: {
    $resp = decode_json($server->process_request('{
        "method": "turn"
    }'));

    ok(!$resp->{'success'}, 'turn fails without degrees');

    $resp = decode_json($server->process_request('{
        "method": "turn",
        "degrees": -2
    }'));

    ok(!$resp->{'success'}, 'turn fails with invalid degrees');

    $resp = decode_json($server->process_request('{
        "method": "turn",
        "degrees": 90,
        "speed": 200
    }'));

    ok(!$resp->{'success'}, 'turn fails with invalid speed');

    my $pos_responses = [ 0, 45, 90, 100 ];
    $ev3mock->reset_mock(get_tacho_position => sub {
        return @$pos_responses > 1 ? shift @$pos_responses : $pos_responses->[0];
    });

    $resp = decode_json($server->process_request('{
        "method": "turn",
        "degrees": 90,
        "speed": 100
    }'));

    ok($resp->{'success'}, 'turn is successful when valid amount of degrees is passed');
    ok(defined $resp->{'distance'}, 'turn, when successful, returns a distance traveled');

    $ev3mock->reset_mock('get_tacho_position'); # reset get_tacho_position back to default
}

