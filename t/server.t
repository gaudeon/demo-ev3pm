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

use Test::More tests => 8;

my $ev3mock = ev3mock->new();

use_ok('server');

my $server = server->new();

ok($server, 'we have a server obj');

ok($server->can('run'), 'server can run');

my $resp = decode_json($server->process_request('{
    "method": "shouldfail"
}'));

ok($resp->{'success'} == 0, 'invalid method returns error');

$resp = decode_json($server->process_request('{
    "method": "hello"
}'));

ok($resp->{'hello'}, 'hello method returned successfully');

$resp = decode_json($server->process_request('{
    "method": "move_forward"
}'));

ok(!$resp->{'success'}, 'move_forward fails without level');

$resp = decode_json($server->process_request('{
    "method": "move_forward",
    "level": 5
}'));

ok(!$resp->{'success'}, 'move_forward fails with invalid level');

$resp = decode_json($server->process_request('{
    "method": "move_forward",
    "level": 1
}'));

ok($resp->{'success'}, 'move_forward is successful when correct level is passed');
