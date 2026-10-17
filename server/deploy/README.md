# 旧 farm 服务端部署（香港 ECS，根路径 `/v1`）

`deploy.sh` 部署旧 farm（app + postgres + backup + caddy，compose 项目 `farm`，目录 `/opt/farm`）。P0 演示服务端另有一套，见 [p0/README.md](p0/README.md)。

## 线上文件以服务器为准

- **`/opt/farm/.env`**：库密码（2026-10-16 已换）、备份用的 age 公钥和 OSS 只写凭据都只在服务器上。`deploy.sh` 发现服务器上已有 `.env` 就不覆盖，只改其中的镜像行（`APP_IMAGE` / `GIT_SHA` / `PG_DIGEST` / `CADDY_DIGEST`）。本机的 `server/.env.production` 只在首次部署时用，里面不要再放库密码。
- **`/opt/farm/Caddyfile`**：线上版本并入了 P0 的 `/preview/p0` 转发和 Journey 退役后的 410，与仓库里的 `Caddyfile` 不同。`deploy.sh` 发现服务器上已有就不覆盖。要改，在服务器上改，先备份，`caddy validate` 通过后热加载。
- `docker-compose.yml`、`crontab`、`backup.sh` 每次部署从仓库推上去。

**2026-10-17 之前的 `deploy.sh` 会用本机文件整份覆盖 `.env` 和 `Caddyfile`。在包含这次修复的版本合入之前，不要运行它。**

## 备份

`backup.sh` 由 farm-backup-1 容器里的 supercronic 每天 03:30 UTC 运行：pg_dump → age 加密 → 用只写子账号上传到 `sensen-farm-backup` 桶的 `farm/` 前缀（30 天后自动删除）。私钥不在服务器上。恢复演练用 `restore-drill.sh`，恢复目标只能是 devserver 上的 `sensen_farm_restore` 库。
