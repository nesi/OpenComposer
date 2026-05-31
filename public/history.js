var ocHistory = ocHistory || {};

// Apply filter based on the input value and update URL query parameters.
ocHistory.applyFilter = function() {
  const filterInput = document.getElementById('_filterInput');
  const filterColumnInput = document.getElementById('_historyFilterColumn');
  const dateRangeInput = document.getElementById('_historyDateRange');
  const filterModeInput = document.querySelector('input[name="filter_mode"]:checked');
  const dateFromInput = document.getElementById('_historyDateFrom');
  const dateToInput = document.getElementById('_historyDateTo');
  const detailButton = document.getElementById('_historyAdvancedToggle');
  const statusInputs = [
    document.getElementById('_historyStatusQueued'),
    document.getElementById('_historyStatusRunning'),
    document.getElementById('_historyStatusCompleted'),
    document.getElementById('_historyStatusCancelled'),
    document.getElementById('_historyStatusFailed')
  ].filter(Boolean);
  if (!filterInput) return;

  const filterText = filterInput.value;
  const statuses = statusInputs
    .filter(input => input.checked)
    .map(input => input.value);
  const urlParams = new URLSearchParams(window.location.search);
  urlParams.set('filter', filterText);
  urlParams.delete('statuses');
  urlParams.delete('filter_column');
  urlParams.delete('date_range');
  urlParams.delete('filter_mode');
  urlParams.delete('date_from');
  urlParams.delete('date_to');
  urlParams.delete('detail_open');
  urlParams.delete('p');

  if (statuses.length > 0) {
    urlParams.set('statuses', statuses.join(' '));
  }
  else {
    urlParams.set('statuses', 'nothing');
  }

  if (filterColumnInput && filterColumnInput.value) {
    urlParams.set('filter_column', filterColumnInput.value);
  }

  if (dateRangeInput && dateRangeInput.value && dateRangeInput.value !== 'all') {
    urlParams.set('date_range', dateRangeInput.value);
  }

  if (filterModeInput && filterModeInput.value && filterModeInput.value !== 'and') {
    urlParams.set('filter_mode', filterModeInput.value);
  }

  if (dateRangeInput && dateRangeInput.value === 'custom' && dateFromInput && dateFromInput.value) {
    urlParams.set('date_from', dateFromInput.value);
  }

  if (dateRangeInput && dateRangeInput.value === 'custom' && dateToInput && dateToInput.value) {
    urlParams.set('date_to', dateToInput.value);
  }

  if (detailButton && detailButton.getAttribute('aria-expanded') === 'true') {
    urlParams.set('detail_open', 'true');
  }

  window.location.href = `${window.location.pathname}?${urlParams.toString()}`;
};

ocHistory.updateDateRangeVisibility = function() {
  const dateRangeInput = document.getElementById('_historyDateRange');
  const customDates = document.getElementById('_historyCustomDates');
  if (!dateRangeInput || !customDates) return;

  customDates.classList.toggle('d-none', dateRangeInput.value !== 'custom');
  ocHistory.syncSearchLabelWidth();
};

ocHistory.syncSearchLabelWidth = function() {
  const labels = Array.from(document.querySelectorAll('.history-search-label'));
  if (labels.length === 0) return;

  labels.forEach(label => {
    label.style.width = 'auto';
  });

  const maxWidth = Math.ceil(Math.max(...labels.map(label => label.offsetWidth)));
  labels.forEach(label => {
    label.style.width = `${maxWidth}px`;
  });
};

// Toggle the detailed search area.
ocHistory.toggleAdvancedSearch = function() {
  const panel = document.getElementById('_historyAdvancedSearch');
  const button = document.getElementById('_historyAdvancedToggle');
  const icon = document.getElementById('_historyAdvancedToggleIcon');
  if (!panel || !button || !icon) return;

  const isHidden = panel.classList.contains('d-none');
  panel.classList.toggle('d-none', !isHidden);
  button.setAttribute('aria-expanded', isHidden ? 'true' : 'false');
  button.classList.toggle('active', isHidden);
  icon.classList.toggle('bi-chevron-down', !isHidden);
  icon.classList.toggle('bi-chevron-up', isHidden);
  window.requestAnimationFrame(() => ocHistory.syncSearchLabelWidth());
};

