module IdentityTijuana
  class Transaction < ReadWrite
    self.table_name = 'transactions'
    belongs_to :donation, optional: true
  end
end
