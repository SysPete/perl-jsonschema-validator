#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/test_dir detect_warnings errors_text/;
use JSONSchema::Validator;
use JSONSchema::Validator::Draft4;
use JSONSchema::Validator::Draft7;
use JSONSchema::Validator::OAS30;

my $schema = { '$ref' => 'http://example.invalid/s.json' };
my $blocked = qr/^Remote fetching is disabled: cannot load http:\/\/example\.invalid\/s\.json\./;

sub construct {
    my ($class, %params) = @_;
    my $v = eval { $class->new(%params) };
    return $v ? 'ok' : $@;
}

# off by default, and caught when the validator is built
my ($r, $e);
like construct('JSONSchema::Validator::Draft7', schema => $schema), $blocked, 'blocked by default at new';
like construct('JSONSchema::Validator::Draft4', schema => { properties => { a => $schema } }), $blocked,
    'nested ref blocked at new';
like construct('JSONSchema::Validator::Draft7',
        schema => { '$id' => 'http://example.invalid/root.json', properties => { a => { '$ref' => 's.json' } } }),
    $blocked, 'relative ref against an http base blocked at new';
like construct('JSONSchema::Validator::OAS30', schema => {
        openapi => '3.0.3', info => { title => 't', version => '1' },
        paths => { '/a' => { get => { responses => { 200 => $schema } } } } }),
    $blocked, 'OAS30 ref anywhere in the document blocked at new';
like construct('JSONSchema::Validator', schema => $schema, specification => 'Draft7'), $blocked,
    'blocked through JSONSchema::Validator->new';

# what the scan must not trip on
is construct('JSONSchema::Validator::Draft7', schema => {
        enum => [$schema], const => $schema, default => $schema, examples => [$schema] }),
    'ok', 'refs inside enum, const, default and examples are data';
is construct('JSONSchema::Validator::OAS30', schema => {
        openapi => '3.0.3', info => { title => 't', version => '1' }, paths => {},
        'x-vendor' => $schema,
        components => { schemas => { a => { example => $schema } } } }),
    'ok', 'refs inside example and x- extensions are data';
is construct('JSONSchema::Validator::Draft7', schema => { '$ref' => 'http://json-schema.org/draft-07/schema#' }),
    'ok', 'bundled meta-schema ref is not remote';
{
    my $v = JSONSchema::Validator::Draft7->new(schema => {
        '$id' => 'http://example.invalid/root.json',
        definitions => { item => { '$id' => 'item.json', type => 'integer' } },
        properties => { a => { '$ref' => 'item.json' } } });
    ($r, $e) = $v->validate_schema({ a => 'x' });
    is $r, 0, 'ref to an $id in the schema resolves locally';
    like errors_text($e), qr/type mismatch/, 'and is applied';
}

# documents, with and without an empty fragment on either side
for my $pair (['http://example.invalid/s.json', $schema],
              ['http://example.invalid/s.json#', $schema],
              ['http://example.invalid/s.json', { '$ref' => 'http://example.invalid/s.json#' }]) {
    my ($key, $s) = @$pair;
    my $v = JSONSchema::Validator::Draft7->new(schema => $s,
        documents => { $key => { type => 'integer' } });
    is( ($v->validate_schema(1))[0], 1, "documents $key" );
    my ($r, $e) = $v->validate_schema('x');
    is $r, 0, "documents $key rejects";
    like errors_text($e), qr/type mismatch/, "documents $key says why";
}

# a scheme handler opts in for its scheme only
my @called;
my $handler = sub { push @called, "$_[0]"; return (\'{"type":"integer"}', 'JSON') };
($r) = JSONSchema::Validator::Draft7->new(schema => $schema,
    scheme_handlers => { http => $handler })->validate_schema(1);
is $r, 1, 'http handler opens http';
is_deeply \@called, ['http://example.invalid/s.json'], 'handler got the uri';
like construct('JSONSchema::Validator::Draft7', schema => $schema, scheme_handlers => { https => $handler }),
    $blocked, 'https handler does not open http';

# an exception during validation reports its message, not where in the code it was raised
($r, $e) = JSONSchema::Validator::Draft7->new(schema => $schema,
    scheme_handlers => { http => sub { die "handler failed\n" } })->validate_schema(1);
