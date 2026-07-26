# Changelog

## [3.0.0] - 2026-06-11

### Added

#### Open OnDemand integration

- **OOD-integrated (embedded) mode** — Open Composer can render inside Open OnDemand's own
  chrome (live OOD navbar and footer) via a reverse-proxy dashboard initializer under
  `ood_integration/`, with no iframe. Toggleable per deployment; runs full-width.

#### Home page, templates & the script browser

- **All Templates page** — a new navbar-level page (`/all_templates`) listing every template as
  one flat list: the featured submit-template category first, then your own saved custom
  templates (purple *My Template* badge), then every remaining application alphabetically.
  Unlike the home page it also lists applications hidden from the home gallery.
- **Navbar links renamed and split** — the left-hand navbar is now
  **Selected Templates** / **All Templates** / **History** / **Nodes**. The upstream
  "Applications" dropdown was removed, along with the `show_navbar_apps` and
  `navbar_apps_label` settings that controlled it.
- **Load or Create a Script from Disk** (`show_load_script`, `load_script_label`) — a full-page
  file browser (breadcrumbs, sortable Name/Size/Modified/Owner/Mode columns, hidden-file and
  owner/mode toggles, quick filter, directory history). Clicking a `.sl`, `.sh`, `.bash`,
  `.sbatch`, `.batch` or `.slurm` file opens it in the generic Slurm editor with the script
  location and name pre-filled.
- **New Script picker** — choose any template to start from, with the directory you were
  browsing carried through as the script location.
- **New Custom Template picker** (`/templates/new`) — pick any application, or a generic
  scheduler template filtered to the configured scheduler, as the starting point. Forms opened
  this way are in *template mode*: **Submit** is hidden and **Save as Custom Template** becomes
  the primary action.
- **Drag-and-drop ordering** of My Custom Templates, persisted as `position:` in each template's
  YAML (`POST /templates/reorder`), plus a per-section search box.
- **`home_format: small`** — a compact, letter-grouped alternative to the default tile grid.
- **`category_badge_colors`** — per-category badge colours, and **`all_templates_footer`** — an
  admin message pinned under the All Templates list.
- **`new_script_featured_category`** — which manifest category is pinned to the top of the
  All Templates and New Script pages (default `Slurm Submit Templates`).
- **`tags` manifest key** — the tag `GPU` (any case) adds a black *GPU* badge wherever the app
  is listed. Applications whose name matches a GPU-domain module in the site module list are
  badged automatically.

#### Application forms

- **`module_load` widget** — a dropdown of every available version of an environment module,
  populated asynchronously from the site module list (`GET /_module_avail`). Changing it
  rewrites the existing `module load …` line in place instead of regenerating the template
  line, so surrounding hand-written script lines are preserved.
- **`dependent_module_select` widget** — a dropdown whose module list follows the value of
  another (driver) widget, matched with `prefix:` or `contains:`.
- **`remember_last: true`** on `select` widgets — restores the user's previous choice from
  browser storage, skipped when a form is opened from a saved template or from History.
- **Script → form parsing** — editing the Script Content box updates the matching form widgets,
  and opening a job from History reconstructs the whole form, including expanding hidden
  sections, from the script's scheduler directives.
- **Empty-script submission warning** (`empty_script_warning`) — asks for confirmation before
  submitting a script that contains only blank lines, comments, scheduler directives and
  `module` lines.
- **New manifest keys** `hidden`, `documentation` and `tags`.

#### History page

- **`sacct` is now the source of truth** for which jobs exist; the SQLite database only enriches
  those rows with Open Composer metadata. Jobs submitted outside Open Composer therefore appear
  in History too — their script is fetched live with `sacct -B`, and **Load script** imports it
  into the generic form named by `external_reload_app`.
- **Job Efficiency panel** (`history_efficiency`, default `false`) — Wall Time, CPU, Memory and,
  for GPU jobs, GPU utilisation and GPU memory, in the job details modal for finished jobs.
  New route `GET /history/job_efficiency`, using `sacct --json` (requires Slurm 20.11+).
- **Live job details** — the details modal is fetched on open, from `scontrol show job --json`
  for queued/running jobs and `sacct` for finished ones, with a collapsible **Source:** section
  disclosing the exact command that was run.
- **`history_store_script`** — set to `false` to keep script text out of the database and always
  fetch it live with `sacct -B`.
