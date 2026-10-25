#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper 'detect_warnings';
use JSONSchema::Validator;
use JSONSchema::Validator::Util ();

BEGIN {
    unless ($ENV{ACCEPTANCE_TESTING}) {
        print qq{1..0 # SKIP these tests are for testing by the developer\n};
        exit
    }
}

unless (eval { require Test::JSON::Schema::Acceptance; 1; }) {
    plan skip_all => 'Test::JSON::Schema::Acceptance is not installed'
}

binmode Test::More->builder->$_, ':encoding(UTF-8)'
    for qw(output failure_output todo_output);

for my $validator_class (@{$JSONSchema::Validator::JSON_SCHEMA_VALIDATORS}) {
    my $specification = lc($validator_class->SPECIFICATION);
    my $accepter = Test::JSON::Schema::Acceptance->new(
        specification => $specification,
        include_optional => 0,
    );

    my $ua_get = sub {
        my $uri = shift;
        my $path = $accepter->additional_resources;
        $uri =~ s/^http:\/\/localhost:1234/file:\/\/$path/;
        return JSONSchema::Validator::Util::get_content($uri);
    };

    $accepter->acceptance(
        validate_data => sub {
            my ($schema, $input_data) = @_;
            my ($result, $errors) = JSONSchema::Validator->new(
                schema => $schema,
                validate_schema => 0,
                specification => $specification,
                scheme_handlers => {'http' => $ua_get}
            )->validate_schema($input_data);
            return $result;
        }
    );
}

ok detect_warnings() == 0, 'no warnings';
done_testing;