is $r, 0, 'failing handler fails validation';
like errors_text($e), qr/^exception: Failed to load resource http:\/\/example\.invalid\/s\.json: handler failed \[/,
    'failing handler says why';
unlike errors_text($e), qr/ line \d+/, 'exception message has no source location';
($r, $e) = JSONSchema::Validator::Draft7->new(schema => $schema,
    scheme_handlers => { http => sub { (\'not json', 'JSON') } })->validate_schema(1);
is $r, 0, 'bad document fails validation';
like errors_text($e), qr/as JSON: .*at character offset 0/, 'bad document keeps the parser message';
unlike errors_text($e), qr/ line \d+|\.pm\b/, 'croak message has no source location';

# fetch_remote => 1 reaches the fetcher
{
    no warnings 'redefine';
    local *JSONSchema::Validator::Util::fetch_file = sub { (\'{"type":"integer"}', 'JSON') };
    ($r) = JSONSchema::Validator::Draft7->new(schema => $schema, fetch_remote => 1)
        ->validate_schema(1);
    is $r, 1, 'fetch_remote opts in';
}

# what stays allowed without fetch_remote
{
    no warnings 'redefine';
    local *JSONSchema::Validator::Util::fetch_file = sub { (\'{"type":"integer"}', 'JSON') };
    my $v = JSONSchema::Validator->new(resource => 'http://example.invalid/root.json',
        specification => 'Draft7');
    is( ($v->validate_schema(1))[0], 1, "caller's own http resource still loads" );
}
my $file_ref = { '$ref' => 'file://' . test_dir('data/remote_fetching/integer.json') };
($r, $e) = JSONSchema::Validator::Draft7->new(schema => $file_ref)->validate_schema('x');
is $r, 0, 'file: ref resolves without fetch_remote';
like errors_text($e), qr/type mismatch/, 'and is applied';
is( (JSONSchema::Validator::Draft7->new(schema => $file_ref)->validate_schema(1))[0], 1,
    'file: ref accepts a valid instance' );

subtest 'the scan at new finds refs by schema position, not key name' => sub {
    for my $case (
        [properties => { default => $schema }],
        [properties => { enum => $schema }],
        [properties => { 'x-a' => $schema }],
        [properties => { '$ref' => { type => 'string' }, a => $schema }],
        [patternProperties => { '^examples$' => $schema }],
        [definitions => { const => $schema }],
        [dependencies => { example => $schema }],
    ) {
        my ($keyword, $value) = @$case;
        my $name = "$keyword " . join(',', sort keys %$value);
        like construct('JSONSchema::Validator::Draft7', schema => { $keyword => $value }), $blocked, $name;
    }
    like construct('JSONSchema::Validator::Draft4', schema => { properties => { default => $schema } }),
        $blocked, 'Draft4 property named default';

    my $oas = sub {
        my (%extra) = @_;
        return construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' }, paths => {}, %extra });
    };
    like $oas->(paths => { '/a' => { get => { responses => { default => $schema } } } }), $blocked,
        'OAS30 default response';
    like $oas->(components => { schemas => { default => $schema } }), $blocked, 'OAS30 schema named default';
    like $oas->(components => { schemas => { a => { properties => { example => $schema } } } }), $blocked,
        'OAS30 property named example';
};

subtest 'the scan at new skips what validation never resolves' => sub {
    for my $schema_with_ref (
        { 'my-annotation' => $schema },
        { title => 'x', description => { '$ref' => 'http://example.invalid/s.json' } },
        { properties => { a => { type => 'integer', 'x-meta' => $schema } } },
    ) {
        my $name = join ',', sort keys %$schema_with_ref;
        is construct('JSONSchema::Validator::Draft7', schema => $schema_with_ref), 'ok', "Draft7 $name";
    }
};

subtest 'the scan at new handles a cyclic schema' => sub {
    my $cyclic = { type => 'object' };
    $cyclic->{properties}{child} = $cyclic;
    # a regression recurses without end, filling memory in seconds; stop it at the warning
    local $SIG{__WARN__} = sub { die "@_" if $_[0] =~ /Deep recursion/; warn @_ };
    is construct('JSONSchema::Validator::Draft7', schema => $cyclic, using_id_with_ref => 0), 'ok',
        'builds';
};

subtest 'local files can be refused' => sub {
    my $path = test_dir('data/remote_fetching/integer.json');
    my %refuse = (
        base_uri => 'urn:example:schema',
        scheme_handlers => { file => sub { die "local files are disabled\n" } },
    );
    for my $ref ($path, "file://$path", 'integer.json') {
        my $v = JSONSchema::Validator::Draft7->new(schema => { '$ref' => $ref }, %refuse);
        my ($r, $e) = $v->validate_schema(1);
        is $r, 0, "$ref is not read";
        like errors_text($e), qr/local files are disabled|cannot resolve relative reference/,
            "$ref says why";
    }
};

ok detect_warnings() == 0, 'no warnings';
done_testing;
