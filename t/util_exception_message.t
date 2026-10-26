#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Time::HiRes ();

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

subtest 'locations followed by a compile error note are removed' => sub {
    for my $case (
        [qq{syntax error at /srv/app/lib/My/Loader.pm line 3, near "+*"\nCompilation failed in require at /srv/app/app.psgi line 10.\n},
            'syntax error, near "+*" Compilation failed in require', 'near'],
        ["syntax error at /srv/app/lib/My/Loader.pm line 3, at EOF\n", 'syntax error, at EOF', 'at EOF'],
    ) {
        my ($message, $expected, $name) = @$case;
        is exception_message($message), $expected, $name;
    }
};

subtest 'stripping takes linear time' => sub {
    my $message = 'boom at x' . (' line 1, <aaaa' x 16000);
    my $start = Time::HiRes::time();
    exception_message($message);
    cmp_ok Time::HiRes::time() - $start, '<', 1, '16000 unterminated filehandle notes';
};

ok detect_warnings() == 0, 'no warnings';
done_testing;
