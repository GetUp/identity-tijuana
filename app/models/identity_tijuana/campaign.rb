module IdentityTijuana
  class Campaign < ReadWrite
    self.table_name = 'campaigns'
    has_many :page_sequences
    has_many :pushes

    scope :deleted_campaigns, -> (last_updated_at, exclude_from) {
      where('deleted_at is not null and deleted_at >= ? and deleted_at < ?', last_updated_at, exclude_from)
        .order('deleted_at, id')
    }

    scope :updated_campaigns, -> (last_updated_at, last_id) {
      updated_campaigns_all(last_updated_at, last_id)
        .order('updated_at, id')
        .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_campaigns_all, -> (last_updated_at, last_id) {
      where('updated_at > ? or (updated_at = ? and id > ?)', last_updated_at, last_updated_at, last_id)
    }

    def import(sync_id)
      begin
        # The campaigns table in TJ maps onto the issues table in ID.
        issue = ::Issue.find_or_create_by(external_id: self.id.to_s, external_source: 'tijuana')
        issue.name = self.name
        issue.save!
        # The campaigns.accounts_key column in TJ maps onto the issue_categories table in ID.
        issue.issue_categories.clear
        accounts_key = self.accounts_key
        if accounts_key.present?
          issue_category = ::IssueCategory.find_or_create_by(name: accounts_key)
          issue.issue_categories << issue_category
        end
      rescue Exception => e
        Rails.logger.error "Tijuana campaigns sync id:#{self.id}, error: #{e.message}"
        raise
      end
    end

    def erase(sync_id)
      begin
        issue = ::Issue.find_by(external_id: self.id.to_s, external_source: 'tijuana')
        if issue.present?
          issue.campaigns.destroy_all # TODO: Will need to cascade to other tables.
          issue.issue_categories.clear
          issue.destroy
        end
      rescue Exception => e
        Rails.logger.error "Tijuana campaigns delete id:#{self.id}, error: #{e.message}"
        raise
      end
    end
  end
end
