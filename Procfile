release: bash -c 'if [ "$COAR_NOTIFY_ENABLED" != "true" ]; then echo "COAR Notify disabled, skipping migrations"; elif [ -z "$DATABASE_URL" ]; then echo "COAR_NOTIFY_ENABLED is true but DATABASE_URL is not set; provision a database before enabling COAR Notify"; exit 1; else bundle exec sequel -m db/migrations "$DATABASE_URL"; fi'
web: bundle exec puma -C ./puma-config.rb
worker: bundle exec sidekiq -t 45 -r ./app/lib/workers.rb
