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

use Test::More tests => 34;

my $ev3mock = ev3mock->new();

use_ok('server');

my $server = server->new();

ok($server, 'we have a server obj');

ok($server->can('run'), 'server can run');

my $resp = decode_json($server->process_http_request({
    method => "shouldfail",
}));

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

CLEAR_MOTOR_FILES: {
    unlink $server->_left_motor_file;
    unlink $server->_right_motor_file;

    ok(!-f $server->_left_motor_file, "left motor file does not exist");
    ok(!-f $server->_right_motor_file, "right motor file does not exist");
}

HELLO: {
    $resp = decode_json($server->process_http_request({
        method => "hello",
    }));

    ok($resp->{'hello'}, 'hello method returned successfully');
}

HAS_LARGE_MOTORS_SET_FALSE: {
    ok(! $server->_has_large_motors_set, '_has_large_motors_set is false');
}

SET_LEFT_MOTOR: {
    $resp = decode_json($server->process_http_request({
        method => "set_left_motor",
    }));

    ok(!$resp->{'success'}, 'set_left_motor fails without port');

    $resp = decode_json($server->process_http_request({
        method => "set_left_motor",
        port   => 0,
    }));

    ok($resp->{'success'}, 'set_left_motor method returned successfully');
}

SET_RIGHT_MOTOR: {
    $resp = decode_json($server->process_http_request({
        method => "set_right_motor",
    }));

    ok(!$resp->{'success'}, 'set_right_motor fails without port');

    $resp = decode_json($server->process_http_request({
        method => "set_right_motor",
        port   => 0,
    }));

    ok($resp->{'success'}, 'set_right_motor method returned successfully');
}

HAS_LARGE_MOTORS_SET_TRUE: {
    ok($server->_has_large_motors_set, '_has_large_motors_set is true');
}

GET_LARGE_MOTORS: {
    ok(ref $server->_get_large_motors eq 'ARRAY', '_get_large_motors returns an array ref');
    ok(defined $server->_get_large_motors->[0], '_get_large_motors l_motor value is defined');
    ok(defined $server->_get_large_motors->[1], '_get_large_motors r_motor value is defined');
}

POSITION: {
    $resp = decode_json($server->process_http_request({
        method => "position"
    }));

    ok(!$resp->{'success'}, 'position fails without port');

    $resp = decode_json($server->process_http_request({
        method => "position",
        port   => 0,
    }));

    ok($resp->{'success'}, 'position method returns successfully');
    ok($resp->{'position'}, 'position, when successful, returns motor position');
}

MOVE: {
    $resp = decode_json($server->process_http_request({
        method => "move"
    }));

    ok(!$resp->{'success'}, 'move fails without degrees');

    $resp = decode_json($server->process_http_request({
        method  => "move",
        degrees => -2,
    }));

    ok(!$resp->{'success'}, 'move fails with invalid degrees');

    $resp = decode_json($server->process_http_request({
        method  => "move",
        degrees => -1,
        speed   => 200,
    }));

    ok(!$resp->{'success'}, 'move fails with invalid speed');

    my $pos_responses = [ 0, 45, 90, 100 ];
    $ev3mock->reset_mock(get_tacho_position => sub {
        return @$pos_responses > 1 ? shift @$pos_responses : $pos_responses->[0];
    });

    $resp = decode_json($server->process_http_request({
        method  => "move",
        degrees => 90,
        speed   => 100,
    }));

    ok($resp->{'success'}, 'move is successful when valid amount of degrees is passed');
    ok(defined $resp->{'position'}, 'move, when successful, returns the starting position of each motor');

    $ev3mock->reset_mock('get_tacho_position'); # reset get_tacho_position back to default

    $resp = decode_json($server->process_http_request({
            method  => "move",
            degrees => -1,
            speed   => 100,
    }));

    ok($resp->{'success'}, 'move is successful when unlimited value for degrees is passed');
}

STOP: {
    $resp = decode_json($server->process_http_request({
        method => "stop",
    }));

    ok($resp->{'success'}, 'stop method returned successfully');
}

TURN: {
    $resp = decode_json($server->process_http_request({
        method => "turn",
    }));

    ok(!$resp->{'success'}, 'turn fails without degrees');

    $resp = decode_json($server->process_http_request({
        method  => "turn",
        degrees => -2,
    }));

    ok(!$resp->{'success'}, 'turn fails with invalid degrees');

    $resp = decode_json($server->process_http_request({
        method  => "turn",
        degrees => 90,
        speed   => 200,
    }));

    ok(!$resp->{'success'}, 'turn fails with invalid speed');

    my $pos_responses = [ 0, 45, 90, 100 ];
    $ev3mock->reset_mock(get_tacho_position => sub {
        return @$pos_responses > 1 ? shift @$pos_responses : $pos_responses->[0];
    });

    $resp = decode_json($server->process_http_request({
        method  => "turn",
        degrees => 90,
        speed   => 100,
    }));

    ok($resp->{'success'}, 'turn is successful when valid amount of degrees is passed');
    ok(defined $resp->{'position'}, 'turn, when successful, returns the starting position of each motor');

    $ev3mock->reset_mock('get_tacho_position'); # reset get_tacho_position back to default
}

