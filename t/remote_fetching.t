#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Time::HiRes ();

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

subtest 'off by default, and caught when the validator is built' => sub {
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
};

subtest 'what the scan must not trip on' => sub {
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

    my $v = JSONSchema::Validator::Draft7->new(schema => {
        '$id' => 'http://example.invalid/root.json',
        definitions => { item => { '$id' => 'item.json', type => 'integer' } },
        properties => { a => { '$ref' => 'item.json' } } });
    my ($r, $e) = $v->validate_schema({ a => 'x' });
    is $r, 0, 'ref to an $id in the schema resolves locally';
    like errors_text($e), qr/type mismatch/, 'and is applied';
};

subtest 'documents, with and without an empty fragment on either side' => sub {
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
};

subtest 'a scheme handler opts in for its scheme only' => sub {
    my @called;
    my $handler = sub { push @called, "$_[0]"; return (\'{"type":"integer"}', 'JSON') };
    my ($r) = JSONSchema::Validator::Draft7->new(schema => $schema,
        scheme_handlers => { http => $handler })->validate_schema(1);
    is $r, 1, 'http handler opens http';
    is_deeply \@called, ['http://example.invalid/s.json'], 'handler got the uri';
    like construct('JSONSchema::Validator::Draft7', schema => $schema, scheme_handlers => { https => $handler }),
        $blocked, 'https handler does not open http';
};

