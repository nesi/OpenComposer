# coding: utf-8
require 'open3'
require 'date'

class Slurm < Scheduler
  SLURM_ENV = "SLURM_TIME_FORMAT=standard"
  # Submit a job to the Slurm scheduler using the 'sbatch' command.
  # If the submission is successful, it checks for job details using the 'scontrol' command.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    sbatch = get_command_path("sbatch", bin, bin_overrides)
    job_name_option = "-J #{job_name}" if job_name && !job_name.empty?
    added_options = "--export=NONE" if added_options.nil?
    command = [ssh_wrapper, sbatch, job_name_option, added_options, script_path].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ") unless status.success?
    job_id_match = stdout.match(/Submitted batch job (\d+)/)
    return nil, "Job ID not found in output." unless job_id_match

    job_id = job_id_match[1]

    # Fetch job details
    scontrol = get_command_path("scontrol", bin, bin_overrides)
    command = [ssh_wrapper, scontrol, "show job", job_id].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ") unless status.success?

    unless stdout.include?("ArrayTaskId") # Single Job
      return job_id, nil
    else
      # Extract and expand array job IDs.
      # ArrayTaskId can be "1-100", "1-1000:40", "1-1000:40%2" (% = concurrency limit), or "1,5,10".
      expanded_ids = stdout.scan(/ArrayTaskId=(\S+)/).flatten.flat_map do |spec|
        spec.split('%').first.split(',').flat_map do |part|
          if part.include?('-')
            range_part, step_part = part.split(':', 2)
            start_val, end_val = range_part.split('-', 2).map(&:to_i)
            step = step_part ? [step_part.to_i, 1].max : 1
            start_val.step(end_val, step).to_a
          else
            [part.to_i]
          end
        end
      end.sort
      return expanded_ids.map { |i| "#{job_id}_#{i}" }, nil # Array Job
    end
  rescue Exception => e
    return nil, e.message
  end

  # Cancel one or more jobs in the Slurm scheduler using the 'scancel' command.
  # Range IDs like "6801262_[1494-2000]" are passed directly to scancel, which
  # understands Slurm's native bracket notation.
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    scancel = get_command_path("scancel", bin, bin_overrides)
    errors  = []
    jobs.each do |id|
      command = [ssh_wrapper, scancel, id].compact.join(" ")
      stdout, stderr, status = Open3.capture3(command)
      errors << [stdout, stderr].join(" ").strip unless status.success?
    end
    errors.empty? ? nil : errors.join("; ")
  rescue Exception => e
    return e.message
  end

  # Query the status of one or more jobs in the Slurm system using 'sacct'.
  # It retrieves job details such as submission time, partition, and status.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    # https://slurm.schedmd.com/sacct.html
    # BOOT_FAIL     : Job terminated due to launch failure, typically due to a hardware failure.
    # CANCELLED     : Job was explicitly cancelled by the user or system administrator. The job may or may not have been initiated.
    # COMPLETED     : Job has terminated all processes on all nodes with an exit code of zero.
    # DEADLINE      : Job terminated on deadline.
    # FAILED        : Job terminated with non-zero exit code or other failure condition.
    # NODE_FAIL     : Job terminated due to failure of one or more allocated nodes.
    # OUT_OF_MEMORY : Job experienced out of memory error.
    # PENDING       : Job is awaiting resource allocation.
    # PREEMPTED     : Job terminated due to preemption.
    # RUNNING       : Job currently has an allocation.
    # REQUEUED      : Job was requeued.
    # RESIZING      : Job is about to change size.
    # REVOKED       : Sibling was removed from cluster due to other cluster starting the job.
    # SUSPENDED     : Job has an allocation, but execution has been suspended and CPUs have been released for other jobs.
    # TIMEOUT       : Job terminated upon reaching its time limit.
    #
    # The categorization was determined based on the table above and the codes below.
    #  - https://github.com/OSC/ood_core/blob/master/lib/ood_core/job/adapters/slurm.rb

    # Get the list of all available fields from sacct
    sacct = get_command_path("sacct", bin, bin_overrides)
    command1 = [ssh_wrapper, SLURM_ENV, sacct, "--helpformat"].compact.join(" ")
    stdout1, stderr1, status1 = Open3.capture3(command1)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?

    # Run sacct with all fields, using --parsable2 for clean pipe-separated output
    command2 = [ssh_wrapper, SLURM_ENV, sacct, "--format=#{stdout1.split.join(",")} --parsable2 -j", jobs.join(",")].compact.join(" ")
    stdout2, stderr2, status2 = Open3.capture3(command2)
    return nil, [stdout2, stderr2].join(" ") unless status2.success?

    lines = stdout2.lines.map(&:chomp)
    header = lines.shift.split('|')
    info = {}
    lines.each do |line|
      job_fields = line.split('|')
      id = job_fields[header.index("JobID")]
      next if id.end_with?(".batch", ".extern")

      # Add necessary fields
      if job_fields.size != stdout1.split.size
      # Some information may not be obtained when `sacct` command runs immediately after submitting a job.
        info[id] = {
          JOB_NAME      => nil,
          JOB_PARTITION => nil,
          JOB_STATUS_ID => nil
        }
      else
        job_state = job_fields[header.index("State")]
        info[id] = {
          JOB_NAME      => job_fields[header.index("JobName")],
          JOB_PARTITION => job_fields[header.index("Partition")],
          JOB_STATUS_ID =>
          # When a job is canceled, the output is "CANCELLED by 1025".
          if job_state.start_with?("CANCELLED")
            JOB_STATUS["cancelled"]
          else
            case job_state
            when "COMPLETED"
              JOB_STATUS["completed"]
            when "CONFIGURING", "REQUEUED", "RESIZING", "PENDING", "PREEMPTED", "SUSPENDED"
              JOB_STATUS["queued"]
            when "COMPLETING", "RUNNING"
              JOB_STATUS["running"]
            when "STOPPED"
              JOB_STATUS["cancelled"]
            when "BOOT_FAIL", "DEADLINE", "FAILED", "NODE_FAIL", "OUT_OF_MEMORY", "REVOKED", "SPECIAL_EXIT", "TIMEOUT"
              JOB_STATUS["failed"]
            else
              nil
            end
          end
        }
      end

      # Add other fields
      header.each_with_index do |field, idx|
        value = job_fields[idx]
        next if value.nil? || value.strip.empty?
        info[id][field] = value
      end
    end

    return info, nil
  rescue Exception => e
    return nil, e.message
  end

  # Run scontrol show job for one job ID and parse the key=value output.
  # Returns [hash, nil, command] on success, [nil, nil, nil] when the job is not found,
  # or [nil, error_message, command] on failure.
  def scontrol_job(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    scontrol = get_command_path("scontrol", bin, bin_overrides)
    command  = [ssh_wrapper, scontrol, "show job", job_id].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    parsed = {}
    stdout.split.each do |token|
      idx = token.index('=')
      next unless idx && idx > 0
      key   = token[0...idx]
      value = token[idx + 1..]
      parsed[key] = value unless key.empty?
    end
    parsed.empty? ? [nil, nil, command] : [parsed, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch all available sacct fields for a single job (for the Job Details modal).
  # Uses -X so only the top-level allocation row is returned (no step sub-rows).
  # Key fields are placed first in the format string so they are always in the
  # earliest columns and unaffected if a later field's value contains a pipe character.
  # Returns [hash, nil, command] on success or [nil, error_message, command] on failure.
  def sacct_job(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)

    help_cmd = [ssh_wrapper, sacct, "--helpformat"].compact.join(" ")
    help_out, help_err, help_status = Open3.capture3(help_cmd)
    return nil, "sacct --helpformat failed: #{[help_out, help_err].join(' ').strip}", nil unless help_status.success?

    # Exclude fields whose values may contain pipe characters and corrupt the row
    unsafe = %w[SubmitLine AdminComment SystemComment Comment Extra Container]
    all_fields = help_out.split.reject { |f| unsafe.include?(f) }
    return nil, "sacct --helpformat returned no fields", nil if all_fields.empty?

    # Put key fields first so they are always in the earliest columns (unaffected
    # by any pipe character appearing in a later field's value)
    priority = %w[WorkDir JobID JobIDRaw JobName State Partition Account User
                  NodeList AllocCPUS AllocTRES ReqMem Start End Submit Elapsed ExitCode]
    fields = priority.select { |f| all_fields.include?(f) } +
             all_fields.reject { |f| priority.include?(f) }

    command = [ssh_wrapper, SLURM_ENV, sacct, "-j", job_id, "-X",
               "--format=#{fields.join(',')}", "--parsable2"].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    lines = stdout.lines.map(&:chomp).reject(&:empty?)
    return nil, nil, command if lines.size < 2

    header   = lines[0].split('|')
    data_row = lines[1]
    return nil, nil, command unless data_row

    result = {}
    data_row.split('|').each_with_index do |value, idx|
      key = header[idx]
      next unless key
      result[key] = value
    end
    result.empty? ? [nil, nil, command] : [result, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch all jobs for the current user within a date range via sacct.
  # Uses a fixed safe set of fields (no free-text fields that could contain pipe characters).
  # Defaults to the last 7 days when no dates are supplied.
  # Returns [jobs_array, nil, command] or [nil, error_message, command].
  def valid_job_id?(id)
    id.to_s.match?(/\A\d+\z/) || id.to_s.match?(/\A\d+_\d+\z/) || id.to_s.match?(/\A\d+_\[/)
  end

  def state_to_oc_status(state)
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

  def sacct_all_jobs(date_from, date_to, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)

    fields = %w[JobID JobName Partition State Submit Start End Elapsed
                WorkDir Account AllocCPUS ReqMem ExitCode]

    effective_from = date_from.to_s.empty? ? (Date.today - 6).strftime("%Y-%m-%d") : date_from.to_s
    effective_to   = date_to.to_s.empty?   ? Date.today.strftime("%Y-%m-%d")       : date_to.to_s

    command = [ssh_wrapper, SLURM_ENV, sacct, "-X", "--parsable2",
               "--format=#{fields.join(',')}",
               "--starttime=#{effective_from}",
               "--endtime=#{effective_to}T23:59:59"].compact.join(" ")

    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    lines = stdout.lines.map(&:chomp).reject(&:empty?)
    return [], nil, command if lines.size < 2

    header = lines[0].split('|')
    jobs = []
    lines[1..].each do |line|
      row = {}
      line.split('|').each_with_index do |value, idx|
        key = header[idx]
        next unless key
        row[key] = value
      end
      jobs << row unless row.empty?
    end

    [jobs, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch estimated start times for a list of pending jobs via squeue --start.
  # Returns a hash of job_id => start_time_string for jobs that have an estimate.
  # N/A and blank values are excluded so callers can treat missing keys as unknown.
  def squeue_start_times(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    return [{}, nil] if job_ids.empty?

    squeue  = get_command_path("squeue", bin, bin_overrides)
    command = [ssh_wrapper, SLURM_ENV, squeue, "--start", "--noheader", "--parsable2",
               "--Format=jobid,starttime", "-j", job_ids.join(",")].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return [{}, [stdout, stderr].join(" ")] unless status.success?

    result = {}
    stdout.lines.each do |line|
      parts = line.chomp.split("|")
      next if parts.size < 2
      job_id     = parts[0].strip
      start_time = parts[1].strip
      next if start_time.empty? || start_time.upcase == "N/A"
      # Normalize to ISO 8601 if squeue didn't honour SLURM_TIME_FORMAT=standard
      # (e.g. NeSI squeue returns "Jun 01 15:15" by default)
      unless start_time =~ /\A\d{4}-\d{2}-\d{2}T/
        begin
          time_str = start_time =~ /\d{4}/ ? start_time : "#{Date.today.year} #{start_time}"
          start_time = DateTime.parse(time_str.gsub(/\s+/, ' ')).strftime("%Y-%m-%dT%H:%M:%S")
        rescue ArgumentError, TypeError, Date::Error
          # keep as-is if we cannot parse the string
        end
      end
      result[job_id] = start_time
    end
    [result, nil]
  rescue Exception => e
    [{}, e.message]
  end

  # Fetch node info via sinfo -N with fixed-width columns.
  # Deduplicates by node name (a node appears once per partition in -N output).
  def sinfo_nodes(bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    sinfo   = get_command_path("sinfo", bin, bin_overrides)
    fmt     = "nodelist:10,StateLong:15,cpusState:20,Memory:15,FreeMem:15,Gres:30,GresUsed:30"
    command = [ssh_wrapper, sinfo, "-N", "--Format=#{fmt}"].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    lines  = stdout.lines.map { |l| l.chomp }
    return [], nil, command if lines.size < 2

    widths = [10, 15, 20, 15, 15, 30, 30]
    seen   = {}
    nodes  = []

    lines[1..].each do |line|
      next if line.strip.empty?
      pos  = 0
      cols = widths.map { |w| v = line[pos, w].to_s.strip; pos += w; v }
      node_name = cols[0]
      next if node_name.empty? || seen.key?(node_name)
      seen[node_name] = true
      nodes << cols
    end

    [nodes, nil, command]
  rescue => e
    return nil, e.message, nil
  end

  # Fetch the batch script for a job via sacct --batch-script (-B).
  # Returns [script_content, nil] or [nil, nil] when not available.
  def batch_script(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)
    command = [ssh_wrapper, SLURM_ENV, sacct, "-j", job_id, "-B"].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, nil unless status.success?

    lines = stdout.lines
    return nil, nil unless lines.size >= 2 && lines[0].start_with?("Batch Script for")

    content = lines.drop(2).join
    content.strip.empty? ? [nil, nil] : [content, nil]
  rescue Exception => e
    return nil, e.message
  end

  # Query the current status of specific job IDs via sacct (batched in groups of 100).
  # Returns [hash_of_job_id_to_row, error_or_nil].
  def sacct_status_update(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    return {}, nil if job_ids.empty?

    sacct  = get_command_path("sacct", bin, bin_overrides)
    result = {}
    last_error = nil

    job_ids.each_slice(100) do |batch|
      command = [ssh_wrapper, SLURM_ENV, sacct, "-X", "--parsable2",
                 "--format=JobID,JobName,State,Start,End",
                 "-j", batch.join(",")].compact.join(" ")
      stdout, stderr, status = Open3.capture3(command)
      unless status.success?
        last_error = [stdout, stderr].join(" ").strip
        next
      end

      lines = stdout.lines.map(&:chomp).reject(&:empty?)
      next if lines.size < 2

      header = lines[0].split('|')
      lines[1..].each do |line|
        row = {}
        line.split('|').each_with_index { |v, i| row[header[i]] = v if header[i] }
        next if row.empty?
        jid = row["JobID"].to_s.strip
        next if jid.empty? || jid.end_with?(".batch", ".extern")
        result[jid] = row
      end
    end

    [result, last_error]
  rescue Exception => e
    [{}, e.message]
  end

  # Compute seff-style efficiency metrics using sacct --json.
  def efficiency(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)
    cmd   = [ssh_wrapper, sacct, "--json -j", job_id].compact.join(" ")
    out, err, st = Open3.capture3(cmd)
    return [nil, [out, err].join(" ")] unless st.success?

    data      = JSON.parse(out)
    jobs_list = data["jobs"] || []
    return [nil, "Job not found."] if jobs_list.empty?

    job   = jobs_list.first
    state = Array(job.dig("state", "current")).join(" ")
    ncpus = ex_tres_eff(job.dig("tres", "allocated") || [], "cpu", 0).to_i

    if state.include?("RUNNING") || ncpus == 0 || ncpus >= 0xfffffff
      return [{ "status" => "not_available", "state" => state }, nil]
    end

    ncores       = (ncpus + 1) / 2
    walltime     = job.dig("time", "elapsed").to_i
    timelimit    = job.dig("time", "limit", "number").to_i * 60
    reqmem_kb    = ex_tres_eff(job.dig("tres", "allocated") || [], "mem", 0).to_f * 1024

    tot_cpu_msec    = 0.0
    mem_kb          = 0.0
    best_step_total = []
    (job["steps"] || []).each do |step|
      total         = step.dig("tres", "requested", "total") || []
      tot_cpu_msec += ex_tres_eff(total, "cpu", 0).to_f
      lmem          = ex_tres_eff(total, "mem", 0).to_f / 1024
      if lmem > mem_kb
        mem_kb          = lmem
        best_step_total = total
      end
    end

    corewalltime = walltime * ncores
    cpu_eff  = corewalltime > 0 ? (tot_cpu_msec / 1000.0 / corewalltime * 100).round(1) : 0.0
    mem_eff  = reqmem_kb    > 0 ? (mem_kb / reqmem_kb * 100).round(1)                    : 0.0
    wall_eff = timelimit    > 0 ? (walltime.to_f / timelimit * 100).round(1)              : 0.0

    result = {
      "status"    => "available",
      "state"     => state,
      "command"   => cmd,
      "cluster"   => job["cluster"].to_s,
      "cores"     => ncores.to_s,
      "nodes"     => job["allocation_nodes"].to_s,
      "Wall Time" => format("%.1f%%  %s of %s",              wall_eff, time2str_eff(walltime),                       time2str_eff(timelimit)),
      "CPU"       => format("%.1f%%  %s of %s core-walltime", cpu_eff, time2str_eff((tot_cpu_msec / 1000).to_i), time2str_eff(corewalltime)),
      "Memory"    => format("%.1f%%  %s of %s",              mem_eff,  kbytes2str_eff(mem_kb),                      kbytes2str_eff(reqmem_kb)),
    }

    # GPU metrics come from the step with the highest memory usage, not the job-level TRES.
    gpu_util = ex_tres_eff(best_step_total, "gpuutil")
    gpu_mem  = ex_tres_eff(best_step_total, "gpumem") # bytes

    result["GPU Utilisation"] = format("%.0f%%", gpu_util) if gpu_util

    if gpu_mem
      a100_gb   = job["partition"] == "genoa" ? 40 : 80
      allocated = job.dig("tres", "allocated") || []
      alloc_gb  = [["l4", 23], ["a100", a100_gb], ["h100", 94]].sum do |kind, mem_gb|
        ex_tres_eff(allocated, "gpu:#{kind}", 0).to_i * mem_gb
      end
      gpu_mem_kb = gpu_mem.to_f / 1024
      if alloc_gb > 0
        gpu_mem_eff = (gpu_mem.to_f / (alloc_gb * (1024.0**3)) * 100).round(1)
        result["GPU Memory"] = format("%.1f%%  %s of %d GB", gpu_mem_eff, kbytes2str_eff(gpu_mem_kb), alloc_gb)
      else
        result["GPU Memory"] = kbytes2str_eff(gpu_mem_kb)
      end
    end

    [result, nil]
  rescue JSON::ParserError => e
    [nil, "sacct --json not supported: #{e.message}"]
  rescue Exception => e
    [nil, e.message]
  end

  def ex_tres_eff(tres_array, name, default = nil, field = "count")
    map = tres_array.each_with_object({}) do |m, h|
      key = m["type"] == "gres" ? m["name"] : m["type"]
      h[key] = m[field]
    end
    map.fetch(name, default)
  end

  def time2str_eff(seconds)
    seconds = seconds.to_i
    minutes, seconds = seconds.divmod(60)
    hours,   minutes = minutes.divmod(60)
    days,    hours   = hours.divmod(24)
    prefix = days > 0 ? "#{days}-" : ""
    prefix + format("%02d:%02d:%02d", hours, minutes, seconds)
  end

  def kbytes2str_eff(kbytes)
    kbytes = kbytes.to_f
    return "0.00 MB" if kbytes == 0
    units = %w[kB MB GB TB PB EB]
    exp   = [Math.log(kbytes.abs) / Math.log(1024), units.size - 1].min.to_i
    format("%.2f %s", kbytes / (1024.0**exp), units[exp])
  end

  private

  # Expand a bracket-range job ID into individual task IDs.
  # "6801262_[1494-2000]"   → ["6801262_1494", ..., "6801262_2000"]
  # "6801262_[1494-2000:2]" → ["6801262_1494", "6801262_1496", ..., "6801262_2000"]
  # Any other string is returned unchanged inside a one-element array.
  def expand_array_range(job_id)
    m = job_id.to_s.match(/\A(\d+)_\[(\d+)-(\d+)(?::(\d+))?\]\z/)
    return [job_id] unless m
    parent = m[1]
    first  = m[2].to_i
    last   = m[3].to_i
    step   = m[4] ? [m[4].to_i, 1].max : 1
    first.step(last, step).map { |i| "#{parent}_#{i}" }
  end
end
