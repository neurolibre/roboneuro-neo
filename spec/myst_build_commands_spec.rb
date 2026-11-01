# The MyST build commands, as the settings define them, against what full-stack-server's /api/myst/build accepts.
#
# full-stack-server validates the request body with MystBuildSchema (api/schema.py) and refuses a field it does not
# know with a 422, so a command sending a field the server lacks fails for every editor. This spec keeps the two
# in step: when the server's schema changes, change ACCEPTED here too.
#
# It reads the settings the way Buffy does (ERB, then YAML) and needs nothing from the app, so it also runs without
# the bundle.

require "erb"
require "yaml"

RSpec.describe "MyST build commands" do
  # MystBuildSchema in full-stack-server's api/schema.py
  ACCEPTED = %w[id repository_url commit_hash binder_hash is_prod build_cache prod_version fresh_execution].freeze
  REQUIRED = %w[id repository_url].freeze
  SETTINGS = %w[config/settings-production.yml config/settings-test.yml].freeze

  def myst_build_commands(file)
    path = File.expand_path("../#{file}", __dir__)
    settings = YAML.safe_load(ERB.new(File.read(path)).result, aliases: true)
    settings.dig("buffy", "responders", "external_service").map { |entry| entry.values.first }
            .select { |service| service["url"].to_s.end_with?("/api/myst/build") }
            .to_h { |service| [service["command"], service] }
  end

  def sent_fields(service)
    (service["query_params"] || {}).keys + (service["mapping"] || {}).keys
  end

  SETTINGS.each do |file|
    context file do
      let(:commands) { myst_build_commands(file) }

      it "sends only fields full-stack-server accepts, and the ones it requires" do
        commands.each do |command, service|
          expect(sent_fields(service) - ACCEPTED).to be_empty, "#{command} sends #{sent_fields(service) - ACCEPTED}"
          expect(REQUIRED - (service["mapping"] || {}).keys).to be_empty, "#{command} lacks #{REQUIRED}"
          expect(service["send_only_mapped"]).to be(true), "#{command} would also send fields the server refuses"
        end
      end

      it "describes each command differently" do
        descriptions = commands.values.map { |service| service["description"] }
        expect(descriptions.uniq.size).to eq(descriptions.size), "repeated: #{descriptions.tally.select { |_, n| n > 1 }.keys}"
      end

      it "has a preview build that runs every notebook again" do
        fresh = commands["build myst preview fresh"]
        expect(fresh).not_to be_nil
        expect(fresh["query_params"]).to include("binder_hash" => "latest", "is_prod" => false,
                                                 "build_cache" => true, "fresh_execution" => true)
      end

      it "keeps the ordinary preview build reusing cached outputs" do
        expect(commands["build myst preview"]["query_params"]).not_to include("fresh_execution" => true)
      end

      it "builds production from scratch, running every notebook in the paper's image" do
        expect(commands["build myst production"]["query_params"]).to include(
          "binder_hash" => "latest", "is_prod" => true, "build_cache" => false, "fresh_execution" => true)
        expect(commands["build myst production"]["mapping"]).to include("prod_version" => "preprint-version")
      end
    end
  end

  it "defines the same MyST build commands in production and test" do
    production, test = SETTINGS.map { |file| myst_build_commands(file) }
    expect(test.keys.sort).to eq(production.keys.sort)
    production.each do |command, service|
      expect(test[command].except("url")).to eq(service.except("url")), "#{command} differs"
    end
  end
end
