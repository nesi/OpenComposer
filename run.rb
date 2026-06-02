require "sinatra"
require "date"
require "set"
require "sinatra/reloader" if ENV.fetch("RACK_ENV", "production") == "development"
require "yaml"
require "erb"
require "sqlite3"
require "json"
require "pstore"
require "time"
require "fileutils"
require "./lib/index"
require "./lib/form"
require "./lib/history"
require "./lib/scheduler"

set :environment, ENV.fetch("RACK_ENV", "production").to_sym
set :host_authorization, { permitted_hosts: [] } if ENV.fetch("RACK_ENV", "production") == "development"
set :erb, trim: "-"

configure :development do
  register Sinatra::Reloader
  also_reload "./lib/**/*.rb"
end

# Internal Constants
VERSION                ||= "2.1.0"
SCHEDULERS_DIR_PATH    ||= "./lib/schedulers"
HISTORY_ROWS           ||= 10
JOB_STATUS             ||= { "queued" => "QUEUED", "running" => "RUNNING", "completed" => "COMPLETED", "failed" => "FAILED", "cancelled" => "CANCELLED", "unknown" => "UNKNOWN" }
JOB_ID                 ||= "id"
JOB_APP_NAME           ||= "appName"
JOB_DIR_NAME           ||= "appPath"
JOB_STATUS_ID          ||= "status"
HEADER_SCRIPT_LOCATION ||= "_script_location"
HEADER_SCRIPT_NAME     ||= "_script_1"
HEADER_JOB_NAME        ||= "_script_2"
HEADER_CLUSTER_NAME    ||= "_cluster_name"
OC_SCRIPT_CONTENT      ||= "_script_content"
SCRIPT_CONTENT         ||= OC_SCRIPT_CONTENT  # Compatibility with previous versions
FORM_LAYOUT            ||= "_form_layout"
SUBMIT_BUTTON          ||= "_submitButton"
SUBMIT_CONFIRM         ||= "_submitConfirm"
SUBMIT_CONTENT         ||= "_submit_content"
WARNING_MODAL          ||= "_warning_modal"
WARNING_MODAL_CANCEL   ||= "_warning_cancel"
WARNING_MODAL_DISCARD  ||= "_warning_discard"
WARNING_MESSAGE        ||= "_warning_message"
SUBMIT_FORM            ||= "_submit_form"
JOB_NAME               ||= "Job Name"
JOB_PARTITION          ||= "Partition"
JOB_SUBMISSION_TIME    ||= "Submission Time"
JOB_KEYS               ||= "job_keys"
SKIP_KEYS ||= ['splat', OC_SCRIPT_CONTENT]
DEFINED_KEYS ||= {
  JOB_APP_NAME           => 'OC_APP_NAME',
  JOB_DIR_NAME           => 'OC_DIR_NAME',
  HEADER_SCRIPT_LOCATION => 'OC_SCRIPT_LOCATION',
  HEADER_SCRIPT_NAME     => 'OC_SCRIPT_NAME',
  HEADER_JOB_NAME        => 'OC_JOB_NAME',
  HEADER_CLUSTER_NAME    => 'OC_CLUSTER_NAME'
}.freeze
HISTORY_KEY_MAP ||= {
  "OC_HISTORY_JOB_NAME"        => JOB_NAME,
  "OC_HISTORY_PARTITION"       => JOB_PARTITION,
  "OC_HISTORY_SUBMISSION_TIME" => JOB_SUBMISSION_TIME,
  "OC_HISTORY_START_TIME"      => "Start",
  "OC_HISTORY_END_TIME"        => "End"
}.freeze
CLUSTERS_KEYS ||= ["scheduler", "login_node", "ssh_wrapper", "bin", "bin_overrides", "sge_root"].freeze

# Structure of manifest
Manifest ||= Struct.new(:dirname, :name, :category, :description, :icon, :related_apps)

# Create a YAML or ERB file object. Give priority to ERB.
# If the file does not exist, return nil.
def read_yaml(yml_path)
  erb_path = yml_path + ".erb"
  if File.exist?(erb_path)
    return YAML.load(ERB.new(File.read(erb_path), trim_mode: "-").result(binding))
  elsif File.exist?(yml_path)
    return YAML.load_file(yml_path)
  end

  return nil
end

# Create a configuration object.
# Defaults are applied for any missing values.
def create_conf
  begin
    conf = read_yaml("./conf.yml")
    halt 500, "./conf.yml.erb does not be found." if conf.nil?
  rescue Exception => e
    halt 500, "There is something wrong with ./conf.yml or ./conf.yml.erb."
  end

  # Check required values
  ## app_dir
  halt 500, "In ./conf.yml.erb, \"apps_dir:\" must be defined." unless conf.key?("apps_dir")

  ## Reject deprecated "cluster:" configuration in v1.8.0 and later
  halt 500, 'In ./conf.yml.erb, "cluster:" is deprecated.' if conf["cluster"]

  ## Check scheduler
  if !conf.key?("scheduler")
    if !conf.key?("clusters")
      halt 500, "The ./conf.yml.erb must have \"scheduler:\""
    else
      conf["clusters"].each do |name, settings|
        if settings.nil? || !settings.key?("scheduler")
          halt 500, "In ./conf.yml.erb, the cluster \"#{name}\" must have \"scheduler:\""
        end
      end
    end
  end

  # Set initial values if not defined
  conf["data_dir"]                ||= ENV["HOME"] + "/composer"
  conf["history"]                 ||= HISTORY_KEY_MAP.keys
  conf["history_store_script"]    = conf.fetch("history_store_script", true)
  conf["footer"]                  ||= "&nbsp;"
  conf["thumbnail_width"]         ||= "100"
  conf["navbar_color"]            ||= "#3D3B40"
  conf["navbar_text_color"]       ||= "#FFFFFF"
  conf["dropdown_color"]          ||= conf["navbar_color"]
  conf["footer_color"]            ||= conf["navbar_color"]
  conf["footer_text_color"]       ||= "#FFFFFF"
  conf["category_color"]          ||= "#5522BB"
  conf["category_text_color"]     ||= "#FFFFFF"
  conf["description_color"]       ||= conf["category_color"]
  conf["description_text_color"] ||= "#FFFFFF"
  conf["form_color"]              ||= "#BFCFE7"
  conf["non_script_color"]        ||= "#FFE28A"
  conf["non_script_button_color"] ||= "#FFBF00"
  conf["submit_color"]            ||= "#FFCCCC"
  conf["submit_button_color"]     ||= "#FFAAAA"
  conf["history_action_color"]    ||= "#DC3545"
  conf["highlight_theme"]         ||= "vs"
  conf["directive_color"]         ||= "#D73A49"
  conf["show_home_directory"] = conf.fetch("show_home_directory", true)
  conf["show_shell_access"]   = conf.fetch("show_shell_access",   true)
  conf["show_open_ondemand"]  = conf.fetch("show_open_ondemand",  true)

  # Set the values for "clusters:" and "history_db"
  if conf.key?("clusters")
    clusters  = conf["clusters"] || {}
    defaults  = CLUSTERS_KEYS.to_h { |k| [k, conf[k]] }
    CLUSTERS_KEYS.each { |k| conf[k] = {} }
    conf["history_db"] = {}

    clusters.each_key do |name|
      cluster_conf = clusters[name] || {}
      CLUSTERS_KEYS.each do |key|
        conf[key][name] = cluster_conf.fetch(key, defaults[key]) || defaults[key]
      end

      conf["history_db"][name] = File.join(conf["data_dir"], "#{name}.sqlite3")
    end
  else
    conf["history_db"] = File.join(conf["data_dir"], "#{conf["scheduler"]}.sqlite3")
  end

  # Create data directory
  FileUtils.mkdir_p(conf["data_dir"])

  return conf
