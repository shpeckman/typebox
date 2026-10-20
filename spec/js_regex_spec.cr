# spec/js_regex_spec.cr
require "./spec_helper"

describe TypeBox::JsRegex do
  it "keeps class escapes ASCII like JavaScript" do
    TypeBox::JsRegex.test("^\\d$", "٣", "u").should be_false
    TypeBox::JsRegex.test("^\\w+$", "é", "u").should be_false
    TypeBox::JsRegex.test("^\\s$", " ", "u").should be_true
    TypeBox::JsRegex.test("\\bfoo\\b", "é foo", "u").should be_true
  end

  it "matches dot outside line terminators only" do
    TypeBox::JsRegex.test("^.$", "\n", "u").should be_false
    TypeBox::JsRegex.test("^.$", "👍", "u").should be_true
  end

  it "anchors $ at the end of input" do
    TypeBox::JsRegex.test("^a$", "a\n", "u").should be_false
  end

  it "supports unicode properties and escapes" do
    TypeBox::JsRegex.test("^\\p{L}+$", "日本", "u").should be_true
    TypeBox::JsRegex.test("^\\p{Script=Greek}$", "α", "u").should be_true
    TypeBox::JsRegex.test("^\\u{1F44D}$", "👍", "u").should be_true
  end

  it "handles empty classes" do
    TypeBox::JsRegex.test("[]", "a", "u").should be_false
    TypeBox::JsRegex.test("^[^]$", "\n", "u").should be_true
  end

  it "reports invalid sources" do
    TypeBox::JsRegex.valid?("(", "u").should be_false
    TypeBox::JsRegex.valid?("a|b", "u").should be_true
  end
end
