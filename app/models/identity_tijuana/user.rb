module IdentityTijuana
  class User < ApplicationRecord
    include ReadWrite
    self.table_name = 'users'
    has_many :donations
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

        member_hash[:custom_fields].push({name: 'deceased', value: deceased.to_s})
        member_hash[:custom_fields].push({name: 'rts', value: return_to_sender.to_s})

        is_living_member = is_member && !deceased
        reason = deceased ? 'deceased' : nil

        if Settings.tijuana.email_subscription_id
          member_hash[:subscriptions].push({
            id: Settings.tijuana.email_subscription_id,
            action: is_living_member ? 'subscribe' : 'unsubscribe',
            reason: reason
          })
        end

        if Settings.tijuana.calling_subscription_id
          member_hash[:subscriptions].push({
            id: Settings.tijuana.calling_subscription_id,
            action: is_living_member && !do_not_call ? 'subscribe' : 'unsubscribe',
            reason: reason
          })
        end

        if Settings.tijuana.sms_subscription_id
          member_hash[:subscriptions].push({
            id: Settings.tijuana.sms_subscription_id,
            action: is_living_member && !do_not_sms ? 'subscribe' : 'unsubscribe',
            reason: reason
          })
        end

        member_hash[:addresses] = [address_hash] unless return_to_sender

        standard_home = standardise_phone_number(home_number)
        standard_mobile = standardise_phone_number(mobile_number)
        member_hash[:phones].push(phone: standard_home) if standard_home.present?
        member_hash[:phones].push(phone: standard_mobile) if standard_mobile.present? and standard_mobile != standard_home

        begin
          UpsertMember.call(
            member_hash,
            entry_point: 'tijuana:fetch_updated_users',
            ignore_name_change: false
          )
          # Destroy the address if "return to sender" is set. Unfortunately
          # this is beyond the capabilities of ID's member upsert processing,
          # so we need to do it as an extra step.
          if return_to_sender
            if (member = Member.find_by_external_id(:tijuana, id))
              if (address = member.addresses.find_by(address_hash))
                address.destroy
              end
            end
          end
        rescue Exception => e
          Rails.logger.error "Tijuana member sync id:#{id}, error: #{e.message}"
          raise
        end
      end
    end

    def standardise_phone_number(phone_number)
      standard_number = PhoneNumber.standardise_phone_number(phone_number) if phone_number.present?
      # Temporary workaround for a bug in identity/Phony phone number handling.
      if standard_number.present? && PhoneNumber.can_detect_mobiles?
        ndc = Phony.plausible?(standard_number) ? Phony.split(standard_number)[1] : nil
        standard_number = nil unless ndc.respond_to?(:start_with?)
      end
      standard_number
    end
  end
end
class User < IdentityTijuana::User
end
