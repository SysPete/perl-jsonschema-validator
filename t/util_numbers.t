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
ok json_equal(Math::BigInt->new(5), 5.0), 'BigInt 5 equals 5.0';
ok !json_equal(Math::BigInt->new(4), 4.5), 'BigInt 4 is not 4.5';
ok json_equal($big, 2**70), 'BigInt 2**70 equals the float 2**70';
ok !json_equal($big + 1, 2**70), 'BigInt 2**70+1 is not the float 2**70';
ok json_equal(-$big, -(2**70)), 'BigInt -2**70 equals the float -2**70';
ok json_equal(Math::BigInt->new(3)->blsft(1000), 3 * 2**1000), 'BigInt 3*2**1000 equals the float';
ok !json_equal(Math::BigInt->new(9**9**9), 2**70), 'BigInt inf is not 2**70';

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

for my $case (
    [Math::BigFloat->new('1.1'), 0, 'BigFloat 1.1 is not an integer'],
    [Math::BigFloat->new('2.0'), 1, 'BigFloat 2.0 is an integer'],
    [$big, 1, 'BigInt 2**70 is an integer'],
) {
    my ($instance, $expected, $name) = @$case;
    $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { type => 'integer' });
    ($r, $e) = $v->validate_schema($instance);
    is $r, $expected, "Draft7 $name" or diag errors_text($e);
}

for my $case (
    ['4.5', '1.5', 1], ['-4.5', '1.5', 1], ['-4.6', '1.5', 0],
) {
    my ($instance, $multiple, $expected) = @$case;
    $v = JSONSchema::Validator->new(specification => 'Draft7',
        schema => { multipleOf => Math::BigFloat->new($multiple) });
    ($r, $e) = $v->validate_schema(Math::BigFloat->new($instance));
    is $r, $expected, "BigFloat $instance multipleOf $multiple is $expected" or diag errors_text($e);
}

my @bounds = (
    [$big, { minimum => 4.5 }, 1, '2**70 >= 4.5'],
    [0.5, { maximum => $big }, 1, '0.5 <= 2**70'],
    [Math::BigInt->new(4), { maximum => 4.5 }, 1, 'BigInt 4 <= 4.5'],
    [Math::BigInt->new(5), { minimum => 4.5 }, 1, 'BigInt 5 >= 4.5'],
    [$big, { exclusiveMinimum => 4.5 }, 1, '2**70 > 4.5'],
    [$big + 1, { maximum => 2**70 }, 0, '2**70+1 > float 2**70',
        qr/^1180591620717411303425 is greater than/],
    [Math::BigInt->new(5), { maximum => 4.5 }, 0, 'BigInt 5 > 4.5', qr/^5 is greater than 4\.5/],
    [Math::BigInt->new(4), { minimum => 4.5 }, 0, 'BigInt 4 < 4.5', qr/^4 is less than 4\.5/],
    [Math::BigInt->new(4), { exclusiveMinimum => 4.5 }, 0, 'BigInt 4 <= 4.5 exclusive',
        qr/^4 is equal or less than 4\.5/],
    [Math::BigInt->new(5), { exclusiveMaximum => 4.5 }, 0, 'BigInt 5 >= 4.5 exclusive',
        qr/^5 is equal or greater than 4\.5/],
);
for my $case (@bounds) {
    my ($instance, $schema, $expected, $name, $error) = @$case;
    $v = JSONSchema::Validator->new(specification => 'Draft7', schema => $schema);
    ($r, $e) = $v->validate_schema($instance);
    is $r, $expected, $name or diag errors_text($e);
    like errors_text($e), $error, "$name says why" if $error;
}

$v = JSONSchema::Validator->new(specification => 'Draft4',
    schema => { maximum => 4.5, exclusiveMaximum => JSON::PP::true });
($r, $e) = $v->validate_schema(Math::BigInt->new(4));
is $r, 1, 'Draft4 BigInt 4 < 4.5 exclusive' or diag errors_text($e);
$v = JSONSchema::Validator->new(specification => 'Draft4',
    schema => { minimum => Math::BigFloat->new('4.0'), exclusiveMinimum => JSON::PP::true });
($r, $e) = $v->validate_schema(4);
is $r, 0, 'Draft4 4 is not > BigFloat 4.0 exclusive';
like errors_text($e), qr/^4 is equal to 4/, 'Draft4 exclusiveMinimum says why';

