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
  //   options.staff     the viewer is staff (as reported by the server)
  //   options.layout    'node', 'running' or 'pending'
  //   options.emptyText shown instead of a table when there are no jobs
  function renderTable(container, jobs, options) {
    options = options || {};
    var keys     = identityColumns(jobs, !!options.staff).concat(LAYOUTS[options.layout] || LAYOUTS.running);
    var pageSize = options.pageSize || 50;
    var rows     = jobs.slice();
    var shown    = pageSize;
    var sortKey  = null;
    var sortAsc  = true;

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
      tbody.innerHTML = rows.slice(0, shown).map(function(job) {
        return '<tr' + (job.mine ? ' class="table-success"' : '') + '>' + keys.map(function(key) {
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

    thead.appendChild(headTr);
    table.appendChild(thead);
    table.appendChild(tbody);
    wrap.appendChild(table);
    container.appendChild(wrap);
    container.appendChild(footer);
    draw();
  }

  // The line that tells the viewer what they are, and are not, being shown.
  function privacyNotice(staff) {
    if (staff) {
      return '<span class="badge bg-dark me-1">Staff view</span>' +
             '<span class="text-muted">You can see job IDs, job names, users and accounts because you are staff. ' +
             'Other users cannot.</span>';
    }
    return '<i class="fas fa-lock text-muted me-1" aria-hidden="true"></i>' +
           '<span class="text-muted">Job IDs, job names and users are shown to staff only. ' +
           'You can see them for your own jobs, which are marked <span class="badge bg-success">Yours</span>.</span>';
  }

  return {
    esc:           esc,
    formatMemory:  formatMemory,
    formatNumber:  formatNumber,
    renderTable:   renderTable,
    privacyNotice: privacyNotice
  };
})();
