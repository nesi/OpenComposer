# Open OnDemand Integration

This directory contains files that embed Open Composer inside the Open OnDemand (OOD) interface.

When installed, clicking the **Open Composer** app tile in OOD opens it embedded within the OOD page — OOD's navigation bar stays at the top, Open Composer's interface fills the middle, and OOD's own footer is visible at the bottom — rather than opening in a new window or tab. The page is a single document rendered in OOD's real layout, so the header and footer are OOD's live chrome (dynamic menus, user/help dropdowns, notifications).

## Contents

| File | Purpose |
| --- | --- |
| `initializers/opencomposer_embed.rb` | Mounts a reverse-proxy controller at `/pun/sys/dashboard/oc(/*path)` and intercepts `AppsController#show` for Open Composer to land there |
| `views/apps/opencomposer_embed.html.erb` | Splices Open Composer's `<head>` assets and `<body>` content into OOD's dashboard layout |
| `dashboard.env.example` | Commented template of the `OC_EMBED_*` settings, for the dashboard's env file |
| `ADMIN_CHECKLIST.md` | Deployment & security-review checklist to hand to an OOD administrator |

## Requirements

- Open OnDemand 3.x or later
- Open Composer deployed as a sys app at `/var/www/ood/apps/sys/opencomposer/`
- Administrator access to `/etc/ood/config/`

## How it works

OOD's dashboard app supports custom Rails initializers placed in `/etc/ood/config/apps/dashboard/initializers/`. The initializer `opencomposer_embed.rb`:

1. **Mounts a reverse proxy** at `/pun/sys/dashboard/oc(/*path)` inside the dashboard. Each request is forwarded to the real Open Composer app at `/pun/sys/opencomposer/...` over the loopback through Apache (on the same port the browser used), forwarding the user's OIDC session cookie so the call is authenticated as that user.
2. **Rewrites the path prefix.** Open Composer builds every URL from its Rack `script_name`, so the whole app self-references the single prefix `/pun/sys/opencomposer`. The proxy rewrites that to `/pun/sys/dashboard/oc` in every text response — links, form actions, assets and inline path variables — so every page, navigation and form submission stays on the proxy path and therefore stays wrapped in OOD's chrome. (Open Composer's own AJAX derives its base from `window.location.pathname`, so it follows the proxy path automatically.)
3. **Wraps HTML in OOD's layout.** For HTML responses the proxy splices Open Composer's `<head>` assets and `<body>` content into the dashboard's `application` layout via `opencomposer_embed.html.erb`, giving the live OOD navbar and footer. CSS/JS/JSON are streamed through (prefix-rewritten); images and fonts pass through unchanged. Redirects are relayed to the browser with their `Location` rewritten onto the proxy path.
4. **De-duplicates Bootstrap and isolates CSS.** OOD's dashboard and Open Composer both ship Bootstrap, and they share one page now:
   - *Bootstrap JS* — two copies each bind Bootstrap's click data-api, which makes OOD's navbar dropdowns toggle open-then-shut and never appear. The proxy strips Open Composer's Bootstrap `<script>` and lets OOD's single Bootstrap drive both apps (Open Composer's components are declarative `data-bs-*`); a tiny shim supplies `window.bootstrap.Modal` for the one imperative call (the history file-overlay).
   - *Bootstrap CSS* — Open Composer's stylesheet, loaded after OOD's, would override OOD's themed navbar/footer, so it is dropped too (OOD's Bootstrap styles Open Composer's markup).
   - *Open Composer's own inline CSS* — its global rules (`a`, `.nav-link`, `.btn-primary`, `.footer a`, `body`, …) are rewritten to apply only inside the embed container (`#oc-embed-root`) so they can't restyle OOD's chrome.

## Installation

### Step 1 — Install Open Composer as a sys app

If Open Composer is not already installed:

```sh
cd /var/www/ood/apps/sys/
sudo git clone https://github.com/RIKEN-RCCS/OpenComposer.git opencomposer
```

### Step 2 — Configure Open Composer for embedded mode

Copy the app example config as a starting point, then edit it:

```sh
cd /var/www/ood/apps/sys/opencomposer
sudo cp conf.yml.erb.app.example conf.yml.erb
sudo nano conf.yml.erb   # or your preferred editor
```

For OOD-integrated mode, set the following in `conf.yml.erb`:

```yaml
# Hide navbar elements that OOD already provides
show_home_directory: false   # OOD's Files menu links to the home directory
show_shell_access:   false   # OOD's Clusters menu provides shell access
show_open_ondemand:  false   # No need to link back to OOD from inside OOD
navbar_logo: ~               # OOD's navbar already shows the site logo

# Hide the Templates dropdown — the home page tile grid already shows them
show_navbar_apps: false

# Hide Open Composer's own footer — OOD's footer is shown instead
show_footer: false
```

All other settings (scheduler, clusters, data_dir, colours, etc.) follow the same `conf.yml.erb.app.example` reference — adjust for your site.

### Step 3 — Force same-tab navigation

By default OOD opens sys app tiles in a new tab. Add `new_window: false` to `manifest.yml` so clicking the tile stays in the same tab:

```yaml
# /var/www/ood/apps/sys/opencomposer/manifest.yml
name: Open Composer
category: Jobs
description: |
  Open Composer is an application that creates and submits batch job scripts.
icon: fas://hat-wizard
new_window: false
```

### Step 4 — Copy the integration files

```sh
sudo mkdir -p /etc/ood/config/apps/dashboard/initializers
sudo mkdir -p /etc/ood/config/apps/dashboard/views/apps

sudo cp /var/www/ood/apps/sys/opencomposer/ood_integration/initializers/opencomposer_embed.rb \
        /etc/ood/config/apps/dashboard/initializers/

sudo cp /var/www/ood/apps/sys/opencomposer/ood_integration/views/apps/opencomposer_embed.html.erb \
        /etc/ood/config/apps/dashboard/views/apps/
```

### Step 5 — Restart the OOD web server

In the OOD dashboard: **Help → Restart Web Server**

Or from the command line:

```sh
sudo httpd -k graceful
# or on systems using systemd:
sudo systemctl reload httpd
```

Clicking the Open Composer tile will now open it embedded within OOD.

## Configuration (other OOD sites)

All settings are optional and read from the dashboard's env file `/etc/ood/config/apps/dashboard/env`. The defaults work for a standard single-host OOD serving HTTPS on port 443 with Open Composer installed as the sys app `opencomposer`. See [`dashboard.env.example`](dashboard.env.example) for the full, commented template.

| Variable | Purpose | Default |
| --- | --- | --- |
| `OC_EMBED_APP_NAME` | Open Composer's sys-app directory name — the `<name>` in `/pun/sys/<name>` (the install directory, **not** the tile's display name). e.g. NeSI/Mahuika uses `slurm_composer`. | `opencomposer` |
| `OC_EMBED_UPSTREAM_HOST` | Hostname used for TLS SNI + the `Host` header on the upstream call. | the request's host |
| `OC_EMBED_UPSTREAM_PORT` | Port the proxy connects to. | the request's port |
| `OC_EMBED_UPSTREAM_SCHEME` | `http` or `https` for the upstream call. | the request's scheme |
| `OC_EMBED_UPSTREAM_IP` | IP actually connected to (TCP), independent of the SNI host — keeps the call on the loopback. Set empty to resolve the host via DNS instead. | `127.0.0.1` |

