# src/typebox/engine.cr
module TypeBox::Engine
  class Frame
    getter indices = ::Set(Int32).new
    getter keys = ::Set(String).new
  end

  class CheckContext
    @frames = [Frame.new]

    def push : Bool
      @frames << Frame.new
      true
    end

    def pop : Bool
      @frames.pop
      true
    end

    def add_index(index : Int32) : Bool
      @frames.last.indices << index
      true
    end

    def add_key(key : String) : Bool
      @frames.last.keys << key
      true
    end

    def indices : ::Set(Int32)
      @frames.last.indices
    end

    def keys : ::Set(String)
      @frames.last.keys
    end

    def merge(results : Array(CheckContext)) : Bool
      results.each do |context|
        indices.concat(context.indices)
        keys.concat(context.keys)
      end
      true
    end
  end

  class ErrorContext < CheckContext
    getter errors = [] of ValidationError

    def at_capacity? : Bool
      @errors.size >= Settings.max_errors
    end

    def add_error(error : ValidationError) : Bool
      @errors << error unless at_capacity?
      false
    end

    def add_error(keyword : String, schema_path : String, instance_path : String, params : JSON::Any) : Bool
      add_error(ValidationError.new(keyword, schema_path, instance_path, params))
    end
  end

  class Validator
    def initialize(@root : JSON::Any); end

    def check(value : JSON::Any?) : Bool
      check_schema(CheckContext.new, @root, value)
    end

    def errors(value : JSON::Any?) : Tuple(Bool, Array(ValidationError))
      context = ErrorContext.new
      result = error_schema(context, "#", "", @root, value)
      locale = Locale.get
      {result, context.errors.map { |error| error.with_message(locale.call(error)) }}
    end

    def check_schema(context : CheckContext, schema : JSON::Any, value : JSON::Any?) : Bool
      raw = schema.raw
      return raw if raw.is_a?(Bool)
      return true unless raw.is_a?(Hash)
      s = raw
      (!type?(s) || check_type(s, value)) &&
        (!Guard.object_not_array?(value) || ((!required?(s) || check_required(s, value.not_nil!)) &&
          (!schema_key?(s, "additionalProperties") || check_additional_properties(context, s, value.not_nil!)) &&
          (!dependencies?(s) || check_dependencies(context, s, value.not_nil!)) &&
          (!dependent_required?(s) || check_dependent_required(s, value.not_nil!)) &&
          (!schema_map?(s, "dependentSchemas") || check_dependent_schemas(context, s, value.not_nil!)) &&
          (!schema_map?(s, "patternProperties") || check_pattern_properties(context, s, value.not_nil!)) &&
          (!schema_map?(s, "properties") || check_properties(context, s, value.not_nil!)) &&
          (!property_names?(s) || check_property_names(context, s, value.not_nil!)) &&
          (!number_key?(s, "minProperties") || Guard.keys(value.not_nil!).size >= num(s, "minProperties")) &&
          (!number_key?(s, "maxProperties") || Guard.keys(value.not_nil!).size <= num(s, "maxProperties")))) &&
        (!Guard.array?(value) || ((!additional_items?(s) || check_additional_items(context, s, items(value))) &&
          (!contains?(s) || check_contains(context, s, items(value))) &&
          (!items?(s) || check_items(context, s, items(value))) &&
          (!number_key?(s, "maxContains") || check_max_contains(context, s, items(value))) &&
          (!number_key?(s, "maxItems") || items(value).size <= num(s, "maxItems")) &&
          (!number_key?(s, "minContains") || check_min_contains(context, s, items(value))) &&
          (!number_key?(s, "minItems") || items(value).size >= num(s, "minItems")) &&
          (!schema_list?(s, "prefixItems") || check_prefix_items(context, s, items(value))) &&
          (!unique_items?(s) || duplicates(s, items(value)).empty?))) &&
        (!Guard.string?(value) || ((!number_key?(s, "maxLength") || Guard.max_length?(value.not_nil!.as_s, num(s, "maxLength"))) &&
          (!number_key?(s, "minLength") || Guard.min_length?(value.not_nil!.as_s, num(s, "minLength"))) &&
          (!string_key?(s, "format") || Format.test(s["format"].as_s, value.not_nil!.as_s)) &&
          (!string_key?(s, "pattern") || JsRegex.test(s["pattern"].as_s, value.not_nil!.as_s, "u")))) &&
        (!Guard.number?(value) || ((!number_key?(s, "exclusiveMaximum") || Guard.to_f(value.not_nil!) < num(s, "exclusiveMaximum")) &&
          (!number_key?(s, "exclusiveMinimum") || Guard.to_f(value.not_nil!) > num(s, "exclusiveMinimum")) &&
          (!number_key?(s, "maximum") || Guard.to_f(value.not_nil!) <= num(s, "maximum")) &&
          (!number_key?(s, "minimum") || Guard.to_f(value.not_nil!) >= num(s, "minimum")) &&
          (!number_key?(s, "multipleOf") || Guard.multiple_of?(value.not_nil!, s["multipleOf"])))) &&
        (!string_key?(s, "$ref") || check_ref(context, s, value)) &&
        (!string_key?(s, "$recursiveRef") || check_schema(context, JSON::Any.new(false), value)) &&
        (!string_key?(s, "$dynamicRef") || check_schema(context, JSON::Any.new(false), value)) &&
        (!s.has_key?("const") || check_const(s, value)) &&
        (!enum?(s) || check_enum(s, value)) &&
        (!schema_key?(s, "if") || check_if(context, s, value)) &&
        (!schema_key?(s, "not") || check_not(context, s, value)) &&
        (!schema_list?(s, "allOf") || check_all_of(context, s, value)) &&
        (!schema_list?(s, "anyOf") || check_any_of(context, s, value)) &&
        (!schema_list?(s, "oneOf") || check_one_of(context, s, value)) &&
        (!schema_key?(s, "unevaluatedItems") || !Guard.array?(value) || check_unevaluated_items(context, s, items(value))) &&
        (!schema_key?(s, "unevaluatedProperties") || !Guard.object?(value) || check_unevaluated_properties(context, s, value.not_nil!))
    end

    def error_schema(context : ErrorContext, schema_path : String, instance_path : String, schema : JSON::Any, value : JSON::Any?) : Bool
      return false if context.at_capacity?
      raw = schema.raw
      if raw.is_a?(Bool)
        return raw || context.add_error("boolean", schema_path, instance_path, empty)
      end
      return true unless raw.is_a?(Hash)
      s = raw
      results = [] of Bool
      results << (!type?(s) || error_type(context, schema_path, instance_path, s, value))
      if Guard.object_not_array?(value)
        object = value.not_nil!
        group = [] of Bool
        group << (!required?(s) || error_required(context, schema_path, instance_path, s, object))
        group << (!schema_key?(s, "additionalProperties") || error_additional_properties(context, schema_path, instance_path, s, object))
        group << (!dependencies?(s) || error_dependencies(context, schema_path, instance_path, s, object))
        group << (!dependent_required?(s) || error_dependent_required(context, schema_path, instance_path, s, object))
        group << (!schema_map?(s, "dependentSchemas") || error_dependent_schemas(context, schema_path, instance_path, s, object))
        group << (!schema_map?(s, "patternProperties") || error_pattern_properties(context, schema_path, instance_path, s, object))
        group << (!schema_map?(s, "properties") || error_properties(context, schema_path, instance_path, s, object))
        group << (!property_names?(s) || error_property_names(context, schema_path, instance_path, s, object))
        group << (!number_key?(s, "minProperties") || Guard.keys(object).size >= num(s, "minProperties") || limit_error(context, "minProperties", schema_path, instance_path, s))
        group << (!number_key?(s, "maxProperties") || Guard.keys(object).size <= num(s, "maxProperties") || limit_error(context, "maxProperties", schema_path, instance_path, s))
        results << group.all?
      end
      if Guard.array?(value)
        list = items(value)
        group = [] of Bool
        group << (!additional_items?(s) || error_additional_items(context, schema_path, instance_path, s, list))
        group << (!contains?(s) || check_contains(context, s, list) || context.add_error("contains", schema_path, instance_path, params({"minContains" => JSON::Any.new(1_i64)})))
        group << (!items?(s) || error_items(context, schema_path, instance_path, s, list))
        group << (!number_key?(s, "maxContains") || error_max_contains(context, schema_path, instance_path, s, list))
        group << (!number_key?(s, "maxItems") || list.size <= num(s, "maxItems") || limit_error(context, "maxItems", schema_path, instance_path, s))
        group << (!number_key?(s, "minContains") || check_min_contains(context, s, list) || context.add_error("contains", schema_path, instance_path, params({"minContains" => s["minContains"]})))
        group << (!number_key?(s, "minItems") || list.size >= num(s, "minItems") || limit_error(context, "minItems", schema_path, instance_path, s))
        group << (!schema_list?(s, "prefixItems") || error_prefix_items(context, schema_path, instance_path, s, list))
        group << (!unique_items?(s) || error_unique_items(context, schema_path, instance_path, s, list))
        results << group.all?
      end
      if Guard.string?(value)
        text = value.not_nil!.as_s
        group = [] of Bool
        group << (!number_key?(s, "maxLength") || Guard.max_length?(text, num(s, "maxLength")) || limit_error(context, "maxLength", schema_path, instance_path, s))
        group << (!number_key?(s, "minLength") || Guard.min_length?(text, num(s, "minLength")) || limit_error(context, "minLength", schema_path, instance_path, s))
        group << (!string_key?(s, "format") || Format.test(s["format"].as_s, text) || context.add_error("format", schema_path, instance_path, params({"format" => s["format"]})))
        group << (!string_key?(s, "pattern") || JsRegex.test(s["pattern"].as_s, text, "u") || context.add_error("pattern", schema_path, instance_path, params({"pattern" => s["pattern"]})))
        results << group.all?
      end
      if Guard.number?(value)
        number = Guard.to_f(value.not_nil!)
        group = [] of Bool
        group << (!number_key?(s, "exclusiveMaximum") || number < num(s, "exclusiveMaximum") || comparison_error(context, "exclusiveMaximum", "<", schema_path, instance_path, s))
        group << (!number_key?(s, "exclusiveMinimum") || number > num(s, "exclusiveMinimum") || comparison_error(context, "exclusiveMinimum", ">", schema_path, instance_path, s))
        group << (!number_key?(s, "maximum") || number <= num(s, "maximum") || comparison_error(context, "maximum", "<=", schema_path, instance_path, s))
        group << (!number_key?(s, "minimum") || number >= num(s, "minimum") || comparison_error(context, "minimum", ">=", schema_path, instance_path, s))
        group << (!number_key?(s, "multipleOf") || Guard.multiple_of?(value.not_nil!, s["multipleOf"]) || context.add_error("multipleOf", schema_path, instance_path, params({"multipleOf" => s["multipleOf"]})))
        results << group.all?
      end
      results << (!string_key?(s, "$ref") || error_ref(context, instance_path, s, value))
      results << (!string_key?(s, "$recursiveRef") || error_schema(context, "#", instance_path, JSON::Any.new(false), value))
      results << (!string_key?(s, "$dynamicRef") || error_schema(context, "#", instance_path, JSON::Any.new(false), value))
      results << (!s.has_key?("const") || check_const(s, value) || context.add_error("const", schema_path, instance_path, params({"allowedValue" => s["const"]})))
      results << (!enum?(s) || check_enum(s, value) || context.add_error("enum", schema_path, instance_path, params({"allowedValues" => s["enum"]})))
      results << (!schema_key?(s, "if") || error_if(context, schema_path, instance_path, s, value))
      results << (!schema_key?(s, "not") || check_not(context, s, value) || context.add_error("not", schema_path, instance_path, empty))
      results << (!schema_list?(s, "allOf") || error_all_of(context, schema_path, instance_path, s, value))
      results << (!schema_list?(s, "anyOf") || error_any_of(context, schema_path, instance_path, s, value))
      results << (!schema_list?(s, "oneOf") || error_one_of(context, schema_path, instance_path, s, value))
      results << (!schema_key?(s, "unevaluatedItems") || !Guard.array?(value) || error_unevaluated_items(context, schema_path, instance_path, s, items(value)))
      results << (!schema_key?(s, "unevaluatedProperties") || !Guard.object?(value) || error_unevaluated_properties(context, schema_path, instance_path, s, value.not_nil!))
      results.all?
    end

    private def check_push(context : CheckContext, schema : JSON::Any, value : JSON::Any?) : Bool
      context.push && check_schema(context, schema, value) && context.pop
    end

    private def error_push(context : ErrorContext, schema_path : String, instance_path : String, schema : JSON::Any, value : JSON::Any?) : Bool
      context.push && error_schema(context, schema_path, instance_path, schema, value) && context.pop
    end

    private def items(value : JSON::Any?) : Array(JSON::Any)
      value.not_nil!.as_a
    end

    private def empty : JSON::Any
      JSON::Any.new({} of String => JSON::Any)
    end

    private def params(values : Hash(String, JSON::Any)) : JSON::Any
      JSON::Any.new(values)
    end

    private def strings(values : Enumerable(String)) : JSON::Any
      JSON::Any.new(values.map { |value| JSON::Any.new(value) }.to_a)
    end

    private def num(s : Hash(String, JSON::Any), key : String) : Float64
      Guard.to_f(s[key])
    end

    private def schema_like?(value : JSON::Any) : Bool
      value.raw.is_a?(Hash) || value.raw.is_a?(Bool)
    end

    private def schema_key?(s : Hash(String, JSON::Any), key : String) : Bool
      (value = s[key]?) ? schema_like?(value) : false
    end

    private def schema_list?(s : Hash(String, JSON::Any), key : String) : Bool
      (list = s[key]?.try(&.as_a?)) ? list.all? { |item| schema_like?(item) } : false
    end

    private def schema_map?(s : Hash(String, JSON::Any), key : String) : Bool
      (map = s[key]?.try(&.raw)) ? (map.is_a?(Hash) || map.is_a?(Array)) && (map.is_a?(Hash) ? map.values.all? { |item| schema_like?(item) } : map.all? { |item| schema_like?(item) }) : false
    end

    private def number_key?(s : Hash(String, JSON::Any), key : String) : Bool
      Guard.number?(s[key]?)
    end

    private def string_key?(s : Hash(String, JSON::Any), key : String) : Bool
      Guard.string?(s[key]?)
    end

    private def type?(s : Hash(String, JSON::Any)) : Bool
      return false unless type = s["type"]?
      Guard.string?(type) || (type.as_a?.try(&.all? { |item| Guard.string?(item) }) || false)
    end

    private def required?(s : Hash(String, JSON::Any)) : Bool
      s["required"]?.try(&.as_a?).try(&.all? { |item| Guard.string?(item) }) || false
    end

    private def enum?(s : Hash(String, JSON::Any)) : Bool
      Guard.array?(s["enum"]?)
    end

    private def items?(s : Hash(String, JSON::Any)) : Bool
      return false unless value = s["items"]?
      schema_like?(value) || (value.as_a?.try(&.all? { |item| schema_like?(item) }) || false)
    end

    private def sized_items?(s : Hash(String, JSON::Any)) : Bool
      items?(s) && Guard.array?(s["items"])
    end

    private def additional_items?(s : Hash(String, JSON::Any)) : Bool
      schema_key?(s, "additionalItems")
    end

    private def contains?(s : Hash(String, JSON::Any)) : Bool
      schema_key?(s, "contains")
    end

    private def unique_items?(s : Hash(String, JSON::Any)) : Bool
      Guard.boolean?(s["uniqueItems"]?)
    end

    private def property_names?(s : Hash(String, JSON::Any)) : Bool
      (value = s["propertyNames"]?) ? Guard.object?(value) || schema_like?(value) : false
    end

    private def dependencies?(s : Hash(String, JSON::Any)) : Bool
      return false unless map = s["dependencies"]?.try(&.as_h?)
      map.values.all? { |item| schema_like?(item) || (item.as_a?.try(&.all? { |entry| Guard.string?(entry) }) || false) }
    end

    private def dependent_required?(s : Hash(String, JSON::Any)) : Bool
      return false unless map = s["dependentRequired"]?.try(&.as_h?)
      map.values.all? { |item| item.as_a?.try(&.all? { |entry| Guard.string?(entry) }) || false }
    end

    private def entries(value : JSON::Any) : Array(Tuple(String, JSON::Any))
      Guard.keys(value).map { |key| {key, Guard.get(value, key).not_nil!} }
    end

    private def type_name?(name : String, value : JSON::Any?) : Bool
      case name
      when "object"                                      then Guard.object_not_array?(value)
      when "array"                                       then Guard.array?(value)
      when "boolean"                                     then Guard.boolean?(value)
      when "integer"                                     then Guard.integer?(value)
      when "number"                                      then Guard.number?(value)
      when "null"                                        then Guard.null?(value)
      when "string"                                      then Guard.string?(value)
      when "bigint", "constructor", "function", "symbol" then false
      when "undefined", "void"                           then value.nil?
      else                                                    true
      end
    end

    private def check_type(s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      type = s["type"]
      (list = type.as_a?) ? list.any? { |name| type_name?(name.as_s, value) } : type_name?(type.as_s, value)
    end

    private def error_type(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      check_type(s, value) || context.add_error("type", schema_path, instance_path, params({"type" => s["type"]}))
    end

    private def check_required(s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      s["required"].as_a.all? { |key| Guard.has_property_key?(value, key.as_s) }
    end

    private def error_required(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      missing = s["required"].as_a.map(&.as_s).reject { |key| Guard.has_property_key?(value, key) }
      missing.empty? || context.add_error("required", schema_path, instance_path, params({"requiredProperties" => strings(missing)}))
    end

    private def property_pattern(s : Hash(String, JSON::Any)) : String
      patterns = [] of String
      s["patternProperties"]?.try(&.as_h?).try { |map| patterns.concat(Guard.keys(JSON::Any.new(map))) }
      s["properties"]?.try(&.as_h?).try do |map|
        Guard.keys(JSON::Any.new(map)).each do |key|
          patterns << "^#{key.gsub(/[.*+?^${}()|\[\]\\]/) { |match| "\\#{match}" }}$"
        end
      end
      patterns.empty? ? "(?!)" : "(#{patterns.join('|')})"
    end

    private def check_additional_properties(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      pattern = property_pattern(s)
      Guard.keys(value).all? do |key|
        JsRegex.test(pattern, key, "u") || (check_push(context, s["additionalProperties"], Guard.get(value, key)) && context.add_key(key))
      end
    end

    private def error_additional_properties(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      pattern = property_pattern(s)
      additional = [] of String
      Guard.keys(value).each do |key|
        valid = JsRegex.test(pattern, key, "u") ||
                (error_push(context, "#{schema_path}/additionalProperties", "#{instance_path}/#{key}", s["additionalProperties"], Guard.get(value, key)) && context.add_key(key))
        additional << key unless valid
      end
      additional.empty? || context.add_error("additionalProperties", schema_path, instance_path, params({"additionalProperties" => strings(additional)}))
    end

    private def check_dependencies(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      return true if Guard.keys(value).empty?
      s["dependencies"].as_h.all? do |key, dependency|
        !Guard.has_property_key?(value, key) ||
          ((list = dependency.as_a?) ? list.all? { |name| Guard.has_property_key?(value, name.as_s) } : check_schema(context, dependency, value))
      end
    end

    private def error_dependencies(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      empty_value = Guard.keys(value).empty?
      results = s["dependencies"].as_h.map do |key, dependency|
        next true unless Guard.has_property_key?(value, key)
        if list = dependency.as_a?
          list.all? do |name|
            Guard.has_property_key?(value, name.as_s) ||
              context.add_error("dependencies", schema_path, instance_path, params({"property" => JSON::Any.new(key), "dependencies" => dependency}))
          end
        else
          error_schema(context, "#{schema_path}/dependencies/#{key}", instance_path, dependency, value)
        end
      end
      empty_value || results.all?
    end

    private def check_dependent_required(s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      return true if Guard.keys(value).empty?
      s["dependentRequired"].as_h.all? do |key, names|
        !Guard.has_property_key?(value, key) || names.as_a.all? { |name| Guard.has_property_key?(value, name.as_s) }
      end
    end

    private def error_dependent_required(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      empty_value = Guard.keys(value).empty?
      results = s["dependentRequired"].as_h.map do |key, names|
        next true unless Guard.has_property_key?(value, key)
        names.as_a.map do |name|
          Guard.has_property_key?(value, name.as_s) ||
            context.add_error("dependentRequired", schema_path, instance_path, params({"property" => JSON::Any.new(key), "dependencies" => names}))
        end.all?
      end
      empty_value || results.all?
    end

    private def check_dependent_schemas(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      return true if Guard.keys(value).empty?
      s["dependentSchemas"].as_h.all? { |key, dependency| !Guard.has_property_key?(value, key) || check_schema(context, dependency, value) }
    end

    private def error_dependent_schemas(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      empty_value = Guard.keys(value).empty?
      results = s["dependentSchemas"].as_h.map do |key, dependency|
        !Guard.has_property_key?(value, key) || error_schema(context, "#{schema_path}/dependentSchemas/#{key}", instance_path, dependency, value)
      end
      empty_value || results.all?
    end

    private def check_pattern_properties(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      map = s["patternProperties"]
      Guard.keys(map).all? do |pattern|
        entries(value).all? do |(key, item)|
          !JsRegex.test(pattern, key, "u") || (check_push(context, Guard.get(map, pattern).not_nil!, item) && context.add_key(key))
        end
      end
    end

    private def error_pattern_properties(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      map = s["patternProperties"]
      Guard.keys(map).map do |pattern|
        entries(value).map do |(key, item)|
          !JsRegex.test(pattern, key, "u") ||
            (error_push(context, "#{schema_path}/patternProperties/#{pattern}", "#{instance_path}/#{key}", Guard.get(map, pattern).not_nil!, item) && context.add_key(key))
        end.all?
      end.all?
    end

    private def exact_optional?(required : Array(String), key : String) : Bool
      required.includes?(key) || Settings.exact_optional_property_types?
    end

    private def required_keys(s : Hash(String, JSON::Any)) : Array(String)
      required?(s) ? s["required"].as_a.map(&.as_s) : [] of String
    end

    private def check_properties(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      required = required_keys(s)
      properties = s["properties"]
      Guard.keys(properties).all? do |key|
        present = Guard.has_property_key?(value, key)
        valid = !present || (check_push(context, Guard.get(properties, key).not_nil!, Guard.get(value, key)) && context.add_key(key))
        exact_optional?(required, key) ? valid : (Guard.get(value, key).nil? || valid)
      end
    end

    private def error_properties(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      required = required_keys(s)
      properties = s["properties"]
      Guard.keys(properties).map do |key|
        if !exact_optional?(required, key) && Guard.get(value, key).nil?
          true
        else
          !Guard.has_property_key?(value, key) ||
            (error_push(context, "#{schema_path}/properties/#{key}", "#{instance_path}/#{key}", Guard.get(properties, key).not_nil!, Guard.get(value, key)) && context.add_key(key))
        end
      end.all?
    end

    private def check_property_names(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      Guard.keys(value).all? { |key| check_schema(context, s["propertyNames"], JSON::Any.new(key)) }
    end

    private def error_property_names(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      invalid = Guard.keys(value).reject do |key|
        error_schema(context, "#{schema_path}/propertyNames", "#{instance_path}/#{key}", s["propertyNames"], JSON::Any.new(key))
      end
      invalid.empty? || context.add_error("propertyNames", schema_path, instance_path, params({"propertyNames" => strings(invalid)}))
    end

    private def check_additional_items(context : CheckContext, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      return true unless sized_items?(s)
      limit = s["items"].as_a.size
      value.each_with_index.all? { |(item, index)| index < limit || (check_push(context, s["additionalItems"], item) && context.add_index(index)) }
    end

    private def error_additional_items(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      return true unless sized_items?(s)
      limit = s["items"].as_a.size
      value.each_with_index.all? do |(item, index)|
        index < limit || (error_push(context, "#{schema_path}/additionalItems", "#{instance_path}/#{index}", s["additionalItems"], item) && context.add_index(index))
      end
    end

    private def check_contains(context : CheckContext, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      return true if s["minContains"]?.try { |minimum| Guard.number?(minimum) && Guard.to_f(minimum) == 0 }
      return false if value.empty?
      value.each_with_index.count { |(item, index)| check_schema(context, s["contains"], item) && context.add_index(index) } > 0
    end

    private def contains_count(context : CheckContext, s : Hash(String, JSON::Any), value : Array(JSON::Any), track : Bool) : Int32
      value.each_with_index.count { |(item, index)| check_schema(context, s["contains"], item) && (!track || context.add_index(index)) }
    end

    private def check_max_contains(context : CheckContext, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      return true unless contains?(s)
      contains_count(context, s, value, false) <= num(s, "maxContains")
    end

    private def error_max_contains(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      minimum = number_key?(s, "minContains") ? s["minContains"] : JSON::Any.new(1_i64)
      check_max_contains(context, s, value) ||
        context.add_error("contains", schema_path, instance_path, params({"minContains" => minimum, "maxContains" => s["maxContains"]}))
    end

    private def check_min_contains(context : CheckContext, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      return true unless contains?(s)
      contains_count(context, s, value, true) >= num(s, "minContains")
    end

    private def check_items(context : CheckContext, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      if sized_items?(s)
        s["items"].as_a.each_with_index.all? { |(schema, index)| value.size <= index || (check_push(context, schema, value[index]) && context.add_index(index)) }
      else
        offset = schema_list?(s, "prefixItems") ? s["prefixItems"].as_a.size : 0
        (offset...value.size).all? { |index| check_push(context, s["items"], value[index]) && context.add_index(index) }
      end
    end

    private def error_items(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      if sized_items?(s)
        s["items"].as_a.each_with_index.map do |(schema, index)|
          value.size <= index || (error_push(context, "#{schema_path}/items/#{index}", "#{instance_path}/#{index}", schema, value[index]) && context.add_index(index))
        end.to_a.all?
      else
        offset = schema_list?(s, "prefixItems") ? s["prefixItems"].as_a.size : 0
        (offset...value.size).map do |index|
          error_push(context, "#{schema_path}/items", "#{instance_path}/#{index}", s["items"], value[index]) && context.add_index(index)
        end.all?
      end
    end

    private def check_prefix_items(context : CheckContext, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      value.empty? || s["prefixItems"].as_a.each_with_index.all? do |(schema, index)|
        value.size <= index || (check_push(context, schema, value[index]) && context.add_index(index))
      end
    end

    private def error_prefix_items(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      value.empty? || s["prefixItems"].as_a.each_with_index.map do |(schema, index)|
        value.size <= index || (error_push(context, "#{schema_path}/prefixItems/#{index}", "#{instance_path}/#{index}", schema, value[index]) && context.add_index(index))
      end.to_a.all?
    end

    private def duplicates(s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Array(Int32)
      return [] of Int32 if s["uniqueItems"].raw == false
      seen = ::Set(String).new
      result = [] of Int32
      value.each_with_index do |item, index|
        key = Hashing.key(item)
        result << index unless seen.add?(key)
      end
      result
    end

    private def error_unique_items(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      found = duplicates(s, value)
      found.empty? || context.add_error("uniqueItems", schema_path, instance_path, params({"duplicateItems" => JSON::Any.new(found.map { |index| JSON::Any.new(index.to_i64) })}))
    end

    private def limit_error(context : ErrorContext, keyword : String, schema_path : String, instance_path : String, s : Hash(String, JSON::Any)) : Bool
      context.add_error(keyword, schema_path, instance_path, params({"limit" => s[keyword]}))
    end

    private def comparison_error(context : ErrorContext, keyword : String, comparison : String, schema_path : String, instance_path : String, s : Hash(String, JSON::Any)) : Bool
      context.add_error(keyword, schema_path, instance_path, params({"comparison" => JSON::Any.new(comparison), "limit" => s[keyword]}))
    end

    private def resolve_ref(s : Hash(String, JSON::Any)) : JSON::Any
      Pointer.resolve(@root, s["$ref"].as_s) || JSON::Any.new(false)
    end

    private def check_ref(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      target = resolve_ref(s)
      next_context = CheckContext.new
      result = schema_like?(target) && check_schema(next_context, target, value)
      context.merge([next_context]) if result
      result
    end

    private def error_ref(context : ErrorContext, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      target = resolve_ref(s)
      next_context = ErrorContext.new
      result = schema_like?(target) && error_schema(next_context, "#", instance_path, target, value)
      if result
        context.merge([next_context] of CheckContext)
      else
        next_context.errors.each { |error| context.add_error(error) }
      end
      result
    end

    private def check_const(s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      constant = s["const"]
      Guard.value_like?(constant) ? Guard.strict_equal?(value, constant) : Guard.deep_equal?(value, constant)
    end

    private def check_enum(s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      s["enum"].as_a.any? { |option| Guard.value_like?(option) ? Guard.strict_equal?(value, option) : Guard.deep_equal?(value, option) }
    end

    private def branch(s : Hash(String, JSON::Any), key : String) : JSON::Any
      schema_key?(s, key) ? s[key] : JSON::Any.new(true)
    end

    private def check_if(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      check_schema(context, s["if"], value) ? check_schema(context, branch(s, "then"), value) : check_schema(context, branch(s, "else"), value)
    end

    private def error_if(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      true_context = ErrorContext.new
      result = if error_schema(true_context, "#{schema_path}/if", instance_path, s["if"], value)
                 error_schema(true_context, "#{schema_path}/then", instance_path, branch(s, "then"), value) ||
                   context.add_error("if", schema_path, instance_path, params({"failingKeyword" => JSON::Any.new("then")}))
               else
                 error_schema(context, "#{schema_path}/else", instance_path, branch(s, "else"), value) ||
                   context.add_error("if", schema_path, instance_path, params({"failingKeyword" => JSON::Any.new("else")}))
               end
      context.merge([true_context] of CheckContext) if result
      result
    end

    private def check_not(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      next_context = CheckContext.new
      !check_schema(next_context, s["not"], value) && context.merge([next_context])
    end

    private def check_all_of(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      schemas = s["allOf"].as_a
      passed = schemas.compact_map { |schema| (next_context = CheckContext.new) && check_schema(next_context, schema, value) ? next_context : nil }
      passed.size == schemas.size && context.merge(passed)
    end

    private def error_all_of(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      schemas = s["allOf"].as_a
      failed = [] of ErrorContext
      passed = [] of CheckContext
      schemas.each_with_index do |schema, index|
        next_context = ErrorContext.new
        if error_schema(next_context, "#{schema_path}/allOf/#{index}", instance_path, schema, value)
          passed << next_context
        else
          failed << next_context
        end
      end
      result = passed.size == schemas.size && context.merge(passed)
      failed.each { |next_context| next_context.errors.each { |error| context.add_error(error) } } unless result
      result
    end

    private def check_any_of(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      passed = s["anyOf"].as_a.compact_map { |schema| (next_context = CheckContext.new) && check_schema(next_context, schema, value) ? next_context : nil }
      passed.size > 0 && context.merge(passed)
    end

    private def error_any_of(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      failed = [] of ErrorContext
      passed = [] of CheckContext
      s["anyOf"].as_a.each_with_index do |schema, index|
        next_context = ErrorContext.new
        if error_schema(next_context, "#{schema_path}/anyOf/#{index}", instance_path, schema, value)
          passed << next_context
        else
          failed << next_context
        end
      end
      result = passed.size > 0 && context.merge(passed)
      failed.each { |next_context| next_context.errors.each { |error| context.add_error(error) } } unless result
      result || context.add_error("anyOf", schema_path, instance_path, empty)
    end

    private def check_one_of(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      passed = s["oneOf"].as_a.compact_map { |schema| (next_context = CheckContext.new) && check_schema(next_context, schema, value) ? next_context : nil }
      passed.size == 1 && context.merge(passed)
    end

    private def error_one_of(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any?) : Bool
      failed = [] of ErrorContext
      passed = [] of CheckContext
      passing = [] of Int32
      s["oneOf"].as_a.each_with_index do |schema, index|
        next_context = ErrorContext.new
        if error_schema(next_context, "#{schema_path}/oneOf/#{index}", instance_path, schema, value)
          passing << index
          passed << next_context
        else
          failed << next_context
        end
      end
      result = passed.size == 1 && context.merge(passed)
      failed.each { |next_context| next_context.errors.each { |error| context.add_error(error) } } if !result && passing.empty?
      result || context.add_error("oneOf", schema_path, instance_path, params({"passingSchemas" => JSON::Any.new(passing.map { |index| JSON::Any.new(index.to_i64) })}))
    end

    private def check_unevaluated_items(context : CheckContext, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      evaluated = context.indices
      value.each_with_index.all? do |(item, index)|
        (evaluated.includes?(index) || check_schema(context, s["unevaluatedItems"], item)) && context.add_index(index)
      end
    end

    private def error_unevaluated_items(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : Array(JSON::Any)) : Bool
      evaluated = context.indices
      unevaluated = [] of Int32
      value.each_with_index do |item, index|
        valid = (evaluated.includes?(index) || error_schema(ErrorContext.new, schema_path, instance_path, s["unevaluatedItems"], item)) && context.add_index(index)
        unevaluated << index unless valid
      end
      unevaluated.empty? || context.add_error("unevaluatedItems", schema_path, instance_path,
        params({"unevaluatedItems" => JSON::Any.new(unevaluated.map { |index| JSON::Any.new(index.to_i64) })}))
    end

    private def check_unevaluated_properties(context : CheckContext, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      evaluated = context.keys
      entries(value).all? do |(key, item)|
        evaluated.includes?(key) || (check_schema(context, s["unevaluatedProperties"], item) && context.add_key(key))
      end
    end

    private def error_unevaluated_properties(context : ErrorContext, schema_path : String, instance_path : String, s : Hash(String, JSON::Any), value : JSON::Any) : Bool
      evaluated = context.keys
      unevaluated = [] of String
      entries(value).each do |(key, item)|
        valid = evaluated.includes?(key) || (error_schema(ErrorContext.new, schema_path, instance_path, s["unevaluatedProperties"], item) && context.add_key(key))
        unevaluated << key unless valid
      end
      unevaluated.empty? || context.add_error("unevaluatedProperties", schema_path, instance_path, params({"unevaluatedProperties" => strings(unevaluated)}))
    end
  end

  module Pointer
    SKIPPED = {"const", "enum"}

    def self.resolve(root : JSON::Any, reference : String) : JSON::Any?
      return unless hash = reference.index('#')
      fragment = reference[(hash + 1)..]
      return root if fragment.empty?
      pointer = URI.decode(fragment)
      return unless pointer.starts_with?('/')
      find(root, pointer)
    end

    private def self.find(node : JSON::Any, pointer : String) : JSON::Any?
      if node.raw.is_a?(Hash) && (match = get(node, pointer))
        return match
      end
      result = nil
      case raw = node.raw
      when Array
        raw.each { |item| find(item, pointer).try { |found| result = found } }
      when Hash
        Guard.keys(node).each do |key|
          next if SKIPPED.includes?(key)
          find(raw[key], pointer).try { |found| result = found }
        end
      end
      result
    end

    private def self.get(node : JSON::Any, pointer : String) : JSON::Any?
      current = node
      pointer.split('/')[1..].each do |token|
        key = token.gsub("~1", "/").gsub("~0", "~")
        return if !Guard.object?(current) || Guard::UNSAFE_KEYS.includes?(key)
        return unless current = Guard.get(current, key)
      end
      current
    end
  end

  module Hashing
    def self.key(value : JSON::Any) : String
      String.build { |io| write(io, value) }
    end

    private def self.write(io : IO, value : JSON::Any) : Nil
      case raw = value.raw
      when Array
        io << "A" << raw.size << '['
        raw.each { |item| write(io, item) }
        io << ']'
      when Hash
        io << "O" << raw.size << '{'
        raw.keys.sort_by!(&.to_utf16.to_a).each do |name|
          io << name.bytesize << ':' << name
          write(io, raw[name])
        end
        io << '}'
      when Int64, Float64
        io << "N" << raw.to_f64.unsafe_as(UInt64) << ';'
      when String
        io << "S" << raw.bytesize << ':' << raw
      when Bool
        io << (raw ? "T" : "F")
      else
        io << "Z"
      end
    end
  end
end