end

# Create a manifest object in a specified application.
# If the name is not defined, the directory name is used.
def create_manifest(app_path)
  begin
    manifest = read_yaml(File.join(app_path, "manifest.yml"))
  rescue Exception => e
    return nil
  end

  ## Reject deprecated "related_app:" configuration in v1.8.0 and later
  halt 500, "In #{File.join(app_path, "manifest.yml")}, related_app: is deprecated." if manifest&.key?("related_app")

  dirname = File.basename(app_path)
  return Manifest.new(dirname, dirname, nil, nil, nil, nil) if manifest.nil?

  manifest["name"] ||= dirname
  return Manifest.new(dirname, manifest["name"], manifest["category"], manifest["description"], manifest["icon"], manifest["related_apps"])
end

# Create an array of manifest objects for all applications.
def create_all_manifests(apps_dir)
  halt 500, "apps_dir (#{apps_dir}) does not exist. Create the directory or update apps_dir in conf.yml.erb." unless Dir.exist?(apps_dir)

  all_manifests = Dir.children(apps_dir).each_with_object([]) do |dir, manifests|
    next if dir.start_with?(".") # Skip hidden files and directories

    app_path = File.join(apps_dir, dir)
    if ["form.yml", "form.yml.erb"].any? { |file| File.exist?(File.join(app_path, file)) }
      manifests << create_manifest(app_path)
    end
  end

  return all_manifests.compact
end

