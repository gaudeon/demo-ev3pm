#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use server;

die "You must run this with root level privileges" unless $> == 0;

my $server = server->new({
    port => 8080,
});

$server->run();
