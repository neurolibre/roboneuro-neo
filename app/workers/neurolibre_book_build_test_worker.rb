# This is the Sidekiq worker that processes Jupyter Books.
# Where possible, we try and capture errors from any of the
# executed tasks and report them back to the review issue.

require_relative '../lib/github'
require_relative '../lib/neurolibre_utilities'

class NeurolibreBookBuildTestWorker < BuffyWorker

    # Include to communicate from background worker to GitHub
    include GitHub
    include NeurolibreUtilities
  
    def perform(url, sha, email, executable)
      if executable == "False"
        sha = "noexec"
      end
      parameters = {"repo_url": url,"commit_hash": sha, "email": email}
      puts parameters
      request_book_build_test(parameters)

    end
  end