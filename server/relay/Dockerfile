# Multi-arch image (linux/amd64 for the OptiPlex, linux/arm64 for the Pi).
# Build from the repo root:
#   docker buildx build --platform linux/amd64,linux/arm64 -f server/relay/Dockerfile -t detour-relay .
# Run:
#   docker run -d --name detour-relay --restart unless-stopped -p 24650:24650/udp detour-relay

FROM rust:1-slim AS build
WORKDIR /src
COPY . .
# Only the relay: skips the Godot bindings entirely.
RUN cargo build --release -p detour-relay --locked

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=build /src/target/release/detour-relay /usr/local/bin/detour-relay
ENV DETOUR_RELAY_BIND=0.0.0.0:24650
EXPOSE 24650/udp
USER nonroot
ENTRYPOINT ["/usr/local/bin/detour-relay"]
