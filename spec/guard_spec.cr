# spec/guard_spec.cr
require "./spec_helper"

describe TypeBox::Guard do
  it "orders keys like JavaScript objects" do
    TypeBox::Guard.keys(json(%({"b":1,"10":2,"a":3,"2":4,"01":5}))).should eq ["2", "10", "b", "a", "01"]
    TypeBox::Guard.keys(json(%([1,2]))).should eq ["0", "1"]
  end

  it "formats numbers like Number#toString" do
    TypeBox::Guard.js_number(1.0).should eq "1"
    TypeBox::Guard.js_number(1.5).should eq "1.5"
    TypeBox::Guard.js_number(1e21).should eq "1e+21"
    TypeBox::Guard.js_number(1e-7).should eq "1e-7"
    TypeBox::Guard.js_number(123456789012345680000.0).should eq "123456789012345680000"
    TypeBox::Guard.js_number(-0.0).should eq "0"
  end

  it "compares with strict equality semantics" do
    TypeBox::Guard.strict_equal?(json("1"), json("1.0")).should be_true
    TypeBox::Guard.strict_equal?(json("1"), json(%("1"))).should be_false
    TypeBox::Guard.strict_equal?(nil, nil).should be_true
    TypeBox::Guard.strict_equal?(json("null"), nil).should be_false
  end

  it "compares structurally with deep equality" do
    TypeBox::Guard.deep_equal?(json(%({"a":[1,2]})), json(%({"a":[1,2.0]}))).should be_true
    TypeBox::Guard.deep_equal?(json("{}"), json("[]")).should be_false
  end

  it "measures UTF-16 length and graphemes" do
    TypeBox::Guard.js_length("👍").should eq 2
    TypeBox::Guard.grapheme_count("👍a").should eq 2
  end

  it "checks multiples with a tolerance" do
    TypeBox::Guard.multiple_of?(json("0.3"), json("0.1")).should be_true
    TypeBox::Guard.multiple_of?(json("7"), json("2")).should be_false
  end
end
