#!/usr/bin/env bash
# Settings › Legal › Licenses (q(129), 李白): the Mapbox Maps SDK row's full text is the SDK's own LICENSE.md — its
# copyright, the Mapbox TOS and the "Additional Mapbox Maps Android licenses" it bundles — for the version the Android
# build packs (android/build/build.gradle). The AAR does not carry the file, so it comes from that version's tag of
# mapbox-maps-android, unchanged. Run after a Mapbox version bump; test_p0_settings fails until the file matches.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION="$(grep -o 'com.mapbox.maps:android:[0-9.]*' android/build/build.gradle | head -1 | cut -d: -f3)"
[ -n "$VERSION" ] || { echo "no com.mapbox.maps:android version in android/build/build.gradle" >&2; exit 1; }
OUT=assets/p0/legal/mapbox-maps-android-LICENSE.md
curl -fsSL --max-time 60 -o "$OUT" "https://raw.githubusercontent.com/mapbox/mapbox-maps-android/v${VERSION}/LICENSE.md"
grep -q "Mapbox Maps for Android version ${VERSION}" "$OUT" || { echo "$OUT is not the ${VERSION} license" >&2; exit 1; }
echo "$OUT ← mapbox-maps-android v${VERSION} ($(wc -c < "$OUT") bytes)"
