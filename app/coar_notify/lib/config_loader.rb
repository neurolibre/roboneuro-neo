# frozen_string_literal: true

require 'yaml'
require 'erb'
require_relative 'defaults'

module CoarNotify
  # Configuration loader for COAR Notify
  #
  # Loads configuration from YAML files with the following priority:
  # 1. YAML configuration (highest priority)
  # 2. Environment variables (fallback)
  # 3. Default values (last resort)
  #
  # Usage:
  #   config = CoarNotify::ConfigLoader.load
  #   config[:enabled]  # => true/false
  #   config[:inbox_url]  # => "http://..."
  module ConfigLoader
    class << self
      # Load configuration from YAML file
      # @param environment [String] the environment (development, test, production)
      # @return [Hash] merged configuration
      def load(environment = nil)
        env = environment || rack_environment
        yaml_config = load_yaml_config(env)

        # Merge: defaults < ENV vars < YAML
        merged_config = Defaults.config.dup

        if yaml_config
          # YAML config takes precedence
          merged_config.merge!(symbolize_keys(yaml_config))
        else
          # Fallback to ENV variables if YAML section doesn't exist
          merged_config.merge!(load_from_env)
        end

        merged_config
      end

      # Load and parse YAML configuration file
      # @param environment [String] the environment
      # @return [Hash, nil] parsed YAML config or nil if section doesn't exist
      def load_yaml_config(environment)
        config_path = File.expand_path("../../../../config/settings-#{environment}.yml", __FILE__)

        return nil unless File.exist?(config_path)

        # Parse ERB first, then YAML
        document = ERB.new(File.read(config_path)).result
        yaml = YAML.load(document)

        # Extract coar_notify section
        coar_config = yaml&.dig('coar_notify', 'env')

        coar_config
      rescue => e
        warn "CoarNotify::ConfigLoader: Failed to load YAML config: #{e.message}"
        nil
      end

      # Load configuration from environment variables
      # @return [Hash] configuration from ENV
      def load_from_env
        {
          enabled: ENV['COAR_NOTIFY_ENABLED'] == 'true',
          inbox_url: ENV['COAR_INBOX_URL'],
          service_id: ENV['COAR_SERVICE_ID'],
          database_url: ENV['DATABASE_URL'],
          ip_whitelist_enabled: ENV['COAR_IP_WHITELIST_ENABLED'] == 'true',
          allowed_ips: parse_allowed_ips(ENV['COAR_ALLOWED_IPS']),
          sql_log_level: ENV['COAR_SQL_LOG_LEVEL'],
          outbox_secret: ENV['COAR_OUTBOX_SECRET'] || ENV['ROBONEURO_SECRET'],
          dashboard_user: ENV['COAR_DASHBOARD_USER'],
          dashboard_password: ENV['COAR_DASHBOARD_PASSWORD']
        }.compact # Remove nil values
      end

      # Get current Rack environment
      # @return [String] environment name
      def rack_environment
        ENV['RACK_ENV'] || 'development'
      end

      # Parse allowed IPs from comma-separated string
      # @param ips_string [String] comma-separated IP addresses
      # @return [Array<String>] array of IP addresses
      def parse_allowed_ips(ips_string)
        return [] if ips_string.nil? || ips_string.empty?
        ips_string.split(',').map(&:strip).reject(&:empty?)
      end

      # Convert string keys to symbols recursively
      # @param hash [Hash] hash with string keys
      # @return [Hash] hash with symbol keys
      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym).transform_values do |value|
          value.is_a?(Hash) ? symbolize_keys(value) : value
        end
      end

      # Reset memoized configuration (useful for testing)
      def reset!
        Defaults.reset!
      end
    end
  end
end
