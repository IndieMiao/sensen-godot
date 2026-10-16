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
# checks appearances against (assets/avatar, read by src/p0/online/appearance.ts). Keep in step with Dockerfile.dockerignore and
# deploy-hk.sh build.
COPY assets/p0/p0_content.json assets/p0/p0_content.json
COPY assets/p0/content assets/p0/content
COPY assets/p0/p0_outposts.json assets/p0/p0_outposts.json
COPY assets/p0/p0_ponds.json assets/p0/p0_ponds.json
COPY assets/p0/city_clusters.json assets/p0/city_clusters.json
COPY assets/ponds/catalog.json assets/ponds/catalog.json
COPY assets/avatar/parts_manifest.json assets/avatar/demo_denylist.json assets/avatar/npc_only.json assets/avatar/
# q(188) ① `Near you` (SGODOT-303): DB-IP City Lite (CC BY 4.0, credited in Settings › Licenses › Map data), one month
# pinned by its digest, turned at build time into the address → nearest open city table (about 11 MB;
# tools/ip_near_table.ts, read by src/p0/ip_city.ts) — the 127 MB location database would not fit the 256 MB
# container, and the server never calls out. Built after the content above, so it follows the open list. The file comes
# from the build context's dbip/ (deploy-hk.sh copies it from the devserver's ~/p0-cache/dbip: DB-IP keeps only the
# last two months online), through a bind mount, so it is in no layer. To update: put the new month's
# dbip-city-lite-<YYYY-MM>.csv.gz in that cache (download.db-ip.com/free/), then its month and sha256 here.
ARG DBIP_MONTH=2026-10
ARG DBIP_SHA256=d0a4d9446c1e5b826b95f99ed3b3ce151b9844df0044fe223a636cde26c75f2a
RUN --mount=type=bind,source=dbip,target=/dbip \
  echo "${DBIP_SHA256}  /dbip/dbip-city-lite-${DBIP_MONTH}.csv.gz" | sha256sum -c - \
  && cd /repo/server && ./node_modules/.bin/tsx tools/ip_near_table.ts /dbip/dbip-city-lite-${DBIP_MONTH}.csv.gz data/ip-near.bin
USER p0
ENV NODE_ENV=production P0_DEV=0 P0_PORT=3110 P0_HOST=0.0.0.0 \
    P0_STATE_FILE=/data/p0-state.json P0_SNAPSHOT_DIR=/data/snapshots P0_EVENT_DIR=/data/events \
    P0_IP_NEAR_TABLE=/repo/server/data/ip-near.bin
WORKDIR /repo/server
EXPOSE 3110
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3110/v1/healthz || exit 1
CMD ["./node_modules/.bin/tsx", "tools/p0_server.ts"]
