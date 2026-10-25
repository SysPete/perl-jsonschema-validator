package Bench::OpenAPIDocument;

use strict;
use warnings;
use JSON::PP ();

# 22 $refs per resource plus 1 shared gives 2091 $refs at the default.
use constant DEFAULT_ENTITIES => 95;

=head1 NAME

Bench::OpenAPIDocument - synthetic OpenAPI 3.0.3 document for benchmarks

=head1 FUNCTIONS

=head2 build

    my $doc = Bench::OpenAPIDocument::build(entities => $n);

Returns a deterministic OpenAPI 3.0.3 document as a hashref, with C<$n>
resources named C<r001>, C<r002>... (default 95). Each resource C<R> has the
schemas C<R>, C<RSummary> and C<RCreate>, and the paths C</R> and
C</R/{id}>.

=cut

sub build {
    my (%params) = @_;
    my $entities = $params{entities} // DEFAULT_ENTITIES;

    my @names = map { sprintf 'r%03d', $_ } 1 .. $entities;
    my $doc = {
        openapi => '3.0.3',
        info => { title => 'Synthetic benchmark API', version => '1' },
        paths => {},
        components => {
            schemas => {
                Error => {
                    type => 'object',
                    required => [qw(code message)],
                    properties => {
                        code => { type => 'integer' },
                        message => { type => 'string' },
                    },
                },
            },
            parameters => {
                Id => _parameter('id', 'path', { type => 'integer', minimum => 1 }, 1),
                Limit => _parameter('limit', 'query', { type => 'integer', minimum => 1, maximum => 100 }),
                Offset => _parameter('offset', 'query', { type => 'integer', minimum => 0 }),
                Sort => _parameter('sort', 'query', { type => 'string', enum => [qw(name created_at)] }),
            },
            responses => {
                Error => {
                    description => 'error',
                    content => { 'application/json' => { schema => _ref('schemas', 'Error') } },
                },
            },
        },
    };

    for my $i (0 .. $#names) {
        my $name = $names[$i];
        my $next = $names[($i + 1) % @names];
        my $previous = $names[$i - 1];
        _add_resource($doc, $name, $next, $previous);
    }

    return $doc;
}

=head2 count_refs

    my $n = Bench::OpenAPIDocument::count_refs($doc);

Returns the number of C<$ref> keys anywhere in C<$doc>.

=cut

sub count_refs {
    my ($data) = @_;

    if (ref $data eq 'HASH') {
        my $count = exists $data->{'$ref'} ? 1 : 0;
        $count += count_refs($_) for values %$data;
        return $count;
    }
    if (ref $data eq 'ARRAY') {
        my $count = 0;
        $count += count_refs($_) for @$data;
        return $count;
    }
    return 0;
}

sub _add_resource {
    my ($doc, $name, $next, $previous) = @_;
    my $schemas = $doc->{components}{schemas};

    $schemas->{$name} = {
        type => 'object',
        required => [qw(id name status)],
        properties => {
            id => { type => 'integer', minimum => 1 },
            name => { type => 'string', minLength => 1, maxLength => 100 },
            count => { type => 'integer', minimum => 0 },
            price => { type => 'number', minimum => 0 },
            active => { type => 'boolean' },
            note => { type => 'string', nullable => _true() },
            parent_id => { type => 'integer', nullable => _true() },
            status => { type => 'string', enum => [qw(draft active archived)] },
            created_at => { type => 'string', format => 'date-time' },
            address => {
                type => 'object',
                properties => {
                    street => { type => 'string' },
                    city => { type => 'string' },
                    postcode => { type => 'string', pattern => '^[A-Z0-9 ]{3,10}$' },
                },
            },
            related => { type => 'array', items => _ref('schemas', "${next}Summary") },
            previous => _ref('schemas', "${previous}Summary"),
            tags => { type => 'array', maxItems => 10, items => { type => 'string' } },
        },
    };
    $schemas->{"${name}Summary"} = {
        type => 'object',
        required => [qw(id name)],
        properties => {
            id => { type => 'integer', minimum => 1 },
            name => { type => 'string', minLength => 1 },
        },
    };
    $schemas->{"${name}Create"} = {
        type => 'object',
        required => [qw(name status)],
        properties => {
            name => { type => 'string', minLength => 1, maxLength => 100 },
            count => { type => 'integer', minimum => 0 },
            price => { type => 'number', minimum => 0 },
            active => { type => 'boolean' },
            note => { type => 'string', nullable => _true() },
            status => { type => 'string', enum => [qw(draft active archived)] },
            tags => { type => 'array', maxItems => 10, items => { type => 'string' } },
        },
    };

    # fresh hashes each time, so the document stays a tree
    my $item = sub { %{ _json_content(_ref('schemas', $name)) } };
    my $create = sub { +{ required => _true(), %{ _json_content(_ref('schemas', "${name}Create")) } } };

    $doc->{paths}{"/$name"} = {
        get => {
            parameters => [map { _ref('parameters', $_) } qw(Limit Offset Sort)],
            responses => _responses(200 => {
                description => 'list',
                %{ _json_content({ type => 'array', items => _ref('schemas', $name) }) },
            }),
        },
        post => {
            requestBody => $create->(),
            responses => _responses(201 => { description => 'created', $item->() }),
        },
    };
    $doc->{paths}{"/$name/{id}"} = {
        parameters => [_ref('parameters', 'Id')],
        get => { responses => _responses(200 => { description => 'item', $item->() }) },
        put => {
            requestBody => $create->(),
            responses => _responses(200 => { description => 'updated', $item->() }),
        },
        delete => { responses => _responses(204 => { description => 'deleted' }) },
    };
}

sub _responses {
    my ($status, $response) = @_;
    return {
        $status => $response,
        400 => _ref('responses', 'Error'),
        404 => _ref('responses', 'Error'),
    };
}

sub _json_content {
    my ($schema) = @_;
    return { content => { 'application/json' => { schema => $schema } } };
}

sub _parameter {
    my ($name, $in, $schema, $required) = @_;
    my $parameter = { name => $name, in => $in, schema => $schema };
    $parameter->{required} = _true() if $required;
    return $parameter;
}

sub _ref {
    my ($section, $name) = @_;
    return { '$ref' => "#/components/$section/$name" };
}

sub _true { JSON::PP::true() }

1;
