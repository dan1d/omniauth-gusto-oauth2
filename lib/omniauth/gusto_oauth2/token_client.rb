# frozen_string_literal: true

require 'faraday'
require 'json'

module OmniAuth
  module GustoOauth2
    # Client for managing Gusto OAuth2 tokens outside the OmniAuth flow.
    #
    # Gusto access tokens expire after 2 hours. Refresh tokens never expire
    # but are single-use — each refresh returns a new refresh token.
    #
    # @example Basic usage
    #   client = OmniAuth::GustoOauth2::TokenClient.new(
    #     client_id: ENV['GUSTO_CLIENT_ID'],
    #     client_secret: ENV['GUSTO_CLIENT_SECRET']
    #   )
    #
    #   result = client.refresh_token(account.refresh_token)
    #   if result.success?
    #     account.update!(
    #       access_token: result.access_token,
    #       refresh_token: result.refresh_token,
    #       token_expires_at: Time.at(result.expires_at)
    #     )
    #   end
    #
    class TokenClient
      class TokenResult
        attr_reader :access_token, :refresh_token, :expires_at, :expires_in, :error, :raw_response

        def initialize(success:, access_token: nil, refresh_token: nil, expires_at: nil, expires_in: nil,
                       error: nil, raw_response: nil)
          @success = success
          @access_token = access_token
          @refresh_token = refresh_token
          @expires_at = expires_at
          @expires_in = expires_in
          @error = error
          @raw_response = raw_response
        end

        def success?
          @success
        end

        def failure?
          !@success
        end
      end

      TOKEN_URL = 'https://api.gusto.com/oauth/token'

      attr_reader :client_id, :client_secret

      def initialize(client_id:, client_secret:, redirect_uri: nil)
        @client_id = client_id
        @client_secret = client_secret
        @redirect_uri = redirect_uri
      end

      # Refresh an access token using a refresh token.
      # Gusto refresh tokens are single-use — always store the new refresh_token.
      #
      # @param refresh_token [String] The refresh token to use
      # @return [TokenResult] Result object with new tokens or error
      def refresh_token(refresh_token)
        return TokenResult.new(success: false, error: 'Refresh token is required') if refresh_token.nil? || refresh_token.empty?

        response = make_refresh_request(refresh_token)

        if response.success?
          parse_success_response(response)
        else
          parse_error_response(response)
        end
      rescue Faraday::Error => e
        TokenResult.new(success: false, error: "Network error: #{e.message}")
      rescue JSON::ParserError => e
        TokenResult.new(success: false, error: "Invalid JSON response: #{e.message}")
      rescue StandardError => e
        TokenResult.new(success: false, error: "Unexpected error: #{e.message}")
      end

      # Check if a token is expired or about to expire
      #
      # @param expires_at [Time, Integer] Token expiration time
      # @param buffer_seconds [Integer] Buffer before expiration (default: 300 = 5 minutes)
      # @return [Boolean] True if token is expired or will expire within buffer
      def token_expired?(expires_at, buffer_seconds: 300)
        return true if expires_at.nil?

        expires_at_time = expires_at.is_a?(Integer) ? Time.at(expires_at) : expires_at
        Time.now >= (expires_at_time - buffer_seconds)
      end

      private

      def make_refresh_request(refresh_token)
        body = {
          grant_type: 'refresh_token',
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token
        }
        body[:redirect_uri] = @redirect_uri if @redirect_uri

        Faraday.post(TOKEN_URL) do |req|
          req.headers['Content-Type'] = 'application/json'
          req.headers['Accept'] = 'application/json'
          req.body = body.to_json
        end
      end

      def parse_success_response(response)
        data = JSON.parse(response.body)

        expires_in = data['expires_in']&.to_i
        expires_at = expires_in ? Time.now.to_i + expires_in : nil

        TokenResult.new(
          success: true,
          access_token: data['access_token'],
          refresh_token: data['refresh_token'],
          expires_in: expires_in,
          expires_at: expires_at,
          raw_response: data
        )
      end

      def parse_error_response(response)
        error_data = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          { 'message' => response.body }
        end

        error_message = error_data['error_description'] || error_data['error'] || "HTTP #{response.status}"

        TokenResult.new(
          success: false,
          error: error_message,
          raw_response: error_data
        )
      end
    end
  end
end
