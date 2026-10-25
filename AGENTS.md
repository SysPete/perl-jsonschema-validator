# AGENTS.md

Guidance for coding agents working in this repository.

## Project

`JSONSchema::Validator` is a Perl validator for JSON Schema Draft 4, 6 and 7
and OpenAPI 3.0. This repository is a fork (SysPete/perl-jsonschema-validator)
of an upstream that is no longer maintained. The fork keeps the namespace and
aims to add draft 2019-09, draft 2020-12 and OpenAPI 3.1.

## Layout

- `lib/JSONSchema/Validator.pm` - entry point; picks a validator class from
  `$schema` / `openapi` or the `specification` option.
- `lib/JSONSchema/Validator/Draft{4,6,7}.pm`, `OAS30.pm` - validator classes.
  Each draft inherits from the previous one (`Draft7` -> `Draft6` -> `Draft4`).
- `lib/JSONSchema/Validator/Constraints/*.pm` - keyword implementations, one
  method per keyword, with the same inheritance chain.
- `URIResolver.pm` (`$ref` / document loading), `JSONPointer.pm`, `Format.pm`
  (`format` checks), `Error.pm` (error objects), `Util.pm` (helpers,
  JSON/YAML loading). `Util.pm` is internal, not a public API: its POD says
  so, and its functions get no POD of their own.
- `lib/JSONSchema/Validator/schemas/` - bundled meta-schemas.
- `t/` - tests; fixtures in `t/data/`, shared helper in `t/lib/Helper.pm`.
- `bench/` - benchmarks and per-machine baselines; see `bench/README.md`.

## Commands

Run from the repository root.

```sh
prove -l t                    # full test suite
prove -l t/json_schema.t      # one file
ACCEPTANCE_TESTING=1 prove -l t/acceptance.t
                              # official JSON-Schema-Test-Suite; needs
                              # Test::JSON::Schema::Acceptance (and Perl 5.20+)
```

`dzil test` / `dzil build` run the author tests (Perl::Critic with
`perlcritic.rc`, POD spelling, `Changes` format) and are only needed for
release work. See `DEVELOPMENT.md` for installing dependencies.

`t/acceptance.t` skips everything unless `ACCEPTANCE_TESTING=1` is set, and
skips silently when `Test::JSON::Schema::Acceptance` is not installed. A plain
`prove -l t` passing says nothing about spec conformance; check the
acceptance run actually executed before citing it.

## Code style

- Match the existing code: `use strict; use warnings;`,
  `my ($self, ...) = @_`, no subroutine signatures, no postfix dereferencing.
- Minimum Perl is set in `dist.ini` (`[Prereqs] perl`). Don't use features
  newer than that floor.
- There is no `.perltidyrc` and existing code is not uniformly formatted.
  Don't reformat code you are only passing through: a whole-file reflow
  buries the real change. A wanted reformat goes in its own commit.
- Naming: methods are verbs, attributes are nouns, private subs start with
  `_`, constants are `UPPER_SNAKE_CASE`. Before picking a name, check the
  word doesn't already mean something here - "scope", "resource", "context"
  and "specification" are all taken.
- No temporal coupling: don't design an API where one call must be followed
  by another before the object is safe to use (build now, configure later).
  Where two things must happen together, one method does both. Propose a
  two-phase API, or new mutable state on an existing object, in prose before
  writing it.

## Comments and POD

- POD lives inline in the modules using Pod::Weaver directives (`=method`,
  etc.); `weaver.ini` assembles the rest. `README.md` is built from it.
- POD states the contract; a `#` comment explains why. Neither restates what
  the code, the sub name or the arguments already say, and a fact lives in
  one place - not in both POD and a comment.
- A comment is one sentence naming the constraint the code cannot state (a
  spec rule, a resolution order, a Perl trap). If there isn't one, write no
  comment.
- Use ASCII punctuation in POD and comments: `->` not an arrow, `-` not an
  em dash, `...` not an ellipsis, straight quotes. If a file needs non-ASCII
  text, `=encoding utf8` must be its first POD directive. POD is
  spell-checked at release (`[Test::PodSpelling]`; stopwords in `dist.ini`).

## Tests

- Add a `t/` test for every behaviour change or bug fix. Tests that load
  `Helper` with `detect_warnings` end with a no-warnings check, so keep code
  warning-free.
