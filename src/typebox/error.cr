# src/typebox/error.cr
module TypeBox
  struct ValidationError
    getter keyword : String
    getter schema_path : String
    getter instance_path : String
    getter params : JSON::Any
    getter message : String

    def initialize(@keyword : String, @schema_path : String, @instance_path : String, @params : JSON::Any, @message : String = ""); end

    def with_message(message : String) : ValidationError
      ValidationError.new(@keyword, @schema_path, @instance_path, @params, message)
    end

    def to_json(builder : JSON::Builder) : Nil
      builder.object do
        builder.field "keyword", @keyword
        builder.field "schemaPath", @schema_path
        builder.field "instancePath", @instance_path
        builder.field "params", @params
        builder.field "message", @message
      end
    end
  end

  alias LocaleFunction = Proc(ValidationError, String)

  module Locale
    EN_US = LocaleFunction.new { |error| Locale.en_us(error) }

    @@current : LocaleFunction = EN_US

    def self.get : LocaleFunction
      @@current
    end

    def self.set(locale : LocaleFunction) : Nil
      @@current = locale
    end

    def self.reset : Nil
      @@current = EN_US
    end

    def self.en_us(error : ValidationError) : String
      params = error.params
      case error.keyword
      when "additionalProperties" then "must not have additional properties"
      when "anyOf"                then "must match a schema in anyOf"
      when "boolean"              then "schema is false"
      when "const"                then "must be equal to constant"
      when "contains"             then "must contain at least 1 valid item"
      when "dependencies", "dependentRequired"
        "must have properties #{list(params["dependencies"])} when property #{text(params["property"])} is present"
      when "enum" then "must be equal to one of the allowed values"
      when "exclusiveMaximum", "exclusiveMinimum", "maximum", "minimum"
        "must be #{text(params["comparison"])} #{text(params["limit"])}"
      when "format"        then "must match format \"#{text(params["format"])}\""
      when "if"            then "must match \"#{text(params["failingKeyword"])}\" schema"
      when "maxItems"      then "must not have more than #{text(params["limit"])} items"
      when "maxLength"     then "must not have more than #{text(params["limit"])} characters"
      when "maxProperties" then "must not have more than #{text(params["limit"])} properties"
      when "minItems"      then "must not have fewer than #{text(params["limit"])} items"
      when "minLength"     then "must not have fewer than #{text(params["limit"])} characters"
      when "minProperties" then "must not have fewer than #{text(params["limit"])} properties"
      when "multipleOf"    then "must be multiple of #{text(params["multipleOf"])}"
      when "not"           then "must not be valid"
      when "oneOf"         then "must match exactly one schema in oneOf"
      when "pattern"       then "must match pattern \"#{text(params["pattern"])}\""
      when "propertyNames" then "property names #{list(params["propertyNames"])} are invalid"
      when "required"      then "must have required properties #{list(params["requiredProperties"])}"
      when "type"
        type = params["type"]
        type.as_s? ? "must be #{type.as_s}" : "must be either #{type.as_a.join(" or ") { |item| text(item) }}"
      when "unevaluatedItems"      then "must not have unevaluated items"
      when "unevaluatedProperties" then "must not have unevaluated properties"
      when "uniqueItems"           then "must not have duplicate items"
      else                              "an unknown validation error occurred"
      end
    end

    def self.text(value : JSON::Any) : String
      case raw = value.raw
      when String         then raw
      when Int64, Float64 then Guard.js_number(raw)
      when Nil            then "null"
      when Bool           then raw.to_s
      when Array          then raw.join(',') { |item| item.raw.nil? ? "" : text(item) }
      else                     "[object Object]"
      end
    end

    private def self.list(value : JSON::Any) : String
      value.as_a.join(", ") { |item| text(item) }
    end
  end
end
