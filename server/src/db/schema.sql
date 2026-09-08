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

-- 建农场的幂等记录。payload_hash 是必需的：同 key 换地区不能被当成重试
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
CREATE TABLE IF NOT EXISTS farm_snapshots (
  farm_id            uuid PRIMARY KEY REFERENCES farms(id) ON DELETE CASCADE,
  snapshot_revision  int  NOT NULL,
  snapshot_taken_at  bigint NOT NULL,
  body               jsonb NOT NULL,
  blueprint_revision int  NOT NULL,
  content_version    text NOT NULL,
  domain_version     text NOT NULL
);

-- D2（SGODOT-76）账号：社交主线的自有 user id。players 是农场分支的匿名玩家，两者暂不关联。
CREATE TABLE IF NOT EXISTS users (
  id              uuid PRIMARY KEY,
  email           text,
  email_verified  boolean NOT NULL DEFAULT false,
  created_at      bigint NOT NULL,
  last_seen_at    bigint NOT NULL
);

-- 一个用户可有多条身份（provider + 该方 uid）；(provider, provider_uid) 是并发首登的裁判。
CREATE TABLE IF NOT EXISTS user_identities (
  provider          text NOT NULL,
  provider_uid      text NOT NULL,
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sign_in_provider  text,
  created_at        bigint NOT NULL,
  PRIMARY KEY (provider, provider_uid)
);
CREATE INDEX IF NOT EXISTS user_identities_user_idx ON user_identities(user_id);

-- 删号墓碑：不带 FK（用户行已删）。只留 uid 与时间，够证明「删过」和排 Apple
-- revocation 队列，不留邮箱等 PII。
CREATE TABLE IF NOT EXISTS account_deletions (
  user_id           uuid PRIMARY KEY,
  provider_uid      text NOT NULL,
  requested_at      bigint NOT NULL,
  source            text NOT NULL,
  apple_revocation  text NOT NULL
);

-- D2 首版把 display_name 放在了 users 上；资料自 D4 起归 profiles，老库把这列去掉。
ALTER TABLE users DROP COLUMN IF EXISTS display_name;

-- D4-a 资料：用户自己编辑、别人能看的东西，和账号（users）的读写权限与生命周期都不同。
CREATE TABLE IF NOT EXISTS profiles (
  user_id            uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  handle             text UNIQUE,
  display_name       text NOT NULL,
  bio                text NOT NULL DEFAULT '',
  avatar             jsonb,
  following_visible  boolean NOT NULL DEFAULT true,
  created_at         bigint NOT NULL,
  updated_at         bigint NOT NULL
);

-- D4-a 关注：单向；互关即密友由查询判定，不存第二份状态。seen 是「新粉丝」页的未读标记。
CREATE TABLE IF NOT EXISTS follows (
  follower_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followee_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   bigint NOT NULL,
  seen         boolean NOT NULL DEFAULT false,
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);
CREATE INDEX IF NOT EXISTS follows_followee_idx ON follows(followee_id, created_at DESC, follower_id DESC);
CREATE INDEX IF NOT EXISTS follows_follower_idx ON follows(follower_id, created_at DESC, followee_id DESC);

