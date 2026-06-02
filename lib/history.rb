

helpers do
  # Generate HTML for icons linking to related applications.
  def output_related_apps_icon(job_app_path, apps)
    return [] if apps.nil?

    apps.map do |name, conf|
      href = "#{@my_ood_url}/pun/sys/dashboard/apps/show/#{name}"
      icon = conf&.dig('icon')
      if icon.nil?
        icon_path = "#{@my_ood_url}/pun/sys/dashboard/apps/icon/#{name}/sys/sys"
        icon_html = "<img width=20 title=\"#{name}\" alt=\"#{name}\" src=\"#{icon_path}\">"
      else
        is_bi_or_fa_icon, icon_path = get_icon_path(job_app_path, icon)

        icon_html = if is_bi_or_fa_icon
                      "<i class=\"#{icon} fs-5\"></i>"
                    else
                      "<img width=20 title=\"#{name}\" alt=\"#{name}\" src=\"#{icon_path}\">"
                    end
      end

      "<a style=\"color: black; text-decoration: none;\" target=\"_blank\" href=\"#{href}\">\n  #{icon_html}\n</a>\n"
    end
  end

  # Output a modal for a specific action (e.g., CancelJob or DeleteInfo).
  def output_action_modal(action)
    id = "_history#{action}"
    form_action = history_path_with_query

    abort_buttons = action == "CancelJob" ? \
      "\n          <button type=\"button\" id=\"#{id}AbortBtn\" class=\"btn btn-warning d-none\">Abort</button>" \
      "\n          <button type=\"button\" id=\"#{id}CloseBtn\" class=\"btn btn-secondary d-none\" onclick=\"window.location.reload()\">Close</button>" \
      : ""

    <<~HTML
    <div class="modal" id="#{id}" aria-hidden="true" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable">
        <div class="modal-content">
          <div class="modal-body" id="#{id}Body">
            (Something wrong)
          </div>
          <div class="modal-footer" id="#{id}Footer">
            <form action="#{form_action}" method="post" id="#{id}Form">
              <input type="hidden" name="action" value="#{action}">
              <input type="hidden" name="JobIds" id="#{id}Input">
              <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">Cancel</button>
              <button type="submit" class="btn btn-primary" tabindex="-1">OK</button>
            </form>#{abort_buttons}
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a badge for an action button (e.g., CancelJob or DeleteInfo) with a modal trigger.
  def output_action_badge(action)
    return if action != "CancelJob" && action != "DeleteInfo"

    <<~HTML
    <button id="_history#{action}Badge" data-bs-toggle="modal" data-bs-target="#_history#{action}" class="btn btn-sm disabled" style="background-color:#{@conf['history_action_color']};border-color:#{@conf['history_action_color']};color:#fff;" disabled>
      #{(action == "CancelJob") ? "Cancel Job" : "Delete Info"}
      <span id="_history#{action}Count" class="badge bg-secondary">0</span>
    </button>
    HTML
  end

  # Output compact ascending/descending sort controls for a History table column.
  def output_history_sort_controls(sort_key)
    asc_class = ["history-sort-link", (@sort == sort_key && @order == "asc" ? "history-sort-active" : nil)].compact.join(" ")
    desc_class = ["history-sort-link", (@sort == sort_key && @order == "desc" ? "history-sort-active" : nil)].compact.join(" ")

    <<~HTML
    <span class="history-sort-controls">
      <a
        href="#{history_path_with_query(sort: sort_key, order: 'asc', p: 1)}"
        class="#{asc_class}"
        aria-label="Sort #{sort_key} ascending"
      ><span class="history-sort-icon">&#9650;</span></a>
      <a
        href="#{history_path_with_query(sort: sort_key, order: 'desc', p: 1)}"
        class="#{desc_class}"
        aria-label="Sort #{sort_key} descending"
      ><span class="history-sort-icon">&#9660;</span></a>
    </span>
    HTML
  end

  # Output a modal for displaying live job details fetched from scontrol/sacct.
  # Content is lazy-loaded via AJAX when the modal is opened.
  def output_job_id_modal(job, filter)
    modal_id   = "_historyJobId#{job[JOB_ID]}"
    job_id_esc = escape_html(job[JOB_ID].to_s)
    cluster_attr = @cluster_name ? " data-cluster=\"#{escape_html(@cluster_name)}\"" : ""

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable modal-lg">
        <div class="modal-content" style="resize: horizontal; padding-right: 16px;">
          <div class="modal-header">
            <h5>Job Details</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body" data-job-id="#{job_id_esc}"#{cluster_attr}>
            <div class="text-center py-3">
              <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">Loading...</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a modal displaying a job script and a link to load parameters.
  # If _script_content is blank, the script is lazy-loaded via sacct -B on modal open.
  def output_job_script_modal(job, filter)
    modal_id    = "_historyJobScript#{job[JOB_ID]}"
    job_link    = "#{File.join(@script_name.to_s, job[JOB_DIR_NAME].to_s)}?jobId=#{URI.encode_www_form_component(job[JOB_ID].to_s)}"
    job_link   += "&cluster=#{@cluster_name}" if @cluster_name
    has_content = !job[OC_SCRIPT_CONTENT].to_s.strip.empty?

    if has_content
      body_html = <<~HTML
      <div class="modal-body">
        #{output_text(job[OC_SCRIPT_CONTENT], filter)}
      </div>
      HTML
    else
      job_id_esc   = escape_html(job[JOB_ID].to_s)
      cluster_attr = @cluster_name ? " data-cluster=\"#{escape_html(@cluster_name)}\"" : ""
      body_html = <<~HTML
      <div class="modal-body" data-script-job-id="#{job_id_esc}"#{cluster_attr}>
        <div class="text-center py-3">
          <div class="spinner-border text-primary" role="status">
            <span class="visually-hidden">Loading...</span>
          </div>
        </div>
      </div>
      HTML
    end

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable modal-lg">
        <div class="modal-content" style="resize: horizontal; padding-right: 16px;">
          <div class="modal-header">
            <h5>Job Script</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          #{body_html}
          <div class="modal-footer">
            <a href="#{job_link}" class="btn btn-primary text-white text-decoration-none">Load parameters</a>
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">Close</button>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a script modal with lazy-load for jobs without an OC app directory.
  def output_job_slurm_script_modal(job)
    modal_id     = "_historyJobScript#{job[JOB_ID]}"
    job_id_esc   = escape_html(job[JOB_ID].to_s)
    cluster_attr = @cluster_name ? " data-cluster=\"#{escape_html(@cluster_name)}\"" : ""

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable modal-lg">
        <div class="modal-content" style="resize: horizontal; padding-right: 16px;">
          <div class="modal-header">
            <h5>Job Script</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body" data-script-job-id="#{job_id_esc}"#{cluster_attr}>
            <div class="text-center py-3">
              <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">Loading...</span>
              </div>
            </div>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-primary" onclick="ocHistory.loadExtScript(this)">Load parameters</button>
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">Close</button>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a pagination link for history navigation.
  def output_link(is_active, i, rows = 1)
    if is_active
      "<li class=\"page-item active\"><a href=\"#\" class=\"page-link\">#{i}</a></li>\n"
    elsif i == "..."
      "<li class=\"page-item\"><a href=\"#\" class=\"page-link\">...</a></li>\n"
    else
      link = history_path_with_query(p: i, rows: rows)
      "<li class=\"page-item\"><a href=\"#{link}\" class=\"page-link\">#{i}</a></li>\n"
    end
  end

  # Output a pagination component for navigating through pages of history records.
  def output_pagination(current_page, page_size, rows)
    html = "<nav class=\"mt-1\">\n"
    html += "  <ul class=\"pagination justify-content-center\">\n"

    if current_page == 1
      html += "    <li class=\"page-item disabled\"><a href=\"#\" class=\"page-link\">&laquo;</a></li>\n"
    else
      previous_link = history_path_with_query(p: current_page - 1, rows: rows)
      html += "    <li class=\"page-item\"><a href=\"#{previous_link}\" class=\"page-link\">&laquo;</a></li>\n"
    end

    if page_size <= 7
      (1..page_size).each do |i|
        html += output_link(current_page == i, i, rows)
      end
    else
      if current_page <= 4
        (1..5).each { |i| html += output_link(current_page == i, i, rows) }
        html += output_link(false, "...")
        html += output_link(false, page_size, rows)
      elsif current_page >= page_size - 3
        html += output_link(false, 1, rows)
        html += output_link(false, "...")
        ((page_size - 4)..page_size).each { |i| html += output_link(current_page == i, i, rows) }
      else
        html += output_link(false, 1, rows)
        html += output_link(false, "...")
        html += output_link(false, current_page - 1, rows)
        html += output_link(true, current_page, rows)
        html += output_link(false, current_page + 1, rows)
        html += output_link(false, "...")
        html += output_link(false, page_size, rows)
      end
    end

    if current_page == page_size
      html += "   <li class=\"page-item disabled\"><a href=\"#\" class=\"page-link\">&raquo;</a></li>\n"
    else
      next_link = history_path_with_query(p: current_page + 1, rows: rows)
      html += "   <li class=\"page-item\"><a href=\"#{next_link}\" class=\"page-link\">&raquo;</a></li>\n"
    end

    html += "  </ul>\n"
    html += "</nav>\n"
  end

  def history_valid_statuses
    %w[running queued completed cancelled failed unknown]
  end

  def parse_history_statuses(raw_statuses)
    return history_valid_statuses.dup if raw_statuses.nil?
    return [] if raw_statuses == "nothing"

    raw_statuses.to_s.split(/\s+/).map(&:strip).reject(&:empty?).select do |status|
      history_valid_statuses.include?(status)
    end
  end

  def serialize_history_statuses(statuses)
    selected_statuses = Array(statuses).map(&:to_s).select { |status| history_valid_statuses.include?(status) }
    return "nothing" if selected_statuses.empty?
    return nil if selected_statuses.sort == history_valid_statuses.sort

    selected_statuses.join(" ")
  end

  def history_path_with_query(overrides = {})
    values = {
      "statuses"      => @statuses,
      "filter"        => @filter,
      "filter_column" => @filter_column,
      "sort"          => @sort,
      "order"         => @order,
      "date_range"    => @date_range,
      "filter_mode"   => @filter_mode,
      "date_from"     => @date_from,
      "date_to"       => @date_to,
      "detail_open"   => @detail_open,
      "rows"          => @rows,
      "p"             => @current_page,
      "cluster"       => @cluster_name,
    }

    overrides.each { |key, value| values[key.to_s] = value }

    query_params = []
    serialized_statuses = serialize_history_statuses(values["statuses"])
    query_params << ["statuses", serialized_statuses] if serialized_statuses
    query_params << ["filter", values["filter"]] if values["filter"] && !values["filter"].empty?
    query_params << ["filter_column", values["filter_column"]] if values["filter_column"] && values["filter_column"] != "all"
    query_params << ["sort", values["sort"]] if values["sort"] && !values["sort"].empty?
    query_params << ["order", values["order"]] if values["order"] && !values["order"].empty?
    query_params << ["date_range", values["date_range"]] if values["date_range"] && values["date_range"] != "all"
    query_params << ["filter_mode", values["filter_mode"]] if values["filter_mode"] && values["filter_mode"] != "and"
    if values["date_range"] == "custom"
      query_params << ["date_from", values["date_from"]] if values["date_from"] && !values["date_from"].empty?
      query_params << ["date_to", values["date_to"]] if values["date_to"] && !values["date_to"].empty?
    end
    query_params << ["detail_open", "true"] if values["detail_open"] == "true"
    query_params << ["rows", values["rows"]] if values["rows"] && values["rows"].to_i != HISTORY_ROWS
    query_params << ["p", values["p"]] if values["p"] && values["p"].to_i != 1
    query_params << ["cluster", values["cluster"]] if values["cluster"]
    query_params.empty? ? "./history" : "./history?#{URI.encode_www_form(query_params)}"
  end

  def history_filter_terms(filter_text)
    filter_text.to_s.split(/\s+/).reject(&:empty?)
  end

  def parse_history_sort(raw_sort, conf)
    sort = raw_sort.to_s
    return JOB_ID if sort.empty?

    valid_columns = history_sort_column_items(conf).map(&:first)
    valid_columns.include?(sort) ? sort : JOB_ID
  end

  def parse_history_order(raw_order)
    order = raw_order.to_s
    return "desc" if order.empty?

    %w[asc desc].include?(order) ? order : "desc"
  end

  def history_date_range_items
    [
      ["all",      "(ALL)"],
      ["today",    "Today"],
      ["yesterday","Yesterday and Today"],
      ["last7",    "Last 7 days"],
      ["last30",   "Last 30 days"],
      ["custom",   "Custom"]
    ]
  end

  def parse_history_date_range(raw_date_range, raw_date_from, raw_date_to)
    date_range = raw_date_range.to_s
    date_range = "custom" if date_range.empty? && (!raw_date_from.to_s.empty? || !raw_date_to.to_s.empty?)
    date_range = "all" if date_range.empty?
    valid_ranges = history_date_range_items.map(&:first)
    date_range = "all" unless valid_ranges.include?(date_range)

    today = Date.today
    case date_range
    when "today"
      [date_range, today.strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")]
    when "yesterday"
      [date_range, (today - 1).strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")]
    when "last7"
      [date_range, (today - 6).strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")]
    when "last30"
      [date_range, (today - 29).strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")]
    when "custom"
      [date_range, raw_date_from.to_s, raw_date_to.to_s]
    else
      [date_range, "", ""]
    end
  end

  # Return a natural sort key for scheduler-specific job IDs.
  def history_job_id_sort_key(job_id)
    value = job_id.to_s
    case value
    when /\A(\d+)\z/            then [$1.to_i, -1, value]
    when /\A(\d+)[_.](\d+)\z/   then [$1.to_i, $2.to_i, value]
    when /\A(\d+)\[(\d+)\]\z/   then [$1.to_i, $2.to_i, value]
    when /\A(\d+)_\[(\d+)/      then [$1.to_i, $2.to_i, value]
    else                             [Float::INFINITY, Float::INFINITY, value]
    end
  end

  # Build SQL WHERE clauses for the history query, including status, date, and text search.
  def history_sql_where(statuses, date_from, date_to, filter = nil, filter_column = "all", filter_mode = "and")
    clauses = ["_deleted = 0"]
    params  = []

    selected_statuses = Array(statuses).map(&:to_s).filter_map { |s| JOB_STATUS[s] }
    if selected_statuses.empty?
      clauses << "1 = 0"
    else
      active_vals    = [JOB_STATUS["queued"], JOB_STATUS["running"]]
      include_active = selected_statuses.any? { |s| active_vals.include?(s) }
      terminal_vals  = selected_statuses.reject { |s| active_vals.include?(s) }
      conds = []
      if include_active
        active_phs = (["?"] * active_vals.length).join(", ")
        conds << "(_status IS NULL OR _status IN (#{active_phs}))"
        params.concat(active_vals)
      end
      if terminal_vals.any?
        placeholders = (["?"] * terminal_vals.length).join(", ")
        conds << "_status IN (#{placeholders})"
        params.concat(terminal_vals)
      end
      clauses << "(#{conds.join(' OR ')})"
    end

    unless date_from.to_s.empty?
      clauses << "_submission_time >= ?"
      params  << date_from.to_s
    end

    unless date_to.to_s.empty?
      next_day = (Date.parse(date_to.to_s) + 1).strftime("%Y-%m-%d")
      clauses << "_submission_time < ?"
      params  << next_day
    end

    terms = history_filter_terms(filter)
    unless terms.empty?
      search_cols = case filter_column
                    when JOB_APP_NAME          then %w[_app_name]
                    when HEADER_SCRIPT_LOCATION then %w[_script_location]
                    when HEADER_SCRIPT_NAME     then %w[_script_name _script_content]
                    when JOB_NAME              then %w[_job_name]
                    when JOB_ID               then %w[_job_id _job_name _app_name]
                    else                           %w[_job_id _app_name _script_location _script_name _job_name]
                    end

      if filter_mode == "or"
        all_conds = terms.flat_map do |term|
          search_cols.map do |col|
            params << "%#{term.downcase}%"
            "LOWER(COALESCE(#{col},'')) LIKE ?"
          end
        end
        clauses << "(#{all_conds.join(' OR ')})"
      else
        terms.each do |term|
          col_conds = search_cols.map do |col|
            params << "%#{term.downcase}%"
            "LOWER(COALESCE(#{col},'')) LIKE ?"
          end
          clauses << "(#{col_conds.join(' OR ')})"
        end
      end
    end

    [clauses, params]
  rescue ArgumentError, Date::Error
    [clauses, params]
  end

  # Build SQL ORDER BY for the given sort column.
  def history_sql_order(sort, order)
    direction = order == "asc" ? "ASC" : "DESC"

    case sort
    when JOB_ID
      <<~SQL.gsub(/\s+/, " ").strip
        CAST(_job_id AS INTEGER) #{direction},
        CASE
          WHEN instr(_job_id,'_') > 0 THEN CAST(substr(_job_id,instr(_job_id,'_')+1) AS INTEGER)
          ELSE -1
        END #{direction},
        _job_id #{direction}
      SQL
    when JOB_APP_NAME          then "_app_name #{direction}, CAST(_job_id AS INTEGER) #{direction}"
    when HEADER_SCRIPT_LOCATION then "_script_location #{direction}, CAST(_job_id AS INTEGER) #{direction}"
    when HEADER_SCRIPT_NAME    then "_script_name #{direction}, CAST(_job_id AS INTEGER) #{direction}"
    when JOB_NAME              then "_job_name #{direction}, CAST(_job_id AS INTEGER) #{direction}"
    when "Start"               then "_start_time #{direction}, CAST(_job_id AS INTEGER) #{direction}"
    when "End"                 then "_end_time #{direction}, CAST(_job_id AS INTEGER) #{direction}"
    when JOB_STATUS_ID
      status_case = <<~SQL.gsub(/\s+/, " ").strip
        CASE _status
          WHEN '#{JOB_STATUS["queued"]}' THEN 0
          WHEN '#{JOB_STATUS["running"]}' THEN 1
          WHEN '#{JOB_STATUS["completed"]}' THEN 2
          WHEN '#{JOB_STATUS["cancelled"]}' THEN 3
          WHEN '#{JOB_STATUS["failed"]}' THEN 4
          WHEN '#{JOB_STATUS["unknown"]}' THEN 5
          ELSE -1
        END
      SQL
      "#{status_case} #{direction}, CAST(_job_id AS INTEGER) #{direction}"
    else
      "CAST(_job_id AS INTEGER) #{direction}, _job_id #{direction}"
    end
  end

  # Return one page of history rows and the total matching count.
  # All filtering, sorting, and pagination is done in SQL for speed.
  def fetch_history_jobs_page(db, statuses, filter, filter_column, filter_mode, date_from, date_to, sort, order, limit, offset)
    where_clauses, where_params = history_sql_where(statuses, date_from, date_to, filter, filter_column, filter_mode)
    where_sql = "WHERE #{where_clauses.join(' AND ')}"
    order_sql = history_sql_order(sort, order)

    select_sql = <<~SQL
      SELECT
        _job_id           AS "#{JOB_ID}",
        _app_name         AS "#{JOB_APP_NAME}",
        _app_dir_name     AS "#{JOB_DIR_NAME}",
        _script_location  AS "#{HEADER_SCRIPT_LOCATION}",
        _script_name      AS "#{HEADER_SCRIPT_NAME}",
        _submission_time  AS "#{JOB_SUBMISSION_TIME}",
        _status           AS "#{JOB_STATUS_ID}",
        _job_name         AS "#{JOB_NAME}",
        _start_time       AS "Start",
        _end_time         AS "End",
        _script_content   AS "#{OC_SCRIPT_CONTENT}",
        1                 AS "_has_db"
      FROM jobs
      #{where_sql}
      ORDER BY #{order_sql}
      LIMIT ? OFFSET ?
    SQL

    total = db.get_first_value("SELECT COUNT(*) FROM jobs #{where_sql}", where_params).to_i
    rows  = db.execute(select_sql, where_params + [limit, offset])
    [rows, total]
  end

  def history_filter_mode_matches?(search_text, filter_text, filter_mode)
    terms = history_filter_terms(filter_text)
    return true if terms.empty?

    if filter_mode == "or"
      terms.any? { |term| search_text.to_s.include?(term) }
    else
      terms.all? { |term| search_text.to_s.include?(term) }
    end
  end

  def history_filter_hits_text?(text, filter)
    terms = history_filter_terms(filter)
    return false if terms.empty?

    normalized_text = text.to_s.downcase
    terms.any? { |term| normalized_text.include?(term.downcase) }
  end

  def history_filter_column_items(conf)
    [
      ["all",                  "(ALL)"],
      [JOB_ID,                 "Job ID"],
      [JOB_APP_NAME,           "Application"],
      [HEADER_SCRIPT_LOCATION, "Script Location"],
      [HEADER_SCRIPT_NAME,     "Script Name / Job Script"],
      [JOB_NAME,               "Job Name"]
    ]
  end

  def history_sort_column_items(conf)
    [
      [JOB_ID,                 "Job ID"],
      [JOB_APP_NAME,           "Application"],
      [HEADER_SCRIPT_LOCATION, "Script Location"],
      [HEADER_SCRIPT_NAME,     "Script Name"],
      [JOB_NAME,               "Job Name"],
      ["Start",                "Start Time"],
      ["End",                  "End Time"],
      [JOB_STATUS_ID,          "Status"]
    ]
  end

  def parse_history_filter_column(raw_filter_column, conf)
    valid_columns = history_filter_column_items(conf).map(&:first)
    selected_column = raw_filter_column.to_s
    return "all" if selected_column.empty?
    return selected_column if valid_columns.include?(selected_column)

    "all"
  end

  # Return the filter text only when the selected column should be highlighted.
  def history_highlight_filter(filter, filter_column, column_key)
    return filter if filter_column.to_s == "all" || filter_column.to_s == column_key.to_s

    nil
  end

  # Return whether the Job Script modal contains a filter hit.
  def job_script_modal_matches_filter?(job, filter)
    history_filter_hits_text?(job[OC_SCRIPT_CONTENT], filter)
  end

  # Return whether the Job Details modal contains a filter hit.
  # Returns false when JOB_KEYS is absent (lazy-loaded modal content).
  def job_details_modal_matches_filter?(job, filter)
    return false if job[JOB_KEYS].nil?

    filtered_keys = job[JOB_KEYS] - [JOB_NAME, JOB_PARTITION, JOB_STATUS_ID]
    filtered_keys.any? do |key|
      history_filter_hits_text?(key, filter) || history_filter_hits_text?(job[key], filter)
    end
  end

  # Output a styled status badge for a job based on its current status.
  def output_status(job_status)
    badge_class, status_text = case job_status
                               when JOB_STATUS["queued"]    then ["bg-warning text-dark", "Queued"]
                               when JOB_STATUS["running"]   then ["bg-primary", "Running"]
                               when JOB_STATUS["completed"] then ["bg-success", "Completed"]
                               when JOB_STATUS["cancelled"] then ["bg-secondary", "Cancelled"]
                               when JOB_STATUS["failed"]    then ["bg-danger", "Failed"]
                               else                              ["bg-secondary", "Unknown"]
                               end

    "<span class=\"badge fs-6 #{badge_class}\">#{status_text}</span>\n"
  end

  def output_text(text, filter)
    terms = history_filter_terms(filter)

    text = if text.nil? || terms.empty?
             escape_html(text)
           else
             highlighted_text = escape_html(text)
             terms.uniq.sort_by { |term| -term.length }.each do |term|
               highlighted_text = highlighted_text.gsub(/(#{Regexp.escape(term)})/i, '<span class="bg-warning text-dark">\1</span>')
             end
             highlighted_text
           end

    text.gsub("\n", "<br>")
  end

  def format_history_table_value(key, value)
    return value unless key == JOB_SUBMISSION_TIME

    Time.parse(value.to_s).strftime("%Y-%m-%d %H:%M:%S")
  rescue ArgumentError
    value
  end

  # --- DB helpers ---

  def get_history_db(conf, cluster_name)
    db = conf["history_db"]
    return db unless db.is_a?(Hash)

    cluster_db = db[cluster_name]
    halt 500, "#{cluster_name} is invalid." unless cluster_db

    cluster_db
  end

  def get_legacy_history_db(conf, cluster_name)
    if conf.key?("clusters")
      halt 500, "#{cluster_name} is invalid." unless cluster_name
      return File.join(conf["data_dir"], "#{cluster_name}.db")
    end

    File.join(conf["data_dir"], "#{conf["scheduler"]}.db")
  end

  # Open or create the SQLite history DB and ensure the schema is current.
  def open_history_db(conf, cluster_name)
    sqlite_path = get_history_db(conf, cluster_name)
    legacy_path = get_legacy_history_db(conf, cluster_name)
    migrate_pstore_to_sqlite(sqlite_path, legacy_path, conf) if !File.exist?(sqlite_path) && File.exist?(legacy_path)

    db = SQLite3::Database.new(sqlite_path)
    db.results_as_hash = true
    setup_history_db(db)
    db
  end

  # Create the jobs table (new schema) and run any pending migrations.
  def setup_history_db(db)
    db.execute_batch(<<~SQL)
      CREATE TABLE IF NOT EXISTS jobs (
        _job_id          TEXT PRIMARY KEY,
        _app_name        TEXT,
        _app_dir_name    TEXT,
        _script_location TEXT,
        _script_name     TEXT,
        _submission_time TEXT,
        _status          TEXT,
        _job_name        TEXT,
        _start_time      TEXT,
        _end_time        TEXT,
        _script_content  TEXT,
        _deleted         INTEGER NOT NULL DEFAULT 0
      );
    SQL

    migrate_history_db_to_v2(db)

    db.execute_batch(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(_status);
      CREATE INDEX IF NOT EXISTS idx_jobs_submission_time ON jobs(_submission_time);
      CREATE INDEX IF NOT EXISTS idx_jobs_deleted ON jobs(_deleted);
    SQL
  end

  # Migrate from the old schema (with payload_json) to the new flat schema.
  # Runs once per DB; subsequent calls are no-ops.
  def migrate_history_db_to_v2(db)
    cols = db.table_info("jobs").map { |c| c["name"] }
    return if cols.include?("_deleted")

    # Rename legacy column names if needed (very old databases)
    migrate_history_db_internal_columns(db)

    db.transaction do
      db.execute_batch(<<~SQL)
        CREATE TABLE jobs_v2 (
          _job_id          TEXT PRIMARY KEY,
          _app_name        TEXT,
          _app_dir_name    TEXT,
          _script_location TEXT,
          _script_name     TEXT,
          _submission_time TEXT,
          _status          TEXT,
          _job_name        TEXT,
          _start_time      TEXT,
          _end_time        TEXT,
          _script_content  TEXT,
          _deleted         INTEGER NOT NULL DEFAULT 0
        );
      SQL

      db.execute("SELECT * FROM jobs").each do |row|
        payload = begin
          JSON.parse(row["payload_json"] || "{}")
        rescue StandardError
          {}
        end

        script_content = payload[OC_SCRIPT_CONTENT] || payload["_script_content"]
        job_name       = row["_job_name"].to_s.empty? ? payload[JOB_NAME] : row["_job_name"]

        db.execute(
          "INSERT OR IGNORE INTO jobs_v2 (_job_id, _app_name, _app_dir_name, _script_location, _script_name, _submission_time, _status, _job_name, _script_content, _deleted) VALUES (?,?,?,?,?,?,?,?,?,0)",
          [row["_job_id"], row["_app_name"], row["_app_dir_name"],
           row["_script_location"], row["_script_name"],
           row["_submission_time"], row["_status"],
           job_name.to_s.empty? ? nil : job_name,
           script_content]
        )
      end

      # Bring in deleted_generic_jobs as tombstone entries so they stay hidden
      begin
        db.execute("SELECT _job_id FROM deleted_generic_jobs").each do |row|
          db.execute(
            "INSERT OR IGNORE INTO jobs_v2 (_job_id, _deleted) VALUES (?, 1)",
            [row["_job_id"]]
          )
        end
      rescue SQLite3::Exception
        # deleted_generic_jobs may not exist — that's fine
      end

      db.execute("DROP TABLE jobs")
      db.execute("ALTER TABLE jobs_v2 RENAME TO jobs")
    end
  end

  # Rename legacy (non-prefixed) column names to the _-prefixed convention.
  def migrate_history_db_internal_columns(db)
    columns = db.table_info("jobs").map { |c| c["name"] }
    legacy_to_internal = {
      "job_id"         => "_job_id",
      "app_name"       => "_app_name",
      "app_dir_name"   => "_app_dir_name",
      "script_location"=> "_script_location",
      "script_name"    => "_script_name",
      "job_name"       => "_job_name",
      "partition"      => "_partition",
      "submission_time"=> "_submission_time",
      "updated_time"   => "_updated_time",
      "status"         => "_status"
    }

    legacy_to_internal.each do |legacy, internal|
      next unless columns.include?(legacy)
      next if columns.include?(internal)

      db.execute("ALTER TABLE jobs RENAME COLUMN #{legacy} TO #{internal}")
      columns[columns.index(legacy)] = internal
    end
  end

  # Return one job record by ID.
  def find_job(db, job_id)
    db.get_first_row("SELECT * FROM jobs WHERE _job_id = ?", [job_id])
  end

  # Sync sacct job data into the DB.
  # New jobs are inserted with sacct data only (no OC metadata).
  # Existing jobs get status/name/times updated; OC metadata (app_name, app_dir_name,
  # script_location, script_name, script_content) is never overwritten by sacct data.
  def upsert_sacct_jobs(db, sacct_jobs)
    return if sacct_jobs.nil? || sacct_jobs.empty?
    db.transaction do
      sacct_jobs.each do |job|
        job_id = job["JobID"].to_s.strip
        next unless valid_oc_job_id?(job_id)
        oc_status   = sacct_state_to_oc_status(job["State"].to_s)
        job_name    = job["JobName"].to_s.strip; job_name = nil if job_name.empty?
        submit_str  = job["Submit"].to_s.strip
        submit_str  = nil if submit_str.empty? || submit_str == "Unknown" || submit_str == "None"
        submit_time = normalize_time_for_db(submit_str)
        start_time  = job["Start"].to_s.strip
        start_time  = nil if start_time.empty? || start_time == "Unknown" || start_time == "None"
        end_time    = job["End"].to_s.strip
        end_time    = nil if end_time.empty? || end_time == "Unknown" || end_time == "None"
        params = [
          job_id, oc_status, job_name, submit_time, start_time, end_time,
          oc_status,
          job_name, job_name,
          submit_time,
          start_time, start_time,
          end_time, end_time
        ]
        db.execute(<<~SQL, params)
          INSERT INTO jobs (_job_id, _status, _job_name, _submission_time, _start_time, _end_time, _deleted)
          VALUES (?, ?, ?, ?, ?, ?, 0)
          ON CONFLICT(_job_id) DO UPDATE SET
            _status          = ?,
            _job_name        = CASE WHEN ? IS NOT NULL THEN ? ELSE _job_name END,
            _submission_time = CASE WHEN _submission_time IS NULL THEN ? ELSE _submission_time END,
            _start_time      = CASE WHEN ? IS NOT NULL THEN ? ELSE _start_time END,
            _end_time        = CASE WHEN ? IS NOT NULL THEN ? ELSE _end_time END
        SQL
      end
    end
  end

  # Insert or overwrite a job record.
  def upsert_job(db, record)
    params = [
      record["_job_id"],
      record["_app_name"],
      record["_app_dir_name"],
      record["_script_location"],
      record["_script_name"],
      record["_submission_time"],
      record["_status"],
      record["_job_name"],
      record["_start_time"],
      record["_end_time"],
      record["_script_content"],
      record.fetch("_deleted", 0).to_i
    ]
    db.execute(<<~SQL, params)
      INSERT INTO jobs (_job_id, _app_name, _app_dir_name, _script_location, _script_name,
                        _submission_time, _status, _job_name, _start_time, _end_time,
                        _script_content, _deleted)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(_job_id) DO UPDATE SET
        _app_name        = excluded._app_name,
        _app_dir_name    = excluded._app_dir_name,
        _script_location = excluded._script_location,
        _script_name     = excluded._script_name,
        _submission_time = excluded._submission_time,
        _status          = excluded._status,
        _job_name        = excluded._job_name,
        _start_time      = excluded._start_time,
        _end_time        = excluded._end_time,
        _script_content  = excluded._script_content,
        _deleted         = excluded._deleted
    SQL
  end

  # Mark every non-deleted job as deleted, clearing all data.
  def delete_all_jobs(db)
    db.execute(<<~SQL)
      UPDATE jobs SET
        _app_name=NULL, _app_dir_name=NULL, _script_location=NULL,
        _script_name=NULL, _submission_time=NULL, _status=NULL,
        _job_name=NULL, _start_time=NULL, _end_time=NULL,
        _script_content=NULL, _deleted=1
      WHERE _deleted=0
    SQL
  end

  # Mark a job as deleted, clearing all data except the job ID.
  def delete_job(db, job_id)
    db.execute(<<~SQL, [job_id])
      UPDATE jobs SET
        _app_name = NULL, _app_dir_name = NULL, _script_location = NULL,
        _script_name = NULL, _submission_time = NULL, _status = NULL,
        _job_name = NULL, _start_time = NULL, _end_time = NULL,
        _script_content = NULL, _deleted = 1
      WHERE _job_id = ?
    SQL
  end

  # Convert a DB row to a hash keyed by the legacy/public constants.
  # Returns nil for deleted records.
  def job_record_to_legacy_hash(record)
    return nil unless record
    return nil if record["_deleted"].to_i == 1

    {
      JOB_ID              => record["_job_id"],
      JOB_APP_NAME        => record["_app_name"],
      JOB_DIR_NAME        => record["_app_dir_name"],
      HEADER_SCRIPT_LOCATION => record["_script_location"],
      HEADER_SCRIPT_NAME  => record["_script_name"],
      JOB_SUBMISSION_TIME => record["_submission_time"],
      JOB_STATUS_ID       => record["_status"],
      JOB_NAME            => record["_job_name"],
      OC_SCRIPT_CONTENT   => record["_script_content"],
      "Start"             => record["_start_time"],
      "End"               => record["_end_time"]
    }
  end

  # Return the IDs of all non-terminal jobs (QUEUED, RUNNING, or NULL for just-submitted).
  def get_nonterminal_job_ids(db)
    active = [JOB_STATUS["queued"], JOB_STATUS["running"]]
    placeholders = (["?"] * active.length).join(", ")
    db.execute(
      "SELECT _job_id FROM jobs WHERE _deleted = 0 AND (_status IS NULL OR _status IN (#{placeholders}))",
      active
    ).map { |row| row["_job_id"] }
  end

  # Bulk-update job statuses in the DB from sacct results.
  def sync_job_statuses(db, sacct_results)
    return if sacct_results.nil? || sacct_results.empty?

    db.transaction do
      sacct_results.each do |job_id, sacct_job|
        oc_status  = sacct_state_to_oc_status(sacct_job["State"].to_s)
        job_name   = sacct_job["JobName"].to_s
        job_name   = nil if job_name.empty?
        start_time = sacct_job["Start"].to_s
        start_time = nil if start_time.empty? || start_time == "Unknown" || start_time == "None"
        end_time   = sacct_job["End"].to_s
        end_time   = nil if end_time.empty? || end_time == "Unknown" || end_time == "None"

        db.execute(<<~SQL, [oc_status, job_name, job_name, start_time, start_time, end_time, end_time, job_id])
          UPDATE jobs SET
            _status     = ?,
            _job_name   = CASE WHEN ? IS NOT NULL THEN ? ELSE _job_name END,
            _start_time = CASE WHEN ? IS NOT NULL THEN ? ELSE _start_time END,
            _end_time   = CASE WHEN ? IS NOT NULL THEN ? ELSE _end_time END
          WHERE _job_id = ? AND _deleted = 0
        SQL
      end
    end
  end

  # Return true if a job ID has a valid format for recording: plain integer or integer_integer.
  def valid_oc_job_id?(job_id)
    job_id.to_s.match?(/\A\d+\z/) || job_id.to_s.match?(/\A\d+_\d+\z/)
  end

  # Set the status of jobs to cancelled in the DB.
  def mark_jobs_as_canceled(db, job_ids)
    Array(job_ids).each do |job_id|
      db.execute(
        "UPDATE jobs SET _status = ? WHERE _job_id = ? AND _deleted = 0",
        [JOB_STATUS["cancelled"], job_id]
      )
    end
  end

  # Map a sacct State string to an OpenComposer status constant.
  def sacct_state_to_oc_status(state)
    s = state.to_s
    return JOB_STATUS["cancelled"] if s.start_with?("CANCELLED")

    case s
    when "COMPLETED"
      JOB_STATUS["completed"]
    when "CONFIGURING", "REQUEUED", "RESIZING", "PENDING", "PREEMPTED", "SUSPENDED"
      JOB_STATUS["queued"]
    when "COMPLETING", "RUNNING"
      JOB_STATUS["running"]
    when "STOPPED"
      JOB_STATUS["cancelled"]
    when "BOOT_FAIL", "DEADLINE", "FAILED", "NODE_FAIL", "OUT_OF_MEMORY",
         "REVOKED", "SPECIAL_EXIT", "TIMEOUT"
      JOB_STATUS["failed"]
    else
      JOB_STATUS["unknown"]
    end
  end

  # Normalize a time string into ISO 8601 using the local timezone.
  def normalize_time_for_db(value)
    return nil if value.nil?

    string = value.to_s.strip
    return nil if string.empty?

    Time.parse(string).iso8601
  rescue ArgumentError
    nil
  end

  # Migrate a legacy PStore DB to SQLite (runs only when the SQLite file is absent).
  def migrate_pstore_to_sqlite(sqlite_path, legacy_path, conf)
    FileUtils.mkdir_p(File.dirname(sqlite_path))

    db = SQLite3::Database.new(sqlite_path)
    db.results_as_hash = true
    setup_history_db(db)

    begin
      db.transaction
      store = PStore.new(legacy_path)
      store.transaction(true) do
        store.roots.each do |job_id|
          data = store[job_id]
          next unless data

          upsert_job(db, convert_pstore_record_to_sqlite(job_id.to_s, data))
        end
      end
      db.commit
    rescue StandardError
      db.rollback
      db.close if db
      File.delete(sqlite_path) if File.exist?(sqlite_path)
      raise
    end

    db.close
  end

  # Convert a legacy PStore record into a new-schema job record.
  def convert_pstore_record_to_sqlite(job_id, data)
    legacy = (data || {}).transform_keys(&:to_s)

    {
      "_job_id"          => job_id,
      "_app_name"        => legacy[JOB_APP_NAME.to_s],
      "_app_dir_name"    => legacy[JOB_DIR_NAME.to_s],
      "_script_location" => legacy[HEADER_SCRIPT_LOCATION.to_s],
      "_script_name"     => legacy[HEADER_SCRIPT_NAME.to_s],
      "_submission_time" => normalize_time_for_db(legacy[JOB_SUBMISSION_TIME.to_s]),
      "_status"          => legacy[JOB_STATUS_ID.to_s],
      "_script_content"  => legacy[OC_SCRIPT_CONTENT.to_s],
      "_deleted"         => 0
    }
  end
end
