# spec/value_spec.cr
require "./spec_helper"

describe TypeBox::Value do
  user = T.object({
    a: T.string(minLength: 1),
    b: T.optional(T.number),
  }, additionalProperties: false)

  describe ".check" do
    it "validates builder schemas" do
      TypeBox::Value.check(user, json(%({"a":"x"}))).should be_true
      TypeBox::Value.check(user, json(%({"a":"x","b":"1"}))).should be_false
      TypeBox::Value.check(user, json(%({"a":""}))).should be_false
      TypeBox::Value.check(user, json(%({"a":"x","c":1}))).should be_false
    end

    it "validates plain JSON schemas including boolean schemas" do
      TypeBox::Value.check(json("false"), json("1")).should be_false
      TypeBox::Value.check(json("true"), json("1")).should be_true
      TypeBox::Value.check(json(%({"type":["string","null"]})), json("null")).should be_true
    end

    it "treats nil as undefined" do
      TypeBox::Value.check(T.undefined, nil).should be_true
      TypeBox::Value.check(T.null, nil).should be_false
      TypeBox::Value.check(T.object({a: T.optional(T.string)}), json(%({}))).should be_true
    end

    it "compares numbers like JavaScript" do
      TypeBox::Value.check(T.literal(1), json("1.0")).should be_true
      TypeBox::Value.check(T.integer, json("2.0")).should be_true
      TypeBox::Value.check(T.number(multipleOf: 0.1), json("0.3")).should be_true
    end

    it "counts string length in graphemes" do
      TypeBox::Value.check(T.string(maxLength: 1), json(%("👍"))).should be_true
      TypeBox::Value.check(T.string(minLength: 2), json(%("é"))).should be_false
    end

    it "detects duplicate items independent of key order" do
      schema = T.array(T.any, uniqueItems: true)
      TypeBox::Value.check(schema, json(%([{"a":1,"b":2},{"b":2,"a":1}]))).should be_false
      TypeBox::Value.check(schema, json(%([1,"1"]))).should be_true
    end

    it "resolves fragment references" do
      schema = json(%({"$defs":{"n":{"type":"number"}},"properties":{"x":{"$ref":"#/$defs/n"}}}))
      TypeBox::Value.check(schema, json(%({"x":1}))).should be_true
      TypeBox::Value.check(schema, json(%({"x":"1"}))).should be_false
      TypeBox::Value.check(json(%({"$ref":"#/nope"})), json("1")).should be_false
    end
  end

  describe ".errors" do
    it "reports errors in upstream order with en_US messages" do
      errors = TypeBox::Value.errors(user, json(%({"a":"","c":1})))
      errors.map(&.keyword).should eq ["boolean", "additionalProperties", "minLength"]
      errors.map(&.instance_path).should eq ["/c", "", "/a"]
      errors.map(&.schema_path).should eq ["#/additionalProperties", "#", "#/properties/a"]
      errors.map(&.message).should eq [
        "schema is false",
        "must not have additional properties",
        "must not have fewer than 1 characters",
      ]
      errors[1].params.should eq json(%({"additionalProperties":["c"]}))
    end

    it "serializes with TypeBox field names" do
      error = TypeBox::Value.errors(T.string, json("1")).first
      error.to_json.should eq %({"keyword":"type","schemaPath":"#","instancePath":"","params":{"type":"string"},"message":"must be string"})
    end

    it "reports required properties" do
      error = TypeBox::Value.errors(T.object({a: T.string, b: T.string}), json("{}")).first
      error.message.should eq "must have required properties a, b"
    end

    it "caps the error count with max_errors" do
      TypeBox::Settings.max_errors = 2
      TypeBox::Value.errors(T.array(T.string), json("[1,2,3,4]")).size.should eq 2
    ensure
      TypeBox::Settings.reset
    end

    it "uses the configured locale" do
      TypeBox::Locale.set(TypeBox::LocaleFunction.new { |error| "#{error.keyword}!" })
      TypeBox::Value.errors(T.string, json("1")).first.message.should eq "type!"
    ensure
      TypeBox::Locale.reset
    end
  end

  describe ".default" do
    it "fills missing properties from defaults" do
      schema = T.object({n: T.number(default: 0), s: T.optional(T.string(default: "x")), z: T.string})
      TypeBox::Value.default(schema, json("{}")).should eq json(%({"n":0,"s":"x"}))
    end

    it "uses the top-level default for undefined" do
      TypeBox::Value.default(T.number(default: 7), nil).should eq json("7")
      TypeBox::Value.default(T.number(default: 7), json("1")).should eq json("1")
    end

    it "clones object defaults" do
      schema = T.object({o: T.object(default: {k: 1})})
      first = TypeBox::Value.default(schema, json("{}")).not_nil!
      first["o"].as_h["k"] = JSON::Any.new(2_i64)
      TypeBox::Value.default(schema, json("{}")).should eq json(%({"o":{"k":1}}))
    end

    it "picks the first union variant that checks" do
      schema = T.union([T.object({a: T.number(default: 1)}), T.object({b: T.string(default: "b")})])
      TypeBox::Value.default(schema, json("{}")).should eq json(%({"a":1}))
    end
  end

  describe ".clean" do
    it "removes unknown properties" do
      TypeBox::Value.clean(user, json(%({"a":"x","c":1}))).should eq json(%({"a":"x"}))
    end

    it "keeps additional properties that pass" do
      schema = T.object({a: T.string}, additionalProperties: T.number)
      TypeBox::Value.clean(schema, json(%({"a":"x","n":1,"s":"y"}))).should eq json(%({"a":"x","n":1}))
    end

    it "evaluates intersections" do
      schema = T.intersect([T.object({a: T.string}), T.object({b: T.number})])
      TypeBox::Value.clean(schema, json(%({"a":"1","b":2,"c":3}))).should eq json(%({"a":"1","b":2}))
    end

    it "slices tuples" do
      TypeBox::Value.clean(T.tuple([T.string]), json(%(["a","b"]))).should eq json(%(["a"]))
    end

    it "prefers narrower union variants" do
      schema = T.union([T.object({a: T.string}), T.object({a: T.string, b: T.number})])
      TypeBox::Value.clean(schema, json(%({"a":"x","b":1,"c":2}))).should eq json(%({"a":"x","b":1}))
    end

    it "decodes custom record patterns like TypeBox" do
      schema = T.record(T.string(pattern: "^[a-c]$"), T.null)
      TypeBox::Value.clean(schema, json(%({"c":null,"[a-c]":null}))).should eq json(%({"[a-c]":null}))
    end
  end

  describe ".clone" do
    it "deep copies and drops unsafe keys" do
      source = json(%({"a":[1,{"b":2}],"__proto__":1,"constructor":2}))
      copy = TypeBox::Value.clone(source).not_nil!
      copy.should eq json(%({"a":[1,{"b":2}]}))
      copy["a"].as_a[1].as_h["b"] = JSON::Any.new(3_i64)
      source["a"][1]["b"].should eq json("2")
    end
  end
end
