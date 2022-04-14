module IdentityTijuana
  COMMERCIAL_DATA_IMPORT_KEYS = ['au_2022']
  class User < ApplicationRecord
    include ReadWrite
    self.table_name = 'users'
    has_many :donations
    has_many :taggings, -> { where(taggable_type: 'User') }, foreign_key: 'taggable_id'
    has_many :tags, through: :taggings
    belongs_to :postcode, optional: true

    scope :updated_users, -> (last_updated_at, last_id) {
      includes(:postcode)
      .includes(:taggings)
      .includes(:tags)
      .where('updated_at > ? || (updated_at = ? && id > ?)', last_updated_at, last_updated_at, last_id)
      .order('updated_at, id')
      .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_users_all, -> (last_updated_at, last_id) {
      where('updated_at > ? || (updated_at = ? && id > ?)',last_updated_at, last_updated_at, last_id)
    }

    def self.import(user_id, sync_id)
      user = User.find(user_id)
      user.import(sync_id)
    end

    def import(sync_id)
      existing = Member.find_by_external_id(:tijuana, id)
      if existing.present? && existing.ghosting_started?
        Rails.logger.warn "Tijuana member (#{id}) is ghosted (#{existing.id}), not updating"
      elsif existing.present? && existing.member_external_ids.find_by(system: COMMERCIAL_DATA_IMPORT_KEYS)
        Rails.logger.warn "Tijuana member (#{id}) changes will overwrite commercial data (#{existing.id}), not updating"
      else
        address_hash = {
          line1: street_address,
          town: suburb,
          country: country_iso,
          state: postcode.try(:state),
          postcode: postcode.try(:number)
        }
        member_hash = {
          ignore_phone_number_match: true,
          firstname: first_name,
          lastname: last_name,
          emails: [{ email: email }],
          phones: [],
          custom_fields: [],
          external_ids: { tijuana: id },
          subscriptions: []
        }

        deceased = has_tag('deceased')
        return_to_sender = has_tag('rts')
        update_deceased = update_rts = true
        if existing
          deceased_custom_field = find_custom_field(existing.id, 'deceased')
          rts_custom_field = find_custom_field(existing.id, 'rts')
          currently_deceased = deceased_custom_field && deceased_custom_field.data == 'true'
          currently_return_to_sender = rts_custom_field && rts_custom_field.data == 'true'
          update_deceased = deceased != currently_deceased
          update_rts = return_to_sender != currently_return_to_sender
          if update_deceased && !deceased
            deceased_custom_field.delete if deceased_custom_field
          end
          if update_rts && !return_to_sender
            rts_custom_field.delete if rts_custom_field
          end
        end
        member_hash[:custom_fields].push({name: 'deceased', value: 'true'}) if update_deceased && deceased
        member_hash[:custom_fields].push({name: 'rts', value: 'true'}) if update_rts && return_to_sender

        is_living_member = is_member && !deceased

        add_subscription_info_if_changed(
          existing,
          Settings.tijuana.email_subscription_id,
          is_living_member,
          member_hash
        )
        add_subscription_info_if_changed(
          existing,
          Settings.tijuana.calling_subscription_id,
          is_living_member && !do_not_call,
          member_hash
        )
        add_subscription_info_if_changed(
          existing,
          Settings.tijuana.sms_subscription_id,
          is_living_member && !do_not_sms,
          member_hash
        )

        same_address = false
        if existing && existing.address
          existing_address_hash = {
            line1: existing.address.line1,
            town: existing.address.town,
            country: existing.address.country,
            state: existing.address.state,
            postcode: existing.address.postcode
          }
          same_address = (address_hash == existing_address_hash)
        end
        member_hash[:addresses] = [address_hash] unless same_address || return_to_sender

        standard_home = standardise_phone_number(home_number)
        standard_mobile = standardise_phone_number(mobile_number)
        member_hash[:phones].push(phone: standard_home) if standard_home.present?
        member_hash[:phones].push(phone: standard_mobile) if standard_mobile.present? and standard_mobile != standard_home

        begin
          member = UpsertMember.call(
            member_hash,
            entry_point: 'tijuana:fetch_updated_users',
            ignore_name_change: false
          )
          if member.present?
            member.created_at = created_at  # Preserve TJ creation date
            member.save
          end
        rescue Exception => e
          Rails.logger.error "Tijuana member sync id:#{id}, error: #{e.message}"
          raise
        end
      end
    end

    def add_subscription_info_if_changed(member, subscription_id, sub_flag, member_hash)
      return unless subscription_id
      update_the_sub = true
      if member
        member_subscription = member.member_subscriptions.find_by(subscription_id: subscription_id)
        curr_sub_flag = member_subscription && member_subscription.unsubscribed_at.blank?
        update_the_sub = sub_flag != curr_sub_flag
      end
      if update_the_sub
        member_hash[:subscriptions].push({
          id: subscription_id,
          action: sub_flag ? 'subscribe' : 'unsubscribe'
        })
      end
    end

    def find_custom_field(member_id, key)
      CustomField.joins(:custom_field_key).where('member_id = ? and custom_field_keys.name = ?', member_id, key).first
    end

    def has_tag(tag_name)
      tags.where(name: tag_name).first != nil
    end

    def standardise_phone_number(phone_number)
      begin
        if phone_number.present?
          standardised_number = PhoneNumber.standardise_phone_number(phone_number)
          # Temporary workaround to forestall problems created by ID's current
          # handling of some bad phone numbers. A call made to Phony.split
          # during ID's member upsert throws an error in these cases. To avoid
          # this happening, we catch these cases ourselves before the upsert,
          # and abandon trying to upsert the affected number.
          Phony.split(standardised_number)
          standardised_number
        else
          nil
        end
      rescue => e
        Rails.logger.warn "#{e.class.name} occurred while standardising phone number #{phone_number}"
        nil
      end
    end
  end
end
class User < IdentityTijuana::User
end
