# src/typebox/pattern.cr
module TypeBox::Pattern
  class Part
    getter text : String?
    getter members : Array(Part)?

    def initialize(@text : String? = nil, @members : Array(Part)? = nil); end

    def finite? : Bool
      return true if @text
      (members = @members) ? !members.empty? && members.all?(&.finite?) : false
    end
  end

  BIGINT    = "-?(?:0|[1-9][0-9]*)n"
  OTHERS    = [BIGINT, Type::STRING_PATTERN, Type::NUMBER_PATTERN, Type::INTEGER_PATTERN, "(?!)"]
  SENTINELS = OTHERS + ["(", ")", "$", "|"]
  OTHER     = Part.new
  SPACE     = {'\t', '\n', '\v', '\f', '\r', ' ', ' ', ' ', ' ', ' ', ' ', ' ', '　', '﻿'}

  alias Parsed = Tuple(Array(Part), String)

  def self.key_type(pattern : String) : Schema?
    case pattern
    when Type::STRING_KEY  then return Type.string
    when Type::INTEGER_KEY then return Type.integer
    when Type::NUMBER_KEY  then return Type.number
    end
    parts = parse(pattern)
    return Type.string if parts.nil? || parts.empty?
    return unless parts.all?(&.finite?)
    if parts.size == 1 && (text = parts.first.text)
      Type.literal(text)
    else
      Type.union_from(variants(parts).map { |variant| Type.literal(variant) })
    end
  end

  def self.parse(pattern : String) : Array(Part)?
    return unless rest = const("^", pattern)
    parts, rest = union(rest)
    const("$", rest) ? parts : nil
  end

  private def self.variants(parts : Array(Part)) : Array(String)
    parts.reduce([] of String) { |variants, part| expand(variants, part) }
  end

  private def self.expand(variants : Array(String), part : Part) : Array(String)
    if text = part.text
      variants.empty? ? [text] : variants.map { |variant| variant + text }
    else
      (part.members || [] of Part).flat_map { |member| expand(variants, member) }
    end
  end

  private def self.space?(char : Char) : Bool
    SPACE.includes?(char) || (0x2000 <= char.ord <= 0x200a)
  end

  private def self.trim(input : String) : String
    trimmed = input.lstrip { |char| space?(char) }
    if trimmed.starts_with?("/*")
      index = trimmed.index("*/", 2)
      trim(index ? trimmed[(index + 2)..] : "")
    elsif trimmed.starts_with?("//")
      index = trimmed.index('\n', 2)
      trim(index ? trimmed[index..] : "")
    else
      trimmed
    end
  end

  private def self.const(token : String, input : String) : String?
    trimmed = trim(input)
    trimmed.starts_with?(token) ? trimmed[token.size..] : nil
  end

  private def self.text(input : String) : Tuple(Part, String)?
    index = 0
    while index < input.size
      rest = input[index..]
      if SENTINELS.any? { |sentinel| rest.starts_with?(sentinel) }
        return index == 0 ? nil : {Part.new(text: input[0, index]), rest}
      end
      index += 1
    end
    nil
  end

  private def self.base(input : String) : Tuple(Part, String)?
    OTHERS.each { |token| (rest = const(token, input)) && (return {OTHER, rest}) }
    group(input) || text(input)
  end

  private def self.group(input : String) : Tuple(Part, String)?
    return unless rest = const("(", input)
    members, rest = union(rest)
    (rest = const(")", rest)) ? {Part.new(members: members), rest} : nil
  end

  private def self.term(input : String) : Parsed?
    return unless found = base(input)
    part, rest = found
    parts, rest = union(rest)
    {[part] + parts, rest}
  end

  private def self.union(input : String) : Parsed
    if found = term(input)
      parts, rest = found
      if after = const("|", rest)
        more, after = union(after)
        return {parts + more, after}
      end
      return {parts, rest}
    end
    {[] of Part, input}
  end
end
