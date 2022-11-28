FROM python:3.10-slim-bullseye

WORKDIR /

RUN apt-get update -qq && apt-get -y install ffmpeg

# This stuff is necessary for building Pillow from source
RUN apt-get -y install \
    build-essential \
    libjpeg-turbo-progs \
    libjpeg62-turbo-dev \
    zlib1g-dev

RUN pip install gunicorn

# If you want to install audio_feeder from a local directory, make sure this exists
RUN rm -rf /tmp/audio_feeder
COPY ./audio[\\-_]feeder /tmp/audio_feeder

RUN if [ ! -d "/tmp/audio_feeder" ];\
    then echo "Installing from PyPI"; pip install "audio_feeder>=0.6.0"; \
    else echo "Using local audio_feeder"; pip install "/tmp/audio_feeder"; fi

CMD gunicorn --access-logfile /etc/audio_feeder/logs/audio_feeder.access.log \
             --error-logfile /etc/audio_feeder/logs/audio_feeder.error.log \
             -b 0.0.0.0:9090 \
             'audio_feeder.app:create_app()'
