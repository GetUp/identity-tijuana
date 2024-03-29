# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 0) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gin"
  enable_extension "btree_gist"
  enable_extension "intarray"
  enable_extension "pg_trgm"
  enable_extension "plpgsql"

  create_table "active_record_audits", id: :serial, force: :cascade do |t|
    t.integer "auditable_id"
    t.string "auditable_type"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.json "audited_changes"
    t.integer "version", default: 0
    t.text "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at", precision: nil
    t.index ["associated_id", "associated_type"], name: "associated_index"
    t.index ["auditable_id", "auditable_type"], name: "auditable_index"
    t.index ["created_at"], name: "index_active_record_audits_on_created_at"
    t.index ["request_uuid"], name: "index_active_record_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "addresses", force: :cascade do |t|
    t.integer "member_id", null: false
    t.text "line1"
    t.text "line2"
    t.text "town"
    t.text "postcode"
    t.text "country"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "canonical_address_id"
    t.string "state"
    t.index ["canonical_address_id"], name: "index_addresses_on_canonical_address_id"
    t.index ["member_id"], name: "index_addresses_on_member_id"
  end

  create_table "area_memberships", force: :cascade do |t|
    t.integer "area_id", null: false
    t.integer "member_id", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["area_id"], name: "index_area_memberships_on_area_id"
    t.index ["member_id"], name: "index_area_memberships_on_member_id"
  end

  create_table "area_zips", id: :serial, force: :cascade do |t|
    t.integer "area_id", null: false
    t.string "zip"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["area_id"], name: "index_area_zips_on_area_id"
    t.index ["zip"], name: "index_area_zips_on_zip"
  end

  create_table "areas", force: :cascade do |t|
    t.text "name"
    t.text "code"
    t.integer "mapit"
    t.text "area_type"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text "party"
    t.text "runner_up_party"
    t.integer "majority"
    t.integer "vote_count"
    t.text "representative_name"
    t.text "representative_gender"
  end

  create_table "canonical_addresses", id: :serial, force: :cascade do |t|
    t.string "official_id"
    t.text "line1"
    t.text "line2"
    t.text "town"
    t.string "state"
    t.string "postcode"
    t.string "country"
    t.float "latitude"
    t.float "longitude"
    t.text "search_text"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["official_id"], name: "index_canonical_addresses_on_official_id"
    t.index ["postcode"], name: "index_canonical_addresses_on_postcode"
    t.index ["search_text"], name: "canonical_addresses_search_text", opclass: :gist_trgm_ops, using: :gist
  end

  create_table "contact_campaigns", id: :serial, force: :cascade do |t|
    t.text "name"
    t.integer "external_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "system"
    t.string "contact_type"
  end

  create_table "contact_response_keys", id: :serial, force: :cascade do |t|
    t.integer "contact_campaign_id"
    t.string "key"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["contact_campaign_id"], name: "index_contact_response_keys_on_contact_campaign_id"
  end

  create_table "contact_responses", id: :serial, force: :cascade do |t|
    t.integer "contact_id", null: false
    t.text "value"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "contact_response_key_id", null: false
    t.index ["contact_id"], name: "index_contact_responses_on_contact_id"
    t.index ["contact_response_key_id"], name: "index_contact_responses_on_contact_response_key_id"
  end

  create_table "contacts", id: :serial, force: :cascade do |t|
    t.integer "contactee_id", null: false
    t.integer "contactor_id"
    t.integer "contact_campaign_id"
    t.string "external_id"
    t.string "contact_type"
    t.string "system"
    t.string "status"
    t.text "notes"
    t.integer "duration"
    t.datetime "happened_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.json "data", default: "{}"
    t.index ["contact_campaign_id"], name: "index_contacts_on_contact_campaign_id"
    t.index ["contact_type"], name: "index_contacts_on_contact_type"
    t.index ["contactee_id"], name: "index_contacts_on_contactee_id"
    t.index ["contactor_id"], name: "index_contacts_on_contactor_id"
    t.index ["external_id"], name: "index_contacts_on_external_id"
  end

  create_table "custom_field_keys", id: :serial, force: :cascade do |t|
    t.text "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean "read_only", default: false, null: false
    t.boolean "categorical", default: false, null: false
    t.string "categories", default: [], array: true
    t.index ["name"], name: "index_custom_field_keys_on_name"
  end

  create_table "custom_fields", id: :serial, force: :cascade do |t|
    t.integer "custom_field_key_id", null: false
    t.text "data"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "member_id", null: false
    t.index ["custom_field_key_id"], name: "index_custom_fields_on_custom_field_key_id"
    t.index ["member_id"], name: "index_custom_fields_on_member_id"
  end

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer "priority", default: 0
    t.integer "attempts", default: 0
    t.text "handler"
    t.text "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string "locked_by"
    t.string "queue"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "list_members", id: :serial, force: :cascade do |t|
    t.integer "list_id", null: false
    t.integer "member_id", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "deleted_at"
    t.index ["list_id"], name: "index_list_members_on_list_id"
    t.index ["member_id"], name: "index_list_members_on_member_id"
  end

  create_table "lists", force: :cascade do |t|
    t.text "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "member_count", default: 0, null: false
    t.boolean "synced_to_redshift", default: false, null: false
    t.bigint "search_id"
    t.bigint "author_id"
    t.index ["search_id"], name: "index_lists_on_search_id"
    t.index ["synced_to_redshift"], name: "index_lists_on_synced_to_redshift"
  end

  create_table "member_external_ids", id: :serial, force: :cascade do |t|
    t.integer "member_id", null: false
    t.string "system", null: false
    t.string "external_id", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["member_id"], name: "index_member_external_ids_on_member_id"
    t.index ["system", "external_id"], name: "index_member_external_ids_on_system_and_external_id", unique: true
  end

  create_table "member_subscriptions", id: :serial, force: :cascade do |t|
    t.integer "subscription_id", null: false
    t.integer "member_id", null: false
    t.datetime "unsubscribed_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text "unsubscribe_reason"
    t.text "subscribe_reason"
    t.boolean "permanent"
    t.integer "unsubscribe_mailing_id"
    t.index ["member_id", "subscription_id"], name: "index_member_subscriptions_on_member_id_and_subscription_id", unique: true
    t.index ["member_id"], name: "index_member_subscriptions_on_member_id"
    t.index ["subscription_id"], name: "index_member_subscriptions_on_subscription_id"
    t.index ["unsubscribe_mailing_id"], name: "index_member_subscriptions_on_unsubscribe_mailing_id"
  end

  create_table "members", force: :cascade do |t|
    t.integer "cons_id"
    t.text "email"
    t.json "contact"
    t.json "meta"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "joined_at"
    t.text "crypted_password"
    t.text "guid"
    t.json "action_history"
    t.text "reset_token"
    t.integer "authy_id"
    t.integer "point_person_id"
    t.integer "role_id"
    t.datetime "last_donated"
    t.integer "donations_count"
    t.float "average_donation"
    t.float "highest_donation"
    t.text "mosaic_group"
    t.text "mosaic_code"
    t.text "entry_point"
    t.float "latitude"
    t.float "longitude"
    t.string "email_sha256"
    t.text "first_name"
    t.text "middle_names"
    t.text "last_name"
    t.string "title"
    t.string "gender"
    t.string "donation_preference", limit: 20
    t.index ["email"], name: "index_members_on_email"
    t.index ["first_name"], name: "index_members_on_first_name"
    t.index ["last_name"], name: "index_members_on_last_name"
    t.index ["point_person_id"], name: "index_members_on_point_person_id"
    t.index ["role_id"], name: "index_members_on_role_id"
  end

  create_table "organisation_memberships", force: :cascade do |t|
    t.integer "member_id", null: false
    t.integer "organisation_id", null: false
    t.text "notes"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["member_id"], name: "index_organisation_memberships_on_member_id"
    t.index ["organisation_id"], name: "index_organisation_memberships_on_organisation_id"
  end

  create_table "organisations", force: :cascade do |t|
    t.text "name"
    t.text "notes"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "permissions", id: :serial, force: :cascade do |t|
    t.text "permission_slug"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "phone_numbers", force: :cascade do |t|
    t.integer "member_id", null: false
    t.text "phone", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text "phone_type"
    t.index ["member_id"], name: "index_phone_numbers_on_member_id"
    t.index ["phone"], name: "index_phone_numbers_on_phone"
  end

  create_table "postcodes", id: :serial, force: :cascade do |t|
    t.string "zip"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.float "latitude"
    t.float "longitude"
    t.index ["zip"], name: "index_postcodes_on_zip"
  end

  create_table "role_permissions", id: :serial, force: :cascade do |t|
    t.integer "role_id", null: false
    t.integer "permission_id", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", id: :serial, force: :cascade do |t|
    t.integer "role_id"
    t.text "description"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "searches", force: :cascade do |t|
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text "name"
    t.boolean "complete"
    t.text "member_ids"
    t.integer "total_members"
    t.integer "offset"
    t.integer "count"
    t.integer "page"
    t.text "rules"
    t.text "sql"
    t.boolean "pinned", default: false, null: false
  end

  create_table "subscriptions", id: :serial, force: :cascade do |t|
    t.text "name"
    t.text "description"
    t.datetime "deleted_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "member_count", default: 0
    t.string "slug", null: false
    t.index ["slug"], name: "index_subscriptions_on_slug", unique: true
  end

  create_table "syncs", force: :cascade do |t|
    t.string "external_system", null: false
    t.string "external_system_params"
    t.string "sync_type", null: false
    t.string "status", default: "initialising", null: false
    t.integer "imported_member_count", default: 0, null: false
    t.integer "progress", default: 0, null: false
    t.string "message"
    t.bigint "list_id"
    t.bigint "contact_campaign_id"
    t.bigint "author_id"
    t.json "reference_data", default: "{}"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_syncs_on_author_id"
    t.index ["contact_campaign_id"], name: "index_syncs_on_contact_campaign_id"
    t.index ["list_id"], name: "index_syncs_on_list_id"
  end

end
