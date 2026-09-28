-- G1-A 存储（spec §8）。用裸 SQL 而不是 ORM 迁移工具：表只有六张，且 applyCommand 的
-- 事务语义（FOR UPDATE + 幂等 + 版本）必须逐字可读，ORM 会把它藏起来。

CREATE TABLE IF NOT EXISTS players (
  id                uuid PRIMARY KEY,
  install_key_hmac  text NOT NULL UNIQUE,
  created_at        bigint NOT NULL,
  last_seen_at      bigint NOT NULL
);

CREATE TABLE IF NOT EXISTS tokens (
  id            uuid PRIMARY KEY,
  player_id     uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  token_hash    text NOT NULL UNIQUE,
  created_at    bigint NOT NULL,
  last_used_at  bigint NOT NULL
);
CREATE INDEX IF NOT EXISTS tokens_player_idx ON tokens(player_id, last_used_at);

CREATE TABLE IF NOT EXISTS farms (
  id                    uuid PRIMARY KEY,
  owner_id              uuid NOT NULL UNIQUE REFERENCES players(id) ON DELETE CASCADE,
  region_id             text NOT NULL,
  layout_patch_id       text NOT NULL,
  blueprint_revision    int  NOT NULL,
  blueprint_checksum    text NOT NULL,
  content_version       text NOT NULL,
  domain_version        text NOT NULL,
  state_schema_version  int  NOT NULL,
  version               int  NOT NULL DEFAULT 0,
  state                 jsonb NOT NULL,
  qa                    boolean NOT NULL DEFAULT false,
  qa_clock              jsonb,
  visit_access          text NOT NULL DEFAULT 'only_me',
  location_visible      boolean NOT NULL DEFAULT true,
  created_at            bigint NOT NULL,
  updated_at            bigint NOT NULL
);

-- Existing farms retain their blueprint's original position; new placements are independent.
ALTER TABLE farms ADD COLUMN IF NOT EXISTS location jsonb CHECK (
  location IS NULL OR (
    jsonb_typeof(location) = 'object'
    AND location ?& ARRAY['lat', 'lng']
    AND jsonb_typeof(location -> 'lat') = 'number'
    AND jsonb_typeof(location -> 'lng') = 'number'
    AND (location ->> 'lat')::double precision BETWEEN -85 AND 85
    AND (location ->> 'lng')::double precision BETWEEN -180 AND 180
  )
);

-- Frozen geographic terrain is independent of save JSON; legacy farms retain their original plot.
ALTER TABLE farms ADD COLUMN IF NOT EXISTS farm_terrain jsonb CHECK (
  farm_terrain IS NULL OR (jsonb_typeof(farm_terrain) = 'object'
    AND farm_terrain ->> 'format' = '1' AND farm_terrain ?& ARRAY['layout_id', 'plot', 'source'])
);

-- 建农场的幂等记录。payload_hash 是必需的：同 key 换地区不能被当成重试
-- Entitlement is granted only by explicit domain migration, never on read or new creation.
ALTER TABLE farms ADD COLUMN IF NOT EXISTS relocation_available boolean NOT NULL DEFAULT false;
ALTER TABLE farms ADD COLUMN IF NOT EXISTS relocation_used boolean NOT NULL DEFAULT false;
ALTER TABLE farms ADD COLUMN IF NOT EXISTS relocation_draft jsonb;

-- （Codex 二审 Important 2）。
CREATE TABLE IF NOT EXISTS farm_creations (
  player_id        uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  idempotency_key  text NOT NULL,
  payload_hash     text NOT NULL,
  farm_id          uuid NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
  created_at       bigint NOT NULL
);

