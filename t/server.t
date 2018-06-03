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

use Test::More tests => 19;

my $ev3mock = ev3mock->new();

use_ok('server');

my $server = server->new();

ok($server, 'we have a server obj');

ok($server->can('run'), 'server can run');

my $resp = decode_json($server->process_http_request({
    method => "shouldfail",
}));

ok($resp->{'success'} == 0, 'invalid method returns error');

DEGREES_TO_TACHO_COUNT: {
    ok($server->_degrees_to_tacho_count(90), '_degrees_to_tacho_count returns a value');
}

HELLO: {
    $resp = decode_json($server->process_http_request({
        method => "hello",
    }));

    ok($resp->{'hello'}, 'hello method returned successfully');
}

AVAILABLE_MOTORS: {
    $resp = decode_json($server->process_http_request({
        method => "available_motors",
    }));

    ok($resp->{'success'}, 'available_motors method returned successfully');
}

LARGE_MOTORS: {
    ok(ref $server->_large_motors eq 'ARRAY', '_large_motors returns an array ref');
}

POSITION: {
    $resp = decode_json($server->process_http_request({
        method => "position"
    }));

    ok(!$resp->{'success'}, 'position fails without sequence number');

    $resp = decode_json($server->process_http_request({
        method          => "position",
        sequence_number => 0,
    }));

    ok($resp->{'success'}, 'position method returns successfully');
    ok($resp->{'position'}, 'position, when successful, returns motor position');
}

MOVE: {
    $resp = decode_json($server->process_http_request({
        method => "move"
    }));

    $resp = decode_json($server->process_http_request({
        method  => "move",
        speed   => 200,
    }));

    ok(!$resp->{'success'}, 'move fails with invalid speed');

    my $pos_responses = [ 0, 45, 90, 100 ];
    $ev3mock->reset_mock(get_tacho_position => sub {
        return @$pos_responses > 1 ? shift @$pos_responses : $pos_responses->[0];
    });

    $resp = decode_json($server->process_http_request({
        method  => "move",
        speed   => 100,
    }));

    ok($resp->{'success'}, 'move is successful when valid amount of degrees is passed');
    ok(defined $resp->{'position'}, 'move, when successful, returns the starting position of each motor');

    $ev3mock->reset_mock('get_tacho_position'); # reset get_tacho_position back to default
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

    ok($resp->{'success'}, 'turn is successful when valid speed is passed');
    ok(defined $resp->{'position'}, 'turn, when successful, returns the starting position of each motor');

    $ev3mock->reset_mock('get_tacho_position'); # reset get_tacho_position back to default
}