subtest 'an exception during validation reports its message, not where in the code it was raised' => sub {
    my ($r, $e) = JSONSchema::Validator::Draft7->new(schema => $schema,
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
};

subtest 'fetch_remote => 1 reaches the fetcher' => sub {
    no warnings 'redefine';
    local *JSONSchema::Validator::Util::fetch_file = sub { (\'{"type":"integer"}', 'JSON') };
    my ($r) = JSONSchema::Validator::Draft7->new(schema => $schema, fetch_remote => 1)
        ->validate_schema(1);
    is $r, 1, 'fetch_remote opts in';
};

subtest 'what stays allowed without fetch_remote' => sub {
    {
        no warnings 'redefine';
        local *JSONSchema::Validator::Util::fetch_file = sub { (\'{"type":"integer"}', 'JSON') };
        my $v = JSONSchema::Validator->new(resource => 'http://example.invalid/root.json',
            specification => 'Draft7');
        is( ($v->validate_schema(1))[0], 1, "caller's own http resource still loads" );
    }
    my $file_ref = { '$ref' => 'file://' . test_dir('data/remote_fetching/integer.json') };
    my ($r, $e) = JSONSchema::Validator::Draft7->new(schema => $file_ref)->validate_schema('x');
    is $r, 0, 'file: ref resolves without fetch_remote';
    like errors_text($e), qr/type mismatch/, 'and is applied';
    is( (JSONSchema::Validator::Draft7->new(schema => $file_ref)->validate_schema(1))[0], 1,
        'file: ref accepts a valid instance' );
};

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

subtest '$id keys inside documents are indexed' => sub {
    my $v = JSONSchema::Validator::Draft7->new(
        schema => { '$ref' => 'http://e.invalid/inner.json' },
        documents => { 'http://e.invalid/outer.json' => {
            definitions => { a => { '$id' => 'inner.json', type => 'integer' } } } });
    is( ($v->validate_schema(1))[0], 1, 'resolves without loading' );
    my ($r, $e) = $v->validate_schema('x');
    is $r, 0, 'and is applied';
    like errors_text($e), qr/type mismatch \(expecting any of \(integer\), found: string\)/, 'says why';
};

subtest 'documents that would replace each other croak' => sub {
    my $already = qr/^documents: http:\/\/e\.invalid\/s\.json is already defined/;
    for my $case (
        ['two keys for one URI', {}, {
            'http://e.invalid/s.json' => { type => 'integer' },
            'http://e.invalid/s.json#' => { type => 'string' } }],
        ['the schema URI', { base_uri => 'http://e.invalid/s.json' }, {
            'http://e.invalid/s.json#' => { type => 'integer' } }],
        ['an $id in the schema', { schema => { definitions => { a => { '$id' => 'http://e.invalid/s.json' } } } }, {
            'http://e.invalid/s.json' => { type => 'integer' } }],
        ['an $id in another document', {}, {
            'http://e.invalid/s.json' => { type => 'integer' },
            'http://e.invalid/a.json' => { definitions => { x => { '$id' => 'http://e.invalid/s.json' } } } }],
    ) {
        my ($name, $params, $documents) = @$case;
        # the same answer whichever order the hash gives the keys in
        for (1 .. 5) {
            like construct('JSONSchema::Validator::Draft7', schema => { type => 'string' }, %$params,
                documents => $documents), $already, $name;
        }
    }
    is construct('JSONSchema::Validator::Draft7',
        schema => { '$id' => 'http://e.invalid/root.json', definitions => { a => { '$id' => 'a.json' } } },
        documents => { 'http://e.invalid/b.json' => { '$id' => 'http://e.invalid/b.json' } }),
        'ok', 'a document whose $id is its own key';
};

subtest 'OAS30 reports a reference that fails to load instead of dying' => sub {
    my $path_item = 'file://' . test_dir('data/remote_fetching/path_item.json');
    my $v = JSONSchema::Validator::OAS30->new(schema => {
        openapi => '3.0.3', info => { title => 't', version => '1' },
        paths => {
            '/remote' => { '$ref' => $path_item },
            '/missing' => { '$ref' => 'file://' . test_dir('data/remote_fetching/no_such.json') },
        } });

    for my $case (['/remote', qr/^exception: Remote fetching is disabled: cannot load http:\/\/example\.invalid\/item\.json\./],
                  ['/missing', qr/^exception: Failed to load resource/]) {
        my ($openapi_path, $error) = @$case;
        my ($r, $e) = eval { $v->validate_request(method => 'get', openapi_path => $openapi_path) };
        is $@, '', "request $openapi_path does not die";
        is $r, 0, "request $openapi_path fails";
        like errors_text($e // []), $error, "request $openapi_path says why";

        ($r, $e) = eval { $v->validate_response(method => 'get', openapi_path => $openapi_path, status => 200) };
        is $@, '', "response $openapi_path does not die";
        is $r, 0, "response $openapi_path fails";
        like errors_text($e // []), $error, "response $openapi_path says why";
    }
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

subtest 'the scan at new follows local refs into any part of the schema' => sub {
    like construct('JSONSchema::Validator::Draft7', schema => {
            '$defs' => { a => $schema }, properties => { p => { '$ref' => '#/$defs/a' } } }),
        $blocked, 'a ref into $defs';
    like construct('JSONSchema::Validator::Draft7', schema => { '$ref' => 'http://e.invalid/doc.json#/defs/a' },
            documents => { 'http://e.invalid/doc.json' => { defs => { a => $schema } } }),
        $blocked, 'a ref into a container in a document';
};

subtest 'the scan at new handles local refs that form a cycle' => sub {
    # unbounded recursion ends in an "Out of memory!" no eval can catch, so stop at the first warning
    my $record = $SIG{__WARN__};
    local $SIG{__WARN__} = sub { die "deep recursion\n" if $_[0] =~ /^Deep recursion/; $record->(@_) };

    is construct('JSONSchema::Validator::Draft7', schema => {
            '$defs' => { a => { '$ref' => '#/$defs/b' }, b => { '$ref' => '#/$defs/a' } },
            properties => { p => { '$ref' => '#/$defs/a' } } }),
        'ok', 'builds';
};

subtest 'the scan at new skips x- extensions of OAS30 paths and responses' => sub {
    my $ok = { 200 => { description => 'ok' } };
    is construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' },
            paths => { 'x-vendor' => $schema, '/a' => { get => { responses => $ok } } } }),
        'ok', 'a Paths Object extension';
    is construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' },
            paths => { '/a' => { get => { responses => { %$ok, 'x-vendor' => $schema } } } } }),
        'ok', 'a Responses Object extension';
    like construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' }, paths => {},
            components => { schemas => { 'x-named' => $schema } } }),
        $blocked, 'a schema named x-named is still a schema';
};

subtest 'the scan at new checks a shared subschema under each scope' => sub {
    # the key names change the hash order, so both visit orders occur
    for my $i (1 .. 20) {
        my $shared = { '$ref' => 'other.json' };
        like construct('JSONSchema::Validator::Draft7', schema => { properties => {
                "a$i" => $shared,
                "b$i" => { '$id' => 'http://example.invalid/b.json', properties => { c => $shared } } } }),
            qr/^Remote fetching is disabled: cannot load http:\/\/example\.invalid\/other\.json\./,
            "properties a$i and b$i";
    }
};

