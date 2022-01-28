module IdentityTijuana
  class User < ApplicationRecord
    include ReadWrite
    self.table_name = 'users'
    has_many :taggings, -> { where(taggable_type: 'User') }, foreign_key: 'taggable_id'
    has_many :tags, through: :taggings
    belongs_to :postcode, optional: true

    scope :updated_users, -> (last_updated_at) {
      includes(:postcode)
      .includes(:taggings)
      .includes(:tags)
      .where('users.updated_at > ?', last_updated_at)
      .order('users.updated_at')
      .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_users_all, -> (last_updated_at) {
      where('users.updated_at > ?', last_updated_at)
    }

    def self.import(user_id, sync_id)
      user = User.find(user_id)
      user.import(sync_id)
    end

    def has_tag(tag_name)
      tags.where(name: tag_name).first != nil
    end

    def import(sync_id)
      existing = Member.find_by_external_id(:tijuana, id)
      if existing.present? && existing.ghosting_started?
          Rails.logger.warn "Tijuana member (#{id}) is ghosted (#{existing.id}), not updating"
      else        
        member_hash = {
          ignore_phone_number_match: true,
          firstname: first_name,
          lastname: last_name,
          emails: [{ email: email }],
          phones: [],
          addresses: [{
            line1: street_address,
            town: suburb,
            country: country_iso,
            state: postcode.try(:state),
            postcode: postcode.try(:number)
          }],
          custom_fields: [],
          external_ids: { tijuana: id },
          subscriptions: []
        }

        member_hash[:custom_fields].push({name: 'deceased', value: 'true'}) if (has_tag('deceased'))
        member_hash[:custom_fields].push({name: 'rts', value: 'true'}) if (has_tag('rts'))

        if Settings.tijuana.email_subscription_id
          member_hash[:subscriptions].push({
            id: Settings.tijuana.email_subscription_id,
            action: is_member ? 'subscribe' : 'unsubscribe'
          })
        end

        if Settings.tijuana.calling_subscription_id
          member_hash[:subscriptions].push({
            id: Settings.tijuana.calling_subscription_id,
            action: is_member && !do_not_call ? 'subscribe' : 'unsubscribe'
          })
        end

        if Settings.tijuana.sms_subscription_id
          member_hash[:subscriptions].push({
            id: Settings.tijuana.sms_subscription_id,
            action: is_member && !do_not_sms ? 'subscribe' : 'unsubscribe'
          })
        end

        standard_home = PhoneNumber.standardise_phone_number(home_number) if home_number.present?
        standard_mobile = PhoneNumber.standardise_phone_number(mobile_number) if mobile_number.present?
        member_hash[:phones].push(phone: standard_home) if standard_home.present?
        member_hash[:phones].push(phone: standard_mobile) if standard_mobile.present? and standard_mobile != standard_home

        begin
          UpsertMember.call(
            member_hash,
            entry_point: 'tijuana:fetch_updated_users',
          ignore_name_change: false
          )
        rescue Exception => e
          Rails.logger.error "Tijuana member sync id:#{id}, error: #{e.message}"
          raise
        end
      end
    end
  end
end
class User < IdentityTijuana::User
end
