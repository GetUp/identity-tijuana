class CustomFieldKey < ApplicationRecord
  include ReadWriteIdentity
  attr_accessor :audit_data
  has_many :custom_fields
  has_many :members, through: :custom_fields
end
