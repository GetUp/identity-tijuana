module IdentityTijuana
  class Postcode < ReadWrite
    self.table_name = 'postcodes'
    has_many :users
  end
end
