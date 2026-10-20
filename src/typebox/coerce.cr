# src/typebox/coerce.cr
module TypeBox::Coerce
  alias Options = Array(Tuple(String, Entry))

  def self.any(value : JSON::Any) : JSON::Any
    value
  end

  def self.any(value : Nil) : JSON::Any
    JSON::Any.new(nil)
  end

  def self.any(value : Bool | String | Int64 | Float64) : JSON::Any
    JSON::Any.new(value)
  end

  def self.any(value : Int) : JSON::Any
    JSON::Any.new(value.to_i64)
  end

  def self.any(value : Float) : JSON::Any
    JSON::Any.new(value.to_f64)
  end

  def self.any(value : Symbol) : JSON::Any
    JSON::Any.new(value.to_s)
  end

  def self.any(value : Schema) : JSON::Any
    value.json
  end

  def self.any(value : Array | Tuple | Set) : JSON::Any
    JSON::Any.new(value.map { |item| any(item) }.to_a)
  end

  def self.any(value : Hash) : JSON::Any
    JSON::Any.new(value.each_with_object({} of String => JSON::Any) { |(key, item), result| result[key.to_s] = any(item) })
  end

  def self.any(value : NamedTuple) : JSON::Any
    any(value.to_h)
  end

  def self.entry(value : Schema) : Entry
    value
  end

  def self.entry(value : Array(Schema)) : Entry
    value
  end

  def self.entry(value : Hash(String, Schema)) : Entry
    value
  end

  def self.entry(value) : Entry
    any(value)
  end

  def self.options(options : NamedTuple) : Options
    result = Options.new
    options.each { |key, value| result << {key.to_s, entry(value)} }
    result
  end

  def self.options(options : Hash) : Options
    result = Options.new
    options.each { |key, value| result << {key.to_s, entry(value)} }
    result
  end

  def self.properties(properties : NamedTuple) : Hash(String, Schema)
    result = {} of String => Schema
    properties.each { |key, value| result[key.to_s] = value.as(Schema) }
    result
  end

  def self.properties(properties : Hash) : Hash(String, Schema)
    result = {} of String => Schema
    properties.each { |key, value| result[key.to_s] = value.as(Schema) }
    result
  end

  def self.ordered(properties : Hash(String, Schema)) : Hash(String, Schema)
    keys = Guard.keys(JSON::Any.new(properties.transform_values { |_| JSON::Any.new(nil) }))
    keys.each_with_object({} of String => Schema) { |key, result| result[key] = properties[key] }
  end
end
