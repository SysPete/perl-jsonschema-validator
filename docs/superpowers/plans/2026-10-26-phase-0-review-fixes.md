# Phase 0 Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every finding of the `review-phase-0-fixes` code review pass its test, on the unreleased 0.012, before the branch is merged.

**Architecture:** Each task ports one group of failing subtests into the matching `t/` file, then changes the module that owns the behaviour. Tasks are grouped by the code they touch: OAS30 request/response handling, document loading, the discriminator, JSON Pointer resolution, the `new()` reference scan, the resolver cache, `get_content`, `exception_message`, and number handling. Each task's Step 2 says which assertions fail at HEAD `f392e19` and which already pass; those that pass guard behaviour the change must keep, and must not be changed to make them fail.

**Tech Stack:** Perl 5.20+, Test::More, URI, Math::BigInt / Math::BigFloat (core).

**Spec:** `docs/paad/code-reviews/review-phase-0-fixes-2026-10-26-10-02-25-f392e19.md` (committed). The security-related requirements are stated in the tasks themselves. Their findings are in the local, git-ignored `docs/paad/security/code-review-review-phase-0-fixes-2026-10-26-10-02-25-f392e19.md`.

## Global Constraints

- Follow `AGENTS.md`: `use strict; use warnings;`, `my ($self, ...) = @_`, no signatures, no postfix deref, no reformatting of code you only pass through.
- Minimum Perl 5.20 (`dist.ini` `[Prereqs] perl = v5.20`); runtime dependencies stay core plus `URI`.
- Do not change the wording of existing Draft 4/6/7 or OAS30 error messages unless the task says so. New messages are allowed.
- `validate_request` / `validate_response` keep returning `($result, $errors, $warnings)`.
- Comments: one sentence naming the constraint the code cannot state, ASCII only; POD states the contract.
- Each new scenario is a named `subtest`. Assertions compare messages and results, never error counts.
- Every result change goes in `Changes` under `0.012  Not Released`, in the existing format.
- Every perl run on this machine is memory-capped: `bash -c 'ulimit -v 2000000; timeout 300 prove -l t/<file>.t'`. A bignum regression can exhaust host memory.
- Run the whole suite (`prove -l t`) before each commit. Every subtest that passed at the start of the task must still pass.
- Refactor before committing: once Step 4 passes, review the task's diff for logic that duplicates an existing helper (`json_equal`, `comparable_numbers`, `canonical_json_key`, `xget`, `_check_remote_ref`, ...) or another part of the same diff. Consolidate it, then rerun Step 4.
- Commit messages: terse, imperative, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Public repository: no criticism of other projects, and no description of weaknesses in commits, POD or Changes. State the behaviour, e.g. "discriminator values are matched as schema names".

## Review Focus

- Draft 4 `id`s ending in `#` (the usual Draft 4 style) must resolve with or without the `#` once Task 6 changes how `$id`s are keyed. At HEAD a `$ref` without the `#` already fails at `new`. Test added in Task 6.
- A caller's own Windows path (`C:/...`) given as `resource` must still load after Task 7. Test added in Task 7.
- Non-strict `uniqueItems` must still treat `"1"` and `1` as duplicates after Task 9 changes its keys. Test added in Task 9.
- After Task 1, a parameter getter that dies with a string must die out of `validate_request`, as on 0.011. Only a reference that fails to load becomes an `exception:` error. Test added in Task 1.
- Discriminator `mapping` values written as `#/components/schemas/X` must still select X after Task 3. Test added in Task 3.

---

### Task 1: OAS30 exceptions keep argument errors, collected results and the scope stack

**Files:**
- Modify: `lib/JSONSchema/Validator/OAS30.pm` (`validate_schema`, `validate_request`, `_validate_request`, `validate_response`, `_validate_response`, `_catch_exception`), `lib/JSONSchema/Validator/Draft4.pm` (`validate_schema`, which Draft6 and Draft7 inherit), `lib/JSONSchema/Validator/URIResolver.pm` (`cache_resolve`)
- Test: `t/validator_oas.t`, `t/validator_json_schema.t`

**Interfaces:**
- Produces: `_catch_exception($self, $context, $code)`. `$context` is the `{errors => [], warnings => [], direction => ...}` hash, now created in the public method and passed to `_validate_request($method, $openapi_path, $get_user_param, $context, %params)` / `_validate_response($method, $openapi_path, $http_status, $get_user_param, $context, %params)`.
- Produces: a reference that fails to load always dies with one of two message forms, and nothing else does:
  - `Failed to load resource <name>...`, from `load_schema` or from `cache_resolve`.
  - `Remote fetching is disabled: ...`, from `_croak_remote_disabled`.

  `cache_resolve` wraps the indexing of a loaded document (`cache_id`) so that any failure there, such as a relative `$id` under a URN or Task 6's `$id` conflict, croaks `Failed to load resource <uri>: <reason>`. `_catch_exception` turns only these two forms into `exception:` errors. Every other die, string or object, is rethrown unchanged, as on 0.011.
- Produces: `validate_schema` in Draft4 and OAS30 leaves `@{$self->scopes}` as long as it found it, whether it returns or dies. On a die it truncates the stack and rethrows `$@` unchanged.

- [x] **Step 1: Add the failing subtests** to `t/validator_oas.t`, before `ok detect_warnings() == 0`. The file-level `$info`, `$responses` and `$missing` are shared with Task 2.

