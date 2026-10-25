# JSON Schema 2019-09, 2020-12 and OpenAPI 3.1 - Design

Status: draft for review, 2026-10-25

## Why

`JSONSchema::Validator` validates JSON Schema Draft 4, 6 and 7 and OpenAPI
3.0. Upstream (skbkontur) has had no commits since September 2022, and its
open issues for draft 2019-09 (#5), 2020-12 (#6) and OpenAPI 3.1 (#2, #7)
are still open, so its users cannot move past OpenAPI 3.0.

This fork (SysPete/perl-jsonschema-validator, same namespace) aims to be a
complete, spec-conformant validator that is independent of any web framework
and light on dependencies: callers pass plain Perl data, whatever framework
they use. It must serve validation under test and in production alike, of
requests, responses or both, including when its errors are returned to API
clients.

## Goals

1. Full compliance with JSON Schema draft 2019-09 and draft 2020-12, measured
   by the official JSON-Schema-Test-Suite (as shipped by
   `Test::JSON::Schema::Acceptance`): every required test **and** every
   optional test passes, with no `todo_tests` entries.
2. Optional-suite compliance for Draft 4, 6 and 7 as well. Their required
   suites already pass and must keep passing.
3. An OpenAPI 3.1 validator, `JSONSchema::Validator::OAS31`, built on 2020-12,
   with the same request/response validation that `OAS30` offers.
4. The four output formats from the 2019-09 / 2020-12 specs (section
   "Output Formatting"): `flag`, `basic`, `detailed` and `verbose`, for the
   new validators.
5. Error messages that are fit to show to an API client, and results that
   never leak server internals such as file paths.
6. Request and response validation cheap enough to run on every production
   request and response, at `basic` as well as `flag`.
## Non-goals

- Framework adapters (Plack, Catalyst, Dancer2, Mojo...). The core takes plain
  Perl data only. Adapters belong in separate distributions.
- Distribution: PAUSE adoption, the CPAN release process and how
  downstream projects install the fork are decided later, not in this project.
- Draft 2019-09/2020-12 output formats for the existing validators (Draft 4/6/7,
  `OAS30`). They keep their current errors.
- Any JSON Schema draft after 2020-12, and OpenAPI 3.2.

## Anti-goals

Failure even if every test passes:

- A dependency on any web framework or its request/response classes.
- Runtime dependencies beyond core Perl and a few small, stable,
  widely-used modules. Today the only non-core runtime dependency is `URI`;
  YAML (`YAML::XS`/`YAML::PP`) and fast JSON (`Cpanel::JSON::XS`/`JSON::XS`)
  are used when present, `JSON::PP` otherwise.
- Breaking existing callers in a minor release, beyond the deliberate
  changes listed under Compatibility.

## Constraints

- **Perl 5.20 minimum** (`Test::JSON::Schema::Acceptance` also requires 5.20).
  The code keeps its existing style: `use strict; use warnings;`,
  `my ($self, ...) = @_`, no signatures, no postfix dereferencing. Features up
  to 5.20 (`//`, `state`, `s///r`, key/value slices) are fine. CI tests 5.20
  through the latest stable Perl: Linux covers every version, macOS and
  Windows the oldest and newest.
- **Every new runtime dependency is justified** in the plan that adds it.
  Format and IDN support use existing CPAN modules, as optional dependencies
  loaded when present (the same pattern as the YAML modules).
- **Namespace stays `JSONSchema::Validator`.**

## Compatibility

Decided by the maintainer:

- Bug fixes are allowed even when they change results (e.g. upstream #37,
  zero-length strings passing `minLength: 1` in parameters).
- **The `OAS30` error format is stable**: the `JSONSchema::Validator::Error`
  objects keep their fields (`message`, `instance_path`, `schema_path`,
  `context`), `to_string`/`TO_JSON` output and message wording, and
  `validate_request`/`validate_response` keep returning
  `($result, $errors, $warnings)`.
- `Draft201909`, `Draft202012` and `OAS31` are new and may do anything.
- **Remote `$ref` fetching is off by default** in every validator, including
  the existing ones. This is a deliberate behaviour change and gets a
  prominent `Changes` entry. It covers every fetch a document triggers,
  through `$ref` or `$schema`. A caller who passes `resource => 'http://...'` (or calls
  `validate_resource`/`validate_paths` with an HTTP URI) has asked for that
  fetch, and it keeps working. A caller-supplied `scheme_handlers` entry for
  a scheme counts as opting in for that scheme.
- **Draft 4/6/7 keep asserting `format` by default**, as today, with the
  hand-written checks in `Format.pm` kept as the fallback. They use a CPAN
  module for a format when one is installed, and never refuse to build over a
  missing module. Unknown formats keep passing. Their optional format tests
  therefore pass only with the optional modules installed.

Builder's calls, made while writing this document (revisit if wrong):

- The `OAS30` stability promise also covers Draft 4/6/7, which share its
  constraint classes and `Error` objects.
- "Remote" means `http` and `https`. Fetching them needs an explicit opt-in
  (constructor option). `file:` URIs and plain paths keep working, since a
  schema's local files are under its author's control. A caller can preload
  documents by URI (a `documents => { $uri => $schema }` option), which
  is also how a caller supplies remote schemas without enabling fetching.
  Caller-supplied `scheme_handlers` keep working as now.

## Design decisions

### Class layout

```
Draft4 -> Draft6 -> Draft7 -> Draft201909 -> Draft202012
Draft4 -> OAS30
Draft202012 -> OAS31
```

and the matching `Constraints::*` classes. Most new keyword work lands in
`Draft201909`; `Draft202012` overrides the keywords that changed
(`items`/`prefixItems`, `$dynamicRef`/`$dynamicAnchor`, the `contains`
interaction with `unevaluatedItems`, the split format vocabularies).

These classes are the public entry points and pick the default dialect for a
schema without `$schema`. They do not fix the dialect of everything they
validate: see Dialects.

The request/response machinery in `OAS30` (`validate_request`,
`validate_response`, parameter and body handling) moves into shared code that
both `OAS30` and `OAS31` use. Whether that is a base class, a role-like mixin
or a helper object is left to the builder; `OAS30` behaviour must not change.
Where 3.1 differs, `OAS31` has its own behaviour:

- `OAS31` has a walker that knows the OpenAPI 3.1 document structure: which
  positions hold Schema Objects and which hold Reference Objects. It hands
  each Schema Object to the 2020-12 indexer, and never treats `$ref`-shaped
  data in `example`, `examples` values, `x-*` extensions or `links` as a
  reference.
- A Schema Object's `$ref` is never collapsed by the pointer layer
  (`JSONPointer::xget` does that today): the schema is validated where it
  sits, with `$ref` as an ordinary keyword alongside its siblings. A
  Reference Object (a `$ref`'d parameter, request body, response or path
  item) is replaced by its target, its `summary`/`description` overrides
  applying as OpenAPI 3.1 says.
- Webhooks are validated through the same calls: `validate_request` and
  `validate_response` accept `webhook => $name` in place of `openapi_path`,
  with `method` as usual. For a webhook the server sends the request, so
  `validate_request` checks the outgoing payload.

### OAS31 types

`OAS31` validates request and response bodies with strict JSON types: the
string `"5"` is not an `integer`, and only JSON booleans are `boolean`.
Strict checks judge what a Perl value is, not how a particular encoder will
serialise it: the JSON encoders disagree with each other on scalars that have
been used both as strings and as numbers, so no single rule can match "the
wire" for every caller. On Perl 5.36 and later, strict checks use
`builtin::created_as_number` and `builtin::created_as_string`, which record
how a value was created and are unaffected by later use. Before 5.36 they use
the closest rule the SV flags allow. The POD tells callers who need the
result to match their encoder exactly to pass the encoded JSON, which
`_validate_content` already decodes. The same classification applies to the
strict checks of `Draft201909` and `Draft202012`; whether Draft 4/6/7 adopt
it as a bug fix is the builder's call.

Parameters (path, query, header, cookie), and the fields of string-valued
media types (`application/x-www-form-urlencoded`, `multipart/form-data`,
`text/*`), arrive as strings. They are converted during validation, not in a
pass before it:

- such values are marked as coming from a parameter or form field; JSON
  bodies are never converted;
- when a subschema's `type` check meets a marked string that is a valid
  spelling of an allowed type, it accepts it, and the later keywords of that
  same subschema (`maximum`, `enum`, ...) see the converted value. Each
  subschema decides on its own, so every applicator is covered and each
  `anyOf`/`oneOf` branch reaches its own answer: `"50"` against
  `anyOf: [{type: integer, maximum: 10}, {type: string, pattern: "^[0-9]+$"}]`
  is valid through the second branch;
- spellings are defined once: `integer` is an optional minus sign and
  digits; `number` is a JSON number; `boolean` is `true` or `false`; `null`
  is only the empty value, and only where the schema allows `null`;
- a marked string that is no valid spelling of any allowed type fails with
  an error saying so.

Splitting serialised values (`style`, `explode`, `deepObject`) is the
caller's job, and the POD says so: callers pass `ids => [1, 2]`, not
`"1,2"`. `OAS30` keeps its current non-strict behaviour unchanged.

`JSONSchema::Validator->new` detects the new drafts from `$schema`
(`https://json-schema.org/draft/2019-09/schema`,
`https://json-schema.org/draft/2020-12/schema`) and OpenAPI 3.1 from
`openapi: 3.1.x`. The bundled meta-schemas (including the 2019-09 and 2020-12
vocabulary meta-schemas, and the OAS 3.1 base and dialect schemas) live under
`lib/JSONSchema/Validator/schemas/` as today.

Every bundled schema is registered with the resolver under its canonical
`$id` in every validator, whatever the remote-fetching setting. A `$ref` to
any of them (from a meta-schema to its vocabulary meta-schemas, from an OAS
dialect to the 2020-12 meta-schema, or from a user schema to a draft's
meta-schema) is served from the bundled copy and never touches the network.

### Loading referenced documents

The new validators (`Draft201909`, `Draft202012`, `OAS31`) load everything at
construction: they follow every `$ref` and every `$schema` reachable from the
root document (for `OAS31`, starting from the Schema Objects its walker
finds), load and index each referenced document (`$id`s, anchors, dynamic
anchors, dialect), and check them all for formats they cannot assert. A missing format module, an
unresolvable `$ref` or a document that cannot be loaded makes construction
fail; none of them can first surface while validating a request.

### Dialects

The dialect - which keywords are active, how `$id` and anchors work, which
vocabularies apply - is a property of each schema resource, chosen from that
resource's `$schema` (or inherited from the enclosing resource, or the
validator's default when there is none). Draft 4, 6, 7, 2019-09 and 2020-12
are dialect definitions that one validation engine switches between
mid-validation. A Draft 7 schema that `$ref`s a 2019-09 schema has that
schema evaluated by 2019-09 rules, and the reverse; this holds in every
validator, Draft 4/6/7 included, as the optional suite's `cross-draft` tests
require.

`OAS30` is the exception. Its Schema Objects use an OAS 3.0 Schema Object
dialect with exactly `OAS30`'s current keyword set (`nullable`,
`discriminator`, `readOnly`, `writeOnly`, `deprecated` added;
`patternProperties`, `dependencies` and `additionalItems` ignored), and
`OAS30` ignores `$schema` as it does today, so it never switches dialect.

