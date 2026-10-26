package JSONSchema::Validator::JSONPointer;

# ABSTRACT: JSON Pointer with URI resolving

use strict;
use warnings;
use URI;
use JSONSchema::Validator::Util 'resolve_uri';
use Carp 'croak';

use Scalar::Util 'weaken';

use overload
    'bool' => sub { $_[0]->value },
    fallback => 1;

our @ISA = 'Exporter';
our @EXPORT_OK = qw(json_pointer);

sub json_pointer {
    return __PACKAGE__;
}

sub append {
    my ($class, $path, @values) = @_;
    my $suffix = join('/', map { $class->escape($_) } @values);
    return $path =~ m!/$!
        ? $path . $suffix
        : $path . '/' . $suffix;
}

sub join {
    my ($class, @parts) = @_;
    return '/' . join('/', map { $class->escape($_) } @parts);
}

sub escape {
    my ($class, $value) = @_;
    $value =~ s!~!~0!g;
    $value =~ s!/!~1!g;
    return $value;
}

sub unescape {
    my ($class, $value) = @_;
    $value =~ s!~1!/!g;
    $value =~ s!~0!~!g;
    return $value;
}

sub new {
    my ($class, %params) = @_;

    my ($scope, $value, $validator) = @params{qw/scope value validator/};

    croak 'JSONPointer: scope is required' unless defined $scope;
    croak 'JSONPointer: validator is required' unless $validator;

    weaken($validator);

    my $self = {
        scope => $scope,
        value => $value,
        validator => $validator
    };

    bless $self, $class;

    return $self;
}

sub validator { shift->{validator} }
sub scope { shift->{scope} }
sub value { shift->{value} }

sub xget {
    my ($self, @parts) = @_;
    return $self->_walk(1, undef, @parts);
}

sub get {
    # pointer is string which is already urldecoded and utf8-decoded
    my ($self, $pointer) = @_;
    return $self unless $pointer;
    return $self->_walk(1, undef, $self->_split($pointer));
}

sub document_get {
    my ($self, $pointer, %options) = @_;
    return $self unless $pointer;
    # a cached_only walk carries the $ref targets it has entered, so a cycle ends it like an unpreloaded $ref
    my $visited = $options{cached_only} ? $options{visited} // {} : undef;
    return $self->_walk(0, $visited, $self->_split($pointer));
}

sub _split {
    my ($self, $pointer) = @_;

    croak "Invalid JSON Pointer $pointer" unless $pointer =~ s!^/!!;

    return length $pointer
        ? map { $self->unescape($_) } split(/\//, $pointer, -1)
        : ('');
}

sub _walk {
    my ($self, $follow_start, $visited, @parts) = @_;

    my ($current_scope, $current_value, $stopped) =
        $self->_enter($self->scope, $self->value, $follow_start, $visited);

    for my $part (@parts) {
        last if $stopped;

        if (ref $current_value eq 'HASH' && exists $current_value->{$part}) {
            $current_value = $current_value->{$part};
        } elsif (ref $current_value eq 'ARRAY' && $part =~ m/^\d+$/ && scalar(@$current_value) > $part) {
            $current_value = $current_value->[$part];
        } else {
            $current_value = undef;
            last;
        }

        ($current_scope, $current_value, $stopped) =
            $self->_enter($current_scope, $current_value, 1, $visited);
    }

    return __PACKAGE__->new(
        value => $current_value,
        scope => $current_scope,
        validator => $self->validator
    )
}

sub _enter {
    my ($self, $current_scope, $current_value, $follow, $visited) = @_;
    my $resolver = $self->validator->resolver;

    while ($follow && ref $current_value eq 'HASH' && $current_value->{'$ref'}) {
        my $ref = resolve_uri($current_value->{'$ref'}, $current_scope);
        return ($current_scope, $current_value, 1)
            if $visited && ($visited->{$ref->as_string}++ || !$resolver->is_preloaded($ref));
        ($current_scope, $current_value) =
            $resolver->resolve($ref, $visited ? (cached_only => 1, visited => $visited) : ());
    }

    if (ref $current_value eq 'HASH' && $self->validator->using_id_with_ref) {
        my $id = $current_value->{$self->validator->ID_FIELD};
        if ($id && !ref $id) {
            $current_scope = $current_scope
                ? resolve_uri($id, $current_scope)->as_string
                : $id;
        }
    }

    return ($current_scope, $current_value, 0);
}

sub keys {
    my ($self, %params) = @_;
    my $raw = $params{raw} // 0;

    if (ref $self->value eq 'HASH') {
        return map { $raw ? $_ : $self->join($_) } keys %{$self->value};
    }

    if (ref $self->value eq 'ARRAY') {
        return map { $raw ? $_ : $self->join($_) } 0 .. $#{$self->value};
    }

    return;
}

1;
