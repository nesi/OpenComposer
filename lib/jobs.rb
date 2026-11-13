require "etc"
require "fileutils"
require "open3"
require "openssl"
require "securerandom"

# Support for the Jobs page and the per-node job list on the Nodes page: who may
# see which details of a job, and how jobs are sorted into categories.
#
# Both views list the jobs of every user. Whose job it is — the job ID, the job
# name, the username and the account — is only sent to the browser for staff
# (members of the groups in "staff_groups:" in conf.yml.erb), and for the
# viewer's own jobs. Everyone else gets the resources and state of each job and
# nothing that says who owns it. The filtering happens here, on the server, so
# the hidden values never reach the page.

# The only keys of a job that every viewer is sent. This is a whitelist on
# purpose: a field added to the scheduler query later stays private until it is
# listed here. ("reason" is listed, but cut down for other people's jobs — see
# public_job_reason.)
JOB_PUBLIC_KEYS  ||= %w[status state partition cpus mem_mb nodes gpus gpu_types
                        time_used time_limit submit start priority reason nodelist array tasks
                        per_node here].freeze

# The keys that say whose job it is. Added back only for staff and for the
# viewer's own jobs.
JOB_PRIVATE_KEYS ||= %w[id name user account].freeze

# The job details shown when a job is clicked on the Nodes page (job["details"]),
# split the same way. Again a whitelist: a detail not listed is never sent.
JOB_DETAIL_PUBLIC_KEYS  ||= %w[qos batch_host alloc_node num_tasks cpus_per_task ntasks_per_node min_cpus
                               min_memory min_tmp_disk sockets cores threads core_spec features licenses
                               tres_alloc tres_per_node tres_per_job tres_per_task tres_per_socket
                               cpus_per_tres mem_per_tres tres_bind tres_freq oversubscribe contiguous
                               req_nodes exc_nodes eligible end time_left min_time deadline pending_time
                               requeue restarts batch exit_code nice reboot network profile].freeze
JOB_DETAIL_PRIVATE_KEYS ||= %w[array_job_id array_task_id group wckey reservation dependency mcs_label
                               command work_dir stdin stdout stderr comment system_comment].freeze

# What squeue prints for a value that is not set.
JOB_DETAIL_UNSET ||= ["(null)", "N/A", "NA", "*", "NONE", "None", "Unknown", "NotSet"].freeze

# Scheduler states of a job that is still waiting. A job in any other state that
# squeue reports (running, completing, configuring, suspended, ...) holds an
# allocation and is counted as running.
JOB_PENDING_STATES ||= %w[PENDING REQUEUED REQUEUE_HOLD REQUEUE_FED RESV_DEL_HOLD SPECIAL_EXIT].freeze

# The job categories, in the order the Jobs page shows them, left to right.
JOB_CATEGORIES ||= [
  { "key" => "compute",      "label" => "Compute jobs",      "group_label" => "Architecture", "resource" => "cpus",
    "empty" => "No compute jobs in the queue." },
  { "key" => "gpu",          "label" => "GPU jobs",          "group_label" => "GPU type",     "resource" => "gpus",
    "empty" => "No GPU jobs in the queue." },
  { "key" => "large_memory", "label" => "Large-memory jobs", "group_label" => "Architecture", "resource" => "mem_mb",
    "empty" => "No large-memory jobs in the queue." }
].freeze

TRES_MEMORY_UNITS ||= { "" => 1.0, "K" => 1.0 / 1024, "M" => 1.0, "G" => 1024.0, "T" => 1024.0**2, "P" => 1024.0**3 }.freeze

# How long a staff-membership answer, and the large-memory thresholds worked out
# from the cluster, are remembered by this process (seconds).
STAFF_CACHE_TTL        ||= 300
LARGE_MEMORY_CACHE_TTL ||= 3600
STAFF_CACHE            ||= { mutex: Mutex.new, entries: {} }
LARGE_MEMORY_CACHE     ||= { mutex: Mutex.new, entries: {} }
JOB_REF_KEYS           ||= { mutex: Mutex.new, keys: {} }

# ── Who is looking ────────────────────────────────────────────────────────────

# The user this process runs as. Taken from the process's own uid rather than
# from the environment.
def current_user_name
  Etc.getpwuid(Process.uid).name
