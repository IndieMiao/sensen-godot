# 构建上下文是**仓库根目录**，不是 server/：服务端要 import workspace 包 blueprint-core，
# 只 COPY server/ 的话 pnpm 解析不了这个依赖（Codex 二审 Critical 5）。
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
RUN corepack enable && addgroup -S farm && adduser -S farm -G farm
COPY --from=build /repo /repo
# 内容表与蓝图打进镜像：它们是单一来源，运行时不从外部挂载（spec §3 铁律 3）。
COPY assets/farm/data assets/farm/data
COPY assets/blueprints assets/blueprints
USER farm
ENV NODE_ENV=production ASSET_ROOT=/repo
WORKDIR /repo/server
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/v1/healthz || exit 1
# 用 tsx 而不是 node --experimental-strip-types：后者不把 `.js` 导入映射回 `.ts`
# （TS 的 NodeNext 约定要求源码里写 .js），启动即 ERR_MODULE_NOT_FOUND。
# tsx 是 esbuild 的薄封装，启动开销约 200ms，MVP 阶段可接受；要去掉它就得先把
# blueprint-core 也编译成 dist 并改 workspace exports，那是另一件事。
CMD ["./node_modules/.bin/tsx", "src/index.ts"]
