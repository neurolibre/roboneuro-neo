# This is the Sidekiq worker that processes Jupyter Books.
# Where possible, we try and capture errors from any of the
# executed tasks and report them back to the review issue.

require_relative '../lib/github'
require_relative '../lib/neurolibre_utilities'

class NeurolibreBookBuildTestWorker < BuffyWorker

    # Include to communicate from background worker to GitHub
    include GitHub
    include NeurolibreUtilities
  
    def perform(url, branch, email)

      latest_sha = get_target_latest_sha(url, branch)

      if latest_sha.nil?
        # respond "Requested branch/SHA does not exist for #{url}"
      else
        post_params = {
          :repo_url => url,
          :commit_hash => latest_sha,
          :email => email
        }.to_json
      end

      request_book_build_test(post_params)

    end
  end