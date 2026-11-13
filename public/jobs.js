// Job tables shared by the Jobs page (views/jobs.erb) and the per-node job list
// on the Nodes page (views/nodes.erb).
//
// What a viewer may see is decided on the server (lib/jobs.rb): a job carries
// its id, name, user and account only when the viewer is staff, or when it is
// the viewer's own job (job.mine). This file hides nothing — it shows whatever
// columns the data it was given can fill.
var ocJobs = (function() {
  'use strict';

  function esc(s) {
    return String(s === null || s === undefined ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function trimNumber(n, digits) {
    return String(parseFloat(n.toFixed(digits)));
  }

  function formatNumber(n) {
    return Number(n || 0).toLocaleString('en');
  }

  // Memory in MB as "512 MB", "16 GB" or "1.46 TB".
  function formatMemory(mb) {
    if (mb === null || mb === undefined) return '—';
    if (mb < 1024) return mb + ' MB';
    var gb = mb / 1024;
    if (gb < 1024) return trimNumber(gb, 1) + ' GB';
    return trimNumber(gb / 1024, 2) + ' TB';
  }

  // A Slurm duration ("1-02:03:04", "02:03:04", "03:04") in seconds, for sorting.
  // "UNLIMITED" sorts last; anything else that is not a duration sorts first.
  function durationSeconds(text) {
    var m = String(text || '').match(/^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$/);
    if (!m) return /unlimited/i.test(String(text)) ? Infinity : -1;
    return ((+m[1] || 0) * 24 + (+m[2] || 0)) * 3600 + (+m[3]) * 60 + (+m[4]);
  }

  // "2026-11-13T10:15:00" as "2026-11-13 10:15"; "N/A" and the like as a dash.
  function formatTime(text) {
    var m = String(text || '').match(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/);
    return m ? m[1] + ' ' + m[2] : '—';
  }

  function stateBadge(job) {
    var state = String(job.state || '');
    var css;
    if      (state === 'RUNNING')                           css = 'primary';
    else if (state === 'PENDING')                           css = 'secondary';
    else if (state === 'SUSPENDED' || state === 'STOPPED')  css = 'warning text-dark';
    else                                                    css = 'info text-dark';
    var label = state.charAt(0) + state.slice(1).toLowerCase().replace(/_/g, ' ');
    var html  = '<span class="badge bg-' + css + '">' + esc(label) + '</span>';
    if (job.array && job.status === 'pending') {
      var tasks = job.tasks > 1 ? job.tasks : 0;
      html += ' <span class="badge border text-secondary fw-normal text-nowrap" title="' +
              (tasks ? 'A job array with ' + formatNumber(tasks) + ' tasks waiting to start. The resources shown are for each task; the totals count every task.'
                     : 'Tasks of a job array that are waiting to start.') + '">' +
              'array' + (tasks ? ' · ' + formatNumber(tasks) + ' tasks' : '') + '</span>';
    }
    return html;
  }

  // Why a pending job is waiting. For other people's jobs the server sends only
  // Slurm's reason code, and "Other" in place of any free text.
  function reasonHtml(job) {
    if (!job.reason) return muted('—');
    if (job.reason === 'Other' && !job.mine && !job.id) {
      return '<span class="text-muted" title="The scheduler gave a free-text reason, which is shown only to staff and to the job\'s owner.">Other</span>';
    }
    return clipped(job.reason, 200);
  }

  function gpuText(job) {
    if (!job.gpus) return '—';
    var types = Object.keys(job.gpu_types || {}).sort();
    if (!types.length) return String(job.gpus);
    return types.map(function(type) { return job.gpu_types[type] + ' × ' + type.toUpperCase(); }).join(', ');
  }

  function muted(text) {
    return '<span class="text-muted">' + esc(text) + '</span>';
  }

  // Text that may be long (a job name, a node list): one line, cut with an
  // ellipsis, the full text on hover.
  function clipped(text, width) {
    if (!text) return muted('—');
    return '<span class="d-inline-block text-truncate align-bottom" style="max-width:' + width + 'px;" title="' +
           esc(text) + '">' + esc(text) + '</span>';
  }

  var YOURS = ' <span class="badge bg-success" title="This is your job.">Yours</span>';

  // value(): what the column sorts by. html(): the cell.
  var COLUMNS = {
    id:        { label: 'Job ID',     value: function(j) { return j.id || ''; },
                 html: function(j) { return '<code>' + esc(j.id) + '</code>' + (j.mine ? YOURS : ''); } },
    name:      { label: 'Job name',   value: function(j) { return j.name || ''; },
                 html: function(j) { return clipped(j.name, 220); } },
    user:      { label: 'User',       value: function(j) { return j.user || ''; },
                 html: function(j) { return esc(j.user); } },
    account:   { label: 'Account',    value: function(j) { return j.account || ''; },
                 html: function(j) { return esc(j.account); } },
    // The only identifying column a non-staff viewer gets: filled for their own
    // jobs, empty for everyone else's.
    yours:     { label: 'Your job',   value: function(j) { return j.mine ? (j.id || '') : ''; },
                 html: function(j) {
                   if (!j.mine) return muted('—');
                   return '<code>' + esc(j.id) + '</code> ' + clipped(j.name, 180) + YOURS;
                 } },
    state:     { label: 'State',      value: function(j) { return j.state || ''; }, html: stateBadge },
    partition: { label: 'Partition',  value: function(j) { return j.partition || ''; },
                 html: function(j) { return esc(j.partition); } },
    nodelist:  { label: 'Running on', value: function(j) { return j.nodelist || ''; },
                 html: function(j) { return clipped(j.nodelist, 200); } },
    nodes:     { label: 'Nodes',      value: function(j) { return j.nodes || 0; }, numeric: true,
                 html: function(j) { return formatNumber(j.nodes); } },
    reason:    { label: 'Reason',     value: function(j) { return j.reason || ''; }, html: reasonHtml },
    cpus:      { label: 'CPUs',       value: function(j) { return j.cpus || 0; }, numeric: true,
                 html: function(j) { return formatNumber(j.cpus); } },
    mem:       { label: 'Memory',     value: function(j) { return j.mem_mb || 0; }, numeric: true,
                 html: function(j) { return esc(formatMemory(j.mem_mb)); } },
    gpus:      { label: 'GPUs',       value: function(j) { return j.gpus || 0; }, numeric: true,
                 html: function(j) { return esc(gpuText(j)); } },
    used:      { label: 'Elapsed',    value: function(j) { return durationSeconds(j.time_used); }, numeric: true,
                 html: function(j) { return esc(j.time_used); } },
    limit:     { label: 'Time limit', value: function(j) { return durationSeconds(j.time_limit); }, numeric: true,
                 html: function(j) { return esc(j.time_limit); } },
    submit:    { label: 'Submitted',  value: function(j) { return j.submit || ''; },
                 html: function(j) { return esc(formatTime(j.submit)); } },
    priority:  { label: 'Priority',   value: function(j) { return j.priority || 0; }, numeric: true,
                 html: function(j) { return formatNumber(j.priority); } }
  };

  // The columns after the identifying ones, by kind of list.
  var LAYOUTS = {
    node:    ['state', 'partition', 'cpus', 'mem', 'gpus', 'nodes', 'used', 'limit'],
    running: ['state', 'partition', 'nodelist', 'cpus', 'mem', 'gpus', 'used', 'limit'],
    pending: ['state', 'partition', 'reason', 'cpus', 'mem', 'gpus', 'limit', 'submit', 'priority']
  };

  // Staff get the job ID, name, user and account of every job. Anyone else gets
  // one "Your job" column, and only when the list has a job of theirs in it.
  function identityColumns(jobs, staff) {
    if (staff) return ['id', 'name', 'user', 'account'];
    return jobs.some(function(j) { return j.mine; }) ? ['yours'] : [];
  }

  // Draw a sortable job table into `container`, 50 rows at a time.
  //   options.staff      the viewer is staff (as reported by the server)
  //   options.layout     'node', 'running' or 'pending'
  //   options.emptyText  shown instead of a table when there are no jobs
  //   options.onRowClick called with (job, row) when a row is clicked (or Enter)
  function renderTable(container, jobs, options) {
    options = options || {};
    var keys      = identityColumns(jobs, !!options.staff).concat(LAYOUTS[options.layout] || LAYOUTS.running);
    var pageSize  = options.pageSize || 50;
    var rows      = jobs.slice();
    var shown     = pageSize;
    var sortKey   = null;
    var sortAsc   = true;
    var clickable = typeof options.onRowClick === 'function';

    container.innerHTML = '';
    if (!jobs.length) {
      container.innerHTML = '<p class="text-muted small mb-0">' + esc(options.emptyText || 'No jobs.') + '</p>';
      return;
    }

    var wrap   = document.createElement('div');
    var table  = document.createElement('table');
    var thead  = document.createElement('thead');
    var headTr = document.createElement('tr');
    var tbody  = document.createElement('tbody');
    var footer = document.createElement('div');
    wrap.className   = 'table-responsive';
    table.className  = 'table table-bordered table-hover table-sm mb-1 align-middle';
    thead.className  = 'table-light';
    footer.className = 'd-flex align-items-center gap-2 small text-muted';

    keys.forEach(function(key) {
      var th = document.createElement('th');
      th.className        = 'user-select-none' + (COLUMNS[key].numeric ? ' text-end' : '');
      th.style.whiteSpace = 'nowrap';
      th.style.cursor     = 'pointer';
      th.title            = 'Click to sort';
      th.dataset.key      = key;
      th.innerHTML        = esc(COLUMNS[key].label) + ' <span class="jobs-sort-mark text-muted" style="font-size:.7em;">⇅</span>';
      th.addEventListener('click', function() { sortBy(key); });
      headTr.appendChild(th);
    });

    function draw() {
      tbody.innerHTML = rows.slice(0, shown).map(function(job, i) {
        return '<tr data-i="' + i + '"' + (job.mine ? ' class="table-success"' : '') +
               (clickable ? ' tabindex="0" style="cursor:pointer;" title="Show all the details of this job"' : '') +
               '>' + keys.map(function(key) {
          return '<td' + (COLUMNS[key].numeric ? ' class="text-end text-nowrap"' : '') + '>' + COLUMNS[key].html(job) + '</td>';
        }).join('') + '</tr>';
      }).join('');

      footer.innerHTML = '';
      var count = document.createElement('span');
      count.textContent = 'Showing ' + formatNumber(Math.min(shown, rows.length)) + ' of ' + formatNumber(rows.length) +
                          (rows.length === 1 ? ' job' : ' jobs');
      footer.appendChild(count);
      if (shown < rows.length) {
        var more = document.createElement('button');
        more.type        = 'button';
        more.className   = 'btn btn-sm btn-outline-secondary py-0';
        more.textContent = 'Show ' + formatNumber(Math.min(pageSize * 4, rows.length - shown)) + ' more';
        more.addEventListener('click', function() { shown += pageSize * 4; draw(); });
        footer.appendChild(more);
      }
    }

    function sortBy(key) {
      if (sortKey === key) { sortAsc = !sortAsc; } else { sortKey = key; sortAsc = true; }
      var column = COLUMNS[key];
      rows = jobs.slice().sort(function(a, b) {
        var av = column.value(a), bv = column.value(b);
        var cmp = column.numeric ? (av === bv ? 0 : (av < bv ? -1 : 1))
                                 : String(av).localeCompare(String(bv), undefined, { numeric: true, sensitivity: 'base' });
        return sortAsc ? cmp : -cmp;
      });
      shown = pageSize;
      Array.prototype.forEach.call(headTr.children, function(th) {
        var mark = th.querySelector('.jobs-sort-mark');
        var on   = th.dataset.key === key;
        mark.textContent = on ? (sortAsc ? '▲' : '▼') : '⇅';
        mark.className   = 'jobs-sort-mark ' + (on ? 'text-primary' : 'text-muted');
      });
      draw();
    }

    if (clickable) {
      // rows[] is re-sorted in place of the old array, so look it up on click.
      var open = function(e) {
        var tr = e.target.closest('tr[data-i]');
        if (tr) options.onRowClick(rows[+tr.dataset.i], tr);
      };
      tbody.addEventListener('click', open);
      tbody.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(e); }
      });
    }

    thead.appendChild(headTr);
    table.appendChild(thead);
    table.appendChild(tbody);
    wrap.appendChild(table);
    container.appendChild(wrap);
    container.appendChild(footer);
    draw();
  }

  // ── Staff view / user view ────────────────────────────────────────────────
  // A staff member can look at the job lists as a user who is not staff sees
  // them. The choice is remembered in this browser, and sent to the server,
  // which does the hiding (so the user view is exactly what users get).
  var VIEW_KEY  = 'ocJobsView';
  var viewInMem = 'staff';

  function getView() {
    try {
      return window.localStorage.getItem(VIEW_KEY) === 'user' ? 'user' : 'staff';
    } catch (e) {
      return viewInMem;
    }
  }

  function setView(view) {
    viewInMem = view;
    try { window.localStorage.setItem(VIEW_KEY, view); } catch (e) { /* remembered for this page only */ }
  }

  // The query parameter asking the server for the user view, or ''.
  function viewParam() {
    return getView() === 'user' ? 'view=user' : '';
  }

  // The line that tells the viewer what they are, and are not, being shown,
  // with the staff/user view switch for staff. onChange() reloads the data.
  function renderPrivacy(el, data, onChange) {
    var html;
    if (data.staff) {
      html = '<span class="badge bg-dark me-1">Staff view</span>' +
             '<span class="text-muted">You can see job IDs, job names, users and accounts because you are staff. ' +
             'Other users cannot.</span>';
    } else if (data.staff_capable) {
      html = '<span class="badge bg-warning text-dark me-1">User view</span>' +
             '<span class="text-muted">You are seeing exactly what a user who is not staff sees. ' +
             'Your own jobs are still marked <span class="badge bg-success">Yours</span>.</span>';
    } else {
      html = '<i class="fas fa-lock text-muted me-1" aria-hidden="true"></i>' +
             '<span class="text-muted">Job IDs, job names and users are shown to staff only. ' +
             'You can see them for your own jobs, which are marked <span class="badge bg-success">Yours</span>.</span>';
    }
    if (data.staff_capable) {
      html += ' <button type="button" class="btn btn-link btn-sm p-0 ms-1 align-baseline jobs-view-toggle">' +
              (data.staff ? 'See what users see' : 'Back to the staff view') + '</button>';
    }
    el.innerHTML = html;
    var toggle = el.querySelector('.jobs-view-toggle');
    if (toggle) {
      toggle.addEventListener('click', function() {
        setView(data.staff ? 'user' : 'staff');
        if (onChange) onChange();
      });
    }
  }

  // ── All the details of one job ────────────────────────────────────────────
  function detailTime(v) {
    var m = String(v).match(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})/);
    return esc(m ? m[1] + ' ' + m[2] : v);
  }

  function detailSeconds(v) {
    var s = parseInt(v, 10);
    if (isNaN(s)) return esc(v);
    var parts = [];
    if (s >= 86400) parts.push(Math.floor(s / 86400) + 'd');
    if (s >= 3600)  parts.push(Math.floor(s % 86400 / 3600) + 'h');
    if (s >= 60)    parts.push(Math.floor(s % 3600 / 60) + 'm');
    parts.push(s % 60 + 's');
    return parts.join(' ');
  }

  function detailTres(v) {
    return String(v).split(',').filter(Boolean).map(function(t) {
      return '<span class="badge text-bg-light border fw-normal me-1">' + esc(t) + '</span>';
    }).join('');
  }

  // [key, label, kind, status]. "d." keys are in job.details; the rest are the
  // list fields. A field with a status is shown only for jobs in that status
  // ('running' or 'pending'). A detail the viewer may not see is not in the
  // data at all, and is simply not shown.
  var DETAIL_SECTIONS = [
    { title: 'Job', fields: [
      ['id', 'Job ID', 'code'], ['name', 'Job name'], ['user', 'User'], ['d.group', 'Group'],
      ['account', 'Account'], ['d.array_job_id', 'Array job ID', 'array'], ['d.array_task_id', 'Array task ID'],
      ['state', 'State', 'state'], ['reason', 'Waiting because', null, 'pending'], ['partition', 'Partition'], ['d.qos', 'QOS'],
      ['priority', 'Priority', 'number'], ['d.nice', 'Nice', 'nonzero'], ['d.reservation', 'Reservation'],
      ['d.dependency', 'Dependency'], ['d.wckey', 'WCKey'], ['d.mcs_label', 'MCS label'],
      ['d.comment', 'Comment'], ['d.system_comment', 'System comment']] },
    { title: 'Resources', fields: [
      ['nodes', 'Nodes', 'number'], ['cpus', 'CPUs', 'number'], ['mem_mb', 'Memory', 'mem'], ['gpus', 'GPUs', 'gpus'],
      ['d.num_tasks', 'Tasks'], ['d.ntasks_per_node', 'Tasks per node', 'nonzero'], ['d.cpus_per_task', 'CPUs per task'],
      ['d.min_cpus', 'Minimum CPUs per node'], ['d.min_memory', 'Memory requested'],
      ['d.min_tmp_disk', 'Temporary disk', 'nonzero'], ['d.tres_alloc', 'Allocated (TRES)', 'tres'],
      ['d.tres_per_node', 'Per node (TRES)', 'tres'], ['d.tres_per_job', 'Per job (TRES)', 'tres'],
      ['d.tres_per_task', 'Per task (TRES)', 'tres'], ['d.tres_per_socket', 'Per socket (TRES)', 'tres'],
      ['d.cpus_per_tres', 'CPUs per TRES'], ['d.mem_per_tres', 'Memory per TRES'], ['d.tres_bind', 'TRES binding'],
      ['d.tres_freq', 'TRES frequency'], ['d.features', 'Features'], ['d.licenses', 'Licenses'],
      ['d.sockets', 'Sockets per node'], ['d.cores', 'Cores per socket'], ['d.threads', 'Threads per core'],
      ['d.core_spec', 'Specialised cores'], ['d.oversubscribe', 'Shares nodes (OverSubscribe)'],
      ['d.contiguous', 'Contiguous nodes', 'bool']] },
    { title: 'Placement', fields: [
      ['nodelist', 'Running on', null, 'running'], ['d.batch_host', 'Batch host', null, 'running'],
      ['d.req_nodes', 'Requested nodes'], ['d.exc_nodes', 'Excluded nodes'], ['d.alloc_node', 'Submitted from']] },
    { title: 'Times', fields: [
      ['submit', 'Submitted', 'time'], ['d.eligible', 'Eligible', 'time'],
      ['start', 'Started', 'time', 'running'], ['start', 'Expected start', 'time', 'pending'],
      ['d.end', 'Expected end', 'time'], ['time_used', 'Elapsed', null, 'running'],
      ['d.time_left', 'Time left', null, 'running'], ['time_limit', 'Time limit'],
      ['d.min_time', 'Minimum time', 'nonzero'], ['d.deadline', 'Deadline', 'time'],
      ['d.pending_time', 'Waited before starting', 'seconds', 'running'],
      ['d.pending_time', 'Waiting for', 'seconds', 'pending']] },
    { title: 'Files and command', fields: [
      ['d.command', 'Command', 'path'], ['d.work_dir', 'Working directory', 'path'],
      ['d.stdout', 'Standard output', 'path'], ['d.stderr', 'Standard error', 'path'],
      ['d.stdin', 'Standard input', 'path']] },
    { title: 'Other', fields: [
      ['d.batch', 'Batch job', 'bool'], ['d.requeue', 'Requeued if it fails', 'bool'], ['d.restarts', 'Restarts'],
      ['d.exit_code', 'Exit code'], ['d.reboot', 'Reboots nodes first', 'bool'], ['d.profile', 'Profiling'],
      ['d.network', 'Network']] }
  ];

  // The HTML of one detail, or null to leave it out.
  function detailHtml(job, key, kind) {
    if (kind === 'state') return stateBadge(job);
    var v = key.indexOf('d.') === 0 ? (job.details || {})[key.slice(2)] : job[key];
    if (v === undefined || v === null || v === '') return null;
    switch (kind) {
      // Slurm reports a job's own ID as its array job ID; only arrays have tasks.
      case 'array':   return (job.details || {}).array_task_id ? esc(v) : null;
      case 'code':    return '<code>' + esc(v) + '</code>';
      case 'number':  return esc(formatNumber(v));
      case 'mem':     return esc(formatMemory(v));
      case 'gpus':    return v ? esc(gpuText(job)) : null;
      case 'time':    return detailTime(v);
      case 'bool':    return v === '1' ? 'Yes' : (v === '0' ? 'No' : esc(v));
      case 'seconds': return detailSeconds(v);
      case 'tres':    return detailTres(v);
      case 'path':    return '<code class="text-break">' + esc(v) + '</code>';
      case 'nonzero': return /^0+([:.]0+)*[KMGT]?$/.test(String(v)) ? null : esc(v);
      default:        return esc(v);
    }
  }

  // Draw every detail of `job` that the viewer is allowed to see.
  function renderJobDetail(container, job) {
    var title = job.id
      ? 'Job <code>' + esc(job.id) + '</code>' + (job.name ? ' <span class="text-muted">·</span> ' + esc(job.name) : '')
      : 'Another user\'s job';
    var html = '<div class="d-flex flex-wrap align-items-center gap-2 mb-2">' +
               '<span class="fw-semibold text-break" style="min-width:0;">' + title + '</span>' +
               stateBadge(job) + (job.mine ? YOURS : '') + '</div>';
    if (!job.id) {
      html += '<p class="small text-muted mb-2"><i class="fas fa-lock me-1" aria-hidden="true"></i>' +
              'Its job ID, name, user, group, account, files, command, dependencies and comments are shown only ' +
              'to staff and to the job\'s owner.</p>';
    }
    if (!job.details) {
      html += '<p class="small text-muted mb-2">This cluster did not report further details for this job.</p>';
    }
    html += '<div class="row row-cols-1 row-cols-lg-2 g-2">' + DETAIL_SECTIONS.map(function(section) {
      var items = section.fields.map(function(f) {
        if (f[3] && f[3] !== job.status) return '';
        var value = detailHtml(job, f[0], f[2]);
        return value === null ? '' :
          '<dt class="col-sm-5 text-muted fw-normal">' + esc(f[1]) + '</dt>' +
          '<dd class="col-sm-7 mb-1 text-break">' + value + '</dd>';
      }).join('');
      return items ? '<div class="col"><div class="card h-100 border-secondary-subtle">' +
                     '<div class="card-header py-1 small fw-semibold">' + esc(section.title) + '</div>' +
                     '<div class="card-body py-2"><dl class="row small mb-0">' + items + '</dl></div></div></div>'
                   : '';
    }).join('') + '</div>';
    container.innerHTML = html;
  }

  return {
    esc:             esc,
    formatMemory:    formatMemory,
    formatNumber:    formatNumber,
    renderTable:     renderTable,
    renderPrivacy:   renderPrivacy,
    renderJobDetail: renderJobDetail,
    viewParam:       viewParam
  };
})();
