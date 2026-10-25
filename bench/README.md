# Benchmarks

Not part of the CPAN distribution (`dist.ini` excludes `bench/`).

`run.pl` builds a synthetic OpenAPI 3.0.3 document
(`lib/Bench/OpenAPIDocument.pm`: 95 resources, 2091 `$ref`s into shared
components, `nullable` fields, path, query and body parameters, nested
objects and arrays) and times six workloads against it and two Draft 7
schemas from `t/data/validator_json_schema/`:

| workload | what it does |
| --- | --- |
| oas30 request valid / invalid | `PUT /r050/{id}`: path parameter and JSON body |
| oas30 response valid / invalid | `GET /r050` 200: a list of 20 items, the last one bad in the invalid case |
| draft7 valid / invalid | `draft7-1` and `draft7-2` schemas, ok and wrong instances |

Each workload is run once before timing, and `run.pl` dies unless the valid
cases return 1 and the invalid cases 0, so a broken workload can't produce a
flattering number.

## Running it

Timing uses [Dumbbench](https://metacpan.org/pod/Dumbbench), installed into
the git-ignored `local/`:

```sh
cpm install -L local Dumbbench
PERL5LIB=local/lib/perl5 perl bench/run.pl [--lib DIR] [--precision 0.005]
```

`--lib` picks which validator is loaded (default: this checkout's `lib`).
`--precision` is Dumbbench's target relative precision. The `+/-` column is
the uncertainty within that run.

## Comparing two revisions

Run both on one machine, back to back, pinned to one core, and alternate
them several times. Within a run the uncertainty is about 0.1-0.2%; between
runs on a laptop CPU the same code moves by 2-3% (clock speed, temperature),
and a single unpinned pair of runs once disagreed by over 10%. Compare
medians across the alternating runs, not one run. On a CPU with
performance and efficiency cores, pin to a performance core, and use the
same Perl version as the baseline you compare against.

```sh
git worktree add --detach /tmp/jsv-old <commit>
export PERL5LIB=local/lib/perl5
for i in 1 2 3; do
    taskset -c 0 perl bench/run.pl --lib /tmp/jsv-old/lib > old-$i.txt
    taskset -c 0 perl bench/run.pl > new-$i.txt
done
git worktree remove /tmp/jsv-old
perl bench/compare.pl --old old-*.txt --new new-*.txt
```

`compare.pl` prints the medians and the change as a Markdown table in the
format of the baselines below.

## Gates

From the design ("Performance"):

- Existing validators (Draft 4/6/7, `OAS30`) regress by no more than 10%
  against the Phase 0 baseline below.
- `OAS31` on the same document, translated to 3.1, is no slower than `OAS30`
  at the Phase 0 baseline, at both `flag` and `basic`, on passing and failing
  requests and responses.

## Baselines

Two machines, so a later phase can still be compared if one is gone.
Compare a later run only with the table from the same machine: the
absolute numbers differ between them. Both use Perl v5.38.2 and report
medians of three alternating runs, 2026-10-25, in ops/sec.

### tp: laptop, 13th Gen Intel Core i7-1355U, pinned to CPU 0

| workload | before Phase 0 (`9d2ab08`) | Phase 0 (`2d878c9`) | change |
| --- | ---: | ---: | ---: |
| draft7 invalid | 13369 | 13944 | +4.3% |
| draft7 valid | 14936 | 15296 | +2.4% |
| oas30 request invalid | 5988 | 5864 | -2.1% |
| oas30 request valid | 7786 | 7575 | -2.7% |
| oas30 response invalid | 229.3 | 222.9 | -2.8% |
| oas30 response valid | 229.9 | 223.8 | -2.7% |

### ducati: desktop, 13th Gen Intel Core i7-13700K, pinned to CPU 4

CPUs 0-15 are its performance cores. Runs here vary by 1-2%, less than on
the laptop.

| workload | before Phase 0 (`9d2ab08`) | Phase 0 (`2d878c9`) | change |
| --- | ---: | ---: | ---: |
| draft7 invalid | 14702 | 15017 | +2.1% |
| draft7 valid | 16316 | 16656 | +2.1% |
| oas30 request invalid | 6516 | 6387 | -2.0% |
| oas30 request valid | 8473 | 8249 | -2.6% |
| oas30 response invalid | 254.5 | 247.2 | -2.9% |
| oas30 response valid | 252.8 | 247.0 | -2.3% |

The Phase 0 columns are the baselines later phases compare against.

## Recording a baseline on a new machine

The baseline numbers only mean something on the machine that produced
them, so a new or replacement machine needs its own table. Measure the
same two commits as the existing tables (`9d2ab08` and `2d878c9`): the
"change" column then shows whether the new machine agrees with the others,
and the Phase 0 column becomes its baseline.

1. Use Perl v5.38.2, as the existing tables do. The system Perl is
   probably a different version, so install one alongside it, for example
   `perlbrew install perl-5.38.2`, and put its `bin` first in `PATH` for
   every command below. `perl -v` should report v5.38.2.

2. Install the dependencies into `local/`. URI is the validator's runtime
   dependency, needed by both commits:

   ```sh
   cpm install -L local Dumbbench URI
   ```

3. Pick a core. On an Intel CPU with performance and efficiency cores,
   `cat /sys/devices/cpu_core/cpus` lists the performance cores (tp: 0-3,
   ducati: 0-15); pick one of those. Elsewhere any core will do. Close
   other busy programs and keep a laptop on mains power.

4. Run the two commits alternately, three times each, with the core from
   step 3 in place of `N`:

   ```sh
   git worktree add --detach /tmp/jsv-pre-phase0 9d2ab08
   git worktree add --detach /tmp/jsv-phase0 2d878c9
   export PERL5LIB=local/lib/perl5
   for i in 1 2 3; do
       taskset -c N perl bench/run.pl --lib /tmp/jsv-pre-phase0/lib > old-$i.txt
       taskset -c N perl bench/run.pl --lib /tmp/jsv-phase0/lib > new-$i.txt
   done
   git worktree remove /tmp/jsv-pre-phase0
   git worktree remove /tmp/jsv-phase0
   perl bench/compare.pl --old old-*.txt --new new-*.txt
   ```

   Each run takes a few seconds. Use the current `bench/` for both
   commits, via `--lib`: the workloads must be the same for both.

5. Check the result. Every "change" should be within about 3 points of
   the other machines' tables. If it isn't, or one workload's three runs
   are far apart, look for a busy machine or a throttling CPU and run it
   again.

6. Add a section under "Baselines" headed with the hostname, CPU model
   (`lscpu | grep 'Model name'`) and the core you pinned to, then paste
   the table, renaming its columns to match the other tables. Note
   anything unusual, such as how much the runs varied.
