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

subtest 'native integers above 2**53 compare exactly with bignums' => sub {
    my $iv = 9007199254740993;
    my $big_iv = Math::BigInt->new('9007199254740993');
    ok json_equal($iv, $big_iv), 'IV 2**53+1 equals BigInt 2**53+1';
    ok !json_equal($iv - 1, $big_iv), 'IV 2**53 is not BigInt 2**53+1';
    ok json_equal(18446744073709551615, Math::BigInt->new('18446744073709551615')), 'UV max';
    ok json_equal(-9223372036854775807, Math::BigInt->new('-9223372036854775807')), 'IV min + 1';

    for my $case (
        [{ maximum => $iv }, $big_iv, 1],
        [{ minimum => $big_iv }, $iv, 1],
        [{ maximum => $iv - 1 }, $big_iv, 0, qr/^9007199254740993 is greater than 9007199254740992/],
        [{ const => $iv }, $big_iv, 1],
        [{ multipleOf => Math::BigInt->new(3) }, $iv, 1],
    ) {
        my ($schema, $instance, $expected, $error) = @$case;
        my $name = join(',', %$schema) . " with $instance";
        my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => $schema);
        my ($r, $e) = $v->validate_schema($instance);
        is $r, $expected, $name or diag errors_text($e);
        like errors_text($e), $error, "$name says why" if $error;
    }
};

subtest 'plain numbers above 2**53 compare exactly' => sub {
    ok !json_equal(9007199254740993, 2**53), 'IV 2**53+1 is not the float 2**53';
    ok json_equal(9007199254740992, 2**53), 'IV 2**53 is the float 2**53';
    ok json_equal(1e300, 1e300), 'large floats';
    ok !json_equal(18446744073709551615, 2**64), 'UV max is not the float 2**64';

    for my $schema ({ const => 9007199254740993 }, { enum => [9007199254740993] }) {
        my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => $schema);
        my ($r, $e) = $v->validate_schema(2**53);
        is $r, 0, (keys %$schema)[0] . ' 2**53+1 rejects the float 2**53';
    }
    my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { uniqueItems => JSON::PP::true });
    is( ($v->validate_schema([9007199254740993, 2**53]))[0], 1, 'uniqueItems agrees' );
};

subtest 'floats keep all their digits when compared with bignums' => sub {
    my $f = 0.1 + 0.2;
    ok !json_equal(Math::BigFloat->new('0.3'), $f), 'BigFloat 0.3 is not 0.1 + 0.2';
    ok json_equal(Math::BigFloat->new('0.30000000000000004'), $f), 'BigFloat 0.30000000000000004 is 0.1 + 0.2';
    ok json_equal(Math::BigFloat->new('0.1'), 0.1), 'BigFloat 0.1 is still 0.1';
    ok !json_equal(Math::BigFloat->new('1'), 1.0000000000000002), 'BigFloat 1 is not 1.0000000000000002';

    my $v = JSONSchema::Validator->new(specification => 'Draft7',
        schema => { exclusiveMaximum => 0.30000000000000004 });
    my ($r, $e) = $v->validate_schema(Math::BigFloat->new('0.3'));
    is $r, 1, 'BigFloat 0.3 < 0.30000000000000004' or diag errors_text($e);

    $v = JSONSchema::Validator->new(specification => 'Draft7',
        schema => { multipleOf => Math::BigFloat->new('0.1') });
    ($r, $e) = $v->validate_schema(0.3);
    is $r, 1, 'the float 0.3 is a multiple of BigFloat 0.1' or diag errors_text($e);
};

subtest 'global bignum rounding settings are ignored' => sub {
    my $seven = Math::BigInt->new(7);
    my ($above, $half, $multiple) = ($big + 1, $big + Math::BigFloat->new('0.5'), Math::BigInt->new('1000000000000000000001'));
    for my $setting (qw/accuracy precision/) {
        my $value = $setting eq 'accuracy' ? 5 : 2;
        Math::BigFloat->$setting($value);
        Math::BigInt->$setting($value);

        my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { maximum => $big });
        is( ($v->validate_schema($above))[0], 0, "$setting: 2**70+1 > 2**70" );
        ok !json_equal($above, $half), "$setting: json_equal";
        ok !json_equal(9007199254740993, 2**53), "$setting: json_equal of plain numbers";
        $v = JSONSchema::Validator->new(specification => 'Draft7',
            schema => { multipleOf => $seven });
        is( ($v->validate_schema($multiple))[0], 1,
            "$setting: 10**21+1 is a multiple of 7" );

        Math::BigFloat->$setting(undef);
        Math::BigInt->$setting(undef);
    }
};

subtest 'a string is not equal to a number' => sub {
    for my $schema ({ enum => ['1', 'x'] }, { const => '1' }) {
        my $keyword = (keys %$schema)[0];
        my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => $schema);
        is( ($v->validate_schema(1))[0], 0, "strict $keyword \"1\" rejects 1" );
        is( ($v->validate_schema('1'))[0], 1, "strict $keyword \"1\" accepts \"1\"" );
        $v = JSONSchema::Validator->new(specification => 'Draft7', schema => $schema, strict => 0);
        is( ($v->validate_schema(1))[0], 1, "non-strict $keyword \"1\" accepts 1" );
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