rescue StandardError
  ENV["USER"].to_s
end

# The groups whose members are shown job IDs, job names and usernames.
def staff_groups(conf)
  Array(conf["staff_groups"]).map { |g| g.to_s.strip }.reject(&:empty?)
end

# Numeric IDs of the groups a user belongs to. Asks the system's user database
# afresh (which is where SSSD/IPA group membership comes from), so a change of
# membership is picked up without restarting the web server; falls back to the
# groups this process was started with.
def user_group_ids(user)
  out, _err, status = Open3.capture3("id", "-G", user)
  ids = status.success? ? out.split.grep(/\A\d+\z/).map(&:to_i) : []
  ids.empty? ? (Process.groups + [Process.gid, Process.egid]).uniq : ids
rescue StandardError
  (Process.groups + [Process.gid, Process.egid]).uniq
end

# True when the current user is in one of the staff groups.
#
# The groups are looked up on this server only. Asking the login node over SSH
# instead would let a user answer for themselves (anything their shell start-up
# files print would be read as group names), so that is deliberately not done.
# Anything that goes wrong — no staff group configured, a group this server
# does not know — means "not staff".
def staff_user?(conf)
  groups = staff_groups(conf)
  return false if groups.empty?

  user = current_user_name
  key  = [user, groups]
  now  = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  STAFF_CACHE[:mutex].synchronize do
    hit = STAFF_CACHE[:entries][key]
    return hit[:staff] if hit && now - hit[:at] < STAFF_CACHE_TTL

    wanted = groups.filter_map do |group|
      begin
        Etc.getgrnam(group).gid
      rescue ArgumentError
        nil # this server has no such group
      end
    end
    staff = !wanted.empty? && !(user_group_ids(user) & wanted).empty?
    STAFF_CACHE[:entries][key] = { staff: staff, at: now }
    staff
  end
rescue StandardError
  false
end

# ── Reading a job ─────────────────────────────────────────────────────────────

# Convert a memory amount from a TRES string ("8G", "7936M", "1.50T") to MB.
def tres_memory_mb(value)
  m = value.to_s.strip.match(/\A(\d+(?:\.\d+)?)([KMGTP]?)B?\z/i)
  return nil unless m

  (m[1].to_f * TRES_MEMORY_UNITS[m[2].upcase]).round
end

# Parse a job's TRES string, e.g.
#   "cpu=8,mem=64G,node=1,billing=8,gres/gpu=2,gres/gpu:a100=2"
# into { "cpu", "mem_mb", "node", "gpus", "gpu_types" => { "a100" => 2 } }.
# Values that are absent stay nil (gpus: 0).
def parse_job_tres(tres)
  out = { "cpu" => nil, "mem_mb" => nil, "node" => nil, "gpus" => 0, "gpu_types" => {} }
  tres.to_s.split(",").each do |item|
    key, value = item.strip.split("=", 2)
    next if value.nil?

    case key
    when "cpu"      then out["cpu"]    = value.to_i
    when "node"     then out["node"]   = value.to_i
    when "mem"      then out["mem_mb"] = tres_memory_mb(value)
    when "gres/gpu" then out["gpus"]   = value.to_i
    else
      type = key.to_s[/\Agres\/gpu:(.+)\z/, 1]
      out["gpu_types"][type.downcase] = value.to_i if type
    end
  end
  out["gpus"] = out["gpu_types"].values.sum if out["gpus"].zero?
  out
end

# Parse the GPUs out of a job's per-node GRES request, e.g. "gres/gpu:a100:2",
# "gpu:1" or "gres/gpu:a100". Returns [gpus_per_node, { type => count }].
# Used only when the TRES string carries no GPU count (a cluster that does not
# track gres/gpu as a TRES).
def parse_gres_gpus_per_node(gres)
  total = 0
  types = Hash.new(0)
  gres.to_s.split(",").each do |item|
    parts = item.strip.sub(/\Agres[\/:]/, "").split(/[:=]/)
    next unless parts.first == "gpu"

    count = parts.size > 1 && parts.last.match?(/\A\d+\z/) ? parts.last.to_i : 1
    type  = parts[1] unless parts.size < 2 || parts[1].match?(/\A\d+\z/)
    total += count
    types[type.downcase] += count if type
  end
  [total, types.to_h]