ocHistory.advancedToggle = document.getElementById('_historyAdvancedToggle');
if (ocHistory.advancedToggle) {
  ocHistory.advancedToggle.addEventListener('click', function() {
    ocHistory.toggleAdvancedSearch();
  });
}

ocHistory.dateRangeInput = document.getElementById('_historyDateRange');
if (ocHistory.dateRangeInput) {
  ocHistory.updateDateRangeVisibility();
  ocHistory.dateRangeInput.addEventListener('change', function() {
    ocHistory.updateDateRangeVisibility();
  });
}

ocHistory.syncSearchLabelWidth();

document.querySelectorAll('input[id^="_historyStatus"]').forEach(input => {
  input.addEventListener('change', function() {
    ocHistory.applyFilter();
  });
});

// Update the status of a batch operation (e.g., CancelJob, DeleteInfo) for selected jobs.
ocHistory.updateStatusBatch = function(action, jobIds) {
  if (!Array.isArray(jobIds)) return;

  const button    = document.getElementById(`_history${action}Badge`);
  const count     = document.getElementById(`_history${action}Count`);
  const input     = document.getElementById(`_history${action}Input`);
  const modalBody = document.getElementById(`_history${action}Body`);

  input.value = jobIds.join(',');

  // Enable or disable the action button based on job selection.
  if (jobIds.length > 0) {
    button.classList.remove('disabled');
    button.disabled = false;
  }
  else {
    button.classList.add('disabled');
    button.disabled = true;
  }

  // Update the job count display.
  count.textContent = jobIds.length;

  // Update the modal content.
  const jobCountText = jobIds.length === 1
    ? ` one ${action === 'CancelJob' ? 'job' : 'information'} (Job ID is ${jobIds[0]}) ?`
    : ` ${jobIds.length} ${action === 'CancelJob' ? 'jobs' : 'information'} ?`;

  const action_str = action === 'CancelJob' ? "cancel" : "delete";
  modalBody.innerHTML = `Do you want to ${action_str} ${jobCountText}`;

  // If more than one job is selected, display the list of job IDs.
  if (jobIds.length > 1) {
    const jobList = document.createElement('ul');
    jobIds.forEach(jobId => {
      const listItem = document.createElement('li');
      listItem.textContent = jobId;
      jobList.appendChild(listItem);
    });
    modalBody.appendChild(jobList);
  }
};

// Update the batch operations for checked rows (e.g., CancelJob, DeleteInfo).
ocHistory.updateBatch = function(rows) {
  const countId = { checked: [], running: [] };

  rows.forEach(row => {
    const checkbox    = row.querySelector('td input[type="checkbox"]');
    const jobId       = row.getElementsByTagName('td')[1].textContent.trim();
    const statusIndex = row.getElementsByTagName('td').length - 1;
    const status      = row.getElementsByTagName('td')[statusIndex].textContent.trim();

    if (checkbox && checkbox.checked) {
      countId.checked.push(jobId);
      if (status === "Running" || status === "Queued") {
        countId.running.push(jobId);
      }
    }
  });

  // Update batch status for deleting job or info action.
  ocHistory.updateStatusBatch("CancelJob",  countId.running);
  ocHistory.updateStatusBatch("DeleteInfo", countId.checked);
};

// Redirect to the current URL with the selected number of rows as a query parameter.
ocHistory.redirectWithRows = function() {
  const selectBox = document.getElementById("_historyRows");
  if (!selectBox) return;

  const selectedValue = selectBox.value;
  const url = new URL(window.location.href);
  const params = url.searchParams;

  params.delete('p');
  params.set('rows', selectedValue);
  window.location.href = url.toString();
};

// Add event listeners to cluster radio buttons and update the URL when a selection changes.
document.querySelectorAll('input[name="_historyCluster"]').forEach(radio => {
  radio.addEventListener('change', () => {
    const url = new URL(window.location.href);
    const detailButton = document.getElementById('_historyAdvancedToggle');
    url.searchParams.set('cluster', radio.value);
    url.searchParams.delete('p');
    url.searchParams.delete('detail_open');

    if (detailButton && detailButton.getAttribute('aria-expanded') === 'true') {
      url.searchParams.set('detail_open', 'true');
    }

    window.location.href = url.toString();
  });
});


