require 'identity_tijuana/application_record'
require 'identity_tijuana/readwrite'

module ExternalSystems::IdentityTijuana
  class Campaign < ApplicationRecord
    include ReadWrite
    self.table_name = 'campaigns'
    validates :name, length: { maximum: 64, minimum: 3 }
    validates_presence_of :accounts_key, on: :create
    alias_attribute :pillar, :accounts_key
  end
end
