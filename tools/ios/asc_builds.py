#!/usr/bin/env python3
"""List the latest App Store Connect builds for the Journey app (processing state check after a TestFlight upload).
Run with /tmp/asc-venv/bin/python (needs pyjwt + cryptography). Key: ~/.appstoreconnect/private_keys/AuthKey_KQ7J86X34J.p8."""
import json, os, sys, time, urllib.request
import jwt

KEY_ID = os.environ.get("ASC_KEY_ID", "KQ7J86X34J")
ISSUER = os.environ.get("ASC_ISSUER_ID", "fdc8f15b-4cb7-4ddb-a8ac-899e1e35ce4c")
APP_ID = os.environ.get("ASC_APP_ID", "6815092667")
key_path = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
now = int(time.time())
token = jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                   open(key_path).read(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
limit = sys.argv[1] if len(sys.argv) > 1 else "5"
url = f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit={limit}&include=preReleaseVersion"
req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
data = json.load(urllib.request.urlopen(req, timeout=30))
versions = {i["id"]: i["attributes"]["version"] for i in data.get("included", []) if i["type"] == "preReleaseVersions"}
for b in data["data"]:
    a = b["attributes"]
    pre = b.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}
    print(json.dumps({"version": versions.get(pre.get("id"), "?"), "build": a["version"], "state": a["processingState"],
                      "uploaded": a["uploadedDate"], "expired": a["expired"]}))
