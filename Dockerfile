FROM python:3.10-bullseye

WORKDIR /

# If you want to install audio_feeder from a local directory, make sure this exists
COPY ./audio_feede[r] /tmp/audio_feeder
RUN if [ ! -d "/tmp/audio_feeder" ];\
    then pip install "audio_feeder>=0.4.0"; \
    else pip install "/tmp/audio_feeder"; fi
RUN pip install gunicorn
RUN apt-get update -qq && apt-get -y install ffmpeg
CMD gunicorn --access-logfile /etc/audio_feeder/logs/audio_feeder.access.log \
             --error-logfile /etc/audio_feeder/logs/audio_feeder.error.log \
             -e AF_LOGGING_LEVEL=INFO \
             -b 0.0.0.0:9090 \
             'audio_feeder.app:create_app()'
