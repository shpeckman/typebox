# src/typebox/schema.cr
require "json"

module TypeBox
  alias Child = Schema | Array(Schema) | Hash(String, Schema)
  alias Entry = JSON::Any | Child

  class Schema
    getter kind : String?
    getter? optional : Bool
    getter? readonly : Bool
    getter? immutable : Bool
    getter? unsafe : Bool
    getter entries : Array(Tuple(String, Entry))
    @json : JSON::Any? = nil

    def initialize(@kind : String?, @entries : Array(Tuple(String, Entry)), @optional : Bool = false,
                   @readonly : Bool = false, @immutable : Bool = false, @unsafe : Bool = false)
    end

    def self.from_json(json : JSON::Any) : Schema
      entries = [] of Tuple(String, Entry)
      json.as_h?.try &.each { |key, value| entries << {key, value.as(Entry)} }
      new(nil, entries)
    end

    def self.coerce(value : Schema | JSON::Any) : Schema
      value.is_a?(Schema) ? value : from_json(value)
    end

    def json : JSON::Any
      @json ||= JSON::Any.new(@entries.each_with_object({} of String => JSON::Any) do |(key, value), result|
        result[key] = Schema.entry_json(value)
      end)
    end

    def self.entry_json(value : Entry) : JSON::Any
      case value
      when JSON::Any then value
      when Schema    then value.json
      when Array     then JSON::Any.new(value.map(&.json))
      else                JSON::Any.new(value.transform_values(&.json))
      end
    end

    def has_key?(key : String) : Bool
      @entries.any? { |(name, _)| name == key }
    end

    def []?(key : String) : Entry?
      @entries.each { |(name, value)| return value if name == key }
      nil
    end

    def value?(key : String) : JSON::Any?
      self[key]?.try { |entry| Schema.entry_json(entry) }
    end

    def schema?(key : String) : Schema?
      case value = self[key]?
      when Schema    then value
      when JSON::Any then value.raw.is_a?(Hash) || value.raw.is_a?(Bool) ? Schema.from_json(value) : nil
      end
    end

    def schemas?(key : String) : Array(Schema)?
      case value = self[key]?
      when Array(Schema) then value
      when JSON::Any     then value.as_a?.try &.map { |item| Schema.from_json(item) }
      end
    end

    def schema_map?(key : String) : Hash(String, Schema)?
      case value = self[key]?
      when Hash(String, Schema) then value
      when JSON::Any            then value.as_h?.try &.transform_values { |item| Schema.from_json(item) }
      end
    end

    def kind?(name : String) : Bool
      @kind == name
    end

    def with_entries(updates : Array(Tuple(String, Entry))) : Schema
      merged = @entries.dup
      updates.each do |(key, value)|
        if index = merged.index { |(name, _)| name == key }
          merged[index] = {key, value}
        else
          merged << {key, value}
        end
      end
      Schema.new(@kind, merged, @optional, @readonly, @immutable, @unsafe)
    end

    def without(keys : Enumerable(String)) : Schema
      Schema.new(@kind, @entries.reject { |(name, _)| keys.includes?(name) }, @optional, @readonly, @immutable, @unsafe)
    end

    def with_kind(kind : String?) : Schema
      Schema.new(kind, @entries, @optional, @readonly, @immutable, @unsafe)
    end

    def with_flags(optional : Bool = @optional, readonly : Bool = @readonly, immutable : Bool = @immutable, unsafe : Bool = @unsafe) : Schema
      Schema.new(@kind, @entries, optional, readonly, immutable, unsafe)
    end

    def ==(other : Schema) : Bool
      @kind == other.kind && @optional == other.optional? && @readonly == other.readonly? &&
        @immutable == other.immutable? && @unsafe == other.unsafe? && json == other.json
    end

    def to_json(builder : JSON::Builder) : Nil
      json.to_json(builder)
    end

    def to_s(io : IO) : Nil
      json.to_json(io)
    end

    def inspect(io : IO) : Nil
      io << "TypeBox::Schema("
      io << (@kind || "unkinded")
      io << ' '
      json.to_json(io)
      io << " optional" if @optional
      io << " readonly" if @readonly
      io << " immutable" if @immutable
      io << " unsafe" if @unsafe
      io << ')'
    end
  end
end