```perl
my $info = { title => 't', version => '1' };
my $responses = { 200 => { description => 'ok' } };
my $missing = 'file://' . test_dir('data/remote_fetching/no_such.json');

subtest 'OAS30 argument errors still croak' => sub {
    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/a' => { get => {
            parameters => [{ name => 'q', in => 'query', schema => { type => 'string' } }],
            responses => $responses } } } });

    eval { $validator->validate_request(method => 'get', openapi_path => '/a', parameters => { query => [1] }) };
    like $@, qr/^param "query" must be hashref or coderef/, 'a parameters value of the wrong type';

    my $error = { code => 500 };
    eval { $validator->validate_request(method => 'get', openapi_path => '/a',
        parameters => { query => sub { die $error } }) };
    is $@, $error, 'an exception object from a getter is rethrown';

    eval { $validator->validate_request(method => 'get', openapi_path => '/a',
        parameters => { query => sub { die "backend down\n" } }) };
    is $@, "backend down\n", 'a string exception from a getter is rethrown';
};

subtest 'OAS30 keeps what it found before a reference fails to load' => sub {
    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/b' => { post => {
            deprecated => JSON::PP::true(),
            parameters => [{ name => 'q', in => 'query', schema => { type => 'integer' } }],
            requestBody => { '$ref' => $missing },
            responses => $responses } } } });

    my ($result, $errors, $warnings) = $validator->validate_request(method => 'post', openapi_path => '/b',
        parameters => { query => { q => 'x' }, body => [1, 'application/json', {}] });
    is $result, 0, 'fails';
    like errors_text($errors), qr/query param "q" has error/, 'the parameter error is kept';
    like errors_text($errors), qr/exception: Failed to load resource/, 'the load failure is reported';
    like errors_text($warnings), qr/^method post of \/b is deprecated/, 'the deprecation warning is kept';
};

subtest 'OAS30 restores the scope after an exception' => sub {
    my $validator = JSONSchema::Validator::OAS30->new(base_uri => 'http://e.invalid/api.json', schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/a' => { post => {
            requestBody => { content => { 'application/json' => { schema => 'not a schema' } } },
            responses => $responses } } } });

    my $depth = @{$validator->scopes};
    for my $call (1 .. 3) {
        eval { $validator->validate_request(method => 'post', openapi_path => '/a',
            parameters => { body => [1, 'application/json', {}] }) };
        isnt $@, '', "call $call dies";
        is scalar @{$validator->scopes}, $depth, "scope stack depth after call $call";
    }
};

subtest 'OAS30 validate_schema restores the scope after an exception' => sub {
    my $validator = JSONSchema::Validator::OAS30->new(base_uri => 'http://e.invalid/api.json', schema => {
        openapi => '3.0.3', info => $info, paths => {} });

    my $depth = @{$validator->scopes};
    for my $call (1 .. 3) {
        eval { $validator->validate_schema(1, schema => 'not a schema', direction => 'request',
            scope => 'http://e.invalid/x.json') };
        isnt $@, '', "call $call dies";
        is scalar @{$validator->scopes}, $depth, "scope stack depth after call $call";
    }
};
```

And at the end of `t/validator_json_schema.t`, before `ok detect_warnings() == 0`:

```perl
subtest 'validate_schema restores the scope after an exception' => sub {
    my $validator = JSONSchema::Validator::Draft7->new(base_uri => 'http://e.invalid/a.json', schema => {});

    my $depth = @{$validator->scopes};
    for my $call (1 .. 3) {
        eval { $validator->validate_schema(1, schema => 'not a schema', scope => 'http://e.invalid/x.json') };
        isnt $@, '', "call $call dies";
        is scalar @{$validator->scopes}, $depth, "scope stack depth after call $call";
    }
};
```

- [x] **Step 2: Run, and confirm the failures**

Run: `bash -c 'ulimit -v 2000000; timeout 300 prove -lv t/validator_oas.t t/validator_json_schema.t'`
Expected: the first two subtests and the three scope subtests fail. One example is `got: '2' expected: '1'` for the scope depth. The `backend down` assertion fails because HEAD returns `exception: backend down` instead of dying, and the validate_request scope subtest's "dies" assertions fail for the same reason.

- [x] **Step 3: Implement**

In `validate_request` / `validate_response`:
- Call `_wrap_params` after the existing `method` / `openapi_path` / `status` croaks, outside the eval.
- Build `$context` there, and pass both into the private method.

`_catch_exception($context, $code)`:
- Records `scalar @{$self->scopes}` before running `$code`.
- On a die, truncates `@{$self->scopes}` back to that length.
- Rethrows `$@` unchanged unless it is a string starting `Failed to load resource ` or `Remote fetching is disabled: `.
- For those, pushes `error(message => 'exception: ' . exception_message($@))` onto `$context->{errors}` and returns `(0, $context->{errors}, $context->{warnings})`.

In `cache_resolve`, run `cache_id` in an `eval`. On a die, rethrow a message that already has one of the two forms unchanged, and croak `Failed to load resource <uri>: <exception_message($@)>` otherwise. Task 6 adds its rollback inside this same `eval`.

Update the comment above `_catch_exception` so it names what is caught and what is rethrown.

In `validate_schema` (Draft4 and OAS30):
- Record `scalar @{$self->scopes}` before the push.
- Run the validation in an `eval`. On a die, truncate `@{$self->scopes}` back to that length and rethrow `$@` unchanged.

`_catch_exception` keeps its own truncation for the scopes that `$ref` and `discriminator` handling push inside `_validate_request` / `_validate_response`.

- [x] **Step 4: Run the files, then the suite**

Run: `bash -c 'ulimit -v 2000000; timeout 300 prove -l t/validator_oas.t t/validator_json_schema.t t/remote_fetching.t'` then `bash -c 'ulimit -v 2000000; timeout 600 prove -l t'`
Expected: PASS. The existing subtest 'OAS30 reports a reference that fails to load instead of dying' in `t/remote_fetching.t` must still pass.

- [x] **Step 5: Changes and commit**

Reword the existing OAS30 `Changes` entry: only a reference that fails to load is returned as an `exception:` error, along with the errors and warnings found before it; argument errors and every other exception, including those thrown by parameter getters, still die. Add: "validate_schema leaves the validator's scope as it found it when it dies".

```bash
git add lib/JSONSchema/Validator/OAS30.pm lib/JSONSchema/Validator/Draft4.pm lib/JSONSchema/Validator/URIResolver.pm t/validator_oas.t t/validator_json_schema.t Changes
git commit -m "Keep OAS30 argument errors fatal and earlier results when a reference fails"
```

### Task 2: Load failures name a local file by its base name only

**Files:**
- Modify: `lib/JSONSchema/Validator/Util.pm` (`load_schema`), `lib/JSONSchema/Validator/URIResolver.pm` (`cache_resolve`)
- Test: `t/validator_oas.t`

**Interfaces:**
- Consumes: `$info`, `$responses`, `$missing` from Task 1's test block.
- Produces: in all three `load_schema` croaks (`Failed to load resource <name>: <reason>`, `Failed to load resource <name> as <type>: <reason>` and `Unsupported type of resource <name>`), a `file:` URI or a path with no scheme is named by the file's base name, and every copy of the full path in `<reason>` becomes that base name. The display name comes from one private `Util.pm` helper, which `load_schema` calls once and `cache_resolve` uses for the `Failed to load resource <uri>: <reason>` croak Task 1 added. Other URIs are unchanged.

