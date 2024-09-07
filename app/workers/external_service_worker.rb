require 'base64'
require_relative '../lib/logging'

class ExternalServiceWorker < BuffyWorker
   # include Logging

  def perform(service, locals)
    load_context_and_env(locals)
    
    http_method = service['method'] || 'post'
    url = service['url']
    headers = service['headers'] || {}
    actions_on_success = service['on_success'] || {}
    template = nil

    return true if url.to_s.strip.empty?

    query_parameters = service['query_params'] || {}
    service_mapping = service['mapping'] || {}
    inputs_from_issue = service['data_from_issue'] || {}
    mapped_parameters = {}

    if service['send_only_mapped']
      service_mapping.each_pair do |k, v|
        mapped_parameters[k] = locals.delete(v) if locals.key?(v)
      end
    else
      inputs_from_issue.each do |input_from_issue|
        mapped_parameters[input_from_issue] = locals[input_from_issue].to_s
      end

      service_mapping.each_pair do |k, v|
        mapped_parameters[k] = locals.delete(v)
      end

    end

    parameters = query_parameters.merge(mapped_parameters)

    # @NeuroLibre add conditional auth
    if headers['username'] && headers['password']
      headers = {'Authorization' => "Basic " + Base64.strict_encode64("#{headers['username']}:#{headers['password']}")}.merge(headers)
      headers.delete('username')
      headers.delete('password')
    end

    if http_method.downcase == 'get'
      response = Faraday.get(url, parameters, headers)
    else
      
      post_headers = {'Content-Type' => 'application/json', 'Accept' => 'application/json'}.merge(headers)
      # @Neurolibre, this is a required temporary solution for 
      # python compatibility.
      if headers['Authorization']
        parameters.delete('target-repository')
      end
      Logger.new(STDOUT).warn(parameters.to_json)
      response = Faraday.post(url, parameters.to_json, post_headers)
    end

    if response.status.between?(200, 299)
      respond(service['success_msg']) if service['success_msg']

      if service['template_file']
        parsed_response = parse_json_response(response.body)
        respond_external_template(service['template_file'], parsed_response)
      end

      unless service['success_msg'] || service['template_file'] || service['silent'] == true
        respond(response.body)
      end

      if service['add_labels'] && service['add_labels'].is_a?(Array)
        labels_to_add = service['add_labels'].uniq.compact
        label_issue(labels_to_add) unless labels_to_add.empty?
      end
      if service['remove_labels'] && service['remove_labels'].is_a?(Array)
        labels_to_remove = service['remove_labels'].uniq.compact
        labels_to_remove.each{|label| unlabel_issue(label)} unless labels_to_remove.empty?
      end

      close_issue if service['close'] == true
    elsif response.status.between?(400, 599)
      if service['error_msg']
        respond(service['error_msg'])
      else
        error_msg = "Error (#{response.status}). The #{service['name'].to_s} service is currently unavailable"
        respond(error_msg) unless service['silent'] == true
      end
    end

  end

  def parse_json_response(body)
    parsed = JSON.parse(body)
    if parsed.is_a? Array
      parsed = begin
        JSON.parse(parsed[0])
      rescue JSON::ParserError => err
        { response: parsed[0] }
      end
    end
    parsed
  end
end
