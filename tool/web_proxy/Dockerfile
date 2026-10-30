# Riflay web proxy. Build from the repository root (it shares two files with the app):
#   docker build -f tool/web_proxy/Dockerfile -t riflay-web-proxy .
#   docker run --rm -p 8787:8787 riflay-web-proxy
FROM docker.io/library/dart:stable AS build
WORKDIR /src
COPY tool/web_proxy/pubspec.yaml tool/web_proxy/pubspec.lock tool/web_proxy/
RUN cd tool/web_proxy && dart pub get
COPY lib/platform/proxy_route.dart lib/platform/
COPY lib/services/youtube_player_api.dart lib/services/
COPY tool/web_proxy tool/web_proxy
# A local checkout's .dart_tool points at the host's package cache: resolve again inside the image.
RUN cd tool/web_proxy && rm -rf .dart_tool && dart pub get --offline && dart compile exe bin/server.dart -o /server

FROM docker.io/library/debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /server /usr/local/bin/riflay-web-proxy
USER nobody
EXPOSE 8787
CMD ["riflay-web-proxy", "--host", "0.0.0.0"]
