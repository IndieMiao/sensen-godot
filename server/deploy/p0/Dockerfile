# P0 server image (SGODOT-232 D1). Build context = repo root:
#   docker build -f server/deploy/p0/Dockerfile -t p0-server:<sha> .
# Same base as server/Dockerfile; the data the server reads at start goes into the image (one source of truth, never
# mounted): the P0 content table, the outpost table, the pond list and the cosmetic catalog (see the COPY lines
# below). Saves, snapshots and the observation log live in the /data volume.
# The build context's ignore list is Dockerfile.dockerignore beside this file (BuildKit), not the farm image's root
# .dockerignore, which leaves assets/p0 out.
FROM node:22-alpine AS build
WORKDIR /repo
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/blueprint-core/package.json packages/blueprint-core/
COPY server/package.json server/
RUN pnpm install --frozen-lockfile --filter farm-server...
COPY packages/blueprint-core packages/blueprint-core
COPY server server

FROM node:22-alpine
WORKDIR /repo
RUN corepack enable && addgroup -S p0 && adduser -S p0 -G p0 && mkdir -p /data && chown p0:p0 /data
COPY --from=build /repo /repo
# Data the P0 server reads at start: content (with the content/ fragments, SGODOT-275), the outpost table (rooms, SGODOT-227), P0's pond list (each pond's map
# point, for the map markers, q(48); SGODOT-270), the frozen pond catalog and the cosmetic catalog the outpost hub
# checks appearances against (regions.json locates ../../avatar). Keep in step with Dockerfile.dockerignore and
# deploy-hk.sh build.
COPY assets/p0/p0_content.json assets/p0/p0_content.json
COPY assets/p0/content assets/p0/content
COPY assets/p0/p0_outposts.json assets/p0/p0_outposts.json
COPY assets/p0/p0_ponds.json assets/p0/p0_ponds.json
COPY assets/ponds/catalog.json assets/ponds/catalog.json
COPY assets/farm/data/regions.json assets/farm/data/regions.json
COPY assets/avatar/parts_manifest.json assets/avatar/demo_denylist.json assets/avatar/npc_only.json assets/avatar/
USER p0
ENV NODE_ENV=production P0_DEV=0 P0_PORT=3110 P0_HOST=0.0.0.0 \
    P0_STATE_FILE=/data/p0-state.json P0_SNAPSHOT_DIR=/data/snapshots P0_EVENT_DIR=/data/events
WORKDIR /repo/server
EXPOSE 3110
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3110/v1/healthz || exit 1
CMD ["./node_modules/.bin/tsx", "tools/p0_server.ts"]