Custom meta-schemas are supported. A `$schema` that is not a known dialect
URI is loaded (bundled, preloaded, or through an opted-in scheme) and its
`$vocabulary` read to decide which keywords are active. A meta-schema with no
`$vocabulary` gets the full keyword set of the draft it is built on, as the
spec recommends. `JSONSchema::Validator->new` stops croaking
`unknown specification` for such schemas: it follows the custom meta-schema's
own `$schema` chain to a known draft and builds that draft's validator class,
so the result shape is the one that class returns. It validates the schema
against its own meta-schema. A vocabulary the
meta-schema marks required (`true`) that this library does not implement
makes construction fail, as 2020-12 core requires; an unknown optional one is
ignored. When a meta-schema includes the `format-assertion` vocabulary,
formats are asserted whatever the constructor option says.

### Keyword dispatch

Today `_validate_schema` calls any constraint method whose name matches a
schema key (`$self->constraints->can($k)`), so a schema key that happens to
match a non-keyword method is executed as one. Dispatch instead comes from
an explicit keyword table per dialect, grouped by vocabulary. Draft 4/6/7 use
tables too, as the engine is shared; their results must not change.

The resolver's table of schema-bearing keywords (`$SEARCH_ID` in
`URIResolver.pm`) becomes per-dialect for the same reason: 2019-09 adds
`$defs`, `dependentSchemas`, `unevaluatedProperties`, `unevaluatedItems`,
`contentSchema` and others, and 2020-12 adds `prefixItems`.