# Parse #SBATCH directives in a batch script into a cache hash suitable for
# replace_with_cache, driven by the app's own script template so no hardcoded
# field mappings are needed.
def parse_sbatch_into_cache(script_content, body, app_name, dir_name)
  return {} if script_content.nil? || !body.is_a?(Hash)

  script_template = body["script"].to_s
  return {} if script_template.strip.empty?

  form_fields = body["form"] || {}

  # Mirror substitute_oc_constants + normalize_interpolation from form.rb
  # without requiring a Sinatra helper context.
  t = script_template.dup
  t.gsub!(/#\{\s*(.*?)\s*\}/, '#{\1}')
  t.gsub!(/\#\{OC_APP_NAME\}/,        app_name.to_s)
  t.gsub!(/\#\{:OC_APP_NAME\}/,       app_name.to_s)
  t.gsub!(/\#\{OC_DIR_NAME\}/,        dir_name.to_s)
  t.gsub!(/\#\{:OC_DIR_NAME\}/,       dir_name.to_s)
  t.gsub!(/\#\{OC_JOB_NAME\}/,        "\#{#{HEADER_JOB_NAME}}")
  t.gsub!(/\#\{:OC_JOB_NAME\}/,       "\#{#{HEADER_JOB_NAME}}")
  t.gsub!(/\#\{OC_SCRIPT_LOCATION\}/, "\#{#{HEADER_SCRIPT_LOCATION}}")
  t.gsub!(/\#\{:OC_SCRIPT_LOCATION\}/,"\#{#{HEADER_SCRIPT_LOCATION}}")
  t.gsub!(/\#\{OC_SCRIPT_NAME\}/,     "\#{#{HEADER_SCRIPT_NAME}}")
  t.gsub!(/\#\{:OC_SCRIPT_NAME\}/,    "\#{#{HEADER_SCRIPT_NAME}}")
  t.gsub!(/\#\{OC_CLUSTER_NAME\}/,    "\#{#{HEADER_CLUSTER_NAME}}")
  t.gsub!(/\#\{:OC_CLUSTER_NAME\}/,   "\#{#{HEADER_CLUSTER_NAME}}")

  # Build one regex pattern per #SBATCH template line
  directive_patterns = []
  t.each_line do |tline|
    tline = tline.strip
    next unless tline.start_with?('#SBATCH')

    fields      = []
    pattern_str = Regexp.escape(tline)

    tline.scan(/#\{([^}]+)\}/).each do |interp|
      expr = interp[0]
      if (m = expr.match(/^zeropadding\((\w+),\s*\d+\)$/))
        fields      << m[1]
        pattern_str  = pattern_str.sub(Regexp.escape("\#{#{expr}}"), '(\d+)')
      else
        fields      << expr
        pattern_str  = pattern_str.sub(Regexp.escape("\#{#{expr}}"), '(.*?)')
      end
    end

    next if fields.empty?
    begin
      directive_patterns << { regex: Regexp.new("^#{pattern_str}$"), fields: fields }
    rescue RegexpError
    end
  end

  # Match each #SBATCH line in the script against the template patterns
  raw_cache = {}
  script_content.each_line do |sline|
    sline = sline.strip
    next unless sline.start_with?('#SBATCH')
    directive_patterns.each do |dp|
      next unless (m = dp[:regex].match(sline))
      dp[:fields].each_with_index do |field, idx|
        val = m[idx + 1]&.strip
        raw_cache[field] = val if val && !val.empty? && !raw_cache.key?(field)
      end
    end
  end

  # Expand checkbox fields: split captured comma-separated values into
  # the per-option cache keys that replace_with_cache expects.
  cache = {}
  raw_cache.each do |field, val|
    widget_def = form_fields[field]
    if widget_def.is_a?(Hash) && widget_def["widget"] == "checkbox"
      sep          = widget_def["separator"] || ","
      checked_vals = val.split(sep).map(&:strip)
      (widget_def["options"] || []).each_with_index do |opt, idx|
        opt_val = (opt.is_a?(Array) ? opt[1] : opt).to_s
        cache["#{field}_#{idx + 1}"] = opt_val if checked_vals.include?(opt_val)
      end
    else
      cache[field] = val
    end
  end

  cache
end

# Replace with cached value.
def replace_with_cache(form, cache)
  form.each do |key, value|
    value["value"] = case value["widget"]
                     when "number", "text", "email"
                       if value.key?("size")
                         value["size"].times.map do |i|
                           cache["#{key}_#{i+1}"] || Array(value["value"])[i]  # Array(nil)[i] is nil
                         end
                       else
                         cache[key] || value["value"]
                       end
                     when "select", "radio"
                       cache[key] || value["value"]
                     when "multi_select"
                       length = cache["#{key}_length"]&.to_i || 0
                       length.times.map { |i| cache["#{key}_#{i+1}"] }
                     when "checkbox"
                       value["options"].size.times.map { |i| cache["#{key}_#{i+1}"] }.compact
                     when "path"
                       cache["#{key}"] || value["value"]
                     end
  end
end

# Create a scheduler object.
def create_scheduler(conf)
  available = Dir.glob("#{SCHEDULERS_DIR_PATH}/*.rb").map { |f| File.basename(f, ".rb") }
  if conf.key?("clusters")
    schedulers = {}
    conf["scheduler"].each do |cluster_name, scheduler_name|
      halt 500, "No such scheduler_name (#{scheduler_name}) found." unless available.include?(scheduler_name)

      require "#{SCHEDULERS_DIR_PATH}/#{scheduler_name}.rb"
      schedulers[cluster_name] = Object.const_get(scheduler_name.capitalize).new
    end
  else
    scheduler_name = conf["scheduler"]
    halt 500, "No such scheduler_name (#{scheduler_name}) found." unless available.include?(scheduler_name)

    require "#{SCHEDULERS_DIR_PATH}/#{scheduler_name}.rb"
    schedulers = Object.const_get(scheduler_name.capitalize).new
  end

  schedulers
end

# Determine the action key based on script and submit sections.
# Rules:
# - Neither set:             -> "submit"
# - Both set:                -> "confirm-save"
# - Only script section set: -> "save"
# - Only submit section set: -> "confirm"
def get_form_action(body)
  script = body["script"]
  submit = body["submit"]

  # Determine script action
  script_action = if script.is_a?(Hash)
                    action = script["action"] || "submit"
                    ["submit", "save"].include?(action) ? action : "submit"
                  else
                    "submit"
                  end

  # Determine submit action
  submit_action = if submit.is_a?(Hash)
                    action = submit["action"] || "submit"
                    ["submit", "confirm"].include?(action) ? action : "submit"
                  else
                    "submit"
                  end

  # Combine rules
  case [script_action, submit_action]
  when ["submit", "submit"]
    "submit"
  when ["save", "confirm"]
    "confirm-save"
  when ["save", "submit"]
    "save"
  else # ["submit", "confirm"]
    "confirm"
  end
end

# Determine whether to show the overwrite warning when script content will be regenerated.
# Default: true
def check_overwrite_warning?(content)
  return true unless content.is_a?(Hash)

  raw_value = content["overwrite_warning"]

  return true if raw_value.nil?
  return raw_value if [true, false].include?(raw_value)

  if raw_value.is_a?(String)
    normalized = raw_value.strip.downcase
    return true if ["true", "1", "yes", "on"].include?(normalized)
    return false if ["false", "0", "no", "off"].include?(normalized)
  end

  !!raw_value
end

# Returns the directory where user templates are stored.
def templates_dir(conf)
  File.join(conf["data_dir"], "templates")
end

# Load all user-saved templates from the templates directory.
def load_templates(conf)
  dir = templates_dir(conf)
  return [] unless Dir.exist?(dir)
  Dir.glob(File.join(dir, "*.yml")).filter_map do |path|
    begin
      yaml = YAML.safe_load(File.read(path))
      next unless yaml.is_a?(Hash) && yaml["name"]
      app_path = yaml["app_path"].to_s.strip
      app_path = yaml.dig("values", "appPath").to_s.strip if app_path.empty?
      app_path = "_generic/Slurm" if app_path.empty?
      {
        "slug"        => File.basename(path, ".yml"),
        "name"        => yaml["name"],
        "description" => yaml["description"].to_s,
        "app_path"    => app_path,
        "icon"        => yaml["icon"].to_s
      }
    rescue
      nil
    end
  end.sort_by { |t| t["name"].downcase }
end

# Create a website of Home, Application, and History.
def show_website(job_id = nil, error_msg = nil, error_params = nil, script_path = nil)
  @conf          = create_conf
  @apps_dir      = @conf["apps_dir"]
  @version       = VERSION
  @my_ood_url    = request.base_url
  @script_name   = request.script_name
  @dir_name      = request.path_info.sub(/^\//, '')
  @cluster_name  = if @conf.key?("clusters")
                     escape_html(params[["history", "nodes"].include?(@dir_name) ? "cluster" : HEADER_CLUSTER_NAME] || @conf["clusters"].keys.first)
                   else
                     nil
                   end
  @login_node    = if @conf.key?("clusters")
                     @conf["login_node"][@cluster_name]
                   else
                     @conf["login_node"]
                   end

  @ood_logo_path = URI.join(@my_ood_url, @script_name + "/", "ood.png")
  @current_path  = File.join(@script_name, @dir_name)
  @manifests     = create_all_manifests(@apps_dir).sort_by { |m| [(m.category || "").downcase, m.name.downcase] }
  @manifests_w_category, @manifests_wo_category = @manifests.partition(&:category)

  case @dir_name
  when ""
    @name = "Home"
    @templates = load_templates(@conf)
    return erb :index
  when "history"
    @name          = "History"
    @scheduler     = create_scheduler(@conf)
    @bin           = @conf["bin"]
    @bin_overrides = @conf["bin_overrides"]
    @ssh_wrapper   = @conf["ssh_wrapper"]
    @statuses      = parse_history_statuses(params["statuses"])
    @filter        = escape_html(params["filter"])
    @filter_column = parse_history_filter_column(params["filter_column"], @conf)
    @sort          = parse_history_sort(params["sort"], @conf)
    @order         = parse_history_order(params["order"])
    @date_range, raw_date_from, raw_date_to = parse_history_date_range(params["date_range"], params["date_from"], params["date_to"])
    @date_from     = escape_html(raw_date_from)
    @date_to       = escape_html(raw_date_to)
    @filter_mode   = escape_html(params["filter_mode"] || "and")
    @detail_open   = escape_html(params["detail_open"] || "false")
    requested_rows = [(params["rows"] || HISTORY_ROWS).to_i, 1].max
    @current_page  = (params["p"] || 1).to_i
    offset         = (@current_page - 1) * requested_rows

    scheduler_s     = @conf.key?("clusters") ? @scheduler[@cluster_name]        : @scheduler
    bin_s           = @conf.key?("clusters") ? @bin[@cluster_name]               : @bin
    bin_overrides_s = @conf.key?("clusters") ? @bin_overrides[@cluster_name]     : @bin_overrides
    ssh_wrapper_s   = @conf.key?("clusters") ? @ssh_wrapper[@cluster_name]       : @ssh_wrapper

    db         = open_history_db(@conf, @cluster_name)
    deleted_db = open_deleted_db(@conf, @cluster_name)
    deleted_ids = Set.new(deleted_db.execute("SELECT _job_id FROM deleted_jobs").map { |r| r["_job_id"] })

    sacct_from = raw_date_from.to_s.empty? ? (Date.today - 6).strftime("%Y-%m-%d") : raw_date_from.to_s
    sacct_to   = raw_date_to.to_s.empty?   ? Date.today.strftime("%Y-%m-%d")        : raw_date_to.to_s
    all_sacct_jobs, @sacct_error, _cmd = scheduler_s.sacct_all_jobs(sacct_from, sacct_to, bin_s, bin_overrides_s, ssh_wrapper_s)

    sacct_map = {}
    (all_sacct_jobs || []).each do |j|
      jid = j["JobID"].to_s.strip
      next unless valid_oc_job_id?(jid)
      sacct_map[jid] = j
    end

    db1_map = db.execute("SELECT * FROM jobs").each_with_object({}) { |r, h| h[r["_job_id"]] = r }

    history_search_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @jobs, @jobs_size = build_merged_history_jobs(
      sacct_map, db1_map, deleted_ids,
      @statuses, @filter, @filter_column, @filter_mode,
      raw_date_from.to_s, raw_date_to.to_s,
      @sort, @order, requested_rows, offset
    )
    @history_search_elapsed_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - history_search_started_at

    @rows        = [requested_rows, @jobs_size].min
    @page_size   = (@rows == 0) ? 1 : ((@jobs_size - 1) / @rows) + 1
    @start_index = @jobs_size == 0 ? 0 : (@current_page - 1) * @rows
    @end_index   = @jobs_size == 0 ? 0 : [@current_page * @rows, @jobs_size].min - 1
    @error_msg   = error_msg

    @filter_column_items = history_filter_column_items(@conf)
    @date_range_items    = history_date_range_items
    @history_search_elapsed_label = format("%.3f", @history_search_elapsed_seconds || 0.0)

    return erb :history
  when "nodes"
    @name = "Nodes"
    return erb :nodes
  else # application form
    @table_index     = 1
    generic_apps_dir = @conf["generic_apps_dir"] || "./generic_apps"

    # Apps under the _generic/ URL prefix are loaded from generic_apps_dir and
    # are intentionally excluded from the main index listing shown to users.
    if @dir_name.start_with?("_generic/")
      @app_base_path = File.join(generic_apps_dir, @dir_name.sub(/\A_generic\//, ""))
      @manifest      = create_manifest(@app_base_path)
    else
      @manifest      = @manifests.find { |m| "#{m.dirname}" == @dir_name }
      @app_base_path = File.join(@apps_dir, @dir_name)
    end

    unless @manifest.nil?
      begin
        @name = @manifest["name"]
        @OC_APP_NAME = @name
        @OC_DIR_NAME = @manifest["dirname"]
        @body = read_yaml(File.join(@app_base_path, "form.yml"))
        @header = if @body.key?("header")
                    @body["header"]
                  else
                    read_yaml("./lib/header.yml")["header"]
                  end
      rescue Exception => e
        @error_msg = e.message
        return erb :error
      end

      # Check if the form key exists. The form body may legitimately be empty
      # (a header-only app such as the generic Slurm app), so a "form:" with no
      # widgets is allowed. It is normalized to an empty hash below so the
      # rendering helpers (which call body["form"].merge(...)) do not crash.
      ["form.yml", "form.yml.erb"].each do |name|
        file = File.join(@app_base_path, name)
        next unless File.exist?(file)

        halt 500, "In ./#{file}, \"form:\" must be defined." unless @body.key?("form")
      end
      @body["form"] ||= {} if @body.is_a?(Hash) && @body.key?("form")

      @form_action = get_form_action(@body)
      @submit_overwrite_warning_enabled = check_overwrite_warning?(@body["submit"])

      # Since the widget name is used as a variable in Ruby, it should consist of only
      # alphanumeric characters and underscores, and numbers should not be used at the
      # beginning of the name. Furthermore, underscores are also prohibited at the
      # beginning of the name to avoid conflicts with Open Composer's internal variables.
      if @body&.dig("form")
        invalid_keys = @body["form"].each_key.reject { |key| key.match?(/^[a-zA-Z][a-zA-Z0-9_]*$/) }
        unless invalid_keys.empty?
          @error_msg = "Widget name(s) (#{invalid_keys.join(', ')}) cannot be used.\n"
          return erb :error
        end
      end

      # Load cache
      @script_content = nil
      @submit_content = nil
      if params["template"]
        slug      = params["template"].gsub(/[^a-zA-Z0-9_\-]/, '')
        tmpl_path = File.join(templates_dir(@conf), "#{slug}.yml")
        if File.exist?(tmpl_path)
          begin
            tmpl  = YAML.safe_load(File.read(tmpl_path))
            cache = tmpl.is_a?(Hash) ? (tmpl["values"] || {}) : {}
            replace_with_cache(@header, cache)
            replace_with_cache(@body["form"], cache)
            @script_content          = escape_html(cache[OC_SCRIPT_CONTENT].to_s) if cache[OC_SCRIPT_CONTENT]
            @submit_content          = escape_html(cache[SUBMIT_CONTENT].to_s) if cache[SUBMIT_CONTENT]
            @template_slug           = slug
            @template_name           = tmpl.is_a?(Hash) ? tmpl["name"].to_s : ''
            @template_description    = tmpl.is_a?(Hash) ? tmpl["description"].to_s : ''
          rescue
          end
        end
      elsif params["jobId"] || job_id
        cluster_name = if @conf.key?("clusters")
                         params[params["jobId"] ? "cluster" : HEADER_CLUSTER_NAME] || @conf["clusters"].keys.first
                       end

        cache = nil
        id = if params["jobId"]
               params["jobId"]
             else
               job_id.is_a?(Array) ? job_id[0].to_s : job_id.to_s
             end
        begin
          db = open_history_db(@conf, cluster_name)
        rescue StandardError
          history_db = @conf.key?("clusters") ? @conf["history_db"][cluster_name] : @conf["history_db"]
          @error_msg = history_db.nil? ? "#{cluster_name} is invalid." : "#{history_db} is not found."
          return erb :error
        end
        record = find_job(db, id)
        cache = job_record_to_legacy_hash(record)

        if cache.nil?
          if @dir_name == "Slurm"
            sched_inst = create_scheduler(@conf)
            bin_val    = @conf["bin"]
            bin_ov_val = @conf["bin_overrides"]
            ssh_val    = @conf["ssh_wrapper"]
            sched_s    = @conf.key?("clusters") ? sched_inst[cluster_name] : sched_inst
            bin_s2     = @conf.key?("clusters") ? bin_val[cluster_name]    : bin_val
            bin_ov_s2  = @conf.key?("clusters") ? bin_ov_val[cluster_name] : bin_ov_val
            ssh_s2     = @conf.key?("clusters") ? ssh_val[cluster_name]    : ssh_val
            script_content, _err = sched_s.batch_script(id, bin_s2, bin_ov_s2, ssh_s2)
            if script_content
              @script_content = escape_html(script_content)
              sbatch_cache = parse_sbatch_into_cache(script_content, @body, @OC_APP_NAME, @OC_DIR_NAME)
              replace_with_cache(@header, sbatch_cache)
              replace_with_cache(@body["form"], sbatch_cache)
            end
          else
            @error_msg = "Specified Job ID (#{id}) is not found."
            return erb :error
          end
        else
          replace_with_cache(@header, cache)
          replace_with_cache(@body["form"], cache)
          if !cache[OC_SCRIPT_CONTENT].to_s.strip.empty?
            @script_content = escape_html(cache[OC_SCRIPT_CONTENT])
          elsif @dir_name == "Slurm"
            # Script content not stored in DB — fetch from sacct -B
            sched_inst = create_scheduler(@conf)
            bin_val    = @conf["bin"]
            bin_ov_val = @conf["bin_overrides"]
            ssh_val    = @conf["ssh_wrapper"]
            sched_s    = @conf.key?("clusters") ? sched_inst[cluster_name] : sched_inst
            bin_s2     = @conf.key?("clusters") ? bin_val[cluster_name]    : bin_val
            bin_ov_s2  = @conf.key?("clusters") ? bin_ov_val[cluster_name] : bin_ov_val
            ssh_s2     = @conf.key?("clusters") ? ssh_val[cluster_name]    : ssh_val
            script_content, _err = sched_s.batch_script(id, bin_s2, bin_ov_s2, ssh_s2)
            if script_content
              @script_content = escape_html(script_content)
              sbatch_cache = parse_sbatch_into_cache(script_content, @body, @OC_APP_NAME, @OC_DIR_NAME)
              replace_with_cache(@header, sbatch_cache)
              replace_with_cache(@body["form"], sbatch_cache)
            end
          end
          @submit_content = escape_html(cache[SUBMIT_CONTENT])
        end
      elsif !error_msg.nil? || !script_path.nil? # When job submission failed or script_path != nil (because after script file has been saved)
        replace_with_cache(@header, error_params)
        replace_with_cache(@body["form"], error_params)
        @script_content = escape_html(error_params[OC_SCRIPT_CONTENT])
        @submit_content = escape_html(error_params[SUBMIT_CONTENT])
      end

      # Set script content
      @script_label = if @body["script"].is_a?(Hash)
                        @body["script"]["label"] || "Script Content"
                      else
                        "Script Content"
                      end

      @job_id    = job_id.is_a?(Array) ? job_id.join(", ") : job_id
      @error_msg = error_msg&.force_encoding('UTF-8')
      @script_path = script_path
      return erb :form
    else
      @error_msg = "#{request.url} is not found."
      return erb :error
    end
  end
end

# Raise a RuntimeError with the given message if the condition is false.
# This function is used in a check section of form.yml[.erb].
def oc_assert(condition, message = "Error exists in script content.")
  raise RuntimeError, message unless condition
end

# Set value to the specified instance variable (@#{key}) in the check section.
# If a value already exists, add value like [old, value] or "#{old}#{separator}#{value}".
def set_check_value(key, value, separator = nil)
  k = :"@#{key}"

  if instance_variable_defined?(k)
    old = instance_variable_get(k)

    if separator.nil?
      new_val =
        if old.is_a?(Array)
          if value.is_a?(Array)
            old.first.is_a?(Array) ? (old + [value]) : [old, value]
          else
            old + [value]
          end
        else
          [old, value]
        end
      instance_variable_set(k, new_val)
    else
      instance_variable_set(k, "#{old}#{separator}#{value}")
    end
  else
    instance_variable_set(k, value)
  end
end

# Output log
def output_log(action, scheduler, **details)
  base = "[#{Time.now}] [Open Composer] #{action} : scheduler=#{scheduler.class.name}"
  extra = details
            .reject { |_k, v| v.nil? || v.to_s.strip.empty? }
            .map    { |k, v| "#{k}=#{v}" }
            .join(" : ")
  puts [base, extra].reject(&:empty?).join(" : ")
end

# Send an application icon.
get "/:apps_dir/:folder/:icon" do
  icon_path = File.join(create_conf["apps_dir"], params[:folder], params[:icon])
  send_file(icon_path) if File.exist?(icon_path)
end

# Return a list of files and/or directories in JSON format.
get "/_files" do
  path = params[:path] || "."
  path = File.dirname(path) if File.file?(path)

  content_type :json
  if File.exist?(path)
    entries = Dir.children(path).map do |entry|
      full_path = File.join(path, entry)
      { name: entry, path: full_path, type: File.directory?(full_path) ? "directory" : "file" }
    end.sort_by { |entry| entry[:name].downcase }
  else
    # When a non-existent directory is specified using the set-value statement of the dynamic form widget.
    entries = ""
  end

  { files: entries }.to_json
end

# Return whether the specified PATH is a file or a directory.
get "/_file_or_directory" do
  path = params[:path] || "."
  content_type :json

  if File.file?(path)
    { type: "file" }.to_json
  else
    { type: "directory" }.to_json
  end
end

post "/history/save_external_script" do
  conf         = create_conf
  cluster_name = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  target_app   = conf["external_reload_app"] || "Slurm"
  cluster_param = cluster_name ? "?#{HEADER_CLUSTER_NAME}=#{URI.encode_www_form_component(cluster_name)}" : ""
  content_type :json
  { url: "#{request.script_name}/_generic/#{target_app}#{cluster_param}" }.to_json
end

get "/job_details" do
  content_type :json

  job_id = (params["jobId"] || "").strip
  return { "error" => "No job ID specified" }.to_json if job_id.empty?
  return { "error" => "Invalid job ID" }.to_json unless job_id.match?(/\A[\d_.\[\]+]+\z/) # '+' allows Slurm heterogeneous-job component IDs (e.g. 1234+0).

  conf         = create_conf
  cluster_name = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  scheduler    = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  bin          = conf.key?("clusters") ? conf["bin"][cluster_name]          : conf["bin"]
  bin_overrides= conf.key?("clusters") ? conf["bin_overrides"][cluster_name]: conf["bin_overrides"]
  ssh_wrapper  = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name]  : conf["ssh_wrapper"]

  result = {
    "job_id"          => job_id,
    "source"          => "none",
    "data"            => {},
    "script_location" => nil,
    "script_name"     => nil,
    "script_content"  => nil
  }

  # Route to sacct first to determine if job is terminal; if not, use scontrol.
  terminal = [JOB_STATUS["completed"], JOB_STATUS["cancelled"], JOB_STATUS["failed"]]
  sacct_data, sacct_err, sacct_cmd = scheduler.sacct_job(job_id, bin, bin_overrides, ssh_wrapper)
  oc_status = sacct_data && !sacct_data.empty? ? sacct_state_to_oc_status(sacct_data["State"].to_s) : nil

  if sacct_data && !sacct_data.empty? && terminal.include?(oc_status)
    # Terminal job confirmed by sacct — use sacct data
    result["source"]  = "sacct"
    result["command"] = sacct_cmd
    result["data"]    = sacct_data
    workdir = sacct_data["WorkDir"]
    result["script_location"] = workdir unless workdir.to_s.strip.empty? || workdir == "None"
  else
    # Active or unknown — try scontrol first, then sacct
    scontrol_data, scontrol_err, scontrol_cmd = scheduler.scontrol_job(job_id, bin, bin_overrides, ssh_wrapper)
    if scontrol_data && !scontrol_data.empty?
      result["source"]  = "scontrol"
      result["command"] = scontrol_cmd
      result["data"]    = scontrol_data
      cmd = scontrol_data["Command"]
      if cmd && cmd != "(null)" && !cmd.strip.empty?
        result["script_location"] = File.dirname(cmd)
        result["script_name"]     = File.basename(cmd)
      end
      result["script_location"] ||= scontrol_data["WorkDir"]
    elsif sacct_data && !sacct_data.empty?
      result["source"]  = "sacct"
      result["command"] = sacct_cmd
      result["data"]    = sacct_data
      workdir = sacct_data["WorkDir"]
      result["script_location"] = workdir unless workdir.to_s.strip.empty? || workdir == "None"
    else
      errors = { "scontrol" => scontrol_err, "sacct" => sacct_err }.compact
      result["errors"] = errors unless errors.empty?
    end
  end

  script_content, _err = scheduler.batch_script(job_id, bin, bin_overrides, ssh_wrapper)
  result["script_content"] = script_content

  result.to_json
rescue Exception => e
  { "error" => e.message }.to_json
end

post "/history/cancel_one" do
  conf         = create_conf
  job_id       = params["jobId"].to_s.strip
  content_type :json
  return JSON.generate({ ok: false, error: "No job ID" }) if job_id.empty?
  return JSON.generate({ ok: false, error: "Invalid job ID" }) unless job_id.match?(/\A[\d_.\[\]+\-]+\z/)

  cluster_name  = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  scheduler     = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  bin           = conf.key?("clusters") ? conf["bin"][cluster_name]           : conf["bin"]
  bin_overrides = conf.key?("clusters") ? conf["bin_overrides"][cluster_name] : conf["bin_overrides"]
  ssh_wrapper   = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name]   : conf["ssh_wrapper"]

  error_msg = scheduler.cancel([job_id], bin, bin_overrides, ssh_wrapper)
  if error_msg.nil?
    output_log("Cancel job", scheduler, cluster: cluster_name, job_ids: [job_id])
    JSON.generate({ ok: true })
  else
    JSON.generate({ ok: false, error: error_msg.to_s })
  end
rescue => e
  content_type :json
  JSON.generate({ ok: false, error: e.message })
end

get "/history/active_job_ids" do
  conf         = create_conf
  content_type :json
  cluster_name  = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  scheduler     = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  bin           = conf.key?("clusters") ? conf["bin"][cluster_name]           : conf["bin"]
  bin_overrides = conf.key?("clusters") ? conf["bin_overrides"][cluster_name] : conf["bin_overrides"]
  ssh_wrapper   = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name]   : conf["ssh_wrapper"]

  deleted_db  = open_deleted_db(conf, cluster_name)
  deleted_ids = Set.new(deleted_db.execute("SELECT _job_id FROM deleted_jobs").map { |r| r["_job_id"] })

  from = (Date.today - 29).strftime("%Y-%m-%d")
  to   = Date.today.strftime("%Y-%m-%d")
  all_jobs, _err, _cmd = scheduler.sacct_all_jobs(from, to, bin, bin_overrides, ssh_wrapper)

  active_statuses = [JOB_STATUS["queued"], JOB_STATUS["running"]]
  ids = (all_jobs || []).filter_map do |j|
    jid = j["JobID"].to_s.strip
    next unless valid_oc_job_id?(jid)
    next if deleted_ids.include?(jid)
    oc_status = sacct_state_to_oc_status(j["State"].to_s)
    jid if active_statuses.include?(oc_status)
  end

  JSON.generate(ids)
rescue => e
  content_type :json
  JSON.generate([])
end

get "/nodes/data" do
  conf = create_conf
  if conf.key?("clusters")
    cluster_name    = params["cluster"] || conf["clusters"].keys.first
    scheduler_s     = create_scheduler(conf)[cluster_name]
    bin_s           = conf["bin"][cluster_name]
    bin_overrides_s = conf["bin_overrides"][cluster_name]
    ssh_wrapper_s   = conf["ssh_wrapper"][cluster_name]
  else
    scheduler_s     = create_scheduler(conf)
    bin_s           = conf["bin"]
    bin_overrides_s = conf["bin_overrides"]
    ssh_wrapper_s   = conf["ssh_wrapper"]
  end
  nodes, error = scheduler_s.sinfo_nodes(bin_s, bin_overrides_s, ssh_wrapper_s)
  rows = (nodes || []).map do |cols|
    { node: cols[0], state: cols[1], cpus: cols[2], memory: cols[3], freemem: cols[4], gres: cols[5], gresused: cols[6] }
  end
  content_type :json
  { error: error, rows: rows, fetched_at: Time.now.strftime("%H:%M:%S") }.to_json
end

post "/templates/:slug/overwrite" do
  conf = create_conf
  slug = params["slug"].gsub(/[^a-zA-Z0-9_\-]/, '')
  path = File.join(conf["data_dir"], "templates", "#{slug}.yml")
  halt 404, "Template not found." unless File.exist?(path)

  begin
    existing = YAML.safe_load(File.read(path))
  rescue
    existing = {}
  end
  existing = {} unless existing.is_a?(Hash)

  skip   = %w[template_name template_description _tmpl_icon splat captures]
  values = params.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s unless skip.include?(k) }

  File.write(path, existing.merge({
    "app_path" => params[JOB_DIR_NAME].to_s.strip,
    "icon"     => params["_tmpl_icon"].to_s,
    "values"   => values
  }).to_yaml)

  redirect request.script_name.empty? ? "/" : request.script_name
end

post "/templates/:slug/rename" do
  conf = create_conf
  slug = params["slug"].gsub(/[^a-zA-Z0-9_\-]/, '')
  path = File.join(conf["data_dir"], "templates", "#{slug}.yml")
  halt 404, "Template not found." unless File.exist?(path)

  name = params["template_name"].to_s.strip
  halt 400, "Template name is required." if name.empty?

  begin
    data = YAML.safe_load(File.read(path))
  rescue
    data = {}
  end
  data = {} unless data.is_a?(Hash)

  File.write(path, data.merge({
    "name"        => name,
    "description" => params["template_description"].to_s.strip
  }).to_yaml)

  redirect request.script_name.empty? ? "/" : request.script_name
end

post "/templates" do
  conf = create_conf
  dir  = File.join(conf["data_dir"], "templates")
  FileUtils.mkdir_p(dir)

  name = params["template_name"].to_s.strip
  halt 400, "Template name is required." if name.empty?

  slug      = name.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
  slug      = "template" if slug.empty?
  base_slug = slug
  i = 1
  while File.exist?(File.join(dir, "#{slug}.yml"))
    slug = "#{base_slug}_#{i}"
    i += 1
  end

  skip   = %w[template_name template_description _tmpl_icon splat captures]
  values = params.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s unless skip.include?(k) }

  File.write(File.join(dir, "#{slug}.yml"), {
    "name"        => name,
    "description" => params["template_description"].to_s.strip,
    "app_path"    => params[JOB_DIR_NAME].to_s.strip,
    "icon"        => params["_tmpl_icon"].to_s,
    "values"      => values
  }.to_yaml)

  redirect request.script_name.empty? ? "/" : request.script_name
end

post "/templates/:slug/delete" do
  conf = create_conf
  slug = params["slug"].gsub(/[^a-zA-Z0-9_\-]/, '')
  path = File.join(conf["data_dir"], "templates", "#{slug}.yml")
  File.delete(path) if File.exist?(path)
  redirect request.script_name.empty? ? "/" : request.script_name
end

get "/*" do
  show_website
end

post "/*" do
  # Keep POST handlers on the local conf object. @conf is initialized in show_website.
  conf          = create_conf
  cluster_name  = if conf.key?("clusters")
                    params[request.path_info == "/history" ? "cluster" : HEADER_CLUSTER_NAME] || conf["clusters"].keys.first
                  else
                    nil
                  end
  scheduler     = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  ssh_wrapper   = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name] : conf["ssh_wrapper"]
  bin           = conf.key?("clusters") ? conf["bin"][cluster_name] : conf["bin"]
  bin_overrides = conf.key?("clusters") ? conf["bin_overrides"][cluster_name] : conf["bin_overrides"]
  history_db    = conf.key?("clusters") ? conf["history_db"][cluster_name] : conf["history_db"]
  data_dir      = conf["data_dir"]
  ENV['SGE_ROOT'] ||= conf.key?("clusters") ? conf["sge_root"][cluster_name] : conf["sge_root"]

  if request.path_info == "/history"
    job_ids   = params["JobIds"].to_s.split(",").reject(&:empty?)
    error_msg = nil

    case params["action"]
    when "CancelJob"
      error_msg = scheduler.cancel(job_ids, bin, bin_overrides, ssh_wrapper)
      output_log("Cancel job", scheduler, cluster: cluster_name, job_ids: job_ids)
    when "DeleteInfo"
      if history_db
        db         = open_history_db(conf, conf.key?("clusters") ? cluster_name : nil)
        deleted_db = open_deleted_db(conf, conf.key?("clusters") ? cluster_name : nil)
        job_ids.each { |job_id| delete_job(db, deleted_db, job_id) }
        output_log("Delete job information", scheduler, cluster: cluster_name, job_ids: job_ids)
      end
    when "CancelAll"
      from = (Date.today - 29).strftime("%Y-%m-%d")
      to   = Date.today.strftime("%Y-%m-%d")
      all_sacct, _err2, _cmd2 = scheduler.sacct_all_jobs(from, to, bin, bin_overrides, ssh_wrapper)
      active_statuses = [JOB_STATUS["queued"], JOB_STATUS["running"]]
      cancel_ids = (all_sacct || []).filter_map do |j|
        jid = j["JobID"].to_s.strip
        next unless valid_oc_job_id?(jid)
        jid if active_statuses.include?(sacct_state_to_oc_status(j["State"].to_s))
      end
      unless cancel_ids.empty?
        error_msg = scheduler.cancel(cancel_ids, bin, bin_overrides, ssh_wrapper)
        output_log("Cancel all jobs", scheduler, cluster: cluster_name, job_ids: cancel_ids)
      end
    when "DeleteAll"
      if history_db
        db         = open_history_db(conf, conf.key?("clusters") ? cluster_name : nil)
        deleted_db = open_deleted_db(conf, conf.key?("clusters") ? cluster_name : nil)
        from = (Date.today - 29).strftime("%Y-%m-%d")
        to   = Date.today.strftime("%Y-%m-%d")
        all_sacct, _err2, _cmd2 = scheduler.sacct_all_jobs(from, to, bin, bin_overrides, ssh_wrapper)
        active_statuses = [JOB_STATUS["queued"], JOB_STATUS["running"]]
        active_count = (all_sacct || []).count do |j|
          jid = j["JobID"].to_s.strip
          valid_oc_job_id?(jid) && active_statuses.include?(sacct_state_to_oc_status(j["State"].to_s))
        end
        if active_count > 0
          noun = active_count == 1 ? "job is" : "jobs are"
          error_msg = "#{active_count} #{noun} still Running or Queued. Cancel them all first, then delete all history."
        else
          sacct_ids = (all_sacct || []).filter_map do |j|
            jid = j["JobID"].to_s.strip
            valid_oc_job_id?(jid) ? jid : nil
          end
          delete_all_jobs(db, deleted_db, sacct_ids)
          output_log("Delete all job history", scheduler, cluster: cluster_name)
        end
      end
    end

    return show_website(nil, error_msg)
  else # application form
    generic_apps_dir = conf["generic_apps_dir"] || "./generic_apps"
    app_path = if request.path_info.start_with?("/_generic/")
                 File.join(generic_apps_dir, request.path_info.sub(/\A\/_generic\//, ""))
               else
                 File.join(conf["apps_dir"], request.path_info)
               end
    manifest = create_manifest(app_path)

    script_location = params[HEADER_SCRIPT_LOCATION]
    script_name     = params[HEADER_SCRIPT_NAME]
    job_name        = params[HEADER_JOB_NAME]
    error_msg =
      if script_location.nil?
        "#{HEADER_SCRIPT_LOCATION} is not defined in #{app_path}/form.yml[.erb]."
      elsif script_name.nil?
        "#{HEADER_SCRIPT_NAME} is not defined in #{app_path}/form.yml[.erb]."
      elsif job_name.nil?
        "#{HEADER_JOB_NAME} is not defined in #{app_path}/form.yml[.erb]."
      else
        nil
      end
    return show_website(nil, error_msg, params) if error_msg

    begin
      form = read_yaml(File.join(app_path, "form.yml"))
    rescue Exception => e
      @error_msg = e.message
      return erb :error
    end
    form["form"] ||= {} if form.is_a?(Hash) # Allow a header-only app with an empty form body.

    script_path    = File.join(script_location, script_name)
    script_dir     = File.dirname(script_path)
    script_content = params[OC_SCRIPT_CONTENT].gsub("\r\n", "\n") # Since HTML textarea for OC_SCRIPT_CONTENT is required, params[OC_SCRIPT_CONTENT] must not be nil.
    form_action    = get_form_action(form)
    job_id         = nil
    submit_options = nil

    # Run commands in the check section
    check_content = form["check"]
    if !check_content.nil?
      params.each do |key, value|
        next if SKIP_KEYS.include?(key)
        if DEFINED_KEYS.key?(key)
          set_check_value(DEFINED_KEYS[key], value)
          next
        end

        base_key = num = nil
        if key =~ /^(.*)_(\d+)$/
          base_key, num = $1, $2
        end
        widget = form["form"][key]&.dig("widget") || (base_key && form["form"][base_key]&.dig("widget"))
        next unless widget

        if ["number"].include?(widget)
          set_check_value(key, value.to_f == value.to_i ? value.to_i : value.to_f)
        elsif ["text", "email", "path"].include?(widget)
          set_check_value(key, value)
        elsif ["select", "radio"].include?(widget)
          option = form["form"][key]["options"].find { |x| x[0].to_s == value }
          if option.size == 1
            set_check_value(key, option[0])
          else
            set_check_value(key, option[1])
            if option[1].is_a?(Array)
              option[1].each_with_index { |v, i| set_check_value("#{key}_#{i+1}", v) }
            end
          end
        elsif ["multi_select", "checkbox"].include?(widget)
          separator = form["form"][base_key]["separator"]
          option = form["form"][base_key]["options"].find { |x| x[0].to_s == value }
          if option.size == 1
            set_check_value(base_key, option[0], separator)
          else
            set_check_value(base_key, option[1], separator)
            if option[1].is_a?(Array)
              option[1].each_with_index { |v, i| set_check_value("#{base_key}_#{i+1}", v, separator) }
            end
          end
        end
      end

      begin
        output_log("Run commands in the check section", scheduler, command: check_content)
        Dir.chdir(script_dir) do
          eval(check_content)
        end
      rescue Exception => e
        return show_website(nil, e.message, params)
      end
    end

    # Save a job script
    FileUtils.mkdir_p(script_location)
    File.open(script_path, "w") { |file| file.write(script_content) }

    # Run commands in the submit section
    submit_content = params[SUBMIT_CONTENT].nil? ? nil : params[SUBMIT_CONTENT].gsub("\r\n", "\n")

    if !submit_content.nil?
      submit_with_echo = <<~BASH
        #{submit_content}
        if [ -n "$OC_SUBMIT_OPTIONS" ]; then
          echo "$OC_SUBMIT_OPTIONS"
        else
          echo "__UNDEFINED__"
        fi
        BASH

      output_log("Run commands in the submit section", scheduler, command: submit_with_echo)
      stdout, stderr, status = nil
      Dir.chdir(script_dir) do
        stdout, stderr, status = Open3.capture3("bash", "-c", submit_with_echo)
      end
      unless status.success?
        return show_website(nil, stderr, params)
      end

      last_line = stdout.lines.last&.strip
      submit_options = (last_line == "__UNDEFINED__") ? nil : last_line
    end

    # Submit a job script
    if form_action == "save" || form_action == "confirm-save"
      output_log("Save job file", scheduler, cluster: cluster_name, app_dir: manifest["dirname"], app_name: manifest["name"], category: manifest["category"], script_path: script_path)
      return show_website(nil, nil, params, script_path)
    end

    Dir.chdir(script_dir) do
      job_id, error_msg = scheduler.submit(script_path, escape_html(job_name.strip), submit_options, bin, bin_overrides, ssh_wrapper)
      params[JOB_SUBMISSION_TIME] = Time.now.iso8601
    end

    # Save a job history (only valid job IDs: plain integer or integer_integer)
    FileUtils.mkdir_p(data_dir)
    db = open_history_db(conf, conf.key?("clusters") ? cluster_name : nil)
    store_script = conf.fetch("history_store_script", true)
    db.transaction do
      Array(job_id).each do |id|
        next unless valid_oc_job_id?(id.to_s)
        upsert_job(db, {
          "_job_id"          => id.to_s,
          "_app_name"        => params[JOB_APP_NAME],
          "_app_dir_name"    => params[JOB_DIR_NAME],
          "_script_location" => params[HEADER_SCRIPT_LOCATION],
          "_script_name"     => params[HEADER_SCRIPT_NAME],
          "_submission_time" => normalize_time_for_db(params[JOB_SUBMISSION_TIME]),
          "_script_content"  => store_script ? script_content : nil
        })
      end
    end

    # Output log
    output_log("Submit job", scheduler, cluster: cluster_name, job_ids: Array(job_id), app_dir: manifest["dirname"], app_name: manifest["name"], category: manifest["category"])

    return show_website(job_id, error_msg, params, script_path)
  end
end
