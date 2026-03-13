# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OmniAuth::GustoOauth2::TokenClient do
  let(:client) do
    described_class.new(
      client_id: 'test_client_id',
      client_secret: 'test_client_secret'
    )
  end

  describe '#refresh_token' do
    context 'when refresh succeeds' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .with(
            body: {
              'grant_type' => 'refresh_token',
              'client_id' => 'test_client_id',
              'client_secret' => 'test_client_secret',
              'refresh_token' => 'old_refresh_token'
            }.to_json
          )
          .to_return(
            status: 200,
            body: {
              access_token: 'new_access_token',
              refresh_token: 'new_refresh_token',
              expires_in: 7200
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns a successful TokenResult' do
        result = client.refresh_token('old_refresh_token')

        expect(result).to be_success
        expect(result).not_to be_failure
        expect(result.access_token).to eq('new_access_token')
        expect(result.refresh_token).to eq('new_refresh_token')
        expect(result.expires_in).to eq(7200)
        expect(result.expires_at).to be_within(5).of(Time.now.to_i + 7200)
      end
    end

    context 'when initialized with redirect_uri' do
      let(:client) do
        described_class.new(
          client_id: 'test_client_id',
          client_secret: 'test_client_secret',
          redirect_uri: 'https://example.com/callback'
        )
      end

      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .with(
            body: {
              'grant_type' => 'refresh_token',
              'client_id' => 'test_client_id',
              'client_secret' => 'test_client_secret',
              'refresh_token' => 'old_refresh_token',
              'redirect_uri' => 'https://example.com/callback'
            }.to_json
          )
          .to_return(
            status: 200,
            body: {
              access_token: 'new_access_token',
              refresh_token: 'new_refresh_token',
              expires_in: 7200
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'includes redirect_uri in the request' do
        result = client.refresh_token('old_refresh_token')

        expect(result).to be_success
      end
    end

    context 'when refresh fails with HTTP error' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .to_return(
            status: 401,
            body: { error: 'invalid_grant', error_description: 'Refresh token is invalid' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns a failed TokenResult with error message' do
        result = client.refresh_token('bad_token')

        expect(result).to be_failure
        expect(result).not_to be_success
        expect(result.error).to eq('Refresh token is invalid')
      end
    end

    context 'when refresh fails with non-JSON response' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns a failed TokenResult with HTTP status' do
        result = client.refresh_token('some_token')

        expect(result).to be_failure
        expect(result.error).to eq('HTTP 500')
      end
    end

    context 'when refresh fails with error field only' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .to_return(
            status: 400,
            body: { error: 'invalid_request' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'falls back to error field' do
        result = client.refresh_token('some_token')

        expect(result).to be_failure
        expect(result.error).to eq('invalid_request')
      end
    end

    context 'when refresh fails with no error fields' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .to_return(
            status: 503,
            body: {}.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'falls back to HTTP status' do
        result = client.refresh_token('some_token')

        expect(result).to be_failure
        expect(result.error).to eq('HTTP 503')
      end
    end

    context 'when refresh token is nil' do
      it 'returns a failed TokenResult' do
        result = client.refresh_token(nil)

        expect(result).to be_failure
        expect(result.error).to eq('Refresh token is required')
      end
    end

    context 'when refresh token is empty' do
      it 'returns a failed TokenResult' do
        result = client.refresh_token('')

        expect(result).to be_failure
        expect(result.error).to eq('Refresh token is required')
      end
    end

    context 'when network error occurs' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .to_raise(Faraday::ConnectionFailed.new('connection refused'))
      end

      it 'returns a failed TokenResult with network error' do
        result = client.refresh_token('some_token')

        expect(result).to be_failure
        expect(result.error).to include('Network error')
      end
    end

    context 'when response body is invalid JSON on success' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .to_return(status: 200, body: 'not json at all')
      end

      it 'returns a failed TokenResult with JSON parse error' do
        result = client.refresh_token('some_token')

        expect(result).to be_failure
        expect(result.error).to include('Invalid JSON response')
      end
    end

    context 'when an unexpected error occurs' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .to_raise(RuntimeError.new('something broke'))
      end

      it 'returns a failed TokenResult with unexpected error' do
        result = client.refresh_token('some_token')

        expect(result).to be_failure
        expect(result.error).to include('Unexpected error')
      end
    end

    context 'when response has no expires_in' do
      before do
        stub_request(:post, 'https://api.gusto.com/oauth/token')
          .to_return(
            status: 200,
            body: { access_token: 'token', refresh_token: 'refresh' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns nil for expires_at and expires_in' do
        result = client.refresh_token('old_token')

        expect(result).to be_success
        expect(result.expires_at).to be_nil
        expect(result.expires_in).to be_nil
      end
    end
  end

  describe '#token_expired?' do
    it 'returns true when expires_at is nil' do
      expect(client.token_expired?(nil)).to be true
    end

    it 'returns true when token is expired' do
      expect(client.token_expired?(Time.now - 3600)).to be true
    end

    it 'returns true when token expires within buffer' do
      expect(client.token_expired?(Time.now + 60, buffer_seconds: 300)).to be true
    end

    it 'returns false when token is still valid' do
      expect(client.token_expired?(Time.now + 3600)).to be false
    end

    it 'handles integer timestamps' do
      expect(client.token_expired?(Time.now.to_i + 3600)).to be false
    end

    it 'handles expired integer timestamps' do
      expect(client.token_expired?(Time.now.to_i - 3600)).to be true
    end
  end
end
