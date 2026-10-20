# src/typebox/format/idna.cr
module TypeBox::Format::Idna
  class PunycodeError < Exception
  end

  BASE         =  36_i64
  TMIN         =   1_i64
  TMAX         =  26_i64
  SKEW         =  38_i64
  DAMP         = 700_i64
  INITIAL_BIAS =  72_i64
  INITIAL_N    = 128_i64

  HYPHEN_PLACEMENT = "^(?!-).*(?<!-)$"
  NOT_RESERVED_ACE = "^(?!..--)"
  ASCII_LDH        = "^[a-zA-Z0-9-]*$"
  NON_ASCII        = "[^\\p{ASCII}]"
  ASCII_DIGIT      = "[0-9]"
  ARABIC_INDIC     = "[\\u{0660}-\\u{0669}]"
  EXT_ARABIC_INDIC = "[\\u{06f0}-\\u{06f9}]"
  COMMON_SEPARATOR = "[\\u{002e}\\u{002c}\\u{003a}\\u{002f}]"
  EURO_SEPARATOR   = "[\\u{002d}\\u{002b}]"
  MARK_NONSPACING  = "\\p{Mn}"
  MARK_SPACING     = "\\p{Mc}"
  COMBINING_MARK   = "[\\p{Mn}\\p{Mc}\\p{Me}]"
  LETTER           = "\\p{L}"
  NUMBER_DECIMAL   = "\\p{Nd}"
  SCRIPT_GREEK     = "\\p{Script=Greek}"
  SCRIPT_HEBREW    = "\\p{Script=Hebrew}"
  SCRIPT_JAPANESE  = "[\\p{Script=Hiragana}\\p{Script=Katakana}\\p{Script=Han}]"
  SCRIPT_ARABIC    = "[\\p{Script=Arabic}\\p{Script=Syriac}\\p{Script=Thaana}\\p{Script=Mandaic}]"
  VIRAMA           = "[\\u{094d}\\u{09cd}\\u{0a4d}\\u{0acd}\\u{0b4d}\\u{0bcd}\\u{0c4d}\\u{0ccd}\\u{0d3b}\\u{0d3c}\\u{0d4d}\\u{0dca}\\u{1b44}\\u{1baa}\\u{1bab}\\u{a9c0}\\u{11046}\\u{1107f}\\u{110b9}\\u{11133}\\u{11134}\\u{111c0}\\u{11235}\\u{1134d}\\u{11442}\\u{114c2}\\u{115bf}\\u{1163f}\\u{116b6}\\u{11c3f}\\u{11d44}\\u{11d45}]"
  DISALLOWED       = "[\\u{0640}\\u{07fa}\\u{302e}\\u{302f}\\u{3031}\\u{3032}\\u{3033}\\u{3034}\\u{3035}\\u{303b}]"
  CONTEXTO         = "[\\u{00b7}\\u{0375}\\u{05f3}\\u{05f4}\\u{200c}\\u{200d}\\u{30fb}]"
  PVALID           = "[\\u{00df}\\u{03c2}\\u{06fd}\\u{06fe}\\u{0f0b}\\u{3007}]"
  EUROPEAN_NUMBER  = [ASCII_DIGIT, EXT_ARABIC_INDIC].join('|')
  PERMITTED        = [LETTER, EURO_SEPARATOR, COMMON_SEPARATOR, NUMBER_DECIMAL, MARK_NONSPACING, MARK_SPACING, CONTEXTO, PVALID].join('|')
  RTL_ALLOWED      = {"R", "AL", "AN", "EN", "ES", "CS", "ET", "ON", "BN", "NSM"}
  LTR_ALLOWED      = {"L", "EN", "ES", "CS", "ET", "ON", "BN", "NSM"}
  RTL_CLASSES      = {"R", "AL", "AN"}

  def self.hostname?(value : String) : Bool
    length = Guard.js_length(value)
    return false if length == 0 || length > 253
    return false if value.ends_with?('.')
    value.split('.', remove_empty: false).all? { |label| ascii_label_length?(label) && (puny_label?(label) || ascii_label?(label)) }
  end

  def self.idn_hostname?(value : String) : Bool
    return false if value.empty? || value.includes?(' ')
    normalized = normalize(value)
    return false if Guard.js_length(normalized) > 253
    labels = normalized.split('.', remove_empty: false)
    bidi = labels.any? { |label| bidi_chars?(label) }
    labels.all? { |label| ascii_label_length?(label) && (puny_label?(label) || unicode_label?(label)) && (!bidi || satisfies_bidi?(label)) }
  end

  private def self.test(pattern : String, value : String) : Bool
    JsRegex.test(pattern, value, "u")
  end

  private def self.ascii_label_length?(value : String) : Bool
    length = Guard.js_length(value)
    length > 0 && length <= 63
  end

  private def self.ascii_label?(value : String) : Bool
    test(HYPHEN_PLACEMENT, value) && test(NOT_RESERVED_ACE, value) && test(ASCII_LDH, value)
  end

  private def self.ace_prefixed?(value : String) : Bool
    value.downcase.starts_with?("xn--")
  end

  private def self.puny_label?(value : String) : Bool
    return false unless ace_prefixed?(value)
    body = value[4..].downcase
    return false if body.rindex('-') == 0
    decoded = decode(body)
    return false unless test(NON_ASCII, decoded)
    unicode_label?(decoded)
  rescue PunycodeError
    false
  end

  private def self.normalize(value : String) : String
    mapped = String.build do |io|
      value.each_char { |char| io << (0xFF01 <= char.ord <= 0xFF5E ? (char.ord - 0xFEE0).chr : char) }
    end
    mapped.unicode_normalize(:nfc).each_char.reject { |char| ignored?(char.ord) }.join.gsub(/[\x{3002}\x{FF0E}\x{FF61}]/, ".")
  end

  private def self.ignored?(code : Int32) : Bool
    code == 0x00AD || code == 0x034F || (0x180B <= code <= 0x180D) || code == 0x200B || (0xFE00 <= code <= 0xFE0F) || (0xE0100 <= code <= 0xE01EF)
  end

  private def self.bidi_class(char : Char) : String
    text = char.to_s
    if test(EUROPEAN_NUMBER, text)
      "EN"
    elsif test(ARABIC_INDIC, text)
      "AN"
    elsif test(MARK_NONSPACING, text)
      "NSM"
    elsif test(SCRIPT_HEBREW, text)
      "R"
    elsif test(SCRIPT_ARABIC, text)
      "AL"
    elsif test(LETTER, text)
      "L"
    else
      "ON"
    end
  end

  private def self.bidi_chars?(value : String) : Bool
    if ace_prefixed?(value)
      begin
        return right_to_left?(decode(value[4..].downcase))
      rescue PunycodeError
        return false
      end
    end
    right_to_left?(value)
  end

  private def self.right_to_left?(value : String) : Bool
    value.each_char.any? { |char| RTL_CLASSES.includes?(bidi_class(char)) }
  end

  private def self.satisfies_bidi?(value : String) : Bool
    rtl = false
    allowed = LTR_ALLOWED
    saw_en = false
    saw_an = false
    first = true
    value.each_char do |char|
      klass = bidi_class(char)
      if first
        return false unless klass == "L" || klass == "R" || klass == "AL"
        rtl = klass == "R" || klass == "AL"
        allowed = rtl ? RTL_ALLOWED : LTR_ALLOWED
        first = false
      end
      return false unless allowed.includes?(klass)
      if klass == "EN"
        saw_en = true
      elsif klass == "AN"
        saw_an = true
      end
    end
    !(rtl && saw_en && saw_an)
  end

  private def self.unicode_label?(value : String) : Bool
    return false if test(NON_ASCII, value) && Guard.js_length(encode(value)) + 4 > 63
    return false if right_to_left?(value) && !satisfies_bidi?(value)
    chars = value.chars
    return false if chars.empty?
    return false if chars[0] == '-' || chars[-1] == '-'
    return false if chars[2..]?.try(&.join.starts_with?("--"))
    return false if test(COMBINING_MARK, chars[0].to_s)
    japanese = false
    chars.each_with_index do |char, index|
      text = char.to_s
      return false if test(DISALLOWED, text)
      return false unless test(PERMITTED, text)
      japanese = true if test(SCRIPT_JAPANESE, text)
      previous = index > 0 ? chars[index - 1] : nil
      following = chars[index + 1]?
      case char.ord
      when 0x00B7
        return false unless previous == 'l' && following == 'l'
      when 0x0375
        return false unless following && test(SCRIPT_GREEK, following.to_s)
      when 0x05F3, 0x05F4
        return false unless previous && test(SCRIPT_HEBREW, previous.to_s)
      when 0x200C
        return false if previous.nil? || (previous.ord < 0x80 && !test(VIRAMA, previous.to_s))
      when 0x200D
        return false unless previous && test(VIRAMA, previous.to_s)
      end
    end
    !(value.includes?('・') && !japanese)
  end

  private def self.adapt(delta : Int64, points : Int64, first : Bool) : Int64
    delta = first ? delta // DAMP : delta >> 1
    delta += delta // points
    k = 0_i64
    while delta > ((BASE - TMIN) * TMAX) >> 1
      delta = delta // (BASE - TMIN)
      k += BASE
    end
    k + ((BASE - TMIN + 1) * delta) // (delta + SKEW)
  end

  def self.decode(value : String) : String
    units = value.to_utf16
    output = [] of Int64
    n = INITIAL_N.to_i64
    i = 0_i64
    bias = INITIAL_BIAS.to_i64
    delimiter = units.rindex(0x2D_u16) || -1
    if delimiter > 0
      delimiter.times do |position|
        unit = units[position]
        raise PunycodeError.new if unit >= 128
        output << unit.to_i64
      end
    end
    cursor = delimiter < 0 ? 0 : delimiter + 1
    while cursor < units.size
      old = i
      w = 1_i64
      k = BASE.to_i64
      loop do
        raise PunycodeError.new if cursor >= units.size
        unit = units[cursor].to_i64
        cursor += 1
        digit = if 0x61 <= unit <= 0x7A
                  unit - 0x61
                elsif 0x30 <= unit <= 0x39
                  unit - 0x30 + 26
                else
                  raise PunycodeError.new
                end
        i += digit * w
        t = k <= bias ? TMIN : (k >= bias + TMAX ? TMAX : k - bias)
        break if digit < t
        w *= BASE - t
        k += BASE
      end
      length = output.size.to_i64 + 1
      bias = adapt(i - old, length, old == 0)
      n += i // length
      i %= length
      raise PunycodeError.new if n > 0x10FFFF || (0xD800 <= n <= 0xDFFF)
      output.insert(i.to_i, n)
      i += 1
    end
    String.build { |io| output.each { |code| io << code.to_i.chr } }
  end

  def self.encode(input : String) : String
    basic = input.each_char.select(&.ascii?).join
    result = basic.empty? ? [] of String : [basic, "-"]
    points = input.chars.map(&.ord.to_i64)
    n = INITIAL_N.to_i64
    delta = 0_i64
    bias = INITIAL_BIAS.to_i64
    handled = basic.size.to_i64
    while handled < points.size
      m = points.select { |point| point >= n }.min? || Int64::MAX
      delta += (m - n) * (handled + 1)
      n = m
      points.each do |point|
        delta += 1 if point < n
        next unless point == n
        q = delta
        k = BASE.to_i64
        loop do
          t = k <= bias ? TMIN : (k >= bias + TMAX ? TMAX : k - bias)
          break if q < t
          result << digit_char(t + (q - t) % (BASE - t))
          q = (q - t) // (BASE - t)
          k += BASE
        end
        result << digit_char(q)
        bias = adapt(delta, handled + 1, handled == basic.size)
        delta = 0_i64
        handled += 1
      end
      delta += 1
      n += 1
    end
    result.join
  end

  private def self.digit_char(digit : Int64) : String
    (digit < 26 ? (digit + 0x61) : (digit - 26 + 0x30)).to_i.chr.to_s
  end
end
