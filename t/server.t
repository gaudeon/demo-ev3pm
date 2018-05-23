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

use ev3mock;

use Test::More tests => 1;

my $ev3mock = ev3mock->new();

use_ok('server');

#my $server = server->new();

#ok($server, 'we have a server obj');

#ok($server->start(), 'server started successfully');
