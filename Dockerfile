# [CONFIRMED via developers.home-assistant.io/docs/apps/configuration] As of
# Supervisor 2026.04.0, build.yaml/build_from is deprecated in favor of
# setting the base image directly here — this single tag resolves to the
# right architecture automatically, no per-arch mapping needed.
#
# home-assistant's base images are Alpine-based (apk, not apt) — if a
# future base image switches that, swap the `apk add` line below for the
# Debian/Ubuntu equivalent (`apt-get update && apt-get install -y ...`).
FROM ghcr.io/home-assistant/base:latest

RUN apk add --no-cache git rsync curl bash

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
