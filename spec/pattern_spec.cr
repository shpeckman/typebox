# spec/pattern_spec.cr
require "./spec_helper"

private def decoded(pattern : String) : String?
  TypeBox::Pattern.key_type(pattern).try(&.to_json)
end

describe TypeBox::Pattern do
  it "maps the standard record keys" do
    decoded(TypeBox::Type::STRING_KEY).should eq %({"type":"string"})
    decoded(TypeBox::Type::INTEGER_KEY).should eq %({"type":"integer"})
    decoded(TypeBox::Type::NUMBER_KEY).should eq %({"type":"number"})
  end

  it "decodes finite patterns into literals" do
    decoded("^[a-c]$").should eq %({"type":"string","const":"[a-c]"})
    decoded("^(a|b)$").should eq %({"anyOf":[{"type":"string","const":"a"},{"type":"string","const":"b"}]})
    decoded("^x(1|2)$").should eq %({"anyOf":[{"type":"string","const":"x1"},{"type":"string","const":"x2"}]})
  end

  it "keeps non-finite patterns" do
    decoded("^a.*$").should be_nil
  end

  it "falls back to string for patterns it cannot parse" do
    decoded("abc").should eq %({"type":"string"})
    decoded("^(a$").should eq %({"type":"string"})
  end
end