subtest 'the scan at new checks OAS30 discriminator mappings' => sub {
    like construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' }, paths => {},
            components => { schemas => { Pet => { type => 'object', discriminator => {
                propertyName => 't', mapping => { dog => 'http://example.invalid/s.json' } } } } } }),
        $blocked, 'a mapping to an http URI';
};

subtest 'the scan at new applies the $id of a ref target once' => sub {
    my $v = eval { JSONSchema::Validator::Draft7->new(schema => {
        '$id' => 'http://x.invalid/a/',
        properties => { p => { '$id' => 'b/', properties => { q => { '$ref' => '#' } } } } }) };
    is $@, '', 'new does not die';
    SKIP: {
        skip "no validator", 1 unless $v;
        my ($r) = $v->validate_schema({ p => { q => { q => 5 } } });
        is $r, 1, 'and validation loads nothing';
    }
};

subtest 'the scan at new skips x- keys only in OAS30 objects that allow extensions' => sub {
    my $response = { description => 'ok', content => { 'application/json' => { schema => $schema } } };
    my $callback = { '{$request.body#/url}' => { post => { responses => { 200 => $response } } } };
    my $oas = sub {
        my (%extra) = @_;
        return construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' }, paths => {}, %extra });
    };
    like $oas->(components => { responses => { 'x-r' => $response } }), $blocked,
        'a response named x-r in components';
    like $oas->(components => { callbacks => { 'x-cb' => $callback } }), $blocked,
        'a callback named x-cb in components';
    like $oas->(paths => { '/a' => { post => { responses => { 200 => { description => 'ok' } },
            callbacks => { 'x-cb' => $callback } } } }), $blocked,
        'a callback named x-cb in an operation';
    is $oas->(paths => { '/a' => { post => { responses => { 200 => { description => 'ok' } },
            callbacks => { cb => { 'x-vendor' => $schema } } } } }), 'ok',
        'a Callback Object extension';
};


subtest 'the scan at new loads nothing' => sub {
    my @loaded;
    my $v = eval { JSONSchema::Validator::Draft7->new(schema => {
            '$ref' => '#/definitions/a/properties/b',
            definitions => { a => { '$ref' => 'urn:example:a' } } },
        scheme_handlers => { urn => sub {
            push @loaded, "$_[0]";
            (\'{"properties":{"b":{"type":"integer"}}}', 'JSON') } }) };
    is $@, '', 'new does not die';
    is_deeply \@loaded, [], 'no handler is called at new';
    my ($r) = $v->validate_schema('x');
    is $r, 0, 'validation follows the reference';
    is_deeply \@loaded, ['urn:example:a'], 'and loads it then';
};

subtest 'a document that is not a reference conflicts without a numeric warning' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    like construct('JSONSchema::Validator::Draft7', schema => { '$id' => 'http://e.invalid/a.json' },
            documents => { 'http://e.invalid/a.json' => 'str' }),
        qr/^documents: http:\/\/e\.invalid\/a\.json is already defined/, 'a string where the schema is';
    is_deeply \@warnings, [], 'and no warnings';
};

subtest 'documents may hold the schema itself' => sub {
    my $root = { '$id' => 'http://e.invalid/root.json', type => 'integer' };
    is construct('JSONSchema::Validator::Draft7', schema => $root,
            documents => { 'http://e.invalid/root.json' => $root }),
        'ok', 'the same schema under its own URI';
};

subtest 'an $id with an empty fragment collides like one without' => sub {
    like construct('JSONSchema::Validator::Draft7', schema => { type => 'string' }, documents => {
            'http://e.invalid/s.json' => { type => 'integer' },
            'http://e.invalid/a.json' => { '$id' => 'http://e.invalid/s.json#', type => 'string' } }),
        qr/^documents: http:\/\/e\.invalid\/s\.json is already defined/, 'an $id ending in #';
};

