# Plex with VAAPI tone mapping instead of OpenCL
#
# Plex Media Server cannot open an OpenCL device on Intel Arc GPUs
# ("Failed to get number of OpenCL platforms: -1001"), even though clinfo
# detects the card in the very same container. As a result tonemap_opencl
# fails and HDR content is delivered without tone mapping — the picture looks
# blown out, washed into yellow-green.
#
# This image wraps the Plex Transcoder binary with a script that rewrites the
# OpenCL branch of the filter chain to tonemap_vaapi, which the same GPU
# handles without any problem.
#
# Build (default base image):
#   docker build -t plex-vaapi-tonemap .
#
# Build against a different base:
#   docker build --build-arg BASE_IMAGE=lscr.io/linuxserver/plex:latest -t plex-vaapi-tonemap .

ARG BASE_IMAGE=binhex/arch-plex:latest
FROM ${BASE_IMAGE}

ARG TRANSCODER="/usr/lib/plexmediaserver/Plex Transcoder"

COPY plex-transcoder-wrapper.sh /usr/local/bin/plex-transcoder-wrapper.sh

RUN set -eu; \
    test -f "${TRANSCODER}" || { echo "Plex Transcoder not found at ${TRANSCODER}"; exit 1; }; \
    if [ ! -f "${TRANSCODER}.orig" ]; then mv "${TRANSCODER}" "${TRANSCODER}.orig"; fi; \
    cp /usr/local/bin/plex-transcoder-wrapper.sh "${TRANSCODER}"; \
    chmod 755 "${TRANSCODER}" "${TRANSCODER}.orig"; \
    echo "wrapper installed"

# Enable HDR tone mapping in Plex settings for this to take effect
# (Settings -> Transcoder -> Enable HDR tone mapping).
