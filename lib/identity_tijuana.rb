require 'identity_tijuana/user'
require 'identity_tijuana/postcode'
require 'identity_tijuana/campaign'
require 'identity_tijuana/user_activity_event'

module ExternalSystems::IdentityTijuana
  SYSTEM_NAME = 'tijuana'
  PULL_JOBS = [:pull_updated_users, :push_updated_members].freeze

  class << self
    def push(sync_id, member_ids, external_system_params)
    end

    def push_in_batches(sync_id, members_for_service, external_system_param)
    end

    def description(external_system_params, contact_campaign_name)
      external_system_params_hash = JSON.parse(external_system_params)
      "#{SYSTEM_NAME.titleize}: #{external_system_params_hash['pull_job']}"
    end

    def pull_updated_users
      puts "Pull users from Tijuana"
      Rails.logger.info "Pull users from Tijuana"
      last_updated_at = Time.parse(Sidekiq.redis { |r| r.get 'tijuana:pull-users:last_updated_at' } || '1970-01-01 00:00:00')

      updated_users = User.updated_users(last_updated_at)
      updated_users.each do |user|
        User.import(user.id)
      end

      unless updated_users.empty?
        Sidekiq.redis { |r| r.set 'tijuana:pull-users:last_updated_at', updated_users.last.updated_at }
      end
    end

    def push_updated_members
      Rails.logger.info "Push members to Tijuana"
      puts "Push members to Tijuana"
      last_updated_at = Time.parse(Sidekiq.redis { |r| r.get 'tijuana:push-members:last_updated_at' } || '1970-01-01 00:00:00')

      updated_members = Member
        .where('members.updated_at > ?', last_updated_at)
        .order('members.updated_at')
        .limit(Settings.tijuana.push_batch_amount)

      updated_members.each do |member|
        User.export(member.id)
      end

      unless updated_members.empty?
        Sidekiq.redis { |r| r.set 'tijuana:push-members:last_updated_at', updated_members.last.updated_at }
      end
    end

    def pull_updated_pillars_and_campaigns
      Rails.logger.info "Pull pillars and campaigns from Tijuana"
      puts "Pull pillars and campaigns from Tijuana"
      last_updated_at = Time.parse(Sidekiq.redis { |r| r.get 'tijuana:pull-pillars-campaigns:last_updated_at' } || '1970-01-01 00:00:00')

      updated_pillars = Campaign
        .where('campaigns.updated_at > ?', last_updated_at)
        .order('campaigns.updated_at')
        .select('pillar', 'updated_at')
        .distinct()
        .limit(Settings.tijuana.pull_batch_amount)

      updated_pillars.each do |updated_pillar|
        IssueCategory.create(name: updated_pillar.pillar)
      end

      updated_campaigns = Campaign
        .where('campaigns.updated_at > ?', last_updated_at)
        .order('campaigns.updated_at')
        .limit(Settings.tijuana.pull_batch_amount)

      updated_campaigns.each do |campaign|
        Issue.create(name: campaign.name)
      end

      unless updated_campaigns.empty?
        Sidekiq.redis { |r| r.set 'tijuana:pull-pillars-campaigns:last_updated_at', updated_campaigns.last.updated_at }
      end
    end

    def pull_updated_user_activity_events
      Rails.logger.info "Pull updated user activity events"
      puts "Pull updated user activity events"
      last_updated_at = Time.parse(Sidekiq.redis { |r| r.get 'tijuana:pull-user-activity-events:last_updated_at' } || '1970-01-01 00:00:00')

      updated_activities = UserActivityEvent
        .where('user_activity_events.updated_at > ?', last_updated_at)
        .order('user_activity_events.updated_at')
        .limit(Settings.tijuana.pull_batch_amount)

      updated_activities.each do |activity|
        UserActivityEvent.import(activity.id)
      end

      unless updated_activities.empty?
        Sidekiq.redis { |r| r.set 'tijuana:pull-user-activity-events:last_updated_at', updated_activities.last.updated_at }
      end
    end
  end
end
