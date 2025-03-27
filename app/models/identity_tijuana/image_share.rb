module IdentityTijuana
  class ImageShare < ReadWrite
    self.table_name = 'image_shares'

    belongs_to :user
  end
end
