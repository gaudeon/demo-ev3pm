#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use server;

my $server = server->new({
    port => 8080,
});

$server->run();