- [x] **Step 1: Add the failing subtests** to `t/validator_oas.t` after Task 1's subtests (add `use File::Temp qw( tempfile );` to the file's `use` lines).

```perl
subtest 'OAS30 does not report server paths when a reference fails to load' => sub {
    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/b' => { post => { requestBody => { '$ref' => $missing }, responses => $responses } } } });

    my ($result, $errors) = $validator->validate_request(method => 'post', openapi_path => '/b',
        parameters => { body => [1, 'application/json', {}] });
    is $result, 0, 'fails';
    unlike errors_text($errors), qr/\Q${\ test_dir()}\E/, 'the file path is not in the error';
    like errors_text($errors), qr/^exception: Failed to load resource no_such\.json: /, 'the file is named';
};

subtest 'OAS30 does not report server paths when a file fails to decode' => sub {
    my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    print $fh "{\n";
    close $fh;
    my ($name) = $file =~ m{([^/\\]+)\z};

    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/b' => { post => { requestBody => { '$ref' => 'file://' . $file }, responses => $responses } } } });

    my ($result, $errors) = $validator->validate_request(method => 'post', openapi_path => '/b',
        parameters => { body => [1, 'application/json', {}] });
    is $result, 0, 'fails';
    unlike errors_text($errors), qr/\Q$file\E/, 'the file path is not in the error';
    like errors_text($errors), qr/^exception: Failed to load resource \Q$name\E as JSON: /, 'the file is named';
};
```

- [x] **Step 2: Run** `bash -c 'ulimit -v 2000000; timeout 300 prove -lv t/validator_oas.t'`. Expected: both new subtests fail, and the error text shows the full path.

- [x] **Step 3: Implement** in `load_schema`. Use `File::Basename::basename` (core) on `URI->new($resource)->file` for `file:`, or on the path itself when there is no scheme, and use it in all three croak messages, replacing the full path in `<reason>`.

- [x] **Step 4: Run** `t/validator_oas.t`, `t/remote_fetching.t`, `t/util_get_content.t`, then the suite. Expected: PASS.

- [x] **Step 5: Changes and commit.** Changes: "Errors for a local file that fails to load name the file, not its full path".

```bash
git add lib/JSONSchema/Validator/Util.pm lib/JSONSchema/Validator/URIResolver.pm t/validator_oas.t Changes
git commit -m "Name a local file that fails to load by its base name"
```

### Task 3: Discriminator values are matched as schema names

**Files:**
- Modify: `lib/JSONSchema/Validator/Constraints/OAS30.pm` (`discriminator`, `__detect_discriminator_ref`)
- Test: `t/validator_oas.t`

**Interfaces:**
- Produces: the instance's discriminator value is only ever a schema name.
  - A value with a `mapping` entry uses the mapping value, interpreted as now: a reference if it contains `/` or ends in `.json`, otherwise a schema name.
  - A value without one must match `^[a-zA-Z0-9._-]+$` (the OAS 3.0 Components key pattern) and becomes `#/components/schemas/<value>`.
  - A value that matches neither fails with the new error `discriminator value "<value>" is not a schema name`, which carries the instance path and schema path.
  - These checks come first, and neither prints the value or warns:
    - a missing property fails with the new error `instance does not have discriminator property "<propertyName>"`;
    - a value that is a reference (object, array or boolean) fails with the new error `discriminator value is not a string`.
    Both carry the instance path and schema path.

- [x] **Step 1: Add the failing subtest** (`tempfile` is imported by Task 2).

```perl
subtest 'OAS30 discriminator values are schema names' => sub {
    my ($fh, $other_file) = tempfile(UNLINK => 1);
    print $fh "{}\n";
    close $fh;

    my $validator = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => $info,
        paths => { '/a' => { post => {
            requestBody => { content => { 'application/json' => {
                schema => { '$ref' => '#/components/schemas/Pet' } } } },
            responses => $responses } } },
        components => { schemas => {
            Pet => { type => 'object', required => ['petType'], discriminator => {
                propertyName => 'petType', mapping => { hound => '#/components/schemas/Dog' } } },
            Dog => { type => 'object', required => ['bark'] },
        } } });

    my $request = sub {
        my $pet_type = shift;
        return $validator->validate_request(method => 'post', openapi_path => '/a',
            parameters => { body => [1, 'application/json', { petType => $pet_type }] });
    };

    my ($result, $errors) = $request->('Dog');
    is $result, 0, 'a schema name selects that schema';
    like errors_text($errors), qr/bark/, 'and applies it';

    ($result, $errors) = $request->('hound');
    is $result, 0, 'a mapping to #/components/schemas/Dog selects Dog';
    like errors_text($errors), qr/bark/, 'and applies it';

    ($result, $errors) = $request->('#/paths');
    is $result, 0, 'a JSON pointer is not followed';
    like errors_text($errors), qr/discriminator value "#\/paths" is not a schema name/, 'says why';

    ($result, $errors) = $request->($other_file);
    is $result, 0, 'a file path is not followed';
    like errors_text($errors), qr/is not a schema name/, 'says why';

    ($result, $errors) = $validator->validate_request(method => 'post', openapi_path => '/a',
        parameters => { body => [1, 'application/json', {}] });
    is $result, 0, 'a missing discriminator property fails';
    like errors_text($errors), qr/instance does not have discriminator property "petType"/, 'says why';

    ($result, $errors) = $request->({});
    is $result, 0, 'an object value fails';
    like errors_text($errors), qr/discriminator value is not a string/, 'says why';
    unlike errors_text($errors), qr/HASH\(/, 'without printing the value';
};
```

- [x] **Step 2: Run** `t/validator_oas.t`. Expected: `'#/paths'` and the file path return 1 or the wrong error, the missing property warns `Use of uninitialized value`, and the object value has no such message. The `Dog` and `hound` assertions already pass.

- [x] **Step 3: Implement** the Interfaces rule in `discriminator`. Push the new error and return 0 before calling `resolve_uri` on a value that is not a schema name.

- [x] **Step 4: Run** `t/validator_oas.t`, `t/oas.t`, then the suite. Expected: PASS.

- [x] **Step 5: Changes and commit.** Changes: "An OAS30 discriminator value without a mapping entry is matched as a schema name under #/components/schemas".

