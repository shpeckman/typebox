# src/typebox/guard.cr
module TypeBox::Guard
  UNSAFE_KEYS = {"__proto__", "constructor", "prototype"}
  MAX_INDEX   = 4_294_967_294_u64

  def self.number?(value : JSON::Any?) : Bool
    return false unless value
    raw = value.raw
    raw.is_a?(Int64) || (raw.is_a?(Float64) && raw.finite?)
  end

  def self.integer?(value : JSON::Any?) : Bool
    return false unless value
    raw = value.raw
    raw.is_a?(Int64) || (raw.is_a?(Float64) && raw.finite? && raw == raw.trunc)
  end

  def self.string?(value : JSON::Any?) : Bool
    !value.nil? && value.raw.is_a?(String)
  end

  def self.boolean?(value : JSON::Any?) : Bool
    !value.nil? && value.raw.is_a?(Bool)
  end

  def self.null?(value : JSON::Any?) : Bool
    !value.nil? && value.raw.nil?
  end

  def self.array?(value : JSON::Any?) : Bool
    !value.nil? && value.raw.is_a?(Array)
  end

  def self.object?(value : JSON::Any?) : Bool
    return false unless value
    raw = value.raw
    raw.is_a?(Hash) || raw.is_a?(Array)
  end

  def self.object_not_array?(value : JSON::Any?) : Bool
    !value.nil? && value.raw.is_a?(Hash)
  end

  def self.to_f(value : JSON::Any) : Float64
    case raw = value.raw
    when Int64   then raw.to_f64
    when Float64 then raw
    else              Float64::NAN
    end
  end

  def self.value_like?(value : JSON::Any?) : Bool
    return true if value.nil?
    case value.raw
    when Hash, Array then false
    else                  true
    end
  end

  def self.strict_equal?(left : JSON::Any?, right : JSON::Any?) : Bool
    return left.nil? && right.nil? if left.nil? || right.nil?
    a = left.raw
    b = right.raw
    case a
    when Int64, Float64
      (b.is_a?(Int64) || b.is_a?(Float64)) && a.to_f64 == b.to_f64
    when Hash
      b.is_a?(Hash) && a.same?(b)
    when Array
      b.is_a?(Array) && a.same?(b)
    else
      !b.is_a?(Int64) && !b.is_a?(Float64) && !b.is_a?(Hash) && !b.is_a?(Array) && a == b
    end
  end

  def self.deep_equal?(left : JSON::Any?, right : JSON::Any?) : Bool
    if left && (items = left.raw.as?(Array))
      other = right.try(&.raw.as?(Array))
      return false unless other && items.size == other.size
      items.each_with_index { |item, index| return false unless deep_equal?(item, other[index]) }
      return true
    end
    if left && (fields = left.raw.as?(Hash))
      return false unless object?(right)
      other_keys = keys(right.not_nil!)
      other_size = array?(right) ? other_keys.size + 1 : other_keys.size
      return false unless fields.size == other_size
      fields.each { |key, item| return false unless deep_equal?(item, get(right.not_nil!, key)) }
      return true
    end
    strict_equal?(left, right)
  end

  def self.index_key?(key : String) : Bool
    return false if key.empty? || key.size > 10
    return key == "0" if key.starts_with?('0')
    key.each_char { |char| return false unless char.ascii_number? }
    key.to_u64 <= MAX_INDEX
  end

  def self.keys(value : JSON::Any) : Array(String)
    case raw = value.raw
    when Hash
      indices = [] of String
      names = [] of String
      raw.each_key { |key| index_key?(key) ? indices << key : names << key }
      indices.sort_by!(&.to_u64)
      indices.concat(names)
    when Array
      Array(String).new(raw.size, &.to_s)
    else
      [] of String
    end
  end

  def self.get(value : JSON::Any, key : String) : JSON::Any?
    case raw = value.raw
    when Hash
      raw[key]?
    when Array
      index_key?(key) && key.to_u64 < raw.size ? raw[key.to_i] : nil
    end
  end

  def self.has_property_key?(value : JSON::Any, key : String) : Bool
    case raw = value.raw
    when Hash  then raw.has_key?(key)
    when Array then key == "length" || (index_key?(key) && key.to_u64 < raw.size)
    else            false
    end
  end

  def self.multiple_of?(dividend : JSON::Any, divisor : JSON::Any) : Bool
    return true unless number?(dividend)
    left = to_f(dividend)
    right = to_f(divisor)
    return true if integer?(dividend) && js_mod(1.0 / right, 1.0) == 0
    remainder = js_mod(left, right)
    {remainder.abs, (remainder - right).abs, (remainder + right).abs}.min < 1e-10
  end

  def self.js_mod(left : Float64, right : Float64) : Float64
    return Float64::NAN if right == 0 || !left.finite? || right.nan?
    return left if right.infinite?
    left - right * (left / right).trunc
  end

  def self.js_number(value : Int64 | Float64) : String
    return value.to_s if value.is_a?(Int64)
    return "NaN" if value.nan?
    return (value > 0 ? "Infinity" : "-Infinity") if value.infinite?
    return "0" if value == 0
    sign = value < 0 ? "-" : ""
    text = value.abs.to_s
    mantissa, _, exponent = text.partition('e')
    point = mantissa.index('.') || mantissa.size
    digits = mantissa.delete('.')
    position = point + (exponent.empty? ? 0 : exponent.to_i)
    leading = digits.size - digits.lstrip('0').size
    digits = digits.lstrip('0')
    position -= leading
    digits = digits.rstrip('0')
    count = digits.size
    body = if count <= position <= 21
             digits + "0" * (position - count)
           elsif 0 < position <= 21
             "#{digits[0, position]}.#{digits[position..]}"
           elsif -6 < position <= 0
             "0.#{"0" * -position}#{digits}"
           else
             exponent_value = position - 1
             head = count > 1 ? "#{digits[0]}.#{digits[1..]}" : digits
             "#{head}e#{exponent_value >= 0 ? '+' : '-'}#{exponent_value.abs}"
           end
    sign + body
  end

  def self.js_length(value : String) : Int32
    count = 0
    value.each_char { |char| count += char.ord > 0xFFFF ? 2 : 1 }
    count
  end

  def self.min_length?(value : String, minimum : Float64) : Bool
    return true if minimum == 0
    units = value.to_utf16
    return false if units.size < minimum
    index = 0
    loop do
      return min_length_segmented?(units, minimum) if grapheme_unit?(units[index]? || 0_u16)
      index += 1
      return true if index >= minimum
    end
  end

  def self.max_length?(value : String, maximum : Float64) : Bool
    units = value.to_utf16
    return true if units.size <= maximum
    index = 0
    loop do
      return max_length_segmented?(units, maximum) if grapheme_unit?(units[index]? || 0_u16)
      index += 1
      return false if index > maximum
    end
  end

  def self.grapheme_count(value : String) : Int32
    units = value.to_utf16
    count = 0
    index = 0
    while index < units.size
      index = next_cluster(units, index)
      count += 1
    end
    count
  end

  private def self.min_length_segmented?(units : Slice(UInt16), minimum : Float64) : Bool
    count = 0
    index = 0
    while index < units.size
      index = next_cluster(units, index)
      count += 1
      return true if count >= minimum
    end
    false
  end

  private def self.max_length_segmented?(units : Slice(UInt16), maximum : Float64) : Bool
    count = 0
    index = 0
    while index < units.size
      index = next_cluster(units, index)
      count += 1
      return false if count > maximum
    end
    true
  end

  private def self.grapheme_unit?(unit : UInt16) : Bool
    unit >= 0x0300 && ((0xD800 <= unit <= 0xDBFF) || combining_mark?(unit.to_i) || variation_selector?(unit.to_i) || unit == 0x200D)
  end

  private def self.code_point_at(units : Slice(UInt16), index : Int32) : Int32
    unit = units[index].to_i
    if 0xD800 <= unit <= 0xDBFF && index + 1 < units.size
      low = units[index + 1].to_i
      return 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00) if 0xDC00 <= low <= 0xDFFF
    end
    unit
  end

  private def self.width(code_point : Int32) : Int32
    code_point > 0xFFFF ? 2 : 1
  end

  private def self.combining_mark?(value : Int32) : Bool
    (0x0300 <= value <= 0x036F) || (0x1AB0 <= value <= 0x1AFF) || (0x1DC0 <= value <= 0x1DFF) || (0xFE20 <= value <= 0xFE2F)
  end

  private def self.variation_selector?(value : Int32) : Bool
    0xFE00 <= value <= 0xFE0F
  end

  private def self.regional_indicator?(value : Int32) : Bool
    0x1F1E6 <= value <= 0x1F1FF
  end

  private def self.consume_modifiers(units : Slice(UInt16), index : Int32) : Int32
    while index < units.size
      point = code_point_at(units, index)
      break unless combining_mark?(point) || variation_selector?(point)
      index += width(point)
    end
    index
  end

  private def self.next_cluster(units : Slice(UInt16), start : Int32) : Int32
    first = code_point_at(units, start)
    finish = consume_modifiers(units, start + width(first))
    while finish < units.size - 1 && code_point_at(units, finish) == 0x200D
      following = code_point_at(units, finish + 1)
      finish = consume_modifiers(units, finish + 1 + width(following))
    end
    if regional_indicator?(first) && finish < units.size && regional_indicator?(code_point_at(units, finish))
      finish += width(code_point_at(units, finish))
    end
    finish
  end
end
