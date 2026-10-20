# typebox

A Crystal port of the parts of [TypeBox](https://github.com/sinclairzx81/typebox) 1.3.27 that
[pi-chord](https://github.com/earendil-works/pi/tree/main/packages/chord) relies on: the type
builders, which emit the same JSON Schema as TypeBox, and the `Value` functions `Check`, `Errors`,
`Default`, `Clean` and `Clone`.

The goal is wire compatibility with TypeScript hosts. A schema built here serializes to the same
JSON as the matching TypeBox call. Every `Value` function gives the same result as TypeBox on the
same schema and value, error messages included.

## Installation

```yaml
dependencies:
  typebox:
    github: shpeckman/typebox
```

```crystal
require "typebox"
```

## Building schemas

`TypeBox::Type` mirrors `Type.*` from TypeBox, with snake_case method names. Options are given as
named arguments using their JSON Schema spelling. A `Schema` value given as an option, such as
`additionalProperties`, is embedded as a child schema.

```crystal
T = TypeBox::Type

User = T.object({
  id:    T.integer(minimum: 1),
  name:  T.string(minLength: 1),
  email: T.optional(T.string(format: "email")),
  role:  T.union([T.literal("admin"), T.literal("member")]),
  tags:  T.immutable(T.array(T.string, uniqueItems: true)),
}, additionalProperties: false)

User.to_json
```

| Builder                                                    | JSON Schema                                                                |
|------------------------------------------------------------|----------------------------------------------------------------------------|
| `T.string`, `T.number`, `T.integer`, `T.boolean`, `T.null` | `{"type": ...}`                                                            |
| `T.void`, `T.undefined`                                    | `{"type":"void"}`, `{"type":"undefined"}`                                  |
| `T.any`, `T.unknown`                                       | `{}`                                                                       |
| `T.never`                                                  | `{"not":{}}`                                                               |
| `T.literal(value)`                                         | `{"type": ..., "const": value}`                                            |
| `T.enum(values)`                                           | `{"enum": [...]}`                                                          |
| `T.array(items)`                                           | `{"type":"array","items": ...}`                                            |
| `T.tuple(items)`                                           | `{"type":"array","additionalItems":false,"items":[...],"minItems":n}`      |
| `T.object(properties)`                                     | `{"type":"object","required":[...],"properties":{...}}`                    |
| `T.record(key, value)`                                     | `patternProperties`, or an object when the key is a finite set of literals |
| `T.union(types)`                                           | `{"anyOf": [...]}`                                                         |
| `T.intersect(types)`                                       | `{"allOf": [...]}`                                                         |
| `T.function(parameters, return_type)`                      | `{"type":"function","parameters":[...],"returnType": ...}`                 |
| `T.unsafe(json)`                                           | the given JSON, marked unsafe                                              |

Modifiers:

- `T.optional` and `T.readonly` mark properties.
- `T.immutable` marks arrays and tuples.
- `T.with(schema, **options)` adds or replaces options on an existing schema.
- `T.evaluate(schema)` reduces unions, intersections and enums the same way TypeBox's `Type.Evaluate` does.

Object properties are given as a `NamedTuple` or a `Hash(String, Schema)`. Keys follow JavaScript
property order: integer-like keys come first, in ascending order.

`T.record` handles the key kinds below. Any other key gives an empty object.

| Key                              | Result                    |
|----------------------------------|---------------------------|
| `String`                         | `^.*$`                    |
| `String` with a `pattern` option | that pattern              |
| `Number`                         | number pattern            |
| `Integer`                        | integer pattern           |
| `Any`                            | `^.*$`                    |
| `Boolean`                        | `true`/`false` object     |
| `Literal`                        | single-key object         |
| `Enum`                           | evaluated to its literals |
| `Union`                          | evaluated to its members  |
| `Intersect`                      | evaluated first           |

`Schema` keeps TypeBox's hidden markers as properties rather than JSON keys:

- `kind` (`"String"`, `"Object"`, …)
- `optional?`
- `readonly?`
- `immutable?`
- `unsafe?`

`Schema.from_json(json)` wraps any JSON Schema document. A schema built this way has no kind.

## Values

Values are `JSON::Any?`. `nil` stands for JavaScript `undefined`, and `JSON::Any.new(nil)` is
`null`.

```crystal
value = JSON.parse(%({"id": 1, "name": "", "role": "owner", "tags": [], "extra": true}))

TypeBox::Value.check(User, value)
TypeBox::Value.errors(User, value).each { |error| puts "#{error.instance_path} #{error.message}" }
TypeBox::Value.clean(User, TypeBox::Value.clone(value))
TypeBox::Value.default(T.object({n: T.number(default: 0)}), JSON.parse("{}"))
```

| Function                       | Behavior                                                                                        |
|--------------------------------|-------------------------------------------------------------------------------------------------|
| `Value.check(schema, value)`   | `true` when the value matches the schema                                                        |
| `Value.errors(schema, value)`  | `Array(ValidationError)` with `keyword`, `schema_path`, `instance_path`, `params` and `message` |
| `Value.default(schema, value)` | fills missing values from `default` annotations, mutating the value                             |
| `Value.clean(schema, value)`   | removes properties and elements the schema does not describe, mutating the value                |
| `Value.clone(value)`           | deep copy that drops `__proto__`, `constructor` and `prototype` keys                            |

Every function takes either a `Schema` or a plain `JSON::Any` schema. `ValidationError#to_json`
writes the TypeBox field names (`schemaPath`, `instancePath`).

## Formats

`TypeBox::Format` holds the string formats used by the `format` keyword. It starts with TypeBox's
registry:

- `date`, `time`, `date-time`, `duration`
- `email`, `idn-email`
- `hostname`, `idn-hostname`
- `ipv4`, `ipv6`
- `uri`, `uri-reference`, `uri-template`
- `iri`, `iri-reference`
- `json-pointer`, `json-pointer-uri-fragment`, `relative-json-pointer`
- `regex`
- `url`
- `uuid`

An unknown format always passes.

```crystal
TypeBox::Format.set("even-length") { |value| value.size.even? }
TypeBox::Format.reset
```

## Settings and locale

```crystal
TypeBox::Settings.max_errors = 20
TypeBox::Settings.exact_optional_property_types = true
TypeBox::Settings.union_priority_sort = false
TypeBox::Settings.reset

TypeBox::Locale.set(TypeBox::LocaleFunction.new { |error| "#{error.keyword} failed" })
TypeBox::Locale.reset
```

## Scope and known differences

The port does not include:

- `$id`, `$anchor`, `$dynamicAnchor` and remote references; only `#` fragment references resolve, the way TypeBox resolves them inside a single document
- `Type.Ref`, `Type.Cyclic` and `Type.Refine`
- template literals, BigInt, Symbol and Constructor types
- mapped and utility types (`Partial`, `Pick`, `Omit`, `KeyOf`, …)
- codecs
- `Value.Convert`, `Value.Create`, `Value.Parse` and `Value.Repair`
- the JIT compiler

Behavior that differs from TypeBox:

- **Inherited keys.** `required` and `properties` look only at a value's own keys. TypeBox's `in` operator also sees keys inherited from `Object.prototype`, such as `toString`.
- **URL formats.** `url`, `iri` and `iri-reference` approximate WHATWG `URL.canParse`. Special schemes must have a valid host and port.
- **Tuple defaults.** `Value.default` fills missing tuple slots with `null` where TypeBox writes `undefined`. JSON output is the same. However, a union of tuples whose element accepts `undefined`, or rejects `null`, can pick a different variant.
- **Records and objects over arrays.** `Value.default` and `Value.clean` on a Record or Object schema applied to an array touch only index keys. TypeBox also visits `length`, and sometimes throws because of it.

## Development

```sh
crystal spec
crystal tool format --check
ameba
```

## License

MIT. Portions are ported from TypeBox, Copyright (c) 2017-2026 Haydn Paterson.
