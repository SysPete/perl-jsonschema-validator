#!/usr/bin/env perl

use strict;
use warnings;
use File::Temp qw( tempfile );
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

subtest 'OAS30 query strings checked against typed enums' => sub {
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
    is $result, 1, '"1" is in integer enum [1, 2]'
        or diag errors_text($errors);

    ($result, $errors) = $request->(int => '3');
    is $result, 0, '"3" is not in integer enum [1, 2]';
    like errors_text($errors), qr/instance is not of enums/, 'integer enum says why';

    ($result, $errors) = $request->(bool => '1');
    is $result, 1, '"1" is in boolean enum [true]'
        or diag errors_text($errors);

    ($result, $errors) = $request->(bool => '0');
    is $result, 0, '"0" is not in boolean enum [true]';
    like errors_text($errors), qr/instance is not of enums/, 'boolean enum says why';
};

subtest 'OAS30 empty path parameter' => sub {
    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.2',
        info => { title => 't', version => '1' },
        paths => {
            '/invoices/{id}' => {
                parameters => [
                    {
                        name => 'id', in => 'path', required => JSON::PP::true(),
                        schema => { type => 'string', minLength => 1 }
                    }
                ],
                get => { responses => { 200 => { description => 'ok' } } }
            }
        }
    });

    my ($result, $errors) = $validator->validate_request(
        method => 'get',
        openapi_path => '/invoices/{id}',
        parameters => { path => { id => '' } },
    );
    is $result, 0, 'fails minLength 1';
    like errors_text($errors), qr/path param "id" has error: minLength \(>= 1\) constraint violated/,
        'says why';
};

my $info = { title => 't', version => '1' };
my $responses = { 200 => { description => 'ok' } };
my $missing = 'file://' . test_dir('data/remote_fetching/no_such.json');

subtest 'OAS30 argument errors still croak' => sub {
    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/a' => { get => {
            parameters => [{ name => 'q', in => 'query', schema => { type => 'string' } }],
            responses => $responses } } } });

    eval { $validator->validate_request(method => 'get', openapi_path => '/a', parameters => { query => [1] }) };
    like $@, qr/^param "query" must be hashref or coderef/, 'a parameters value of the wrong type';

    my $error = { code => 500 };
    eval { $validator->validate_request(method => 'get', openapi_path => '/a',
        parameters => { query => sub { die $error } }) };
    is $@, $error, 'an exception object from a getter is rethrown';

    eval { $validator->validate_request(method => 'get', openapi_path => '/a',
        parameters => { query => sub { die "backend down\n" } }) };
    is $@, "backend down\n", 'a string exception from a getter is rethrown';
};

subtest 'OAS30 keeps what it found before a reference fails to load' => sub {
    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/b' => { post => {
            deprecated => JSON::PP::true(),
            parameters => [{ name => 'q', in => 'query', schema => { type => 'integer' } }],
            requestBody => { '$ref' => $missing },
            responses => $responses } } } });

    my ($result, $errors, $warnings) = $validator->validate_request(method => 'post', openapi_path => '/b',
        parameters => { query => { q => 'x' }, body => [1, 'application/json', {}] });
    is $result, 0, 'fails';
    like errors_text($errors), qr/query param "q" has error/, 'the parameter error is kept';
    like errors_text($errors), qr/exception: Failed to load resource/, 'the load failure is reported';
    like errors_text($warnings), qr/^method post of \/b is deprecated/, 'the deprecation warning is kept';
};

subtest 'OAS30 restores the scope after an exception' => sub {
    my $validator = JSONSchema::Validator::OAS30->new(base_uri => 'http://e.invalid/api.json', schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/a' => { post => {
            requestBody => { content => { 'application/json' => { schema => 'not a schema' } } },
            responses => $responses } } } });

    my $depth = @{$validator->scopes};
    for my $call (1 .. 3) {
        eval { $validator->validate_request(method => 'post', openapi_path => '/a',
            parameters => { body => [1, 'application/json', {}] }) };
        isnt $@, '', "call $call dies";
        is scalar @{$validator->scopes}, $depth, "scope stack depth after call $call";
    }
};

subtest 'OAS30 validate_schema restores the scope after an exception' => sub {
    my $validator = JSONSchema::Validator::OAS30->new(base_uri => 'http://e.invalid/api.json', schema => {
        openapi => '3.0.3', info => $info, paths => {} });

    my $depth = @{$validator->scopes};
    for my $call (1 .. 3) {
        eval { $validator->validate_schema(1, schema => 'not a schema', direction => 'request',
            scope => 'http://e.invalid/x.json') };
        isnt $@, '', "call $call dies";
        is scalar @{$validator->scopes}, $depth, "scope stack depth after call $call";
    }
};

