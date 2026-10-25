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
medians across the alternating runs, not one run.

```sh
git worktree add --detach /tmp/jsv-old <commit>
export PERL5LIB=local/lib/perl5
for i in 1 2 3; do
    taskset -c 0 perl bench/run.pl --lib /tmp/jsv-old/lib > old-$i.txt
    taskset -c 0 perl bench/run.pl > new-$i.txt
done
git worktree remove /tmp/jsv-old
```

## Gates

From the design ("Performance"):

- Existing validators (Draft 4/6/7, `OAS30`) regress by no more than 10%
  against the Phase 0 baseline below.
- `OAS31` on the same document, translated to 3.1, is no slower than `OAS30`
  at the Phase 0 baseline, at both `flag` and `basic`, on passing and failing
  requests and responses.

## Baselines

Machine: 13th Gen Intel Core i7-1355U, Perl v5.38.2, pinned to CPU 0.
Medians of three alternating runs, 2026-10-25, ops/sec.

| workload | before Phase 0 (`9d2ab08`) | Phase 0 (`41bbf86`) | change |
| --- | ---: | ---: | ---: |
| draft7 invalid | 13676 | 12458 | -8.9% |
| draft7 valid | 15343 | 14072 | -8.3% |
| oas30 request invalid | 6183 | 5844 | -5.5% |
| oas30 request valid | 8024 | 7571 | -5.6% |
| oas30 response invalid | 235.9 | 226.3 | -4.1% |
| oas30 response valid | 236.4 | 225.0 | -4.8% |

The Phase 0 column is the baseline later phases compare against.
