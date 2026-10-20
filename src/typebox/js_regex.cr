# src/typebox/js_regex.cr
module TypeBox::JsRegex
  WORD        = "A-Za-z0-9_"
  DIGIT       = "0-9"
  SPACE       = "\\x{9}-\\x{d}\\x{20}\\x{a0}\\x{1680}\\x{2000}-\\x{200a}\\x{2028}\\x{2029}\\x{202f}\\x{205f}\\x{3000}\\x{feff}"
  NOT_DIGIT   = "\\x{0}-\\x{2f}\\x{3a}-\\x{d7ff}\\x{e000}-\\x{10ffff}"
  NOT_WORD    = "\\x{0}-\\x{2f}\\x{3a}-\\x{40}\\x{5b}-\\x{5e}\\x{60}\\x{7b}-\\x{d7ff}\\x{e000}-\\x{10ffff}"
  NOT_SPACE   = "\\x{0}-\\x{8}\\x{e}-\\x{1f}\\x{21}-\\x{9f}\\x{a1}-\\x{167f}\\x{1681}-\\x{1fff}\\x{200b}-\\x{2027}\\x{202a}-\\x{202e}\\x{2030}-\\x{205e}\\x{2060}-\\x{2fff}\\x{3001}-\\x{d7ff}\\x{e000}-\\x{fefe}\\x{ff00}-\\x{10ffff}"
  ANY         = "\\x{0}-\\x{d7ff}\\x{e000}-\\x{10ffff}"
  ASCII       = "\\x{0}-\\x{7f}"
  NOT_ASCII   = "\\x{80}-\\x{d7ff}\\x{e000}-\\x{10ffff}"
  DOT         = "[^\\n\\r\\x{2028}\\x{2029}]"
  BOUNDARY    = "(?:(?<=[#{WORD}])(?![#{WORD}])|(?<![#{WORD}])(?=[#{WORD}]))"
  NO_BOUNDARY = "(?:(?<=[#{WORD}])(?=[#{WORD}])|(?<![#{WORD}])(?![#{WORD}]))"
  NEVER       = "(?!)"

  @@cache = {} of Tuple(String, String) => Regex

  def self.compile(source : String, flags : String = "") : Regex
    key = {source, flags}
    @@cache[key] ||= begin
      options = flags.includes?('m') ? Regex::Options::MULTILINE_ONLY : Regex::Options::DOLLAR_ENDONLY
      options |= Regex::Options::IGNORE_CASE if flags.includes?('i')
      Regex.new(translate(source, flags.includes?('s')), options)
    end
  end

  def self.valid?(source : String, flags : String = "") : Bool
    compile(source, flags)
    true
  rescue ArgumentError
    false
  end

  def self.test(source : String, value : String, flags : String = "") : Bool
    compile(source, flags).matches?(value)
  end

  def self.translate(source : String, dot_all : Bool = false) : String
    chars = source.chars
    String.build do |io|
      index = 0
      in_class = false
      while index < chars.size
        char = chars[index]
        if char == '\\'
          index = escape(chars, index + 1, in_class, io)
          next
        end
        if in_class
          in_class = false if char == ']'
          io << char
          index += 1
          next
        end
        case char
        when '['
          if chars[index + 1]? == ']'
            io << NEVER
            index += 2
          elsif chars[index + 1]? == '^' && chars[index + 2]? == ']'
            io << '[' << ANY << ']'
            index += 3
          else
            in_class = true
            io << '['
            if chars[index + 1]? == '^'
              io << '^'
              index += 1
            end
            index += 1
          end
        when '.'
          io << (dot_all ? "[#{ANY}]" : DOT)
          index += 1
        else
          io << char
          index += 1
        end
      end
    end
  end

  private def self.escape(chars : Array(Char), index : Int32, in_class : Bool, io : IO) : Int32
    char = chars[index]?
    unless char
      io << "\\\\"
      return index
    end
    case char
    when 'd' then io << (in_class ? DIGIT : "[#{DIGIT}]")
    when 'D' then io << (in_class ? NOT_DIGIT : "[#{NOT_DIGIT}]")
    when 'w' then io << (in_class ? WORD : "[#{WORD}]")
    when 'W' then io << (in_class ? NOT_WORD : "[#{NOT_WORD}]")
    when 's' then io << (in_class ? SPACE : "[#{SPACE}]")
    when 'S' then io << (in_class ? NOT_SPACE : "[#{NOT_SPACE}]")
    when 'b' then io << (in_class ? "\\x{8}" : BOUNDARY)
    when 'B' then io << (in_class ? "B" : NO_BOUNDARY)
    when '0'
      io << "\\x{0}"
    when 'x'
      hex = chars[index + 1, 2]?.try(&.join)
      if hex && hex.size == 2 && hex.each_char.all?(&.hex?)
        io << "\\x{" << hex << '}'
        return index + 3
      end
      io << 'x'
    when 'u'
      return unicode_escape(chars, index + 1, in_class, io)
    when 'p', 'P'
      if chars[index + 1]? == '{' && (close = chars.index('}', index + 2))
        property(char == 'P', chars[(index + 2)...close].join, in_class, io)
        return close + 1
      end
      io << char
    when '/'
      io << '/'
    else
      io << '\\' << char
    end
    index + 1
  end

  private def self.unicode_escape(chars : Array(Char), index : Int32, in_class : Bool, io : IO) : Int32
    if chars[index]? == '{'
      if close = chars.index('}', index + 1)
        code_point(chars[(index + 1)...close].join.to_i(16), in_class, io)
        return close + 1
      end
      io << 'u'
      return index
    end
    hex = chars[index, 4]?.try(&.join)
    unless hex && hex.size == 4 && hex.each_char.all?(&.hex?)
      io << 'u'
      return index
    end
    value = hex.to_i(16)
    if 0xD800 <= value <= 0xDBFF && chars[index + 4]? == '\\' && chars[index + 5]? == 'u'
      low_hex = chars[index + 6, 4]?.try(&.join)
      if low_hex && low_hex.size == 4 && low_hex.each_char.all?(&.hex?) && 0xDC00 <= (low = low_hex.to_i(16)) <= 0xDFFF
        code_point(0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00), in_class, io)
        return index + 10
      end
    end
    code_point(value, in_class, io)
    index + 4
  end

  private def self.code_point(value : Int32, in_class : Bool, io : IO) : Nil
    if 0xD800 <= value <= 0xDFFF
      io << NEVER unless in_class
    else
      io << "\\x{" << value.to_s(16) << '}'
    end
  end

  private def self.property(negated : Bool, name : String, in_class : Bool, io : IO) : Nil
    if name == "ASCII" || name == "Any"
      range = name == "ASCII" ? (negated ? NOT_ASCII : ASCII) : (negated ? "" : ANY)
      io << (in_class ? range : (range.empty? ? NEVER : "[#{range}]"))
      return
    end
    value = name.partition('=').last.presence || name
    io << (negated ? "\\P{" : "\\p{") << value << '}'
  end
end
