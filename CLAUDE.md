# dockerstiny

Docker-based local development environments for [Destiny.gg](https://www.destiny.gg) — a streaming and community platform. `bin/dgg` creates environments on demand: each is its own Docker Compose project (`dgg-<name>`) running the stack (website, chat, live-ws, optionally the wiki) with its own database, served at `https://<name>.dgg.localhost` through a shared Traefik proxy, with git worktrees for the services being changed.

## Services

Per environment. `chat`, `live-ws`, `cron`, `worker` and `wikistiny` are Compose profiles an environment can leave out (`dgg create --without …`, `--wiki`).

| Service | Tech | Role | Internal Port |
|------------|-------------------------------|-----------------------------------------------|---------------|
| **nginx** | Nginx 1.20 (Alpine) | Terminates TLS (mkcert wildcard cert). Routes to website, chat, live-ws. Reached only via the proxy — publishes no host port | `$DGG_PORT` (default 443) |
| **website** | PHP 8.4 FPM, Doctrine ORM, Twig, Symfony components | Main web application | 9000 (FPM) |
| **cron** | Same image as website | Scheduled tasks (`cron/index.php`); runs once and exits | — |
| **worker** | PHP 8.4 CLI | Messenger queue consumers (2 replicas by default) | — |
| **chat** | Go, Gorilla WebSocket | Real-time WebSocket chat server | 1118 |
| **live-ws** | TypeScript, ws, Redis | Live WebSocket API for streaming updates | 42069 |
| **redis** | Redis 5.0 (Alpine) | Caching, sessions, pub/sub messaging | 6379 |
| **mysql** | MariaDB 10.11.6 | Relational database (`destinygg` DB, user: `destiny`) | 3306 |
| **wikistiny** | MediaWiki + Wikistiny extension | Community wiki (SQLite) at `https://wiki-<name>.dgg.localhost` | 80 |

Shared: the **proxy** (`proxy/`, Compose project `dgg-proxy`) — Traefik on `127.0.0.1:443`, routing by SNI with TLS passthrough to each environment's nginx (it terminates TLS itself only for the wikis).

Test profile (`test`): `website-test` and `mysql-test` run PHPUnit against an isolated DB (`dgg test <name>`).

## Directory Structure

```
bin/dgg           The CLI. `dgg help` lists every command
docker-compose.yml  The stack, parameterized by envs/<name>/env — never run bare; use `dgg compose <name> -- …`
proxy/            Traefik Compose project; dynamic/ holds its file-provider config (certs, tunnel route)
docker/           Dockerfiles, config templates (nginx, wiki, website, chat, live-ws), mysql/php config, TLS certs
scripts/          cleanup.sh (tear everything down)

# Gitignored, created by dgg:
website/ chat/ chat-gui/ live-ws/ Wikistiny/   Canonical clones — the object store worktrees hang off; any branch may be checked out
config/           Shared base config for every environment (holds secrets): website.config.php, website.env, chat.settings.cfg, live-ws.env
envs/<name>/      One environment: env (its Compose env file), config/ (rendered), website/ + other worktrees
.dgg/             base/ (detached worktrees the dgg/chat:base and dgg/live-ws:base images build from), snapshots/ (DB snapshots)
dgg.conf          DGG_DOMAIN, DGG_PORT, NGROK_DOMAIN, DGG_REPOS_DIR
```

Inside a repo (`website/` = PHP app — lib/ (Destiny namespace), views/ (Twig), assets/ (JS/TS), public/ (web root), config/; `chat/` = Go server; `live-ws/` = TypeScript WebSocket API; `chat-gui/` = chat UI library compiled into the website bundle).

## Networking

```
Browser → Traefik (127.0.0.1:443, by hostname) → dgg-<name> nginx (TLS) ─┬→ website (PHP-FPM :9000)
                                                                          ├→ chat (WebSocket :1118)
                                                                          └→ live-ws (WebSocket :42069)

website ↔ mysql (queries, Doctrine ORM)
website ↔ redis (sessions, cache)
chat    ↔ mysql (user data, persistence)
chat    ↔ redis (pub/sub)
live-ws ↔ redis (pub/sub for live streaming updates)
chat, live-ws, wiki → website API at https://<name>.dgg.localhost — a network alias on the environment's nginx, so the public URL works inside the network too
```

## How config works

Nothing environment-specific lives in a repo. `dgg up`/`create`/`render` regenerate `envs/<name>/config/` from the templates in `docker/` plus the shared files in `config/`:

| Rendered file | From | Used by |
|------|---------|---------|
| `config/nginx/dgg.local.conf`, `domain.conf` | `docker/nginx-config/dgg.local.conf.template` | nginx |
| `config/website.config.php` | generated: requires `/etc/dgg/shared/website.config.php` (= `config/website.config.php`) and overrides the URL keys | website, cron, worker — via a stub `config/config.local.php` dgg writes into the website worktree |
| `config/chat/settings.cfg` | `config/chat.settings.cfg` | chat |
| `config/live-ws/.env` | `config/live-ws.env` | live-ws |
| `config/wiki/LocalSettings.php` | `docker/wiki-config/LocalSettings.php.template` | wikistiny |
| `<website worktree>/.env` | `config/website.env` | webpack (URLs are baked into `static/` at build time — why every environment has its own website checkout) |

To change a setting for every environment, edit the file in `config/`; to change how URLs are derived, edit `render_env` in `bin/dgg`.

## Common Commands

```bash
dgg init                                   # one-time setup (idempotent)
dgg create <name> --with website,chat-gui  # new environment; worktrees on branch <name>
dgg create <name> --with chat:some-branch --minimal
dgg ls [--json]
dgg status <name> [--json]                 # per-service health + worktrees; non-zero exit on problems (cron "exited (0)" is normal)
dgg up <name> / dgg down <name>            # down keeps the DB and worktrees
dgg rm <name>                              # containers, volumes, worktrees (refuses if dirty; never deletes branches)

# Inside envs/<name>/ the name is optional
dgg logs <name> -f chat
dgg exec <name> website bash
dgg build <name>                           # rebuild + restart chat/live-ws from their worktrees
dgg test <name>                            # website PHPUnit suite
dgg migrate <name>                         # vendor/bin/doctrine-migrations migrate --no-interaction

# Generate a diff migration
dgg exec <name> website vendor/bin/doctrine-migrations migrations:diff
# Note: the generated migration file may need manual edits for changes not managed by the ORM.

dgg snapshot save <name> --force           # make this env's DB the one new envs start from (--as <label> to keep both)
dgg snapshot restore <name> [snapshot]     # reset this env's DB to a snapshot + migrate; old DB kept as backup-<name>; flushes its Redis
dgg tunnel <name> --run                    # point the ngrok tunnel (TTS webhooks) at an env
dgg update                                 # refresh base images from origin's default branches

# Website frontend (from envs/<name>/website)
npm run watch      # watch mode
npm run build:dev  # one-off dev build

# Impersonate a user (in browser)
# https://<name>.dgg.localhost/impersonate?username=admin
```

## Agent notes

- Output is plain (no colour) and terse when stdout isn't a terminal. Install/build output goes to `envs/<name>/create.log` (base images: `.dgg/build.log`) and is shown only on failure; `DGG_VERBOSE=1` streams it.
- `dgg exec` drops the TTY automatically when there isn't one; `dgg logs` defaults to `--tail 100`.
- Each environment gets a generated `envs/<name>/CLAUDE.md` (its URL, which services are worktrees and on which branch, how each kind of change takes effect) — read it before working in one.
- Permissions: `.claude/settings.json` here allows the routine dgg commands (including `snapshot restore` — it only touches one environment and keeps a backup), keeps `dgg rm`, `dgg snapshot save|rm` and `scripts/cleanup.sh` on ask, and denies reading files that hold live API keys (`config/`, the rendered chat and live-ws configs, the canonical clones' local configs). Claude Code only reads settings from the directory a session starts in, so dgg writes the same rules to `envs/<name>/.claude/settings.json` and to `.claude/settings.local.json` in each worktree (`agent_settings_json` in `bin/dgg` — keep the two lists in sync).
- Don't read `config/`. To change a shared setting, tell the user which key to edit.

## Frontend Stack (website)

Webpack, Bootstrap 5.3, Hotwired Stimulus, ESLint, Prettier. Source in `website/assets/`, built output in `website/static/`.