subtest 'a huge exponent is never written out in full' => sub {
    # written out, these need a petabyte, so a regression dies at once instead of filling memory
    my $exp = '1000000000000000';
    my $huge = Math::BigFloat->new("1e$exp");
    my $tiny = Math::BigFloat->new("1e-$exp");

    ok !json_equal($huge, 5), 'json_equal';
    ok json_equal($huge, Math::BigFloat->new("10e" . ($exp - 1))), 'json_equal of equal values';

    for my $case (
        [Draft7 => { maximum => 5 }, $huge, 0, qr/^1e\+$exp is greater than 5/],
        [Draft7 => { minimum => 5 }, $tiny, 0, qr/^1e-$exp is less than 5/],
        [Draft7 => { minimum => 5 }, $huge, 1],
        [Draft7 => { exclusiveMaximum => 5 }, $huge, 0, qr/^1e\+$exp is equal or greater than 5/],
        [Draft4 => { maximum => 5, exclusiveMaximum => JSON::PP::true }, $huge, 0,
            qr/^1e\+$exp is greater than 5/],
        [Draft7 => { maximum => $huge }, 5, 1],
        [Draft7 => { const => 5 }, $huge, 0],
        [Draft7 => { multipleOf => 3 }, $huge, 0, qr/^instance is not multiple of 3/],
        [Draft7 => { multipleOf => 8 }, $huge, 1],
        [Draft7 => { multipleOf => 7 }, Math::BigFloat->new("7e$exp"), 1],
        [Draft7 => { multipleOf => Math::BigFloat->new('0.3') }, $huge, 0],
        [Draft7 => { multipleOf => Math::BigFloat->new('0.25') }, $huge, 1],
        [Draft7 => { multipleOf => 1 }, $tiny, 0],
        [Draft7 => { multipleOf => $tiny }, 1, 1],
        [Draft7 => { multipleOf => $huge }, 5, 0, qr/^instance is not multiple of 1e\+$exp/],
    ) {
        my ($spec, $schema, $instance, $expected, $error) = @$case;
        my $name = "$spec " . join(',', map { ref && ref ne 'JSON::PP::Boolean' ? $_->bsstr : $_ } %$schema) . " with " . (ref $instance ? $instance->bsstr : $instance);
        my $v = JSONSchema::Validator->new(specification => $spec, schema => $schema);
        my ($r, $e) = $v->validate_schema($instance);
        is $r, $expected, $name or diag errors_text($e);
        like errors_text($e), $error, "$name says why" if $error;
    }
};

subtest 'strict uniqueItems' => sub {
    my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { uniqueItems => JSON::PP::true });
    my $exp = '1000000000000000';
    for my $case (
        [[1, 1.0], 0, '1 and 1.0'],
        [[1, Math::BigFloat->new('1.0')], 0, '1 and BigFloat 1.0'],
        [[0, -0.0], 0, '0 and -0.0'],
        [[$big, 2**70], 0, 'BigInt 2**70 and the float 2**70'],
        [[$big + 1, 2**70], 1, 'BigInt 2**70+1 and the float 2**70'],
        [[0.1, Math::BigFloat->new('0.1')], 0, '0.1 and BigFloat 0.1'],
        [[1, '1'], 1, 'number and string'],
        [[1, JSON::PP::true], 1, 'number and true'],
        [[JSON::PP::true, JSON::PP::true], 0, 'true twice'],
        [[undef, undef], 0, 'null twice'],
        [[undef, ''], 1, 'null and empty string'],
        [[{a => [1, 'x']}, {a => [1.0, 'x']}], 0, 'nested 1 and 1.0'],
        [[{a => 1}, {a => 1, b => 2}], 1, 'different keys'],
        [[{'a,b' => 1}, {a => 1, b => 1}], 1, 'keys that would run together'],
        [[['a', 'b'], ['a,b']], 1, 'strings that would run together'],
        [[Math::BigFloat->new("1e$exp"), Math::BigFloat->new("10e" . ($exp - 1))], 0, 'equal huge exponents'],
        [[Math::BigFloat->new("1e$exp"), Math::BigFloat->new("2e$exp")], 1, 'different huge exponents'],
    ) {
        my ($instance, $expected, $name) = @$case;
        my ($r, $e) = $v->validate_schema($instance);
        is $r, $expected, $name or diag errors_text($e);
        like errors_text($e), qr/^instance has non-unique elements/, "$name says why" unless $expected;
    }

    # pairwise this takes minutes; one pass takes well under a second
    my @objects = map { { id => $_, tags => ['x', $_ * 1.5] } } 1 .. 20000;
    my $start = time;
    is( ($v->validate_schema(\@objects))[0], 1, '20000 distinct objects' );
    cmp_ok time - $start, '<', 10, 'in linear time';
    push @objects, { id => 7, tags => ['x', 10.5] };
    is( ($v->validate_schema(\@objects))[0], 0, 'a late duplicate is found' );
};

ok detect_warnings() == 0, 'no warnings';
done_testing;
