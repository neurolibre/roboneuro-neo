# frozen_string_literal: true

module CoarNotify
  # Default configuration values for COAR Notify
  #
  # These defaults are used as fallbacks when YAML configuration
  # or environment variables are not provided.
  module Defaults
    # Get default configuration values
    # @return [Hash] default configuration
    def self.config
      @config ||= {
        enabled: false,
        inbox_url: 'https://robo.neurolibre.org/coar_notify/inbox',
        service_id: 'https://neurolibre.org',
        database_url: 'sqlite::memory:',
        ip_whitelist_enabled: false,
        allowed_ips: [],
        sql_log_level: 'WARN',
        # Credentials deliberately default to nil so that an unconfigured
        # deploy fails closed rather than exposing the outbox or dashboard.
        outbox_secret: nil,
        dashboard_user: nil,
        dashboard_password: nil
      }
    end

    # Reset defaults (useful for testing)
    def self.reset!
      @config = nil
    end
  end
end
