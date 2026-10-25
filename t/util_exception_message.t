#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/detect_warnings/;
use JSONSchema::Validator::Util qw(exception_message);

subtest 'source locations are removed' => sub {
    for my $case (
        ["boom at /a/b/Foo.pm line 12.\n", 'boom', 'module'],
        ["boom at t/x.t line 3.\n", 'boom', 'test'],
        ["boom at (eval 3) line 1.\n", 'boom', 'eval'],
        ["boom at -e line 1.\n", 'boom', 'one-liner'],
        ["cannot fetch at /srv/app/app.psgi line 42.\n", 'cannot fetch', 'psgi file'],
        ["boom at script/myapp line 7.\n", 'boom', 'script without an extension'],
        ["boom at /srv/My App/handler.cgi line 7.\n", 'boom', 'path with a space'],
        ["boom at x.pl line 1, <\$fh> line 5.\n", 'boom', 'filehandle line'],
        ["boom at x.pl line 1, <STDIN> chunk 2.\n", 'boom', 'filehandle chunk'],
        ["outer at A.pm line 1.\n\tinner at B.pm line 2.\n", 'outer inner', 'stacked'],
    ) {
        my ($message, $expected, $name) = @$case;
        is exception_message($message), $expected, $name;
    }
};

subtest 'other text is kept' => sub {
    is exception_message("value at index 3 is bad at Foo.pm line 9.\n"), 'value at index 3 is bad',
        '"at" in the message';
    is exception_message('see the note at line 4 of the spec'), 'see the note at line 4 of the spec',
        'a line number in the message';
};

ok detect_warnings() == 0, 'no warnings';
done_testing;