end

# Turn one raw scheduler row (Scheduler#cluster_jobs) into a job with typed
# values. Returns nil for a row that did not parse into sensible columns — such a
# row is dropped rather than shown, because a misaligned row could put one
# column's text under another column's heading.
def normalize_cluster_job(raw)
  state = raw["state"].to_s.strip.upcase
  user  = raw["user"].to_s.strip
  return nil unless state.match?(/\A[A-Z_]+\z/) && !user.empty?

  tres      = parse_job_tres(raw["tres"])
  nodes     = [tres["node"] || raw["nodes"].to_i, 1].max
  gpus      = tres["gpus"]
  gpu_types = tres["gpu_types"]
  if gpus.zero?
    per_node, per_node_types = parse_gres_gpus_per_node(raw["tres_per_node"])
    gpus      = per_node * nodes
    gpu_types = per_node_types.transform_values { |n| n * nodes }
  elsif gpu_types.empty?
    # The TRES string counts the GPUs but not their type (a Slurm that tracks
    # only gres/gpu): take the type from the job's request, if it named one.
    _, asked  = parse_gres_gpus_per_node(raw["tres_per_node"])
    gpu_types = asked.size == 1 ? { asked.keys.first => gpus } : asked.transform_values { |n| n * nodes }
  end

  id      = raw["id"].to_s.strip
  status  = JOB_PENDING_STATES.include?(state) ? "pending" : "running"
  running = status == "running"
  account = raw["account"].to_s.strip
  job = {
    "id"         => id,
    "name"       => raw["name"].to_s.strip,
    "user"       => user,
    "account"    => ["(null)", "N/A"].include?(account) ? "" : account,
    "status"     => status,
    "state"      => state,
    "partition"  => raw["partition"].to_s.strip,
    "cpus"       => tres["cpu"] || raw["cpus"].to_i,
    "mem_mb"     => tres["mem_mb"],
    "nodes"      => nodes,
    "gpus"       => gpus,
    "gpu_types"  => gpu_types,
    "time_used"  => raw["time_used"].to_s.strip,
    "time_limit" => raw["time_limit"].to_s.strip,
    "submit"     => raw["submit"].to_s.strip,
    "start"      => raw["start"].to_s.strip,
    "priority"   => raw["priority"].to_i,
    "reason"     => running ? "" : raw["reason"].to_s.strip,
    "nodelist"   => running ? raw["nodelist"].to_s.strip : "",
    "array"      => id.include?("_"),
    # A pending job array is one row, but stands for all of its waiting tasks.
    "tasks"      => running ? 1 : array_task_count(id)
  }

  # The job details, when they were asked for (see SQUEUE_DETAIL_FIELDS).
  detail_keys = JOB_DETAIL_PUBLIC_KEYS + JOB_DETAIL_PRIVATE_KEYS
  if raw.keys.any? { |key| detail_keys.include?(key) }
    details = { "tres_alloc" => raw["tres"], "tres_per_node" => raw["tres_per_node"] }
    detail_keys.each { |key| details[key] = raw[key] if raw.key?(key) }
    job["details"] = details.transform_values do |value|
      value = value.to_s.strip
      JOB_DETAIL_UNSET.include?(value) ? "" : value
    end
  end
  job
end

# The number of tasks in a pending job array's ID, e.g. 19 for "123_[2-20%4]"
# and 5 for "123_[1,3,5-7]". 1 for anything else, including an ID too long for
# its column (squeue cuts it, so the closing bracket is missing).
def array_task_count(id)
  spec = id.to_s[/_\[([^\]]+)\]\z/, 1]
  return 1 if spec.nil?

  count = spec.sub(/%\d+\z/, "").split(",").sum do |part|
    if (m = part.match(/\A(\d+)-(\d+)(?::(\d+))?\z/))
      first, last, step = m[1].to_i, m[2].to_i, [m[3].to_i, 1].max
      last >= first ? (last - first) / step + 1 : 0
    else
      part.match?(/\A\d+\z/) ? 1 : 0
    end
  end
  count.positive? ? count : 1
end