```bash
git add lib/JSONSchema/Validator/Constraints/OAS30.pm t/validator_oas.t Changes
git commit -m "Match OAS30 discriminator values as schema names"
```

### Task 4: A root `$ref` into its own document resolves

**Files:**
- Modify: `lib/JSONSchema/Validator/JSONPointer.pm` (`xget` / `get`), `lib/JSONSchema/Validator/URIResolver.pm` (`fragment_resolve`)
- Test: `t/validator_json_schema.t`

**Interfaces:**
- Produces: `JSONPointer::document_get($self, $pointer, %options)`. It is like `get`, but it walks the raw document and does not follow a `$ref` on the value it starts from. It still follows `$ref`s it meets on the way down, as `get` does. `fragment_resolve` uses it, with no options.
  - With `cached_only => 1`, a `$ref` met on the way down whose target is neither in the resolver's cache nor a bundled schema ends the walk. The returned pointer holds that `{ '$ref' => ... }` object and its scope, and nothing is loaded. Task 5 uses this.

- [x] **Step 1: Add the failing subtest** at the end of `t/validator_json_schema.t`, before `ok detect_warnings() == 0`.

```perl
subtest 'a root $ref into its own definitions' => sub {
    # unbounded recursion ends in an "Out of memory!" no eval can catch, so stop at the first warning
    my $record = $SIG{__WARN__};
    local $SIG{__WARN__} = sub { die "deep recursion\n" if $_[0] =~ /^Deep recursion/; $record->(@_) };

    my $validator = eval { JSONSchema::Validator->new(schema => {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        '$ref' => '#/definitions/x',
        definitions => { x => { type => 'integer' } } }) };
    is $@, '', 'new does not die';

    my ($result, $errors) = eval { $validator->validate_schema(5) };
    is $result, 1, '5 is an integer' or diag $@ || join "\n", map { $_->message } @{$errors // []};
    ($result, $errors) = eval { $validator->validate_schema('a') };
    is $result, 0, '"a" is not an integer';
    like join("\n", map { $_->message } @{$errors // []}), qr/type mismatch/, 'says why';
};
```

- [x] **Step 2: Run** `bash -c 'ulimit -v 2000000; timeout 300 prove -lv t/validator_json_schema.t'`. Expected: `got: '0' expected: '1'` and `'exception: deep recursion'`.

- [x] **Step 3: Implement** `document_get`, sharing the walk with `xget` through a private helper rather than copying it, and call it from `fragment_resolve`.

- [x] **Step 4: Run** `t/validator_json_schema.t`, `t/json_schema.t`, `t/remote_fetching.t`, the suite, and `ACCEPTANCE_TESTING=1 prove -l t/acceptance.t` if `Test::JSON::Schema::Acceptance` is installed (say in the report whether it ran). Expected: PASS.

- [x] **Step 5: Changes and commit.** Changes: "A schema whose root $ref points into its own definitions resolves".

```bash
git add lib/JSONSchema/Validator/JSONPointer.pm lib/JSONSchema/Validator/URIResolver.pm t/validator_json_schema.t Changes
git commit -m "Resolve a root \$ref that points into its own document"
```

### Task 5: The `new()` scan sees what validation will load, and only that

**Files:**
- Modify: `lib/JSONSchema/Validator/URIResolver.pm` (`_check_remote_refs`, `_check_remote_ref`)
- Test: `t/remote_fetching.t`

**Interfaces:**
- Consumes: Task 4's `document_get` with `cached_only => 1`.
- Produces: four rules for `_check_remote_refs`.
  1. A `$ref` whose document is already in the cache (the schema, a `documents` entry or a known `$id`) is followed without calling `resolve`. The scan takes the cached value, walks the fragment with `document_get(..., cached_only => 1)` inside `eval`, and scans the result under the scope it returns. A walk that stops at an uncached `$ref` returns that `$ref` object, which the scan checks like any other. Nothing is loaded and no cache entry is written during the scan.
  2. `$seen` is keyed on `"$scope\0" . refaddr($data)`.
  3. In OAS30, `x-` keys are skipped in the `paths`, `responses` and `callbacks` name maps, but still walked in other name maps such as `properties` and `schemas`.
  4. In OAS30, each string value of a `discriminator`'s `mapping` that contains `/` or ends in `.json` is checked like a `$ref`.

- [x] **Step 1: Add the failing subtests** to `t/remote_fetching.t`, before `ok detect_warnings() == 0`. They use the file's existing `construct`, `$schema` and `$blocked`.

```perl
subtest 'the scan at new follows local refs into any part of the schema' => sub {
    like construct('JSONSchema::Validator::Draft7', schema => {
            '$defs' => { a => $schema }, properties => { p => { '$ref' => '#/$defs/a' } } }),
        $blocked, 'a ref into $defs';
    like construct('JSONSchema::Validator::Draft7', schema => { '$ref' => 'http://e.invalid/doc.json#/defs/a' },
            documents => { 'http://e.invalid/doc.json' => { defs => { a => $schema } } }),
        $blocked, 'a ref into a container in a document';
};

subtest 'the scan at new skips x- extensions of OAS30 paths and responses' => sub {
    my $ok = { 200 => { description => 'ok' } };
    is construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' },
            paths => { 'x-vendor' => $schema, '/a' => { get => { responses => $ok } } } }),
        'ok', 'a Paths Object extension';
    is construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' },
            paths => { '/a' => { get => { responses => { %$ok, 'x-vendor' => $schema } } } } }),
        'ok', 'a Responses Object extension';
    like construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' }, paths => {},
            components => { schemas => { 'x-named' => $schema } } }),
        $blocked, 'a schema named x-named is still a schema';
};

subtest 'the scan at new checks a shared subschema under each scope' => sub {
    # the key names change the hash order, so both visit orders occur
    for my $i (1 .. 20) {
        my $shared = { '$ref' => 'other.json' };
        like construct('JSONSchema::Validator::Draft7', schema => { properties => {
                "a$i" => $shared,
                "b$i" => { '$id' => 'http://example.invalid/b.json', properties => { c => $shared } } } }),
            qr/^Remote fetching is disabled: cannot load http:\/\/example\.invalid\/other\.json\./,
            "properties a$i and b$i";
    }
};

subtest 'the scan at new checks OAS30 discriminator mappings' => sub {
    like construct('JSONSchema::Validator::OAS30', schema => {
            openapi => '3.0.3', info => { title => 't', version => '1' }, paths => {},
            components => { schemas => { Pet => { type => 'object', discriminator => {
                propertyName => 't', mapping => { dog => 'http://example.invalid/s.json' } } } } } }),
        $blocked, 'a mapping to an http URI';
};

subtest 'the scan at new loads nothing' => sub {
    my @loaded;
    my $v = eval { JSONSchema::Validator::Draft7->new(schema => {
            '$ref' => '#/definitions/a/properties/b',
            definitions => { a => { '$ref' => 'urn:example:a' } } },
        scheme_handlers => { urn => sub {
            push @loaded, "$_[0]";
            (\'{"properties":{"b":{"type":"integer"}}}', 'JSON') } }) };
    is $@, '', 'new does not die';
    is_deeply \@loaded, [], 'no handler is called at new';
    my ($r) = $v->validate_schema('x');
    is $r, 0, 'validation follows the reference';
    is_deeply \@loaded, ['urn:example:a'], 'and loads it then';
};
```