- **Output / Error columns** (`OC_HISTORY_OUTPUT_FILE`, `OC_HISTORY_ERROR_FILE`) with an in-page
  file viewer (`GET /_read_file`); files over 1 MB are truncated with a warning.
- **Cancel All Jobs** and **Delete All History** actions, plus **Refresh**, with progress
  reporting and an abort control. New route `GET /history/active_job_ids`.
- **`squeue` supplement** so freshly queued jobs appear before `sacct` reports them.
- **Per-column ascending/descending sort links** driven by `sort` and `order` query parameters.
- **Cancelled and Unknown status filters**, alongside Queued/Running/Completed/Failed.

#### Nodes page

- **Per-cluster selector** when more than one cluster is configured.
- **Command disclosure** — an ⓘ button reveals the exact `sinfo` command the page is built
  from, so users can reproduce it in a terminal.
- **State summary badges** above the table, and a **"Fetched at …"** timestamp with a Refresh
  link (the page does not poll).
- The node search box matches node name, state, CPU and memory figures, and GRES type names.

#### Job submission

- **Automatic SSH key provisioning** (`ensure_ssh_key`, `ssh_key_type`, `ssh_key_name`;
  disabled by default) — on Submit, if the user has no usable SSH key, Open Composer generates
  a passphrase-less key, appends its public half to `~/.ssh/authorized_keys`, and appends a
  `Host *` / `IdentityFile` stanza to `~/.ssh/config` so `ssh_wrapper` submission does not
  prompt for a password. Existing keys are never overwritten; failures are logged but do not
  block submission.
- **`scheduler_env` and `copy_environment`** adopted from upstream v2.0.1 and wired through
  this fork's submit, cancel and per-job cancel paths.
- **`modules_list_url`** — the JSON module catalogue behind the `module_load` and
  `dependent_module_select` widgets and the automatic GPU badge is now configurable, and
  empty by default. Previously the URL was a hard-coded constant, so the feature could not
  be pointed at a site's own catalogue or turned off.

#### Navbar, branding & layout

- **Configurable navbar items** — the label and icon of the File/Home Directory, Shell Access,
  and Return to OnDemand links are now set in `conf.yml.erb`
  (`home_directory_label`/`_icon`, `shell_access_label`/`_icon`, `open_ondemand_label`/`_icon`),
  plus `open_ondemand_new_tab` to open the link in the same tab.
- **Search box** can be shown/hidden (`show_search`) and now sits on the right of the navbar.
  It searches every template by name, category and description — hidden applications and your
  own saved templates included.
- **`app_title_color` and `app_description_text_color`** — the application title and its
  description on the application page can each be coloured independently of the rest of the
  band. Both default to `description_text_color`, so existing configurations are unaffected.
- **`favicon`**, **footer brand logo** (`footer_brand_logo`/`footer_brand_url`/`footer_brand_alt`,
  replacing the fixed OnDemand logo), an **app description** blurb (`app_description`), and a
  **separator** under the top bar (`show_navbar_separator`/`navbar_separator_color`) are all
  configurable, along with `show_navbar_logo`, `footer_padding`, `footer_ood_logo` and
  `footer_logo_height`.
- **Return to OnDemand / navbar logo** auto-derive to `<this host>/pun/sys/dashboard` when
  `open_ondemand_url` is unset, so no per-site URL is required.
- **Multiple categories per app** — a manifest `category` may be a list; the app then shows one
  badge per category on the All Templates page, in the New Script picker and in search results.
  (The home-page grid still groups on the whole value, so prefer a single string there.)

### Changed

- **History database migrated to a 7-column V3 schema**, with deletions recorded as tombstones
  in a separate `<cluster>_deleted.sqlite3`. V1 and V2 databases migrate automatically on first
  open.
- The generic per-scheduler script templates moved to `generic_apps_dir`, reachable at
  `/_generic/<directory>` and used as the fallback when an application's `form.yml` is missing.
- **`conf.yml.erb.sample` reorganised into ten numbered sections** — Required, Cluster & job
  scheduler, SSH key provisioning, Data & modules, Templates & scripts, History, Form behaviour,
  Navigation bar, Appearance, Footer — ordered from what must be set for Open Composer to run at
  all through to what is purely cosmetic. Section 2 of `docs/install.html` now uses the same
  groups in the same order, so the file and the document can be read side by side. No setting,
  value or default changed.
