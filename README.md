# Audio Feeder Docker Container

This is a basic `docker compose` setup that serves [`audio-feeder`](https://github.com/pganssle/audio-feeder/) on your local network using `gunicorn`, with a separate `nginx` container serving static media content (e.g. your audiobooks) and forwarding everything else to the app on port 8080.

The app runs on the free-threaded build of Python 3.14 (3.14t) with the GIL disabled, in a single `gunicorn` process with many threads; see [Free-threading](#free-threading) for details.

I personally put the whole thing behind an [`nginx` reverse proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/) with [`certbot`](https://hub.docker.com/r/certbot/certbot/) handling the certificates, but that is optional; see [Reverse proxy](#reverse-proxy).

## Installation

1. Clone this repository somewhere on your path.
2. Copy `env_template` to `.env` and set `AUDIOBOOK_DIR` to the directory containing your audiobooks. The other variables are the directories on the host where the database, the static files and the rendered feeds are kept, under `/data/audio_feeder` by default.
3. Copy `config/audio_feeder/config.yml.example` to `config/audio_feeder/config.yml`:

   ```console
   $ cp config/audio_feeder/config.yml.example config/audio_feeder/config.yml
   ```

   This has to exist before the containers are first started, because otherwise Docker creates an empty directory in its place. At the very least, set `base_host` to an address of this machine that your podcast app can reach (not `localhost`), since the URLs in the feeds are built from it. See the [configuration documentation](https://audio-feeder.readthedocs.io/en/latest/configuration.html) for the other settings.
4. Build the image with `docker compose build`.
5. Run `./install_audio_feeder.sh`, which runs `audio-feeder install` in the container to set up the configuration directory. This also rewrites `config.yml` with every setting in it, keeping your values but not the comments.
6. Start the containers with `docker compose up -d`.
7. Load your books into the database (generating the feeds for your books) with:

   ```console
   $ docker compose run --rm audio_feeder audio-feeder update
   ```

   or by visiting http://localhost:8080/update (or whatever address your server is running on). This searches the directories listed in the `content_paths` setting, which is `audiobooks` (where `AUDIOBOOK_DIR` is mounted) in the example configuration. It may take a while if you have a large number of audiobooks.
8. (Optional) Run `sudo ./install.sh` to install a `systemd` timer that triggers a database update every 3 hours, then enable it with `sudo systemctl enable --now update_audiobooks.timer`. This needs [GNU Stow](https://www.gnu.org/software/stow/).

The book list is then at http://localhost:8080/books.

After changing `config/audio_feeder/config.yml`, restart the app with `docker compose restart audio_feeder`, since the configuration is only read when it starts.

Finally, when these steps inevitably are incomplete or fail, send a PR to this repository improving the instructions for the next person 😉

## Choosing the version of audio-feeder

The image installs `audio-feeder` from PyPI, using the requirement in the `AUDIO_FEEDER_SPEC` build argument, which defaults to `audio_feeder>=0.7.0`. To install something else, e.g. a version that hasn't been released yet, set `AUDIO_FEEDER_SPEC` in `.env` (there's a commented-out example in `env_template`), or pass it to the build:

```console
$ docker compose build --build-arg AUDIO_FEEDER_SPEC="audio-feeder @ git+https://github.com/pganssle/audio-feeder@main"
```

Any [requirement specifier](https://packaging.python.org/en/latest/specifications/dependency-specifiers/) works, including a pinned version (`audio_feeder==0.7.0`) or a specific commit (`audio-feeder @ git+https://github.com/pganssle/audio-feeder@<sha>`). If there's a clone of `audio-feeder` in `audio_feeder/` or `audio-feeder/` in this directory, it's installed instead.

Docker caches the layer that installs `audio-feeder`, so rebuilding the image doesn't pick up a new release (or new commits on a branch) unless something in the build changed. To upgrade, rebuild without the cache and restart:

```console
$ docker compose build --pull --no-cache
$ ./install_audio_feeder.sh
$ docker compose up -d
```

Re-running `./install_audio_feeder.sh` updates the stylesheets and images in the static directory.

## Free-threading

The image runs `audio-feeder` under the free-threaded build of CPython 3.14, which can run Python code in several threads in parallel. There are no official `python` images for the free-threaded build, so the image installs one with [`uv`](https://docs.astral.sh/uv/) (from [python-build-standalone](https://github.com/astral-sh/python-build-standalone)) on `debian:trixie-slim`. The Python, `uv` and Debian versions are build arguments (`PYTHON_VERSION`, `UV_VERSION` and `DEBIAN_VERSION`) in the `Dockerfile`.

Since the threads don't contend for a GIL, `gunicorn` runs a single worker process with the `gthread` worker class, rather than a pool of processes. The number of threads is set by `GUNICORN_THREADS` in `.env` (12 by default). The rest of the `gunicorn` configuration is in `gunicorn.conf.py`, and you can override any of it with [`GUNICORN_CMD_ARGS`](https://docs.gunicorn.org/en/stable/settings.html).

Importing a C extension that hasn't declared that it supports free-threading would normally re-enable the GIL. The image sets `PYTHON_GIL=0`, which keeps the GIL disabled regardless, so to make sure that's safe, `gunicorn.conf.py` checks at startup whether importing `audio-feeder` would have enabled it, and refuses to start if so (the log says which module was responsible). Set `AF_REQUIRE_FREE_THREADING=0` in the container's environment to start anyway, with a warning.

## Reverse proxy

To put the `nginx` container behind a reverse proxy running in another container, copy `docker-compose.override.yml.example` to `docker-compose.override.yml`, which `docker compose` reads automatically. This attaches the `nginx` container to an external network called `docknet` (change it to whatever network your reverse proxy is on), which you can create with `docker network create docknet` if it doesn't exist yet. The reverse proxy can then forward requests to `http://audiofeeder-nginx:80`.

Server-specific `nginx` configuration (e.g. `server_name`) can go in `${DATA_DIR}/nginx_custom/audio_feeder.conf`, which is included in the `server` block if it exists.