# The reason a pending job is waiting, as shown on other people's jobs. Slurm
# normally reports a reason code ("Priority", "Resources", "Dependency",
# "QOSMaxCpuPerUserLimit", "ReqNodeNotAvail, UnavailableNodes:c[001-004]"). It
# can also report free text, which may name an account or another job, so only
# the leading code is passed on, and free text becomes "Other".
def public_job_reason(reason)
  text = reason.to_s.strip
  return "" if text.empty?

  text[/\A[A-Za-z][A-Za-z0-9_]*(?=\z|,)/] || "Other"
end

# The copy of a job that is sent to the browser. Every viewer gets the public
# keys; the keys that say whose job it is (and the full pending reason) are
# added only for staff and for the viewer's own jobs. With ref:, also the job's
# reference (see job_ref), for fetching its details later.
def redact_cluster_job(job, staff:, viewer:, ref: nil)
  mine = !viewer.to_s.empty? && job["user"] == viewer
  out  = job.slice(*JOB_PUBLIC_KEYS)
  out["mine"] = mine
  if staff || mine
    out.merge!(job.slice(*JOB_PRIVATE_KEYS))
  else
    out["reason"] = public_job_reason(job["reason"])
  end
  if job["details"]
    out["details"] = job["details"].slice(*(staff || mine ? JOB_DETAIL_PUBLIC_KEYS + JOB_DETAIL_PRIVATE_KEYS : JOB_DETAIL_PUBLIC_KEYS))
  end
  out["ref"] = ref.call(job["id"]) if ref
  out
end

# ── Job references ────────────────────────────────────────────────────────────
#
# On the Jobs page a job's details are fetched when it is clicked. The page must
# be able to name the job without knowing its ID (other people's IDs are hidden
# from users who are not staff), so each job in the list carries a reference:
# its cluster and ID, encrypted with a key only this app reads. Asking for a
# job's details by reference follows the same rules as the lists, so a reference
# can never show more than the list it came from.

# The key: 32 random bytes in the user's data_dir, made on first use and shared
# by every process of the app, so references outlive a restart of one process.
def job_ref_key(conf)
  path = File.join(conf["data_dir"].to_s, ".job-ref.key")
  JOB_REF_KEYS[:mutex].synchronize do
    JOB_REF_KEYS[:keys][path] ||= read_or_create_job_ref_key(path)
  end
end

def read_or_create_job_ref_key(path)
  existing = File.exist?(path) ? File.binread(path) : nil
  return existing if existing && existing.bytesize == 32

  FileUtils.mkdir_p(File.dirname(path))
  tmp = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
  File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(SecureRandom.random_bytes(32)) }
  begin
    # link never replaces a key that another process has just made; a damaged
    # key is replaced.
    existing ? File.rename(tmp, path) : File.link(tmp, path)
  rescue Errno::EEXIST
    nil # another process made the key first: use that one
  rescue NotImplementedError, Errno::EPERM, Errno::EOPNOTSUPP
    File.rename(tmp, path) unless File.exist?(path) # no hard links on this filesystem
  ensure
    File.unlink(tmp) if File.exist?(tmp)
  end
  key = File.binread(path)
  raise "The job reference key #{path} is damaged." unless key.bytesize == 32

  key
end

# The reference of job `id` on `cluster` (AES-256-GCM, as URL-safe base64).
def job_ref(cluster, id, key)
  cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
  cipher.key = key
  iv = cipher.random_iv
  cipher.auth_data = ""
  data = cipher.update("#{cluster}\n#{id}") + cipher.final
  [iv + cipher.auth_tag + data].pack("m0").tr("+/", "-_").delete("=")
end

# The job ID in a reference made by job_ref, or nil when the reference is not
# one of ours, has been altered, or is for another cluster.
def job_ref_id(ref, cluster, key)
  text = ref.to_s.tr("-_", "+/")
  raw  = (text + ("=" * ((4 - text.length % 4) % 4))).unpack1("m0")
  return nil if raw.bytesize <= 28

  cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
  cipher.key      = key
  cipher.iv       = raw.byteslice(0, 12)
  cipher.auth_tag = raw.byteslice(12, 16)
  cipher.auth_data = ""
  ref_cluster, id = (cipher.update(raw.byteslice(28..)) + cipher.final).split("\n", 2)
  ref_cluster == cluster.to_s && cluster_job_id?(id) ? id : nil
