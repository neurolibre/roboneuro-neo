# frozen_string_literal: true

require 'octokit'
require 'faraday'
require 'json'

module CoarNotify
  module Services
    # GitHubNotifier adapter for posting COAR Notify results to GitHub
    #
    # This service acts as an adapter between COAR Notify processing
    # and roboneuro's GitHub integration. It handles:
    # - Posting comments to review issues
    # - Querying neurolibre API for paper data
    # - Updating paper metadata in neurolibre
    #
    # Example usage:
    #   GitHubNotifier.post_comment(issue_id, "Review received!")
    #   issue_id = GitHubNotifier.get_issue_by_doi("10.55458/neurolibre.00027")
    class GitHubNotifier
      class << self
        # Post a comment to a GitHub issue
        #
        # @param issue_id [Integer] GitHub issue number
        # @param message [String] comment body (markdown supported)
        # @return [Sawyer::Resource, nil] GitHub comment object or nil if failed
        def post_comment(issue_id, message)
          return nil unless issue_id

          github_client.add_comment(
            reviews_repository,
            issue_id,
            message
          )
        rescue Octokit::Error => e
          warn "COAR Notify: Failed to post GitHub comment to issue #{issue_id}: #{e.message}"
          nil
        end

        # Get review issue ID from neurolibre by paper DOI
        #
        # @param doi [String] paper DOI (e.g., "10.55458/neurolibre.00027")
        # @return [Integer, nil] review issue ID or nil if not found
        def get_issue_by_doi(doi)
          return nil unless doi

          response = Faraday.get(
            "#{neurolibre_api_url}/api_lookup_by_doi",
            { doi: doi, secret: roboneuro_secret }
          )

          if response.success?
            data = JSON.parse(response.body)
            data['review_issue_id']
          end
        rescue Faraday::Error, JSON::ParserError => e
          warn "COAR Notify: Failed to query neurolibre API for DOI #{doi}: #{e.message}"
          nil
        end

        # Update paper metadata in neurolibre with COAR review data
        #
        # @param doi [String] paper DOI
        # @param review_data [Hash] review metadata
        # @option review_data [String] :review_url URL of the review
        # @option review_data [String] :service service name (e.g., "prereview")
        # @option review_data [String] :notification_id COAR notification ID
        # @return [Boolean] true if successful, false otherwise
        def update_paper_metadata(doi, review_data)
          return false unless doi

          response = Faraday.post(
            "#{neurolibre_api_url}/api_update_coar_review",
            {
              secret: roboneuro_secret,
              doi: doi,
              review: review_data
            }.to_json,
            {
              'Content-Type' => 'application/json'
            }
          )

          response.success?
        rescue Faraday::Error => e
          warn "COAR Notify: Failed to update neurolibre metadata for DOI #{doi}: #{e.message}"
          false
        end

        # Get paper data from neurolibre by issue ID
        #
        # @param issue_id [Integer] GitHub issue ID
        # @return [Hash, nil] paper data or nil if not found
        def get_paper_by_issue(issue_id)
          return nil unless issue_id

          response = Faraday.get(
            "#{neurolibre_api_url}/api_paper_by_issue",
            { issue_id: issue_id, secret: roboneuro_secret }
          )

          if response.success?
            JSON.parse(response.body, symbolize_names: true)
          end
        rescue Faraday::Error, JSON::ParserError => e
          warn "COAR Notify: Failed to get paper for issue #{issue_id}: #{e.message}"
          nil
        end

        private

        # Get configured GitHub client
        #
        # @return [Octokit::Client] authenticated GitHub client
        def github_client
          @github_client ||= Octokit::Client.new(
            access_token: ENV['BUFFY_GH_ACCESS_TOKEN']
          )
        end

        # Get reviews repository name
        #
        # @return [String] repository in format "owner/repo"
        def reviews_repository
          ENV['REVIEWS_REPOSITORY'] || 'neurolibre/neurolibre-reviews'
        end

        # Get neurolibre API base URL
        #
        # @return [String] base URL for neurolibre API
        def neurolibre_api_url
          ENV['NEUROLIBRE_API_URL'] || 'https://neurolibre.org/papers'
        end

        # Get roboneuro secret for API authentication
        #
        # @return [String] secret token
        def roboneuro_secret
          ENV['ROBONEURO_SECRET']
        end
      end
    end
  end
end
