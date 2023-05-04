require 'uri'
require 'json'
require 'time'
require 'yaml'
require 'faraday'
require 'logger'
require 'openai'
require_relative 'github'


include GitHub


# Move these to ENV later.
$TEST_DOMAIN="https://preview.neurolibre.org"
$TEST_SSL = true

$PROD_DOMAIN="https://neurolibre-data-prod.conp.cloud"
$PROD_SSL = true

module NeurolibreUtilities

    def openai_client
        OpenAI.configure do |config|
            config.access_token = ENV['OAI_ACCESS_TOKEN']
            config.organization_id = ENV['OAI_ORG_ID']
            config.request_timeout = 120
        end
        @openai_client = OpenAI::Client.new
    end

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

    def get_funny_quote(repo_url)
        branch = get_default_branch(repo_url)
        target_repo = get_repo_owner_and_name(repo_url)
        response = openai_client.chat(
            parameters: {
                model: "gpt-3.5-turbo", # Required.
                messages: [{ role: "user", content: "Write an amusing and moderately flattering one liner quote based on the content of https://raw.githubusercontent.com/#{target_repo.split("/")[0]}/#{target_repo.split("/")[1]}/#{branch}/paper.md"}], # Required.
                temperature: 0.7,
            })
        return response.dig("choices", 0, "message", "content")
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
    # def is_email_valid? email
    #     email =~URI::MailTo::EMAIL_REGEXP
    # end

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

    def get_latest_upstream_sha(forked_repo)
        # This does not take custom_branch as it is intended to find the
        # latest commit pushed by the user from its roboneurolibre fork. 
        target_repo = get_repo_owner_and_name(forked_repo)
        sha = github_client.commits(target_repo).map {|c,a| [c.commit.author.name,c.sha]}.select{ |e, i| e != 'roboneuro' }.first[1]
        return sha
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
        # [Book]->[POST /api/book/build]
        # Preview server exclusive.
        # See the swagger API docs at https://preview.neurolibre.org/documentation#/Book/post_api_book_build
        # This function sends the request to the API endpoint documented in the above line.
        # All the details regarding API calls are available in the Swagger documentation.
        
        streamed = []
        response = {}

        # Receiving response in stream to avoid cloudflare timeout (100s).
        # BinderHub build sends keepalive every 30 seconds to avoid such 
        # proxy timeouts as well.
        neurolibre_test_client.headers["Accept"] = "text/event-stream"
        neurolibre_test_client.options[:timeout] = 3600
    
        neurolibre_test_client.post('/api/forward', payload_in) do |req|
            req.options.on_data = Proc.new do |chunk, overall_received_bytes, env|
                streamed << chunk
            end
        end
        
        # Depending wheter a book is found or not, binderhub messages
        # are appended by a book build status flag on the full-stack-server end.
        success_flag = "<-- Book Success -->\n"
        fail_flag = "<-- Book Failed -->\n"
        pos_success = streamed.find_index { |line| line.start_with?(success_flag)}
        pos_fail = streamed.find_index { |line| line.start_with?(fail_flag)}

        # If neither flag can't be found, it is likely that
        # jupyter book dependency is missing.
        if pos_fail.nil? && pos_success.nil?
            # Payload is JSON, convert to hash first
            payload_hash = JSON.parse(payload_in)
            # Format url into owner/repository format
            target_repo = get_repo_owner_and_name(payload_hash['repo_url'])
            # Look for book execution attempt log
            cur_response = neurolibre_test_client.get("/book-artifacts/#{target_repo.split("/")[0]}/github.com/#{target_repo.split("/")[1]}/#{payload_hash['commit_hash']}/book-build.log")
            response['status'] = 424 # Stands for missing dependency
            response['binder_message'] = streamed.join # This is array, have to join
            if cur_response.status == 200
                response['book_message'] = cur_response.body # This is string, no need to join
            else
                # If book-build.log is absent, means that user pod failed 
                # means that binderhub build failed.
                response['book_message'] = "Because the Binder build failed, the book build was not triggered."
            end
            # Cannot proceed.
            return response
        end

        # If book can be found, it means that both binder and book build were ok
        # I book can't be found, binder may have succeeded, or both failed. 
        pos_success ? status = 200 : status = 404
        pos_success ? pos = pos_success : pos = pos_fail
        pos_success ? flag = success_flag : flag = fail_flag

        #Logger.new(STDOUT).warn("#{pos}")
        Logger.new(STDOUT).warn("#{flag}")
        #Logger.new(STDOUT).warn("#{streamed}")
    
        binder_message = streamed[0...pos].join
        book_message = /#{flag}(.+)/.match(streamed[pos..-1].join)[1]

        # Add status code 
        response['status'] = status
        # Add book message
        response['book_message'] = JSON.parse(book_message)
        # Add binder logs
        response['binder_message'] = binder_message

        return response
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
            txt = response.body
            rgx = /href=['"]\K[^'"]+.log/
            logs = txt.scan(rgx)
            logs.each do |log_file|
                log = neurolibre_test_client.get("/book-artifacts/#{uname}/github.com/#{repo}/#{hash}/_build/html/reports/#{log_file}")
                cur_log= "<details><summary> <b>Execution error log</b> for <code>#{log_file.gsub('.log','')}</code> notebook (#{log_file.gsub('.log','')}.ipynb) or MyST (#{log_file.gsub('.log','')}.md)).</summary><pre><code>#{log.body}</code></pre></details>"
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

    # def email_received_request(user_mail,repository_address,sha,commit_sha,jid)
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

    #   mail = Mail.deliver do
    #     to       user_mail
    #     from    'RoboNeuro <noreply@neurolibre.org>'
    #     subject "NeuroLibre - Build request for #{repository_address}"

    #     text_part do
    #       body "We have received your request for #{repository_address} commit #{commit_sha}."
    #     end

    #     html_part do
    #       content_type 'text/html; charset=UTF-8'
    #       body  """
    #             <body>
    #             #{NeuroLibre.header_start}
    #             <center>
    #             <h3><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{repository_address}</code></h3>
    #             <p>We have received your request to build a NeuroLibre preprint.</p>
    #             <h3><b>Your submission key is <code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{sha}</code></b></h3>
    #             <div style=\"background-color:#f0eded;border-radius:15px;padding:10px\">
    #             <p>We would like to remind you that the build process may take some time. We will notify you of the results as soon as it is completed.</p>
    #             <p>You can access the progress page by clicking this button.</p>
    #             <a href=\"https://playground.neurolibre.org/preview?id=#{jid}\">
    #             <button type=\"button\" style=\"background-color:red;color:white;border-radius:6px;box-shadow:5px 5px 5px grey;padding:10px 24px;font-size: 14px;border: 2px solid #FFFFFF;\">RoboNeuro Build</button>
    #             </a>
    #             </div>
    #             <h3><b>Building book at Git sha <a href=\"https://github.com/#{repository_address}/commit/#{commit_sha}\"><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{commit_sha[0...6]}</code></a></b></h3>
    #             <p>For further information, please visit our <a href=\"https://docs.neurolibre.org/en/latest/\">documentation</a>.</p>
    #             <p>Robotically yours,</p>
    #             <p>RoboNeuro</p>
    #             </center>
    #             </body>
    #             #{NeuroLibre.footer}
    #             """
    #     end
    #   end
    # end

    # def email_processed_request(user_mail,repository_address,sha,commit_sha,results_binder,results_book)


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

    def get_default_branch(repository_address)
        target_repo = get_repo_owner_and_name(repository_address)
        response = Faraday.get("https://api.github.com/repos/#{target_repo}")
        repo_info = JSON.parse(response.body)
        return repo_info['default_branch']
    end

    # def update_github_content(repository_address,content_path,new_content,commit_message,branch="main")
    #     # To configure the forked repository for production.
    #         # A repo for which roboneuro has write access (neurolibre or roboneurolibre orgs.)
    #         target_repo = get_repo_owner_and_name(repository_address)
            
    #         # Get blob sha of the target file 
    #         blob = JSON.parse(RestClient.get("https://api.github.com/repos/#{target_repo}/contents/#{content_path}"))
            
    #         # Update the content
    #         r = github_client.update_contents(target_repo,
    #                                   content_path,
    #                                   commit_message,
    #                                   blob['sha'],
    #                                   new_content,
    #                                   :branch => branch)
    #         # Let caller infer in case this fails 
    #         if r.nil?
    #             return nil
    #         else
    #             return true
    #         end
    # end

    # def fork_for_production(papers_repo)
    #     target_repo = get_repo_owner_and_name(papers_repo)
    #     r = github_client.fork(target_repo, {:organization => 'roboneurolibre'})
    #     puts(r['html_url'])
    #     return r['html_url']
    # end

    # def update_config_for_prod(forked_address)
    #     # Argument to this function is a GitHub URL for a roboneurolibre repository
    #     # forked from user's account, e.g., https://github.com/roboneurolibre/my_preprint
    #     # Sets launch_buttons/binderhub_url and repository/url for neurolibre production.
    #     # Returns true/false, conditional to a successful update of the _config.yml on forked repo.
    #     target_repo = get_repo_owner_and_name(forked_address)
    #     branch = get_default_branch(forked_address)

    #     begin
    #         jb_config = RestClient.get("https://raw.githubusercontent.com/#{target_repo}/#{branch}/content/_config.yml")
    #     rescue
    #         warn "Cannot get content/_config.yml from #{forked_address}"
    #         return false
    #     end

    #     # Parse yaml
    #     jb_config = YAML.load(jb_config)

    #     # Production binderhub server
    #     if not jb_config['launch_buttons']
    #         jb_config['launch_buttons'] = {}
    #     end
    #     jb_config['launch_buttons']['binderhub_url'] = "https://binder-mcgill.conp.cloud"

    #     # Update repository address
    #     if not jb_config['repository']
    #         jb_config['repository'] = {}
    #     end
    #     jb_config['repository']['url'] = "#{forked_address}"

    #     if update_github_content(forked_address,"content/_config.yml",jb_config.to_yaml,"Updating _config.yml for production",branch).nil?
    #         warn "Cannot update _config.yml for #{forked_address}"
    #         return false
    #     else 
    #         return true
    #     end
    # end

    # def update_toc_for_prod(forked_address, issue_id)
    #     # First argument to this function is a GitHub URL for a roboneurolibre repository
    #     # forked from user's account, e.g., https://github.com/roboneurolibre/my_preprint
    #     # The second argument is to add a hyperlink to the NeuroLibre page from the preprint.
    #     # Returns true/false, conditional to a successful update of the _config.yml on forked repo.
    #     target_repo = get_repo_owner_and_name(forked_address)
    #     branch = get_default_branch(forked_address)

    #     begin
    #         jb_toc = RestClient.get("https://raw.githubusercontent.com/#{target_repo}/#{branch}/content/_toc.yml")
    #     rescue
    #         warn "Cannot get content/_toc.yml from #{forked_address}"
    #         return false
    #     end

    #     jb_toc = YAML.load(jb_toc)
        
    #     if jb_toc['parts']
    #         jb_toc['parts'].append({"caption"=>"NeuroLibre", "chapters"=>[{"url"=>"https://neurolibre.org/papers/10.55458/neurolibre.#{"%05d"%issue_id}", "title"=>"Citable PDF and archives"}]})
    #     end

    #     if jb_toc['chapters']
    #         jb_toc['chapters'].append({"url"=>"https://neurolibre.org/papers/10.55458/neurolibre.#{"%05d"%issue_id}", "title"=>"Citable PDF and archives"})
    #     end
        
    #     if jb_toc['format'] == 'jb-article' && jb_toc['sections']
    #         jb_toc['sections'].append({"url"=>"https://neurolibre.org/papers/10.55458/neurolibre.#{"%05d"%issue_id}", "title"=>"Citable PDF and archives"})
    #     end
        
    #     if update_github_content(forked_address,"content/_toc.yml",jb_toc.to_yaml,"Updating _toc.yml for production",branch).nil?
    #         warn "Cannot update _toc.yml for #{forked_address}"
    #         return false
    #     else 
    #         return true
    #     end
    
    # end

    # def update_forked_content_fail_msg(forked_address,content,job_id)
    #     target_repo = get_repo_owner_and_name(forked_address)
    #     branch = get_default_branch(forked_address)
    #     "😥 I could not update `_toc.yml` at the [forked repository](#{forked_address}), interrupting the production workflow.
    #     <details><summary> Potential issues </summary><ul>
    #     <li>I waited for 20 seconds after the repo was forked to update `#{content}`. But sometimes GitHub slows down, wait for a minute and try again!</li>
    #     <li>`#{content}` may not be a properly formatted `yaml` file. You can copy/paste [its content](https://raw.githubusercontent.com/#{target_repo}/#{branch}/content/#{content}) to validate [online](https://jsonformatter.org/yaml-validator).</li>
    #     <li>That's all I can think of. If you've tried all of the above and still running into a problem, the technical reviewer should check `roboneuro` logs at job ID `#{job_id}`</li>
    #     </ul></details>"
    # end

    # def request_book_sync(payload_in)
    #     # [Book]->[POST /api/book/sync]
    #     # Preprint server exclusive
    #     # See the swagger API docs at https://neurolibre-data-prod.conp.cloud/documentation#/Book/post_api_book_sync
    #     # This function sends the request to the API endpoint documented in the above line.
    #     # All the details regarding API calls are available in the Swagger documentation.

    #     # Based on the commit hash, this 
    #     # function copies the built book from test to the production server.
    #     begin 
    #     response = RestClient::Request.new(
    #         method: :post,
    #         :url => "#{$PROD_DOMAIN}/api/book/sync",
    #         verify_ssl: $PROD_SSL,
    #         :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #         :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #         :payload => payload_in,
    #         :timeout => 1200, # Give 20 minutes
    #         :headers => { :content_type => :json }
    #         ).execute
    #     rescue
    #         # Somtething unexpected happened.
    #         response = nil
        
    #     end

    #     if response.nil?
    #         res = "Run into a problem during book sync."
    #     else
    #         res = " :maple_leaf: Your book is now on the NeuroLibre production server!
    #         You may take a look at the the book (link below). 
    #         <details><summary> <b> Book prod sync response</b> </summary><pre><code>#{response}</code></pre></details>
    #         <p>:warning: Please do not execute this book, unless a (production) BinderHub image has been requested and completed by this technical screening.</p>"
    #     end

    #     return res
    # end

    # def request_data_sync(payload_in)
    #     # [Data]->[POST /api/data/sync]
    #     # Preprint server exclusive
    #     # See the swagger API docs at https://neurolibre-data-prod.conp.cloud/documentation#/Data/post_api_data_sync
    #     # This function sends the request to the API endpoint documented in the above line.
    #     # All the details regarding API calls are available in the Swagger documentation.

    #     # Based on the project_name provided in the repo2data, this 
    #     # function copies data from test to the production server.
    #     begin
    #         response = RestClient::Request.new(
    #             method: :post,
    #             :url => "#{$PROD_DOMAIN}/api/data/sync",
    #             verify_ssl: $PROD_SSL,
    #             :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #             :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #             :payload => payload_in,
    #             :timeout => 1200, # Give 20 minutes
    #             :headers => { :content_type => :json }
    #             ).execute
    #     rescue
    #         response = nil
    #     end

    #     if response.nil?
    #         res = "Run into a problem during book sync."
    #     else
    #         res = " :maple_leaf: I have successfully moved your data to the production server!
    #         <details><summary> <b> Data prod sync response</b> </summary><pre><code>#{response}</code></pre></details>"
    #     end

    #     return res
    # end

    # def request_production_binderhub(payload_in)
    #     # [Binder]->[POST /api/binder/build]
    #     # Preprint server exclusive
    #     # See the swagger API docs at https://neurolibre-data-prod.conp.cloud/documentation
    #     # This function sends the request to the API endpoint documented in the above line.
    #     # All the details regarding API calls are available in the Swagger documentation.

    #     # Sends a binderhub build request to the production server for 
    #     # a repository forked into the roboneurolibre GitHub organization. 
    #     # Requests from other user/ organization/ repositories are not allowed.
    #     begin
    #     response = RestClient::Request.new(
    #         method: :post,
    #         :url => "#{$PROD_DOMAIN}/api/binder/build",
    #         verify_ssl: $PROD_SSL,
    #         :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #         :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #         :payload => payload_in,
    #         :timeout => 1800, # Give 30 minutes
    #         :headers => { :content_type => :json }
    #         ).execute
    #     rescue
    #         response = nil
    #     end

    #     if response.nil?
    #             res = "Run into problem during production BinderHub build request for #{payload_in["repo_url"]}"
    #     else
    #             res = ":hibiscus: Your Binder is ready!
    #             <details><summary> <b> BinderHub prod build response</b> </summary><pre><code>#{response}</code></pre></details>"
    #     end

    #     return res
    # end

    # def zenodo_create_buckets(payload_in)
    #     # [Zenodo]->[POST /api/zenodo/buckets]
    #     # Preprint server exclusive
    #     # See the swagger API docs at https://neurolibre-data-prod.conp.cloud/documentation#/Zenodo/post_api_zenodo_buckets
    #     # This function sends the request to the API endpoint documented in the above line.
    #     # All the details regarding API calls are available in the Swagger documentation.

    #     # This action can ben run only once, regardless of the commit. Only one deposit per issue. 
    #     # Checks are performed on the server side.
    #     response = RestClient::Request.new(
    #     method: :post,
    #     :url => "#{$PROD_DOMAIN}/api/zenodo/buckets",
    #     verify_ssl: $PROD_SSL,
    #     :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #     :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #     :payload => payload_in,
    #     :headers => { :content_type => :json }
    #     ).execute

    #     return response
    # end

    # def get_resource_lookup(repository_address)
    #     # Preview server exclusive.
    #     # Uses bare GET to locate files.
    #     # This is allowed under the `book-artifacts` directory and for its subdirectories.

    #     # Each build on the test server is listed on this tabular file with 
    #     # the respective components.
        
    #     puts(" Requested lookup table for #{repository_address}")
    #     response = RestClient::Request.new(
    #         method: :get,
    #         :url => "#{$TEST_DOMAIN}/book-artifacts/lookup_table.tsv",
    #         verify_ssl: $TEST_SSL,
    #         :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #         :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #         :headers => { :content_type => :json }
    #     ).execute
        
    #     # The second entry in the tsv file is the repository address, if found, then proceed.
    #     found= response.split("\n").map {|c| [c]}.select{ |e| e[0].split(",")[1] == repository_address }.join(', ')

    #     if (found.nil? || found.empty?)
    #         puts('Cannot find a lookup table.')
    #         lut = nil
    #     else
    #         cur_date,cur_url,cur_docker, cur_tag, cur_data_url, cur_data_doi = found.split(",")
    #         lut = {'project_name' => cur_tag,
    #                'docker' => cur_docker,
    #                'data_url' => cur_data_url,
    #                'data_doi' => cur_data_doi}
    #     end

    #     return lut

    # end

    # def zenodo_get_status(issue_id)
    #     # [Zenodo]->[POST /api/zenodo/list]
    #     # Preprint server exclusive
    #     # See the swagger API docs at https://neurolibre-data-prod.conp.cloud/documentation#/Zenodo/post_api_zenodo_list
    #     # This function sends the request to the API endpoint documented in the above line.
    #     # All the details regarding API calls are available in the Swagger documentation.

    #     # Depending on  the availibility of the zenodo records on the
    #     # production server, a response is returned.
    #     # API endpoint zenodo/list returns a simple HTML formatted list of records found
    #     # in the /zenodo_records/issue_id directory. REGEX patterns are used for interpretation. 
    #     post_params = {:issue_id => issue_id}.to_json
    #     id = "%05d" % issue_id
    #     response = RestClient::Request.new(
    #         method: :post,
    #         :url => "#{$PROD_DOMAIN}/api/zenodo/list",
    #         verify_ssl: $PROD_SSL,
    #         :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #         :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #         :payload => post_params,
    #         :headers => { :content_type => :json }
    #         ).execute
        
    #     res = response.to_str

    #     regex_repository_upload = /(<li>zenodo_uploaded_repository)(.*?)(?=.json)/
    #     regex_data_upload = /(<li>zenodo_uploaded_data)(.*?)(?=.json)/
    #     regex_book_upload = /(<li>zenodo_uploaded_book)(.*?)(?=.json)/
    #     regex_docker_upload = /(<li>zenodo_uploaded_docker)(.*?)(?=.json)/
    #     regex_deposit = /(<li>zenodo_deposit)(.*?)(?=.json)/
    #     regex_publish = /(<li>zenodo_published)(.*?)(?=.json)/
    #     hash_regex = /_(?!.*_)(.*)/
        
    #     zenodo_regexs = [regex_repository_upload,regex_data_upload,regex_book_upload,regex_docker_upload]
    #     types = ['Repository', 'Data', 'Book','Docker']
                
    #     rsp = []
        
    #     if res[regex_deposit].nil? || res[regex_deposit].empty?
    #         rsp.push("<h3>Deposit</h3>:red_square: <b>Zenodo deposit records have not been created yet.</b>")
    #     else
    #         rsp.push("<h3>Deposit</h3>:green_square: Zenodo deposit records are found.")
    #     end
        
    #     rsp.push("<h3>Upload</h3><ul>")
    #     zenodo_regexs.each_with_index do |cur_regex,idx|
    #     if res[cur_regex].nil? || res[cur_regex].empty?
    #         rsp.push("<li>:red_circle: <b>#{types[idx]} archive is missing</b></li>")
    #     else
    #         tmp = res[cur_regex][hash_regex][1..-1]
    #         # Display file size for uploaded items, so it is informative.
    #         response = RestClient::Request.new(
    #             method: :get,
    #             :url => "#{$PROD_DOMAIN}/zenodo_records/#{id}/#{res[cur_regex]}.json".gsub("<li>",""),
    #             verify_ssl: $PROD_SSL,
    #             :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #             :password =>  ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #             :headers => { :content_type => :json }
    #         ).execute
    #         cur_record = JSON.parse(response.to_str)
    #         # Display MB or GB depending on the size.
    #         size = (cur_record['size'].to_i/1e6).round(2)
    #         if size > 999
    #           size = (cur_record['size'].to_i/1e9).round(2).to_s + " GB"
    #         else
    #           size = size.to_s + " MB"
    #         end
    #         # Format 
    #         rsp.push("<li>:green_circle: #{types[idx]} archive <ul><li><code>#{size}</code> <code>#{tmp}</code></li></ul></li>")
    #     end
    #     end
    #     rsp.push("</ul><h3>Publish</h3>")
        
    #     if res[regex_publish].nil? || res[regex_publish].empty?
    #         rsp.push(":small_red_triangle_down: <b>Zenodo DOIs have not been published yet.</b>")
    #     else
    #         rsp.push(":white_check_mark: Zenodo DOIs are published.")
    #     end
            
    #     return rsp.join('')

    # end

    # def zenodo_archive_items(payload_in,items,item_args)
    #     # [Zenodo]->[POST /api/zenodo/upload]
    #     # Preprint server exclusive
    #     # See the swagger API docs at https://neurolibre-data-prod.conp.cloud/documentation#/Zenodo/post_api_zenodo_upload
    #     # This function sends the request to the API endpoint documented in the above line.
    #     # All the details regarding API calls are available in the Swagger documentation.

    #     # Requests will be sent to NeuroLibre server one by one
    #     # Otherwise, it may time-out, also not modular. 
    #     response = []
    #     items.each_with_index do |it, idx|
            
    #         payload_in["item"] = it
    #         payload_in["item_arg"] = item_args[idx]
    #         payload_call = payload_in.to_json
    #         r = RestClient::Request.new(
    #             method: :post,
    #             :url => "#{$PROD_DOMAIN}/api/zenodo/upload",
    #             verify_ssl: $PROD_SSL,
    #             :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #             :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #             :payload => payload_call,
    #             :timeout => 1800, # Give 30 minutes
    #             :headers => { :content_type => :json }
    #             ).execute

    #         response.push(r.to_str)
    #     end

    #     return response

    # end

    # def zenodo_publish(issue_id)
    #     # [Zenodo]->[POST /api/zenodo/publish]
    #     # Preprint server exclusive
    #     # See the swagger API docs at https://neurolibre-data-prod.conp.cloud/documentation#/Zenodo/post_api_zenodo_publish
    #     # This function sends the request to the API endpoint documented in the above line.
    #     # All the details regarding API calls are available in the Swagger documentation.
        
    #     payload_in = {}
    #     payload_in["issue_id"] = issue_id
    #     payload_call = payload_in.to_json
        
    #     r = RestClient::Request.new(
    #             method: :post,
    #             :url => "#{$PROD_DOMAIN}/api/publish",
    #             verify_ssl: $PROD_SSL,
    #             :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #             :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #             :payload => payload_call,
    #             :timeout => 1800, # Give 30 minutes
    #             :headers => { :content_type => :json }
    #     ).execute

    #     return(r.to_str)
    # end

    # def zenodo_get_published(issue_id,item)
    #     # Uses bare URL with GET to access static files.

    #     begin
    #         id = "%05d" % issue_id
    #         response = RestClient::Request.new(
    #                 method: :get,
    #                 :url => "#{$PROD_DOMAIN}/zenodo_records/#{id}/zenodo_published_#{item}_NeuroLibre_#{id}.json",
    #                 verify_ssl: $PROD_SSL,
    #                 :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #                 :password =>  ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #                 :headers => { :content_type => :json }
    #             ).execute
    #         cur_record = JSON.parse(response.to_str)
    #     rescue
    #         cur_record = nil
    #     end   

    #     return cur_record
    # end

    # def zenodo_flush_items(items,issue_id)
    #     # [Zenodo]->[POST /api/zenodo/flush]
    #     # Preprint server exclusive
    #     # See the swagger API docs at https://neurolibre-data-prod.conp.cloud/documentation#/Zenodo/post_api_zenodo_flush
    #     # This function sends the request to the API endpoint documented in the above line.
    #     # All the details regarding API calls are available in the Swagger documentation.

    #     # Deletes zenodo records from Zenodo (and locally on the server)
    #     # Deletes corresponding data from the prod server.

    #     payload_in = {}
    #     payload_in["items"] = items
    #     payload_in["issue_id"] = issue_id

    #     r = RestClient::Request.new(
    #             method: :post,
    #             :url => "#{$PROD_DOMAIN}/api/zenodo/flush",
    #             verify_ssl: $PROD_SSL,
    #             :user => ENV['NEUROLIBRE_TESTAPI_USER'],
    #             :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
    #             :payload => payload_in.to_json,
    #             :timeout => 1800, # Give 30 minutes
    #             :headers => { :content_type => :json }
    #             ).execute

    #     return r.to_str

    # end

    # def create_git_json(file_path, issue_id, papers_repo, journal_alias)
    #     id = "%05d" % issue_id
    #     crossref_xml_path = "#{journal_alias}.#{id}/10.55458.#{journal_alias}.#{id}.json"
    
    #     gh_response = github_client.create_contents(papers_repo,
    #                                                 crossref_xml_path,
    #                                                 "Creating 10.55458.#{journal_alias}.#{id}.json",
    #                                                 File.open("#{file_path.strip}").read,
    #                                                 :branch => "#{journal_alias}.#{id}")
    
    #     return gh_response.content.html_url
    # end


    # def assign_zenodo_archives(issue_id,zenodo_dois)
        
    #     nwo = "neurolibre/neurolibre-reviews"
    #     issue = github_client.issue(nwo, issue_id)

    #     doi_regex = /\b(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?!["&\'<>])\S)+)\b/
        
    #     types = {"repository" => "Repository","data" => "Data","book" => 'Book',"docker" => "Docker"}

    #     rsp = []
    #     new_body = ''
        
    #     zenodo_dois.keys.each_with_index do |key,idx|

    #       doi = zenodo_dois[key]
    #       if doi
    #         doi_with_url = "<a href=\"https://doi.org/#{doi}\" target=\"_blank\">#{doi}</a>"
    #         if idx == 0
    #           new_body = issue.body.gsub(/\*\*#{types[key]} archive:\*\*\s*(.*|Pending)/i, "**#{types[key]} archive:** #{doi_with_url}")
    #         else
    #           new_body = new_body.gsub(/\*\*#{types[key]} archive:\*\*\s*(.*|Pending)/i, "**#{types[key]} archive:** #{doi_with_url}")
    #         end
    #         rsp.push("OK. #{doi_with_url} is the archive or #{types[key]}.<br>")
    #       else
    #         rsp.push("* #{cur_doi} doesn't look like an archive DOI for #{types[key]}.<br>")
    #       end
    #     end
    
    #     github_client.update_issue(nwo, issue_id, issue.title, new_body)
        
    #     return rsp.join('')
    
    # end

end