package JSONSchema::Validator::BundledSchemas;

# ABSTRACT: Meta-schemas shipped with the distribution

use strict;
use warnings;

use File::Basename ();
use URI::file;

use JSONSchema::Validator::Util qw( load_schema );

our @ISA = 'Exporter';
our @EXPORT_OK = qw( bundled_schema read_bundled_schema );

# canonical $id/id without the empty fragment => file in schemas/
my %FILE_FOR_ID = (
    'http://json-schema.org/draft-04/schema' => 'draft4',
    'http://json-schema.org/draft-06/schema' => 'draft6',
    'http://json-schema.org/draft-07/schema' => 'draft7',
    'https://spec.openapis.org/oas/3.0/schema/2019-04-02' => 'oas30',
);

my %CACHE;

=func read_bundled_schema

    my $schema = read_bundled_schema('draft7');

Reads a file from the F<schemas> directory by its base name, without caching.

=cut

sub read_bundled_schema {
    my ($name) = @_;
    my $dir = File::Basename::dirname(__FILE__);
    return load_schema(URI::file->new_abs($dir . '/schemas/' . lc($name) . '.json'));
}

=func bundled_schema

    my $schema = bundled_schema('http://json-schema.org/draft-07/schema#');

Returns the bundled meta-schema whose C<$id> (C<id> for Draft 4 and OpenAPI 3.0)
equals the given URI, with or without an empty trailing fragment, or C<undef>
if there is none. Each file is read once per process.

=cut

sub bundled_schema {
    my ($uri) = @_;
    return unless defined $uri;

    $uri =~ s/#\z//;
    my $name = $FILE_FOR_ID{$uri} or return;

    return $CACHE{$name} //= read_bundled_schema($name);
}

1;
