# dockerstiny

A collection of Dockerfiles and config files that enable you to easily run Destiny.gg (website and chat) locally on your computer for development purposes. Tested on macOS, Linux, and Windows (via Linux on WSL2).

## Requirements
* [Docker](https://www.docker.com/) (with [Docker Compose](https://docs.docker.com/compose/))
* [npm](https://www.npmjs.com/)
* [Composer](https://getcomposer.org/)
* [mkcert](https://github.com/FiloSottile/mkcert) — if using Linux on WSL2, mkcert must be installed on Windows (see [Windows mkcert instructions](#windows-mkcert-instructions) below)

## Setup
1. Clone this repo and `cd` into it.
```
git clone https://github.com/11k/dockerstiny.git
cd dockerstiny
```

2. Run the setup script. It will clone repos, generate TLS certs, install dependencies, build assets, and run database migrations.
```
./scripts/setup.sh
```

3. Start the dev environment.
```
docker compose --profile dev up
```

4. Access the site at `https://localhost:8080` (or whichever port you chose during setup).
5. Go to `https://localhost:8080/impersonate?username=admin` to log in as the admin.

## Wikistiny instructions
1. Run the install script to initialize the wiki.
```
docker compose --profile dev exec -it wikistiny su www-data -s /bin/bash -c 'MW_CONFIG_FILE=/tmp/LocalSettings.php php maintenance/run install --dbtype=sqlite --dbname="$WIKI_DB_NAME" --dbpath=/var/www/data --pass="$WIKI_PASS" --server="http://localhost:$WIKI_SERVER_PORT" --confpath=/tmp --scriptpath="" "$WIKI_NAME" "$WIKI_ADMIN"'
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
mkcert-v1.4.3-windows-amd64.exe -cert-file dgg.pem -key-file dgg-key.pem localhost 127.0.0.1 host.docker.internal
```

6. Copy the generated files to the appropriate location. This can be done from within WSL2 by utilizing `wslvar` and `wslpath`.
```
cp $(wslpath "$(wslvar HOMEDRIVE)$(wslvar HOMEPATH)")/Downloads/dgg* docker/nginx-certs
```

7. Do the same with the CA certificate.
```
cp $(wslpath "$(mkcert-v1.4.3-windows-amd64.exe -CAROOT)\rootCA.pem") docker/ca-certs/
```
