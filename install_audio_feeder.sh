#! /bin/bash
set -euo pipefail

# Creates the configuration directory (the database and static directories,
# and the stylesheets and images used by the web page) in the container. This
# can be re-run after upgrading audio-feeder to update the static files.
docker compose run --rm audio_feeder audio-feeder install --config-dir /etc/audio_feeder