- [x] **Step 2: Run** `bash -c 'ulimit -v 2000000; timeout 300 prove -lv t/remote_fetching.t'`. Expected: the first four subtests fail. 'x-named' and 'the scan at new loads nothing' already pass; the latter guards the new local-ref walk.

- [x] **Step 3: Implement** the four rules. Update the comment above `_check_remote_refs` so it says the scan follows local references and skips extensions.

- [x] **Step 4: Run** `t/remote_fetching.t`, `t/oas.t`, `t/validator_oas.t`, then the suite. Expected: PASS, including 'what the scan must not trip on' and 'the scan at new handles a cyclic schema'.

- [x] **Step 5: Changes and commit.** Amend the 0.012 INCOMPATIBLE entry's `new()` sentence so it covers references reached through local `$ref`s and discriminator mappings.

```bash
git add lib/JSONSchema/Validator/URIResolver.pm t/remote_fetching.t Changes
git commit -m "Scan local refs, discriminator mappings and every scope at new, not x- extensions"
```

**Departures:** rule 3 skips `x-` keys only in the Paths Object, an operation's Responses Object and a Callback Object, not in `components.responses` or a `callbacks` map, whose keys are names (OpenAPI 3.0). Rule 4 uses `Util::discriminator_ref`, shared with the discriminator, so a bare-name mapping is also followed. `JSONPointer->new` takes an optional `resolver`, which the scan's walk is given instead of reading it from the validator.

### Task 6: Cache keys and lazily loaded documents never replace an entry

**Files:**
- Modify: `lib/JSONSchema/Validator/URIResolver.pm` (`new`, `cache_resolve`, `cache_id_dfs`)
- Test: `t/remote_fetching.t`

**Interfaces:**
- Produces: three rules.
  1. The `documents` key check in `new` croaks only when the existing entry is a different reference: `$self->{cache}{$key} != $documents->{$document_uri}`.
  2. `cache_id_dfs` looks up and stores each `$id` under `_document_key($id->as_string)`.
  3. `cache_resolve` indexes a loaded document with `$croak_on_conflict` set. If indexing dies, the `eval` Task 1 put around `cache_id` first deletes the document's entry and every key indexing added, then croaks as Task 1 says, so the next call repeats the same failure.

- [x] **Step 1: Add the failing subtests** to `t/remote_fetching.t` after Task 5's subtests.

```perl
subtest 'documents may hold the schema itself' => sub {
    my $root = { '$id' => 'http://e.invalid/root.json', type => 'integer' };
    is construct('JSONSchema::Validator::Draft7', schema => $root,
            documents => { 'http://e.invalid/root.json' => $root }),
        'ok', 'the same schema under its own URI';
};

subtest 'an $id with an empty fragment collides like one without' => sub {
    like construct('JSONSchema::Validator::Draft7', schema => { type => 'string' }, documents => {
            'http://e.invalid/s.json' => { type => 'integer' },
            'http://e.invalid/a.json' => { '$id' => 'http://e.invalid/s.json#', type => 'string' } }),
        qr/^documents: http:\/\/e\.invalid\/s\.json is already defined/, 'an $id ending in #';
};

subtest 'Draft 4 ids ending in # resolve with or without the #' => sub {
    my $v = eval { JSONSchema::Validator::Draft4->new(schema => {
        id => 'http://e.invalid/root.json#',
        definitions => { a => { id => 'http://e.invalid/a.json#', type => 'integer' } },
        properties => { x => { '$ref' => 'http://e.invalid/a.json' }, y => { '$ref' => 'a.json#' } } }) };
    is $@, '', 'new finds both refs locally';
    for my $property (qw/x y/) {
        my ($r, $e) = $v->validate_schema({ $property => 'no' });
        is $r, 0, "$property applies the definition";
        like errors_text($e), qr{^type mismatch .*\[schema path: /properties/$property/}, "$property says why";
    }
};

subtest 'a document loaded during validation does not change later results' => sub {
    my $replacing = '{"definitions":{"a":{"$id":"http://e.invalid/s.json","type":"integer"}}}';
    my $partial = '{"definitions":{"a":{"$id":"http://e.invalid/a.json","type":"integer"},"b":{"$id":"rel.json"}}}';
    for my $case (
        ['an $id naming a preloaded document', $replacing,
            [{ '$ref' => 'http://e.invalid/s.json' }, { '$ref' => 'urn:example:doc' }]],
        ['an $id that cannot be resolved', $partial,
            [{ '$ref' => 'urn:example:doc' }, { '$ref' => 'http://e.invalid/a.json' }]],
    ) {
        my ($name, $doc, $all_of) = @$case;
        my $v = JSONSchema::Validator::Draft7->new(schema => { allOf => $all_of },
            documents => { 'http://e.invalid/s.json' => { type => 'string' } },
            scheme_handlers => { urn => sub { (\$doc, 'JSON') }, http => sub { die "no network\n" } });
        my ($r1, $e1) = $v->validate_schema('abc');
        my ($r2, $e2) = $v->validate_schema('abc');
        is $r2, $r1, "$name: same result on the second call";
        is errors_text($e2), errors_text($e1), "$name: same errors on the second call";
    }
};
```

- [x] **Step 2: Run** `t/remote_fetching.t`. Expected:
  - 'documents may hold the schema itself' fails with `documents: ... is already defined`.
  - The `#` collision builds instead of croaking.
  - The loaded-document cases differ between the two calls.
  - The Draft 4 subtest's `new` croaks `Remote fetching is disabled: cannot load http://e.invalid/a.json`, because the `$id` is cached as `a.json#`. Rule 2 fixes it.

