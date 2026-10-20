# AGENTS.md

## Overview

`typebox` is a Crystal port of the parts of
[TypeBox](https://github.com/sinclairzx81/typebox) 1.3.27 that
[`@earendil-works/chord`](https://github.com/earendil-works/pi/tree/main/packages/chord)
uses:

- the `Type.*` builders;
- the JSON Schema check and error engine;
- `Value.Check`, `Errors`, `Default`, `Clean` and `Clone`;
- the format registry;
- the en_US locale;
- the `Extends`/`Evaluate`/`Priority` machinery that `Clean` and `Default` depend on.

Its consumer is `llm-chord`, which must stay wire-compatible with TypeScript hosts.

Upstream is the specification. When behavior is in doubt, read the TypeBox sources in
`node_modules/typebox/build` (the `.mjs` files) and match them, quirks included.

## Repository layout

```
src/typebox.cr               Entry point: requires the tree
src/typebox/schema.cr        Schema: ordered entries, kind, optional/readonly/immutable/unsafe flags
src/typebox/coerce.cr        Crystal values and named options to JSON::Any and schema entries
src/typebox/settings.cr      maxErrors, exactOptionalPropertyTypes, unionPrioritySort
src/typebox/guard.cr         JavaScript semantics: number kinds, ===, deep equality, key order, graphemes
src/typebox/js_regex.cr      Translates JavaScript (u-flag) regular expressions to PCRE2
src/typebox/error.cr         ValidationError, Locale (en_US messages)
src/typebox/format.cr        Format registry and the date/time/uri/url checks
src/typebox/format/idna.cr   hostname, idn-hostname, punycode, bidi rules
src/typebox/engine.cr        CheckContext/ErrorContext, Validator (CheckSchema/ErrorSchema), Pointer, Hashing
src/typebox/type.cr          Type builders and Record key resolution
src/typebox/pattern.cr       Record pattern decoding (template-literal pattern parser subset)
src/typebox/extends.cr       Structural extends check (True/Union/False)
src/typebox/evaluate.cr      Compare, Broaden, Distribute, Narrow, Composite, Flatten, Priority
src/typebox/value.cr         Value.check/errors/default/clean/clone, UnionPrioritySort
spec/                        Crystal specs
```

## Build / test / spec

```console
crystal spec
crystal tool format --check
ameba
```

`ameba` reads `.ameba.yml`, which disables three rules:

- `Naming/QueryBoolMethods`
- `Lint/NotNil`
- `Metrics/CyclomaticComplexity`

The specs never hit the network.

## Code standards

- Every Crystal file opens with a single comment naming its path, e.g. `# src/typebox/engine.cr`. There are no other comments in code.
- Write compiler-friendly, performance-focused, idiomatic Crystal, with a data-driven design.
- The usage-facing API must be ergonomic.
- Prevent shotgun surgery: a behavior change should touch one cohesive spot.
- Never use `out` as an identifier. It is a reserved keyword.
- Never edit the `version` field in `shard.yml`.
- Keep `README.md` (usage and public API) and this file in sync with the code.

## Conventions specific to this codebase

- **Values.** Values are `JSON::Any?`, and `nil` is JavaScript `undefined`. JSON integers are `Int64`. Number checks go through `Guard`, so `1` and `1.0` compare equal the way `===` does.
- **Key order.** `Guard.keys` returns JavaScript property order: integer-like keys ascending, then insertion order. Iterate values with it whenever upstream uses `Object.keys` or `Object.getOwnPropertyNames`, because error order depends on it.
- **Schema entries.** A `Schema` stores `entries` in TypeBox's key order. Children are `Schema`, `Array(Schema)` or `Hash(String, Schema)`.
  - Builders call `Type.create(kind, structural, options)`, which mirrors `Memory.Create`: options override structural keys in place.
  - `with_entries` mirrors `Memory.Update`.
  - Hidden TypeBox keys (`~kind`, `~optional`, …) are fields, never JSON.
- **Validation engine.** `Validator` mirrors `schema/engine/schema.mjs` keyword by keyword, in the same order.
  - `check_schema` short-circuits.
  - `error_schema` evaluates every keyword and returns `false` once `maxErrors` is reached.
  - `check_push`/`error_push` reproduce `(Push() && Check()) && Pop()`: a failing child never pops its frame, and unevaluated keywords depend on that.
- **`$ref` resolution.** `$ref` follows `schema/resolve/resolve.mjs` for documents without `$id`.
  - The fragment pointer is tried at every object node of the document root.
  - A node that matches returns before its children are searched.
  - Among children, the last match wins.
  - `const` and `enum` subtrees are skipped.
  - A missing target is the `false` schema.
- **Recursive checks.** `Value` functions that call `Check` on a sub-schema (union variants in `Default` and `Clean`) build a new `Validator` rooted at that sub-schema, as upstream does.
- **Union priority sort.** `Clean` runs `PrioritySort` (`value/shared/union_priority_sort.mjs`) first. A Record with a non-standard pattern is rebuilt through `Pattern.key_type`, which ports `TemplateLiteralDecodeUnsafe`, so `^[a-c]$` becomes an object keyed `[a-c]`, exactly like TypeBox.
- **Regular expressions.** Patterns run through `JsRegex.translate`, because Crystal's PCRE2 always uses UTF and UCP. `\d`, `\w`, `\s`, `\b` and `.` are rewritten to their JavaScript meanings. Pass `"u"` where upstream uses the `u` flag.
- **Compiler quirks.**
  - A method that captures a block and also contains a `-> {}` literal can fail with "read before assignment". Keep the proc literal in a separate method.
  - `record` is a macro; do not name variables `record`.
- **Differential testing.** Behavior was verified against TypeBox 1.3.27 under Node with two generated corpora:
  - **Builder corpus.** Random builder trees were compared for schema JSON, hidden flags, `Check`, `Errors` (exact order and messages), `Default`, `Clean` and `Clone`.
  - **Raw-schema corpus.** Random JSON Schema documents were compared for `Check` and `Errors`, covering every keyword the engine handles.

  Re-run both after touching the engine, the builders, `Evaluate` or `Value`. The remaining known differences are listed in `README.md`.
