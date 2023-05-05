module IdentityTijuana
  class Push < ReadWrite
    self.table_name = 'pushes'
    belongs_to :campaign
    has_many :blasts

    scope :deleted_pushes, -> (last_updated_at, exclude_from) {
      where(
        'deleted_at is not null and deleted_at >= ? and deleted_at < ?',
        last_updated_at, exclude_from
      ).order('deleted_at, id')
    }

    scope :updated_pushes, -> (last_updated_at, last_id, exclude_from) {
      updated_pushes_all(last_updated_at, last_id, exclude_from)
        .order('updated_at, id')
        .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_pushes_all, -> (last_updated_at, last_id, exclude_from) {
      where(
        '(updated_at > ? or (updated_at = ? and id > ?)) and updated_at < ?',
        last_updated_at, last_updated_at, last_id, exclude_from
      )
    }

    def import(sync_id)
      begin
        # The pushes table in TJ maps onto the campaigns table in ID.
        campaign = ::Campaign.find_or_create_by(external_id: self.id.to_s, external_source: 'tijuana_push')
        campaign.name = self.name
        campaign.issue = ::Issue.find_by(external_id: self.campaign_id.to_s, external_source: 'tijuana')
        # campaign.author_id = nil
        # campaign.controlshift_campaign_id = nil
        # campaign.campaign_type = nil
        # campaign.latitude = nil
        # campaign.longitude = nil
        # campaign.location = nil
        # campaign.image = nil
        # campaign.url = nil
        # campaign.slug = nil
        # campaign.moderation_status = nil
        # campaign.finished_at = nil
        # campaign.target_type = nil
        # campaign.outcome = nil
        # campaign.languages = nil
        campaign.save!
      rescue Exception => e
        Rails.logger.error "Tijuana pushes sync id:#{self.id}, error: #{e.message}"
        raise
      end
    end

    def erase(sync_id)
      begin
        campaign = ::Campaign.find_by(external_id: self.id.to_s, external_source: 'tijuana_push')
        campaign.destroy if campaign.present?
      rescue Exception => e
        Rails.logger.error "Tijuana pushes delete id:#{self.id}, error: #{e.message}"
        raise
      end
    end
  end
end