// When the browser restores this page from bfcache (user pressed Back), re-enable
// any Load-parameters buttons that were disabled before navigation.
window.addEventListener('pageshow', function(event) {
  if (event.persisted) {
    document.querySelectorAll('button[onclick*="loadExtScript"]').forEach(function(btn) {
      btn.disabled = false;
      btn.textContent = 'Load parameters';
    });
  }
});

// Load the script from a "Job Script (Slurm - Generic)" modal into the target
// app via sessionStorage, prefilling the script editor and all three header
// fields (Script location, Script name, Job name) from the metadata stashed by
// loadJobScript.
ocHistory.loadExtScript = function(btn) {
  var modal = btn.closest('.modal');
  if (!modal) return;
  var body = modal.querySelector('.modal-body[data-script-job-id]');
  if (!body) return;

  // Wait until loadJobScript has finished (whether the script was available or not).
  // Without this guard the button click is silently ignored while the spinner is running.
  if (body.dataset.loaded !== 'true') return;

  var pre = body.querySelector('pre');
  var scriptContent = pre ? pre.textContent : '';

  var cluster  = body.dataset.cluster || '';
  var base     = window.location.pathname.replace(/\/history$/, '');
  var formData = new URLSearchParams({ cluster: cluster });

  btn.disabled    = true;
  btn.textContent = 'Loading…';

  fetch(base + '/history/save_external_script', { method: 'POST', body: formData })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.url) {
        var payload = {
          script:         scriptContent,
          scriptLocation: body.dataset.extScriptLocation || '',
          scriptName:     body.dataset.extScriptName     || '',
          jobName:        body.dataset.extJobName        || ''
        };
        var key = '_oc_ext_' + Date.now();
        sessionStorage.setItem(key, JSON.stringify(payload));
        var sep = data.url.indexOf('?') >= 0 ? '&' : '?';
        window.location.href = data.url + sep + 'ocExtLoad=' + encodeURIComponent(key);
      } else {
        alert('Error: ' + (data.error || 'Unknown error'));
        btn.disabled    = false;
        btn.textContent = 'Load parameters';
      }
    })
    .catch(function(e) {
      alert('Error: ' + e.message);
      btn.disabled    = false;
      btn.textContent = 'Load parameters';
    });
};

// Escape HTML special characters for safe DOM insertion.
ocHistory.escapeHtml = function(text) {
  const d = document.createElement('div');
  d.textContent = String(text == null ? '' : text);
  return d.innerHTML;
};

// Build HTML table content for Job Details modal from /job_details JSON.
ocHistory.buildJobDetailsContent = function(data) {
  if (data.error) {
    return `<div class="alert alert-warning">${ocHistory.escapeHtml(data.error)}</div>`;
  }

  const entries = data.data ? Object.entries(data.data) : [];
  const rows    = entries.slice().sort(([a], [b]) => a.localeCompare(b));

  if (rows.length === 0) {
    let html = '<p class="text-muted">(No details available for this job.)</p>';
    if (data.errors && Object.keys(data.errors).length > 0) {
      html += '<details class="mt-2"><summary class="text-muted small">Error details</summary>';
      Object.entries(data.errors).forEach(([src, msg]) => {
        html += `<p class="text-muted small mb-0"><strong>${ocHistory.escapeHtml(src)}:</strong> ${ocHistory.escapeHtml(msg)}</p>`;
      });
      html += '</details>';
    }
    return html;
  }

  let html = '<table class="table table-striped table-sm text-break">';
  rows.forEach(([k, v]) => {
    html += `<tr><td>${ocHistory.escapeHtml(k)}</td><td>${ocHistory.escapeHtml(v)}</td></tr>`;
  });
  html += '</table>';

  if (data.source && data.source !== 'none') {
    if (data.command) {
      html += `<details class="mt-2"><summary class="text-muted small" style="cursor:pointer">Source: ${ocHistory.escapeHtml(data.source)}</summary><pre class="small text-muted mt-1 p-1 mb-0" style="white-space:pre-wrap;word-break:break-all">${ocHistory.escapeHtml(data.command)}</pre></details>`;
    } else {
      html += `<p class="text-muted small mt-1 mb-0">Source: ${ocHistory.escapeHtml(data.source)}</p>`;
    }
  }
  return html;
};