### Annotations

`unevaluatedProperties`, `unevaluatedItems` and the `verbose` output need
annotation results from sibling and nested subschemas, including through
`$ref`, `allOf`/`anyOf`/`oneOf`, `if`/`then`/`else`, `dependentSchemas` and
`contains`. Annotations from failed subschemas are dropped, as the spec
requires.

Annotations are only collected when something will use them: the schema
contains an `unevaluated*` keyword, the output level is `verbose`, or the
caller asks for annotations at `basic`/`detailed` (an option, off by default;
the spec allows skipping collection nothing needs). `flag` validation of a
schema without `unevaluated*` collects nothing and stops at the first
failure.

Builder's call: annotations travel in the `$data` hashref that every
constraint already receives, so constraint signatures don't change.

### Dynamic scope

`$recursiveRef`/`$recursiveAnchor` (2019-09) come first; `$dynamicRef`/
`$dynamicAnchor` (2020-12) then extend the same machinery. The existing
`scopes` stack in `Draft4` is a starting point but tracks only base URIs; the
builder decides how far to extend it versus replace it.

### Output

The new validators return results in the spec's output format, at a level the
caller chooses when calling validate: `flag`, `basic`, `detailed` or
`verbose`. The level is a validate-time argument rather than post-processing,
so `flag` can stop at the first failure. Each output unit carries `valid`,
`keywordLocation`, `absoluteKeywordLocation` (where applicable),
`instanceLocation` and `error` or `annotations`, as the spec describes. The
exact Perl API (plain hashref vs result object with `TO_JSON`) is the
builder's call; the JSON produced must match the spec.

