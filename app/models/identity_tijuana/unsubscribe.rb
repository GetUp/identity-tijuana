module IdentityTijuana
  class Unsubscribe < ReadWrite
    self.table_name = 'unsubscribes'
    belongs_to :user
  end
end
