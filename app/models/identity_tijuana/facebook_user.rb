module IdentityTijuana
  class FacebookUser < ReadWrite
    self.table_name = 'facebook_users'

    validates :facebook_id, :user_id, presence: true
  end
end
