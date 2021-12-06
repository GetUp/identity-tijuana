require 'rails_helper'

describe IdentityTijuana do
  context '#push' do
    before(:each) do
      clean_external_database

      @sync_id = 1
      @external_system_params = JSON.generate({'tag' => 'test_tag'})

      2.times { FactoryBot.create(:member) }
      FactoryBot.create(:member_without_email)
      @members = Member.all
    end

    context 'with valid parameters' do
      it 'yeilds members_with_emails' do
        IdentityTijuana.push(@sync_id, @members, @external_system_params) do |members_with_emails, campaign_name|
          expect(members_with_emails.count).to eq(2)
        end
      end
    end
  end

  context '#push_in_batches' do
    before(:each) do
      clean_external_database

      expect_any_instance_of(IdentityTijuana::API).to receive(:tag_emails).with(anything, anything) {{ }}

      @sync_id = 1
      @external_system_params = JSON.generate({'tag' => 'test_tag'})

      allow(Settings).to receive_message_chain("tijuana.push_batch_amount") { 10 }
      allow(Settings).to receive_message_chain("tijuana.api.url") { "http://tijuana" }
      allow(Settings).to receive_message_chain("tijuana.api.secret") { "blarg" }

      2.times { FactoryBot.create(:member) }
      FactoryBot.create(:member_without_email)
      @members = Member.all.with_email
    end

    context 'with valid parameters' do
      it 'yeilds correct batch_index' do
        IdentityTijuana.push_in_batches(1, @members, @external_system_params) do |batch_index, write_result_count|
          expect(batch_index).to eq(0)
        end
      end
      #TODO update with write results
      it 'yeilds write_result_count' do
        IdentityTijuana.push_in_batches(1, @members, @external_system_params) do |batch_index, write_result_count|
          expect(write_result_count).to eq(0)
        end
      end
    end
  end

  context 'with server errors' do
    before(:each) do
      clean_external_database

      @sync_id = 1
      @external_system_params = JSON.generate({'tag' => 'test_tag'})

      allow(Settings).to receive_message_chain("tijuana.push_batch_amount") { 10 }
      allow(Settings).to receive_message_chain("tijuana.api.url") { "http://tijuana" }
      allow(Settings).to receive_message_chain("tijuana.api.secret") { "blarg" }

      2.times { FactoryBot.create(:member) }
      FactoryBot.create(:member_without_email)
      @members = Member.all.with_email
    end

    it 'raises an error on connection refused' do
      stub_request(:post, "tijuana").to_raise(Errno::ECONNREFUSED)
      expect {
        IdentityTijuana.push_in_batches(1, @members, @external_system_params)
      }.to raise_error(Errno::ECONNREFUSED)
    end

    it 'raises an error on error 500' do
      stub_request(:post, "tijuana").to_return(status: [500, "Test Error"])
      expect {
        IdentityTijuana.push_in_batches(1, @members, @external_system_params)
      }.to raise_error(RuntimeError)
    end
  end
end
