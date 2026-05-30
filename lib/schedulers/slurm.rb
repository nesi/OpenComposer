# coding: utf-8
require 'open3'

class Slurm < Scheduler
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
      # Extract and expand array job IDs
      expanded_ids = stdout.scan(/ArrayTaskId=(\S+)/).flatten.flat_map do |part|
        part.include?('-') ? Range.new(*part.split('-').map(&:to_i)).to_a : [part.to_i]
      end.sort
      return expanded_ids.map { |i| "#{job_id}_#{i}" }, nil # Array Job
    end
  rescue Exception => e
    return nil, e.message
  end

  # Cancel one or more jobs in the Slurm scheduler using the 'scancel' command.
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    scancel = get_command_path("scancel", bin, bin_overrides)
    command = [ssh_wrapper, scancel, jobs.join(',')].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return status.success? ? nil : [stdout, stderr].join(" ")
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
    command1 = [ssh_wrapper, sacct, "--helpformat"].compact.join(" ")
    stdout1, stderr1, status1 = Open3.capture3(command1)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?

    # Run sacct with all fields, using --parsable2 for clean pipe-separated output
    command2 = [ssh_wrapper, sacct, "--format=#{stdout1.split.join(",")} --parsable2 -j", jobs.join(",")].compact.join(" ")
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
            JOB_STATUS["completed"]
          else
            case job_state
            when "CANCELLED", "COMPLETED"
              JOB_STATUS["completed"]
            when "CONFIGURING", "REQUEUED", "RESIZING", "PENDING", "PREEMPTED", "SUSPENDED"
              JOB_STATUS["queued"]
            when "COMPLETING", "RUNNING", "STOPPED"
              JOB_STATUS["running"]
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

  # Run scontrol show job --yaml for one job ID and return a flattened hash.
  # Returns [hash, nil] on success, [nil, nil] when the job is not found,
  # or [nil, error_message] on failure.
  def scontrol_job(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    require 'yaml'
    scontrol = get_command_path("scontrol", bin, bin_overrides)
    command = [ssh_wrapper, scontrol, "show job", job_id, "--yaml"].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ").strip unless status.success?
    return nil, nil if stdout.strip.empty?

    parsed = YAML.safe_load(stdout)
    jobs   = parsed&.dig("jobs")
    return nil, nil unless jobs.is_a?(Array) && !jobs.empty?

    result = {}
    flatten_yaml_job(jobs.first, "", result)
    result.empty? ? [nil, nil] : [result, nil]
  rescue Exception => e
    return nil, e.message
  end

  # Fetch all sacct fields for a single job via --yaml (for the Job Details modal).
  # Returns [hash, nil] on success or [nil, error_message] on failure.
  def sacct_job(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    require 'yaml'
    sacct   = get_command_path("sacct", bin, bin_overrides)
    command = [ssh_wrapper, sacct, "-j", job_id, "-X", "--yaml"].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ").strip unless status.success?
    return nil, nil if stdout.strip.empty?

    parsed = YAML.safe_load(stdout)
    jobs   = parsed&.dig("jobs")
    return nil, nil unless jobs.is_a?(Array) && !jobs.empty?

    result = {}
    flatten_yaml_job(jobs.first, "", result)
    result.empty? ? [nil, nil] : [result, nil]
  rescue Exception => e
    return nil, e.message
  end

  # Fetch the batch script for a job via sacct --batch-script (-B).
  # Returns [script_content, nil] or [nil, nil] when not available.
  def batch_script(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)
    command = [ssh_wrapper, sacct, "-j", job_id, "-B"].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, nil unless status.success?

    lines = stdout.lines
    return nil, nil unless lines.size >= 2 && lines[0].start_with?("Batch Script for")

    content = lines.drop(2).join
    content.strip.empty? ? [nil, nil] : [content, nil]
  rescue Exception => e
    return nil, e.message
  end

  private

  # Recursively flatten a YAML job hash into dot-notation key/value pairs.
  # The "steps" key is skipped — it contains per-step accounting data.
  def flatten_yaml_job(obj, prefix, result)
    return unless obj.is_a?(Hash)
    obj.each do |key, value|
      next if key.to_s == "steps"
      full_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
      case value
      when Hash     then flatten_yaml_job(value, full_key, result)
      when Array    then result[full_key] = value.join(", ") unless value.empty?
      when NilClass then # skip
      when String   then result[full_key] = value unless value.empty?
      else               result[full_key] = value.to_s
      end
    end
  end
end
