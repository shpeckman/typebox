# src/typebox/type.cr
module TypeBox::Type
  INTEGER_PATTERN = "-?(?:0|[1-9][0-9]*)"
  NUMBER_PATTERN  = "-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?"
  STRING_PATTERN  = ".*"
  INTEGER_KEY     = "^#{INTEGER_PATTERN}$"
  NUMBER_KEY      = "^#{NUMBER_PATTERN}$"
  STRING_KEY      = "^#{STRING_PATTERN}$"

  alias LiteralValue = String | Bool | Int::Signed | Int::Unsigned | Float32 | Float64

  def self.create(kind : String?, structural : Coerce::Options, options : Coerce::Options = Coerce::Options.new) : Schema
    Schema.new(kind, structural).with_entries(options)
  end

  def self.string(**options) : Schema
    create("String", [{"type", JSON::Any.new("string").as(Entry)}], Coerce.options(options))
  end

  def self.number(**options) : Schema
    create("Number", [{"type", JSON::Any.new("number").as(Entry)}], Coerce.options(options))
  end

  def self.integer(**options) : Schema
    create("Integer", [{"type", JSON::Any.new("integer").as(Entry)}], Coerce.options(options))
  end

  def self.boolean(**options) : Schema
    create("Boolean", [{"type", JSON::Any.new("boolean").as(Entry)}], Coerce.options(options))
  end

  def self.null(**options) : Schema
    create("Null", [{"type", JSON::Any.new("null").as(Entry)}], Coerce.options(options))
  end

  def self.void(**options) : Schema
    create("Void", [{"type", JSON::Any.new("void").as(Entry)}], Coerce.options(options))
  end

  def self.undefined(**options) : Schema
    create("Undefined", [{"type", JSON::Any.new("undefined").as(Entry)}], Coerce.options(options))
  end

  def self.any(**options) : Schema
    create("Any", Coerce::Options.new, Coerce.options(options))
  end

  def self.unknown(**options) : Schema
    create("Unknown", Coerce::Options.new, Coerce.options(options))
  end

  def self.never(**options) : Schema
    create("Never", [{"not", JSON::Any.new({} of String => JSON::Any).as(Entry)}], Coerce.options(options))
  end

  def self.literal(value : LiteralValue | JSON::Any, **options) : Schema
    literal_from(Coerce.any(value), Coerce.options(options))
  end

  def self.literal_from(value : JSON::Any, options : Coerce::Options = Coerce::Options.new) : Schema
    name = case value.raw
           when Bool           then "boolean"
           when Int64, Float64 then "number"
           when String         then "string"
           else                     raise ArgumentError.new("Invalid Literal value")
           end
    create("Literal", [{"type", JSON::Any.new(name).as(Entry)}, {"const", value.as(Entry)}], options)
  end

  def self.enum(values : Enumerable, **options) : Schema
    create("Enum", [{"enum", Coerce.any(values.to_a).as(Entry)}], Coerce.options(options))
  end

  def self.array(items : Schema, **options) : Schema
    create("Array", [{"type", JSON::Any.new("array").as(Entry)}, {"items", items.as(Entry)}], Coerce.options(options))
  end

  def self.tuple(items : Array(Schema), **options) : Schema
    tuple_from(items, Coerce.options(options))
  end

  def self.tuple_from(items : Array(Schema), options : Coerce::Options = Coerce::Options.new) : Schema
    create("Tuple", [
      {"type", JSON::Any.new("array").as(Entry)},
      {"additionalItems", JSON::Any.new(false).as(Entry)},
      {"items", items.as(Entry)},
      {"minItems", JSON::Any.new(items.size.to_i64).as(Entry)},
    ], options)
  end

  def self.object(properties : NamedTuple | Hash, **options) : Schema
    object_from(Coerce.properties(properties), Coerce.options(options))
  end

  def self.object(**options) : Schema
    object_from({} of String => Schema, Coerce.options(options))
  end

  def self.object_from(properties : Hash(String, Schema), options : Coerce::Options = Coerce::Options.new) : Schema
    ordered = Coerce.ordered(properties)
    required = ordered.reject { |_, schema| schema.optional? }.keys
    structural = [{"type", JSON::Any.new("object").as(Entry)}] of Tuple(String, Entry)
    structural << {"required", Coerce.any(required).as(Entry)} unless required.empty?
    structural << {"properties", ordered.as(Entry)}
    create("Object", structural, options)
  end

  def self.union(types : Array(Schema), **options) : Schema
    union_from(types, Coerce.options(options))
  end

  def self.union_from(types : Array(Schema), options : Coerce::Options = Coerce::Options.new) : Schema
    create("Union", [{"anyOf", types.as(Entry)}], options)
  end

  def self.intersect(types : Array(Schema), **options) : Schema
    intersect_from(types, Coerce.options(options))
  end

  def self.intersect_from(types : Array(Schema), options : Coerce::Options = Coerce::Options.new) : Schema
    create("Intersect", [{"allOf", types.as(Entry)}], options)
  end

  def self.function(parameters : Array(Schema), return_type : Schema, **options) : Schema
    create("Function", [
      {"type", JSON::Any.new("function").as(Entry)},
      {"parameters", parameters.as(Entry)},
      {"returnType", return_type.as(Entry)},
    ], Coerce.options(options))
  end

  def self.record(key : Schema, value : Schema, **options) : Schema
    Records.from_key(key, value).with_entries(Coerce.options(options))
  end

  def self.record_pattern(pattern : String, value : Schema) : Schema
    Records.create(pattern, value)
  end

  def self.unsafe(schema : Schema) : Schema
    schema.with_flags(unsafe: true)
  end

  def self.unsafe(schema : JSON::Any | Hash | NamedTuple) : Schema
    Schema.from_json(Coerce.any(schema)).with_flags(unsafe: true)
  end

  def self.optional(schema : Schema) : Schema
    schema.with_flags(optional: true)
  end

  def self.readonly(schema : Schema) : Schema
    schema.with_flags(readonly: true)
  end

  def self.immutable(schema : Schema) : Schema
    schema.with_flags(immutable: true)
  end

  def self.with(schema : Schema, **options) : Schema
    schema.with_entries(Coerce.options(options))
  end

  def self.with(schema : Schema, options : Hash) : Schema
    schema.with_entries(Coerce.options(options))
  end

  def self.evaluate(schema : Schema, **options) : Schema
    Evaluate.type(schema).with_entries(Coerce.options(options))
  end

  module Records
    def self.create(pattern : String, value : Schema) : Schema
      Type.create("Record", [
        {"type", JSON::Any.new("object").as(Entry)},
        {"patternProperties", {pattern => value}.as(Entry)},
      ])
    end

    def self.pattern(schema : Schema) : String
      schema.schema_map?("patternProperties").try(&.keys.first?) || STRING_KEY
    end

    def self.value(schema : Schema) : Schema
      schema.schema_map?("patternProperties").try(&.values.first?) || Type.unknown
    end

    def self.from_key(key : Schema, value : Schema) : Schema
      case key.kind
      when "Any"       then create(STRING_KEY, value)
      when "Boolean"   then Type.object_from({"true" => value, "false" => value})
      when "Enum"      then from_key(Evaluate.enum(key.value?("enum").not_nil!.as_a), value)
      when "Integer"   then create(INTEGER_KEY, value)
      when "Intersect" then from_key(Evaluate.intersect(key.schemas?("allOf") || [] of Schema), value)
      when "Literal"   then from_literal(key.value?("const").not_nil!, value)
      when "Number"    then create(NUMBER_KEY, value)
      when "Union"     then from_union(key.schemas?("anyOf") || [] of Schema, value)
      when "String"    then from_string(key, value)
      else                  Type.object_from({} of String => Schema)
      end
    end

    private def self.from_literal(constant : JSON::Any, value : Schema) : Schema
      case raw = constant.raw
      when String         then Type.object_from({raw => value})
      when Int64, Float64 then Type.object_from({Guard.js_number(raw) => value})
      when Bool           then Type.object_from({raw.to_s => value})
      else                     Type.object_from({} of String => Schema)
      end
    end

    private def self.from_string(key : Schema, value : Schema) : Schema
      pattern = key["pattern"]?
      pattern.is_a?(JSON::Any) && (text = pattern.as_s?) ? create(text, value) : create(STRING_KEY, value)
    end

    private def self.from_union(types : Array(Schema), value : Schema) : Schema
      flattened = Evaluate.flatten(types)
      return create(STRING_KEY, value) if flattened.any? { |type| type.kind?("String") || type.kind?("Number") || type.kind?("Integer") }
      properties = {} of String => Schema
      flattened.each do |type|
        next unless type.kind?("Literal")
        constant = type.value?("const").not_nil!
        case raw = constant.raw
        when String         then properties[raw] = value
        when Int64, Float64 then properties[Guard.js_number(raw)] = value
        end
      end
      Type.object_from(properties)
    end
  end
end
