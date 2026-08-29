# EverRise Auto Updater

A Home Assistant add-on that keeps the EverRise dashboard (frontend + the
`everrise_dashboard` backend bridge) up to date on every client's box,
without HACS and without needing anyone's laptop to be reachable.

## How it works

Every `poll_interval_seconds` (default 1 hour), this add-on:

1. Clones the **frontend** dist repo (just the built `index.html`/`assets/`
   — nothing to extract) and, if its latest commit differs from the one
   last deployed, copies it into `config/www/<frontend_folder>/`. No
   restart needed — Home Assistant just serves whatever's on disk.
2. Clones the **backend** bridge repo and, if its latest commit differs
   from the one last deployed, copies `custom_components/<backend_domain>/`
   into `config/custom_components/<backend_domain>/`, then restarts Core
   once so the new Python code is picked up.

Both checks are independent and skip cleanly if a repo is unreachable for
one cycle — it just tries again next time.

## Why this exists instead of HACS

HACS's GitHub device-code login is a genuine one-time human-in-the-loop
step — fine for a community integration someone chooses to install once,
awkward for something you want every new client's provisioning run to
finish end-to-end without you sitting in front of a browser. Since both
of EverRise's own repos here are first-party (you control exactly when a
new version ships — the dist repo only gets a new commit when you
manually trigger its build workflow), a plain scheduled `git pull` is a
better fit: no interactive login, ever, and updates ship the moment you
decide to, not whenever a client happens to click an "update available"
badge inside their own HA instance.

## Setup

1. Push this folder to its own GitHub repo (referenced in
   `server/data/catalog.json` as this add-on's `repository.url`).
2. Add its repository in Home Assistant's Add-on Store, or let the
   provisioner do it automatically as part of a normal run.
3. Set the four options to your real repo URLs/names if they differ from
   the defaults in `config.yaml` — same `options` block the provisioner
   already knows how to push via `POST /addons/everrise_updater/options`,
   just like every other catalog add-on.

## Required repo shapes

- **Frontend repo**: repo root IS the dist output (`index.html`,
  `assets/`, etc.) — matching `everrise-dashboard-dist.zip`'s own layout.
- **Backend repo**: a normal `ha-everrise-dashboard-bridge`-shaped repo,
  i.e. `custom_components/<domain>/` somewhere in it — matching what
  `installCustomComponent` in the provisioner already expects.
