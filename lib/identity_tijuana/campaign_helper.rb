module IdentityTijuana
  module CampaignHelper
    module ClassMethods
      def fetch_campaign_updates(sync_id)
        started_at = DateTime.now
        last_updated_at = get_redis_date('tijuana:campaigns:last_updated_at')
        last_id = (Sidekiq.redis { |r| r.get 'tijuana:campaigns:last_id' } || 0).to_i
        campaigns_dependent_data_cutoff = DateTime.now
        updated_campaigns = IdentityTijuana::Campaign.updated_campaigns(last_updated_at, last_id)
        updated_campaigns_all = IdentityTijuana::Campaign.updated_campaigns_all(last_updated_at, last_id)

        updated_campaigns.each do |campaign|
          campaign.import(sync_id)
        end

        unless updated_campaigns.empty?
          campaigns_dependent_data_cutoff = updated_campaigns.last.updated_at if updated_campaigns.count < updated_campaigns_all.count
        end

        # Erase any logically deleted campaigns from ID.
        deleted_campaigns = IdentityTijuana::Campaign.deleted_campaigns(last_updated_at, campaigns_dependent_data_cutoff)
        deleted_campaigns.each do |campaign|
          campaign.erase(sync_id)
        end

        unless updated_campaigns.empty?
          set_redis_date('tijuana:campaigns:last_updated_at', updated_campaigns.last.updated_at)
          Sidekiq.redis { |r| r.set 'tijuana:campaigns:last_id', updated_campaigns.last.id }
        end

        set_redis_date('tijuana:campaigns:dependent_data_cutoff', campaigns_dependent_data_cutoff)

        execution_time_seconds = ((DateTime.now - started_at) * 24 * 60 * 60).to_i
        yield(
          updated_campaigns.size,
            updated_campaigns.pluck(:id),
            {
              scope: 'tijuana:campaigns:last_updated_at',
              scope_limit: Settings.tijuana.pull_batch_amount,
              from: last_updated_at,
              to: updated_campaigns.empty? ? nil : updated_campaigns.last.updated_at,
              started_at: started_at,
              completed_at: DateTime.now,
              execution_time_seconds: execution_time_seconds,
              remaining_behind: updated_campaigns_all.count
            },
            false
        )

        release_mutex_lock(:fetch_campaign_updates)
        need_another_batch = updated_campaigns.count < updated_campaigns_all.count
        if need_another_batch
          schedule_pull_batch(:fetch_campaign_updates)
        else
          schedule_pull_batch(:fetch_page_sequence_updates)
          schedule_pull_batch(:fetch_push_updates)
        end
      end
    end

    extend ClassMethods
    def self.included(other)
      other.extend(ClassMethods)
    end
  end
end
