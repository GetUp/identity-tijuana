module IdentityTijuana
  class Tagging < ReadWrite
    self.table_name = 'taggings'
    belongs_to :tag
    belongs_to :taggable, polymorphic: true
  end
end
