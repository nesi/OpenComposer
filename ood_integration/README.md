# Open OnDemand Integration

This directory contains files that embed Open Composer inside the Open OnDemand (OOD) interface.

When installed, clicking the **Open Composer** app tile in OOD opens it embedded within the OOD page — OOD's navigation bar stays at the top, Open Composer's interface runs in a full-height iframe below it, and OOD's own footer is visible at the bottom — rather than opening in a new window or tab.

## Contents

| File | Purpose |
|------|---------|
| `initializers/opencomposer_embed.rb` | Intercepts `AppsController#show` for Open Composer and renders the embed view instead of the default redirect |
| `views/apps/opencomposer_embed.html.erb` | Full-height iframe view rendered within OOD's own layout |

## Requirements

- Open OnDemand 3.x or later
- Open Composer deployed as a sys app at `/var/www/ood/apps/sys/opencomposer/`
- Administrator access to `/etc/ood/config/`

## How it works

OOD's dashboard app supports custom Rails initializers placed in `/etc/ood/config/apps/dashboard/initializers/`. The initializer `opencomposer_embed.rb` uses Ruby's `prepend` to intercept the `AppsController#show` action. When the Open Composer tile is clicked, instead of redirecting the user to the app at `/pun/sys/opencomposer/`, OOD renders `opencomposer_embed.html.erb` — a view containing a full-height `<iframe>` that loads Open Composer inside the existing OOD page.

A small JavaScript block measures the heights of OOD's navbar and footer after the page has loaded and positions the iframe container so both remain fully visible.

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

# Hide Open Composer's own footer — OOD's footer is shown below the iframe
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

## Content Security Policy (CSP)

If Open Composer is served from a different origin than OOD's main page (for example when testing locally with Docker where OOD runs on port 443 but you access it via port 8080), the browser may block the iframe with an error such as:

```
Refused to display '...' in a frame because an ancestor violates the
following Content Security Policy directive: "frame-ancestors https://localhost;"
```

To fix this, add your origin to the `frame-ancestors` directive in `/etc/httpd/conf.d/ood-portal.conf`:

```apache
Header always set Content-Security-Policy "frame-ancestors https://your-ood-host https://your-ood-host:8080;"
```

Then reload Apache:

```sh
sudo httpd -k graceful
```

In production OOD deployments where the browser accesses OOD on the standard HTTPS port (443), both the outer page and the iframe share the same origin and the default CSP is fine.

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
- Patches the OOD Apache CSP to allow iframe embedding from the host browser

```sh
cd docker_open_ondemand/ondemand-compose
docker-compose build
docker-compose up -d
```

Open `https://localhost:8080` in your browser (accept the self-signed certificate) and log in as `hpc.user` / `ilovelinux`.

> **Apple Silicon (ARM64):** The Slurm compute node Dockerfile downloads an AMD64 TurboVNC package by default. Change `amd64` to `arm64` on lines 22–25 of `docker_open_ondemand/ondemand-compose/slurm-compute-node-1/Dockerfile` before building.

After making any change to Open Composer files in the Docker environment, run **Help → Restart Web Server** inside OOD to clear Passenger's view cache.
