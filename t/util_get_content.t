#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use URI ();
use URI::file ();

use JSONSchema::Validator::Util ();

use lib qw( t/lib );

use Helper qw( test_dir );


my $p = test_dir('/data/json_schema/draft4/basic.json');

ok ${(JSONSchema::Validator::Util::get_content($p))[0]};
ok ${(JSONSchema::Validator::Util::get_content('file://' . $p))[0]};
ok ${(JSONSchema::Validator::Util::get_content(URI::file->new($p)))[0]};
ok ${(JSONSchema::Validator::Util::get_content(URI->new($p, 'file')))[0]};

#my $u = 'http://httpbin.org';
#
#ok ${(JSONSchema::Validator::Util::get_content($u))[0]};
#ok ${(JSONSchema::Validator::Util::get_content(URI->new($u)))[0]};


subtest 'a drive letter is a path' => sub {
    eval { JSONSchema::Validator::Util::get_content('C:/no_such_dir/x.json') };
    like $@, qr/does not exist/, 'read as a file when no handler is given';
    eval { JSONSchema::Validator::Util::get_content('zz:x.json') };
    like $@, qr/^Unsupported scheme "zz"/, 'an unknown scheme is refused';

    my $seen;
    JSONSchema::Validator::Util::get_content('C:/x.json', { file => sub { $seen = shift; return } });
    isa_ok $seen, 'URI::file', 'what a file handler receives';
    like "$seen", qr{C:/x\.json\z}, 'and it names the path';
};

subtest 'a load failure names a drive-letter path by its base name' => sub {
    eval { JSONSchema::Validator::Util::load_schema('C:/no_such_dir/x.json') };
    like $@, qr/^Failed to load resource x\.json: /, 'the file is named';
    unlike $@, qr/no_such_dir/, 'its directory is not';
};

done_testing;
