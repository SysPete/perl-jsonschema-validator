#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/test_dir detect_warnings errors_text/;
use JSON::PP ();
use JSONSchema::Validator;
use JSONSchema::Validator::Util qw( load_schema );

for my $validator_class (@{$JSONSchema::Validator::OAS_VALIDATORS}) {
    my $version = lc($validator_class->SPECIFICATION);

    my $resource = 'file://' . test_dir("/data/validator_oas/${version}-schema.json");
    my $instance_file_ok = test_dir("/data/validator_oas/${version}-ok.json");
    my $instance_file_wrong = test_dir("/data/validator_oas/${version}-wrong.json");

    my $instance_ok = load_schema($instance_file_ok);
    my $instance_wrong = load_schema($instance_file_wrong);

    my $schema_file = test_dir("/data/validator_oas/${version}-schema.json");
    my $schema = load_schema($schema_file);

    my @validators = (
        JSONSchema::Validator->new(resource => $resource),
        JSONSchema::Validator->new(schema => $schema),
        JSONSchema::Validator->new(schema => $schema, specification => $version)
    );

    for my $validator (@validators) {
        my ($result, $errors, $warnings) = $validator->validate_request(%{$instance_ok->{request}});
        is $result, 1, "check validation request $instance_file_ok";
        ok @$errors == 0, "check validation request errors $instance_file_ok";
        ok @$warnings == 0, "check validation request warnings $instance_file_ok";

        ($result, $errors, $warnings) = $validator->validate_response(%{$instance_ok->{response}});
        is $result, 1, "check validation response $instance_file_ok";
        ok @$errors == 0, "check validation response errors $instance_file_ok";
        ok @$warnings == 0, "check validation response warnings $instance_file_ok";

        ($result, $errors, $warnings) = $validator->validate_request(%{$instance_wrong->{request}});
        is $result, 0, "check validation request $instance_file_wrong";
        ok @$errors > 0, "check validation request errors $instance_file_wrong";
        ok @$warnings == 0, "check validation request warnings $instance_file_wrong";

        ($result, $errors, $warnings) = $validator->validate_response(%{$instance_wrong->{response}});
        is $result, 0, "check validation response $instance_file_wrong";
        ok @$errors > 0, "check validation response errors $instance_file_wrong";
        ok @$warnings == 0, "check validation response warnings $instance_file_wrong";
    }

    # data/wrong-schema/$version.json
    $resource = 'file://' . test_dir("/data/validator_oas/wrong-schema/${version}.json");
    my $result = eval { my $validator = JSONSchema::Validator->new(resource => $resource) };
    is $result, undef, "check exception on wrong meta schema validation of $resource";
    like $@, qr/invalid schema/, "check exception message on wrong meta schema validation of $resource";
}

{
    my $validator = JSONSchema::Validator->new(
        specification => 'OAS30',
        schema => {
            openapi => '3.0.0',
            info => { title => 'enum', version => '1' },
            paths => {
                '/enum' => {
                    get => {
                        parameters => [
                            { name => 'int', in => 'query', schema => { type => 'integer', enum => [1, 2] } },
                            { name => 'bool', in => 'query', schema => { type => 'boolean', enum => [JSON::PP::true] } },
                        ],
                        responses => { 200 => { description => 'ok' } },
                    },
                },
            },
        },
    );

    my $request = sub {
        my ($name, $value) = @_;
        return $validator->validate_request(
            method => 'get',
            openapi_path => '/enum',
            parameters => { query => { $name => $value } },
        );
    };

    my ($result, $errors) = $request->(int => '1');
    is $result, 1, 'OAS30 query "1" is in integer enum [1, 2]'
        or diag errors_text($errors);

    ($result, $errors) = $request->(int => '3');
    is $result, 0, 'OAS30 query "3" is not in integer enum [1, 2]';
    like errors_text($errors), qr/instance is not of enums/, 'OAS30 integer enum says why';

    ($result, $errors) = $request->(bool => '1');
    is $result, 1, 'OAS30 query "1" is in boolean enum [true]'
        or diag errors_text($errors);

    ($result, $errors) = $request->(bool => '0');
    is $result, 0, 'OAS30 query "0" is not in boolean enum [true]';
    like errors_text($errors), qr/instance is not of enums/, 'OAS30 boolean enum says why';
}

ok detect_warnings() == 0, 'no warnings';
done_testing;
