module IdentityTijuana
  class Transaction < ApplicationRecord
    include ReadWrite
    self.table_name = 'transactions'
    belongs_to :donation, optional: true
  end
end
