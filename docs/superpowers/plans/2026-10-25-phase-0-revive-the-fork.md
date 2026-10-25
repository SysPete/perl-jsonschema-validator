# Phase 0: Revive the Fork - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the fork to a maintained baseline: Perl 5.20 floor, modern CI
running the current official test suite, every required Draft 4/6/7 test
passing, remote fetching off by default, and a recorded performance baseline.

**Architecture:** Small, targeted changes to the existing classes. Two new
helpers in `JSONSchema::Validator::Util` (`json_equal`, `resolve_uri`), one new
module (`JSONSchema::Validator::BundledSchemas`), two new constructor options
(`fetch_remote`, `documents`) threaded from `Draft4::create` into
`URIResolver`. A benchmark lives outside the distribution under `bench/`.

**Tech Stack:** Perl 5.20+, Test::More, Test::JSON::Schema::Acceptance 1.040,
Dist::Zilla (release only), GitHub Actions with shogo82148/actions-setup-perl.

**Spec:** `docs/superpowers/specs/2026-10-25-modern-drafts-and-oas31-design.md`
(Phase 0 under "Phases"; "Compatibility"; "Performance").

## Global Constraints

- Minimum Perl 5.20. Code style stays as the existing code: `use strict;
  use warnings;`, `my ($self, ...) = @_`, no signatures, no postfix
  dereferencing.
- Runtime dependencies: core Perl plus `URI` only. `Math::BigInt` /
  `Math::BigFloat` are recognised with `Scalar::Util::blessed` + `->isa`;
  never `require` them at load time.
- Draft 4/6/7 and `OAS30` keep their `Error` objects, fields, `to_string` /
  `TO_JSON` output and existing message wording. New messages may be added.
- Bug fixes may change results.
- Remote fetching off by default covers every fetch a document triggers. A
  caller's own `resource => 'http://...'` keeps working. A `scheme_handlers`
  entry for a scheme counts as opting in for that scheme.
- Public repository: no criticism of other projects, no names of downstream
  users, in code, POD, commit messages or docs.
- Tests run on the host Perl from the repository root:
  `prove -l t/<file>.t`. Developer-only modules install into `local/`
  (git-ignored): `cpm install -L local Test::JSON::Schema::Acceptance@1.040`,
  then `PERL5LIB=local/lib/perl5`.
- Assertions show real data (AGENTS.md "Tests"): every invalid case asserts
  the result **and** the error text, via `errors_text($errors)` from
  `t/lib/Helper.pm` (Task 3), never error counts or `->[0]` positions.
- `t/acceptance.t` skips silently without its module or without
  `ACCEPTANCE_TESTING=1`. A step that runs it has passed only if the output
  shows the draft4, draft6 and draft7 summary tables with their `TOTAL`
  lines and `prove` reports no `skipped`; a skipped run is a failed step.
- Commit messages: terse, imperative, ending with the
  `Co-Authored-By:` line the session supplies.

## Review Focus

1. A huge integer decoded as `Math::BigInt` (e.g. `2**70`) against
   `type: integer` and `maximum` - expected: integer, compared exactly (Task 3).
2. `multipleOf` where the quotient does not terminate (`1` against
   `multipleOf: 0.3333` with both as `Math::BigFloat`) - expected: invalid, no
   hang, no warning (Task 3).
3. A `documents` key with an empty fragment (`http://example.com/s.json#`) -
   expected: satisfies `$ref: "http://example.com/s.json"` and the reverse
   (Task 6).
4. A `scheme_handlers` entry for `https` while the `$ref` is `http` - expected:
   the `http` ref is still blocked (Task 6).
5. A URN-based schema with a relative path `$ref` (`"$ref": "other.json"`)
   - expected: validation result 0 with an error saying the reference cannot
   be resolved against a URN base, never a `Can't locate object method
   "authority"` death (Task 4).

---

### Task 1: Perl 5.20 floor, development setup and CI

**Files:**
- Modify: `dist.ini`
- Modify: `cpanfile`
- Modify: `.gitignore`
- Modify: `.github/workflows/tests.yml`
- Modify: `DEVELOPMENT.md`
- Modify: `Changes`

