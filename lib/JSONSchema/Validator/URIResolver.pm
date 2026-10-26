package JSONSchema::Validator::URIResolver;

# ABSTRACT: URI resolver

use strict;
use warnings;
use Carp 'croak';

use Scalar::Util qw(weaken refaddr);

use URI;
use URI::Escape;
use Encode;

use JSONSchema::Validator::JSONPointer 'json_pointer';
use JSONSchema::Validator::BundledSchemas 'bundled_schema';
use JSONSchema::Validator::Util qw( load_schema resolve_uri exception_message is_load_failure resource_name discriminator_ref );

# what keys contain the schema? Required to find an $id in a schema
my $SEARCH_ID = {
    value => {
        additionalItems => 1,
        items => 1,
        additionalProperties => 1,
        not => 1,
        propertyNames => 1,
        contains => 1,
        if => 1,
        then => 1,
        else => 1
    },
    kv_value => {
        properties => 1,
        patternProperties => 1,
        dependencies => 1,
        definitions => 1
    },
    arr_value => {
        items => 1,
        allOf => 1,
        anyOf => 1,
        oneOf => 1
    }
};

# keywords whose values are instances, not schemas: a "$ref" inside one is data
my %DATA_KEYWORDS = map { $_ => 1 } qw(enum const default examples example);

# OpenAPI 3.0 objects whose keys are names, so a key such as "default" is not a keyword
my %OAS_NAME_MAPS = map { $_ => 1 } qw(
    paths responses content headers encoding links callbacks
    schemas parameters requestBodies securitySchemes properties
);

sub new {
    my ($class, %params) = @_;

    croak 'URIResolver: validator must be specified' unless $params{validator};
    croak 'URIResolver: schema must be specified' unless defined $params{schema};

    my $validator   = $params{validator};
    my $schema      = $params{schema};
    my $base_uri    = $params{base_uri} // '';

    my $scheme_handlers     = $params{scheme_handlers} // {};
    my $fetch_remote        = $params{fetch_remote} // 0;
    my $documents           = $params{documents} // {};

    weaken($validator);

    my $self = {
        validator => $validator,
        cache => {},
        scheme_handlers => $scheme_handlers,
        fetch_remote => $fetch_remote
    };

    bless $self, $class;

    $base_uri = $self->_add_document($base_uri, $schema);

    $self->cache_id(URI->new($base_uri), $schema) if $validator->using_id_with_ref && ref $schema eq 'HASH';

    # a document must not silently replace the schema, another document or an $id in either
    my %document_keys;
    for my $document_uri (sort keys %$documents) {
        my $key = _document_key($document_uri);
        croak "documents: $key is already defined"
            if exists $self->{cache}{$key} && $self->{cache}{$key} != $documents->{$document_uri};
        $document_keys{$document_uri} = $self->_add_document($document_uri, $documents->{$document_uri});
    }
    for my $document_uri (sort keys %$documents) {
        my $document = $documents->{$document_uri};
        next unless $validator->using_id_with_ref && ref $document eq 'HASH';
        $self->cache_id(URI->new($document_keys{$document_uri}), $document, 1);
    }

    # fail now, not when some later instance reaches the reference
    unless ($fetch_remote) {
        $self->_check_remote_refs($schema, $base_uri);
        $self->_check_remote_refs($documents->{$_}, $_) for keys %$documents;
    }

    return $self;
}

sub validator { shift->{validator} }
sub scheme_handlers { shift->{scheme_handlers} }
sub fetch_remote { shift->{fetch_remote} }
sub cache { shift->{cache} }

sub _document_key {
    my ($uri) = @_;
    return '#' eq substr($uri, -1) ? substr($uri, 0, -1) : $uri;
}

# Caches the schema under the uri without an empty fragment; returns that key.
sub _add_document {
    my ($self, $uri, $schema) = @_;

    my $key = _document_key($uri);
    $self->{cache}{$key} = $schema;

    return $key;
}

# self - URIResolver
# origin_uri - URI
# return (scope|string, schema)
sub resolve {
    my ($self, $origin_uri, %options) = @_;

    return ($origin_uri->as_string, $self->cache->{$origin_uri->as_string}) if exists $self->cache->{$origin_uri->as_string};

    my $uri = $origin_uri->clone;
    $uri->fragment(undef);

    my $schema = $self->cache_resolve($uri);
    return $self->fragment_resolve($origin_uri, $schema, %options);
}