`OAS31` request and response validation also reports failures that come from
OpenAPI rather than JSON Schema: an unknown operation, a missing required
parameter, an unsupported content type, an undocumented status. These use
the same output units, with one location rule for OpenAPI-level and
schema-level units alike - the JSON Schema rule, applied to the OpenAPI
document:

- `instanceLocation` points into the request/response, e.g.
  `/parameters/query/limit`, `/parameters/header/X-Foo`, `/body`.
- `keywordLocation` is the path actually walked from the OpenAPI document
  root, including `$ref` steps, e.g.
  `/paths/~1me~1items/get/parameters/0/required`, or
  `/paths/~1me~1items/get/parameters/0/$ref/required` when that parameter is
  a `$ref`. A schema error inside a body continues the same path into the
  schema.
- `absoluteKeywordLocation` is the dereferenced location, under the public
  identifiers described below, e.g.
  `https://api.example.com/openapi.yaml#/components/parameters/Limit/required`.
- Merging path-level and operation-level parameters keeps each parameter's
  source location.
- An unknown operation reports the path item's location; when even the path
  is unknown, `keywordLocation` is empty.

What `OAS30` returns as `$warnings` (deprecated, readOnly/writeOnly
direction) becomes annotations or errors in `OAS31` output; the builder
chooses which, and documents it.

