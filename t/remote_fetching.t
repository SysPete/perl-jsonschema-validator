#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/test_dir detect_warnings errors_text/;
use JSONSchema::Validator;
use JSONSchema::Validator::Draft7;

my $schema = { '$ref' => 'http://example.invalid/s.json' };

# off by default
my ($r, $e) = JSONSchema::Validator::Draft7->new(schema => $schema)->validate_schema(1);
is $r, 0, 'blocked by default';
like errors_text($e), qr/Remote fetching is disabled: cannot load http:\/\/example\.invalid\/s\.json/,
    'blocked by default says why';

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
($r, $e) = JSONSchema::Validator::Draft7->new(schema => $schema,
    scheme_handlers => { https => $handler })->validate_schema(1);
is $r, 0, 'https handler does not open http';
like errors_text($e), qr/Remote fetching is disabled/, 'https handler: says why';

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

ok detect_warnings() == 0, 'no warnings';
done_testing;
