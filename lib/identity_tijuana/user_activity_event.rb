require 'identity_tijuana/application_record'
require 'identity_tijuana/readwrite'

module ExternalSystems::IdentityTijuana
  class UserActivityEvent < ApplicationRecord
    include ReadWrite
    self.table_name = 'user_activity_events'

    belongs_to :user
    belongs_to :campaign
    belongs_to :page_sequence
    belongs_to :page
    belongs_to :email
    belongs_to :push
    belongs_to :content_module
    belongs_to :user_response, :polymorphic => true
    belongs_to :acquisition_source

    def self.import(activity_id)
      activity = UserActivityEvent.find(activity_id)
      activity.import(activity_id)
    end

    def import(activity_id)
      member = user.member()

      if activity == 'action_taken' and user_response_type = 'AgraAction'
        external_id = nil
      elsif activity == 'action_taken'
        external_id = content_module_id
      elsif activity == 'unsubscribed'
        external_id = email_id
      else
        external_id = nil
      end

      action_hash = {
        name: activity,
        action_type: activity,
        external_id: external_id,
      }

      action = Action.create!(action_hash)

      member_action_hash = {
        member_id: member.id,
        action_id: action.id,
        source: Source.create(source: source),
        metadata: {
          response: {
            type: user_response_type,
            response: user_response
          }
        }
      }

      member_action = MemberAction.create!(member_action_hash)
    end
  end
end
