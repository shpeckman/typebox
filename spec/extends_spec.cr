# spec/extends_spec.cr
require "./spec_helper"

private def relation(left : TypeBox::Schema, right : TypeBox::Schema) : TypeBox::Extends::Result
  TypeBox::Extends.check(left, right)
end

describe TypeBox::Extends do
  it "relates scalars" do
    relation(T.literal("a"), T.string).should eq TypeBox::Extends::Result::True
    relation(T.string, T.literal("a")).should eq TypeBox::Extends::Result::False
    relation(T.integer, T.number).should eq TypeBox::Extends::Result::True
    relation(T.number, T.integer).should eq TypeBox::Extends::Result::False
    relation(T.never, T.string).should eq TypeBox::Extends::Result::True
    relation(T.any, T.string).should eq TypeBox::Extends::Result::Union
    relation(T.unsafe(json(%({"type":"string"}))), T.unknown).should eq TypeBox::Extends::Result::True
  end

  it "relates unions" do
    relation(T.union([T.literal("a"), T.literal("b")]), T.string).should eq TypeBox::Extends::Result::True
    relation(T.string, T.union([T.number, T.string])).should eq TypeBox::Extends::Result::True
    relation(T.union([T.string, T.number]), T.string).should eq TypeBox::Extends::Result::False
  end

  it "relates objects structurally" do
    wide = T.object({a: T.string})
    narrow = T.object({a: T.string, b: T.number})
    relation(narrow, wide).should eq TypeBox::Extends::Result::True
    relation(wide, narrow).should eq TypeBox::Extends::Result::False
    relation(T.object({a: T.optional(T.string)}), wide).should eq TypeBox::Extends::Result::False
    relation(wide, T.object({a: T.optional(T.string)})).should eq TypeBox::Extends::Result::True
  end

  it "relates arrays respecting immutability" do
    relation(T.array(T.literal(1)), T.array(T.number)).should eq TypeBox::Extends::Result::True
    relation(T.immutable(T.array(T.number)), T.array(T.number)).should eq TypeBox::Extends::Result::False
    relation(T.array(T.number), T.immutable(T.array(T.number))).should eq TypeBox::Extends::Result::True
  end

  it "relates tuples and functions" do
    relation(T.tuple([T.string, T.number]), T.array(T.union([T.string, T.number]))).should eq TypeBox::Extends::Result::True
    relation(T.tuple([T.string]), T.tuple([T.string, T.number])).should eq TypeBox::Extends::Result::False
    relation(T.function([T.string], T.number), T.function([T.literal("a")], T.void)).should eq TypeBox::Extends::Result::True
    relation(T.function([T.literal("a")], T.number), T.function([T.string], T.number)).should eq TypeBox::Extends::Result::False
  end
end

describe TypeBox::Evaluate do
  it "compares types as sets" do
    TypeBox::Evaluate.compare(T.literal("a"), T.string).should eq TypeBox::Evaluate::Comparison::LeftInside
    TypeBox::Evaluate.compare(T.string, T.literal("a")).should eq TypeBox::Evaluate::Comparison::RightInside
    TypeBox::Evaluate.compare(T.string, T.string).should eq TypeBox::Evaluate::Comparison::Equal
    TypeBox::Evaluate.compare(T.string, T.number).should eq TypeBox::Evaluate::Comparison::Disjoint
  end

  it "sorts by priority from narrowest to broadest" do
    sorted = TypeBox::Evaluate.priority([T.string, T.literal("a"), T.number])
    sorted.map(&.kind).should eq ["Literal", "String", "Number"]
  end

  it "distributes intersections over unions" do
    evaluated = TypeBox::Evaluate.intersect([T.union([T.literal("a"), T.literal(1)]), T.string])
    compact(evaluated).should eq %({"type":"string","const":"a"})
  end
end
