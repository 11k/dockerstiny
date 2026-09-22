# dockerstiny

Spin up Destiny.gg (website, chat, live-ws, wiki) dev environments on demand. Each environment is its own Docker Compose project with its own database, served at its own hostname, with git worktrees for just the services you're changing. Tested on macOS, Linux, and Windows (via Linux on WSL2).

## Requirements
* [Docker](https://www.docker.com/) (with [Docker Compose](https://docs.docker.com/compose/))
* [npm](https://www.npmjs.com/)
* [Composer](https://getcomposer.org/)
* [mkcert](https://github.com/FiloSottile/mkcert) — if using Linux on WSL2, mkcert must be installed on Windows (see [Windows mkcert instructions](#windows-mkcert-instructions) below)
* Bash 4+ (macOS ships 3.2: `brew install bash`)

## Setup
1. Clone this repo and put `dgg` on your PATH.
```
git clone https://github.com/11k/dockerstiny.git
cd dockerstiny
ln -s "$PWD/bin/dgg" /usr/local/bin/dgg   # or anywhere on your PATH
```

2. Run the one-time setup. It clones the repos, generates a wildcard TLS cert, seeds the shared config, starts the proxy and builds the base images. It's safe to re-run.
```
dgg init
```

3. Create an environment.
```
dgg create my-feature --with website,chat-gui
```

4. Open `https://my-feature.dgg.localhost`, or `https://my-feature.dgg.localhost/impersonate?username=admin` to log in as the admin. Your code is in `envs/my-feature/`.
5. When the feature ships, `dgg rm my-feature`. To tear down everything, run `./scripts/cleanup.sh`.

## Environments

```
dgg create tts-fix --with website,live-ws     # worktrees on a new "tts-fix" branch in each
dgg create emotes --with chat-gui:feat/emotes # …or name the branch (existing or new)
dgg create chat-bug --with chat --minimal     # skip live-ws, cron and the queue workers
dgg ls                                        # what exists, what's running, which branches
dgg down tts-fix                              # stop it; database and worktrees are kept
dgg up tts-fix
dgg rm tts-fix                                # containers, volumes, worktrees — never branches
```

`--with` lists the services you're *changing*. Each gets a git worktree in `envs/<name>/<service>` on a branch named after the environment (created from origin's default branch if it doesn't exist yet). Services you don't list still run, from shared images built off origin's default branch — `dgg update` refreshes those. The website is the exception: every environment gets a website checkout, because its asset build bakes in the environment's URLs. Without `--with website` it's a detached checkout of the default branch.

Inside `envs/<name>/` the name can be left off: `dgg logs -f chat`, `dgg exec website bash`, `dgg migrate`, `dgg test`. Run `dgg help` for everything, and `dgg compose <name> -- <args>` for raw Compose access.

Day to day:
* **website** — edit in `envs/<name>/website`; PHP changes are live, assets need `npm run watch` there.
* **chat-gui** — edit in `envs/<name>/chat-gui`; the website's `node_modules/dgg-chat-gui` links to it, so the website's `npm run watch` picks changes up.
* **chat / live-ws** — these are compiled into their images: `dgg build <name>` rebuilds and restarts them.

### How it fits together

```
Browser ─→ Traefik (127.0.0.1:443, routes by hostname) ─┬→ dgg-foo: nginx → website, chat, live-ws, …
                                                        └→ dgg-bar: nginx → …
```

* **One proxy, no port juggling.** A shared Traefik container owns port 443 and finds environments through container labels. `*.localhost` resolves to loopback on its own, and because every environment has its own hostname, logins in one don't clobber another's cookies. Change the domain or port in `dgg.conf` (then `dgg render --all`, `dgg proxy restart`, and delete `docker/nginx-certs/wildcard.*` + re-run `dgg init` for a new domain).
* **Config is rendered, not copied.** Settings shared by all environments — keys, secrets, feature config — live in `config/` (gitignored; seeded by `dgg init`). Each environment's URLs are layered on top into `envs/<name>/config/` whenever it starts. Edit `config/website.config.php` once and every environment sees it; nothing environment-specific lives in a repo.
* **Databases start from a snapshot.** The first environment migrates an empty database and saves it as the `default` snapshot; later ones unpack it and only run migrations newer than it. `dgg snapshot save <env> --force` replaces it with that environment's data (handy once one has useful seed data), `--as <name>` keeps several, and `dgg create --snapshot <name>` picks one. `dgg snapshot restore <env> [name]` resets an existing environment's database to a snapshot and migrates it; the database it replaces is kept as the snapshot `backup-<env>`, so `dgg snapshot restore <env> backup-<env>` undoes it. Restoring also flushes that environment's Redis, which logs you out.
* **Dependencies are cloned.** New worktrees get `node_modules` and `vendor` as copy-on-write clones of the canonical checkouts when the lockfiles match, and a real install when they don't.

### Working with coding agents
dgg is meant to be driven by an agent as comfortably as by hand:
* `dgg status <name> --json` and `dgg ls --json` give structured state; `dgg status` exits non-zero when a service is down (and knows cron exiting is normal).
* Without a terminal, output is plain and short. Install and build output goes to `envs/<name>/create.log` and only surfaces on failure (`DGG_VERBOSE=1` to stream it).
* Every environment gets a generated `envs/<name>/CLAUDE.md` with its URL, its worktrees and branches, and how each kind of change takes effect.
* Claude Code permission rules ship in `.claude/settings.json`, and dgg writes the same rules into each environment and worktree (Claude Code doesn't read settings from parent directories). Routine commands run without prompts; `dgg rm`, `dgg snapshot save|rm` and `scripts/cleanup.sh` always ask; files holding live API keys (`config/` and the rendered chat/live-ws configs) can't be read.
* `dgg snapshot save` refuses to replace an existing snapshot without `--force`.

### TTS webhooks
Replicate can't reach localhost, so TTS generation needs an ngrok tunnel, and the tunnel has one domain. Set `NGROK_DOMAIN` in `dgg.conf`, then point it at whichever environment needs it:
```
dgg tunnel my-feature --run    # routes the tunnel to my-feature and starts ngrok
dgg tunnel off
```
Only `/api/tts/webhook/` is served on the tunnel hostname.

### Moving from the single-environment setup
Old `dockerstiny`-style projects keep running until you remove them (`docker compose -p <project> down`), but this checkout's Compose file no longer drives them. To carry a database over, stop its MySQL container and run `dgg snapshot save --volume <project>_mysql_data` (add `--force` to replace the default snapshot, or `--as <name>` to keep it alongside). `dgg init` seeds `config/` from the existing `website/config/config.local.php`, `chat/settings.cfg` and `live-ws/.env`.

## Wikistiny instructions
1. Create the environment with `--wiki`. The wiki is served at `https://wiki-<name>.dgg.localhost`.
2. Run the install script to initialize the wiki.
```
dgg exec <name> wikistiny su www-data -s /bin/bash -c 'MW_CONFIG_FILE=/tmp/LocalSettings.php php maintenance/run install --dbtype=sqlite --dbname="$WIKI_DB_NAME" --dbpath=/var/www/data --pass="$WIKI_PASS" --server="$WIKI_SERVER" --confpath=/tmp --scriptpath="" "$WIKI_NAME" "$WIKI_ADMIN"'
```

## Windows mkcert Instructions
1. Download the latest release of mkcert from the project's [releases page on GitHub](https://github.com/FiloSottile/mkcert/releases). The version you need ends with "-windows-amd64.exe".
2. Open Command Prompt.
3. Navigate into the directory that contains the mkcert executable you just downloaded, likely `Downloads`.
```
cd %HOMEPATH%\Downloads
```

4. Create and install a locally-trusted certificate authority. Your executable may have a slightly different name.
```
mkcert-v1.4.3-windows-amd64.exe -install
```

5. Generate a certificate and private key.
```
mkcert-v1.4.3-windows-amd64.exe -cert-file wildcard.pem -key-file wildcard-key.pem "*.dgg.localhost" dgg.localhost localhost 127.0.0.1
```

6. Copy the generated files to the appropriate location. This can be done from within WSL2 by utilizing `wslvar` and `wslpath`.
```
cp $(wslpath "$(wslvar HOMEDRIVE)$(wslvar HOMEPATH)")/Downloads/wildcard* docker/nginx-certs
```

7. Do the same with the CA certificate.
```
cp $(wslpath "$(mkcert-v1.4.3-windows-amd64.exe -CAROOT)\rootCA.pem") docker/ca-certs/
```

8. Tell `dgg init` the cert is already there by recording the domain it covers.
```
echo dgg.localhost > docker/nginx-certs/wildcard.domain
```
