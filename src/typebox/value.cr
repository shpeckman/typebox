# src/typebox/value.cr
module TypeBox::Value
  def self.check(schema : Schema | JSON::Any, value : JSON::Any?) : Bool
    Engine::Validator.new(json(schema)).check(value)
  end

  def self.errors(schema : Schema | JSON::Any, value : JSON::Any?) : Array(ValidationError)
    Engine::Validator.new(json(schema)).errors(value)[1]
  end

  private def self.json(schema : Schema | JSON::Any) : JSON::Any
    schema.is_a?(Schema) ? schema.json : schema
  end

  def self.clone(value : JSON::Any?) : JSON::Any?
    value.try { |present| clone_value(present) }
  end

  def self.default(schema : Schema | JSON::Any, value : JSON::Any?) : JSON::Any?
    Defaults.from_type(Schema.coerce(schema), value)
  end

  def self.clean(schema : Schema | JSON::Any, value : JSON::Any?) : JSON::Any?
    type = Schema.coerce(schema)
    Cleaner.from_type(Settings.union_priority_sort? ? PrioritySort.from_type(type) : type, value)
  end

  private def self.clone_value(value : JSON::Any) : JSON::Any
    case raw = value.raw
    when Array
      JSON::Any.new(raw.map { |item| clone_value(item) })
    when Hash
      result = {} of String => JSON::Any
      raw.each { |key, item| result[key] = clone_value(item) unless Guard::UNSAFE_KEYS.includes?(key) }
      JSON::Any.new(result)
    else
      value
    end
  end

  protected def self.assign(target : JSON::Any, key : String, item : JSON::Any?) : Nil
    case raw = target.raw
    when Hash
      item.nil? ? raw.delete(key) : (raw[key] = item)
    when Array
      return unless Guard.index_key?(key)
      index = key.to_i
      while raw.size <= index
        raw << JSON::Any.new(nil)
      end
      raw[index] = item || JSON::Any.new(nil)
    end
  end

  protected def self.remove(target : JSON::Any, key : String) : Nil
    case raw = target.raw
    when Hash  then raw.delete(key)
    when Array then raw[key.to_i] = JSON::Any.new(nil) if Guard.index_key?(key) && key.to_u64 < raw.size
    end
  end

  protected def self.entry_any(entry : Entry?) : JSON::Any?
    entry.try { |present| Schema.entry_json(present) }
  end

  module Defaults
    def self.from_type(type : Schema, value : JSON::Any?) : JSON::Any?
      defaulted = type.has_key?("default") && value.nil? ? Value.clone(Value.entry_any(type["default"]?)) : value
      case type.kind
      when "Array"     then from_array(type, defaulted)
      when "Intersect" then from_type(Evaluate.type(type), defaulted)
      when "Object"    then from_object(type, defaulted)
      when "Record"    then from_record(type, defaulted)
      when "Tuple"     then from_tuple(type, defaulted)
      when "Union"     then from_union(type, defaulted)
      else                  defaulted
      end
    end

    private def self.from_array(type : Schema, value : JSON::Any?) : JSON::Any?
      return value unless (list = value.try(&.as_a?)) && (items = type.schema?("items"))
      list.each_index { |index| list[index] = from_type(items, list[index]) || JSON::Any.new(nil) }
      value
    end

    private def self.from_object(type : Schema, value : JSON::Any?) : JSON::Any?
      return value unless value && Guard.object?(value)
      properties = type.schema_map?("properties") || {} of String => Schema
      known = Guard.keys(JSON::Any.new(properties.transform_values(&.json)))
      known.each do |key|
        property = properties[key]
        result = from_type(property, Guard.get(value, key))
        next if result.nil? && (property.optional? || !property.has_key?("default"))
        Value.assign(value, key, result)
      end
      additional = type.schema?("additionalProperties")
      return value if additional.nil? || Guard.boolean?(Value.entry_any(type["additionalProperties"]?))
      Guard.keys(value).each do |key|
        next if known.includes?(key)
        Value.assign(value, key, from_type(additional, Guard.get(value, key)))
      end
      value
    end

    private def self.from_record(type : Schema, value : JSON::Any?) : JSON::Any?
      return value unless value && Guard.object?(value)
      pattern = Type::Records.pattern(type)
      record_value = Type::Records.value(type)
      Guard.keys(value).each do |key|
        next unless JsRegex.test(pattern, key) && record_value.has_key?("default")
        Value.assign(value, key, from_type(record_value, Guard.get(value, key)))
      end
      return value unless additional = type.schema?("additionalProperties")
      Guard.keys(value).each do |key|
        next if JsRegex.test(pattern, key)
        Value.assign(value, key, from_type(additional, Guard.get(value, key)))
      end
      value
    end

    private def self.from_tuple(type : Schema, value : JSON::Any?) : JSON::Any?
      return value unless list = value.try(&.as_a?)
      (type.schemas?("items") || [] of Schema).each_with_index do |item, index|
        Value.assign(value.not_nil!, index.to_s, from_type(item, list[index]?))
      end
      value
    end

    private def self.from_union(type : Schema, value : JSON::Any?) : JSON::Any?
      (type.schemas?("anyOf") || [] of Schema).each do |variant|
        result = from_type(variant, Value.clone(value))
        return result if Value.check(variant, result)
      end
      value
    end
  end

  module Cleaner
    def self.from_type(type : Schema, value : JSON::Any?) : JSON::Any?
      case type.kind
      when "Array"     then from_array(type, value)
      when "Intersect" then from_type(evaluate_intersection(type), value)
      when "Object"    then from_object(type, value)
      when "Record"    then from_record(type, value)
      when "Tuple"     then from_tuple(type, value)
      when "Union"     then from_union(type, value)
      else                  value
      end
    end

    private def self.evaluate_intersection(type : Schema) : Schema
      evaluated = Evaluate.type(type)
      return evaluated unless evaluated.kind?("Object")
      unevaluated = type["unevaluatedProperties"]?
      unevaluated ? evaluated.with_entries([{"additionalProperties", unevaluated}]) : evaluated
    end

    private def self.from_array(type : Schema, value : JSON::Any?) : JSON::Any?
      return value unless (list = value.try(&.as_a?)) && (items = type.schema?("items"))
      JSON::Any.new(list.map { |item| from_type(items, item) || JSON::Any.new(nil) })
    end

    private def self.unknown_check(type : Schema, item : JSON::Any?) : Bool
      additional = type["additionalProperties"]?
      case additional
      when JSON::Any
        additional.raw == true || (additional.raw.is_a?(Hash) && Value.check(additional, item))
      when Schema
        Value.check(additional, item)
      else
        false
      end
    end

    private def self.additional(type : Schema) : Schema
      type.schema?("additionalProperties") || Type.unknown
    end

    private def self.from_object(type : Schema, value : JSON::Any?) : JSON::Any?
      return value unless value && Guard.object_not_array?(value)
      properties = type.schema_map?("properties") || {} of String => Schema
      Guard.keys(value).each do |key|
        item = Guard.get(value, key)
        if property = properties[key]?
          Value.assign(value, key, from_type(property, item))
        elsif unknown_check(type, item)
          Value.assign(value, key, from_type(additional(type), item))
        else
          Value.remove(value, key)
        end
      end
      value
    end

    private def self.from_record(type : Schema, value : JSON::Any?) : JSON::Any?
      return value unless value && Guard.object?(value)
      pattern = Type::Records.pattern(type)
      record_value = Type::Records.value(type)
      Guard.keys(value).each do |key|
        item = Guard.get(value, key)
        if JsRegex.test(pattern, key)
          Value.assign(value, key, from_type(record_value, item))
        elsif unknown_check(type, item)
          Value.assign(value, key, from_type(additional(type), item))
        else
          Value.remove(value, key)
        end
      end
      value
    end

    private def self.from_tuple(type : Schema, value : JSON::Any?) : JSON::Any?
      return value unless list = value.try(&.as_a?)
      items = type.schemas?("items") || [] of Schema
      length = Math.min(list.size, items.size)
      length.times { |index| list[index] = from_type(items[index], list[index]) || JSON::Any.new(nil) }
      list.size > length ? JSON::Any.new(list[0, length]) : value
    end

    private def self.from_union(type : Schema, value : JSON::Any?) : JSON::Any?
      (type.schemas?("anyOf") || [] of Schema).each do |variant|
        result = from_type(variant, Value.clone(value))
        return result if Value.check(variant, result)
      end
      value
    end
  end

  module PrioritySort
    def self.from_type(type : Schema) : Schema
      case type.kind
      when "Array"
        replace(type, "items", type.schema?("items").try { |items| from_type(items) })
      when "Intersect"
        replace(type, "allOf", type.schemas?("allOf").try(&.map { |item| from_type(item) }))
      when "Union"
        replace(type, "anyOf", type.schemas?("anyOf").try { |items| Evaluate.priority(items).map { |item| from_type(item) } })
      when "Object"
        replace(type, "properties", type.schema_map?("properties").try(&.transform_values { |item| from_type(item) }))
      when "Record"
        from_record(type)
      when "Tuple"
        replace(type, "items", type.schemas?("items").try(&.map { |item| from_type(item) }))
      else
        type
      end
    end

    private def self.from_record(type : Schema) : Schema
      pattern = Type::Records.pattern(type)
      value = from_type(Type::Records.value(type))
      rebuilt = Pattern.key_type(pattern).try { |key| Type::Records.from_key(key, value) } || Type::Records.create(pattern, value)
      missing = type.entries.reject { |(key, _)| rebuilt.has_key?(key) }
      rebuilt.with_entries(missing).with_flags(type.optional?, type.readonly?, type.immutable?, type.unsafe?)
    end

    private def self.replace(type : Schema, key : String, child : Child?) : Schema
      child ? type.with_entries([{key, child.as(Entry)}]) : type
    end
  end
end