# true when resolve can return uri without loading anything
sub is_preloaded {
    my ($self, $uri) = @_;

    my $document = $uri->clone;
    $document->fragment(undef);
    return exists $self->cache->{$uri->as_string}
        || exists $self->cache->{$document->as_string}
        || defined bundled_schema($document->as_string);
}

# self - URIResolver
# uri - URI
# return schema
sub cache_resolve {
    my ($self, $uri) = @_;

    my $scheme = $uri->scheme;

    return $self->cache->{$uri->as_string} if exists $self->cache->{$uri->as_string};

    my $schema = bundled_schema($uri->as_string);

    if (!defined $schema) {
        my $is_web = $scheme && ($scheme eq 'http' || $scheme eq 'https');

        # A handler for the scheme is the caller opting in to it.
        _croak_remote_disabled($uri) if $is_web && !$self->fetch_remote && !exists $self->scheme_handlers->{$scheme};

        $schema = load_schema($uri->as_string, $self->scheme_handlers);
    }

    my %known = map { $_ => 1 } keys %{$self->cache};
    $self->cache->{$uri->as_string} = $schema;

    if ($self->validator->using_id_with_ref) {
        unless (eval { $self->cache_id($uri, $schema, 1); 1 }) {
            my $error = $@;
            # a half-indexed document would let the next call find some of its $ids and not fail
            delete @{$self->cache}{grep { !$known{$_} } keys %{$self->cache}};
            die $error if is_load_failure($error);
            croak sprintf('Failed to load resource %s: %s', resource_name($uri->as_string), exception_message($error));
        }
    }

    return $schema;
}

sub _croak_remote_disabled {
    my ($uri) = @_;
    croak sprintf('Remote fetching is disabled: cannot load %s. Preload it with "documents" or pass fetch_remote => 1',
        $uri->as_string);
}

# Croaks on any reference cache_resolve would refuse to load, using the same scoping as validation.
# The scan follows local references, and searches a JSON Schema only where schemas can be and an
# OpenAPI document everywhere but data and the extensions of objects that allow them.
# context: ref_target - data is a $ref target, whose $id is already in scope (as in validation);
# components - data is the OpenAPI Components Object
sub _check_remote_refs {
    my ($self, $data, $scope, $seen, %context) = @_;
    $seen //= {};

    if (ref $data eq 'ARRAY') {
        $self->_check_remote_refs($_, $scope, $seen) for @$data;
        return;
    }
    return unless ref $data eq 'HASH';
    # a schema built in Perl can contain itself, and a $ref can lead back to where it is
    return if $seen->{"$scope\0" . refaddr $data}++;

    # siblings of $ref are ignored (draft 4-7, OpenAPI 3.0), so are not searched
    if (exists $data->{'$ref'}) {
        $self->_check_remote_ref($data->{'$ref'}, $scope, $seen) unless ref $data->{'$ref'};
        return;
    }

    my $id = $data->{$self->validator->ID_FIELD};
    if ($self->validator->using_id_with_ref && !$context{ref_target} && defined $id && !ref $id) {
        $scope = eval { resolve_uri($id, $scope)->as_string } // $scope;
    }

    my $is_oas = $self->validator->SPECIFICATION eq 'OAS30';
    for my $key (keys %$data) {
        my $value = $data->{$key};
        my $is_name_map = $SEARCH_ID->{kv_value}{$key} || ($is_oas && $OAS_NAME_MAPS{$key});
        if ($is_name_map && ref $value eq 'HASH') {
            # the Paths and Responses Objects allow extensions; components.responses keys are names
            my $is_extensible = $is_oas && ($key eq 'paths' || ($key eq 'responses' && !$context{components}));
            for my $name (keys %$value) {
                next if $is_extensible && $name =~ /^x-/;
                $self->_check_remote_refs($value->{$name}, $scope, $seen);
            }
        } elsif ($SEARCH_ID->{value}{$key} || $SEARCH_ID->{arr_value}{$key}) {
            $self->_check_remote_refs($value, $scope, $seen);
        } elsif ($is_oas && $key eq 'discriminator') {
            my $mapping = ref $value eq 'HASH' ? $value->{mapping} : undef;
            next unless ref $mapping eq 'HASH';
            for my $target (values %$mapping) {
                $self->_check_remote_ref(discriminator_ref($target), $scope, $seen) if defined $target && !ref $target;
            }
        } elsif ($is_oas && !$DATA_KEYWORDS{$key} && $key !~ /^x-/) {
            $self->_check_remote_refs($value, $scope, $seen, $key eq 'components' ? (components => 1) : ());
        }
    }
}

