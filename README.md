# Open Composer

## Overview

Open Composer is a web application to generate batch job scripts and submit batch jobs for HPC clusters on [Open OnDemand](https://openondemand.org/).

Open Composer is an Open OnDemand app in the "Jobs" category. Unlike Batch Connect interactive apps, Open Composer provides a graphical interface for creating, previewing, editing, and submitting batch job scripts. It supports multiple job schedulers and can be configured for different HPC applications.

- **App type:** Workflow Composer (Jobs category)
- **Latest release:** [`v2.1.0`](https://github.com/RIKEN-RCCS/OpenComposer/releases/tag/v2.1.0) (see [Changelog](CHANGELOG.md))
- **License:** MIT (see [LICENSE file](https://github.com/RIKEN-RCCS/OpenComposer/blob/main/LICENSE))
- **Requirements:** Open OnDemand 3.0 or later
- **Supported job schedulers:** Slurm, PBS Pro, Grid Engine, Fujitsu TCS

## Features

- Graphical web interface for generating and submitting batch job scripts
- Multi-scheduler and multi-cluster support
- Job history page with filtering, status tracking, and job cancellation
- One-by-one job cancellation with an animated in-modal progress bar
- Editable job script preview before submission
- Configurable application forms via `form.yml`
- Dynamic form widgets with conditional visibility and validation
- Support for preprocessing steps via submit sections
- Customizable per-application headers and labels
- Path selector widget for file and directory selection
- My Templates — save, manage, and reuse form configurations
- Nodes page with dynamic GRES columns auto-discovered from the scheduler
- Navbar search bar for quickly finding templates by name, category, or description
- Fully customisable navbar and footer (colours, logo, links — see [Configuration](#configuration))
- **OOD-integrated mode** — embed Open Composer inside the OOD chrome so users never leave the OOD interface (see [OOD Integration](#ood-integration))
- Bilingual documentation (English and Japanese)

## Deployment Modes

Open Composer supports two deployment modes. Choose the one that fits your site.

### Mode 1 — Standalone app (default)

Open Composer opens in its own tab/window when a user clicks the app tile. This is the standard OOD app behaviour and requires no extra configuration beyond installing the app itself.

Use `conf.yml.erb.app.example` as your starting point:

```sh
cd /var/www/ood/apps/sys/
sudo git clone https://github.com/RIKEN-RCCS/OpenComposer.git opencomposer
cd opencomposer
sudo cp conf.yml.erb.app.example conf.yml.erb
# Edit conf.yml.erb for your site
```

In standalone mode the full navbar is shown by default — Home Directory link, Shell Access, Return-to-OOD button, logo, and the Templates dropdown.

### Mode 2 — OOD-integrated (embedded)

Open Composer opens **inside** the OOD page when a user clicks the tile — OOD's own navigation bar stays at the top, Open Composer's interface appears in a full-height iframe below it, and OOD's footer is visible at the bottom. No separate tab or window is opened.

This mode requires two extra files to be installed on your OOD server and uses a streamlined `conf.yml.erb` that hides navbar elements OOD already provides (home directory, shell, return-to-OOD link, footer).

See [OOD Integration](#ood-integration) below for full installation instructions.

## Screenshots

### Home page

<img width="600" style="border: 1px solid #333;" alt="Home" src="https://riken-rccs.github.io/OpenComposer/docs/img/home_page.png">

### Application page

<img width="600" style="border: 1px solid #333;" alt="Application" src="https://riken-rccs.github.io/OpenComposer/docs/img/application_page.png">

### History page

<img width="600" style="border: 1px solid #333;" alt="History" src="https://riken-rccs.github.io/OpenComposer/docs/img/history_page.png">

## Documents

Full documentation (installation, application settings, user manual):

<table>
  <tr>
    <td>Installation for administrator</td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/install.html" target="_blank">EN</a></td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/install_ja.html" target="_blank">JA</a></td>
  </tr>
  <tr>
    <td>Application Settings for administrator</td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/application.html" target="_blank">EN</a></td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/application_ja.html" target="_blank">JA</a></td>
  </tr>
  <tr>
    <td>User Manual</td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/manual.html" target="_blank">EN</a></td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/manual_ja.html" target="_blank">JA</a></td>
  </tr>
</table>

## Quick Start

### Standalone app

The following steps assume administrator privileges. If you do not have administrator privileges, see [Section 4. "Installation by general user"](https://riken-rccs.github.io/OpenComposer/docs/install.html#general) in the installation document.

```sh
cd /var/www/ood/apps/sys/
sudo git clone https://github.com/RIKEN-RCCS/OpenComposer.git opencomposer
cd opencomposer
sudo cp conf.yml.erb.app.example conf.yml.erb
# Edit conf.yml.erb for your site — see Configuration below
```

Then reload the OOD dashboard (**Help → Restart Web Server**). Open Composer will appear in the **Jobs** category.

For full details see [Section 2. "Setting"](https://riken-rccs.github.io/OpenComposer/docs/install.html#setting) in the installation manual.

### OOD-integrated (embedded) mode

See [OOD Integration](#ood-integration) below.

## Configuration

All configuration lives in `conf.yml.erb`. The file `conf.yml.erb.app.example` ships as a fully-commented reference for standalone deployments; `conf.yml.erb` is tuned for OOD-integrated mode with elements OOD already provides turned off.

### Required

| Key | Description |
|-----|-------------|
| `apps_dir` | Path to the directory containing application folders. Relative paths are from the Open Composer root. |
| `scheduler` | Scheduler type: `slurm`, `pbspro`, `sge`, `miyabi`, or `fujitsu_tcs`. Use inside a `clusters:` block for multi-cluster sites. |

### General

| Key | Default | Description |
|-----|---------|-------------|
| `data_dir` | `~/composer` | Per-user data directory (templates, job history DB). |
| `login_node` | — | Hostname or `{label: hostname}` map used for Shell Access links. |
| `ssh_wrapper` | — | Custom SSH command for shell links. |
| `bin` | `/usr/bin` | Directory containing scheduler binaries. |
| `bin_overrides` | — | Override paths for individual scheduler binaries (`sbatch`, `scontrol`, etc.). |
| `generic_apps_dir` | `./generic_apps` | Directory for hidden generic scheduler templates. |
| `external_reload_app` | — | Subfolder in `generic_apps_dir` used when reloading an external job from History. |

### History

| Key | Default | Description |
| --- | ------- | ----------- |
| `history_store_script` | `true` | Store the submitted batch script in the DB. Set to `false` to always re-fetch via `sacct -B`. |
| `history_efficiency` | `false` | Show a **Job Efficiency** section (Wall Time, CPU, Memory, optional GPU) in the job details modal for completed, failed, and cancelled jobs. Uses `sacct --json`, which requires Slurm 20.11+. Set to `true` to enable. |
| `history` | — | Map of extra columns for the History page. Each key is an env variable name; `label:` sets the column header. |

### Layout

| Key | Default | Description |
|-----|---------|-------------|
| `home_format` | `"big"` | Home page tile layout: `"big"` or `"small"`. |
| `thumbnail_width` | `"100"` | Width (px) of app thumbnails on the home page. |
| `highlight_theme` | `"vs"` | Syntax-highlighting theme for the script editor. Any [highlight.js theme](https://highlightjs.org/demo) name. |
| `directive_color` | `"#001C36"` | Colour applied to scheduler directive lines in the script editor. |
| `navbar_color` | `"#FFFFFF"` | Navbar background colour. |
| `navbar_text_color` | `"#191919"` | Navbar text and link colour. |
| `dropdown_color` | `"#FFFFFF"` | Dropdown menu background colour. |
| `dropdown_text_color` | `"#191919"` | Dropdown menu text colour. |
| `category_color` | `"#FFFFFF"` | App-category card background colour. |
| `category_text_color` | `"#191919"` | App-category card text colour. |
| `description_color` | `"#FFFFFF"` | App description area background. |
| `description_text_color` | `"#191919"` | App description area text colour. |
| `form_color` | `"#F3F4F4"` | Form background colour. |
| `non_script_color` | `"#FFFFFF"` | Non-script section background. |
| `non_script_button_color` | `"#00B9E4"` | Non-script section button colour. |
| `submit_color` | `"#EBF8FD"` | Submit section background. |
| `submit_button_color` | `"#25545E"` | Submit section button colour. |
| `history_action_color` | `"#DC3545"` | Colour for history action buttons (e.g., cancel). |

### Footer

| Key | Default | Description |
|-----|---------|-------------|
| `show_footer` | `true` | Set to `false` to hide Open Composer's own footer entirely (recommended in OOD-integrated mode — OOD's footer is shown instead). |
| `footer` | — | HTML string for the footer's right-hand side (copyright, links, etc.). |
| `footer_color` | `"#191919"` | Footer background colour. |
| `footer_text_color` | `"#FFFFFF"` | Footer text colour. |
| `footer_padding` | `"p-3"` | Bootstrap padding class (`p-1` … `p-5`). |
| `footer_ood_logo` | `true` | Show the "Powered by Open OnDemand" logo in the footer. Set to `false` to hide it. |
| `footer_logo_height` | `"50px"` | Height of the OOD logo in the footer. |

### Navbar links

| Key | Default | Description |
|-----|---------|-------------|
| `navbar_logo` | — | Filename of a logo image inside `public/` (e.g. `"mysite_logo.svg"`). When set, the logo appears at the left of the navbar and links to `open_ondemand_url`. Set to `~` (null) to hide. |
| `show_navbar_apps` | `true` | Show the **Templates** dropdown menu in the navbar, listing all available application templates. Set to `false` when the home-page tile grid already shows them or when running in OOD-integrated mode. |
| `navbar_apps_label` | `"Applications"` | Label for the templates dropdown. |
| `navbar_search_placeholder` | `"Search apps…"` | Placeholder text for the navbar search box. |
| `show_home_directory` | `true` | Show a **Home Directory** icon-link in the navbar that opens the OOD file browser. |
| `show_shell_access` | `true` | Show a **Shell Access** icon-link in the navbar that opens an SSH session in the OOD shell app. Requires `login_node` to be set. If `login_node` is a map with multiple entries a dropdown is shown. |
| `show_open_ondemand` | `true` | Show a **Return to OOD** link in the navbar. |
| `open_ondemand_url` | — | URL for the Return-to-OOD link and the navbar-logo link. |
| `open_ondemand_label` | `"Open OnDemand"` | Label for the Return-to-OOD link. |

## OOD Integration

The `ood_integration/` directory contains two files that embed Open Composer inside the OOD interface. When installed, clicking the **Open Composer** tile opens the app within the OOD page — OOD's navbar stays at the top and Open Composer runs in a full-height iframe below it.

For full installation steps and troubleshooting, see [ood_integration/README.md](ood_integration/README.md).

### Quick install (OOD-integrated mode)

**1. Install Open Composer as a sys app** (if not already done):

```sh
cd /var/www/ood/apps/sys/
sudo git clone https://github.com/RIKEN-RCCS/OpenComposer.git opencomposer
cd opencomposer
sudo cp conf.yml.erb.app.example conf.yml.erb
# Edit conf.yml.erb — see ood_integration/README.md for recommended settings
```

**2. Copy the OOD integration files:**

```sh
sudo mkdir -p /etc/ood/config/apps/dashboard/initializers
sudo mkdir -p /etc/ood/config/apps/dashboard/views/apps

sudo cp /var/www/ood/apps/sys/opencomposer/ood_integration/initializers/opencomposer_embed.rb \
        /etc/ood/config/apps/dashboard/initializers/

sudo cp /var/www/ood/apps/sys/opencomposer/ood_integration/views/apps/opencomposer_embed.html.erb \
        /etc/ood/config/apps/dashboard/views/apps/
```

**3. Restart the OOD web server:** **Help → Restart Web Server** in the OOD dashboard.

Clicking the Open Composer tile will now open it embedded within OOD.

## Local Testing with Docker

A self-contained OOD environment is included under `docker_open_ondemand/` for testing before deploying to production. It runs a local OOD instance with a Slurm compute node and auto-mounts the Open Composer app.

```sh
cd docker_open_ondemand/ondemand-compose
docker-compose build
docker-compose up -d
```

Then open `https://localhost:8080` in your browser (accept the self-signed certificate) and log in as `hpc.user` / `ilovelinux`.

See the notes in `docker_open_ondemand/` for ARM64 (Apple Silicon) requirements and the CSP patch needed to allow iframe embedding.

## Testing

| System      | Site       | Scheduler          | Repository |
|-------------|------------|--------------------|-----------|
| Fugaku      | RIKEN RCCS | Fujitsu TCS, Slurm | [composer_fugaku](https://github.com/RIKEN-RCCS/composer_fugaku) |
| R-CCS Cloud | RIKEN RCCS | Slurm              | [composer_rccs_cloud](https://github.com/RIKEN-RCCS/composer_rccs_cloud) |

## Contributing

For discussions, see the [GitHub Discussions](https://github.com/RIKEN-RCCS/OpenComposer/discussions).

## Troubleshooting

For bugs or feature requests, [open an issue](https://github.com/RIKEN-RCCS/OpenComposer/issues) with detailed logs and reproduction steps.

## Reference

If you use this software in your research or development work, please cite the following publication:

> Masahiro Nakao and Keiji Yamamoto. 2025. "Open Composer: A Web-Based Application for Generating and Managing Batch Jobs on HPC Clusters". In Proceedings of the SC '25 Workshops of the International Conference for High Performance Computing, Networking, Storage and Analysis (SC Workshops '25). ACM, New York, NY, USA, 697-704. [https://doi.org/10.1145/3731599.3767428](https://doi.org/10.1145/3731599.3767428)

## Presentation

- [HUST: International Workshop on HPC User Support Tools](https://hust-workshop.github.io), St. Louis, USA, Nov. 2025 [[Paper](https://doi.org/10.1145/3731599.3767428)] [[Slide](https://www.mnakao.net/data/2025/HUST2025.pdf)]
- [SupercomputingAsia 2025](https://sca25.sc-asia.org/), Singapore, Mar. 2025 [[Poster](https://mnakao.net/data/2025/sca.pdf)]
- [The 197th HPC Research Symposium](https://www.ipsj.or.jp/kenkyukai/event/arc251hpc197.html), Fukuoka, Japan, Dec. 2024 [[Paper](https://mnakao.net/data/2024/HPC197.pdf)] [[Slide](https://mnakao.net/data/2024/HPC197-slide.pdf)] (Japanese)

## Known Limitations

No major limitations are currently known.

## Acknowledgments

The authors thank the Open OnDemand community for providing a robust ecosystem for HPC web applications.
Development of Open Composer has been carried out at [RIKEN R-CCS](https://www.r-ccs.riken.jp/en/), with significant contributions from [RIST](https://www.rist.or.jp/ehome.html).
