class CreateTijuanaTestDb < ActiveRecord::Migration[5.0]
  def up
    create_table "blasts", force: :cascade do |t|
      t.integer  "push_id",        limit: 4
      t.string   "name",           limit: 255
      t.datetime "deleted_at"
      t.datetime "created_at",                 null: false
      t.datetime "updated_at",                 null: false
      t.integer  "delayed_job_id", limit: 4
      t.datetime "sent_at"
      t.string   "blast_type",     limit: 255
      t.string   "test_feature",   limit: 255
      t.string   "objective",      limit: 255
    end

    add_index "blasts", ["updated_at"], name: "index_blasts_on_updated_at", using: :btree

    create_table "campaigns", force: :cascade do |t|
      t.string   "name",                  limit: 64
      t.text     "description",           limit: 65535
      t.datetime "created_at",                                          null: false
      t.datetime "updated_at",                                          null: false
      t.datetime "deleted_at"
      t.string   "created_by",            limit: 255
      t.string   "updated_by",            limit: 255
      t.integer  "alternate_key",         limit: 4
      t.boolean  "opt_out",                             default: true
      t.integer  "theme_id",              limit: 4,     default: 1,     null: false
      t.string   "slug",                  limit: 255
      t.string   "accounts_key",          limit: 255
      t.boolean  "quarantined"
      t.boolean  "hidden_in_admin",                     default: false
      t.string   "default_email_name",    limit: 255
      t.string   "default_email_address", limit: 255
      t.string   "default_email_reply",   limit: 255
    end

    add_index "campaigns", ["accounts_key"], name: "index_campaigns_on_accounts_key", using: :btree
    add_index "campaigns", ["slug"], name: "index_campaigns_on_slug", using: :btree
    add_index "campaigns", ["updated_at"], name: "index_campaigns_on_updated_at", using: :btree

    create_table "content_module_links", force: :cascade do |t|
      t.integer "page_id",           limit: 4,  null: false
      t.integer "content_module_id", limit: 4,  null: false
      t.integer "position",          limit: 4
      t.string  "layout_container",  limit: 64
    end

    add_index "content_module_links", ["content_module_id"], name: "index_content_module_links_on_content_module_id", using: :btree

    create_table "content_modules", force: :cascade do |t|
      t.string   "type",                            limit: 64,    null: false
      t.text     "content",                         limit: 65535
      t.datetime "created_at",                                    null: false
      t.datetime "updated_at",                                    null: false
      t.text     "options",                         limit: 65535
      t.string   "title",                           limit: 128
      t.string   "public_activity_stream_template", limit: 255
      t.integer  "alternate_key",                   limit: 4
    end

    add_index "content_modules", ["type"], name: "index_content_modules_on_type", using: :btree

    create_table "emails", force: :cascade do |t|
      t.integer  "blast_id",              limit: 4
      t.string   "name",                  limit: 255
      t.text     "sent_to_users_ids",     limit: 16777215
      t.string   "from_address",          limit: 255
      t.string   "reply_to_address",      limit: 255
      t.string   "subject",               limit: 255
      t.text     "body",                  limit: 16777215
      t.datetime "deleted_at"
      t.datetime "created_at",                                             null: false
      t.datetime "updated_at",                                             null: false
      t.datetime "test_sent_at"
      t.integer  "delayed_job_id",        limit: 4
      t.string   "from_name",             limit: 255
      t.string   "footer",                limit: 255
      t.datetime "cut_completed_at"
      t.integer  "get_together_id",       limit: 4
      t.boolean  "secure_links",                           default: false
      t.boolean  "body_is_html_document",                  default: false
      t.boolean  "body_is_graphic_email",                  default: false
      t.string   "preview_text",          limit: 255
    end

    add_index "emails", ["updated_at"], name: "index_emails_on_updated_at", using: :btree

    create_table "page_sequences", force: :cascade do |t|
      t.integer  "campaign_id",                       limit: 4
      t.string   "name",                              limit: 218
      t.datetime "created_at"
      t.datetime "updated_at"
      t.datetime "deleted_at"
      t.string   "created_by",                        limit: 255
      t.string   "updated_by",                        limit: 255
      t.integer  "alternate_key",                     limit: 4
      t.text     "options",                           limit: 65535
      t.integer  "theme_id",                          limit: 4
      t.string   "last_page_url",                     limit: 255
      t.string   "slug",                              limit: 255
      t.boolean  "welcome_email_disabled"
      t.boolean  "quarantined"
      t.boolean  "pillar_pin",                                      default: false
      t.boolean  "pillar_show",                                     default: false
      t.text     "title",                             limit: 255
      t.text     "blurb",                             limit: 255
      t.boolean  "expired",                                         default: false
      t.datetime "expires_at"
      t.integer  "expired_redirect_page_sequence_id", limit: 4
      t.string   "accounts_key",                      limit: 255
    end

    add_index "page_sequences", ["accounts_key"], name: "index_page_sequences_on_accounts_key", using: :btree
    add_index "page_sequences", ["campaign_id"], name: "index_page_sequences_on_campaign_id", using: :btree
    add_index "page_sequences", ["slug"], name: "index_page_sequences_on_slug", using: :btree
    add_index "page_sequences", ["updated_at"], name: "index_page_sequences_on_updated_at", using: :btree

    create_table "pages", force: :cascade do |t|
      t.integer  "page_sequence_id",       limit: 4
      t.string   "name",                   limit: 64
      t.datetime "created_at"
      t.datetime "updated_at"
      t.datetime "deleted_at"
      t.integer  "position",               limit: 4
      t.text     "required_user_details",  limit: 65535
      t.boolean  "send_thankyou_email",                  default: false
      t.text     "thankyou_email_text",    limit: 65535
      t.string   "thankyou_email_subject", limit: 255
      t.integer  "views",                  limit: 4,     default: 0,     null: false
      t.string   "created_by",             limit: 255
      t.string   "updated_by",             limit: 255
      t.integer  "alternate_key",          limit: 4
      t.boolean  "paginate_main_content",                default: false
      t.boolean  "no_wrapper"
      t.string   "member_value_type",      limit: 8
      t.string   "slug",                   limit: 255
      t.string   "thankyou_email_from",    limit: 255
    end

    add_index "pages", ["page_sequence_id"], name: "index_pages_on_page_sequence_id", using: :btree
    add_index "pages", ["slug"], name: "index_pages_on_slug", using: :btree
    add_index "pages", ["thankyou_email_from"], name: "index_pages_on_thankyou_email_from", using: :btree
    add_index "pages", ["updated_at"], name: "index_pages_on_updated_at", using: :btree

    create_table "pushes", force: :cascade do |t|
      t.integer  "campaign_id",                  limit: 4
      t.string   "name",                         limit: 255
      t.datetime "deleted_at"
      t.datetime "created_at",                                               null: false
      t.datetime "updated_at",                                               null: false
      t.datetime "locked_at"
      t.boolean  "override_no_email_today_rule",             default: false, null: false
    end

    add_index "pushes", ["updated_at"], name: "index_pushes_on_updated_at", using: :btree

    create_table 'tags', force: :cascade do |t|
      t.string  'name',           limit: 255
      t.integer 'taggings_count', limit: 4, default: 0
      t.integer 'author_id', limit: 4
    end

    add_index 'tags', ['name'], name: 'index_tags_on_name', unique: true, using: :btree

    create_table 'taggings', force: :cascade do |t|
      t.integer  'tag_id',        limit: 4
      t.integer  'taggable_id',   limit: 4
      t.string   'taggable_type', limit: 255
      t.integer  'tagger_id',     limit: 4
      t.string   'tagger_type',   limit: 255
      t.string   'context',       limit: 128
      t.datetime 'created_at'
    end

    add_index 'taggings', %w[tag_id taggable_id taggable_type context], name: 'taggind_idx', unique: true, using: :btree
    add_index 'taggings', %w[taggable_id taggable_type tag_id], name: 'tags_list_cutter_idx', using: :btree

    create_table 'users', force: :cascade do |t|
      t.string   'email',                        limit: 256, null: false
      t.string   'first_name',                   limit: 64
      t.string   'last_name',                    limit: 64
      t.string   'mobile_number',                limit: 32
      t.string   'home_number',                  limit: 32
      t.string   'street_address',               limit: 128
      t.string   'suburb',                       limit: 64
      t.string   'country_iso',                  limit: 2
      t.datetime 'created_at'
      t.datetime 'updated_at'
      t.boolean  'is_member', default: true, null: false
      t.boolean  'do_not_call', default: false, null: false
      t.string   'encrypted_password',           limit: 255
      t.string   'password_salt',                limit: 255
      t.string   'reset_password_token',         limit: 255
      t.datetime 'remember_created_at'
      t.integer  'sign_in_count', limit: 4, default: 0
      t.datetime 'current_sign_in_at'
      t.datetime 'last_sign_in_at'
      t.string   'current_sign_in_ip',           limit: 255
      t.string   'last_sign_in_ip',              limit: 255
      t.boolean  'is_admin', default: false
      t.datetime 'deleted_at'
      t.string   'created_by',                   limit: 255
      t.string   'updated_by',                   limit: 255
      t.integer  'postcode_id',                  limit: 4
      t.string   'old_tags',                     limit: 3072,  default: '',    null: false
      t.string   'new_tags',                     limit: 512,   default: '',    null: false
      t.boolean  'is_volunteer',                               default: false
      t.float    'random',                       limit: 24
      t.string   'fragment',                     limit: 255
      t.boolean  'is_agra_member', default: true
      t.datetime 'reset_password_sent_at'
      t.text     'notes',                        limit: 65_535
      t.string   'quick_donate_trigger_id',      limit: 255
      t.boolean  'low_volume', default: false
      t.datetime 'address_validated_at'
      t.string   'facebook_id',                  limit: 50
      t.string   'otp_secret_key',               limit: 255
      t.integer  'second_factor_attempts_count', limit: 4, default: 0
      t.boolean  'do_not_sms', default: false, null: false
    end

    add_index 'users', ['created_at'], name: 'created_at_idx', using: :btree
    add_index 'users', %w[deleted_at first_name], name: 'index_users_on_deleted_at_and_first_name', using: :btree
    add_index 'users', %w[deleted_at is_member], name: 'member_status', using: :btree
    add_index 'users', %w[deleted_at last_name], name: 'index_users_on_deleted_at_and_last_name', using: :btree
    add_index 'users', %w[deleted_at notes], name: 'index_users_on_deleted_at_and_notes', length: { 'deleted_at' => nil, 'notes' => 200 }, using: :btree
    add_index 'users', %w[deleted_at postcode_id], name: 'postcode_id_idx', using: :btree
    add_index 'users', %w[deleted_at suburb], name: 'index_users_on_deleted_at_and_suburb', using: :btree
    add_index 'users', ['email'], name: 'index_users_on_email', unique: true, length: { 'email' => 255 }, using: :btree
    add_index 'users', ['otp_secret_key'], name: 'index_users_on_otp_secret_key', unique: true, using: :btree
    add_index 'users', ['random'], name: 'users_random_idx', using: :btree
    add_index 'users', ['reset_password_token'], name: 'users_reset_password_token_idx', using: :btree
    add_index 'users', ['do_not_call'], name: 'index_users_on_do_not_call', using: :btree
    add_index 'users', ['do_not_sms'], name: 'index_users_on_do_not_sms', using: :btree

    create_table 'postcodes', force: :cascade do |t|
      t.string   'number',     limit: 255
      t.string   'state',      limit: 255
      t.datetime 'created_at'
      t.datetime 'updated_at'
      t.float    'longitude',  limit: 53
      t.float    'latitude',   limit: 53
    end
  end
end
