# src/typebox/settings.cr
module TypeBox::Settings
  @@max_errors = 8
  @@exact_optional_property_types = false
  @@union_priority_sort = true

  def self.max_errors : Int32
    @@max_errors
  end

  def self.max_errors=(value : Int32) : Int32
    @@max_errors = value
  end

  def self.exact_optional_property_types? : Bool
    @@exact_optional_property_types
  end

  def self.exact_optional_property_types=(value : Bool) : Bool
    @@exact_optional_property_types = value
  end

  def self.union_priority_sort? : Bool
    @@union_priority_sort
  end

  def self.union_priority_sort=(value : Bool) : Bool
    @@union_priority_sort = value
  end

  def self.reset : Nil
    @@max_errors = 8
    @@exact_optional_property_types = false
    @@union_priority_sort = true
  end
end
