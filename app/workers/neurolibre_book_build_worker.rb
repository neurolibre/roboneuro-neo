# This is the Sidekiq worker that processes Jupyter Books.
# Where possible, we try and capture errors from any of the
# executed tasks and report them back to the review issue.

require_relative '../lib/github'
require_relative '../lib/neurolibre_utilities'

class NeurolibreBookBuildWorker < BuffyWorker

    # Include to communicate from background worker to GitHub
    include GitHub
    include NeurolibreUtilities
  
    def perform(locals, url, branch, issue_id, production)
      load_context_and_env(locals)

      if production
        # Perform the task for the fork (roboneurolibre)
        url = url.sub(%r{github.com/[^/]+/}, "github.com/roboneurolibre/")
      end

      latest_sha = get_target_latest_sha(url, branch)
  
      if latest_sha.nil?
        respond "Requested branch/SHA does not exist for #{url}"
      else
        post_params = {
          :id => issue_id,
          :repo_url => url,
          :commit_hash => latest_sha
        }.to_json
      end
  
      content_validation = validate_target_repo_structure(url, branch)
  
      if content_validation['response'] == false
        respond(content_validation['reason'])
      end
  
      # Make sure that there's not a book on NeuroLibre servers 
      # built from the exact same commit hash. 
      book_exists_result = get_built_books(commit_sha:latest_sha)

      if book_exists_result == nil

        #gpt_quote = get_funny_quote(url)
        # Respond in issue with update that book is building
        #respond " :seedling: I've started building your NeuroLibre reproducible preprint! :seedling: \n\n My close :robot: friend GPT read your `paper.md` and noted: \n> #{gpt_quote} "

        # Send book build request
        # build_results = request_book_build(post_params)
        
        request_book_build(post_params)

        # # Success
        # if build_results['status'] == 200
        #   book_url = build_results['book_message']['book_url']
        #   message = ":hibiscus: Awesome news! :hibiscus:  \n > Your build was successful and [the latest version of your reproducible preprint](#{book_url}) is ready for you to check out :confetti_ball: \n```\n#{build_results['binder_message']}\n```"
        #   respond(message)
        # end

        # # Fail reason 1
        # if build_results['status'] == 404
        #   log_message = get_book_build_log(build_results['binder_message'],url,latest_sha,false)
        #   respond(log_message)
        # end

        # # Fail reason 2
        # if build_results['status'] == 424
        #   # When passed, the last argument to function overrides the default method 
        #   # for getting book build logs. Given that code 424 may involve a case 
        #   # where book-buil.log does not exist, this ensures that a custom message 
        #   # is displayed. 
        #   log_message = get_book_build_log(build_results['binder_message'],url,latest_sha,false,build_results['book_message'])
        #   respond(log_message)
        # end

      else

        respond " :eyes: Looks like the reproducible preprint you requested has been already built: \n```\n#{book_exists_result}\n```"
      
      end
  
      
  
    end
  end