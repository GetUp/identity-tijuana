module IdentityTijuana
  class Tag < ReadWrite
    self.table_name = 'tags'
    has_many :taggings, dependent: nil
    has_many :users, through: :taggings
  end
end
