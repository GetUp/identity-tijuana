module IdentityTijuana
  class Postcode < ReadWrite
    self.table_name = 'postcodes'
    has_many :users, dependent: nil
  end
end