- Write each new scenario as a named `subtest`. Don't restructure existing
  flat tests unless you are changing them for another reason.
- A failing assertion should show real data: compare error messages,
  instance paths and schema paths, not error counts or array positions, so a
  failure diff says what went wrong.

## Dependencies

- Runtime: core Perl plus `URI` only. Optional modules (`YAML::XS`,
  `YAML::PP`, `Cpanel::JSON::XS`, `JSON::XS`) are used when present and must
  never be required at load time; they are listed under `skip` in `dist.ini`.
- Any new runtime dependency needs a stated justification. Prefer the
  optional, load-when-present pattern.

## Compatibility

- The `JSONSchema::Validator::Error` objects for Draft 4/6/7 and `OAS30` are
  a stable interface: fields (`message`, `instance_path`, `schema_path`,
  `context`), `to_string` / `TO_JSON` output and existing message wording do
  not change. New messages may be added. The one exception: since 0.012,
  `exception:` messages drop the "at FILE line N." locations Perl adds,
  because they can reach API clients.
- `validate_request` / `validate_response` keep returning
  `($result, $errors, $warnings)`.
- Bug fixes may change validation results; note them in `Changes`.

## Generated files - do not edit by hand

- `README.md` - built from the POD in `lib/JSONSchema/Validator.pm` by
  `dzil build`. Edit the POD instead.
- `cpanfile` - written by `dzil build` from `dist.ini`. Change prereqs in
  `dist.ini`; if you can't run `dzil`, update `cpanfile` to match by hand.

## CI

- Pin every GitHub Action to a full commit SHA with the release in a
  comment, never a tag: `uses: actions/checkout@<sha> # v7.0.1`. Resolve the
  SHA with `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha`.
- Branch protection requires only the `CI passed` job, which passes only if
  every job in its `needs` succeeded. A new job that must pass goes in that
  list. The `history` job fails a branch containing merge commits.

## Changes and commits

- Record user-visible changes at the top of `Changes` under an unreleased
  entry, in the existing format (checked by `Test::CPAN::Changes`).
- Commit messages: terse, imperative mood.
- Bring a branch up to date by rebasing onto `master`, never by merging
  `master` into it; pull requests are merged with a merge commit. Ask before
  force-pushing a rebased branch.
- This is a public repository: no criticism of other projects and no names
  of downstream users in code, POD, commit messages or docs.

## Process

Work is planned and reviewed with the
[superpowers](https://github.com/obra/superpowers) and
[paad](https://github.com/Ovid/paad) skills.

1. Design: [brainstorming](https://github.com/obra/superpowers/tree/main/skills/brainstorming)
   produces or updates the spec in `docs/superpowers/specs/`.
   [pushback](https://github.com/Ovid/paad/tree/main/plugins/paad/skills/pushback)
   reviews it, often over several rounds, until no open issues remain.
2. Plan: each phase gets a plan in `docs/superpowers/plans/`, written with
   [writing-plans](https://github.com/obra/superpowers/tree/main/skills/writing-plans)
   when the phase starts. pushback reviews the plan too, then
   [alignment](https://github.com/Ovid/paad/tree/main/plugins/paad/skills/alignment)
   checks it against the spec. Each task becomes an issue in the phase's
   milestone.
3. Build: [subagent-driven-development](https://github.com/obra/superpowers/tree/main/skills/subagent-driven-development)
   or [executing-plans](https://github.com/obra/superpowers/tree/main/skills/executing-plans),
   with [test-driven-development](https://github.com/obra/superpowers/tree/main/skills/test-driven-development)
   and [systematic-debugging](https://github.com/obra/superpowers/tree/main/skills/systematic-debugging).
   Tick the plan's checkboxes as tasks finish, and record in the plan where
   the work departed from it.
4. Review: [agentic-review](https://github.com/Ovid/paad/tree/main/plugins/paad/skills/agentic-review)
   on the branch before opening the PR, then a PR to `master`, rebased and
   merged with a merge commit (see "Changes and commits").
5. Across sessions: [handoff](https://github.com/Ovid/paad/tree/main/plugins/paad/skills/handoff)
   when context runs out;
   [rethink](https://github.com/Ovid/paad/tree/main/plugins/paad/skills/rethink)
   to check a recommendation before acting on it.
