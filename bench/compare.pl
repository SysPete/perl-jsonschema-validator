#!/usr/bin/env perl

# Print a Markdown table of median ops/sec from run.pl outputs:
#   perl bench/compare.pl --old old-*.txt --new new-*.txt

use strict;
use warnings;

use Getopt::Long;

my (@old, @new);
GetOptions('old=s{1,}' => \@old, 'new=s{1,}' => \@new)
    or die "usage: $0 --old FILE... --new FILE...\n";
die "usage: $0 --old FILE... --new FILE...\n" unless @old && @new;

my $old = _medians(@old);
my $new = _medians(@new);

print "| workload | old | new | change |\n";
print "| --- | ---: | ---: | ---: |\n";
for my $name (sort keys %$new) {
    die "$name is missing from the --old files\n" unless exists $old->{$name};
    printf "| %s | %s | %s | %+.1f%% |\n", $name, _format($old->{$name}),
        _format($new->{$name}), 100 * ($new->{$name} / $old->{$name} - 1);
}

sub _medians {
    my (@files) = @_;
    my %ops;
    for my $file (@files) {
        open my $fh, '<', $file or die "$file: $!\n";
        while (my $line = <$fh>) {
            push @{ $ops{$1} }, $2 if $line =~ /^(\w+(?: \w+)*)\s+([\d.]+)\s+[\d.]+%$/;
        }
    }
    die "no results in @files\n" unless %ops;

    my %median;
    for my $name (keys %ops) {
        my @sorted = sort { $a <=> $b } @{ $ops{$name} };
        die "$name: expected one result per file\n" unless @sorted == @files;
        my $mid = int(@sorted / 2);
        $median{$name} = @sorted % 2 ? $sorted[$mid] : ($sorted[$mid - 1] + $sorted[$mid]) / 2;
    }
    return \%median;
}

# Same precision as the baseline tables: whole numbers, one decimal below 1000.
sub _format {
    my ($n) = @_;
    return $n >= 1000 ? sprintf('%.0f', $n) : sprintf('%.1f', $n);
}
