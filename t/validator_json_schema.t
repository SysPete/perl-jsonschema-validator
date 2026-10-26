#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/test_dir detect_warnings/;
use JSONSchema::Validator;
use JSONSchema::Validator::Util qw( load_schema );

for my $validator_class (@{$JSONSchema::Validator::JSON_SCHEMA_VALIDATORS}) {
    my $draft = lc($validator_class->SPECIFICATION);
    # data/validator_json_schema/$draft-1-schema.json
    my $resource = 'file://' . test_dir("/data/validator_json_schema/${draft}-1-schema.json");
    my $instance_file_ok = test_dir("/data/validator_json_schema/${draft}-1-ok.json");
    my $instance_file_wrong = test_dir("/data/validator_json_schema/${draft}-1-wrong.json");

    my $instance_ok = load_schema($instance_file_ok);
    my $instance_wrong = load_schema($instance_file_wrong);

    my $validator = JSONSchema::Validator->new(resource => $resource);

    my ($result, $errors) = $validator->validate_schema($instance_ok);
    is $result, 1, "check validation $instance_file_ok";
    ok @$errors == 0, "check validation errors $instance_file_ok";

    ($result, $errors) = $validator->validate_schema($instance_wrong);
    is $result, 0, "check validation $instance_file_wrong";
    ok @$errors > 0, "check validation errors $instance_file_wrong";

    my $schema_file = test_dir("/data/validator_json_schema/${draft}-1-schema.json");
    my $schema = load_schema($schema_file);

    ## with schema and without specification
    $validator = JSONSchema::Validator->new(schema => $schema);

    ($result, $errors) = $validator->validate_schema($instance_ok);
    is $result, 1, "check validation $instance_file_ok";
    ok @$errors == 0, "check validation errors $instance_file_ok";

    ($result, $errors) = $validator->validate_schema($instance_wrong);
    is $result, 0, "check validation $instance_file_wrong";
    ok @$errors > 0, "check validation errors $instance_file_wrong";

    # data/validator_json_schema/$draft-2-schema.json
    $resource = 'file://' . test_dir("/data/validator_json_schema/${draft}-2-schema.json");
    $instance_file_ok = test_dir("/data/validator_json_schema/${draft}-2-ok.json");
    $instance_file_wrong = test_dir("/data/validator_json_schema/${draft}-2-wrong.json");

    $instance_ok = load_schema($instance_file_ok);
    $instance_wrong = load_schema($instance_file_wrong);

    ## without specification
    $result = eval { $validator = JSONSchema::Validator->new(resource => $resource) };
    is $result, undef, "check exception on unknown specification of $resource";
    like $@, qr/unknown specification/, "check exception message on unknown specification of $resource";

    ## with specification
    $validator = JSONSchema::Validator->new(resource => $resource, specification => $draft);

    ($result, $errors) = $validator->validate_schema($instance_ok);
    is $result, 1, "check validation $instance_file_ok";
    ok @$errors == 0, "check validation errors $instance_file_ok";

    ($result, $errors) = $validator->validate_schema($instance_wrong);
    is $result, 0, "check validation $instance_file_wrong";
    ok @$errors > 0, "check validation errors $instance_file_wrong";

    $schema_file = test_dir("/data/validator_json_schema/${draft}-2-schema.json");
    $schema = load_schema($schema_file);

    ## with schema and without specification
    $result = eval { $validator = JSONSchema::Validator->new(schema => $schema) };
    is $result, undef, "check exception on unknown specification by schema of resource $resource";
    like $@, qr/unknown specification/, "check exception message on unknown specification by schema of resource $resource";

    ## with schema and specification
    $validator = JSONSchema::Validator->new(schema => $schema, specification => $draft);

    ($result, $errors) = $validator->validate_schema($instance_ok);
    is $result, 1, "check validation $instance_file_ok";
    ok @$errors == 0, "check validation errors $instance_file_ok";

    ($result, $errors) = $validator->validate_schema($instance_wrong);
    is $result, 0, "check validation $instance_file_wrong";
    ok @$errors > 0, "check validation errors $instance_file_wrong";

    # data/wrong-schema/$draft.json
    $resource = 'file://' . test_dir("/data/validator_json_schema/wrong-schema/${draft}.json");
    $result = eval { my $validator = JSONSchema::Validator->new(resource => $resource) };
    is $result, undef, "check exception on wrong meta schema validation of $resource";
    like $@, qr/invalid schema/, "check exception message on wrong meta schema validation of $resource";
}

subtest 'validate_schema restores the scope after an exception' => sub {
    my $validator = JSONSchema::Validator::Draft7->new(base_uri => 'http://e.invalid/a.json', schema => {});

    my $depth = @{$validator->scopes};
    for my $call (1 .. 3) {
        eval { $validator->validate_schema(1, schema => 'not a schema', scope => 'http://e.invalid/x.json') };
        isnt $@, '', "call $call dies";
        is scalar @{$validator->scopes}, $depth, "scope stack depth after call $call";
    }
};

