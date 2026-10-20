# spec/type_spec.cr
require "./spec_helper"

describe TypeBox::Type do
  it "builds scalar schemas with options" do
    compact(T.string(minLength: 1)).should eq %({"type":"string","minLength":1})
    compact(T.number).should eq %({"type":"number"})
    compact(T.integer).should eq %({"type":"integer"})
    compact(T.boolean).should eq %({"type":"boolean"})
    compact(T.null).should eq %({"type":"null"})
    compact(T.void).should eq %({"type":"void"})
    compact(T.undefined).should eq %({"type":"undefined"})
    compact(T.never).should eq %({"not":{}})
    compact(T.any).should eq "{}"
    compact(T.unknown).should eq "{}"
  end

  it "records kinds" do
    T.string.kind.should eq "String"
    T.object({a: T.string}).kind.should eq "Object"
    T.unsafe(json(%({"type":"string"}))).kind.should be_nil
  end

  it "builds literals and enums" do
    compact(T.literal(1.5)).should eq %({"type":"number","const":1.5})
    compact(T.literal("a")).should eq %({"type":"string","const":"a"})
    compact(T.literal(true)).should eq %({"type":"boolean","const":true})
    compact(T.enum(["a", "b", 1])).should eq %({"enum":["a","b",1]})
  end

  it "builds arrays and tuples" do
    compact(T.array(T.number, minItems: 1)).should eq %({"type":"array","items":{"type":"number"},"minItems":1})
    compact(T.tuple([T.string, T.number], description: "x")).should eq(
      %({"type":"array","additionalItems":false,"items":[{"type":"string"},{"type":"number"}],"minItems":2,"description":"x"}))
    compact(T.tuple([] of TypeBox::Schema)).should eq %({"type":"array","additionalItems":false,"items":[],"minItems":0})
  end

  it "builds objects with required keys from non-optional properties" do
    schema = T.object({a: T.optional(T.string), b: T.readonly(T.number)}, additionalProperties: false)
    compact(schema).should eq(
      %({"type":"object","required":["b"],"properties":{"a":{"type":"string"},"b":{"type":"number"}},"additionalProperties":false}))
  end

  it "orders integer-like property keys first" do
    compact(T.object({"b" => T.string, "1" => T.number})).should eq(
      %({"type":"object","required":["1","b"],"properties":{"1":{"type":"number"},"b":{"type":"string"}}}))
  end

  it "embeds schema options as child schemas" do
    compact(T.object({a: T.string}, additionalProperties: T.number)).should eq(
      %({"type":"object","required":["a"],"properties":{"a":{"type":"string"}},"additionalProperties":{"type":"number"}}))
  end

  it "builds unions, intersections and functions" do
    compact(T.union([T.string, T.number])).should eq %({"anyOf":[{"type":"string"},{"type":"number"}]})
    compact(T.intersect([T.object({a: T.string}), T.object({b: T.number})])).should eq(
      %({"allOf":[{"type":"object","required":["a"],"properties":{"a":{"type":"string"}}},{"type":"object","required":["b"],"properties":{"b":{"type":"number"}}}]}))
    compact(T.function([T.string], T.number)).should eq(
      %({"type":"function","parameters":[{"type":"string"}],"returnType":{"type":"number"}}))
  end

  it "builds records by key kind" do
    compact(T.record(T.string, T.number, minProperties: 1)).should eq(
      %({"type":"object","patternProperties":{"^.*$":{"type":"number"}},"minProperties":1}))
    compact(T.record(T.integer, T.number)).should eq(%({"type":"object","patternProperties":{"^-?(?:0|[1-9][0-9]*)$":{"type":"number"}}}))
    compact(T.record(T.number, T.null)).should eq(
      %({"type":"object","patternProperties":{"^-?(?:0|[1-9][0-9]*)(?:\\\\.[0-9]+)?$":{"type":"null"}}}))
    compact(T.record(T.string(pattern: "^[a-c]$"), T.null)).should eq(%({"type":"object","patternProperties":{"^[a-c]$":{"type":"null"}}}))
    compact(T.record(T.union([T.literal("x"), T.literal(1)]), T.string)).should eq(
      %({"type":"object","required":["1","x"],"properties":{"1":{"type":"string"},"x":{"type":"string"}}}))
    compact(T.record(T.boolean, T.null)).should eq(
      %({"type":"object","required":["true","false"],"properties":{"true":{"type":"null"},"false":{"type":"null"}}}))
    compact(T.record(T.enum(["a", "b"]), T.null)).should eq(
      %({"type":"object","required":["a","b"],"properties":{"a":{"type":"null"},"b":{"type":"null"}}}))
    T.record(T.literal("k"), T.null).kind.should eq "Object"
    T.record(T.string, T.null).kind.should eq "Record"
  end

  it "applies modifiers without changing the JSON" do
    schema = T.optional(T.readonly(T.string))
    schema.optional?.should be_true
    schema.readonly?.should be_true
    compact(schema).should eq %({"type":"string"})
    immutable = T.immutable(T.array(T.string))
    immutable.immutable?.should be_true
    T.unsafe(T.string).unsafe?.should be_true
  end

  it "adds and replaces options with with" do
    compact(T.with(T.string(minLength: 1), minLength: 2, description: "d")).should eq(
      %({"type":"string","minLength":2,"description":"d"}))
  end

  it "evaluates intersections of objects into one object" do
    evaluated = T.evaluate(T.intersect([T.object({a: T.string}), T.object({b: T.optional(T.number)})]))
    evaluated.kind.should eq "Object"
    compact(evaluated).should eq(%({"type":"object","required":["a"],"properties":{"a":{"type":"string"},"b":{"type":"number"}}}))
  end

  it "evaluates unions by dropping narrower members" do
    compact(T.evaluate(T.union([T.literal("a"), T.string]))).should eq %({"type":"string"})
    compact(T.evaluate(T.intersect([T.string, T.number]))).should eq %({"not":{}})
  end

  it "rejects invalid literal values" do
    expect_raises(ArgumentError) { T.literal(json("null")) }
  end
end
