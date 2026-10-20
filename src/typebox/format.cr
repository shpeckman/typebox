# src/typebox/format.cr
require "uri"

module TypeBox::Format
  alias Check = Proc(String, Bool)

  DAYS          = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  DATE          = "^(\\d\\d\\d\\d)-(\\d\\d)-(\\d\\d)$"
  TIME          = "^(\\d\\d):(\\d\\d):(\\d\\d)(?:\\.\\d+)?(?:([Zz])|([+-])(\\d\\d):(\\d\\d))?$"
  DURATION      = "^P((\\d+Y(\\d+M(\\d+D)?)?|\\d+M(\\d+D)?|\\d+D)(T(\\d+H(\\d+M(\\d+S)?)?|\\d+M(\\d+S)?|\\d+S))?|T(\\d+H(\\d+M(\\d+S)?)?|\\d+M(\\d+S)?|\\d+S)|\\d+W)$"
  EMAIL         = "^(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*|\"(?:[^\"\\\\]|\\\\[\\x20-\\x7e])*\")@(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*|\\[(?:IPv6:[a-f0-9:]+|(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(?:\\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3})\\])$"
  IDN_EMAIL     = "^(?:[A-Za-z0-9!#$%&'*+\\/=?^_`{|}~\\u{0080}-\\u{10FFFF}-]+(?:\\.[A-Za-z0-9!#$%&'*+\\/=?^_`{|}~\\u{0080}-\\u{10FFFF}-]+)*|\"(?:[^\"\\\\]|\\\\.)*\")@[\\p{L}\\p{N}](?:[\\p{L}\\p{N}-]{0,62})(?<!-)(?:\\.[\\p{L}\\p{N}](?:[\\p{L}\\p{N}-]{0,62})(?<!-))*$"
  IPV4          = "^(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)$"
  IPV6          = "^(?:(?:(?:[0-9a-f]{1,4}:){6}|::(?:[0-9a-f]{1,4}:){5}|(?:[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){4}|(?:(?:[0-9a-f]{1,4}:)?[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){3}|(?:(?:[0-9a-f]{1,4}:){0,2}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){2}|(?:(?:[0-9a-f]{1,4}:){0,3}[0-9a-f]{1,4})?::[0-9a-f]{1,4}:|(?:(?:[0-9a-f]{1,4}:){0,4}[0-9a-f]{1,4})?::)(?:[0-9a-f]{1,4}:[0-9a-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4})?::[0-9a-f]{1,4}|(?:(?:[0-9a-f]{1,4}:){0,6}[0-9a-f]{1,4})?::)$"
  POINTER       = "^(?:\\/(?:[^~/]|~0|~1)*)*$"
  POINTER_URI   = "^#(?:\\/(?:[a-z0-9_\\-.!$&'()*+,;:=@]|%[0-9a-f]{2}|~0|~1)*)*$"
  RELATIVE      = "^(?:0|[1-9][0-9]*)(?:#|(?:\\/(?:[^~/]|~0|~1)*)*)$"
  URI_TEMPLATE  = "^(?:(?:[^\\x00-\\x20\"<>%\\\\^`{|}\\x7f]|%[0-9a-f]{2})|\\{[+#./;?&=,!@|]?(?:[a-z0-9_]|%[0-9a-f]{2})+(?:\\.(?:[a-z0-9_]|%[0-9a-f]{2})+)*(?::[1-9]\\d{0,3}|\\*)?(?:,(?:[a-z0-9_]|%[0-9a-f]{2})+(?:\\.(?:[a-z0-9_]|%[0-9a-f]{2})+)*(?::[1-9]\\d{0,3}|\\*)?)*\\})*$"
  UUID          = "^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$"
  URI           = "^[a-z][a-z0-9+\\-.]*:(?:\\/\\/(?:(?:[-a-z0-9._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\\[(?:(?:(?:[\\da-f]{1,4}:){6}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|::(?:[\\da-f]{1,4}:){5}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){4}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,1}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){3}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,2}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){2}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,3}[\\da-f]{1,4})?::[\\da-f]{1,4}:(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,4}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,5}[\\da-f]{1,4})?::[\\da-f]{1,4}|(?:(?:[\\da-f]{1,4}:){0,6}[\\da-f]{1,4})?::)|v[0-9a-f]+\\.[-a-z0-9._~!$&'()*+,;=:]+)\\]|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)|(?:[-a-z0-9._~!$&'()*+,;=]|%[0-9a-f]{2})*)(?::\\d*)?(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*|\\/(?:(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?(?:\\?(?:[-a-z0-9._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?(?:#(?:[-a-z0-9._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?$"
  URI_REFERENCE = "^(?:[a-z][a-z0-9+\\-.]*:(?:\\/\\/(?:(?:[-a-z0-9._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\\[(?:(?:(?:[\\da-f]{1,4}:){6}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|::(?:[\\da-f]{1,4}:){5}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){4}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,1}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){3}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,2}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){2}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,3}[\\da-f]{1,4})?::[\\da-f]{1,4}:(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,4}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,5}[\\da-f]{1,4})?::[\\da-f]{1,4}|(?:(?:[\\da-f]{1,4}:){0,6}[\\da-f]{1,4})?::)|v[0-9a-f]+\\.[-a-z0-9._~!$&'()*+,;=:]+)\\]|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)|(?:[-a-z0-9._~!$&'()*+,;=]|%[0-9a-f]{2})*)(?::\\d*)?(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*|\\/(?:(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:\\/\\/(?:(?:[-a-z0-9._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\\[(?:(?:(?:[\\da-f]{1,4}:){6}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|::(?:[\\da-f]{1,4}:){5}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){4}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,1}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){3}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,2}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:){2}(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,3}[\\da-f]{1,4})?::[\\da-f]{1,4}:(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,4}[\\da-f]{1,4})?::(?:[\\da-f]{1,4}:[\\da-f]{1,4}|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d))|(?:(?:[\\da-f]{1,4}:){0,5}[\\da-f]{1,4})?::[\\da-f]{1,4}|(?:(?:[\\da-f]{1,4}:){0,6}[\\da-f]{1,4})?::)|v[0-9a-f]+\\.[-a-z0-9._~!$&'()*+,;=:]+)\\]|(?:(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)|(?:[-a-z0-9._~!$&'()*+,;=]|%[0-9a-f]{2})*)(?::\\d*)?(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*|\\/(?:(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:[-a-z0-9._~!$&'()*+,;=@]|%[0-9a-f]{2})+(?:\\/(?:[-a-z0-9._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?)(?:\\?(?:[-a-z0-9._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?(?:#(?:[-a-z0-9._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?$"
  SPECIAL       = {"http", "https", "ws", "wss", "ftp", "file"}

  @@formats = {} of String => Check

  def self.set(name : String, &check : String -> Bool) : Nil
    @@formats[name] = check
  end

  def self.get(name : String) : Check?
    @@formats[name]?
  end

  def self.has?(name : String) : Bool
    @@formats.has_key?(name)
  end

  def self.entries : Array(Tuple(String, Check))
    @@formats.to_a
  end

  def self.clear : Nil
    @@formats.clear
  end

  def self.test(name : String, value : String) : Bool
    check = @@formats[name]?
    check ? check.call(value) : true
  end

  def self.reset : Nil
    clear
    set("date-time") { |value| date_time?(value) }
    set("date") { |value| date?(value) }
    set("duration") { |value| JsRegex.test(DURATION, value) }
    set("email") { |value| JsRegex.test(EMAIL, value, "i") }
    set("hostname") { |value| Idna.hostname?(value) }
    set("idn-email") { |value| JsRegex.test(IDN_EMAIL, value.unicode_normalize(:nfc), "iu") }
    set("idn-hostname") { |value| Idna.idn_hostname?(value) }
    set("ipv4") { |value| JsRegex.test(IPV4, value) }
    set("ipv6") { |value| JsRegex.test(IPV6, value, "i") }
    set("iri-reference") { |value| iri_reference?(value) }
    set("iri") { |value| iri?(value) }
    set("json-pointer-uri-fragment") { |value| JsRegex.test(POINTER_URI, value, "i") }
    set("json-pointer") { |value| JsRegex.test(POINTER, value) }
    set("regex") { |value| JsRegex.valid?(value, "u") }
    set("relative-json-pointer") { |value| JsRegex.test(RELATIVE, value) }
    set("time") { |value| time?(value) }
    set("uri-reference") { |value| JsRegex.test(URI_REFERENCE, value, "i") }
    set("uri-template") { |value| JsRegex.test(URI_TEMPLATE, value, "i") }
    set("uri") { |value| JsRegex.test(URI, value, "i") }
    set("url") { |value| url?(value) }
    set("uuid") { |value| JsRegex.test(UUID, value, "i") }
  end

  def self.date?(value : String) : Bool
    match = JsRegex.compile(DATE).match(value)
    return false unless match
    year = match[1].to_i
    month = match[2].to_i
    day = match[3].to_i
    leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    1 <= month <= 12 && 1 <= day && day <= (month == 2 && leap ? 29 : DAYS[month])
  end

  def self.time?(value : String, strict_time_zone : Bool = true) : Bool
    match = JsRegex.compile(TIME).match(value)
    return false unless match
    return false if strict_time_zone && match[4]?.nil? && match[5]?.nil?
    hour = match[1].to_i
    minute = match[2].to_i
    second = match[3].to_i
    return false if hour > 23 || minute > 59 || second > 60
    if match[5]?
      return false if match[6].to_i > 23 || match[7].to_i > 59
    end
    return true if second < 60
    sign = match[5]? == "-" ? -1 : 1
    offset_hours = (match[6]? || "0").to_i
    offset_minutes = (match[7]? || "0").to_i
    total = (hour * 60 + minute) - sign * (offset_hours * 60 + offset_minutes)
    (total % 1440 + 1440) % 1440 == 1439
  end

  def self.date_time?(value : String) : Bool
    parts = value.split(/[Tt]/, remove_empty: false)
    parts.size == 2 && date?(parts[0]) && time?(parts[1])
  end

  def self.url?(value : String) : Bool
    can_parse?(value)
  end

  def self.iri?(value : String) : Bool
    return false if value.each_char.any? { |char| char.ord <= 0x20 || "<>^`{|}\\".includes?(char) }
    return false if JsRegex.test("%(?![0-9a-fA-F]{2})", value)
    narrowed = Guard.js_length(value) < 2048 ? value.sub(/\[[vV][0-9a-fA-F]+\.[^\]]+\]/, "[::1]") : value
    can_parse?(narrowed)
  end

  def self.iri_reference?(value : String) : Bool
    return false if JsRegex.test("[\\x00-\\x20\\x7F\\\\]|%(?![0-9a-fA-F]{2})", value)
    return false if JsRegex.test("^[a-zA-Z][a-zA-Z0-9+\\-.]*\\/\\/", value)
    return can_parse?(value) if value.matches?(/\A[a-zA-Z][a-zA-Z0-9+\-.]*:/)
    return can_parse?("http:#{value}") if value.starts_with?("//")
    true
  end

  private def self.can_parse?(value : String) : Bool
    trimmed = value.strip { |char| char.ord <= 0x20 }
    return false unless match = trimmed.match(/\A([a-zA-Z][a-zA-Z0-9+\-.]*):(.*)\z/m)
    scheme = match[1].downcase
    rest = match[2]
    return true unless SPECIAL.includes?(scheme)
    authority = rest.lstrip("/\\")
    host_port = authority.split(/[\/\\?#]/, 2).first
    host_port = host_port.rpartition('@').last
    return scheme == "file" if host_port.empty?
    if host_port.starts_with?('[')
      close = host_port.index(']')
      return false unless close && JsRegex.test(IPV6, host_port[1...close], "i")
      port = host_port[(close + 1)..]
      return port.empty? || (port.starts_with?(':') && valid_port?(port[1..]))
    end
    host, _, port = host_port.partition(':')
    return false if host.empty? && scheme != "file"
    return false if host.each_char.any? { |char| " #%/<>?@[\\]^|".includes?(char) || char.ord < 0x20 || char.ord == 0x7F }
    port.empty? || valid_port?(port)
  end

  private def self.valid_port?(port : String) : Bool
    return true if port.empty?
    number = port.each_char.all?(&.ascii_number?) ? port.to_u64? : nil
    !number.nil? && number <= 65535
  end

  reset
end
