# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OmniAuth::Strategies::GustoOauth2 do
  let(:app) { ->(_env) { [200, {}, ['OK']] } }
  let(:strategy) { described_class.new(app, 'test_client_id', 'test_client_secret') }

  describe 'configuration' do
    it 'has correct name' do
      expect(strategy.options.name).to eq('gusto_oauth2')
    end

    it 'uses correct site' do
      expect(strategy.options.client_options.site).to eq('https://api.gusto.com')
    end

    it 'uses correct authorize URL' do
      expect(strategy.options.client_options.authorize_url).to eq('/oauth/authorize')
    end

    it 'uses correct token URL' do
      expect(strategy.options.client_options.token_url).to eq('/oauth/token')
    end

    it 'uses request_body auth scheme' do
      expect(strategy.options.client_options.auth_scheme).to eq(:request_body)
    end
  end

  describe 'info' do
    let(:raw_info) do
      {
        'uuid' => 'user-123',
        'email' => 'test@example.com',
        'first_name' => 'Jane',
        'last_name' => 'Doe',
        'name' => 'Jane Doe',
        'company_uuid' => 'company-456',
        'company_name' => "Jane's Restaurant"
      }
    end

    before do
      allow(strategy).to receive(:raw_info).and_return(raw_info)
    end

    it 'returns email' do
      expect(strategy.info[:email]).to eq('test@example.com')
    end

    it 'returns name' do
      expect(strategy.info[:name]).to eq('Jane Doe')
    end

    it 'returns first_name' do
      expect(strategy.info[:first_name]).to eq('Jane')
    end

    it 'returns last_name' do
      expect(strategy.info[:last_name]).to eq('Doe')
    end

    it 'returns company_uuid' do
      expect(strategy.info[:company_uuid]).to eq('company-456')
    end

    it 'returns company_name' do
      expect(strategy.info[:company_name]).to eq("Jane's Restaurant")
    end
  end

  describe 'uid' do
    before do
      allow(strategy).to receive(:raw_info).and_return('uuid' => 'user-123')
    end

    it 'returns uuid' do
      expect(strategy.uid).to eq('user-123')
    end
  end

  describe '#build_access_token' do
    let(:access_token) { instance_double(OAuth2::AccessToken) }
    let(:oauth_client) { instance_double(OAuth2::Client) }
    let(:auth_code) { instance_double(OAuth2::Strategy::AuthCode) }
    let(:rack_env) do
      {
        'rack.input' => StringIO.new,
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/auth/gusto_oauth2/callback',
        'QUERY_STRING' => 'code=test_code&state=test_state',
        'HTTP_HOST' => 'example.com'
      }
    end

    before do
      allow(oauth_client).to receive_messages(site: 'https://api.gusto.com', auth_code: auth_code)
      allow(auth_code).to receive(:get_token).and_return(access_token)
      allow(strategy).to receive_messages(client: oauth_client,
                                          callback_url: 'https://example.com/auth/gusto_oauth2/callback?code=test_code', request: Rack::Request.new(rack_env), token_params: OmniAuth::Strategy::Options.new({}), deep_symbolize: {})
    end

    it 'strips query params from callback_url for redirect_uri' do
      strategy.build_access_token

      expect(auth_code).to have_received(:get_token).with(
        'test_code',
        hash_including(redirect_uri: 'https://example.com/auth/gusto_oauth2/callback'),
        anything
      )
    end

    context 'when token exchange fails' do
      before do
        error_response = double('response', status: 400, body: 'Bad Request', headers: {}, parsed: {})
        allow(auth_code).to receive(:get_token).and_raise(OAuth2::Error.new(error_response))
      end

      it 're-raises the OAuth2 error' do
        expect { strategy.build_access_token }.to raise_error(OAuth2::Error)
      end
    end

    context 'when token exchange fails with nil response on error' do
      before do
        error = OAuth2::Error.allocate
        allow(error).to receive_messages(response: nil, message: 'OAuth2 error')
        allow(auth_code).to receive(:get_token).and_raise(error)
      end

      it 'handles nil response gracefully' do
        expect { strategy.build_access_token }.to raise_error(OAuth2::Error)
      end
    end
  end

  describe 'extra' do
    let(:raw_info) { { 'uuid' => 'user-123' } }

    before do
      allow(strategy).to receive(:raw_info).and_return(raw_info)
    end

    it 'includes raw_info' do
      expect(strategy.extra[:raw_info]).to eq(raw_info)
    end
  end

  describe '#raw_info' do
    let(:access_token) { instance_double(OAuth2::AccessToken) }
    let(:me_response) do
      instance_double(OAuth2::Response, body: {
        'uuid' => 'user-abc',
        'email' => 'jane@example.com',
        'first_name' => 'Jane',
        'last_name' => 'Doe',
        'companies' => [
          { 'uuid' => 'company-xyz', 'name' => "Jane's Restaurant" }
        ]
      }.to_json)
    end
    let(:token_info_response) do
      instance_double(OAuth2::Response, body: {
        'scope' => 'companies:read',
        'resource' => { 'type' => 'Company', 'uuid' => 'company-xyz' },
        'resource_owner' => { 'type' => 'CompanyAdmin', 'uuid' => 'admin-abc' }
      }.to_json)
    end

    before do
      allow(strategy).to receive(:access_token).and_return(access_token)
      allow(access_token).to receive(:get).with('/v1/me', anything).and_return(me_response)
      allow(access_token).to receive(:get).with('/v1/token_info', anything).and_return(token_info_response)
    end

    it 'fetches user and company info via REST API' do
      info = strategy.raw_info

      expect(info['uuid']).to eq('admin-abc')
      expect(info['email']).to eq('jane@example.com')
      expect(info['first_name']).to eq('Jane')
      expect(info['last_name']).to eq('Doe')
      expect(info['name']).to eq('Jane Doe')
      expect(info['company_uuid']).to eq('company-xyz')
      expect(info['company_name']).to eq("Jane's Restaurant")
    end

    it 'sends correct API version header to /v1/me' do
      strategy.raw_info

      expect(access_token).to have_received(:get).with(
        '/v1/me',
        hash_including(headers: hash_including('X-Gusto-API-Version' => '2024-04-01'))
      )
    end

    it 'sends correct API version header to /v1/token_info' do
      strategy.raw_info

      expect(access_token).to have_received(:get).with(
        '/v1/token_info',
        hash_including(headers: hash_including('X-Gusto-API-Version' => '2024-04-01'))
      )
    end

    context 'when API request fails' do
      before do
        allow(access_token).to receive(:get).and_raise(StandardError.new('connection refused'))
      end

      it 'returns fallback hash with nil uuid' do
        expect(strategy.raw_info).to eq('uuid' => nil)
      end
    end

    context 'when /v1/me returns no companies' do
      let(:me_response) do
        instance_double(OAuth2::Response, body: {
          'uuid' => 'user-abc',
          'email' => 'jane@example.com',
          'first_name' => 'Jane',
          'last_name' => nil,
          'companies' => []
        }.to_json)
      end

      it 'falls back to resource uuid from token_info and handles nil last_name' do
        info = strategy.raw_info

        expect(info['company_uuid']).to eq('company-xyz')
        expect(info['company_name']).to be_nil
        expect(info['name']).to eq('Jane')
      end
    end

    context 'when /v1/me returns no companies and token_info has no resource' do
      let(:me_response) do
        instance_double(OAuth2::Response, body: {
          'uuid' => 'user-abc',
          'email' => 'jane@example.com',
          'first_name' => 'Jane',
          'last_name' => 'Doe',
          'companies' => []
        }.to_json)
      end
      let(:token_info_response) do
        instance_double(OAuth2::Response, body: {
          'scope' => 'companies:read',
          'resource' => nil,
          'resource_owner' => { 'type' => 'CompanyAdmin', 'uuid' => 'admin-abc' }
        }.to_json)
      end

      it 'returns nil for company_uuid' do
        expect(strategy.raw_info['company_uuid']).to be_nil
      end
    end

    context 'when token_info has no resource_owner' do
      let(:token_info_response) do
        instance_double(OAuth2::Response, body: {
          'scope' => 'companies:read',
          'resource' => { 'type' => 'Company', 'uuid' => 'company-xyz' },
          'resource_owner' => nil
        }.to_json)
      end

      it 'falls back to uuid from /v1/me' do
        expect(strategy.raw_info['uuid']).to eq('user-abc')
      end
    end

    context 'when /v1/me returns nil companies key' do
      let(:me_response) do
        instance_double(OAuth2::Response, body: {
          'uuid' => 'user-abc',
          'email' => 'jane@example.com',
          'first_name' => 'Jane',
          'last_name' => 'Doe'
        }.to_json)
      end

      it 'handles missing companies key gracefully' do
        info = strategy.raw_info

        expect(info['company_uuid']).to eq('company-xyz')
        expect(info['company_name']).to be_nil
      end
    end

    context 'when OmniAuth.logger is nil' do
      before do
        allow(OmniAuth).to receive(:logger).and_return(nil)
        allow(access_token).to receive(:get).and_raise(StandardError.new('fail'))
      end

      it 'returns fallback without logging errors' do
        expect(strategy.raw_info).to eq('uuid' => nil)
      end
    end
  end
end