rescue ArgumentError, OpenSSL::Cipher::CipherError
  nil
end

# A job ID as squeue prints it: "123", "123_4", a waiting array "123_[5-20%4]"
# (possibly cut short by its column), or a heterogeneous job component "123+1".
def cluster_job_id?(id)
  id.to_s.match?(/\A\d+(?:_(?:\d+|\[[0-9,%:\-]*\]?))?(?:\+\d+)?\z/)
end

# The job with ID `id` in a fresh squeue answer for its job (see the /jobs/job
# route), or nil. A waiting job array whose range has changed since the list was
# made (some of its tasks started) is found by its array's waiting record.
def find_cluster_job(jobs, id)
  found = jobs.find { |job| job["id"] == id }
  return found if found
  return nil unless id.match?(/\A\d+_\[/)

  jobs.find { |job| job["status"] == "pending" && job["id"].start_with?("#{id[/\A\d+/]}_[") }
end

# Who is looking, for the job routes: [staff, staff_capable]. A staff member
# can switch to the view of a user who is not staff (view=user), to see exactly
# what such a user is shown; the switch can only take away, never add.
def job_viewer(conf, params)
  capable = staff_user?(conf)
  [capable && params["view"].to_s != "user", capable]
end

# ── What a job has on each node ───────────────────────────────────────────────

# The node names in a Slurm node list, e.g. "c[001-003,007],gpu01" ->
# ["c001", "c002", "c003", "c007", "gpu01"]; at most `limit` of them.
def expand_hostlist(list, limit = 10_000)
  names = []
  # Split at the commas between names, not those inside brackets.
  list.to_s.scan(/(?:[^,\[]|\[[^\]]*\])+/).each do |term|
    break if names.size >= limit

    expand_hostlist_term(term.strip, names, limit)
  end
  names
end

def expand_hostlist_term(term, names, limit)
  match = term.match(/\A([^\[]*)\[([^\]]*)\](.*)\z/)
  return names << term unless match

  prefix, ranges, rest = match.captures
  ranges.split(",").each do |range|
    next unless range.match?(/\A\d+(?:-\d+)?\z/)

    first, last = range.split("-")
    (first.to_i..(last || first).to_i).each do |n|
      return names if names.size >= limit

      expand_hostlist_term("#{prefix}#{n.to_s.rjust(first.length, '0')}#{rest}", names, limit)
    end
  end
  names
end

# What a running job has on each of its nodes, for its details: for a job on one
# node, its totals; for a job on several, the scheduler's per-node allocations
# (Scheduler#job_node_allocations; nil when they could not be looked up). Each
# entry gives what each node of its node list has, how many nodes that is and,
# when `node` is given, whether that node is one of them.
def job_per_node(job, allocations, node: nil)
  return nil unless job["status"] == "running" && !job["nodelist"].to_s.empty?

  if job["nodes"].to_i <= 1
    allocations = [{ "nodes" => job["nodelist"], "cpus" => job["cpus"], "mem_mb" => job["mem_mb"], "gpus" => job["gpus"] }]
  end
  return nil if allocations.nil? || allocations.empty?

  allocations.map do |allocation|
    names = expand_hostlist(allocation["nodes"])
    entry = allocation.slice("nodes", "cpus", "mem_mb", "gpus").merge("node_count" => names.size)
    entry["this_node"] = names.include?(node) if node
    entry
  end
end

# What a job has on the node its per-node entries were made for (job_per_node
# with node:), or nil.
def job_on_node(per_node)
  per_node&.find { |entry| entry["this_node"] }&.slice("cpus", "mem_mb", "gpus")
end

# ── Large-memory threshold ────────────────────────────────────────────────────

# Memory (MB) of the standard node of a partition: the most common size among
# its nodes without GPUs (or among all its nodes, if every one has GPUs). With a
# tie, the smaller size.
def standard_node_memory_mb(node_groups)
  pool = node_groups.reject { |g| g["gpu"] }
  pool = node_groups if pool.empty?
  counts = Hash.new(0)
  pool.each { |g| counts[g["memory_mb"].to_i] += g["nodes"].to_i }
  counts.max_by { |memory, nodes| [nodes, -memory] }&.first
end

# Normalize "jobs_large_memory_gb:" from conf.yml.erb into { partition => MB }.
# It may be one number for every partition, or a hash of partition names with an
# optional "default".
def configured_large_memory_thresholds(value)
  case value
  when Numeric
    { "default" => (value * 1024).round }
  when Hash
    value.each_with_object({}) do |(partition, gb), out|
      next unless gb.is_a?(Numeric)

      name = partition.to_s.strip
      out[name.match?(/\Adefault\z/i) ? "default" : name] = (gb * 1024).round
    end
  else
    {}
  end
end

# Memory per node (MB), by partition, above which a job counts as "large memory".
#
# Worked out from the cluster: a job is large-memory when it asks for more memory
# per node than the standard node of its partition has, i.e. when it can only run
# on one of the partition's bigger nodes. "jobs_large_memory_gb:" overrides this:
# a single number, or a "default:", sets every partition; per-partition values
# set those partitions and leave the rest to the cluster.
def large_memory_thresholds(conf, cluster_name, scheduler, bin, bin_overrides, ssh_wrapper)
  configured = configured_large_memory_thresholds(conf["jobs_large_memory_gb"])
  return configured if configured.key?("default")

  cluster_large_memory_thresholds(cluster_name, scheduler, bin, bin_overrides, ssh_wrapper).merge(configured)
end

# The thresholds worked out from the cluster (see large_memory_thresholds). The
# answer is remembered for an hour.
def cluster_large_memory_thresholds(cluster_name, scheduler, bin, bin_overrides, ssh_wrapper)
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  LARGE_MEMORY_CACHE[:mutex].synchronize do
    hit = LARGE_MEMORY_CACHE[:entries][cluster_name]
    return hit[:thresholds] if hit && now - hit[:at] < LARGE_MEMORY_CACHE_TTL
  end

  partitions, _error = scheduler.partition_node_memory(bin, bin_overrides, ssh_wrapper)
  thresholds = (partitions || {}).each_with_object({}) do |(partition, node_groups), out|
    memory = standard_node_memory_mb(node_groups)
    out[partition] = memory if memory && memory > 0
  end

  # A failed lookup is not remembered, so the next page view tries again.
  unless thresholds.empty?
    LARGE_MEMORY_CACHE[:mutex].synchronize do
      LARGE_MEMORY_CACHE[:entries][cluster_name] = { thresholds: thresholds, at: now }
    end
  end
  thresholds
end

# True when a job asks for more memory per node than the large-memory threshold
# of every partition it could run in.
def large_memory_job?(job, thresholds)
  return false if job["mem_mb"].nil? || thresholds.empty?

  limits = job["partition"].to_s.split(",").filter_map do |partition|
    thresholds[partition.strip] || thresholds["default"]
  end
  limits << thresholds["default"] if limits.empty? && thresholds["default"]
  return false if limits.empty?

  job["mem_mb"].to_f / [job["nodes"].to_i, 1].max > limits.max
end

# ── Categories ────────────────────────────────────────────────────────────────

# The architecture a job runs on, taken from its partition. "jobs_architectures:"
# in conf.yml.erb may give partitions a display name (and so put several
# partitions under one architecture). A pending job that may start in any of
# several partitions is listed under all of them, e.g. "genoa or milan".
def job_architecture(partition, labels)
  names = partition.to_s.split(",").map(&:strip).reject(&:empty?)
                   .map { |name| (labels[name] || name).to_s }.uniq.sort
  names.empty? ? "Unknown" : names.join(" or ")
end

# The category and the group within it that a job belongs to. Each job is in
# exactly one: a job with GPUs is a GPU job whatever its memory; a job without
# GPUs is large-memory if it is over the threshold; every other job is compute.
#
# GPU jobs are grouped by GPU type alone, whatever their partition: the type a
# running job is using, or the type a pending job is waiting for. A job that
# asked for GPUs without naming a type is "Any type" until it starts.
def classify_cluster_job(job, thresholds, architecture_labels)
  if job["gpus"].to_i > 0
    types = job["gpu_types"].keys.sort
    return ["gpu", types.empty? ? "Any type" : types.map(&:upcase).join(" + ")]
  end

  architecture = job_architecture(job["partition"], architecture_labels)
  if large_memory_job?(job, thresholds)
    ["large_memory", architecture]
  else
    ["compute", architecture]
  end
end

# Sum of jobs, CPUs, GPUs and memory over a list of jobs. A pending job array
# counts once per task.
def job_totals(jobs)
  tasks = ->(j) { [j["tasks"].to_i, 1].max }
  {
    "jobs"   => jobs.sum { |j| tasks.call(j) },
    "cpus"   => jobs.sum { |j| j["cpus"].to_i * tasks.call(j) },
    "gpus"   => jobs.sum { |j| j["gpus"].to_i * tasks.call(j) },
    "mem_mb" => jobs.sum { |j| j["mem_mb"].to_i * tasks.call(j) }
  }
end

# Sort normalized jobs into the categories shown on the Jobs page. Running jobs
# are listed longest-running first; pending jobs highest priority first.
# The jobs in the result are NOT redacted — see redact_job_categories.
def build_job_categories(jobs, thresholds, architecture_labels)
  grouped = Hash.new { |h, k| h[k] = Hash.new { |g, name| g[name] = { "running" => [], "pending" => [] } } }
  jobs.each do |job|
    category, group = classify_cluster_job(job, thresholds, architecture_labels)
    grouped[category][group][job["status"]] << job
  end

  JOB_CATEGORIES.map do |category|
    groups = grouped[category["key"]].sort_by { |name, _| [name == "Any type" ? 1 : 0, name.downcase] }.map do |name, lists|
      running = lists["running"].sort_by { |j| j["start"].match?(/\A\d{4}-/) ? j["start"] : "9" }
      pending = lists["pending"].sort_by { |j| [-j["priority"], j["submit"]] }
      {
        "label"   => name,
        "running" => job_totals(running).merge("list" => running),
        "pending" => job_totals(pending).merge("list" => pending)
      }
    end
    category.merge(
      "groups"  => groups,
      "running" => groups.sum { |g| g["running"]["jobs"] },
      "pending" => groups.sum { |g| g["pending"]["jobs"] },
      "resource_running" => groups.sum { |g| g["running"][category["resource"]] },
      "resource_pending" => groups.sum { |g| g["pending"][category["resource"]] }
    )
  end
end

# Replace every job in the categories with the copy the viewer may see.
def redact_job_categories(categories, staff:, viewer:, ref: nil)
  categories.map do |category|
    groups = category["groups"].map do |group|
      redacted = %w[running pending].to_h do |status|
        list = group[status]["list"].map { |job| redact_cluster_job(job, staff: staff, viewer: viewer, ref: ref) }
        [status, group[status].merge("list" => list)]
      end
      group.merge(redacted)
    end
    category.merge("groups" => groups)
  end
end

# One line describing the large-memory thresholds, for the Jobs page.
def large_memory_note(thresholds)
  return "No large-memory threshold is available, so no job is listed here." if thresholds.empty?

  # One decimal place: a 358000 MB node holds 349.6 GB, and rounding that up to
  # "350 GB" would put a job asking for exactly 350 GB on the wrong side.
  format_gb = ->(mb) { "#{(mb / 1024.0).floor(1).to_s.sub(/\.0\z/, '')} GB" }
  ordered   = thresholds.sort_by { |name, _| name == "default" ? "~" : name }
  # A threshold of 0 (set in conf.yml.erb) puts every job of the partition here.
  every, sized = ordered.partition { |_name, mb| mb.zero? }

  sentences = []
  unless sized.empty?
    sizes = sized.map(&:last).uniq
    sentences << if sizes.size == 1 && every.empty?
                   "Jobs without GPUs that ask for more than #{format_gb.call(sizes.first)} of memory per node."
                 else
                   parts = sized.map { |name, mb| "#{format_gb.call(mb)} #{name == 'default' ? 'elsewhere' : "on #{name}"}" }
                   "Jobs without GPUs that ask for more memory per node than: #{parts.join(', ')}."
                 end
  end
  unless every.empty?
    names = every.map { |name, _| name == "default" ? "every other partition" : name }
    sentences << "Every job without GPUs in #{names.join(', ')}."
  end
  sentences.join(" ")
end
