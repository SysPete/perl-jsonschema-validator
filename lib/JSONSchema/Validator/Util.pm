package JSONSchema::Validator::Util;

# ABSTRACT: Internal helper functions

use strict;
use warnings;

use B ();
use Carp 'croak';
use File::Basename ();
use File::Fetch ();
use Scalar::Util qw( blessed looks_like_number );
use URI 1.00 ();

our @ISA = 'Exporter';
our @EXPORT_OK = qw(
    json_encode json_decode serialize unbool
    round is_type detect_type is_bignum json_equal canonical_json_key comparable_numbers format_number
    data_section load_schema resolve_uri exception_message is_load_failure resource_name
    discriminator_ref
);

use constant CONTENT_TYPE_JSON => 'JSON';
use constant CONTENT_TYPE_YAML => 'YAML';

use constant TYPE_MAP => {
    'array' => \&is_array,
    'boolean' => \&is_bool,
    'integer' => \&is_integer,
    'number' => \&is_number,
    'object' => \&is_object,
    'null' => \&is_null, # for OAS30 null is not defined
    'string' => \&is_string,

    # it is for some buggy code
    '_ref' => \&is_ref
};

# such order is required
use constant TYPE_LIST => ['array', 'object', 'null', '_ref', 'integer', 'number', 'boolean', 'string'];

BEGIN {
    # YAML
    if (eval { require YAML::XS; YAML::XS->VERSION(0.67); 1; }) {
        *yaml_load = sub { local $YAML::XS::Boolean = 'JSON::PP'; YAML::XS::Load(@_) };
    }
    elsif (eval { require YAML::PP; 1; }) {
        my $pp = YAML::PP->new(boolean => 'JSON::PP');
        *yaml_load = sub { $pp->load_string(@_) };
    } else {
        *yaml_load = sub { croak 'No YAML package installed' };
    }

    # JSON
    my $json_class;
    if (eval { require Cpanel::JSON::XS; 1; }) {
        $json_class = 'Cpanel::JSON::XS';
    } elsif (eval { require JSON::XS; JSON::XS->VERSION(3.0); 1; }) {
        $json_class = 'JSON::XS';
    } else {
        require JSON::PP;
        $json_class = 'JSON::PP';
    }
    my $json = $json_class->new->canonical(1)->utf8;
    *json_encode = sub { $json->encode(@_); };
    *json_decode = sub { $json->decode(@_); };
}

# URI->abs dies on a base without an authority, such as urn:uuid:...
sub resolve_uri {
    my ($ref, $base) = @_;

    $ref = URI->new("$ref");
    return $ref unless defined $base && length "$base";
    $base = URI->new("$base");

    # RFC 3986 5.2.2: the empty reference is the base document; URI->abs keeps its fragment
    if ("$ref" eq '') {
        my $resolved = $base->clone;
        $resolved->fragment(undef);
        return $resolved;
    }

    return $ref->abs($base) if $base->can('authority');
    return $ref if $ref->scheme;

    if ("$ref" =~ /\A#(.*)\z/s) {
        # URI::fragment runs a match of its own before reading its argument, which would reset $1
        my $fragment = $1;
        my $resolved = $base->clone;
        $resolved->fragment($fragment);
        return $resolved;
    }
    croak qq{cannot resolve relative reference "$ref" against non-hierarchical base "$base"};
}

sub unbool {
    my $x = shift;
    return "$x" if ref $x eq 'JSON::PP::Boolean';
    return $x if ref $x;
    return '1' if $x && $x eq '1';
    return '0' if !defined $x || $x eq '0' || $x eq '';
    return $x;
}

sub serialize { json_encode(shift) }

