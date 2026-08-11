# frozen_string_literal: true

require 'yaml'

module CoarNotify
  module Models
    # ServiceRegistry manages external COAR Notify service configurations
    #
    # Services are defined in config/services.yml and include:
    # - Service metadata (name, ID, inbox URL)
    # - Supported COAR Notify patterns
    #
    # Example usage:
    #   ServiceRegistry.get('prereview')
    #   ServiceRegistry.inbox_url('prereview')
    #   ServiceRegistry.name_from_id('https://prereview.org')
    class ServiceRegistry
      class << self
        # Get all configured services
        # @return [Hash] service configurations
        def all
          @services ||= load_services
        end

        # Get configuration for a specific service
        # @param service_name [String, Symbol] service name (e.g., 'prereview')
        # @return [Hash, nil] service configuration or nil if not found
        def get(service_name)
          all[service_name.to_s]
        end

        # Get inbox URL for a service
        # @param service_name [String, Symbol] service name
        # @return [String, nil] inbox URL or nil if service not found
        def inbox_url(service_name)
          get(service_name)&.dig('inbox_url')
        end

        # Find service name from service ID URL
        # @param service_id [String] service ID URL (e.g., 'https://prereview.org')
        # @return [String, nil] service name or nil if not found
        def name_from_id(service_id)
          all.find { |_key, config| config['id'] == service_id }&.first
        end

        # Get human-readable display name
        # @param service_name [String, Symbol] service name
        # @return [String, nil] display name or nil if service not found
        def display_name(service_name)
          get(service_name)&.dig('name')
        end

        # Check if service supports a specific pattern
        # @param service_name [String, Symbol] service name
        # @param pattern [String] COAR Notify pattern (e.g., 'RequestReview')
        # @return [Boolean] true if pattern is supported
        def supports_pattern?(service_name, pattern)
          config = get(service_name)
          return false unless config

          supported = config['supported_patterns'] || []
          supported.include?(pattern)
        end

        # List all available service names
        # @return [Array<String>] service names
        def service_names
          all.keys
        end

        # Reload service configurations from file
        # Useful for testing or after config changes
        def reload!
          @services = nil
          all
        end

        private

        def load_services
          config_path = File.join(__dir__, '../config/services.yml')

          unless File.exist?(config_path)
            warn "COAR Notify: services.yml not found at #{config_path}"
            return {}
          end

          yaml_content = YAML.load_file(config_path)
          yaml_content['services'] || {}
        rescue => e
          warn "COAR Notify: Failed to load services.yml: #{e.message}"
          {}
        end
      end
    end
  end
end
