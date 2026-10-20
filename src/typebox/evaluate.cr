# src/typebox/evaluate.cr
module TypeBox::Evaluate
  enum Comparison
    Equal
    Disjoint
    LeftInside
    RightInside
  end

  def self.compare(left : Schema, right : Schema) : Comparison
    forward = Extends.check(left, right)
    backward = Extends.check(right, left)
    if forward.true_like? && backward.true_like?
      Comparison::Equal
    elsif forward.true_like? && backward.false?
      Comparison::LeftInside
    elsif forward.false? && backward.true_like?
      Comparison::RightInside
    else
      Comparison::Disjoint
    end
  end

  def self.type(type : Schema) : Schema
    case type.kind
    when "Enum"      then self.enum(type.value?("enum").try(&.as_a?) || [] of JSON::Any)
    when "Intersect" then intersect(type.schemas?("allOf") || [] of Schema)
    when "Union"     then union(type.schemas?("anyOf") || [] of Schema)
    else                  type
    end
  end

  def self.enum(values : Array(JSON::Any)) : Schema
    union(values.map { |value| Type.literal_from(value) })
  end

  def self.intersect(types : Array(Schema)) : Schema
    union(broaden(distribute(types)))
  end

  def self.union(types : Array(Schema)) : Schema
    union_fast(broaden(types))
  end

  def self.union_fast(types : Array(Schema)) : Schema
    case types.size
    when 0 then Type.never
    when 1 then types.first
    else        Type.union_from(types)
    end
  end

  def self.flatten(types : Array(Schema)) : Array(Schema)
    types.flat_map { |type| type.kind?("Union") ? flatten(type.schemas?("anyOf") || [] of Schema) : [type] }
  end

  def self.broaden(types : Array(Schema)) : Array(Schema)
    result = [] of Schema
    types.each do |type|
      evaluated = type(type)
      case evaluated.kind
      when "Any", "Unknown"
        result = [evaluated]
        break
      when "Never"
        next
      when "Object"
        result << evaluated
      else
        result = broaden_filter(evaluated, result)
      end
    end
    flatten(result)
  end

  private def self.broaden_filter(type : Schema, types : Array(Schema)) : Array(Schema)
    kept = [] of Schema
    types.each do |other|
      case compare(type, other)
      when .left_inside?, .equal? then return types
      when .disjoint?             then kept << other
      end
    end
    kept << type
    kept
  end

  def self.distribute(types : Array(Schema), result : Array(Schema) = [] of Schema) : Array(Schema)
    types.each do |type|
      result = if type.kind?("Union")
                 (type.schemas?("anyOf") || [] of Schema).flat_map { |variant| distribute([variant], result) }
               else
                 distribute_type(type, result)
               end
    end
    result
  end

  private def self.distribute_type(type : Schema, types : Array(Schema)) : Array(Schema)
    return [type] if types.empty?
    types.map { |other| distribute_operation(other, type) }
  end

  private def self.distribute_operation(left : Schema, right : Schema) : Schema
    evaluated_left = type(left)
    evaluated_right = type(right)
    if evaluated_left.kind?("Union") || evaluated_right.kind?("Union")
      intersect([evaluated_left, evaluated_right])
    else
      narrow(evaluated_left, evaluated_right)
    end
  end

  def self.narrow(left : Schema, right : Schema) : Schema
    return left if left.kind?("Never") || left.kind?("Any")
    return right if left.kind?("Unknown")
    return right if right.kind?("Never") || right.kind?("Any")
    return left if right.kind?("Unknown")
    composite_left = composite?(left)
    composite_right = composite?(right)
    return composite(left, right) if composite_left && composite_right
    return left if composite_left
    return right if composite_right
    case compare(left, right)
    when .left_inside?           then left
    when .right_inside?, .equal? then right
    else                              Type.never
    end
  end

  private def self.composite?(type : Schema) : Bool
    type.kind?("Object") || type.kind?("Tuple")
  end

  private def self.properties_of(type : Schema) : Hash(String, Schema)
    if type.kind?("Object")
      type.schema_map?("properties") || {} of String => Schema
    else
      result = {} of String => Schema
      (type.schemas?("items") || [] of Schema).each_with_index { |item, index| result[index.to_s] = item }
      result
    end
  end

  def self.composite(left : Schema, right : Schema) : Schema
    left_properties = properties_of(left)
    right_properties = properties_of(right)
    properties = {} of String => Schema
    (left_properties.keys | right_properties.keys).each do |key|
      a = left_properties[key]?
      b = right_properties[key]?
      properties[key] = a && b ? composite_property(a, b) : (a || b).not_nil!
    end
    Type.object_from(properties)
  end

  private def self.composite_property(left : Schema, right : Schema) : Schema
    readonly = left.readonly? && right.readonly?
    optional = left.optional? && right.optional?
    intersect([left, right]).with_flags(optional: optional, readonly: readonly)
  end

  def self.priority(types : Array(Schema)) : Array(Schema)
    result = [] of Schema
    types.each { |type| result = insert(type, result) }
    result
  end

  private def self.insert(type : Schema, types : Array(Schema)) : Array(Schema)
    types.each_with_index do |other, index|
      comparison = compare(type, other)
      next if comparison.right_inside? || comparison.disjoint?
      return types[0, index] + [type] + types[index..]
    end
    types + [type]
  end
end