sub round {
    my $value = shift;
    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

sub load_schema {
    my ($resource, $scheme_handlers) = @_;

    my $name = resource_name($resource);
    my $path = _local_path($resource);
    my $named = sub {
        my ($reason) = @_;
        $reason =~ s/\Q$path\E/$name/g if defined $path;
        return $reason;
    };

    my ($content_ref, $content_type) = eval { get_content($resource, $scheme_handlers) };

    if ($@) {
        croak(sprintf('Failed to load resource %s: %s', $name, $named->($@)));
    }

    my $schema = eval { decode_content($content_ref, $content_type) };

    if ($@) {
        croak(sprintf('Failed to load resource %s as %s: %s', $name, $content_type, $named->($@))) if $content_type;
        croak(sprintf('Unsupported type of resource %s', $name));
    }

    return $schema;
}

sub _local_path {
    my ($resource) = @_;

    my $uri = blessed($resource) && $resource->isa('URI') ? $resource : URI->new("$resource");
    my $scheme = $uri->scheme;

    return undef if defined $scheme && $scheme ne 'file';
    my $path = defined $scheme ? $uri->file : "$resource";
    return defined $path && length $path ? $path : undef;
}

# An OAS30 discriminator mapping value is a reference only if it looks like one, else a schema name.
sub discriminator_ref {
    my ($value) = @_;
    return $value if $value =~ m|/| || $value =~ m/\.json$/;
    return '#/components/schemas/' . $value;
}

# Errors can reach API clients, so a local file is named by its base name, not its server path.
sub resource_name {
    my ($resource) = @_;
    my $path = _local_path($resource);
    return defined $path ? File::Basename::basename($path) : "$resource";
}

sub get_content {
    my ($resource, $scheme_handlers) = @_;

    my $uri = blessed($resource) && $resource->isa('URI') ? $resource : URI->new($resource);

    if ($uri->has_recognized_scheme) {
        if (my $scheme = $uri->scheme) {
            $scheme_handlers //= {};
            if (exists $scheme_handlers->{$scheme}) {
                return $scheme_handlers->{$scheme}->($uri);
            }
            elsif ($scheme eq 'http' || $scheme eq 'https') {
                return fetch_file($uri->canonical->as_string);
            }
            elsif ($scheme eq 'file') {
                return read_file($uri->file);
            }
            croak(sprintf('Unsupported scheme "%s" of URI %s', $scheme // '', $uri->as_string));
        }
    }

    # May it is path of local file without scheme?
    return read_file("$resource");
}

sub decode_content {
    my ($content_ref, $content_type) = @_;

    if ($content_type) {
        return yaml_load($$content_ref) if $content_type eq CONTENT_TYPE_YAML;
        return json_decode($$content_ref) if $content_type eq CONTENT_TYPE_JSON;
    }

    my $schema;

    # Try to guess.
    $schema = eval { json_decode($$content_ref) };
    $schema = yaml_load($$content_ref) if $@;

    return $schema;
}

sub detect_content_type_from_path {
    my ($path) = @_;

    my (undef, undef, $suffix) = File::Basename::fileparse($path, qr/\.[^.]+/);

    $suffix = lc($suffix);

    return CONTENT_TYPE_JSON if $suffix eq '.json';
    return CONTENT_TYPE_YAML if $suffix eq '.yaml';
    return CONTENT_TYPE_YAML if $suffix eq '.yml';
    return;
}

sub detect_content_type_from_content {
    my ($content_ref) = @_;

    return unless defined $content_ref && defined $$content_ref;

    return CONTENT_TYPE_JSON if $$content_ref =~ /^\s+[\{\[]/;
    return CONTENT_TYPE_YAML if $$content_ref =~ /^---[\n\r ]/;
    return CONTENT_TYPE_YAML if $$content_ref =~ /^%YAML [0-9]\.[0-9]+\b/;
    return;
}

sub fetch_file {
    my ($uri) = @_;

    my $file = File::Fetch->new(uri => $uri) or croak(File::Fetch->error);

    # Try to patch File::Fetch < 0.50 to support HTTPS scheme.
    if ($file->scheme eq 'https' && !exists $File::Fetch::METHODS->{https}) {
        require version;
        if (version->parse(File::Fetch->VERSION) < version->parse('0.50')) {
            $File::Fetch::METHODS->{https} = [
                eval { require LWP::Protocol::https } ? 'lwp' : (),
                qw( wget curl ),
            ];
        }
    }

    $file->fetch(to => \my $content) or croak($file->error // "Can't fetch file from $uri");

    my $content_type = detect_content_type_from_path($file->output_file)
                    || detect_content_type_from_content(\$content);

    return (\$content, $content_type);
}

sub read_file {
    my ($path) = @_;

    croak "File $path does not exists" unless -e $path;
    croak "File $path does not have read permission" unless -r _;

    my $size = -s _;

    open(my $fh, '<', $path) or croak "Open file $path error: $!";
    read($fh, (my $content), $size);
    close($fh);

    my $content_type = detect_content_type_from_path($path)
                    || detect_content_type_from_content(\$content);

    return (\$content, $content_type);
}

# params: $value, $type, $is_strict
sub is_type {
    return 0 unless exists TYPE_MAP->{$_[1]};
    return TYPE_MAP->{$_[1]}->($_[0], $_[2]);
}

# params: $value, $is_strict
sub detect_type {
    for my $type (@{TYPE_LIST()}) {
        return $type if TYPE_MAP->{$type}->(@_);
    }
    # it must be unreachable code
    croak 'Unknown type detected';
}

# params: $value, $is_strict
sub is_array {
    return ref $_[0] eq 'ARRAY';
}

# params: $value, $is_strict
sub is_bool {
    my $type = ref $_[0];
    return 1 if $type eq 'JSON::PP::Boolean' or
                $type eq 'JSON::XS::Boolean' or
                $type eq 'Cpanel::JSON::XS::Boolean';
    return 0 if $_[1]; # is strict
    my $is_number = looks_like_number($_[0]) && ($_[0] == 1 || $_[0] == 0);
    my $is_string = defined $_[0] && $_[0] eq '';
    my $is_undef = !defined $_[0];
    return 1 if $is_number || $is_string || $is_undef;
    return 0;
}

sub is_bignum {
    return 0 unless blessed($_[0]);
    return $_[0]->isa('Math::BigInt') || $_[0]->isa('Math::BigFloat') ? 1 : 0;
}

sub comparable_numbers {
    my ($x, $y) = @_;
    return ($x, $y) unless (ref $x && is_bignum($x)) || (ref $y && is_bignum($y));
    require Math::BigFloat;
    # a global accuracy or precision set by the host program would round these
    local ($Math::BigFloat::accuracy, $Math::BigFloat::precision, $Math::BigInt::accuracy, $Math::BigInt::precision);
    # a bignum must not go through a string: "1e1000000000" would be written out in full
    return map {
        !ref $_ ? Math::BigFloat->new(_exact_number_string($_))
        : $_->isa('Math::BigFloat') ? $_->copy
        : Math::BigFloat->new($_)
    } $x, $y;
}

sub format_number {
    my ($n) = @_;
    return "$n" unless ref $n && is_bignum($n) && $n->isa('Math::BigFloat') && !$n->is_nan;
    return $n->is_inf || abs($n->exponent) <= 100 ? "$n" : $n->bsstr;
}

sub _exact_number_string {
    my ($n) = @_;
    # an integer Perl holds as IV/UV prints exactly; halving it below would make it a float
    return "$n" if ref $n || B::svref_2object(\$n)->FLAGS & B::SVf_IOK() || abs($n) == 9**9**9;

    # "$n" keeps 15 significant digits, so 0.1 + 0.2 would read as 0.3; take the shortest that reads back
    if (int($n) != $n) {
        for my $digits (15 .. 40) {
            my $s = sprintf '%.*g', $digits, $n;
            return $s if $s == $n;
        }
        return "$n";
    }

    # Perl stringifies a float to 15 significant digits, and older Windows C libraries
    # pad %.0f with zeros after 17, so halve (exact for a float) below 2**53 and shift back.
    my ($sign, $m, $shift) = ($n < 0 ? '-' : '', abs $n, 0);
    while ($m >= 2**53) { $m /= 2; $shift++ }
    return $sign . sprintf('%.0f', $m) unless $shift;

    require Math::BigInt;
    return $sign . Math::BigInt->new(sprintf('%.0f', $m))->blsft($shift)->bstr;
}

sub json_equal {
    my ($x, $y) = @_;

    return defined $y ? 0 : 1 unless defined $x;
    return 0 unless defined $y;

    # strict booleans are always references, so two plain scalars are numbers or strings
    if (!ref $x && !ref $y) {
        my $x_is_number = is_number($x, 1);
        return 0 unless $x_is_number == is_number($y, 1);
        return ($x eq $y ? 1 : 0) unless $x_is_number;
        return ($x == $y ? 1 : 0) if abs($x) < 2**53 && abs($y) < 2**53;
        # == turns an IV into a float, so 2**53+1 would equal the float 2**53
        require Math::BigFloat;
        local ($Math::BigFloat::accuracy, $Math::BigFloat::precision, $Math::BigInt::accuracy, $Math::BigInt::precision);
        return Math::BigFloat->new(_exact_number_string($x)) == Math::BigFloat->new(_exact_number_string($y)) ? 1 : 0;
    }

    if (is_bool($x, 1) || is_bool($y, 1)) {
        return 0 unless is_bool($x, 1) && is_bool($y, 1);
        return ($x ? 1 : 0) == ($y ? 1 : 0) ? 1 : 0;
    }

    if (is_number($x, 1) || is_number($y, 1)) {
        return 0 unless is_number($x, 1) && is_number($y, 1);
        my ($nx, $ny) = comparable_numbers($x, $y);
        return $nx == $ny ? 1 : 0;
    }

    if (is_array($x) || is_array($y)) {
        return 0 unless is_array($x) && is_array($y) && @$x == @$y;
        for my $i (0 .. $#$x) {
            return 0 unless json_equal($x->[$i], $y->[$i]);
        }
        return 1;
    }

    if (is_object($x) || is_object($y)) {
        return 0 unless is_object($x) && is_object($y) && keys %$x == keys %$y;
        for my $key (keys %$x) {
            return 0 unless exists $y->{$key} && json_equal($x->{$key}, $y->{$key});
        }
        return 1;
    }

    return 0 unless is_string($x, 1) && is_string($y, 1);
    return $x eq $y ? 1 : 0;
}

{
    my $unique = 0;

    # Values that json_equal finds equal get the same key, and in practice nothing else does.
    sub canonical_json_key {
        my ($x) = @_;

        return 'n' unless defined $x;
        if (!ref $x) {
            return is_number($x, 1) ? _number_key($x) : 's' . length($x) . ':' . $x;
        }
        return 'b' . ($x ? 1 : 0) if is_bool($x, 1);
        return _number_key($x) if is_number($x, 1);
        return '[' . join(',', map { canonical_json_key($_) } @$x) . ']' if is_array($x);
        if (is_object($x)) {
            return '{' . join(',', map {
                's' . length($_) . ':' . $_ . '=' . canonical_json_key($x->{$_})
            } sort keys %$x) . '}';
        }
        return 'u' . $unique++;
    }

    sub _number_key {
        my ($n) = @_;

        my ($sign, $digits, $exponent);
        if (ref $n) {
            return 'u' . $unique++ if $n->is_nan;
            return $n->is_inf('-') ? 'd-inf' : 'dinf' if $n->is_inf;
            # parts is mantissa and exponent without writing out the zeros
            my ($m, $e) = $n->isa('Math::BigFloat') ? $n->parts : ($n->copy, 0);
            ($sign, $digits, $exponent) = ($m < 0 ? '-' : '', $m->copy->babs->bstr, "$e");
        } else {
            return 'u' . $unique++ if $n != $n;
            return $n < 0 ? 'd-inf' : 'dinf' if abs($n) == 9**9**9;
            my $s = _exact_number_string($n);
            $s =~ /\A([-+]?)(\d*)(?:\.(\d*))?(?:[eE]([-+]?\d+))?\z/ or return 'u' . $unique++;
            my $frac = $3 // '';
            ($sign, $digits, $exponent) = ($1 eq '-' ? '-' : '', $2 . $frac, ($4 // 0) - length $frac);
        }

        $digits =~ s/\A0+//;
        return 'd0' if $digits eq '';
        $digits =~ s/(0+)\z// and $exponent += length $1;
        return "d$sign${digits}e$exponent";
    }
}

# params: $value, $is_strict
sub is_integer {
    return 1 if B::svref_2object(\$_[0])->FLAGS & B::SVf_IOK();
    return $_[0]->is_int ? 1 : 0 if ref $_[0] && is_bignum($_[0]);
    return 0 if $_[1]; # is strict
    return 0 if ref $_[0];
    return 1 if looks_like_number($_[0]) && int($_[0]) == $_[0];
    return 0;
}

# params: $value, $is_strict
sub is_number {
    return 1 if B::svref_2object(\$_[0])->FLAGS & (B::SVf_IOK() | B::SVf_NOK());
    return 1 if ref $_[0] && is_bignum($_[0]);
    return 0 if $_[1]; # is strict
    return 0 if ref $_[0];
    return 1 if looks_like_number($_[0]);
    return 0;
}

# params: $value, $is_strict
sub is_ref {
    my $ref = ref $_[0];
    return 0 unless $ref;
    return 0 if $ref eq 'JSON::PP::Boolean' ||
                $ref eq 'HASH' ||
                $ref eq 'ARRAY';
    return 0 if is_bignum($_[0]);
    return 1;
}

# params: $value, $is_strict
sub is_object {
    return ref $_[0] eq 'HASH';
}

# params: $value, $is_strict
sub is_null {
    return !(defined $_[0]);
}

# params: $value, $is_strict
sub is_string {
    return !(ref $_[0]) && !is_number(@_) && defined $_[0] if $_[1]; # is strict
    return !(ref $_[0]) && defined $_[0];
}

# Errors can reach API clients, so drop the "at FILE line N." locations Perl adds.
sub is_load_failure {
    my ($exception) = @_;
    return !ref $exception && $exception =~ /\A(?:Failed to load resource |Remote fetching is disabled: )/;
}

sub exception_message {
    my ($message) = @_;
    # any file name, since a handler that dies may live in app.psgi or bin/app
    $message =~ s/ at (?:(?! at ).)+? line \d+(?:, <[^>]*> (?:line|chunk) \d+)?\.?(?=\s|\z)//g;
    $message =~ s/\s+/ /g;
    $message =~ s/\A | \z//g;
    return $message;
}

sub data_section {
    my $class = shift;
    my $handle = do { no strict 'refs'; \*{"${class}::DATA"} };
    return unless fileno $handle;
    seek $handle, 0, 0;
    local $/ = undef;
    my $data = <$handle>;
    $data =~ s/^.*\n__DATA__\r?\n//s;
    $data =~ s/\r?\n__END__\r?\n.*$//s;
    return $data;
}

1;

__END__

=head1 DESCRIPTION

Internal helper functions for the validator classes. This module is not a
public interface: its functions may change or be removed in any release.
Use L<JSONSchema::Validator> and the validator classes instead.