- The user manual gained a **"Submitting"** section covering the two things that can happen when
  Submit is pressed — the empty-script confirmation dialog and first-time SSH key provisioning —
  which were previously described only in the installation and application-author documents.

### Fixed

- **Shell Access navbar link** was gated on the wrong setting (`show_home_directory`) and had a
  hard-coded label, so `show_shell_access` had no effect. It now honours `show_shell_access`,
  `shell_access_label` and `shell_access_icon`.
- **`OC_HISTORY_PARTITION` and `OC_HISTORY_SUBMISSION_TIME` rendered as permanently empty
  columns.** Both are in the default `history` set, so any site that omitted `history:` from
  `conf.yml.erb` got two blank columns headed by the raw variable name. They now have real
  column definitions: Partition is carried through from the scheduler's job record, Submission
  Time uses the stored submission timestamp, and both are sortable.
- **`scheduler_env` only reached job submission, cancellation and status queries.** The
  History page, Nodes page, job details modal, Job Efficiency report and batch-script
  retrieval all ran without it, so a configless Slurm site could submit jobs while those
  pages returned nothing. Every scheduler command now receives it.
- **`sge_root` was exported only while handling a POST request**, so the GET-driven History
  and Nodes pages ran `qstat`/`qacct`/`qhost` without `SGE_ROOT`. It is now exported on every
  request (still never overriding a value already in the environment).
- **A manifest `category` given as a list produced one home-page section whose heading was
  the list rendered as a Ruby array literal.** The application is now listed under each of
  its categories, on both the home page and the New Custom Template picker.
- **`dependent_module_select` values were not available to the `check` section**, leaving the
  corresponding `@` variable `nil`. They are now passed through like `module_load` values.
- **The application title was unreadable on the application page.** The title inherited a
  heading colour from the surrounding theme rather than the band's own text colour, so it
  rendered dark on the coloured `description_color` band while the description beside it was
  light. The colour is now applied to the heading directly, via `app_title_color`.
- **The Shell Access navbar link was rendered even with no `login_node` configured**,
  producing a link to an empty host. It is now hidden unless a login node is known, matching
  the equivalent links on the application and history pages.
- **`description_color` and `footer_color` were documented with a fixed hex default.** Both
  actually fall back to another setting — `category_color` and `navbar_color` respectively — so
  recolouring the category headers or the navigation bar silently recolours them too. The
  documented defaults now state the fallback.
- **Script Content box not updating** when changing widgets on a template form.
- **Syntax-highlight overlay misaligned** with the typed text in the embedded editor.
- **"Show advanced CPU options" (and similar toggles) wrongly auto-ticked when loading a script.**
  A hidden section is now expanded only by a directive line **unique** to it (e.g. the advanced CPU
  section's `#SBATCH --cpus-per-task=`), never by a line it shares with a visible field (e.g.
  `#SBATCH --ntasks=`). Applied to both the client-side parser (`parseScriptToWidgets`) and the
  server-side sacct -B parser (`parse_sbatch_into_cache`).

## [2.1.0] - 2026-06-01

### Added

#### My Templates

- **"My Templates" section on the home page** — saved templates are shown as thumbnails in the same
  grid style as regular apps, using the source app's own icon. Clicking a template opens its source
  app form pre-filled with the saved values.
- **Save as Template** button on any application form. Saves the current form values, the source
  app path, and the app icon into a YAML file under `{data_dir}/templates/`.
- **Save button** (replaces "Save as Template") when a template has been loaded into the form —
  overwrites the stored values without prompting for a name again.
- **Edit (pencil) button** on each template thumbnail — opens an inline modal to rename the
  template or update its description without leaving the home page.
- **Delete (×) button** on each template thumbnail — deletes the template after a confirmation prompt.
- New routes: `POST /templates`, `POST /templates/:slug/overwrite`,
  `POST /templates/:slug/rename`, `POST /templates/:slug/delete`.

#### Nodes page

- **Dynamic GRES columns** — the Nodes table automatically discovers every GRES type reported
  by the scheduler (e.g. `gpu`, `nvme`) and creates one column per type. No static column
  configuration is needed.
- GRES columns are displayed in **alphabetical order**.
- Each GRES cell shows **available / total** resource counts with the existing resource-bar style,
  broken out by subtype (e.g. `A100`, `H100`).
- Removed the **Type** and **Arch** filter checkboxes from the Nodes page.

