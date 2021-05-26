require 'omniauth-oauth2'
require 'base64'

module OmniAuth
  module Strategies
    class Clever < OmniAuth::Strategies::OAuth2
      API_VERSION = 'v3.0'
      # Clever is a unique OAuth 2.0 service provider in that login sequences
      # are often initiated by Clever, not the client. When Clever initiates
      # login, a state parameter is not relevant nor sent.

      option :name, "clever"
      option :client_options, {
        :site          => 'https://api.clever.com',
        :authorize_url => 'https://clever.com/oauth/authorize',
        :token_url     => 'https://clever.com/oauth/tokens'
      }

      option :get_user_info, false

      # This option bubbles up to the OmniAuth::Strategies::OAuth2
      # when we call super in the callback_phase below.
      # **State will still be verified** when login is initiated by the client.
      option :provider_ignores_state, true

      def token_params
        super.tap do |params|
          params[:headers] = {'Authorization' => "Basic #{Base64.strict_encode64("#{options.client_id}:#{options.client_secret}")}"}
        end
      end

      def callback_phase
        error = request.params["error_reason"] || request.params["error"]
        stored_state = session.delete("omniauth.state")
        if error
          fail!(error, CallbackError.new(request.params["error"], request.params["error_description"] || request.params["error_reason"], request.params["error_uri"]))
        else
          # Only verify state if we've initiated login and have stored a state
          # to compare to.
          if stored_state && (!request.params["state"] || request.params["state"] != stored_state)
            fail!(:csrf_detected, CallbackError.new(:csrf_detected, "CSRF detected"))
          else
            super
          end
        end
      end

      uid{ raw_info.dig('data','id') }

      info do
        { :user_type => raw_info['type'] }.merge(raw_info['data'] || {}).merge(raw_user_info['data'] || {})
      end

      extra do
        {
          'raw_info' => raw_info,
          'raw_user_info' => raw_user_info
        }
      end

      def raw_info
        @raw_info ||= _raw_info
      end

      def _raw_info
        access_token.get("/#{API_VERSION}/me").parsed
      end

      def raw_user_info
        @raw_user_info ||= _raw_user_info
      end

      def _raw_user_info
        if options.get_user_info
          user_id = raw_info.dig('data','id')
          if user_id
            return access_token.get("/#{API_VERSION}/users/#{user_id}").parsed
          end
        end

        {}
      end

      # Fix unknown redirect uri bug by NOT appending the query string to the callback url.
      def callback_url
        full_host + script_name + callback_path
      end
    end
  end
end
