module ExternalSystems::IdentityTijuana
  class Email < ApplicationRecord
    include ReadWrite
    self.table_name = 'emails'
  end
end