- [x] **Step 3: Implement** the three rules.

- [x] **Step 4: Run** `t/remote_fetching.t`, `t/json_schema.t`, `t/validator_json_schema.t`, the suite, and the acceptance run if available. Expected: PASS.

- [x] **Step 5: Changes and commit.** Changes: "A document loaded during validation whose $id names an entry already known fails with an exception: error instead of replacing it".

```bash
git add lib/JSONSchema/Validator/URIResolver.pm t/remote_fetching.t Changes
git commit -m "Never replace a cached document, and key \$ids without an empty fragment"
```

### Task 7: Only paths are read as local files

**Files:**
- Modify: `lib/JSONSchema/Validator/Util.pm` (`get_content`), POD of `fetch_remote` in `lib/JSONSchema/Validator/Draft4.pm`
- Test: `t/remote_fetching.t`, `t/util_get_content.t`

**Interfaces:**
- Produces: the order in which `get_content` handles a resource.
  1. A `scheme_handlers` entry for the URI's scheme, recognised by URI or not.
  2. `http` / `https` fetch.
  3. `file:`, a URI with no scheme, or a single-letter scheme (a Windows drive) is a local path. It goes to the `file` handler when one is given, called with `URI::file->new($path)`; otherwise it goes to `read_file`.
  4. Anything else croaks `Unsupported scheme "<scheme>" of URI <uri>` (the existing message).

- [x] **Step 1: Add the failing subtests.** In `t/remote_fetching.t`:

```perl
subtest 'an unknown scheme is not read as a local file' => sub {
    my %refuse = (
        base_uri => 'urn:example:schema',
        scheme_handlers => { file => sub { die "local files are disabled\n" } },
    );
    # URI parses a drive letter as a scheme
    for my $ref ('zz:no_such.json', 'C:/no_such.json') {
        my $v = JSONSchema::Validator::Draft7->new(schema => { '$ref' => $ref }, %refuse);
        my ($r, $e) = $v->validate_schema(1);
        is $r, 0, "$ref fails";
        unlike errors_text($e), qr/does not exist/, "$ref is not looked up on disk";
    }
};
```

In `t/util_get_content.t` (it calls the function fully qualified):

```perl
subtest 'a drive letter is a path' => sub {
    eval { JSONSchema::Validator::Util::get_content('C:/no_such_dir/x.json') };
    like $@, qr/does not exist/, 'read as a file when no handler is given';
    eval { JSONSchema::Validator::Util::get_content('zz:x.json') };
    like $@, qr/^Unsupported scheme "zz"/, 'an unknown scheme is refused';
};
```

- [x] **Step 2: Run** both files. Expected: `zz:` reports `does not exist` in both, and the `C:/` case in `t/remote_fetching.t` reaches `read_file`.

- [x] **Step 3: Implement** the four-step order. In the `fetch_remote` POD recipe, add that a reference whose scheme has no handler and is not `http`, `https` or `file` is refused.

- [x] **Step 4: Run** `t/remote_fetching.t`, `t/util_get_content.t`, then the suite. Expected: PASS.

- [x] **Step 5: Changes and commit.** Changes: "A reference with a scheme that has no handler and is not http, https or file is refused; a drive-letter path goes to the file handler".

```bash
git add lib/JSONSchema/Validator/Util.pm lib/JSONSchema/Validator/Draft4.pm t/remote_fetching.t t/util_get_content.t Changes
git commit -m "Refuse references with an unknown scheme instead of reading them as paths"
```

**Departures:** `_local_path` is the one local-path decision for `get_content`, `load_schema` and `resource_name`, and treats a drive letter as a path (Task 2 ruling).

### Task 8: `exception_message` strips compile-error locations, in linear time

**Files:**
- Modify: `lib/JSONSchema/Validator/Util.pm` (`exception_message`)
- Test: `t/util_exception_message.t`

- [ ] **Step 1: Add the failing subtests** (add `use Time::HiRes ();`).

```perl
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
```

- [ ] **Step 2: Run** the file. Expected: `got: 'syntax error at /srv/app/lib/My/Loader.pm line 3, near ...'`, and about 5 seconds against the bound of 1.

- [ ] **Step 3: Implement.**
  - After `line \d+`, also accept `, near "..."`, `, at EOF` and `, at end of line`. Strip only the location and keep the note.
  - Make the filehandle part `<[^>\s]*>` so it cannot scan past one segment.

- [ ] **Step 4: Run** the file and the suite. Expected: PASS, with every existing 'source locations are removed' case unchanged.

- [ ] **Step 5: Commit.** Changes: extend the existing exception-location line to cover compile errors.

```bash
git add lib/JSONSchema/Validator/Util.pm t/util_exception_message.t Changes
git commit -m "Strip compile error locations from exception messages in linear time"
```

### Task 9: Non-strict checks and format checks never write a bignum out in full

**Files:**
- Modify: `lib/JSONSchema/Validator/Constraints/Draft4.pm` (`uniqueItems` non-strict branch, `_loose_equal`), `lib/JSONSchema/Validator/Util.pm` (`is_bool`), `lib/JSONSchema/Validator/Format.pm` (`_validate_int_32_64`, `validate_float`)
- Test: `t/util_numbers.t`

**Interfaces:**
- Consumes: `canonical_json_key`, `json_equal`, `comparable_numbers`, `is_bignum` from `Util.pm`.
- Produces:
  - Non-strict `uniqueItems` keys objects and arrays with `canonical_json_key`, numbers with `canonical_json_key(is_bignum($_) ? $_ : 0 + $_)`, and booleans, null and strings as now.
  - `_loose_equal` compares objects and arrays with `json_equal`. When the instance is a bignum, a `$e` that is a number in non-strict terms (`is_number($e)`, which includes numeric strings such as `"5"`) is compared with `comparable_numbers`, and any other `$e` gives 0.
  - Non-strict `is_bool` returns 0 for a bignum.
  - `_validate_int_32_64` accepts a bignum only when it `is_int` and lies within `[-2**31, 2**31-1]` / `[-2**63, 2**63-1]`, compared with `bcmp`.
  - `validate_float` returns 1 for a finite bignum.

- [ ] **Step 1: Add the failing subtests** to `t/util_numbers.t`, before `ok detect_warnings() == 0`. The helper goes at file scope.