subtest 'Draft 4 ids ending in # resolve with or without the #' => sub {
    my $v = eval { JSONSchema::Validator::Draft4->new(schema => {
        id => 'http://e.invalid/root.json#',
        definitions => { a => { id => 'http://e.invalid/a.json#', type => 'integer' } },
        properties => { x => { '$ref' => 'http://e.invalid/a.json' }, y => { '$ref' => 'a.json#' } } }) };
    is $@, '', 'new finds both refs locally';
    for my $property (qw/x y/) {
        my ($r, $e) = $v->validate_schema({ $property => 'no' });
        is $r, 0, "$property applies the definition";
        like errors_text($e), qr{^type mismatch .*\[schema path: /properties/$property/}, "$property says why";
    }
};

subtest 'a document loaded during validation does not change later results' => sub {
    my $replacing = '{"definitions":{"a":{"$id":"http://e.invalid/s.json","type":"integer"}}}';
    my $partial = '{"definitions":{"a":{"$id":"http://e.invalid/a.json","type":"integer"},"b":{"$id":"rel.json"}}}';
    for my $case (
        ['an $id naming a preloaded document', $replacing,
            [{ '$ref' => 'http://e.invalid/s.json' }, { '$ref' => 'urn:example:doc' }],
            'exception: Failed to load resource urn:example:doc: $id http://e.invalid/s.json is already defined'
            . ' [instance path: /] [schema path: /allOf/1/$ref(urn:example:doc)]'],
        ['an $id that cannot be resolved', $partial,
            [{ '$ref' => 'urn:example:doc' }, { '$ref' => 'http://e.invalid/a.json' }]],
    ) {
        my ($name, $doc, $all_of, $expected) = @$case;
        my $v = JSONSchema::Validator::Draft7->new(schema => { allOf => $all_of },
            documents => { 'http://e.invalid/s.json' => { type => 'string' } },
            scheme_handlers => { urn => sub { (\$doc, 'JSON') }, http => sub { die "no network\n" } });
        my ($r1, $e1) = $v->validate_schema('abc');
        my ($r2, $e2) = $v->validate_schema('abc');
        is $r2, $r1, "$name: same result on the second call";
        is errors_text($e2), errors_text($e1), "$name: same errors on the second call";
        is errors_text($e1), $expected, "$name: the error names the conflict" if defined $expected;
    }
};

subtest 'a file loaded during validation that redefines another names neither by its path' => sub {
    my $v = JSONSchema::Validator::Draft7->new(schema => { allOf => [
        { '$ref' => 'file://' . test_dir('data/remote_fetching/integer.json') },
        { '$ref' => 'file://' . test_dir('data/remote_fetching/redefines_integer.json') } ] });
    my ($r, $e) = $v->validate_schema(1);
    is $r, 0, 'validation fails';
    is_deeply [map { $_->message } @$e],
        ['exception: Failed to load resource redefines_integer.json: $id integer.json is already defined'],
        'the error names both files without their directory';
};


subtest 'an unknown scheme is not read as a local file' => sub {
    my %refuse = (
        base_uri => 'urn:example:schema',
        scheme_handlers => { file => sub { die "local files are disabled\n" } },
    );
    # URI parses a drive letter as a scheme
    for my $ref ('zz:no_such.json', 'C:/no_such.json') {
        my $v = JSONSchema::Validator::Draft7->new(schema => { '$ref' => $ref }, %refuse);
        my ($r, $e) = $v->validate_schema(1);
        is $r, 0, "$ref fails";
        unlike errors_text($e), qr/does not exist/, "$ref is not looked up on disk";
    }
};

subtest 'the scan at new checks a ref target once however the ref is spelled' => sub {
    my @word = split //, 'definitions';
    my @refs;
    for my $mask (0 .. 1599) {
        my $spelling = join '',
            map { $mask & (1 << $_) ? sprintf('%%%02x', ord $word[$_]) : $word[$_] } 0 .. $#word;
        push @refs, { '$ref' => "#/$spelling/a" };
    }
    my $start = Time::HiRes::time();
    is construct('JSONSchema::Validator::Draft7', schema => {
            definitions => { a => { properties => { map { ("p$_" => { type => 'integer' }) } 1 .. 1000 } } },
            items => \@refs }),
        'ok', 'new succeeds';
    cmp_ok Time::HiRes::time() - $start, '<', 2, '1600 spellings of a ref to 1000 properties';
};

subtest 'the scan at new follows a long chain of local refs without warnings' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my %definitions = map {
        ("d$_" => { properties => { next => { '$ref' => '#/definitions/d' . ($_ + 1) } } })
    } 0 .. 198;
    $definitions{d199} = { type => 'integer' };
    is construct('JSONSchema::Validator::Draft7',
            schema => { '$ref' => '#/definitions/d0', definitions => \%definitions }),
        'ok', 'new succeeds';
    is_deeply \@warnings, [], '200 definitions linked by $ref';
};
ok detect_warnings() == 0, 'no warnings';

done_testing;
