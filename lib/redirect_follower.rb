require 'net/https'
require "addressable/uri"

class RedirectFollower
  REDIRECT_DEFAULT_LIMIT = 5
  class TooManyRedirects < StandardError; end

  attr_accessor :url, :body, :redirect_limit, :response, :headers

  def initialize(url, limit = REDIRECT_DEFAULT_LIMIT, options = {})
    if limit.is_a? Hash
      options = limit
      limit = REDIRECT_DEFAULT_LIMIT
    end
    @url, @redirect_limit = url, limit
    @headers = options[:headers] || {}
  end

  def resolve
    raise TooManyRedirects if redirect_limit < 0

    uri = Addressable::URI.parse(url).normalize

    http = Net::HTTP.new(uri.host, uri.inferred_port)
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end

    self.response = http.request_get(uri.request_uri, @headers)

    if response.kind_of?(Net::HTTPRedirection)
      self.url = redirect_url
      self.redirect_limit -= 1
      resolve
    end

    charset = nil
    if content_type = response['content-type']
      if content_type =~ /charset=(.+)/i
        charset = $1
      end
    end

    if charset
      self.body = response.body.force_encoding(charset).encode('utf-8')
    else
      self.body = response.body
    end

    self
  end

  def redirect_url
    if response['location'].nil?
      response.body.match(/<a href=\"([^>]+)\">/i)[1]
    else
      response['location']
    end
  end
end