Messages are written for someone who has not seen the schema ("expected
integer, got string"), not as keyword dumps.

Output from every new validator (`Draft201909`, `Draft202012`, `OAS31`)
identifies documents only by public identifiers, never by a file path:

- a document's public identifier is its `$id` if it has one; otherwise its
  path relative to the root document, resolved against the root's public
  URI;
- the root's public URI is the caller's `base_uri`, e.g.
  `https://api.example.com/openapi.yaml`. With it, every
  `absoluteKeywordLocation` is a full URI as the spec requires, e.g.
  `https://api.example.com/params.yaml#/Limit`;
- without a `base_uri`, `absoluteKeywordLocation` is emitted as a relative
  reference (`#/components/...`, `params.yaml#/Limit`), and the POD says that
  passing `base_uri` gives spec-exact output.

### Formats

- In 2019-09 and 2020-12, `format` is an annotation by default. Assertion is
  enabled by a constructor option (and in 2020-12 by the `format-assertion`
  vocabulary).
- Format checks use existing CPAN modules where a good one exists, loaded
  only if installed. Hand-written checks only where no suitable module
  exists. Which module backs which format is decided per format in the
  formats phase plan, with justification.
- These rules are for `Draft201909`, `Draft202012` and `OAS31`; Draft 4/6/7
  follow the Compatibility section.
- When assertion is enabled and a schema - the root document or any document
  reachable through `$ref` - uses a format whose module isn't installed, the
  validator **refuses to build**: it croaks naming the format
  and the module to install. The 2020-12 spec requires refusing to process a
  schema whose required format assertions can't be evaluated, and it is
  safer than silently passing every value in production.
- Tests: the optional format test files are skipped, with a message naming
  the module, when their module is missing, so a minimal install still passes
  its tests. The fork's CI installs every optional module; that is where
  optional compliance is checked.
- Arbitrary-precision numbers use core `Math::BigInt`/`Math::BigFloat`.
- ECMA-262 regex semantics (e.g. `\d` is ASCII-only) are met by translating
  patterns to Perl regexes, not by a new dependency.

### Performance

A caller may validate every request and response in production and return
the errors to clients, which means `basic` output, not just `flag`.

Phase 0 builds a synthetic OpenAPI 3.0 benchmark document and records a
baseline. The document is shaped like a large real-world API: around 2,000
`$ref`s into shared components, `nullable` fields, path, query and body
parameters, nested objects and arrays. The baseline is `OAS30` validating
representative passing and failing requests and responses against it, plus
Draft 7 on a few schemas. Later phases re-run it.

Builder's calls, as starting gates:

- Existing validators (Draft 4/6/7, `OAS30`) regress by no more than 10%.
- `OAS31` on the same document, translated to 3.1, is no slower than `OAS30`
  was at the baseline, at both `flag` and `basic`, on passing and failing
  requests and responses.

## Phases

Each phase is a GitHub milestone on SysPete/perl-jsonschema-validator. Each
task in a phase is a GitHub issue, linked to its section of that phase's
plan. Issues link to the matching upstream issue where one exists. The spec
and plans live in this repository under `docs/superpowers/specs/` and
`docs/superpowers/plans/`. Plans are written one phase at a time, when the
phase starts, so later plans can use what earlier phases taught.

The suite is the yardstick: a task is done when its test files pass and
everything that passed before still passes.

**0. Revive the fork.** Perl 5.20 minimum, CI matrix updated, current
`Test::JSON::Schema::Acceptance`, acceptance tests run in CI. Fix what the
newer suite exposes for Draft 4/6/7. Remote fetching off by default, with the
preload option, and bundled schemas registered under their canonical `$id`. Cheap upstream bugs (#20 missing test dependency, #37
zero-length `minLength`). Synthetic benchmark document and baseline.

**1. Draft 2019-09 core.** `Draft201909` with every keyword except
`unevaluated*` and `$recursiveRef`/`$recursiveAnchor`: `$defs`, `$anchor`,
`$id` without fragments, `$ref` alongside other keywords,
`dependentRequired`, `dependentSchemas`, `minContains`, `maxContains`,
`$vocabulary`, content keywords, meta-schemas. Dialects per schema resource,
custom meta-schemas, keyword tables. Loading all referenced documents at
construction. 2019-09 added
to the acceptance run, with the remaining files as todo. A `cases_ok` test
helper in `t/lib/Helper.pm`: each case a hashref with a `name` and optional
`setup` and `check`, run as a named subtest through shared test code, with
no new test dependency. `t/util_numbers.t` moves to it as its first user;
new table-shaped tests use it, and existing files move only when changed
for another reason.

**2. Output formats.** Output units with keyword, absolute keyword and
instance locations; `flag`, `basic` and `detailed` for `Draft201909`.

**3. Annotations and `unevaluated*`.** Annotation collection,
`unevaluatedProperties`, `unevaluatedItems`, `verbose` output. Benchmark gate.

**4. Dynamic scope.** `$recursiveRef`/`$recursiveAnchor`. Required 2019-09
suite fully passing.

**5. Draft 2020-12.** `Draft202012`: `prefixItems` and the new `items`,
`$dynamicRef`/`$dynamicAnchor`, `contains` and `unevaluatedItems`, format
vocabularies. Required 2020-12 suite fully passing.

**6. Optional suite.** Formats (with their optional modules), bignum, ECMA
regex, cross-draft references and the rest of `optional/`, for every
supported draft. No `todo_tests` remain.

**7. OpenAPI 3.1.** Shared request/response code extracted from `OAS30`,
`OAS31` on `Draft202012`, OAS 3.1 meta-schemas, `jsonSchemaDialect`,
`webhooks` (including `webhook => $name` validation), optional `paths`,
`components/pathItems`, the OpenAPI-aware walker, `$ref` siblings in Schema
Objects, strict body types and schema-directed conversion, OpenAPI failures
as output units. Benchmark gate. Upstream #2 and #7.

Phases 6 and 7 are independent and may run in either order.

## Left to the builder

- Internal structure beyond what is decided above: how annotations and
  dynamic scope are represented, how OAS code is shared, the Perl API shape
  of output results.
- Which CPAN module backs each format, within the dependency rules.
- Task breakdown within each phase.
- POD for all new public classes and options; README and `Changes` kept
  current.
