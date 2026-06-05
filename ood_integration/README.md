# Open OnDemand Integration

This directory contains files that embed Open Composer inside the Open OnDemand (OOD) interface.

When installed, clicking the **Open Composer** app tile in OOD opens it embedded within the OOD page — with OOD's navigation bar at the top and Open Composer's own navigation bar inside the frame — rather than opening in a separate window.

## How it works

Two files override OOD's default app-tile behaviour for Open Composer specifically:

- **`initializers/opencomposer_embed.rb`** — intercepts the `AppsController#show` action for Open Composer and renders a custom view instead of the default redirect
- **`views/apps/opencomposer_embed.html.erb`** — renders Open Composer in a full-height iframe within OOD's own layout

## Installation

Copy both files to your OOD server:

```bash
# Create directories if they don't exist
mkdir -p /etc/ood/config/apps/dashboard/initializers
mkdir -p /etc/ood/config/apps/dashboard/views/apps

# Copy the files
cp ood_integration/initializers/opencomposer_embed.rb \
   /etc/ood/config/apps/dashboard/initializers/

cp ood_integration/views/apps/opencomposer_embed.html.erb \
   /etc/ood/config/apps/dashboard/views/apps/
```

Then restart the OOD web server: **Help → Restart Web Server** in the OOD UI.

## Requirements

- Open OnDemand 4.x
- Open Composer deployed as a sys app at `/var/www/ood/apps/sys/opencomposer/`

## Local testing with Docker

See [`docker_open_ondemand/`](../docker_open_ondemand/) for a local OOD environment you can use to test this integration before deploying to production.