```perl
# The longest string a bignum was written out as while $code ran.
sub longest_bignum_string {
    my $code = shift;
    my $longest = 0;
    no warnings 'redefine';
    my ($float, $int) = (\&Math::BigFloat::bstr, \&Math::BigInt::bstr);
    local *Math::BigFloat::bstr = sub { my $s = $float->(@_); $longest = length $s if length $s > $longest; $s };
    local *Math::BigInt::bstr = sub { my $s = $int->(@_); $longest = length $s if length $s > $longest; $s };
    $code->();
    return $longest;
}

subtest 'non-strict checks never write a huge exponent out in full' => sub {
    my $huge = Math::BigFloat->new('1e100000');
    for my $case (
        ['uniqueItems', { uniqueItems => JSON::PP::true }, [$huge, 1]],
        ['enum of arrays', { enum => [[1]] }, [$huge]],
        ['const array', { const => [1] }, [$huge]],
        ['enum of strings', { enum => ['x'] }, $huge],
        ['boolean type', { type => 'boolean' }, $huge],
    ) {
        my ($name, $schema, $instance) = @$case;
        my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => $schema, strict => 0);
        cmp_ok longest_bignum_string(sub { $v->validate_schema($instance) }), '<', 1000, $name;
    }
    my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { uniqueItems => JSON::PP::true }, strict => 0);
    is( ($v->validate_schema(['1', 1]))[0], 0, 'non-strict uniqueItems still finds "1" and 1 equal' );
    is( ($v->validate_schema([$huge, Math::BigFloat->new('10e99999')]))[0], 0, 'and equal bignums' );
    $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { enum => ['5'] }, strict => 0);
    is( ($v->validate_schema(Math::BigInt->new(5)))[0], 1, 'non-strict enum still matches "5" with a BigInt 5' );

    my $oas = JSONSchema::Validator->new(schema => {
        openapi => '3.0.3', info => { title => 't', version => '1' },
        paths => { '/a' => { post => {
            requestBody => { content => { 'application/json' => { schema => {
                type => 'array', uniqueItems => JSON::PP::true, items => { enum => ['x', [1]] } } } } },
            responses => { 200 => { description => 'ok' } } } } } });
    cmp_ok longest_bignum_string(sub { $oas->validate_request(method => 'post', openapi_path => '/a',
            parameters => { body => [1, 'application/json', [$huge, 1]] }) }),
        '<', 1000, 'OAS30 validate_request, non-strict by default';
};

subtest 'format checks never write a huge exponent out in full' => sub {
    my $huge = Math::BigFloat->new('1e100000');
    for my $case ([int32 => 0], [int64 => 0], [float => 1], [double => 1]) {
        my ($format, $expected) = @$case;
        my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { type => 'number', format => $format });
        my $r;
        cmp_ok longest_bignum_string(sub { $r = ($v->validate_schema($huge))[0] }), '<', 1000, $format;
        is $r, $expected, "$format result";
    }
    my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { type => 'integer', format => 'int64' });
    is( ($v->validate_schema(Math::BigInt->new('9223372036854775807')))[0], 1, 'int64 maximum' );
    is( ($v->validate_schema(Math::BigInt->new('9223372036854775808')))[0], 0, 'int64 maximum + 1' );
};
```

- [ ] **Step 2: Run** `bash -c 'ulimit -v 2000000; timeout 300 prove -lv t/util_numbers.t'`. Expected: each non-strict case, the OAS30 `validate_request` case and each format reports `'100001' < '1000'`. The `"1"` and `1`, equal bignums, `enum ["5"]` and int64 limit assertions already pass and guard behaviour the change must keep.

- [ ] **Step 3: Implement** the Interfaces rules.

- [ ] **Step 4: Run** `t/util_numbers.t`, `t/format.t`, `t/oas.t`, `t/validator_oas.t`, then the suite. Expected: PASS.

- [ ] **Step 5: Changes and commit.** Changes: "Non-strict enum, const and uniqueItems, and the int32, int64, float and double formats, compare bignums without writing them out; non-strict enum and const compare objects and arrays as JSON values".

```bash
git add lib/JSONSchema/Validator/Constraints/Draft4.pm lib/JSONSchema/Validator/Util.pm lib/JSONSchema/Validator/Format.pm t/util_numbers.t Changes
git commit -m "Compare bignums without writing them out in non-strict checks and formats"
```

### Task 10: Bounds above 2\*\*53 compare exactly, and messages show the digits compared

**Files:**
- Modify: `lib/JSONSchema/Validator/Util.pm` (`comparable_numbers`, `format_number`), `lib/JSONSchema/Validator/Constraints/Draft4.pm` (`multipleOf` plain branch)
- Test: `t/util_numbers.t`

**Interfaces:**
- Produces:
  - `comparable_numbers` takes the BigFloat path when either operand is a bignum, or when either is a plain number with `abs >= 2**53`.
  - `multipleOf` uses `_is_bignum_multiple(comparable_numbers(...))` under the same condition.
  - `format_number` prints a plain non-integer through `_exact_number_string`, and a `Math::BigInt` with more than 100 digits with `bsstr`, so a value prints the same whichever class holds it.

- [ ] **Step 1: Add the failing subtests** after Task 9's.

```perl
subtest 'plain integers above 2**53 compare exactly with float bounds' => sub {
    for my $case (
        [{ maximum => 1e16 }, 10000000000000001, 0, 'maximum'],
        [{ minimum => 1e16 }, 9999999999999999, 0, 'minimum'],
        [{ exclusiveMinimum => 1e16 }, 10000000000000001, 1, 'exclusiveMinimum'],
        [{ multipleOf => 2 }, 9007199254740993, 0, 'multipleOf'],
    ) {
        my ($schema, $instance, $expected, $name) = @$case;
        my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => $schema);
        is( ($v->validate_schema($instance))[0], $expected, "$name: $instance" );
    }
};

subtest 'messages show every digit a comparison used' => sub {
    my $v = JSONSchema::Validator->new(specification => 'Draft7',
        schema => { exclusiveMaximum => Math::BigFloat->new('0.3') });
    my ($r, $e) = $v->validate_schema(0.1 + 0.2);
    is $r, 0, '0.1 + 0.2 is not below 0.3';
    like errors_text($e), qr/^0\.30000000000000004 is equal or greater than 0\.3 /, 'says by how much';

    $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { maximum => 5 });
    my $as_float = errors_text(($v->validate_schema(Math::BigFloat->new('1e150')))[1]);
    my $as_int = errors_text(($v->validate_schema(Math::BigInt->new('1' . '0' x 150)))[1]);
    is $as_int, $as_float, 'a huge value prints the same as a BigInt and a BigFloat';
};
```