The `OC_EMBED_UPSTREAM_*` knobs exist so administrators can point the upstream call at whatever fronts their OOD — for example a TLS-terminating load balancer where the portal vhost listens on a plain-HTTP port. For a standard 443 host none of them are needed.

After editing the env file, restart the web server (**Help → Restart Web Server**, or `sudo systemctl reload httpd`).

## Uninstalling

Remove the two integration files and restart the web server:

```sh
sudo rm /etc/ood/config/apps/dashboard/initializers/opencomposer_embed.rb
sudo rm /etc/ood/config/apps/dashboard/views/apps/opencomposer_embed.html.erb
sudo httpd -k graceful
```

Open Composer will revert to its default behaviour (opening in a new tab).

## Local testing with Docker

A self-contained OOD environment is included under [`docker_open_ondemand/`](../docker_open_ondemand/) for testing this integration locally before deploying to production.

The Docker setup:

- Runs OOD and a Slurm compute node in containers
- Volume-mounts the Open Composer repo into the OOD container at `/var/www/ood/apps/sys/opencomposer/`
- On container start, `startup.sh` automatically copies the integration files from the mounted directory into `/etc/ood/config/apps/dashboard/`

```sh
cd docker_open_ondemand/ondemand-compose
docker-compose build
docker-compose up -d
```

Open `https://localhost:8080` in your browser (accept the self-signed certificate) and log in as user / password.

> **Apple Silicon (ARM64):** The Slurm compute node Dockerfile downloads an AMD64 TurboVNC package by default. Change `amd64` to `arm64` on lines 22–25 of `docker_open_ondemand/ondemand-compose/slurm-compute-node-1/Dockerfile` before building.

After making any change to Open Composer files in the Docker environment, run **Help → Restart Web Server** inside OOD to clear Passenger's view cache.
