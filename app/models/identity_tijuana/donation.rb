module IdentityTijuana
  class Donation < ApplicationRecord
    include ReadWrite
    self.table_name = 'donations'
    belongs_to :user
    has_many :transactions

    scope :updated_donations, -> (last_updated_at, exclude_from) {
      includes(:transactions)
        .where('donations.updated_at > ?', last_updated_at)
        .and(where('donations.updated_at < ?', exclude_from))
        .order('donations.updated_at')
        .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_donations_all, -> (last_updated_at, exclude_from) {
      where('donations.updated_at > ?', last_updated_at)
        .and(where('donations.updated_at < ?', exclude_from))
    }

    def self.import(donation_id, sync_id)
      donation = Donation.find(donation_id)
      donation.import(sync_id)
    end

    def import(sync_id)
      member = Member.find_by_external_id(:tijuana, user_id)
      if member.present?
        if member.ghosting_started?
          Rails.logger.warn "Tijuana member (#{id}) is ghosted (#{existing.id}), not updating"
        else
          regular_donation_id = nil
          if frequency != 'one_off'
            regular_donation_hash = {
              member_id: member.id,
              # started_at: nil,
              # ended_at: nil,
              frequency: frequency,
              # medium: nil,
              source: 'tijuana',
              # initial_amount: nil,
              current_amount: amount_in_cents / 100.0,
              # amount_last_changed_at: nil,
              created_at: created_at,
              updated_at: updated_at,
              # smartdebit_reference: nil,
              external_id: id,
              # payment_method_expires_at: nil,
              # ended_reason: nil,
              # member_action_id: nil,
            }
            begin
              rd = Donations::RegularDonation.upsert!(regular_donation_hash)
              regular_donation_id = rd.id
            rescue Exception => e
              Rails.logger.error "Tijuana donation sync id:#{id}, error: #{e.message}"
              raise
            end
          end
          transactions.each do | transaction |
            donation_hash = {
              # member_action_id: nil,
              member_id: member.id,
              amount: (transaction.amount_in_cents || 0.0) / 100.0,
              external_source: 'tijuana',
              created_at: transaction.created_at,
              updated_at: transaction.updated_at,
              external_id: transaction.id,
              # nonce: nil,
              # medium: nil,
              # refunded_at: nil,
            }
            donation_hash[:regular_donation_id] = regular_donation_id if regular_donation_id.present?
            begin
              Donations::Donation.upsert!(donation_hash)
            rescue Exception => e
              Rails.logger.error "Tijuana transaction sync id:#{transaction.id}, error: #{e.message}"
              raise
            end
          end
        end
      end
    end
  end
end
class TijuanaDonation < IdentityTijuana::Donation
end
