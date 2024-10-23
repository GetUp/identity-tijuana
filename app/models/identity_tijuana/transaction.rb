module IdentityTijuana
  class Transaction < ReadWrite
    self.table_name = 'transactions'
    belongs_to :donation, optional: false

    scope :updated_transactions_all, ->(last_updated_at, last_id, exclude_from) {
      where('updated_at > ? OR (updated_at = ? AND id > ?)',
            last_updated_at, last_updated_at, last_id)
        .where(updated_at: ...exclude_from)
    }
  end
end
