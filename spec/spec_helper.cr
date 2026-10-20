# spec/spec_helper.cr
require "spec"
require "../src/typebox"

T = TypeBox::Type

def json(text : String) : JSON::Any
  JSON.parse(text)
end

def compact(schema : TypeBox::Schema) : String
  schema.to_json
end
