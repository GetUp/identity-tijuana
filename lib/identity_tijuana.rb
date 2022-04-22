require "identity_tijuana/engine"

module IdentityTijuana
  SYSTEM_NAME = 'tijuana'
  SYNCING = 'tag'
  CONTACT_TYPE = 'email'
  PULL_JOBS = [[:fetch_user_updates, 10.minutes]]
  MEMBER_RECORD_DATA_TYPE='object'
  MUTEX_EXPIRY_DURATION = 10.minutes

  def self.acquire_mutex_lock(method_name, sync_id)
    mutex_name = "#{SYSTEM_NAME}:mutex:#{method_name}"
    new_mutex_expiry = DateTime.now + MUTEX_EXPIRY_DURATION
    mutex_acquired = set_redis_date(mutex_name, new_mutex_expiry, true)
    unless mutex_acquired
      mutex_expiry = get_redis_date(mutex_name)
      if mutex_expiry.past?
        unless worker_currently_running?(method_name, sync_id)
          delete_redis_date(mutex_name)
          mutex_acquired = set_redis_date(mutex_name, new_mutex_expiry, true)
        end
      end
    end
    mutex_acquired
  end

  def self.release_mutex_lock(method_name)
    mutex_name = "#{SYSTEM_NAME}:mutex:#{method_name}"
    delete_redis_date(mutex_name)
  end

  def self.get_redis_date(redis_identifier, default_value=Time.at(0))
    date_str = Sidekiq.redis { |r| r.get redis_identifier }
    date_str ? Time.parse(date_str) : default_value
  end

  def self.set_redis_date(redis_identifier, date_time_value, as_mutex=false)
    date_str = date_time_value.utc.to_s(:inspect) # Ensures fractional seconds are retained
    if as_mutex
      Sidekiq.redis { |r| r.setnx redis_identifier, date_str }
    else
      Sidekiq.redis { |r| r.set redis_identifier, date_str }
    end
  end

  def self.delete_redis_date(redis_identifier)
    Sidekiq.redis { |r| r.del redis_identifier }
  end

  def self.push(sync_id, member_ids, external_system_params)
    begin
      members = Member.where(id: member_ids).with_email
      yield members, nil
    rescue => e
      raise e
    end
  end

  def self.push_in_batches(sync_id, members, external_system_params)
    begin
      members.in_batches(of: Settings.tijuana.push_batch_amount).each_with_index do |batch_members, batch_index|
        tag = JSON.parse(external_system_params)['tag']
        rows = ActiveModel::Serializer::CollectionSerializer.new(
          batch_members,
          serializer: TijuanaMemberSyncPushSerializer
        ).as_json.to_a.map{|member| member[:email]}
        tijuana = API.new
        tijuana.tag_emails(tag, rows)
        yield batch_index, rows.count
      end
    rescue => e
      raise e
    end
  end

  def self.description(sync_type, external_system_params, contact_campaign_name)
    external_system_params_hash = JSON.parse(external_system_params)
    if sync_type === 'push'
      "#{SYSTEM_NAME.titleize} - #{SYNCING.titleize}: ##{external_system_params_hash['tag']} (#{CONTACT_TYPE})"
    else
      "#{SYSTEM_NAME.titleize}: #{external_system_params_hash['pull_job']}"
    end
  end

  def self.worker_currently_running?(method_name, sync_id)
    workers = Sidekiq::Workers.new
    workers.each do |_process_id, _thread_id, work|
      args = work["payload"]["args"]
      worker_sync_id = (args.count > 0) ? args[0] : nil
      worker_sync = worker_sync_id ? Sync.find_by(id: worker_sync_id) : nil
      next unless worker_sync
      worker_system = worker_sync.external_system
      worker_method_name = JSON.parse(worker_sync.external_system_params)["pull_job"]
      already_running = (worker_system == SYSTEM_NAME &&
        worker_method_name == method_name &&
        worker_sync_id != sync_id)
      return true if already_running
    end
    return false
  end

  def self.get_pull_jobs
    defined?(PULL_JOBS) && PULL_JOBS.is_a?(Array) ? PULL_JOBS : []
  end

  def self.get_push_jobs
    defined?(PUSH_JOBS) && PUSH_JOBS.is_a?(Array) ? PUSH_JOBS : []
  end

  def self.pull(sync_id, external_system_params)
    begin
      pull_job = JSON.parse(external_system_params)['pull_job'].to_s
      self.send(pull_job, sync_id) do |records_for_import_count, records_for_import, records_for_import_scope, pull_deferred|
        yield records_for_import_count, records_for_import, records_for_import_scope, pull_deferred
      end
    rescue => e
      raise e
    end
  end

  def self.schedule_pull_batch(pull_job)
    sync = Sync.create!(
      external_system: SYSTEM_NAME,
      external_system_params: { pull_job: pull_job, time_to_run: DateTime.now }.to_json,
      sync_type: Sync::PULL_SYNC_TYPE
    )
    PullExternalSystemsWorker.perform_async(sync.id)
  end

  def self.fetch_user_updates(sync_id)
    begin
      mutex_acquired = acquire_mutex_lock(__method__.to_s, sync_id)
      unless mutex_acquired
        yield 0, {}, {}, true
        return
      end
      need_another_batch = fetch_user_updates_impl(sync_id) do |records_for_import_count, records_for_import, records_for_import_scope, pull_deferred|
        yield records_for_import_count, records_for_import, records_for_import_scope, pull_deferred
      end
    ensure
      release_mutex_lock(__method__.to_s) if mutex_acquired
    end
    schedule_pull_batch(:fetch_user_updates) if need_another_batch
    schedule_pull_batch(:fetch_tagging_updates)
    schedule_pull_batch(:fetch_donation_updates)
  end

  def self.fetch_user_updates_impl(sync_id)
    started_at = DateTime.now
    last_updated_at = get_redis_date('tijuana:users:last_updated_at')
    last_id = (Sidekiq.redis { |r| r.get 'tijuana:users:last_id' } || 0).to_i
    users_dependent_data_cutoff = DateTime.now
    updated_users = User.updated_users(last_updated_at, last_id)
    updated_users_all = User.updated_users_all(last_updated_at, last_id)
    updated_users.each do |user|
      User.import(user.id, sync_id)
    end

    unless updated_users.empty?
      set_redis_date('tijuana:users:last_updated_at', updated_users.last.updated_at)
      Sidekiq.redis { |r| r.set 'tijuana:users:last_id', updated_users.last.id }
      users_dependent_data_cutoff = updated_users.last.updated_at if updated_users.count < updated_users_all.count
    end

    set_redis_date('tijuana:users:dependent_data_cutoff', users_dependent_data_cutoff)

    execution_time_seconds = ((DateTime.now - started_at) * 24 * 60 * 60).to_i
    yield(
      updated_users.size,
      updated_users.pluck(:id),
      {
        scope: 'tijuana:users:last_updated_at',
        scope_limit: Settings.tijuana.pull_batch_amount,
        from: last_updated_at,
        to: updated_users.empty? ? nil : updated_users.last.updated_at,
        started_at: started_at,
        completed_at: DateTime.now,
        execution_time_seconds: execution_time_seconds,
        remaining_behind: updated_users_all.count
      },
      false
    )

    updated_users.count < updated_users_all.count
  end

  def self.fetch_users_for_dedupe
    i = 0
    loop do
      results = User.connection.execute("SELECT email, first_name, last_name, mobile_number, street_address, suburb, country_iso, REPLACE(p.number,' ','') FROM users u JOIN postcodes p ON u.postcode_id = p.id LIMIT 10000 OFFSET #{i * 10_000}").to_a
      break if results.empty?

      # deduper doesn't like empty strings
      value_string = results.map { |x| '(' + x.map { |v| v.present? ? ActiveRecord::Base.connection.quote(v.downcase) : 'NULL' }.join(',') + ')' }.join(',')

      ActiveRecord::Base.connection.execute("INSERT INTO dedupe_processed_records (email, first_name, last_name, phone, line1, town, country, postcode) VALUES #{value_string}")
      i += 1
      puts "Done #{i * 10_000}"
    end
  end

  def self.fetch_donation_updates(sync_id)
    begin
      mutex_acquired = acquire_mutex_lock(__method__.to_s, sync_id)
      unless mutex_acquired
        yield 0, {}, {}, true
        return
      end
      need_another_batch = fetch_donation_updates_impl(sync_id) do |records_for_import_count, records_for_import, records_for_import_scope, pull_deferred|
        yield records_for_import_count, records_for_import, records_for_import_scope, pull_deferred
      end
    ensure
      release_mutex_lock(__method__.to_s) if mutex_acquired
    end
    schedule_pull_batch(:fetch_donation_updates) if need_another_batch
  end

  def self.fetch_donation_updates_impl(sync_id)
    started_at = DateTime.now
    last_updated_at = get_redis_date('tijuana:donations:last_updated_at')
    last_id = (Sidekiq.redis { |r| r.get 'tijuana:donations:last_id' } || 0).to_i
    users_dependent_data_cutoff = get_redis_date('tijuana:users:dependent_data_cutoff')
    updated_donations = IdentityTijuana::Donation.updated_donations(last_updated_at, last_id, users_dependent_data_cutoff)
    updated_donations_all = IdentityTijuana::Donation.updated_donations_all(last_updated_at, last_id, users_dependent_data_cutoff)
    updated_donations.each do |donation|
      IdentityTijuana::Donation.import(donation.id, sync_id)
    end

    unless updated_donations.empty?
      set_redis_date('tijuana:donations:last_updated_at', updated_donations.last.updated_at)
      Sidekiq.redis { |r| r.set 'tijuana:donations:last_id', updated_donations.last.id }
    end

    execution_time_seconds = ((DateTime.now - started_at) * 24 * 60 * 60).to_i
    yield(
      updated_donations.size,
        updated_donations.pluck(:id),
        {
          scope: 'tijuana:donations:last_updated_at',
          scope_limit: Settings.tijuana.pull_batch_amount,
          from: last_updated_at,
          to: updated_donations.empty? ? nil : updated_donations.last.updated_at,
          started_at: started_at,
          completed_at: DateTime.now,
          execution_time_seconds: execution_time_seconds,
          remaining_behind: updated_donations_all.count
        },
        false
    )

    updated_donations.count < updated_donations_all.count
  end

  def self.fetch_tagging_updates(sync_id)
    begin
      mutex_acquired = acquire_mutex_lock(__method__.to_s, sync_id)
      unless mutex_acquired
        yield 0, {}, {}, true
        return
      end
      need_another_batch = fetch_tagging_updates_impl(sync_id) do |records_for_import_count, records_for_import, records_for_import_scope, pull_deferred|
        yield records_for_import_count, records_for_import, records_for_import_scope, pull_deferred
      end
    ensure
      release_mutex_lock(__method__.to_s) if mutex_acquired
    end
    schedule_pull_batch(:fetch_tagging_updates) if need_another_batch
  end

  def self.fetch_tagging_updates_impl(sync_id)
    latest_tagging_scope_limit = 50000
    started_at = DateTime.now
    last_id = (Sidekiq.redis { |r| r.get 'tijuana:taggings:last_id' } || 0).to_i
    users_dependent_data_cutoff = get_redis_date('tijuana:users:dependent_data_cutoff')
    connection = ActiveRecord::Base.connection == List.connection ? ActiveRecord::Base.connection : List.connection

    tags_remaining_behind_sql = %{
      SELECT count(*)
      FROM taggings tu #{'FORCE INDEX (PRIMARY)' unless Settings.tijuana.database_url.start_with? 'postgres'}
      JOIN tags t
        ON t.id = tu.tag_id
      WHERE tu.id > #{last_id}
        AND taggable_type = 'User'
        AND (tu.created_at < #{connection.quote(users_dependent_data_cutoff)} OR tu.created_at is null)
        AND t.name like '%_syncid%'
    }

    scoped_latest_taggings_sql = %{
      SELECT tu.taggable_id, t.name, tu.id, t.author_id, tu.created_at
      FROM taggings tu #{'FORCE INDEX (PRIMARY)' unless Settings.tijuana.database_url.start_with? 'postgres'}
      JOIN tags t
        ON t.id = tu.tag_id
      WHERE tu.id > #{last_id}
        AND taggable_type = 'User'
        AND (tu.created_at < #{connection.quote(users_dependent_data_cutoff)} OR tu.created_at is null)
        AND t.name like '%_syncid%'
      ORDER BY tu.id
      LIMIT #{latest_tagging_scope_limit}
    }

    puts 'Getting latest taggings'
    tags_remaining_results = IdentityTijuana::Tagging.connection.execute(tags_remaining_behind_sql).to_a
    results = IdentityTijuana::Tagging.connection.execute(scoped_latest_taggings_sql).to_a
    tags_remaining_count = tags_remaining_results[0][0]

    unless results.empty?
      puts 'Creating value strings'
      results = results.map { |row| row.try(:values) || row } # deal with results returned in array or hash form
      value_strings = results.map do |row|
        "(#{connection.quote(row[0])}, #{connection.quote(row[1])}, #{connection.quote(row[2])})"
      end

      puts 'Inserting value strings and merging'
      base_table_name = "tj_tags_sync_#{sync_id}_#{SecureRandom.hex(16)}"
      table_name = "tmp.#{base_table_name}"
      connection.execute(%{
        CREATE SCHEMA IF NOT EXISTS tmp;
        DROP TABLE IF EXISTS #{table_name};
        CREATE TABLE #{table_name} (tijuana_id TEXT, tag TEXT, tijuana_author_id INTEGER);
        INSERT INTO #{table_name} VALUES #{value_strings.join(',')};
        CREATE INDEX #{base_table_name}_tijuana_id ON #{table_name} (tijuana_id);
        CREATE INDEX #{base_table_name}_tag ON #{table_name} (tag);
      })

      connection.execute(%{
        INSERT INTO lists (name, author_id, created_at, updated_at)
        SELECT DISTINCT 'TIJUANA TAG: ' || et.tag, author_id, current_timestamp, current_timestamp
        FROM #{table_name} et
        LEFT JOIN lists l
          ON l.name = 'TIJUANA TAG: ' || et.tag
        WHERE l.id is null;
        })

      connection.execute(%Q{
        INSERT INTO list_members (member_id, list_id, created_at, updated_at)
        SELECT DISTINCT mei.member_id, l.id, current_timestamp, current_timestamp
        FROM #{table_name} et
        JOIN lists l
          ON l.name = 'TIJUANA TAG: ' || et.tag
        JOIN member_external_ids mei
          ON (mei.external_id = et.tijuana_id AND mei.system = 'tijuana')
        LEFT JOIN list_members lm
          ON lm.member_id = mei.member_id AND lm.list_id = l.id
        WHERE lm.id is null;
      })

      list_ids = connection.execute(%Q{SELECT DISTINCT l.id
        FROM #{table_name} et
        JOIN lists l
          ON l.name = 'TIJUANA TAG: ' || et.tag
      }).to_a.map { |row| row['id'] }

      connection.execute("DROP TABLE #{table_name};")

      list_ids.each do |list_id|
        list = List.find(list_id)
        user_results = User.connection.execute("SELECT email, first_name, last_name FROM users WHERE id = #{ActiveRecord::Base.connection.quote(list.author_id)}").to_a
        if user_results && user_results[0]
          ## Create Members for both the user and campaign contact
          author = UpsertMember.call(
            {
              emails: [{ email: user_results[0][0] }],
              firstname: user_results[0][1],
              lastname: user_results[0][2],
              external_ids: { tijuana: list.author_id },
            },
            entry_point: "#{SYSTEM_NAME}:#{__method__.to_s}",
            ignore_name_change: false
          )
          List.find(list_id).update!(author_id: author.id)
        end
        CountListMembersWorker.perform_async(list_id)
      end

      if Settings.options.use_redshift
        List.find(list_ids).each(&:copy_to_redshift)
      end

      Sidekiq.redis { |r| r.set 'tijuana:taggings:last_id', results.last[2] }
    end

    execution_time_seconds = ((DateTime.now - started_at) * 24 * 60 * 60).to_i
    yield(
      results.size,
      results,
      {
        scope: 'tijuana:taggings:last_id',
        scope_limit: latest_tagging_scope_limit,
        from: results.empty? ? nil : results.first[4],
        to: results.empty? ? nil : results.last[4],
        started_at: started_at,
        completed_at: DateTime.now,
        execution_time_seconds: execution_time_seconds,
        remaining_behind: tags_remaining_count
      },
      false
    )

    results.count < tags_remaining_count
  end
end