-- 命令日志。**成功与失败都记**：只记成功的话，同一个幂等键稍后可能从失败变成功
-- （Codex 二审 Important 2）。effective_now / content_version / domain_version 让历史命令
-- 可以被确定性重放（Important 4）。
CREATE TABLE IF NOT EXISTS commands (
  id               bigserial PRIMARY KEY,
  farm_id          uuid NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
  idempotency_key  text NOT NULL,
  base_version     int  NOT NULL,
  type             text NOT NULL,
  payload          jsonb NOT NULL,
  payload_hash     text NOT NULL,
  outcome          text NOT NULL,
  result           jsonb,
  effective_now    bigint NOT NULL,
  content_version  text NOT NULL,
  domain_version   text NOT NULL,
  applied_at       bigint NOT NULL,
  UNIQUE (farm_id, idempotency_key)
);

-- G2 的访客快照。三个版本列让「旧快照能不能继续下发」可判定（Codex 三审 O-I5）。
CREATE TABLE IF NOT EXISTS online_rooms (
  id text PRIMARY KEY,
  revision int NOT NULL,
  commit_id uuid NOT NULL,
  state jsonb NOT NULL,
  updated_at bigint NOT NULL
);
CREATE TABLE IF NOT EXISTS online_parties (
  id text PRIMARY KEY,
  code text NOT NULL UNIQUE,
  state jsonb NOT NULL
);
ALTER TABLE online_rooms ADD COLUMN IF NOT EXISTS rescued jsonb NOT NULL DEFAULT '[]';
CREATE TABLE IF NOT EXISTS online_players (
  player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  instance_id text NOT NULL DEFAULT '',
  party_id text NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS online_players_instance ON online_players(instance_id);
ALTER TABLE online_players ADD COLUMN IF NOT EXISTS party_farm_access text NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS farm_snapshots (
  farm_id            uuid PRIMARY KEY REFERENCES farms(id) ON DELETE CASCADE,
  snapshot_revision  int  NOT NULL,
  snapshot_taken_at  bigint NOT NULL,
  body               jsonb NOT NULL,
  blueprint_revision int  NOT NULL,
  content_version    text NOT NULL,
  domain_version     text NOT NULL
);

-- 账号（SGODOT-135）。自有 uuid 是主键；邮箱账户自建（大陆可用），Apple / Google 经 Firebase
-- 只作为 user_identities 里的一条身份。每个账号对应一个 players 行（user_id 非空），
-- 农场、联机、队伍照旧按 player id 走；user_id 为空的 players 是游客，只读。
CREATE TABLE IF NOT EXISTS users (
  id              uuid PRIMARY KEY,
  email           text UNIQUE,
  email_verified  boolean NOT NULL DEFAULT false,
  password_hash   text,
  created_at      bigint NOT NULL,
  last_seen_at    bigint NOT NULL
);
-- 同一个库可能已有 D2（feat/next-feature）建的旧 users 表：它没有密码列、邮箱也不唯一。
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash text;
CREATE UNIQUE INDEX IF NOT EXISTS users_email_key ON users(email);
-- (provider, provider_uid) 是并发首登的裁判：provider = 'email' | 'firebase'。
CREATE TABLE IF NOT EXISTS user_identities (
  provider          text NOT NULL,
  provider_uid      text NOT NULL,
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sign_in_provider  text,
  created_at        bigint NOT NULL,
  PRIMARY KEY (provider, provider_uid)
);
CREATE INDEX IF NOT EXISTS user_identities_user_idx ON user_identities(user_id);
ALTER TABLE players ADD COLUMN IF NOT EXISTS user_id uuid UNIQUE REFERENCES users(id) ON DELETE CASCADE;
-- 验证码只存 HMAC；一个邮箱每种用途同时一个有效码。
CREATE TABLE IF NOT EXISTS email_codes (
  email       text NOT NULL,
  purpose     text NOT NULL,
  code_hash   text NOT NULL,
  expires_at  bigint NOT NULL,
  sent_at     bigint NOT NULL,
  attempts    int NOT NULL DEFAULT 0,
  PRIMARY KEY (email, purpose)
);
-- 删号墓碑：不带 FK、不留邮箱。
CREATE TABLE IF NOT EXISTS account_deletions (
  user_id           uuid PRIMARY KEY,
  provider_uid      text NOT NULL,
  requested_at      bigint NOT NULL,
  source            text NOT NULL,
  apple_revocation  text NOT NULL
);