-- D4-b feed：图文动态 + 点赞 + 一级评论。软删（deleted_at）：E1 审核与举报要能回看。
CREATE TABLE IF NOT EXISTS posts (
  id               uuid PRIMARY KEY,
  author_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  idempotency_key  text NOT NULL,
  text             text NOT NULL,
  images           jsonb NOT NULL DEFAULT '[]'::jsonb,
  like_count       int  NOT NULL DEFAULT 0,
  comment_count    int  NOT NULL DEFAULT 0,
  created_at       bigint NOT NULL,
  deleted_at       bigint,
  UNIQUE (author_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS posts_author_idx ON posts(author_id, created_at DESC, id DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS posts_created_idx ON posts(created_at DESC, id DESC) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS post_likes (
  post_id     uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  bigint NOT NULL,
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX IF NOT EXISTS post_likes_user_idx ON post_likes(user_id);

CREATE TABLE IF NOT EXISTS post_comments (
  id          uuid PRIMARY KEY,
  post_id     uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text        text NOT NULL,
  created_at  bigint NOT NULL,
  deleted_at  bigint
);
CREATE INDEX IF NOT EXISTS post_comments_post_idx ON post_comments(post_id, created_at, id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS post_comments_author_idx ON post_comments(author_id);

-- D6 审核：帖子 / 评论的前置过滤结果；approved / pending（进人工队列，可见）/ rejected（拒发）/ hidden（举报或人工下架）。
ALTER TABLE posts ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'approved';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS moderation_categories jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE post_comments ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'approved';
ALTER TABLE post_comments ADD COLUMN IF NOT EXISTS moderation_categories jsonb NOT NULL DEFAULT '[]'::jsonb;
CREATE INDEX IF NOT EXISTS posts_review_idx ON posts(created_at) WHERE moderation_status = 'pending' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS post_comments_review_idx ON post_comments(created_at) WHERE moderation_status = 'pending' AND deleted_at IS NULL;

-- 举报：同一人对同一目标只记一条；target_id 是 text，用户 / 帖子 / 评论都可能是目标，不做外键（目标删了举报记录要留）。
CREATE TABLE IF NOT EXISTS reports (
  id           uuid PRIMARY KEY,
  reporter_id  uuid NOT NULL,
  target_type  text NOT NULL,
  target_id    text NOT NULL,
  reason       text NOT NULL,
  detail       text NOT NULL DEFAULT '',
  created_at   bigint NOT NULL,
  status       text NOT NULL DEFAULT 'open',
  resolved_at  bigint,
  resolved_by  uuid,
  action       text,
  UNIQUE (reporter_id, target_type, target_id)
);
CREATE INDEX IF NOT EXISTS reports_open_idx ON reports(created_at, id) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS reports_target_idx ON reports(target_type, target_id);

-- 拉黑：双向不可见由查询判定。
CREATE TABLE IF NOT EXISTS blocks (
  blocker_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  bigint NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
CREATE INDEX IF NOT EXISTS blocks_blocked_idx ON blocks(blocked_id);

-- 封禁：账号还在（删号是用户的权利，封禁是我们的处置），但所有需要登录的路由 403 BANNED。
CREATE TABLE IF NOT EXISTS account_bans (
  user_id     uuid PRIMARY KEY,
  reason      text NOT NULL,
  banned_by   uuid,
  created_at  bigint NOT NULL
);

-- D3 IM：会话（单聊 / 群聊）、成员、消息（会话内 seq）、每用户 inbox 事件流（用户级 seq，增量同步用）。
CREATE TABLE IF NOT EXISTS conversations (
  id               uuid PRIMARY KEY,
  kind             text NOT NULL,
  title            text,
  created_by       uuid NOT NULL,
  created_at       bigint NOT NULL,
  last_seq         bigint NOT NULL DEFAULT 0,
  last_message_at  bigint
);
CREATE TABLE IF NOT EXISTS conversation_members (
  conversation_id  uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at        bigint NOT NULL,
  last_read_seq    bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS conversation_members_user_idx ON conversation_members(user_id);
-- 一对用户只有一个单聊：(lo, hi) 是并发建会话的裁判。
CREATE TABLE IF NOT EXISTS dm_pairs (
  user_lo          uuid NOT NULL,
  user_hi          uuid NOT NULL,
  conversation_id  uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  PRIMARY KEY (user_lo, user_hi)
);
-- sender_id 不做外键：发送者删号后消息内容清空但行留着，对方的会话不会突然缺一段。
CREATE TABLE IF NOT EXISTS messages (
  id                     uuid PRIMARY KEY,
  conversation_id        uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  seq                    bigint NOT NULL,
  sender_id              uuid NOT NULL,
  client_id              text NOT NULL,
  kind                   text NOT NULL,
  body                   jsonb NOT NULL,
  created_at             bigint NOT NULL,
  deleted_at             bigint,
  moderation_status      text NOT NULL DEFAULT 'approved',
  moderation_categories  jsonb NOT NULL DEFAULT '[]'::jsonb,
  UNIQUE (conversation_id, seq),
  UNIQUE (conversation_id, sender_id, client_id)
);
CREATE TABLE IF NOT EXISTS user_events (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  seq         bigint NOT NULL,
  type        text NOT NULL,
  payload     jsonb NOT NULL,
  created_at  bigint NOT NULL,
  PRIMARY KEY (user_id, seq)
);
CREATE TABLE IF NOT EXISTS user_event_seq (
  user_id   uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  next_seq  bigint NOT NULL DEFAULT 0
);
-- B5 好友位置：每人一行最新位置，不存轨迹；删号级联。
CREATE TABLE IF NOT EXISTS user_locations (
  user_id      uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  lat          double precision NOT NULL,
  lng          double precision NOT NULL,
  accuracy_m   double precision,
  updated_at   bigint NOT NULL
);
-- D7 推送：设备 token（token 唯一；同设备换账号时归属跟着换）。删号级联。
CREATE TABLE IF NOT EXISTS device_tokens (
  token       text PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform    text NOT NULL,
  updated_at  bigint NOT NULL
);
CREATE INDEX IF NOT EXISTS device_tokens_user_idx ON device_tokens(user_id);

