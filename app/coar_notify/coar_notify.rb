# frozen_string_literal: true

require 'sequel'
require 'coarnotify'
require 'logger'
require_relative 'lib/config_loader'

# CoarNotify module for COAR Notify protocol integration
#
# This module implements W3C Linked Data Notifications (LDN) and
# COAR Notify protocol support for roboneuro.
#
# Architecture: Option 2 - Embedded receiver/consumer with persistent storage
#
# Usage:
#   CoarNotify.enabled?
#   CoarNotify.inbox_url
#   CoarNotify.configure { |config| ... }
module CoarNotify
  # Add app directory to load path for autoloading
  $LOAD_PATH.unshift(File.expand_path('../..', __dir__)) unless $LOAD_PATH.include?(File.expand_path('../..', __dir__))

  # Autoload models
  module Models
    autoload :Notification, File.expand_path('models/notification', __dir__)
    autoload :ServiceRegistry, File.expand_path('models/service_registry', __dir__)
  end

  # Autoload services
  module Services
    autoload :Sender, File.expand_path('services/sender', __dir__)
    autoload :Receiver, File.expand_path('services/receiver', __dir__)
    autoload :Processor, File.expand_path('services/processor', __dir__)
    autoload :GitHubNotifier, File.expand_path('services/github_notifier', __dir__)
  end

  # Autoload workers
  module Workers
    autoload :SendWorker, File.expand_path('workers/send_worker', __dir__)
    autoload :ReceiveWorker, File.expand_path('workers/receive_worker', __dir__)
  end

  # Autoload routes
  module Routes
    autoload :Inbox, File.expand_path('routes/inbox', __dir__)
    autoload :Dashboard, File.expand_path('routes/inbox_ui', __dir__)
    autoload :Outbox, File.expand_path('routes/outbox', __dir__)
  end

  class << self
    # Get configuration (loaded from YAML or ENV)
    # @return [Hash] configuration hash
    def config
      @config ||= ConfigLoader.load
    end

    # Reset configuration (useful for testing)
    def reset_config!
      @config = nil
      ConfigLoader.reset!
    end

    # Check if COAR Notify is enabled
    # @return [Boolean] true if enabled
    def enabled?
      # Try YAML config first, then ENV, then default
      config[:enabled] || ENV['COAR_NOTIFY_ENABLED'] == 'true'
    end

    # Get the inbox URL for this instance
    # @return [String] inbox URL
    def inbox_url
      # Priority: YAML > ENV > default
      config[:inbox_url] || ENV['COAR_INBOX_URL'] || 'https://robo.neurolibre.org/coar_notify/inbox'
    end

    # Get the service ID for this instance
    # @return [String] service ID
    def service_id
      # Priority: YAML > ENV > default
      config[:service_id] || ENV['COAR_SERVICE_ID'] || 'https://neurolibre.org'
    end

    # Check if IP whitelist is enabled
    # @return [Boolean] true if enabled
    def ip_whitelist_enabled?
      # Priority: YAML > ENV > default
      config[:ip_whitelist_enabled] || ENV['COAR_IP_WHITELIST_ENABLED'] == 'true'
    end

    # Get allowed IPs for whitelist
    # @return [Array<String>] list of allowed IP addresses
    def allowed_ips
      # Priority: YAML > ENV > default
      config[:allowed_ips] || parse_allowed_ips_from_env || []
    end

    # Shared secret required to POST to the outbox
    #
    # Returns nil when unset, in which case the outbox refuses all requests.
    #
    # @return [String, nil] outbox secret
    def outbox_secret
      value = config[:outbox_secret] || ENV['COAR_OUTBOX_SECRET'] || ENV['ROBONEURO_SECRET']
      value.nil? || value.empty? ? nil : value
    end

    # Username for dashboard basic auth
    # @return [String, nil] dashboard user
    def dashboard_user
      value = config[:dashboard_user] || ENV['COAR_DASHBOARD_USER']
      value.nil? || value.empty? ? nil : value
    end

    # Password for dashboard basic auth
    # @return [String, nil] dashboard password
    def dashboard_password
      value = config[:dashboard_password] || ENV['COAR_DASHBOARD_PASSWORD']
      value.nil? || value.empty? ? nil : value
    end

    # Whether the dashboard has credentials configured
    #
    # The dashboard serves reviewer identities and full notification payloads,
    # so it stays closed unless both a user and a password are set.
    #
    # @return [Boolean] true when the dashboard may serve requests
    def dashboard_configured?
      !dashboard_user.nil? && !dashboard_password.nil?
    end

    # Get database connection
    # @return [Sequel::Database] database connection
    def database
      @database ||= establish_database_connection
    end

    # Configure the module
    # @yield configuration block
    def configure
      yield self if block_given?
    end

    # Initialize the module (called on app boot)
    def init!
      return unless enabled?

      # Establish database connection first
      @database = establish_database_connection

      setup_database

      # Models will use the shared database connection via CoarNotify.database
      # No need to load them here - they'll be autoloaded when needed
    end

    private

    def parse_allowed_ips_from_env
      ips_string = ENV['COAR_ALLOWED_IPS']
      return nil if ips_string.nil? || ips_string.empty?
      ips_string.split(',').map(&:strip).reject(&:empty?)
    end

    def establish_database_connection
      # Priority: YAML > ENV > default
      database_url = config[:database_url] || ENV['DATABASE_URL']

      unless database_url
        warn 'COAR Notify: DATABASE_URL not set, using in-memory SQLite (not recommended for production)'
        database_url = 'sqlite::memory:'
      end

      db = Sequel.connect(database_url)

      # SQL logging - configure via sql_log_level in config YAML or COAR_SQL_LOG_LEVEL env var
      # Valid levels: DEBUG, INFO, WARN, ERROR, FATAL
      logger = Logger.new($stderr)
      log_level_str = config[:sql_log_level] || 'WARN'
      logger.level = Logger.const_get(log_level_str.upcase)
      db.loggers << logger

      # Enable PostgreSQL extensions globally and on database
      if db.database_type == :postgres
        # Load extensions globally on Sequel module (required for Sequel.pg_jsonb, etc.)
        Sequel.extension :pg_array
        Sequel.extension :pg_json

        # Also load on database instance (required for column operations)
        db.extension :pg_array
        db.extension :pg_json  # For JSONB column support
      end

      db
    end

    def setup_database
      # Set up Sequel plugins globally
      Sequel::Model.plugin :timestamps
      # NOT using validation_helpers due to SQL generation bugs
    end

  end
end
