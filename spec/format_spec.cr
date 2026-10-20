# spec/format_spec.cr
require "./spec_helper"

private def format?(name : String, value : String) : Bool
  TypeBox::Format.test(name, value)
end

describe TypeBox::Format do
  it "checks dates and times" do
    format?("date", "2024-02-29").should be_true
    format?("date", "2023-02-29").should be_false
    format?("time", "10:20:30Z").should be_true
    format?("time", "23:59:60Z").should be_true
    format?("time", "10:20:30").should be_false
    format?("date-time", "2024-01-01T10:20:30.5+01:00").should be_true
    format?("duration", "P1DT2H").should be_true
  end

  it "checks network formats" do
    format?("email", "A@b.co").should be_true
    format?("ipv4", "256.1.1.1").should be_false
    format?("ipv6", "::1").should be_true
    format?("hostname", "-bad-.com").should be_false
    format?("hostname", "xn--bcher-kva.example").should be_true
    format?("idn-hostname", "bücher.example").should be_true
    format?("uri", "urn:isbn:123").should be_true
    format?("uri", "not a uri").should be_false
    format?("url", "http://example.com/x?y=1").should be_true
    format?("uuid", "550E8400-e29b-41d4-a716-446655440000").should be_true
  end

  it "checks pointers and regular expressions" do
    format?("json-pointer", "/a~1b").should be_true
    format?("json-pointer", "a").should be_false
    format?("relative-json-pointer", "0#").should be_true
    format?("regex", "^a+$").should be_true
    format?("regex", "(").should be_false
  end

  it "passes unknown formats" do
    format?("nope", "anything").should be_true
  end

  it "registers custom formats" do
    TypeBox::Format.set("even", &.size.even?)
    TypeBox::Value.check(T.string(format: "even"), json(%("ab"))).should be_true
    TypeBox::Value.check(T.string(format: "even"), json(%("abc"))).should be_false
  ensure
    TypeBox::Format.reset
  end
end
