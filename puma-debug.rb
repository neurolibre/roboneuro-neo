# Simplified Puma config for debugging - single worker, no preload
# Usage: bundle exec puma -C ./puma-debug.rb

threads 1, 5
port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RACK_ENV") { "development" }

# No workers (single mode for easier debugging)
# No preload (errors show immediately)

# Show configuration on startup
begin
  require_relative 'app/coar_notify/coar_notify'

  puts "=" * 80
  puts "PUMA DEBUG MODE - Single worker, no preload"
  puts "Environment: #{ENV['RACK_ENV'] || 'development'}"
  puts
  puts "CoarNotify Configuration (from YAML):"
  puts "  enabled: #{CoarNotify.enabled?}"
  puts "  inbox_url: #{CoarNotify.inbox_url}"
  puts "  service_id: #{CoarNotify.service_id}"
  puts "  database_url: #{CoarNotify.config[:database_url] ? CoarNotify.config[:database_url].gsub(/:[^:@]+@/, ':***@') : 'NOT SET'}"
  puts "  ip_whitelist_enabled: #{CoarNotify.ip_whitelist_enabled?}"
  puts
  puts "Configuration source: config/settings-#{ENV['RACK_ENV'] || 'development'}.yml"
  puts "=" * 80
rescue => e
  puts "=" * 80
  puts "PUMA DEBUG MODE - Single worker, no preload"
  puts "Warning: Could not load CoarNotify configuration"
  puts "Error: #{e.message}"
  puts "=" * 80
end
