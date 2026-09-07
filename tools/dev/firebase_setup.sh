#!/usr/bin/env bash
# 用已登录的 firebase-tools 账号把一个 GCP 项目配置成可用的 Firebase Auth 项目：
#   1) addFirebase  2) 建 Web 应用并取 Web API key  3) 开启 Email/Password 提供方
#   4) 写 user://firebase.json（开发机）
# 用法：tools/dev/firebase_setup.sh <project-id>
# 前置：firebase login 已完成；账号已在 console.firebase.google.com 接受过 Firebase 服务条款。
# 步骤 3 走 Identity Toolkit Admin API，访问令牌取自 firebase CLI 的 configstore（CLI 每次运行会自动刷新）。
set -euo pipefail
PROJECT="${1:?usage: firebase_setup.sh <project-id>}"
strip() { sed -E 's/\x1b\[[0-9;]*m//g'; }
CFG="$HOME/.config/configstore/firebase-tools.json"
USER_DIR="$HOME/Library/Application Support/Godot/app_userdata/SensenAvatar"

echo "== 1) addFirebase =="
if firebase projects:list 2>/dev/null | strip | grep -q "$PROJECT"; then
  echo "already a Firebase project"
else
  firebase projects:addfirebase "$PROJECT" 2>&1 | strip | grep -vE "^\s*$" | tail -n 3
fi

echo "== 2) web app + sdk config =="
APP_ID=$(firebase apps:list WEB --project "$PROJECT" --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("result") or []; print(r[0]["appId"] if r else "")')
if [ -z "$APP_ID" ]; then
  firebase apps:create WEB gensen-web --project "$PROJECT" 2>&1 | strip | grep -vE "^\s*$" | tail -n 3
  APP_ID=$(firebase apps:list WEB --project "$PROJECT" --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("result") or []; print(r[0]["appId"] if r else "")')
fi
echo "web appId: $APP_ID"
SDK_JSON=$(firebase apps:sdkconfig WEB "$APP_ID" --project "$PROJECT" --json 2>/dev/null)
API_KEY=$(echo "$SDK_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("result",{}); c=r.get("sdkConfig", r); print(c.get("apiKey",""))')
AUTH_DOMAIN=$(echo "$SDK_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("result",{}); c=r.get("sdkConfig", r); print(c.get("authDomain",""))')
[ -n "$API_KEY" ] || { echo "no apiKey in sdkconfig"; echo "$SDK_JSON" | head -c 600; exit 1; }
echo "apiKey: ${API_KEY:0:8}… authDomain: $AUTH_DOMAIN"

echo "== 3) enable Email/Password =="
TOKEN=$(python3 -c 'import json,os; print(json.load(open(os.path.expanduser("~/.config/configstore/firebase-tools.json")))["tokens"]["access_token"])')
# 先确保 Identity Toolkit API 打开（新项目默认关）
curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  "https://serviceusage.googleapis.com/v1/projects/$PROJECT/services/identitytoolkit.googleapis.com:enable" -d '{}' > /tmp/fb_enable.json || true
python3 - <<'PY'
import json; d=json.load(open('/tmp/fb_enable.json')); print("identitytoolkit enable:", "ok" if ("name" in d or d.get("done")) else d.get("error",{}).get("message","?"))
PY
sleep 3
curl -sS -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT/config?updateMask=signIn.email.enabled,signIn.email.passwordRequired" \
  -d '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}' > /tmp/fb_config.json
python3 - <<'PY'
import json; d=json.load(open('/tmp/fb_config.json'))
if "error" in d: print("config PATCH error:", json.dumps(d["error"])[:400]); raise SystemExit(1)
print("email/password enabled:", d.get("signIn",{}).get("email",{}))
PY

echo "== 4) google provider web client (if enabled in console) =="
GOOGLE_CLIENT_ID=$(curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT/defaultSupportedIdpConfigs" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((c.get("clientId","") for c in d.get("defaultSupportedIdpConfigs",[]) if c["name"].endswith("google.com") and c.get("enabled")), ""))' 2>/dev/null || true)
echo "google web client id: ${GOOGLE_CLIENT_ID:-(Google provider not enabled yet — enable it in console: Authentication > Sign-in method > Google)}"

echo "== 5) write user://firebase.json =="
mkdir -p "$USER_DIR"
python3 - "$USER_DIR/firebase.json" "$API_KEY" "$PROJECT" "$AUTH_DOMAIN" "$GOOGLE_CLIENT_ID" <<'PY'
import json,sys,os
p,key,proj,dom,gcid=sys.argv[1:]
d={}
if os.path.exists(p):
    try: d=json.load(open(p))
    except Exception: d={}
d.update({"api_key":key,"project_id":proj,"auth_domain":dom})
if gcid: d["google_web_client_id"]=gcid
json.dump(d, open(p,"w"), indent=2)
print("wrote", p, "keys:", sorted(d))
PY
echo "DONE: project=$PROJECT"
