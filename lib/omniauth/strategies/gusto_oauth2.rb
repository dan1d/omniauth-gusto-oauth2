# frozen_string_literal: true

require 'omniauth-oauth2'
require 'json'

module OmniAuth
  module Strategies
    # OmniAuth strategy for Gusto OAuth2.
    #
    # Gusto uses standard OAuth2 with 2-hour access tokens and single-use refresh tokens.
    # The authorize and token endpoints are on api.gusto.com.
    # User info is fetched via GET /v1/me.
    #
    # @example Basic usage
    #   provider :gusto_oauth2, ENV['GUSTO_CLIENT_ID'], ENV['GUSTO_CLIENT_SECRET']
    #
    # @example With Devise
    #   config.omniauth :gusto_oauth2, ENV['GUSTO_CLIENT_ID'], ENV['GUSTO_CLIENT_SECRET']
    #
    class GustoOauth2 < OmniAuth::Strategies::OAuth2
      option :name, 'gusto_oauth2'

      option :client_options, {
        site: 'https://api.gusto.com',
        authorize_url: '/oauth/authorize',
        token_url: '/oauth/token',
        auth_scheme: :request_body
      }

      # UID is the resource owner UUID from /v1/token_info
      uid { raw_info['uuid'] }

      info do
        {
          email: raw_info['email'],
          name: raw_info['name'],
          first_name: raw_info['first_name'],
          last_name: raw_info['last_name'],
          company_uuid: raw_info['company_uuid'],
          company_name: raw_info['company_name']
        }
      end

      extra do
        { raw_info: raw_info }
      end

      def raw_info
        @raw_info ||= fetch_user_and_company_info
      end

      # Override to strip query params from callback_url for redirect_uri matching.
      # Gusto requires the redirect_uri to match exactly.
      def build_access_token
        redirect_uri = callback_url.sub(/\?.*/, '')
        log(:info, "Token exchange — site: #{client.site}, redirect_uri: #{redirect_uri}")
        verifier = request.params['code']
        client.auth_code.get_token(
          verifier,
          { redirect_uri: redirect_uri }.merge(token_params.to_hash(symbolize_keys: true)),
          deep_symbolize(options.auth_token_params)
        )
      rescue ::OAuth2::Error => e
        log(:error, "Token exchange FAILED: status=#{e.response&.status} body=#{e.response&.body}")
        raise
      end

      private

      API_VERSION = '2024-04-01'

      ME_URL = '/v1/me'
      TOKEN_INFO_URL = '/v1/token_info'

      def api_headers
        { 'Accept' => 'application/json', 'X-Gusto-API-Version' => API_VERSION }
      end

      def fetch_user_and_company_info
        me_data = fetch_me
        token_data = fetch_token_info

        company = me_data['companies']&.first || {}

        {
          'uuid' => token_data.dig('resource_owner', 'uuid') || me_data['uuid'],
          'email' => me_data['email'],
          'first_name' => me_data['first_name'],
          'last_name' => me_data['last_name'],
          'name' => [me_data['first_name'], me_data['last_name']].compact.join(' '),
          'company_uuid' => company['uuid'] || token_data.dig('resource', 'uuid'),
          'company_name' => company['name']
        }
      rescue StandardError => e
        log(:warn, "Failed to fetch user/company info: #{e.message}")
        { 'uuid' => nil }
      end

      def fetch_me
        response = access_token.get(ME_URL, headers: api_headers)
        JSON.parse(response.body)
      end

      def fetch_token_info
        response = access_token.get(TOKEN_INFO_URL, headers: api_headers)
        JSON.parse(response.body)
      end

      def log(level, message)
        return unless defined?(OmniAuth.logger) && OmniAuth.logger

        OmniAuth.logger.send(level, "[GustoOauth2] #{message}")
      end
    end
  end
end