#### History page

- **One-by-one job cancellation** — "Cancel Job" now issues one `scancel` call per selected job
  instead of a single bulk call.
- An **animated Bootstrap progress bar** (`X / N jobs`) is shown inside the cancel modal while
  cancellation is running.
- On full success the bar turns green and the page auto-reloads after one second. On partial
  failure the bar turns yellow and each error is listed.
- New route: `POST /history/cancel_one` — cancels a single job and returns JSON
  `{ok: true}` / `{ok: false, error: "..."}`.

### Fixed

- Clicking "Save" to overwrite a template no longer discards content that was already entered in the
  form. Previously, saving would clear fields the user had filled in; now the existing form values are
  preserved correctly.

## [2.0.1] - 2026-07-10

> Upstream release, merged into this line after 3.0.0 was cut — hence the out-of-order date.
> Everything below is included in 3.0.0.

### Added

- Allow custom values to be entered in multi_select widgets, in addition to the predefined suggestions.
- Add a `scheduler_env` setting in conf.yml to customize environment variables passed to scheduler commands.
- Add a `copy_environment` setting for Slurm to control whether `--export=ALL` or `--export=NONE` is used.

### Changed

- Disable spellcheck on generated form inputs and filter inputs.
- Shorten the Slurm configless host example in the documentation and sample conf.yml.
- Prefix internal history columns with underscores to avoid conflicts with user-defined history fields.

### Fixed