subtest 'a root $ref into its own definitions' => sub {
    # unbounded recursion ends in an "Out of memory!" no eval can catch, so stop at the first warning
    my $record = $SIG{__WARN__};
    local $SIG{__WARN__} = sub { die "deep recursion\n" if $_[0] =~ /^Deep recursion/; $record->(@_) };

    my $validator = eval { JSONSchema::Validator->new(schema => {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        '$ref' => '#/definitions/x',
        definitions => { x => { type => 'integer' } } }) };
    is $@, '', 'new does not die';

    my ($result, $errors) = eval { $validator->validate_schema(5) };
    is $result, 1, '5 is an integer' or diag $@ || join "\n", map { $_->message } @{$errors // []};
    ($result, $errors) = eval { $validator->validate_schema('a') };
    is $result, 0, '"a" is not an integer';
    like join("\n", map { $_->message } @{$errors // []}), qr/type mismatch/, 'says why';
};

subtest 'document_get with cached_only stops at a $ref it would have to load' => sub {
    my @loaded;
    my $validator = JSONSchema::Validator::Draft7->new(
        schema => {},
        base_uri => 'http://e.invalid/root.json',
        documents => { 'http://e.invalid/other.json' => { c => { '$ref' => 'urn:example:x' } } },
        scheme_handlers => { urn => sub { push @loaded, "$_[0]"; return (\'{"b":{"type":"string"}}', 'JSON') } });
    my $document = {
        local => { '$ref' => 'urn:example:x' },
        via_cache => { '$ref' => 'other.json#/c' },
        bundled => { '$ref' => 'http://json-schema.org/draft-07/schema#/definitions/nonNegativeInteger' },
    };
    my $pointer = JSONSchema::Validator::JSONPointer->new(
        scope => 'http://e.invalid/doc.json', value => $document, validator => $validator);

    my $got = $pointer->document_get('/local/b', cached_only => 1);
    is_deeply $got->value, { '$ref' => 'urn:example:x' }, 'stops at the $ref';
    is $got->scope, 'http://e.invalid/doc.json', 'with the scope it is in';

    $got = $pointer->document_get('/via_cache/b', cached_only => 1);
    is_deeply $got->value, { '$ref' => 'urn:example:x' }, 'stops at a $ref inside a cached document';
    is $got->scope, 'http://e.invalid/other.json#/c', 'with the scope it is in';
    is_deeply \@loaded, [], 'loads nothing';

    $got = $pointer->document_get('/bundled', cached_only => 1);
    is_deeply $got->value, { type => 'integer', minimum => 0 }, 'follows a $ref to a bundled schema';

    $got = $pointer->document_get('/local/b');
    is_deeply $got->value, { type => 'string' }, 'without cached_only follows the $ref';
    is_deeply \@loaded, ['urn:example:x'], 'by loading it';
};

subtest 'document_get with cached_only stops at a $ref cycle' => sub {
    # unbounded recursion ends in an "Out of memory!" no eval can catch, so stop at the first warning
    my $record = $SIG{__WARN__};
    local $SIG{__WARN__} = sub { die "deep recursion\n" if $_[0] =~ /^Deep recursion/; $record->(@_) };

    my $validator = JSONSchema::Validator::Draft7->new(
        schema => {},
        base_uri => 'http://e.invalid/root.json',
        documents => { 'http://e.invalid/doc.json' => {
            a => { '$ref' => '#/b' },
            b => { '$ref' => '#/a' },
            self => { '$ref' => '#/self' } } });
    my $pointer = JSONSchema::Validator::JSONPointer->new(
        scope => 'http://e.invalid/root.json',
        value => {
            two_step => { '$ref' => 'http://e.invalid/doc.json#/a' },
            self => { '$ref' => 'http://e.invalid/doc.json#/self' } },
        validator => $validator);

    my $got = eval { $pointer->document_get('/two_step/x', cached_only => 1) };
    is $@, '', 'a two-step cycle ends';
    is_deeply $got && $got->value, { '$ref' => '#/a' }, 'at the $ref back to its start';
    is $got && $got->scope, 'http://e.invalid/doc.json#/b', 'with the scope it is in';

    $got = eval { $pointer->document_get('/self/x', cached_only => 1) };
    is $@, '', 'a self-reference ends';
    is_deeply $got && $got->value, { '$ref' => '#/self' }, 'at the $ref to itself';
    is $got && $got->scope, 'http://e.invalid/doc.json#/self', 'with the scope it is in';
};

ok detect_warnings() == 0, 'no warnings';
done_testing;
