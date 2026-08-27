# Wrap the official Part-DB image so it runs as a Home Assistant add-on.
# The base image is published multi-arch (amd64/arm64) on Docker Hub.
ARG BUILD_FROM=marcohald/part-db:master
FROM ${BUILD_FROM}

# jq is used by run.sh to read the add-on options from /data/options.json.
# The Part-DB image is Debian-based, so apt is available.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod a+x /run.sh

# Replace the upstream entrypoint with our launcher. run.sh maps the add-on
# options to Part-DB environment variables, wires persistence to /config, then
# hands over to the upstream FrankenPHP entrypoint (docker-entrypoint) + the
# frankenphp server.
ENTRYPOINT ["/run.sh"]

# The upstream image inherits STOPSIGNAL SIGWINCH (a leftover from the old
# Apache variant). FrankenPHP/Caddy ignores SIGWINCH and shuts down on SIGTERM,
# so without this override stopping the add-on times out and Docker SIGKILLs it
# (exit code 137). SIGTERM lets it stop gracefully.
STOPSIGNAL SIGTERM
