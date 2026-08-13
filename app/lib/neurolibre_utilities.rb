require 'uri'
require 'json'
require 'time'
require 'yaml'
require 'faraday'
require 'logger'
require_relative 'github'


include GitHub


# Move these to ENV later.
$TEST_DOMAIN="https://preview.neurolibre.org"
$TEST_SSL = true

$PROD_DOMAIN="https://preprint.neurolibre.org"
$PROD_SSL = true

module NeurolibreUtilities

    def neurolibre_test_client
        @neurolibre_test_client = Faraday.new(url: $TEST_DOMAIN) do |faraday|
          faraday.request :json
          faraday.ssl.verify = $TEST_SSL
          faraday.request :authorization, :basic, ENV['PREVIEW_API_USER'], ENV['PREVIEW_API_KEY']
        end
      end
    
    def neurolibre_prod_client
        @neurolibre_prod_client = Faraday.new(url: $PROD_DOMAIN) do |faraday|
          faraday.request :json
          faraday.ssl.verify = $PROD_SSL
          faraday.request :authorization, :basic, ENV['PREVIEW_API_USER'], ENV['PREVIEW_API_KEY']
        end
    end

    class << self
        attr_accessor :logo
        attr_accessor :header_start
        attr_accessor :header_finish
        attr_accessor :footer
      end
      self.logo = "https://raw.githubusercontent.com/neurolibre/docs.neurolibre.com/master/source/img/logo_neurolibre_old.png"
      self.header_start = """
                          <div style=\"background-color:#333;padding:3px;border-radius:10px;\">
                          <center><img src=\" https://github.com/neurolibre/brand/blob/main/png/neurolibre_test_start.png?raw=true \" height=\"200px\"></img>
                          </div>
                          """
      self.header_finish = """
                          <div style=\"background-color:#333;padding:3px;border-radius:10px;\">
                          <center><img src=\" https://github.com/neurolibre/brand/blob/main/png/neurolibre_test_finish.png?raw=true \" height=\"200px\"></img>
                          </div>
                          """
          self.footer =   """
                          <div style=\"background-color:#333;height:70px;border-radius:10px;\">
                          <p><img src=\" https://github.com/neurolibre/neurolibre.com/blob/master/static/img/favicon.png?raw=true \" height=\"70px\" style=\"float:left;\"></p>
                          <p><a href=\"https://twitter.com/neurolibre?lang=en\"><img style=\"height:45px;margin-right:10px;float:right;margin-top:12px;\" src=\"https://cdn2.iconfinder.com/data/icons/black-white-social-media/32/online_social_media_twitter-512.png\"></a></p>
                          <a href=\"https://github.com/neurolibre\"><img style=\"height:45px;margin-right:10px;float:right;margin-top:12px;\" src=\"https://cdn2.iconfinder.com/data/icons/black-white-social-media/64/github_social_media_logo-512.png\"></a>
                          <a href=\"https://neurolibre.herokuapp.com\"><img style=\"height:45px;margin-right:10px;float:right;margin-top:12px;\" src=\"https://cdn3.iconfinder.com/data/icons/black-white-social-media/32/www_logo_social_media-512.png\"></a>
                          </p></div>
                          """

    def get_repo_owner_and_name(in_address, for_pdf=false)

        if for_pdf
            uri = URI(in_address)
            if uri.kind_of?(URI::HTTP) or uri.kind_of?(URI::HTTPS)
                # This is full url, fetch user/repo
                target_repo = uri # user/repo
            else
                # assumes username/repo
                target_repo = "https://github.com/#{in_address}"
            end
        else
            uri = URI(in_address)
            if uri.kind_of?(URI::HTTP) or uri.kind_of?(URI::HTTPS)
                # This is full url, fetch user/repo
                target_repo = uri.path[1...] # user/repo
            else
                # assumes username/repo
                target_repo = in_address
            end
        end

        return target_repo
    end

    def get_target_latest_sha(target_repository_url, branch=nil)
        
        target_repo = get_repo_owner_and_name(target_repository_url)

        if branch.nil? || branch.empty?
            begin
                sha = github_client.commits(target_repo).map {|c,a| [c.sha]}.first
            rescue
                sha = nil
            end
        else
            begin
                sha = github_client.commit(target_repo,branch)['sha']
            rescue
                sha = nil
            end
        end

        if sha.kind_of?(Array)
            return sha[0]
        else
            return sha
        end

    end


    def get_built_books(commit_sha: nil,user_name: nil,repo_name: nil, server_type: "test")
        # [Book]->[GET /api/book]
        # Exists in both preprint and production servers.
        # See the swagger API docs at https://preview.neurolibre.org/documentation#/Book/get_api_book
        # This function sends the request to the API endpoint documented in the above line.
        # All the details regarding API calls are available in the Swagger documentation.

        # This function returns a JSON array containing fields:
        # - time_added
        # - book_url
        # - download_link
        # Depending on the request, array length would be > 1. In that case,
        # elements will be returned in reverse chronological order so that
        # result[0] corresponds to the latest.

        # This endpoint exists on both types of server, set requested domain
        server_type == "test" ? active_client = neurolibre_test_client : active_client = neurolibre_prod_client
        
        # Send request to the /api/book endpoint
        response = active_client.get('/api/book') do |req|
          if !commit_sha.nil?
            req.params['commit_hash'] = commit_sha
          elsif !user_name.nil?
            req.params['user_name'] = user_name
          elsif !repo_name.nil?
            req.params['repo_name'] = repo_name
          end
        end

        # On success, multiple outputs possible depending on
        # which keys were used for the request and how many 
        # resources were returned. 
        case response.status
        when 200..299
          result = JSON.parse(response.body)
          if result.is_a?(Array) && result.length()==1
              result = result.map {|c| {:time_added => Time.parse(c['time_added']),:book_url => c['book_url'], :download_url => c['download_url'] }}.to_json
          elsif result.is_a?(Array) && result.length() >1
              # Array in reverse chronological order
              result = result.map {|c| {:time_added => Time.parse(c['time_added']),:book_url => c['book_url'], :download_url => c['download_url'] }}.sort_by { |hash| hash[:time_added].to_i }.reverse.to_json
          end
        when 400..499
          result = nil
          warn "Requested book does not exist on the NeuroLibre #{server_type} server (yet)."
        else
          result = nil
        end

        # Return the result
        return result
    end

    def request_book_build(payload_in)
        
        response = neurolibre_test_client.post('/api/book/build', payload_in)
        Logger.new(STDOUT).warn(response)
    
    end

    def request_book_build_test(payload_in)
        
        response = neurolibre_test_client.post('/api/book/build/test', payload_in.to_json)
        Logger.new(STDOUT).warn(response)
    
    end


    def get_book_build_log(binder_message,url,hash,success,book_message=nil)
        # Uses static GET to locate files. 
        # This is allowed under the `book-artifacts` directory and for its subdirectories.
        jblogs = []

        if !success
            binder_log = "<p>&#129344; We ran into a problem building your book. Please see the log files below.</p><details><summary> <b>BinderHub build log</b> </summary><pre><code>#{binder_message}</code></pre></details><p>If the BinderHub build looks OK, please see the Jupyter Book build log(s) below.</p>"
            jblogs.push(binder_log)
        else
            jblogs.push("<p>&#127882; For your reference, we're sharing the logs.</p>")
            jblogs.push("<details><summary> <b>BinderHub build log</b> </summary><pre><code>#{binder_message}</code></pre></details>")
        end

        target_repo = get_repo_owner_and_name(url)
        uname = target_repo.split("/")[0]
        repo = target_repo.split("/")[1]

        if book_message.nil?
            # To handle certain errors, book build may be passed as an argument
            # If not, fetch from the server.
            cur_response = neurolibre_test_client.get("/book-artifacts/#{uname}/github.com/#{repo}/#{hash}/book-build.log")
            book_log = "<details><summary> <b>Jupyter Book build log</b> </summary><pre><code>#{cur_response.body}</code></pre></details>"
        else
            book_log = "<details><summary> <b>Jupyter Book build log</b> </summary><pre><code>#{book_message}</code></pre></details>"
        end

        # Add book logs to the response
        jblogs.push(book_log)

        cur_response = neurolibre_test_client.get("/book-artifacts/#{uname}/github.com/#{repo}/#{hash}/_build/html/reports/")

        case cur_response.status
        when 404
            Logger.new(STDOUT).warn("No execution reports, all or none succeeded.")
        when 200
            # If reports directory exists, so should some logs there.
            txt = cur_response.body
            rgx = /href=['"]\K[^'"]+.log/
            logs = txt.scan(rgx)
            logs.each do |log_file|
                log = neurolibre_test_client.get("/book-artifacts/#{uname}/github.com/#{repo}/#{hash}/_build/html/reports/#{log_file}")
                cur_log= "<details><summary> <b>Execution error log</b> for <code>#{log_file.gsub(/\..*/, "")}</code> notebook (#{log_file.gsub(/\..*/, "")}.ipynb) or MyST (#{log_file.gsub(/\..*/, "")}.md)).</summary><pre><code>#{log.body}</code></pre></details>"
                jblogs.push(cur_log)
            end
        end

        if !success
            msg = "<p>&#128030; After inspecting the logs above, you can interactively debug your notebooks on our <a href=\"https://binder.conp.cloud\">BinderHub server</a>.</p> <p>For guidelines, please see <a href=\"https://docs.neurolibre.org/en/latest/TEST_SUBMISSION.html#debugging-for-long-neurolibre-submission\">the relevant documentation.</a></p>"
            jblogs.push(msg)
        else
            msg = "<p>If you are happy with the final version of your reproducible preprint, please see <a href=\"https://docs.neurolibre.org\">our documentation</a> to publish it.</p>"
            jblogs.push(msg)
        end
        # Return logs 
        return jblogs.join('')
    end

    def validate_target_repo_structure(url, branch)
        # Returns a JSON array containing fields:
        # - response
        # - reason
        # If response is true, then the repository meets minimum file/folder
        # level requirements. Otherwise, reason indicates why the repo
        # is not valid.

        uri = URI(url)
        target_user_repo = uri.path.delete_prefix('/').delete_suffix('/')

        if branch.nil? || branch.empty?
            ref = nil
        else
            ref ="heads/#{branch}"
        end

        # Confirm binder, content folders exist
        begin
            binder_folder = github_client.contents(target_user_repo,
                                                  :path => 'binder',
                                                  :ref => ref)
            content_folder = github_client.contents(target_user_repo,
                                                   :path => 'content',
                                                   :ref => ref)
        rescue Octokit::NotFound
            message = {:response => false,
                   :reason => "Missing 'binder' or 'content' folder for #{url}"}
            return JSON.parse(message.to_json)
        end

        # Initialize default reponse
        message = {:response => true,
               :reason => "Repository meets mimimum file/folder level requirements."}

        binder_files = [];
        # Check for BinderHub config files
        binder_folder.each do |file|
            binder_files.append(file.name)
        end

        binder_configs = [
            "environment.yml",
            "data_requirement.json",
            "requirements.txt",
            "Pipfile",
            "Pipfile.lock",
            "setup.py",
            "Project.toml",
            "REQUIRE",
            "install.R",
            "apt.txt",
            "DESCRIPTION",
            "manifest.yml",
            "postBuild",
            "start",
            "runtime.txt",
            "default.nix",
            "Dockerfile",
            "start"
            ];

        if  (binder_configs & binder_files).length() == 0
            message = {:response => false,
                   :reason => "Binder folder does not contain a valid environment configuration file."}
        end

        content_files = [];
        # Check for _toc.yml and _config.yml
        content_folder.each do |file|
            content_files.append(file.name)
        end

        content_required = ['_toc.yml','_config.yml'];

        if (content_required & content_files).length() < 2
            message =  {:response => false,
                    :reason => "Missing _toc.yml or _config.yml under the content folder."}
        end

        return JSON.parse(message.to_json)
    end



    #     puts "Sending results email"
    #     # This results_book could be empty even upon
    #     # response 200 (parse_neurolibre_response)
    #     book_url = results_book['book_url']

    #     # TODO: This is commented out for now till 
    #     # parse_neurolibre_response is better governed.
        
    #     # response = RestClient::Request.new(
    #     #     method: :get,
    #     #     :url => book_url,
    #     #     verify_ssl: $TEST_SSL,
    #     #     :headers => { :content_type => :json }
    #     # ).execute do |response|
    #     # case response.code
    #     # when 404
    #     #     puts "Looks like the book build has failed. Setting book_url to nil."
    #     #     book_url = nil
    #     # when 200
    #     #     puts "Book url successful."
    #     # end
    #     # end
    #     success = false 
    #     if book_url
    #         success = true 
    #         book_html = """
    #                     <div style=\"background-color:gainsboro;border-radius:15px;padding:10px\">
    #                     <p>🌱</p>
    #                     <h2><strong>Your <a href=\"#{book_url}\">NeuroLibre Book</a> is ready!</strong></h2>
    #                     <center><img style=\"height:250px;\" src=\"https://github.com/neurolibre/brand/blob/main/png/built.png?raw=true\"></center>
    #                     </div>
    #                     <p>You can review the attached log files to investigate the build.</p>
    #                     """
    #     else
    #         book_html = """
    #                     <div style=\"background-color:#f0eded;border-radius:15px;padding:10px\">
    #                     <p><strong>Looks like your book build was not successful.</strong></p>
    #                     <center><img style=\"height:250px;\" src=\"https://github.com/neurolibre/brand/blob/main/png/sad_robo.png?raw=true\"></center>
    #                     <h3>Please download the attached log file and open it in your web browser to troubleshoot the issue.</h3>
    #                     </div>
    #                     """
    #     end

    #     html_logs = get_book_build_log(results_binder,repository_address,commit_sha,success)

    #     File.open("logs_#{commit_sha[0,7]}.html", "w+") do |f|
    #     # Remove ANSI colors
    #         f.puts("<!DOCTYPE html>")
    #         f.puts("<html lang=\"en\" class=\"no-js\">")
    #         f.puts("<style>body {  background-color: #fbdeda;  color: black;  font-family: monospace;}pre {  background-color: #222222;  border: none;  color: white;  padding: 10px;  margin: 10px;  overflow: auto;}code {  font-family: monospace;  font-size: 12px;  background-color: #222222;  color: white;  border-radius: 5px;  padding: 2px;}  </style>")
    #         f.puts("<body>")
    #         html_logs.each_line { |element| f.puts(element)}
    #         f.puts("</body></html>")
    #     end

    #     options_mail = {
    #     :address => "smtp.sendgrid.net",
    #     :port                 => 587,
    #     :user_name            => 'apikey',
    #     :domain               => 'neurolibre.org',
    #     :password             => ENV['SENDGRID_API_TOKEN'],
    #     :authentication       => 'plain',
    #     :enable_starttls_auto => true  }

    #   Mail.defaults do
    #     delivery_method :smtp, options_mail
    #   end

    #   @mail = Mail.new do
    #     to       user_mail
    #     from    'RoboNeuro <noreply@neurolibre.org>'
    #     subject "NeuroLibre - Build results for #{repository_address}"

    #     text_part do
    #       body "We have finished processing your request for #{repository_address} commit #{commit_sha}. Results #{results_binder}"
    #     end

    #     html_part do
    #       content_type 'text/html; charset=UTF-8'
    #       body  """
    #             <body>
    #             #{NeuroLibre.header_finish}
    #             <center>
    #             <h3><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{repository_address}</code></h3>
    #             <p>Your test request <code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{sha}</code> has been completed.</p>
    #             #{book_html}
    #             <h3><b>Git reference for this build was <a href=\"https://github.com/#{repository_address}/commit/#{commit_sha}\"><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{commit_sha[0...6]}</code></a></b></h3>
    #             <p>For further information, please visit our <a href=\"https://docs.neurolibre.com/en/latest/\">documentation</a>.</p>
    #             <p>Thank you for using our playground service,</p>
    #             <p>RoboNeuro</p>
    #             </center>
    #             </body>
    #             #{NeuroLibre.footer}
    #             """
    #      end

    #     # add_file "./binder_build_#{commit_sha}.log"
    #     # add_file "./book_build_#{commit_sha}.log"
    #     add_file "./logs_#{commit_sha[0,7]}.html"

    #   end

    #   @round_tripped_mail = Mail.new(@mail.encoded)
    #   @round_tripped_mail.deliver

    #   return book_url
    # end





end
