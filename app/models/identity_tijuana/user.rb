module IdentityTijuana
  class User < ReadWrite
    self.table_name = 'users'
    has_many :donations
    has_many :taggings, -> { where(taggable_type: 'User') }, foreign_key: 'taggable_id'
    has_many :tags, through: :taggings
    belongs_to :postcode, optional: true

    scope :updated_users, -> (last_updated_at, last_id) {
      includes(:postcode)
      .includes(:taggings)
      .includes(:tags)
      .where('updated_at > ? or (updated_at = ? and id > ?)', last_updated_at, last_updated_at, last_id)
      .order('updated_at, id')
      .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_users_all, -> (last_updated_at, last_id) {
      where('updated_at > ? or (updated_at = ? and id > ?)',last_updated_at, last_updated_at, last_id)
    }

    def has_tag(tag_name)
      tags.where(name: tag_name).first != nil
    end
  end
end
class User < IdentityTijuana::User
end