sub _check_remote_ref {
    my ($self, $ref, $scope, $seen) = @_;

    # a reference that can't be resolved at all is reported by validation
    my $uri = eval { resolve_uri($ref, $scope) } or return;

    my $document = $uri->clone;
    $document->fragment(undef);

    if (exists $self->cache->{$uri->as_string} || exists $self->cache->{$document->as_string}) {
        # a walk that stops at a $ref returns that $ref object, which is then checked like any other
        my @target = eval {
            $self->fragment_resolve($uri, $self->cache->{$document->as_string}, cached_only => 1)
        } or return;
        $self->_check_remote_refs($target[1], $target[0], $seen, ref_target => 1);
        return;
    }

    my $scheme = $uri->scheme // '';
    return unless $scheme eq 'http' || $scheme eq 'https';
    return if exists $self->scheme_handlers->{$scheme};

    return if $self->is_preloaded($uri);

    _croak_remote_disabled($document);
}

# self - URIResolver
# uri - URI
# schema - HASH/ARRAY
# return (scope|string, schema)
sub fragment_resolve {
    my ($self, $uri, $schema, %options) = @_;
    return ($uri->as_string, $self->cache->{$uri->as_string}) if exists $self->cache->{$uri->as_string};

    my $enc = Encode::find_encoding("UTF-8");
    my $fragment = $enc->decode(uri_unescape($uri->fragment), 1);

    my $pointer = json_pointer->new(
        scope => $uri->as_string,
        value => $schema,
        validator => $self->validator,
        resolver => $self
    );

    # try to use fragment as json pointer
    $pointer = $pointer->document_get($fragment, %options);
    my $subschema = $pointer->value;
    my $current_scope = $pointer->scope;

    # a cached_only walk can stop at a $ref, which is not the value of this uri
    $self->cache->{$uri->as_string} = $subschema unless $options{cached_only};

    return ($current_scope, $subschema);
}

# self - URIResolver
# uri - URI
# schema - HASH/ARRAY
# croak_on_conflict - croak instead of replacing an entry for a different schema
sub cache_id {
    my ($self, $uri, $schema, $croak_on_conflict) = @_;

    # try to find id/$id and cache it to properly handle links in $ref
    # https://json-schema.org/understanding-json-schema/structuring.html#using-id-with-ref

    my $scopes = [$uri];
    $self->cache_id_dfs($schema, $scopes, $croak_on_conflict);
}

# self - URIResolver
# schema - HASH/ARRAY
# scopes - [URI, ...]
sub cache_id_dfs {
    my ($self, $schema, $scopes, $croak_on_conflict) = @_;
    return unless ref $schema eq 'HASH';

    # skip all fields (id field too) if $ref present (draft 4-7)
    return if exists $schema->{'$ref'};

    if (exists $schema->{$self->validator->ID_FIELD} && !ref $schema->{$self->validator->ID_FIELD}) {
        my $id = resolve_uri($schema->{$self->validator->ID_FIELD}, $scopes->[-1]);
        my $key = _document_key($id->as_string);

        my $existing = $self->cache->{$key};
        croak "documents: $key is already defined"
            if $croak_on_conflict && defined $existing && $existing != $schema;
        $self->cache->{$key} = $schema;
        push @$scopes, $id;
    }

    for my $k (keys %$schema) {
        if ($SEARCH_ID->{value}{$k} && ref $schema->{$k} eq 'HASH') {
            $self->cache_id_dfs($schema->{$k}, $scopes, $croak_on_conflict);
        }

        if ($SEARCH_ID->{arr_value}{$k} && ref $schema->{$k} eq 'ARRAY') {
            for my $value (@{$schema->{$k}}) {
                next unless ref $value eq 'HASH';
                $self->cache_id_dfs($value, $scopes, $croak_on_conflict);
            }
        }

        if ($SEARCH_ID->{kv_value}{$k} && ref $schema->{$k} eq 'HASH') {
            for my $kv_key (keys %{$schema->{$k}}) {
                my $value = $schema->{$k}{$kv_key};
                next unless ref $value eq 'HASH';
                $self->cache_id_dfs($value, $scopes, $croak_on_conflict);
            }
        }
    }

    if (exists $schema->{$self->validator->ID_FIELD} && !ref $schema->{$self->validator->ID_FIELD}) {
        pop @$scopes;
    }
}

1;