subtest 'OAS30 does not report server paths when a reference fails to load' => sub {
    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/b' => { post => { requestBody => { '$ref' => $missing }, responses => $responses } } } });

    my ($result, $errors) = $validator->validate_request(method => 'post', openapi_path => '/b',
        parameters => { body => [1, 'application/json', {}] });
    is $result, 0, 'fails';
    unlike errors_text($errors), qr/\Q${\ test_dir()}\E/, 'the file path is not in the error';
    like errors_text($errors), qr/^exception: Failed to load resource no_such\.json: /, 'the file is named';
};

subtest 'OAS30 does not report server paths when a file fails to decode' => sub {
    my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    print $fh "{\n";
    close $fh;
    my ($name) = $file =~ m{([^/\\]+)\z};

    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/b' => { post => { requestBody => { '$ref' => 'file://' . $file }, responses => $responses } } } });

    my ($result, $errors) = $validator->validate_request(method => 'post', openapi_path => '/b',
        parameters => { body => [1, 'application/json', {}] });
    is $result, 0, 'fails';
    unlike errors_text($errors), qr/\Q$file\E/, 'the file path is not in the error';
    like errors_text($errors), qr/^exception: Failed to load resource \Q$name\E as JSON: /, 'the file is named';
};

subtest 'OAS30 discriminator values are schema names' => sub {
    my ($fh, $other_file) = tempfile(UNLINK => 1);
    print $fh "{}\n";
    close $fh;

    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/a' => { post => {
            requestBody => { content => { 'application/json' => {
                schema => { '$ref' => '#/components/schemas/Pet' } } } },
            responses => $responses } } },
        components => { schemas => {
            Pet => { type => 'object', required => ['petType'], discriminator => {
                propertyName => 'petType', mapping => { hound => '#/components/schemas/Dog' } } },
            Dog => { type => 'object', required => ['bark'] },
        } } });

    my $request = sub {
        my $pet_type = shift;
        return $validator->validate_request(method => 'post', openapi_path => '/a',
            parameters => { body => [1, 'application/json', { petType => $pet_type }] });
    };

    my ($result, $errors) = $request->('Dog');
    is $result, 0, 'a schema name selects that schema';
    like errors_text($errors), qr/bark/, 'and applies it';

    ($result, $errors) = $request->('hound');
    is $result, 0, 'a mapping to #/components/schemas/Dog selects Dog';
    like errors_text($errors), qr/bark/, 'and applies it';

    ($result, $errors) = $request->('#/paths');
    is $result, 0, 'a JSON pointer is not followed';
    like errors_text($errors), qr/discriminator value "#\/paths" is not a schema name/, 'says why';
    like errors_text($errors), qr/\[instance path: \/\] \[schema path: \/discriminator\]/, 'at the instance and schema paths';

    ($result, $errors) = $request->("Dog\n");
    is $result, 0, 'a name with a trailing newline fails';
    like errors_text($errors), qr/is not a schema name/, 'says why';

    ($result, $errors) = $request->($other_file);
    is $result, 0, 'a file path is not followed';
    like errors_text($errors), qr/is not a schema name/, 'says why';

    ($result, $errors) = $validator->validate_request(method => 'post', openapi_path => '/a',
        parameters => { body => [1, 'application/json', {}] });
    is $result, 0, 'a missing discriminator property fails';
    like errors_text($errors), qr/instance does not have discriminator property "petType"/, 'says why';

    ($result, $errors) = $request->({});
    is $result, 0, 'an object value fails';
    like errors_text($errors), qr/discriminator value is not a string/, 'says why';
    unlike errors_text($errors), qr/HASH\(/, 'without printing the value';
};

subtest 'OAS30 messages show a numeric parameter as written' => sub {
    my $validator = JSONSchema::Validator->new(specification => 'OAS30', schema => {
        openapi => '3.0.0', info => { title => 't', version => '1' },
        paths => { '/n' => { get => {
            parameters => [{ name => 'n', in => 'query', schema => { type => 'number', minimum => 8, maximum => 10 } }],
            responses => { 200 => { description => 'ok' } } } } } });
    for my $case (
        ['1.50e1', '1.50e1 is greater than 10 [instance path: /] [schema path: /maximum]'],
        ['1e400', '1e400 is greater than 10 [instance path: /] [schema path: /maximum]'],
        ['007.0', '007.0 is less than 8 [instance path: /] [schema path: /minimum]'],
        ['-0.0', '-0.0 is less than 8 [instance path: /] [schema path: /minimum]'],
    ) {
        my ($value, $expected) = @$case;
        my ($result, $errors) = $validator->validate_request(method => 'get', openapi_path => '/n',
            parameters => { query => { n => $value } });
        is $result, 0, "$value is out of range";
        is errors_text($errors), qq{query param "n" has error: $expected}, "$value is shown as written";
    }
};

ok detect_warnings() == 0, 'no warnings';
done_testing;