**Interfaces:**
- Produces: `local/` as the developer module directory; CI that sets
  `ACCEPTANCE_TESTING=1` and installs the optional modules.

- [ ] **Step 1: Raise the Perl floor**

`dist.ini` `[Prereqs]`: `perl = v5.20`. `cpanfile` (kept in step with what
`dzil build` writes): both `requires "perl" => "v5.16.0";` become
`"v5.20.0"`, and add under `on 'develop'`:
`requires "Test::JSON::Schema::Acceptance" => "1.040";`. Mirror that in
`dist.ini` as `[Prereqs / DevelopRequires]` with
`Test::JSON::Schema::Acceptance = 1.040`.

- [ ] **Step 2: Keep non-distribution directories out of the tarball**

`dist.ini` `[GatherDir]`: add `exclude_match = ^docs/`,
`exclude_match = ^bench/`, `exclude_match = ^local/`. `.gitignore`: add
`local/`.

- [ ] **Step 3: Rewrite the CI workflow**

`.github/workflows/tests.yml`:
- `actions/checkout@v4`, `shogo82148/actions-setup-perl@v1`.
- Matrix: Linux on `5.20, 5.22, 5.24, 5.26, 5.28, 5.30, 5.32, 5.34, 5.36,
  5.38, 5.40, 5.42, latest`; macOS and Windows on `5.20` and `latest`. If the
  action has no 5.20 for an OS, use its lowest version above 5.20 and say so
  in a comment beside that entry.
- Install: `cpanm -n Test::JSON::Schema::Acceptance@1.040 YAML::XS YAML::PP
  Cpanel::JSON::XS JSON::XS` then `cpanm -n --installdeps .`. The suite
  version is pinned; upgrading it is a deliberate commit of its own.
- Run: `prove -lr t` with `ACCEPTANCE_TESTING: 1` on every job.
- A separate job, `acceptance-latest`, on Linux with `latest` Perl, installs
  the newest Test::JSON::Schema::Acceptance and runs only
  `prove -l t/acceptance.t`, with `continue-on-error: true` so it reports new
  suite tests without blocking the build.

- [ ] **Step 4: Update `DEVELOPMENT.md` and `Changes`**

`DEVELOPMENT.md` "INSTALL DEPENDENCIES": replace the acceptance and
LWP::UserAgent lines with the `cpm install -L local ...` line and
`PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t`.
`Changes`: add at the top

```
0.012  Not Released
    - Minimum Perl version is now 5.20
```

- [ ] **Step 5: Verify**

Run: `prove -lr t`
Expected: `All tests successful.` (acceptance skipped without
`ACCEPTANCE_TESTING`).

- [ ] **Step 6: Commit**

```bash
git add dist.ini cpanfile .gitignore .github/workflows/tests.yml DEVELOPMENT.md Changes
git commit -m "Require Perl 5.20 and modernise CI"
```

---

### Task 2: Run the current official test suite

**Files:**
- Modify: `t/acceptance.t`

**Interfaces:**
- Produces: `t/acceptance.t` running Test::JSON::Schema::Acceptance 1.040
  without any `todo_tests`. It fails until Task 4 is done; that is expected on
  this branch, which merges as a whole.

- [ ] **Step 1: Point the harness at Test::JSON::Schema::Acceptance 1.040**

Construct with `specification => $specification, include_optional => 0`
(optional tests belong to a later phase). Remove the old `nvsize`
`multipleOf.json` todo, leaving no `todo_tests` at all. Before any test
output, set UTF-8 on the Test::Builder handles so test names with non-ASCII
characters do not warn:

```perl
binmode Test::More->builder->$_, ':encoding(UTF-8)'
    for qw(output failure_output todo_output);
```

- [ ] **Step 2: Run it and confirm the known failures**

Run: `PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t`
Expected: FAIL. The summary tables show 18 failures for draft4 and 28 each
for draft6 and draft7 (74 in all), in exactly these files, and the
`no warnings` test passes:

- draft4: `anyOf.json`, `enum.json`, `maximum.json`, `minimum.json`,
  `multipleOf.json`, `oneOf.json`, `ref.json`, `type.json`
- draft6 and draft7: those files plus `const.json`, `exclusiveMaximum.json`
  and `exclusiveMinimum.json`

