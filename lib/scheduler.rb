# This class is a superclass for job schedulers, which provides an
# interface to interact with different scheduling systems.
class Scheduler
  # Submit a job to the scheduler.
  # @param script_path [String] path to the job script.
  # @param job_name [String] job name.
  # @added_options [String] Added options.
  # @param bin [String] PATH of commands of job scheduler.
  # @param bin_overrides [Array] PATH of each command of job scheduler.
  # @param ssh_wrapper [String] SSH wrapper. This is used when the local server does not have a job scheduler (optional).
  # @return [Array<String, String>] job id and error message. If successful, the error message is nil; otherwise, the job id is nil.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    raise NotImplementedError, "This method should be overridden by a subclass"
  end

  # Cancel one or more jobs.
  # @param job_ids [Array] array of job IDs to be canceled.
  # @param bin [String] Same as submit().
  # @param bin_overrides [Array] Same as submit().
  # @param ssh_wrapper [String] Same as submit().
  # @return [String] error message. If successful, the error message is nil.
  def cancel(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    raise NotImplementedError, "This method should be overridden by a subclass"
  end

  # Query the status of one or more jobs.
  # @param job_ids [Array] array of job IDs to be queried.
  # @param bin [String] Same as submit().
  # @param bin_overrides [Array] Same as submit().
  # @param ssh_wrapper [String] Same as submit().
  # @return [Array<Hash>] a hash array containing job status and error message.
  #         Example: {JOB_NAME => "foo", JOB_SUBMISSION_TIME => "2024-09-21 15:59:14", JOB_PARTITION => "GH100", JOB_STATUS_ID => JOB_STATUS["completed"]}
  #         Status can be one of: JOB_STATUS["completed"], JOB_STATUS["queued"], JOB_STATUS["running"], JOB_STATUS["failed"].
  #         Additional key-value pairs will be displayed in a modal on the History page when clicking on the job ID.
  def query(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    raise NotImplementedError, "This method should be overridden by a subclass"
  end

  # Fetch live details for a single job from the scheduler control command.
  # Override in subclasses that support this (e.g. Slurm via scontrol).
  # @return [Array<Hash, String>] [parsed_hash_or_nil, error_message_or_nil]
  def scontrol_job(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    [nil, nil]
  end

  # Fetch key fields for a single job from sacct for the Job Details modal.
  # @return [Array<Hash, String>] [parsed_hash_or_nil, error_message_or_nil]
  def sacct_job(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    [nil, nil]
  end

  # Fetch all jobs for the current user within a date range from sacct.
  # @return [Array<Array, String, String>] [jobs_array_or_nil, error_or_nil, command_or_nil]
  def sacct_all_jobs(date_from, date_to, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    [nil, nil, nil]
  end

  # Fetch estimated start times for pending jobs from squeue --start.
  # @param job_ids [Array<String>] base job IDs to query (e.g. ["6801262"]).
  # @return [Array<Hash, String>] [job_id => start_time_string, error_or_nil]
  def squeue_start_times(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    [{}, nil]
  end

  # Fetch the batch script submitted for a job.
  # Override in subclasses that support this (e.g. Slurm via sacct -B).
  # @return [Array<String, String>] [script_content_or_nil, error_message_or_nil]
  def batch_script(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    [nil, nil]
  end

  # Fetch node information from the scheduler for the Nodes page.
  # Each element of the returned array is a 7-element array:
  #   [nodelist, state, cpus_a_i_o_t, memory_mb, free_mem_mb, gres, gres_used]
  # @return [Array<Array, String, String>] [nodes_array_or_nil, error_or_nil, command_or_nil]
  def sinfo_nodes(bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    [nil, nil, nil]
  end

  private

  # Determine the executable path for a given command name.
  # It checks if a specific path override is defined for the command in the bin_overrides hash.
  # If an override exists, it returns the corresponding path; otherwise, it returns the original command name.
  #
  # @param command [String] the command name (e.g. "sbatch").
  # @param bin [String] Same as submit().
  # @param bin_overrides [Array] Same as submit().
  # @return [String] the full path to the command if override exists, or the command name if not.
  def get_command_path(command, bin = nil, bin_overrides = nil)
    return bin_overrides[command] if bin_overrides&.key?(command)

    if bin
      full_path = File.join(bin, command)
      return full_path if File.exist?(full_path)
    end

    command
  end
end
