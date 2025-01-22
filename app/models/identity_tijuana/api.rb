module IdentityTijuana
  class API
    def initialize(url = nil, secret = nil)
      @url = url || Settings.tijuana.api.url
      @secret = secret || Settings.tijuana.api.secret

      @client = HTTPClient.new
      @headers = { 'Auth-Token' => @secret }
    end

    def tag_emails(tag, emails, listcut)
      params = { tag: tag, :"emails[]" => emails, listcut: listcut }
      res = @client.post(@url, params, @headers)
      if (res.status < 200) || (res.status >= 300)
        message = "Tijuana HTTP POST failed: #{res.status}:#{res.reason}"
        Rails.logger.debug message
        Rails.logger.debug res.body
        raise message
      end
    end
  end
end