Two causes: numbers arrive as `Math::BigFloat` (Task 3) and URN base URIs
(Task 4, the five `ref.json` groups whose names start with "simple URN base
URI" or "URN base URI", draft6 and draft7 only).

- [ ] **Step 3: Commit**

Put the per-draft failure counts from Step 2 in the commit body.

```bash
git add t/acceptance.t
git commit -m "Run Test::JSON::Schema::Acceptance 1.040"
```

---

### Task 3: Big numbers and JSON equality

Decoders with `allow_bignum` (the acceptance harness among them) hand the
validator `Math::BigFloat` / `Math::BigInt` objects. Today `is_ref` claims any
blessed value, so `detect_type` reports `_ref` and numeric keywords skip it.

**Files:**
- Modify: `lib/JSONSchema/Validator/Util.pm`
- Modify: `lib/JSONSchema/Validator/Constraints/Draft4.pm` (`enum`,
  `uniqueItems`, `multipleOf`)
- Modify: `lib/JSONSchema/Validator/Constraints/Draft6.pm` (`const`)
- Modify: `lib/JSONSchema/Validator.pm` (the `=head2 allow_bignum => 1` POD
  section)
- Test: `t/util_numbers.t` (new)
- Test: `t/validator_oas.t`
- Modify: `t/lib/Helper.pm` (add `errors_text`)

**Interfaces:**
- Produces in `JSONSchema::Validator::Util` (exportable):
  - `is_bignum($value) -> 0|1` - true for a blessed `Math::BigInt` or
    `Math::BigFloat`.
  - `json_equal($a, $b) -> 0|1` - JSON data model equality: numbers compare
    numerically whatever their Perl representation (`1 == 1.0`,
    `Math::BigFloat` included); booleans only equal booleans; strings by
    `eq`; arrays element-wise; objects by key set and values; `undef` only
    equals `undef`.
- Produces in `t/lib/Helper.pm` (exportable): `errors_text($errors) -> $string`
  - every line of `unwind_to_string_list` for each error, joined with
  newlines, so nested `context` messages are matched too (stringifying an
  `Error` shows only its top message).

- [ ] **Step 1: Write the failing unit tests** in `t/util_numbers.t`

```perl
use Math::BigInt; use Math::BigFloat; use JSON::PP;
use JSONSchema::Validator::Util qw(is_type detect_type json_equal);

my $f = Math::BigFloat->new('1.5');
my $i = Math::BigFloat->new('2.0');
my $big = Math::BigInt->new(2)->bpow(70);

is detect_type($f, 1), 'number', 'BigFloat 1.5 is a number';
is detect_type($i, 1), 'integer', 'BigFloat 2.0 is an integer';
is detect_type($big, 1), 'integer', 'BigInt 2**70 is an integer';
ok !is_type($f, 'integer', 1), 'BigFloat 1.5 is not an integer';

ok json_equal(0, Math::BigFloat->new('0.0')), '0 equals 0.0';
ok json_equal([1], [Math::BigFloat->new('1.0')]), '[1] equals [1.0]';
ok !json_equal(0, JSON::PP::false), '0 is not false';
ok !json_equal([1], [JSON::PP::true]), '[1] is not [true]';
ok json_equal({a => [1, {b => 'x'}]}, {a => [1.0, {b => 'x'}]}), 'nested';
ok !json_equal({a => 1}, {a => 1, b => 2}), 'different keys';
ok !json_equal(undef, ''), 'null is not empty string';
```

Plus the Review Focus cases, through a Draft 7 validator:

```perl
my $v = JSONSchema::Validator->new(specification => 'Draft7',
    schema => { type => 'integer', maximum => Math::BigInt->new(2)->bpow(70) });
is( ($v->validate_schema($big))[0], 1, '2**70 <= 2**70' );
my ($r, $e) = $v->validate_schema($big + 1);
is $r, 0, '2**70+1 > 2**70';
like errors_text($e), qr/is greater than/, 'maximum says why';

$v = JSONSchema::Validator->new(specification => 'Draft7',
    schema => { multipleOf => Math::BigFloat->new('0.3333') });
($r, $e) = $v->validate_schema(Math::BigFloat->new('1'));
is $r, 0, '1 is not a multiple of 0.3333';
like errors_text($e), qr/is not multiple of/;
```

And the official suite's "float division = inf" case, which an inexact
`multipleOf` gets wrong:

```perl
$v = JSONSchema::Validator->new(specification => 'Draft7',
    schema => { type => 'integer', multipleOf => Math::BigFloat->new('0.123456789') });
($r, $e) = $v->validate_schema(Math::BigFloat->new('1e308'));
is $r, 0, '1e308 is not a multiple of 0.123456789';
like errors_text($e), qr/is not multiple of/;
```

End the file with `ok detect_warnings() == 0, 'no warnings';` (using
`t/lib/Helper.pm` as the other tests do).

In `t/validator_oas.t`, pin today's non-strict `OAS30` comparisons, which this
task must not change: a query parameter `"1"` against
`{type: integer, enum: [1, 2]}` is valid, and `"1"` against
`{type: boolean, enum: [true]}` is valid (both through `validate_request`).
These pass before the change too; they guard Step 3.

- [ ] **Step 2: Run both**

Run: `prove -l t/util_numbers.t` and
`PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t`
Expected: both FAIL (detect_type returns `_ref`; acceptance still shows the 74 failures from Task 2).

- [ ] **Step 3: Implement**

In `Util.pm`: `is_ref` returns 0 for `is_bignum` values; `is_number` returns
1 for them; `is_integer` returns 1 for `Math::BigInt` and for a
`Math::BigFloat` whose `is_int` is true; add `is_bignum` and `json_equal`.
`enum`, `const` and `uniqueItems` use `json_equal` only when the constraint is
strict (`$self->strict`, true for Draft 4/6/7); the non-strict path, which
`OAS30` uses, keeps today's code unchanged. `multipleOf`: when either operand
is a bignum, upgrade both to `Math::BigFloat` and test the exact remainder,
`$x->copy->bmod($m)->is_zero` - never `bdiv`, which rounds to 40 digits and
makes `1e308 / 0.123456789` look whole; otherwise keep today's floating-point
code. `Validator.pm` POD: replace the `allow_bignum => 1` section's "not
supported" text with: `Math::BigInt` and `Math::BigFloat` values are validated
as numbers, with exact comparisons and `multipleOf`.

- [ ] **Step 4: Verify**

Run: `prove -lr t` and
`PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t`
Expected: `t/util_numbers.t` and the rest of `t/` PASS. `t/acceptance.t` still FAILS, but only in `ref.json` for draft6 and draft7, and only in the five URN groups named in Task 2 (2 per draft are deaths, the rest wrong results); draft4 has no failures.

- [ ] **Step 5: Refactor**

With the tests green, tidy what this task wrote: the type checks in `is_number`/`is_integer`/`is_ref` share one bignum test (`is_bignum`), not three copies; `json_equal` is the only deep comparison - remove any serialise-and-compare left in the strict path. Re-run the Step 4
commands; they must still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/JSONSchema/Validator/Util.pm lib/JSONSchema/Validator/Constraints/Draft4.pm \
        lib/JSONSchema/Validator/Constraints/Draft6.pm lib/JSONSchema/Validator.pm \
        t/util_numbers.t t/validator_oas.t t/lib/Helper.pm Changes
git commit -m "Accept Math::BigInt and Math::BigFloat numbers"
```

(`Changes`: "- Numbers decoded as Math::BigInt / Math::BigFloat are validated
as numbers; enum, const and uniqueItems compare numbers numerically".)

---

### Task 4: URN base URIs

`URI->abs` on a base without an authority (`urn:uuid:...`) dies with `Can't
locate object method "authority" via package "URI::urn"`.

**Files:**
- Modify: `lib/JSONSchema/Validator/Util.pm`
- Modify every `->abs(` call site: `Constraints/Draft4.pm:670`,
  `Constraints/OAS30.pm:153`, `Draft4.pm:118`, `JSONPointer.pm:83`, `:91`,
  `:108`, `:116`, `URIResolver.pm:171`
- Test: `t/util_resolve_uri.t` (new)

**Interfaces:**
- Produces in `JSONSchema::Validator::Util` (exportable):
  `resolve_uri($ref, $base) -> URI`. `$ref` and `$base` are strings or `URI`
  objects; `$base` may be empty/undef (then `$ref` is returned as a `URI`).
  Hierarchical base: same as `URI->new($ref)->abs($base)`. Non-hierarchical
  base (no `authority` method, e.g. `urn:`): an absolute `$ref` is returned
  as is; a fragment-only `$ref` returns the base with that fragment; anything
  else croaks `cannot resolve relative reference "$ref" against
  non-hierarchical base "$base"`.

- [ ] **Step 1: Write the failing unit tests** in `t/util_resolve_uri.t`

```perl
is resolve_uri('#/a', 'urn:uuid:deadbeef-1234-ffff-ffff-4321feebdaed')->as_string,
   'urn:uuid:deadbeef-1234-ffff-ffff-4321feebdaed#/a';
is resolve_uri('urn:example:x', 'urn:example:y')->as_string, 'urn:example:x';
is resolve_uri('b.json#/c', 'http://h/a/s.json')->as_string, 'http://h/a/b.json#/c';
is resolve_uri('b.json', undef)->as_string, 'b.json';
like exception { resolve_uri('other.json', 'urn:example:root') },
     qr/cannot resolve relative reference "other.json"/;
```

(`exception` = `eval { ...; 1 } ? undef : $@`, written inline.)

Review Focus case, end to end:

```perl
my $v = JSONSchema::Validator->new(specification => 'Draft7',
    schema => { '$id' => 'urn:example:root', '$ref' => 'other.json' });
my ($r, $e) = $v->validate_schema('x');
is $r, 0, 'relative path ref against URN base fails';
unlike errors_text($e), qr/authority/, 'no URI::urn death';
like errors_text($e), qr/cannot resolve relative reference/, 'says why';
```

- [ ] **Step 2: Run both**

Run: `prove -l t/util_resolve_uri.t` and
`PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t`
Expected: FAIL (`resolve_uri` undefined; the URN groups still fail).

- [ ] **Step 3: Implement `resolve_uri` and use it at every call site listed**

- [ ] **Step 4: Verify**

Run: `prove -lr t` and
`PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t`
Expected: PASS, acceptance summary `fail` column 0 for draft4, draft6 and
draft7.

- [ ] **Step 5: Refactor**

With the tests green, tidy what this task wrote: no `->abs(` remains outside `resolve_uri` (`git grep -n -- '->abs(' lib` shows only Util.pm); the eight call sites read the same way. Re-run the Step 4
commands; they must still pass.

- [ ] **Step 6: Commit**

```bash
git add lib t/util_resolve_uri.t Changes
git commit -m "Resolve references against URN base URIs"
```

---

### Task 5: Bundled schemas resolve by canonical `$id`

**Files:**
- Create: `lib/JSONSchema/Validator/BundledSchemas.pm`
- Modify: `lib/JSONSchema/Validator/URIResolver.pm` (`cache_resolve`)
- Test: `t/bundled_schemas.t` (new)

**Interfaces:**
- Produces: `JSONSchema::Validator::BundledSchemas::bundled_schema($uri) ->
  $schema | undef` (exportable). Matches the four bundled schemas by their
  `$id`/`id` with and without a trailing empty fragment:
  `http://json-schema.org/draft-04/schema`,
  `http://json-schema.org/draft-06/schema`,
  `http://json-schema.org/draft-07/schema`,
  `https://spec.openapis.org/oas/3.0/schema/2019-04-02`. Each file is read
  from `lib/JSONSchema/Validator/schemas/` once per process and cached.
  Later phases add their meta-schemas to the same table.
- `URIResolver::cache_resolve` consults `bundled_schema` after its own cache
  and before `scheme_handlers` or any loading.

- [ ] **Step 1: Write the failing test** in `t/bundled_schemas.t`

```perl
my $fail = sub { die "network used for $_[0]\n" };
for my $id ('http://json-schema.org/draft-07/schema#',
            'http://json-schema.org/draft-07/schema') {
    my $v = JSONSchema::Validator->new(specification => 'Draft7',
        schema => { '$ref' => $id },
        scheme_handlers => { http => $fail, https => $fail });
    is( ($v->validate_schema({ type => 'string' }))[0], 1, "$id: valid schema" );
    my ($r, $e) = $v->validate_schema({ type => 12 });
    is $r, 0, "$id: invalid schema";
    like errors_text($e), qr{instance is not of enums \[instance path: /type\]},
        "$id: says why";
}
ok bundled_schema('https://spec.openapis.org/oas/3.0/schema/2019-04-02'), 'oas30';
ok !defined bundled_schema('http://example.com/nope'), 'unknown id';
```

plus the same `type => 12` check for draft-04 and draft-06 ids.

- [ ] **Step 2: Run it**

Run: `prove -l t/bundled_schemas.t`
Expected: FAIL - the "valid schema" cases return 0, their errors containing
`network used for http://json-schema.org/draft-07/schema`.

- [ ] **Step 3: Implement `BundledSchemas.pm` and the `cache_resolve` lookup**

- [ ] **Step 4: Verify**

Run: `prove -lr t` and
`PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t`
Expected: PASS, with the three summary tables showing `fail` 0 (see Global
Constraints: a skipped acceptance run is a failed step).

- [ ] **Step 5: Refactor**

With the tests green, tidy what this task wrote: `JSONSchema::Validator::read_specification` and `BundledSchemas` locate and load the schema files through one routine, not two. Re-run the Step 4
commands; they must still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/JSONSchema/Validator/BundledSchemas.pm lib/JSONSchema/Validator/URIResolver.pm \
        t/bundled_schemas.t Changes
git commit -m "Serve bundled meta-schemas by canonical id"
```

---

### Task 6: Remote fetching off by default, `documents` preload

**Files:**
- Modify: `lib/JSONSchema/Validator/Draft4.pm` (`create`, POD)
- Modify: `lib/JSONSchema/Validator/URIResolver.pm` (`new`, `cache_resolve`)
- Modify: `lib/JSONSchema/Validator.pm` (POD for `new`)
- Modify: `Changes`
- Test: `t/remote_fetching.t` (new)
- Create: `t/data/remote_fetching/integer.json` (`{"type": "integer"}`)

**Interfaces:**
- Consumes: `bundled_schema` (Task 5), already wired into `cache_resolve`.
- Produces: constructor options accepted by every validator class and by
  `JSONSchema::Validator->new` (which passes them through):
  - `fetch_remote => 0|1`, default 0. Allows `http`/`https` loads triggered
    by the document.
  - `documents => { $uri => $schema, ... }` (not `resources`: `resource` is
    already the root-schema argument of `new`). Seeds the resolver cache; keys
    are normalised so `X` and `X#` are the same entry; `$id`s inside each
    resource are indexed as for the root (`cache_id`).
- `cache_resolve` order: own cache (including `documents`) -> bundled ->
  caller's `scheme_handlers` for the scheme -> if scheme is `http`/`https`
  and `fetch_remote` is false, croak
  `Remote fetching is disabled: cannot load $uri. Preload it with "documents" or pass fetch_remote => 1` -> `load_schema`.

- [ ] **Step 1: Write the failing tests** in `t/remote_fetching.t`

```perl
my $schema = { '$ref' => 'http://example.invalid/s.json' };

# off by default
my ($r, $e) = JSONSchema::Validator::Draft7->new(schema => $schema)->validate_schema(1);
is $r, 0, 'blocked by default';
like errors_text($e), qr/Remote fetching is disabled: cannot load http:\/\/example\.invalid\/s\.json/;

# documents, with and without an empty fragment on either side
for my $pair (['http://example.invalid/s.json', $schema],
              ['http://example.invalid/s.json#', $schema],
              ['http://example.invalid/s.json', { '$ref' => 'http://example.invalid/s.json#' }]) {
    my ($key, $s) = @$pair;
    my $v = JSONSchema::Validator::Draft7->new(schema => $s,
        documents => { $key => { type => 'integer' } });
    is( ($v->validate_schema(1))[0], 1, "documents $key" );
    my ($r, $e) = $v->validate_schema('x');
    is $r, 0, "documents $key rejects";
    like errors_text($e), qr/type mismatch/, "documents $key says why";
}

# a scheme handler opts in for its scheme only
my @called;
my $handler = sub { push @called, "$_[0]"; return (\'{"type":"integer"}', 'JSON') };
($r) = JSONSchema::Validator::Draft7->new(schema => $schema,
    scheme_handlers => { http => $handler })->validate_schema(1);
is $r, 1; is_deeply \@called, ['http://example.invalid/s.json'];
($r, $e) = JSONSchema::Validator::Draft7->new(schema => $schema,
    scheme_handlers => { https => $handler })->validate_schema(1);
is $r, 0, 'https handler does not open http';
like errors_text($e), qr/Remote fetching is disabled/;

# fetch_remote => 1 reaches the fetcher
{
    no warnings 'redefine';
    local *JSONSchema::Validator::Util::fetch_file = sub { (\'{"type":"integer"}', 'JSON') };
    ($r) = JSONSchema::Validator::Draft7->new(schema => $schema, fetch_remote => 1)
        ->validate_schema(1);
    is $r, 1, 'fetch_remote opts in';
}

# what stays allowed without fetch_remote
{
    no warnings 'redefine';
    local *JSONSchema::Validator::Util::fetch_file = sub { (\'{"type":"integer"}', 'JSON') };
    my $v = JSONSchema::Validator->new(resource => 'http://example.invalid/root.json',
        specification => 'Draft7');
    is( ($v->validate_schema(1))[0], 1, "caller's own http resource still loads" );
}
my $file_ref = { '$ref' => 'file://' . test_dir('data/remote_fetching/integer.json') };
($r, $e) = JSONSchema::Validator::Draft7->new(schema => $file_ref)->validate_schema('x');
is $r, 0, 'file: ref resolves without fetch_remote';
like errors_text($e), qr/type mismatch/, 'and is applied';
is( (JSONSchema::Validator::Draft7->new(schema => $file_ref)->validate_schema(1))[0], 1,
    'file: ref accepts a valid instance' );
```

Check `get_content` calls `fetch_file` by package name so the `local`
override takes effect; if it does not, add the smallest seam that makes it
replaceable and say so in the commit message.

- [ ] **Step 2: Run it**

Run: `prove -l t/remote_fetching.t`
Expected: FAIL (first test: result 1 or a network error, not the new message).

- [ ] **Step 3: Implement** - the check belongs in `URIResolver::cache_resolve`, which
  only document-triggered loads reach; not in `Util::get_content`, which the
  caller's own `resource` and `validate_resource`/`validate_paths` also use.
  Add the options in `Draft4::create` (stored on the validator and passed to `URIResolver->new`) and the `cache_resolve` order
  above. POD: document both options in `Draft4.pm` and `Validator.pm`, and
  correct the `=item resources` typo in `Validator.pm` to `resource`.

- [ ] **Step 4: Verify**

Run: `prove -lr t` and
`PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t`
Expected: PASS, with the three acceptance summary tables showing `fail` 0
(the harness opts in through its `http` scheme handler; a skipped run is a
failed step).

- [ ] **Step 5: Refactor**

With the tests green, tidy what this task wrote: the `http`/`https` scheme test is written once; `documents` keys and resolver cache keys go through the same normalisation. Re-run the Step 4
commands; they must still pass.

- [ ] **Step 6: Commit**

`Changes`: "- INCOMPATIBLE: http/https references are no longer fetched
unless fetch_remote => 1 is passed or a scheme handler is given; documents can
be preloaded with the new documents option".

```bash
git add lib t/remote_fetching.t t/data/remote_fetching Changes
git commit -m "Turn remote fetching off by default, add documents option"
```

---

### Task 7: Regression test for upstream issue #37

The report (an empty path parameter passing `minLength: 1`) does not
reproduce: `validate_request` rejects it. Pin that.

**Files:**
- Test: `t/validator_oas.t`

- [ ] **Step 1: Add the test**

```perl
my $v = JSONSchema::Validator->new(schema => {
    openapi => '3.0.2', info => { title => 't', version => '1' },
    paths => { '/invoices/{id}' => {
        parameters => [ { name => 'id', in => 'path', required => JSON::PP::true(),
                          schema => { type => 'string', minLength => 1 } } ],
        get => { responses => { 200 => { description => 'ok' } } } } } });
my ($r, $e) = $v->validate_request(method => 'get', openapi_path => '/invoices/{id}',
    parameters => { path => { id => '' } });
is $r, 0, 'empty path parameter fails minLength 1';
like errors_text($e), qr/path param "id" has error: minLength \(>= 1\) constraint violated/;
```

- [ ] **Step 2: Run it**

Run: `prove -l t/validator_oas.t`
Expected: PASS (behaviour already correct; this is a pin).

- [ ] **Step 3: Commit**

```bash
git add t/validator_oas.t
git commit -m "Pin empty path parameter rejected by minLength"
```

---

### Task 8: Synthetic benchmark and baseline

**Files:**
- Create: `bench/lib/Bench/OpenAPIDocument.pm`
- Create: `bench/run.pl`
- Create: `bench/README.md`

**Interfaces:**
- Produces:
  - `Bench::OpenAPIDocument::build(entities => $n) -> $hashref` - a
    deterministic OpenAPI 3.0.3 document. Per resource `R` (named `r001`...):
    `components/schemas/R` (12 properties: string, integer, number, boolean,
    `nullable: true` string and integer, enum string, date-time string, nested
    object with 3 properties, array of `$ref` to the next resource's
    `RSummary`, `$ref` to the previous resource's `RSummary`, array of
    strings with `maxItems`), `RSummary`, `RCreate` (`required` list);
    paths `/R` (get with `$ref` query params `Limit`, `Offset`, `Sort`; post
    with `RCreate` body) and `/R/{id}` (path param `$ref` `Id`; get, put,
    delete); every response `$ref`s `components/responses/Error` for 400 and
    404. Shared `components/parameters` and `components/responses`.
  - `Bench::OpenAPIDocument::count_refs($doc) -> $n`.
  - `bench/run.pl [--lib DIR] [--time SECONDS]`: loads the validator from
    `DIR` (default `lib`), prints Perl version, validator version, `$ref`
    count, and an ops/sec table via core `Benchmark::timethese` for:
    `oas30 request valid`, `oas30 request invalid`, `oas30 response valid`
    (a list of 20 items), `oas30 response invalid`, `draft7 valid`,
    `draft7 invalid` (the Draft 7 cases use
    `t/data/validator_json_schema/draft7-1-*.json` and `draft7-2-*.json`).

- [ ] **Step 1: Write the generator and check its shape**

Choose the default `entities` so that `count_refs` is between 1900 and
2300.

Run: `perl -Ibench/lib -MBench::OpenAPIDocument -e 'my $d = Bench::OpenAPIDocument::build(); print Bench::OpenAPIDocument::count_refs($d), "\n"'`
Expected: a number between 1900 and 2300.

- [ ] **Step 2: Write `bench/run.pl` and confirm every workload gives the
  expected result once before timing**

`run.pl` validates each workload once and dies unless the valid cases return
1 and the invalid cases return 0, so a broken workload can't produce a
flattering number.

Run: `perl bench/run.pl --time 1`
Expected: the header lines and six rows, no die.

- [ ] **Step 3: Record the baseline**

Measure both the code before Phase 0 and the code after it, back to back on
the maintainer's machine:

Run: `git worktree add /tmp/jsv-pre-phase0 9d2ab08`, then
`perl bench/run.pl --time 10 --lib /tmp/jsv-pre-phase0/lib` and
`perl bench/run.pl --time 10`.
Expected: both complete; every Phase 0 row is within 10% of the pre-Phase 0
row (the spec's gate for existing validators, applied to Phase 0 itself). A
row outside it is a finding to fix in the task that caused it, not to record.

`bench/README.md`: how to run it; how to compare two revisions (a
`git worktree` of the older commit and `--lib`, back to back on one machine);
the gates from the spec ("Performance"); and both baseline tables with
commit, date, Perl version and CPU model. The Phase 0 table is the baseline
later phases compare against.

- [ ] **Step 4: Commit**

```bash
git add bench
git commit -m "Add synthetic OpenAPI benchmark and phase 0 baseline"
```

---

## After the tasks

- Upstream #20 (install failing on `Test::CPAN::Changes`): already resolved
  in 0.011, whose `t/release-cpan-changes.t` skips without `RELEASE_TESTING`
  and whose metadata lists the module as a develop requirement only. Record
  that on the tracking issue; no code change.
- Push the branch and confirm CI is green on every matrix entry.
