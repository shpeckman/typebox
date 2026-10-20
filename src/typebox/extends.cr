# src/typebox/extends.cr
module TypeBox::Extends
  enum Result
    True
    Union
    False

    def true_like? : Bool
      !false?
    end
  end

  def self.check(left : Schema, right : Schema) : Result
    left(canonical(left), canonical(right))
  end

  private def self.canonical(type : Schema) : Schema
    type.unsafe? ? Type.unknown : type
  end

  private def self.match(result : Result) : Result
    result.true_like? ? Result::True : Result::False
  end

  private def self.verdict(value : Bool) : Result
    value ? Result::True : Result::False
  end

  private def self.items(type : Schema, key : String) : Array(Schema)
    type.schemas?(key) || [] of Schema
  end

  private def self.child(type : Schema, key : String) : Schema
    type.schema?(key) || Type.unknown
  end

  private def self.properties(type : Schema) : Hash(String, Schema)
    type.schema_map?("properties") || {} of String => Schema
  end

  def self.left(left : Schema, right : Schema) : Result
    case left.kind
    when "Any"       then any(right)
    when "Array"     then array(left, right)
    when "Boolean"   then right.kind?("Boolean") ? Result::True : right(left, right)
    when "Enum"      then left(Evaluate.enum(enum_values(left)), right)
    when "Function"  then function(left, right)
    when "Integer"   then right.kind?("Integer") || right.kind?("Number") ? Result::True : right(left, right)
    when "Intersect" then left(Evaluate.intersect(items(left, "allOf")), right)
    when "Literal"   then literal(left, right)
    when "Never"     then Result::True
    when "Null"      then right.kind?("Null") ? Result::True : right(left, right)
    when "Number"    then right.kind?("Number") ? Result::True : right(left, right)
    when "Object"    then object(left, right)
    when "Record"    then record(left, right)
    when "String"    then right.kind?("String") ? Result::True : right(left, right)
    when "Tuple"     then tuple(left, right)
    when "Undefined" then right.kind?("Void") || right.kind?("Undefined") ? Result::True : right(left, right)
    when "Union"     then union(items(left, "anyOf"), right)
    when "Unknown"   then verdict(right.kind?("Any") || right.kind?("Unknown"))
    when "Void"      then right.kind?("Void") ? Result::True : right(left, right)
    else                  Result::False
    end
  end

  def self.right(left : Schema, right : Schema) : Result
    case right.kind
    when "Any"       then Result::True
    when "Enum"      then left(left, Evaluate.enum(enum_values(right)))
    when "Intersect" then verdict(items(right, "allOf").all? { |type| left(left, type).true_like? })
    when "Union"     then verdict(items(right, "anyOf").any? { |type| left(left, type).true_like? })
    when "Unknown"   then Result::True
    else                  Result::False
    end
  end

  private def self.enum_values(type : Schema) : Array(JSON::Any)
    type.value?("enum").try(&.as_a?) || [] of JSON::Any
  end

  private def self.any(right : Schema) : Result
    right.kind?("Any") || right.kind?("Unknown") ? Result::True : Result::Union
  end

  private def self.array(left : Schema, right : Schema) : Result
    return right(left, right) unless right.kind?("Array")
    return Result::False if left.immutable? && !right.immutable?
    left(child(left, "items"), child(right, "items"))
  end

  private def self.function(left : Schema, right : Schema) : Result
    return Result::True if right.kind?("Any") || right.kind?("Unknown")
    return Result::False unless right.kind?("Function")
    return Result::False unless parameters(items(left, "parameters"), items(right, "parameters")).true_like?
    returns = child(right, "returnType")
    returns.kind?("Void") ? Result::True : left(child(left, "returnType"), returns)
  end

  private def self.parameters(left : Array(Schema), right : Array(Schema)) : Result
    left.each_with_index do |parameter, index|
      other = right[index]?
      return verdict(parameter.optional?) unless other
      return Result::False if !parameter.optional? && other.optional?
      return Result::False unless left(other, parameter).true_like?
    end
    Result::True
  end

  private def self.literal(left : Schema, right : Schema) : Result
    constant = left.value?("const").not_nil!
    base = case constant.raw
           when Bool           then "Boolean"
           when Int64, Float64 then "Number"
           else                     "String"
           end
    if right.kind?("Literal")
      verdict(Guard.strict_equal?(constant, right.value?("const")))
    elsif right.kind?(base)
      Result::True
    else
      right(left, right)
    end
  end

  private def self.object(left : Schema, right : Schema) : Result
    case right.kind
    when "Record" then object_to_record(properties(left), Type::Records.value(right))
    when "Object" then object_to_object(properties(left), properties(right))
    else               right(left, right)
    end
  end

  private def self.object_to_record(properties : Hash(String, Schema), value : Schema) : Result
    verdict(properties.values.all? { |property| left(property, value).true_like? })
  end

  private def self.object_to_object(left : Hash(String, Schema), right : Hash(String, Schema)) : Result
    verdict(right.all? do |key, property|
      if other = left[key]?
        left(other, property).true_like? && (!other.optional? || property.optional?)
      else
        property.optional?
      end
    end)
  end

  private def self.record(left : Schema, right : Schema) : Result
    case right.kind
    when "Record"         then left(Type::Records.value(left), Type::Records.value(right))
    when "Object"         then verdict(properties(right).empty?)
    when "Any", "Unknown" then Result::True
    else                       Result::False
    end
  end

  private def self.tuple(left : Schema, right : Schema) : Result
    elements = items(left, "items")
    case right.kind
    when "Tuple"
      others = items(right, "items")
      verdict(elements.size == others.size && elements.zip(others).all? { |(element, other)| left(element, other).true_like? })
    when "Array"
      target = child(right, "items")
      verdict(elements.all? { |element| left(element, target).true_like? })
    else
      right(left, right)
    end
  end

  private def self.union(variants : Array(Schema), right : Schema) : Result
    targets = right.kind?("Union") ? items(right, "anyOf") : [right]
    verdict(variants.all? { |variant| targets.any? { |target| left(variant, target).true_like? } })
  end
end
