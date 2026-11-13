require 'open3'

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
  # @param scheduler_env [Hash] environment variables for scheduler commands.
  # @param copy_environment [Boolean] copy the PUN environment to submitted jobs.
  # @return [Array<String, String>] job id and error message. If successful, the error message is nil; otherwise, the job id is nil.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil, copy_environment = nil)
    raise NotImplementedError, "This method should be overridden by a subclass"
  end

  # Cancel one or more jobs.
  # @param job_ids [Array] array of job IDs to be canceled.
  # @param bin [String] Same as submit().
  # @param bin_overrides [Array] Same as submit().
  # @param ssh_wrapper [String] Same as submit().
  # @param scheduler_env [Hash] Same as submit().
  # @return [String] error message. If successful, the error message is nil.
  def cancel(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    raise NotImplementedError, "This method should be overridden by a subclass"
  end

  # Query the status of one or more jobs.
  # @param job_ids [Array] array of job IDs to be queried.
  # @param bin [String] Same as submit().
  # @param bin_overrides [Array] Same as submit().
  # @param ssh_wrapper [String] Same as submit().
  # @param scheduler_env [Hash] Same as submit().
  # @return [Array<Hash>] a hash array containing job status and error message.
  #         Example: {JOB_NAME => "foo", JOB_SUBMISSION_TIME => "2024-09-21 15:59:14", JOB_PARTITION => "GH100", JOB_STATUS_ID => JOB_STATUS["completed"]}
  #         Status can be one of: JOB_STATUS["completed"], JOB_STATUS["queued"], JOB_STATUS["running"], JOB_STATUS["failed"].
  #         Additional key-value pairs will be displayed in a modal on the History page when clicking on the job ID.
  def query(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
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

  # Fetch all currently active (queued/running) jobs for the current user from squeue.
  # Returns entries with the same key names as sacct_all_jobs so they can be merged
  # into sacct_map for any job IDs sacct did not report (e.g. freshly queued jobs).
  # @return [Array<Array, String>] [jobs_array, error_or_nil]
  def squeue_active_jobs(bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    [[], nil]
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

  # Whether this scheduler can list every user's jobs (cluster_jobs below). The
  # Jobs page and the per-node job list on the Nodes page are only offered when
  # it can.
  def supports_cluster_jobs?
    false
  end

  # Fetch the jobs of ALL users that are currently in the queue, for the Jobs page
  # and for the per-node job list on the Nodes page.
  # @param node [String] when given, only the jobs allocated to that node.
  # @param job [String] when given (a numeric job ID), only that job.
  # @param details [Boolean] also fetch the fields behind the job details view.
  # @return [Array<Array, String, String>] [jobs_array_or_nil, error_or_nil, command_or_nil]
  #         Each job is a Hash of raw scheduler strings. It contains other users'
  #         job IDs, job names and usernames, so it must go through
  #         normalize_cluster_job and redact_cluster_job (lib/jobs.rb) before any
  #         of it is sent to the browser.
  def cluster_jobs(bin = nil, bin_overrides = nil, ssh_wrapper = nil, node: nil, job: nil, details: false)
    [nil, "Listing jobs is not supported for this scheduler.", nil]
  end

  # What running jobs have been given on each of their nodes, for jobs that run
  # on more than one node (cluster_jobs only has each job's totals).
  # @param job_ids [Array<String>] the IDs of running jobs.
  # @return [Hash] { job_id => [{ "nodes" => node list, "cpus" => Integer,
  #         "mem_mb" => Integer, "gpus" => Integer }] }, each entry giving what
  #         each node in its node list has. Jobs it could not look up are left out.
  def job_node_allocations(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    {}
  end

  # Memory of the nodes in each partition, for working out which jobs need a
  # large-memory node (see large_memory_thresholds in lib/jobs.rb).
  # @return [Array<Hash, String>] [{ partition => [{ "memory_mb" => Integer, "nodes" => Integer, "gpu" => Boolean }] }, error_or_nil]
  def partition_node_memory(bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    [{}, nil]
  end

  # Return true if the given string is a valid job ID for this scheduler.
  # Override in subclasses to match each scheduler's ID format.
  def valid_job_id?(id)
    id.to_s.match?(/\A\d+\z/)
  end

  # Map a raw scheduler state string to an OpenComposer status constant.
  # Override in subclasses with scheduler-specific state strings.
  def state_to_oc_status(state)
    JOB_STATUS["unknown"]
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

  def capture_scheduler_command(scheduler_env, command)
    Open3.capture3(scheduler_command_env(scheduler_env), command)
  end

  def scheduler_command_env(scheduler_env)
    return {} unless scheduler_env.is_a?(Hash)

    (scheduler_env || {}).each_with_object({}) do |(key, value), env|
      env[key.to_s] = value.to_s unless value.nil?
    end
  end
end
