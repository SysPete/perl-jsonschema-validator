#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/detect_warnings errors_text/;
use JSON::PP;
use Math::BigInt;
use Math::BigFloat;
use JSONSchema::Validator;
use JSONSchema::Validator::Util qw(is_type detect_type json_equal);

my $f = Math::BigFloat->new('1.5');
my $i = Math::BigFloat->new('2.0');
my $big = Math::BigInt->new(2)->bpow(70);

is detect_type($f, 1), 'number', 'BigFloat 1.5 is a number';
is detect_type($i, 1), 'integer', 'BigFloat 2.0 is an integer';
is detect_type($big, 1), 'integer', 'BigInt 2**70 is an integer';
ok !is_type($f, 'integer', 1), 'BigFloat 1.5 is not an integer';

ok json_equal(0, Math::BigFloat->new('0.0')), '0 equals 0.0';
ok json_equal([1], [Math::BigFloat->new('1.0')]), '[1] equals [1.0]';
ok !json_equal(0, JSON::PP::false), '0 is not false';
ok !json_equal([1], [JSON::PP::true]), '[1] is not [true]';
ok json_equal({a => [1, {b => 'x'}]}, {a => [1.0, {b => 'x'}]}), 'nested';
ok !json_equal({a => 1}, {a => 1, b => 2}), 'different keys';
ok !json_equal(undef, ''), 'null is not empty string';

my $v = JSONSchema::Validator->new(specification => 'Draft7',
    schema => { type => 'integer', maximum => Math::BigInt->new(2)->bpow(70) });
is( ($v->validate_schema($big))[0], 1, '2**70 <= 2**70' );
my ($r, $e) = $v->validate_schema($big + 1);
is $r, 0, '2**70+1 > 2**70';
like errors_text($e), qr/is greater than/, 'maximum says why';

$v = JSONSchema::Validator->new(specification => 'Draft7',
    schema => { multipleOf => Math::BigFloat->new('0.3333') });
($r, $e) = $v->validate_schema(Math::BigFloat->new('1'));
is $r, 0, '1 is not a multiple of 0.3333';
like errors_text($e), qr/is not multiple of/, 'multipleOf says why';

$v = JSONSchema::Validator->new(specification => 'Draft7',
    schema => { type => 'integer', multipleOf => Math::BigFloat->new('0.123456789') });
($r, $e) = $v->validate_schema(Math::BigFloat->new('1e308'));
is $r, 0, '1e308 is not a multiple of 0.123456789';
like errors_text($e), qr/is not multiple of/, 'float division = inf says why';

ok detect_warnings() == 0, 'no warnings';
done_testing;
