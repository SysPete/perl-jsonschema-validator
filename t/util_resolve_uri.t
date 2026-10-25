#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/detect_warnings errors_text/;
use JSONSchema::Validator;
use JSONSchema::Validator::Util qw( resolve_uri );

sub exception {
    my ($code) = @_;
    return eval { $code->(); 1 } ? undef : $@;
}

my $urn = 'urn:uuid:deadbeef-1234-ffff-ffff-4321feebdaed';

is resolve_uri('#/a', $urn)->as_string, "$urn#/a", 'fragment against URN base';
is resolve_uri('urn:example:x', 'urn:example:y')->as_string, 'urn:example:x',
    'absolute ref against URN base';
is resolve_uri('b.json#/c', 'http://h/a/s.json')->as_string, 'http://h/a/b.json#/c',
    'hierarchical base';
is resolve_uri('b.json', undef)->as_string, 'b.json', 'no base';
is resolve_uri(URI->new('b.json'), URI->new('http://h/a/s.json'))->as_string,
    'http://h/a/b.json', 'URI objects';
like exception(sub { resolve_uri('other.json', 'urn:example:root') }),
    qr/cannot resolve relative reference "other.json" against non-hierarchical base "urn:example:root"/,
    'relative path against URN base croaks';

my $v = JSONSchema::Validator->new(specification => 'Draft7',
    schema => { '$id' => 'urn:example:root', '$ref' => 'other.json' });
my ($r, $e) = $v->validate_schema('x');
is $r, 0, 'relative path ref against URN base fails';
unlike errors_text($e), qr/authority/, 'no URI::urn death';
like errors_text($e), qr/cannot resolve relative reference/, 'says why';

subtest 'fragment replaces the fragment of a URN base' => sub {
    is resolve_uri('#/a', 'urn:x:y#foo')->as_string, 'urn:x:y#/a', 'base with a fragment';
    is resolve_uri('#/a', 'urn:x:y#')->as_string, 'urn:x:y#/a', 'base with an empty fragment';

    for my $draft (qw/Draft4 Draft7/) {
        my $id = $draft eq 'Draft4' ? 'id' : '$id';
        my $v = JSONSchema::Validator->new(specification => $draft, schema => {
            $id => "$urn#",
            definitions => { a => { type => 'integer' } },
            properties => { x => { '$ref' => '#/definitions/a' } },
        });
        my ($r, $e) = $v->validate_schema({ x => 'str' });
        is $r, 0, "$draft: ref under an id ending in # is not the root";
        like errors_text($e), qr{type mismatch .* \[instance path: /x\]}, "$draft: says why";
    }
};

subtest 'empty reference is the base without its fragment' => sub {
    is resolve_uri('', 'urn:x:y')->as_string, 'urn:x:y', 'URN base';
    is resolve_uri('', 'urn:x:y#/a')->as_string, 'urn:x:y', 'URN base with a fragment';
    is resolve_uri('', 'http://h/a/s.json#/a')->as_string, 'http://h/a/s.json', 'hierarchical base';
};

ok detect_warnings() == 0, 'no warnings';
done_testing;