// Fetch job details from the server and populate the Job Details modal.
ocHistory.loadJobDetails = function(modalEl) {
  const body = modalEl.querySelector('.modal-body[data-job-id]');
  if (!body || body.dataset.loaded === 'true') return;

  const jobId   = body.dataset.jobId;
  const cluster = body.dataset.cluster;
  const base    = window.location.pathname.replace(/\/history$/, '');
  let url = `${base}/job_details?jobId=${encodeURIComponent(jobId)}`;
  if (cluster) url += `&cluster=${encodeURIComponent(cluster)}`;

  fetch(url)
    .then(r => r.json())
    .then(data => {
      body.dataset.loaded = 'true';
      body.innerHTML = ocHistory.buildJobDetailsContent(data);
    })
    .catch(() => {
      body.dataset.loaded = 'true';
      body.innerHTML = '<div class="alert alert-warning">Could not load job details.</div>';
    });
};

// Fetch batch script via sacct -B and populate the Job Script modal.
// Also stashes script_location, script_name, and JobName as data-attributes on
// the modal body so that loadExtScript can prefill the form header fields.
ocHistory.loadJobScript = function(modalEl) {
  const body = modalEl.querySelector('.modal-body[data-script-job-id]');
  if (!body || body.dataset.loaded === 'true') return;

  const jobId   = body.dataset.scriptJobId;
  const cluster = body.dataset.cluster;
  const base    = window.location.pathname.replace(/\/history$/, '');
  let url = `${base}/job_details?jobId=${encodeURIComponent(jobId)}`;
  if (cluster) url += `&cluster=${encodeURIComponent(cluster)}`;

  fetch(url)
    .then(r => r.json())
    .then(data => {
      body.dataset.loaded = 'true';
      // Stash metadata for loadExtScript to use when "Load parameters" is clicked.
      if (data.script_location) body.dataset.extScriptLocation = data.script_location;
      if (data.script_name)     body.dataset.extScriptName     = data.script_name;
      if (data.data && data.data.JobName) body.dataset.extJobName = data.data.JobName;
      if (data.script_content) {
        body.innerHTML = `<pre class="mb-0 p-2" style="white-space: pre-wrap;">${ocHistory.escapeHtml(data.script_content)}</pre>`;
      } else {
        body.innerHTML = '<p class="text-muted p-2">(No batch script available for this job.)</p>';
      }
    })
    .catch(() => {
      body.dataset.loaded = 'true';
      body.innerHTML = '<div class="alert alert-warning m-2">Could not load batch script.</div>';
    });
};

// Attach lazy-load listeners to Job Details modals.
document.querySelectorAll('[id^="_historyJobId"]').forEach(function(el) {
  el.addEventListener('show.bs.modal', function() {
    ocHistory.loadJobDetails(this);
  });
});

// Attach lazy-load listeners to Job Script modals (when script content is missing from DB).
document.querySelectorAll('[id^="_historyJobScript"]').forEach(function(el) {
  el.addEventListener('show.bs.modal', function() {
    ocHistory.loadJobScript(this);
  });
});

// Handle "Select All" checkbox functionality.
ocHistory.selectAllCheckbox = document.getElementById('_historySelectAll');
ocHistory.tbody = document.getElementById('_historyTbody');

if (ocHistory.selectAllCheckbox && ocHistory.tbody) {
  const rows = Array.from(ocHistory.tbody.getElementsByTagName('tr'));

  // Event listener for the "Select All" checkbox.
  ocHistory.selectAllCheckbox.addEventListener('change', function() {
    const isChecked = this.checked;
    rows.forEach(row => {
      const checkbox = row.querySelector('td input[type="checkbox"]');
      if (checkbox) checkbox.checked = isChecked;
    });
    ocHistory.updateBatch(rows);
  });

  // Event listener for individual row checkboxes.
  rows.forEach(row => {
    const checkbox = row.querySelector('td input[type="checkbox"]');
    if (checkbox) {
      checkbox.addEventListener('change', function() {
        ocHistory.updateBatch(rows);
      });
    }
  });
}
