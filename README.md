# Audio Feeder Docker Container

This is a basic `docker-compose` set up that serves [`audio-feeder`](https://github.com/pganssle/audio-feeder/) on your local network using `gunicorn` with a separate `nginx` container serving static media content (e.g. your audiobooks).

I personally put the whole thing behind an [`nginx` reverse proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/) with [`certbot`](https://hub.docker.com/r/certbot/certbot/) handling the certificates, but that is optional.

## Installation

To use this:

1. Clone this repository somewhere on your path.
2. Copy `env_template` to `.env` and fill out the environment variables.
3. Run `docker-compose build` to build the containers
4. Run `./install_audio_feeder.sh` to initialize the folders
5. Start up the docker containers with `docker-compose up -d`.
6. (Optional) Run `./install.sh` to install services to automatically update your audiobooks on a server.
7. Customize `config/audio_feeder/config.yml` as desired.
8. Run `docker-compose run audio_feeder audio_feeder update` or visit https://localhost:8080/update (or whatever endpoint is running your server) to trigger an initial database update (generating the feeds for your books) — this may take a while if you have a large number of audiobooks.

Finally, when these steps inevitably are incomplete or fail, send a PR to this repository improving the instructions for the next person 😉
