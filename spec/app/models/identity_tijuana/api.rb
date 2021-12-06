
describe IdentityTijuana::API do
  before(:each) do
    allow(Settings).to receive_message_chain("tijuana.push_batch_amount") { 10 }
    allow(Settings).to receive_message_chain("tijuana.api.url") { "http://tijuana" }
    allow(Settings).to receive_message_chain("tijuana.api.secret") { "blarg" }

    @api = IdentityTijuana::API.new
  end

  context '#tag_emails' do
    context 'with no server' do
      it 'raises an error' do
        stub_request(:post, "tijuana").to_raise(Errno::ECONNREFUSED)
        expect {
          @api.tag_emails('test_tag', [])
        }.to raise_error(Errno::ECONNREFUSED)
      end
    end

    context 'with error 500' do
      it 'raises an error' do
        stub_request(:post, "tijuana").to_return(status: [500, "Test Error"])
        expect {
          @api.tag_emails('test_tag', [])
        }.to raise_error(RuntimeError)
      end
    end
  end
end
