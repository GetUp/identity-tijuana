# frozen_string_literal: true

class Sync < ApplicationRecord
  include ReadWriteIdentity

  INITIALISING_STATUS = 'initialising'
  INITIALISED_STATUS = 'initialised'
  ACTIVE_STATUS = 'active'
  FINALISED_STATUS = 'finalised'
  FAILED_STATUS = 'failed'
  PUSH_SYNC_TYPE = 'push'
  PULL_SYNC_TYPE = 'pull'

  def pull_from_external_service
  end
end
