#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path);
use Dumbbench;
use FindBin;
use Getopt::Long;
use JSON::PP ();
use Time::HiRes qw(time);

use lib "$FindBin::Bin/lib";
use Bench::OpenAPIDocument;

my $root = abs_path("$FindBin::Bin/..");
my $lib = "$root/lib";
my $precision = 0.005;
GetOptions('lib=s' => \$lib, 'precision=f' => \$precision)
    or die "usage: $0 [--lib DIR] [--precision FRACTION]\n";

# loaded at run time so --lib decides which validator is measured
unshift @INC, abs_path($lib);
require JSONSchema::Validator;

my $doc = Bench::OpenAPIDocument::build();
my $oas = JSONSchema::Validator->new(schema => $doc);

my $resource = 'r050';
my $valid_body = {
    name => 'Widget',
    count => 3,
    price => 9.5,
    active => JSON::PP::true(),
    note => undef,
    status => 'active',
    tags => [qw(a b c)],
};
my $invalid_body = {
    count => -1,
    price => 'free',
    active => 'yes',
    status => 'deleted',
    tags => [1 .. 12],
};
my @valid_items = map { _item($_) } 1 .. 20;
my @invalid_items = @valid_items;
$invalid_items[-1] = { %{ $valid_items[-1] }, id => 0, status => 'gone', created_at => 'yesterday' };

my %request = (method => 'put', openapi_path => "/$resource/{id}");
my %response = (method => 'get', openapi_path => "/$resource", status => '200');

my @draft7 = map {
    my $n = $_;
    my $base = "$root/t/data/validator_json_schema/draft7-$n";
    {
        validator => JSONSchema::Validator->new(schema => _load("$base-schema.json"), specification => 'Draft7'),
        ok => _load("$base-ok.json"),
        wrong => _load("$base-wrong.json"),
    }
} 1, 2;

my %workloads = (
    'oas30 request valid' => [1, sub {
        ($oas->validate_request(%request,
            parameters => { path => { id => '42' }, body => [1, 'application/json', $valid_body] }))[0];
    }],
    'oas30 request invalid' => [0, sub {
        ($oas->validate_request(%request,
            parameters => { path => { id => '0' }, body => [1, 'application/json', $invalid_body] }))[0];
    }],
    'oas30 response valid' => [1, sub {
        ($oas->validate_response(%response, parameters => { body => [1, 'application/json', \@valid_items] }))[0];
    }],
    'oas30 response invalid' => [0, sub {
        ($oas->validate_response(%response, parameters => { body => [1, 'application/json', \@invalid_items] }))[0];
    }],
    'draft7 valid' => [1, sub {
        my $result = 1;
        ($_->{validator}->validate_schema($_->{ok}))[0] or $result = 0 for @draft7;
        $result;
    }],
    'draft7 invalid' => [0, sub {
        my $result = 0;
        ($_->{validator}->validate_schema($_->{wrong}))[0] and $result = 1 for @draft7;
        $result;
    }],
);

# a workload that gives the wrong answer must not produce a number
for my $name (sort keys %workloads) {
    my ($expected, $code) = @{ $workloads{$name} };
    my $got = $code->();
    die "$name: expected $expected, got $got\n" unless $got == $expected;
}

printf "perl:      %s\n", $^V;
printf "validator: %s (%s)\n", $JSONSchema::Validator::VERSION, $INC{'JSONSchema/Validator.pm'};
printf "\$refs:     %d\n\n", Bench::OpenAPIDocument::count_refs($doc);

my $bench = Dumbbench->new(target_rel_precision => $precision, initial_runs => 20);
my %iterations;
for my $name (sort keys %workloads) {
    my $code = $workloads{$name}[1];

    # several calls per sample, so timer overhead is noise on ~10ms, not on one call
    my $start = time;
    $code->();
    my $n = $iterations{$name} = int(0.01 / (time - $start)) || 1;

    $bench->add_instances(Dumbbench::Instance::PerlSub->new(
        name => $name,
        code => sub { $code->() for 1 .. $n },
    ));
}
$bench->run;

printf "%-24s %12s %8s\n", 'workload', 'ops/sec', '+/-';
for my $instance (sort { $a->name cmp $b->name } $bench->instances) {
    my $result = $instance->result;
    my $per_op = $result->raw_number / $iterations{ $instance->name };
    my $relative = $result->raw_error->[0] / $result->raw_number;
    printf "%-24s %12.1f %7.1f%%\n", $instance->name, 1 / $per_op, 100 * $relative;
}

sub _item {
    my ($id) = @_;
    return {
        id => $id,
        name => "item $id",
        count => $id,
        price => $id + 0.25,
        active => $id % 2 ? JSON::PP::true() : JSON::PP::false(),
        note => $id % 3 ? "note $id" : undef,
        parent_id => $id > 1 ? $id - 1 : undef,
        status => 'active',
        created_at => '2026-10-25T12:00:00Z',
        address => { street => "$id High Street", city => 'Leeds', postcode => 'LS1 4AB' },
        related => [{ id => $id + 1, name => 'next' }],
        previous => { id => $id, name => 'previous' },
        tags => [qw(x y)],
    };
}

sub _load {
    my ($file) = @_;
    open my $fh, '<', $file or die "$file: $!\n";
    local $/;
    return JSON::PP->new->decode(<$fh>);
}