- Fix a modal that could fail to show job details on the history page in [31](https://github.com/RIKEN-RCCS/OpenComposer/issues/31).
- Fix history not updating immediately after canceling a job.
- Fix caching conflicts caused by internal history keys.
- Fix a SyntaxError that could break the Script Content editor layout when multiple multi_select widgets retained submitted values after a failed job submission.

## [2.0.0] - 2026-05-11

### Add

- Add side-by-side syntax highlighting overlays for the script and submit textareas.
- Add configurable `highlight_theme` and `directive_color` settings for history/script highlighting.
- Add advanced history search options for date range, AND/OR matching, and field selection.
- Add history search elapsed-time output next to the entry count.

### Changed

- Change history storage from PStore to SQLite with automatic migration from legacy `.db` files.
- Expand history search to index all stored job values, including Job Details and Job Script contents.
- Improve history search highlighting so it follows AND/OR search terms and the selected field.

### Fix

- Fix initialization error in Dynamic Form Widget

## [1.9.0] - 2026-03-20

### Add

- A warning will be displayed before manual changes to the script and submit sections are deleted.
- Support OC_ROUNDING_ROUND, OC_ROUNDING_FLOOR, and OC_ROUNDING_CEIL in calc().
- Local Development is added in install manual.

### Changed

- RACK is used for development.
- Improve README to match Appverse documentation standard in [18](https://github.com/RIKEN-RCCS/OpenComposer/issues/28).

## [1.8.0] - 2025-12-26

### Add

- Add the function to define multiple login_nodes and ssh_wrappers in conf.yml in [25](https://github.com/RIKEN-RCCS/OpenComposer/discussions/25).
- Add calc function in [20](https://github.com/RIKEN-RCCS/OpenComposer/pull/20).
- History page items can be freely changed in [19](https://github.com/RIKEN-RCCS/OpenComposer/pull/19).
- Add failed job status in [19](https://github.com/RIKEN-RCCS/OpenComposer/pull/19).
- The cancel/delete modal and job script modal on the history page can be resized in [19](https://github.com/RIKEN-RCCS/OpenComposer/pull/19).
- Add a variable @OC_DIR_NAME.

### Changed

- Change clusters from cluster in conf.yml (It is an incompatible change).
- Change related_apps from related_apps in manifest.yml (It is an incompatible change).
- Changed dirname and basename to work the same as linux commands.
- Change a variable OC_SCRIPT_CONTENT from SCRIPT_CONTENT.

### Fixed

- Do nothing if expr returns an error.

## [1.7.0] - 2025-11-06

### Add

- The function only saves job scripts.
- The function allows users to view and edit preprocessing.

### Changed

- Manual format changed from Markdown to HTML.

### Fixed

- An error occurs when you first open the History page in [18](https://github.com/RIKEN-RCCS/OpenComposer/pull/18).
- An issue where variables could not be referenced in the submit and check sections.
- An error where the separator was not reflected when using an array as the second argument in the options of checkbox and multi_select widgets.
- An error that disabled elements could not be referenced on the initial screen.

## [1.6.0] - 2025-10-19

### Add

- The function for zeropadding.
- The function to output log.
- The custom PBS Pro scheduler for Miyabi.

### Changed

- Change the manual format from Markdown to HTML.
- Change "cancel job" from "delete job" in history page.
- The name of the page from Top Page to Home Page.

### Fixed

- The initial value was not set correctly when the value was a number.
- Consolidate querying both running and history jobs in PBS Pro in [9](https://github.com/RIKEN-RCCS/OpenComposer/pull/9).
- PBS Pro qstat bug in [8](https://github.com/RIKEN-RCCS/OpenComposer/pull/8).

## [1.5.0] - 2025-05-08

### Add

- Add highlights to filtered results in history page.
- Support multiple clusters.

### Changed

- Filter in history page searches all job information.

### Fixed

- Sanitization for XSS.

## [1.4.0] - 2025-04-08

### Added

- Support to set a main label and a sub-label.
- Support to hide job scripts.
- Dynamic Form Widget is also enabled in the header.
- Add icons such as Open OnDemand to the navigation bar.
- Add an effect for submit button.
- Add a function oc_assert() which can be used in form.yml.

### Changed

- For slurm, remove init_bash and added --export=NONE to the sbatch option.
- For slurm, PBSpro and Fujitsu TCS, increase the amount of verbose output.
- On the history page, when you hover the cursor over the image of a visualization app, the name of the application is displayed.
- On the history page, adjust the amount of information depending on the window width.
- Change width when script content is hidden from 800px to 960px.
- Adjust the amount of information displayed in the history depending on the window width.
- Change the command from Cancel Job to Delete Job.
- Display error messages more clearly in form.

### Fixed

- A reference so that it works even if the destination of related_app in manuscript is a link.

## [1.3.0] - 2025-02-12

### Added

- Support Grid Engine job scheduler.
- It is possible to define headers for each application.
- For pre-processing, submit section in form.yml is added. And delete submit.yml.
- Added the ability to change the script label.
- The path widget can specify the directory one level above.
- It is possible to define headers for each application.

### Changed

- Change path selector modal overflow behavior in [1](https://github.com/RIKEN-RCCS/OpenComposer/pull/1)
- To speed up the history page, update the status only for the job IDs that are displayed.
- The separator option enables output without spaces.
- To prevent elements that are initially hidden from appearing for just a moment, make them visible after all loading is complete.

### Fixed

- Fixed behavior of the path widget with or without a slash at the end of a directory.

## [1.2.0] - 2025-01-20

### Added

- Support PBS job scheduler.
- Add bin_overrides in conf.yml.erb.
- Add a utility misc/read_yml_erb.rb.

### Changed

- login_node in conf.yml.erb has been made optional.
- Simplify `ident` parameter.
- When a job scheduler error occurs, output stdout as well as stderr.
- Get the job submission date and time from a Ruby function, not from the scheduler.

### Fixed

- Fixed a mistake in the application name link on the form.
- Element with disabled is considered unchecked.
- When the selected option in select widget becomes disabled by dynamic form widget, the non-disabled option is selected.
- Fixed an issue where the disable- and hide- options for radio and checkbox widgets did not work properly when there was more than one option.

## [1.1.0] - 2025-01-09

### Added

- Added `ident` parameter in the web form.
- Enabled setting related applications.
- Added support for Font Awesome icons.
- Included English documents.
- Introduced a function to specify an application directory.
- Added an option to include the value of "Job Name" in the header as part of the job submission command.

### Changed

- Divided the manual into sections for creating web forms and using Open Composer.
- Extended the inquiry period for completed Fujitsu_TCS jobs to 365 days.
- Improved error handling: when job submission fails, the same page reloads with the failed parameters pre-filled.
- Updated manual examples: replaced `job_name` examples with `comment` examples to reduce confusion.
- Made labels bold for better visibility.
- Made application names in forms bold.
- Ensured that changes in header values do not update `JOB_SCRIPT_CONTENTS`.

### Fixed

- Fixed the issue with loading the bash environment when executing `pjsub`/`sbatch` commands.
- Resolved the issue where `public/no_image_square.jpg` could not be displayed.

### Security

- Applied URL encoding for special characters on the history page to enhance security.

## [1.0.0] - 12-11-2024

First release.
