# Changelog

## [3.0.0] - 2026-06-11

### Added

#### Open OnDemand integration

- **OOD-integrated (embedded) mode** — Open Composer can render inside Open OnDemand's own
  chrome (live OOD navbar and footer) via a reverse-proxy dashboard initializer under
  `ood_integration/`, with no iframe. Toggleable per deployment; runs full-width.

#### Navbar, branding & layout

- **Configurable navbar items** — the label and icon of the File/Home Directory, Shell Access,
  and Return to OnDemand links are now set in `conf.yml.erb`
  (`home_directory_label`/`_icon`, `shell_access_label`/`_icon`, `open_ondemand_label`/`_icon`).
- **Search box** can be shown/hidden (`show_search`) and now sits on the right of the navbar.
- **`favicon`**, **footer brand logo** (`footer_brand_logo`/`footer_brand_url`/`footer_brand_alt`,
  replacing the fixed OnDemand logo), an **app description** blurb (`app_description`), and a
  **gradient separator** under the top bar (`show_navbar_separator`) are all configurable.
- **Return to OnDemand / navbar logo** auto-derive to `<this host>/pun/sys/dashboard` when
  `open_ondemand_url` is unset, so no per-site URL is required.
- **Multiple categories per app** — a manifest `category` may be a list; the app then appears
  under each category and shows a badge per category.

### Fixed

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
