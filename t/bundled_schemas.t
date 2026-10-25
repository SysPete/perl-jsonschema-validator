#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/detect_warnings errors_text/;
use JSONSchema::Validator;
use JSONSchema::Validator::BundledSchemas qw( bundled_schema );

my $fail = sub { die "network used for $_[0]\n" };

my %SPEC = (
    'draft-04' => 'Draft4',
    'draft-06' => 'Draft6',
    'draft-07' => 'Draft7',
);

for my $draft (sort keys %SPEC) {
    for my $id ("http://json-schema.org/$draft/schema#",
                "http://json-schema.org/$draft/schema") {
        my $v = JSONSchema::Validator->new(
            specification => $SPEC{$draft},
            schema => { '$ref' => $id },
            scheme_handlers => { http => $fail, https => $fail },
        );
        is( ($v->validate_schema({ type => 'string' }))[0], 1, "$id: valid schema" );
        my ($r, $e) = $v->validate_schema({ type => 12 });
        is $r, 0, "$id: invalid schema";
        like errors_text($e), qr{instance is not of enums \[instance path: /type\]},
            "$id: says why";
    }
}

ok bundled_schema('https://spec.openapis.org/oas/3.0/schema/2019-04-02'), 'oas30';
ok !defined bundled_schema('http://example.com/nope'), 'unknown id';

subtest 'one validator cannot change the meta-schema another sees' => sub {
    my $id = 'http://json-schema.org/draft-07/schema#';
    my $v1 = JSONSchema::Validator->new(specification => 'Draft7', schema => { '$ref' => $id });
    my (undef, $meta) = $v1->resolver->resolve(URI->new($id));
    $meta->{properties}{type} = { type => 'null' };

    my $v2 = JSONSchema::Validator->new(specification => 'Draft7', schema => { '$ref' => $id });
    my ($r, $e) = $v2->validate_schema({ type => 'string' });
    is $r, 1, 'a later validator gets an unchanged copy' or diag errors_text($e);
};

ok detect_warnings() == 0, 'no warnings';
done_testing;
