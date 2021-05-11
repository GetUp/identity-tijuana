module ExternalSystems::IdentityTijuana
  class Blast < ApplicationRecord
    include ReadWrite
    self.table_name = 'blasts'
  end
end