- [ ] **Step 2: Run** the file. Expected: the four bound cases are wrong, and the messages show `0.3 is equal or greater than 0.3` and two different forms of 10\*\*150.

- [ ] **Step 3: Implement** the Interfaces rules.

- [ ] **Step 4: Run** the file and the suite. Expected: PASS, including the existing 'a huge exponent is never written out in full' cases and their `1e+...` messages.

- [ ] **Step 5: Changes and commit.**
  - Add: "minimum, maximum, exclusiveMinimum, exclusiveMaximum and multipleOf compare integers above 2\*\*53 exactly", and "error messages show a bignum with more than 100 digits in exponent form, and a float with all the digits that were compared".
  - Reword the existing line to: "With strict, enum, const and uniqueItems compare integers above 2\*\*53 exactly, so 9007199254740993 no longer matches 9007199254740992.0".

```bash
git add lib/JSONSchema/Validator/Util.pm lib/JSONSchema/Validator/Constraints/Draft4.pm t/util_numbers.t Changes
git commit -m "Compare bounds above 2**53 exactly and print the digits compared"
```

### Task 11: Strict `uniqueItems` keys agree with `json_equal` and are cheap for large floats

**Files:**
- Modify: `lib/JSONSchema/Validator/Util.pm` (`canonical_json_key`, `_number_key`)
- Test: `t/util_numbers.t`

**Interfaces:**
- Produces:
  - `canonical_json_key` localises `$Math::BigFloat::accuracy`, `$Math::BigFloat::precision`, `$Math::BigInt::accuracy` and `$Math::BigInt::precision`, as `comparable_numbers` does.
  - `_number_key` keys a plain scalar from `0 + $n` (under `no warnings 'numeric'`), so a numified string keys like its number.
  - Every integer with `abs` in `[2**53, 2**1024)` is keyed `p<sign><m>:<e>`, where `m` is odd and the value is `m * 2**e`, whatever holds it, so an IV, an NV and a bignum of the same value share a key. Compute it exactly, never through a double that could round:
    - an IV / UV: shift out its trailing zero bits in integer arithmetic;
    - an NV (always an integer at this size): take `m` and `e` from `POSIX::frexp`, then strip trailing zero bits from `m`;
    - an integral bignum: the same, with `Math::BigInt` operations and `bcmp` for the range.
  - No plain number builds a Math::BigInt. Every other number keeps the decimal key. The invariant in the comment above `canonical_json_key` still holds: values `json_equal` finds equal share a key, and values it finds different do not.

- [ ] **Step 1: Add the failing subtests** after Task 10's (add `use Time::HiRes ();`).

```perl
subtest 'uniqueItems ignores global bignum rounding settings' => sub {
    my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { uniqueItems => JSON::PP::true });
    for my $setting (qw/accuracy precision/) {
        my $value = $setting eq 'accuracy' ? 5 : 2;
        Math::BigFloat->$setting($value);
        Math::BigInt->$setting($value);

        is( ($v->validate_schema([9007199254740992, 2**53]))[0], 0, "$setting: 2**53 as an integer and a float" );
        is( ($v->validate_schema([$big, 2**70]))[0], 0, "$setting: 2**70 as a bignum and a float" );

        Math::BigFloat->$setting(undef);
        Math::BigInt->$setting(undef);
    }
};

subtest 'uniqueItems agrees with json_equal on a numified string' => sub {
    my $string = "5 ";
    { no warnings 'numeric'; my $n = $string + 0 }
    my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { uniqueItems => JSON::PP::true });
    is( ($v->validate_schema([$string, 5]))[0], json_equal($string, 5) ? 0 : 1, '"5 " used as a number, and 5' );
};

subtest 'strict uniqueItems keys large floats quickly' => sub {
    my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { uniqueItems => JSON::PP::true });
    my @floats = map { ($_ + 0.5) * 1e300 } 1 .. 40000;
    my $start = Time::HiRes::time();
    is( ($v->validate_schema(\@floats))[0], 1, '40000 distinct floats above 2**53' );
    cmp_ok Time::HiRes::time() - $start, '<', 5, 'without building a bignum for each';
    is( ($v->validate_schema([2**60, Math::BigInt->new(2)->bpow(60)]))[0], 0, 'a float and an equal BigInt' );
    is( ($v->validate_schema([1e300, Math::BigFloat->new('1e300')]))[0], 1, '1e300 as a float is not 10**300' );
};

subtest 'strict uniqueItems keys large integers by value, however Perl holds them' => sub {
    my $v = JSONSchema::Validator->new(specification => 'Draft7', schema => { uniqueItems => JSON::PP::true });
    is( ($v->validate_schema([1152921504606846976, 2**60]))[0], 0, '2**60 as an integer and a float' );
    is( ($v->validate_schema([1152921504606846976, Math::BigInt->new(2)->bpow(60)]))[0], 0, '2**60 as an integer and a BigInt' );
    is( ($v->validate_schema([9007199254740993, 9007199254740992]))[0], 1, '2**53 + 1 and 2**53 as integers' );
    is( ($v->validate_schema([9007199254740993, 2**53]))[0], 1, '2**53 + 1 as an integer and 2**53 as a float' );
};
```

- [ ] **Step 2: Run** the file. Expected:
  - `accuracy: 2**53 ...` gets 1.
  - `"5 " used as a number` gets 1.
  - The 40000 floats take about 10 seconds.
  - 'strict uniqueItems keys large integers by value' already passes. It guards the new key scheme.

- [ ] **Step 3: Implement** the Interfaces rules.

- [ ] **Step 4: Run** the file, which includes the existing 'strict uniqueItems' and its equal-huge-exponent cases, then the suite and the acceptance run if available. Expected: PASS.

- [ ] **Step 5: Commit.** Changes: none (these are fixes within the unreleased uniqueItems rewrite).

```bash
git add lib/JSONSchema/Validator/Util.pm t/util_numbers.t
git commit -m "Key strict uniqueItems numbers by value, cheaply and ignoring global rounding"
```
