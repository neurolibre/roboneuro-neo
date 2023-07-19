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

      puts url
      puts email

      latest_sha = get_target_latest_sha(url, branch)
      puts latest_sha

      if latest_sha.nil?
        # respond "Requested branch/SHA does not exist for #{url}"
      else
        parameters = {"repo_url": url,"commit_hash": latest_sha, "email": email}
      end

      puts parameters
      #request_book_build_test(parameters)

    end
  end