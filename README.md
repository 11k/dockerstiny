# dockerstiny

A collection of Dockerfiles and config files that enable you to easily run Destiny.gg (website and chat) locally on your computer for development purposes.

Only tested on macOS. Windows and Linux users beware.

## Requirements
* [Docker](https://www.docker.com/)
* [Docker Compose](https://docs.docker.com/compose/)
* [npm](https://www.npmjs.com/)
* [mkcert](https://github.com/FiloSottile/mkcert)

## Instructions
1. Download/install the requirements above.
2. Clone this repo.
```
git clone dockerstiny
```

3. Navigate into the project folder.
```
cd dockerstiny
```

4. Clone [`destinygg/website`](https://github.com/destinygg/website.git) and [`destinygg/chat`](https://github.com/destinygg/chat.git) into this folder.
```
git clone https://github.com/destinygg/website.git ./website
git clone https://github.com/destinygg/chat.git ./chat
```

5. Use `mkcert` to create and install a locally-trusted certificate authority.
```
mkcert -install
```

6. Generate a certificate and private key.
```
mkcert -cert-file docker/nginx-certs/dgg.pem -key-file docker/nginx-certs/dgg-key.pem localhost 127.0.0.1
```

7. Copy the included website and chat config files to the appropriate locations.
```
cp docker/website-config/config.local.php website/config/
cp docker/chat-config/settings.cfg chat/
```

8. Copy the database initialization scripts into the `mysql-scripts` directory. Note the numeric prefixes. This ensures the scripts are executed in the correct order.
```
cp website/config/destiny.gg.sql docker/mysql-scripts/01.destiny.gg.sql
cp website/config/destiny.gg.data.sql docker/mysql-scripts/02.destiny.gg.data.sql
```

9. Install all Node.js dependencies for the website.
```
cd website
npm ci
```

10. Generate the site's static assets.
```
npm run build
```

11. Head back into the project folder and build/run. This command will take some time.
```
cd ..
docker-compose up
```

12. Access the site via `https://localhost:8080`.
13. Go to `https://localhost:8080/impersonate?username=admin` to log in as the admin.

