module IdentityTijuana
  class Donation < ReadWrite
    self.table_name = 'donations'
    belongs_to :user
    has_many(
      :transactions,
      -> { order 'transactions.created_at' },
      inverse_of: 'donation',
      dependent: nil
    )
    has_many(
      :donation_upgrades,
      -> { order 'donation_upgrades.created_at' },
      inverse_of: 'donation',
      dependent: nil
    )

    scope :updated_donations, ->(last_updated_at, last_id, exclude_from) {
      where('updated_at > ? or (updated_at = ? and id > ?)', last_updated_at, last_updated_at, last_id)
        .and(where(updated_at: ...exclude_from))
        .order('updated_at, id')
        .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_donations_all, ->(last_updated_at, last_id, exclude_from) {
      where('updated_at > ? or (updated_at = ? and id > ?)', last_updated_at, last_updated_at, last_id)
        .and(where(updated_at: ...exclude_from))
    }

    def self.import(donation_id, sync_id)
      donation = Donation.find(donation_id)
      donation.import(sync_id)
    end

    def import(_sync_id)
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
            rescue StandardError => e
              Rails.logger.error "Tijuana donation sync id:#{id}, error: #{e.message}"
              raise
            end
          end
          refund_transactions = transactions.filter_map { |t|
            t.refund_of_id && t.successful ? [t.refund_of_id, t] : nil
          }.to_h
          transactions.each do |transaction|
            next unless transaction.successful

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
              attempts = 0
              while true
                begin
                  attempts += 1
                  Donations::Donation.upsert!(donation_hash)
                  break
                rescue ActiveRecord::RecordInvalid => e
                  # Workaround for a problematic index in ID, which requires
                  # uniqueness for all donations with respect to member_id,
                  # amount, and created_at. Since the first 2 fields are
                  # important enough that they can't really be changed, we
                  # are forced to offset the created_at date by however many
                  # microseconds are required to make it unique for that member
                  # and transaction amount.
                  raise unless e.message.include?('has already been taken')
                  raise if attempts > 1

                  tj_connection = TijuanaDonation.connection
                  preceding_duplicates = tj_connection.execute(%{
                    SELECT t.id
                    FROM donations d, transactions t
                    WHERE d.id = t.donation_id
                    AND d.user_id = #{user_id}
                    AND t.amount_in_cents = #{transaction.amount_in_cents}
                    AND t.created_at = #{tj_connection.quote(transaction.created_at)}
                    AND t.id < #{transaction.id}
                  }).to_a
                  offset_microseconds = preceding_duplicates.count + 1
                  donation_hash[:created_at] = transaction.created_at + (offset_microseconds / 1000000.0)
                end
              end
            rescue StandardError => e
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
