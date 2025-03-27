module IdentityTijuana
  class MergeRecord < ReadWrite
    self.table_name = 'merge_records'

    validates :join_id, presence: true
    validates :name, presence: true
    validates :value, presence: true
    validates :merge_id, presence: true
  end
end
