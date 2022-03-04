module IdentityTijuana
  class Donation < ApplicationRecord
    include ReadWrite
    self.table_name = 'donations'
    belongs_to :user
    has_many :transactions, -> { order 'transactions.created_at' }
    has_many :donation_upgrades, -> { order 'donation_upgrades.created_at' }

    scope :updated_donations, -> (last_updated_at, last_id, exclude_from) {
      includes(:transactions)
        .includes(:donation_upgrades)
        .where('updated_at > ? || (updated_at = ? && id > ?)', last_updated_at, last_updated_at, last_id)
        .and(where('updated_at < ?', exclude_from))
        .order('updated_at, id')
        .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_donations_all, -> (last_updated_at, last_id, exclude_from) {
      where('updated_at > ? || (updated_at = ? && id > ?)', last_updated_at, last_updated_at, last_id)
        .and(where('updated_at < ?', exclude_from))
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
              started_at: created_at,
              ended_at: cancelled_at || (active ? nil : updated_at),
              frequency: frequency,
              medium: payment_method,
              source: 'tijuana',
              initial_amount: (donation_upgrades.first ?
                                 donation_upgrades.first.original_amount_in_cents :
                                 amount_in_cents) / 100.0,
              current_amount: amount_in_cents / 100.0,
              amount_last_changed_at: donation_upgrades.last ? donation_upgrades.last.created_at : nil,
              # smartdebit_reference: nil,
              external_id: id,
              # payment_method_expires_at: nil,
              # ended_reason: nil,
              # member_action_id: nil,
              created_at: created_at,
              updated_at: DateTime.now
            }
            begin
              rd = Donations::RegularDonation.upsert!(regular_donation_hash)
              regular_donation_id = rd.id
            rescue Exception => e
              Rails.logger.error "Tijuana donation sync id:#{id}, error: #{e.message}"
              raise
            end
          end
          refund_transactions = transactions.map { |t| t.refund_of_id ? [ t.refund_of_id, t ] : nil }.compact.to_h
          transactions.each do | transaction |
            next if transaction.refund_of_id
            refund_transaction = refund_transactions[transaction.id]
            donation_hash = {
              # member_action_id: nil,
              member_id: member.id,
              amount: (transaction.amount_in_cents || 0.0) / 100.0,
              external_source: 'tijuana',
              external_id: transaction.id,
              # nonce: nil,
              medium: payment_method,
              refunded_at: refund_transaction ? refund_transaction.created_at : nil,
              created_at: transaction.created_at,
              updated_at: DateTime.now,
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
