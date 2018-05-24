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
        hello   => time,
    };
}

sub __move_forward__meta {
    return {
        description => 'Move the robot forward some distance',
        level => {
            description => 'How far relatively to move the robot',
            test        => sub {
                my $data = shift;

                die "Not a valid level\n" unless $data && $data =~ /^[1-4]$/;
            },
        },
    };
}

sub __move_forward {
    my $self = shift;

    return {};
}

sub run {
    my $self = shift;

    my $retval = $self->SUPER::run(@_);

    $self->{'__listing'}  = 1 if $retval;

    return $retval;
}

sub is_listening { return shift->{'__listening'} }

1;
