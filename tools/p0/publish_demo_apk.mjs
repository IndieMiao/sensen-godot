#!/usr/bin/env node
// P0 internal demo APK → Aliyun OSS (SGODOT-232; the user's choice of 2026-10-09: OSS for now, internal only).
// Like the Journey releases (docs/qa/release-playbook-android-ios.md §1.5, server/deploy/downloads/README.md): one
// immutable directory per build, p0/demo/releases/p0-demo-<YYYYMMDD>-<sha256 first 12>/, holding the APK, release.json
// (the manifest) and SHA256SUMS. Nothing is ever overwritten: an object already at the path must be byte-identical,
// else the script stops; a new build is a new path.
//
//   node tools/p0/publish_demo_apk.mjs --apk build/p0-demo.apk --evidence <evidence.json> [--backend <p0 image sha>]
//        --backend        the server image this APK goes out against. The live P0 names its own in X-P0-Release; left
//                         out, that is what the manifest records, and given, it must be the same image (0.2.23 went out
//                         with the client's commit there while the server stayed on the one before, #717). The preview
//                         instance sends no such header, so with --preview it is required and recorded as given.
//        --ahead-of <sha> with --backend: the APK goes up before its server is deployed (v7, 11-06: the update page that
//                         the wipe's minimum points at must hold a link that already works). The live server must still
//                         run <sha>, the image --backend replaces; --backend is recorded as given. Nothing points at
//                         the new directory until the deploy's own steps do (min-version, the update page).
//        --preview        a 355 preview (auth-preview.md): package com.sensen.p0preview against /preview/p0-next/v1, into
//                         p0/demo/preview/p0-preview-<YYYYMMDD>-<sha12>/, never releases/. Only the preview gate's
//                         min-version (deploy-hk.sh --target preview) may point at it; nothing here sets one.
//        --check-only     builds the release directory under output/p0-demo/release/ and checks the live server; no upload
//        --publish        uploads it to OSS, then downloads it back: full SHA-256, Range 206, manifest and checksum bytes
//        --dry-run        (with --check-only only) accepts a …00 dry-run versionCode
//   P0_OSS_PREFIX=p0/demo/test[/…]   puts the directory there instead of p0/demo/releases: an end-to-end try of a new
//                    bucket or domain with a real APK, never a release (only a test prefix is accepted)
//
// Inputs: output/p0-demo/build.json, written by tools/p0/build_demo_apk.sh for this exact APK (the script checks the
// hash), and an evidence.json {sha256, emulator_validation, physical_installation_verified, notes?} saying what was
// really verified on this APK; the manifest copies those two flags, never more (playbook: no claims not made).
// Publishing needs the user's approval each time (AGENTS.md: the demo is internal only). The Update button a player
// sees opens the URL the server sends with 426 (deploy-hk.sh min-version <code> <url>), so the URL printed here is
// what a later min-version uses; the APK itself carries no update address.
// Needs the aliyun CLI with ossutil 2.x (`aliyun ossutil version`; 2.4.1 on 2026-10-29) and the profile farm-oss2: a RAM
// user limited to the release bucket, kept by the migration side (nothing here reads or prints its keys). The old
// bucket is only listed, with the default profile.
import {execFile} from 'node:child_process';
import {promisify, isDeepStrictEqual} from 'node:util';
import {readFile, writeFile, mkdir, copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const arg = (name) => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : undefined; };
const has = (name) => process.argv.includes(name);
assert(has('--check-only') !== has('--publish'), 'select exactly one mode: --check-only or --publish');
assert(!(has('--dry-run') && has('--publish')), 'a dry run is never published');
const apkPath = arg('--apk'), evidencePath = arg('--evidence');
assert(apkPath && evidencePath, 'usage: --apk <apk> --evidence <evidence.json> [--backend <p0 image sha>] [--preview]');
const PREVIEW = has('--preview');

const run = promisify(execFile);
const API = PREVIEW ? 'https://farm.sensenjoy.cn/preview/p0-next/v1' : 'https://farm.sensenjoy.cn/preview/p0/v1';
const PACKAGE = PREVIEW ? 'com.sensen.p0preview' : 'com.sensen.p0demo';
const CERTIFICATE = '38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673';   // this Mac's debug keystore
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
// Where a release goes (the user's "oss2 ok", 10-29): the liusen account's US bucket behind oss2.sensenjoy.cn. The old
// bucket behind oss.sensenjoy.cn stays as it is — every link sent so far and the live gate's update url point there —
// and is still read for the same-day versionCode check, so the day of the switch misses nothing.
// The profile is the aliyun CLI's, so it goes before `ossutil`: after it, ossutil reads it as a section of its own
// ~/.ossutilconfig and falls back to the default account without a word (迁移方 on #554). Not ALIBABA_CLOUD_PROFILE either,
// which would take the old bucket's listing to the new account too.
const OSS = {host: 'https://oss2.sensenjoy.cn', bucket: 'liusen-gensen-cdn-us-775292',
  cli: ['--profile', 'farm-oss2'], ossutil: ['--region', 'us-west-1']};
const OLD_OSS = {host: 'https://oss.sensenjoy.cn', bucket: 'sensenjoy', cli: [], ossutil: []};
const CONTENT_TYPES = {'.apk': 'application/vnd.android.package-archive', '.json': 'application/json', SHA256SUMS: 'text/plain; charset=utf-8'};
const contentType = (file) => CONTENT_TYPES[file] ?? CONTENT_TYPES[file.slice(file.lastIndexOf('.'))];

const apk = await readFile(apkPath), hash = digest(apk);
const build = JSON.parse(await readFile('output/p0-demo/build.json', 'utf8'));
assert.equal(build.sha256, hash, 'output/p0-demo/build.json is not for this APK: rebuild, or pass the APK that was built last');
assert.equal(build.package, PACKAGE);
assert.equal(build.signer_sha256, CERTIFICATE, 'demo updates must keep the same certificate');
assert.equal(build.server, API, PREVIEW ? 'a preview APK must point at the preview server' : 'the APK must point at the live P0 server');
assert.equal(build.key_baked, true, 'the demo key is missing from the APK');
// An internal voice test export (build_demo_apk.sh with P0_DEV_CLEARTEXT) lets plain traffic through to a LAN host:
// never a release. A build.json from before the switch has neither field, so only a true / a host refuses.
assert(!build.dev_cleartext && build.network_security_config !== true,
  'this APK was built with P0_DEV_CLEARTEXT (plain traffic allowed for an internal test): rebuild without it to publish');
assert.equal(build.version_baked, build.version_code, 'x-p0-version must equal the versionCode');
assert.equal(build.native_ok, true, 'Mapbox / LiveKit / the token are missing from the APK: ' + (build.native_missing ?? []).join(', '));
assert.equal(build.legal_ok, true, 'license texts are missing from the APK: ' + (build.legal_missing ?? ['(built before the check)']).join(', '));
assert.match(build.version_name, /^\d+\.\d+\.\d+$/, 'versionName like 0.1.0');
const code = String(build.version_code);
assert.match(code, /^20\d{6}\d{2}$/, 'versionCode YYYYMMDDNN');
if (!has('--dry-run')) assert(!code.endsWith('00'), 'a …00 versionCode is a dry run and is never published');
assert.equal(build.source_dirty, false, 'built from uncommitted changes');
// The map and voice libraries and the Mapbox token must be in the APK itself (SGODOT-261: a demo without them had a
// black map). Read the APK's own entries, not only what build.json says.
const entries = new Set((await run('unzip', ['-Z1', apkPath], {maxBuffer: 64 * 1024 * 1024})).stdout.split('\n'));
const nativeMissing = ['lib/arm64-v8a/libmapbox-maps.so', 'lib/arm64-v8a/libmapbox-common.so',
  'lib/arm64-v8a/liblkjingle_peerconnection_so.so', 'assets/mapbox_token.txt'].filter((n) => !entries.has(n));
assert.equal(nativeMissing.length, 0, 'the APK lacks ' + nativeMissing.join(', ') + ': build with the Mapbox / plugin setup');
// An all_resources export packs untracked scenes, scripts and json as well (周瑜 on #163); only stray .uid files pass.
assert(Array.isArray(build.untracked_exported), 'build.json predates the untracked check: rebuild with the current script');
assert(build.untracked_exported_count === build.untracked_exported.length, 'too many untracked files to list: clean the tree');
const stray = build.untracked_exported.filter((f) => !f.endsWith('.uid'));
assert.equal(stray.length, 0, 'untracked files went into the APK: ' + stray.join(', '));
const evidence = JSON.parse(await readFile(evidencePath, 'utf8'));
assert.equal(evidence.sha256, hash, 'evidence is not for this exact APK');
assert.equal(typeof evidence.emulator_validation, 'boolean');
assert.equal(typeof evidence.physical_installation_verified, 'boolean');

// The live server this APK talks to: up, not in maintenance; the minimum version is recorded, never changed here.
const healthResponse = await fetch(API + '/healthz', {signal: AbortSignal.timeout(20000), cache: 'no-store'});
const health = await healthResponse.json();
assert.equal(health.ok, true);
assert.equal(health.maintenance?.on, false, 'the P0 server is in maintenance');
// The image this APK goes out against: the live server's own word when it gives one (see --backend above).
const liveRelease = healthResponse.headers.get('x-p0-release');
const IMAGE = /^[0-9a-f]{7,40}$/;
const sameImage = (a, b) => IMAGE.test(a) && IMAGE.test(b) && (a.startsWith(b) || b.startsWith(a));
let backend = arg('--backend');
// A typo, or `--backend` with its value left off (the next flag read as one), never goes into the manifest (后裔 on #719).
if (has('--backend')) assert(IMAGE.test(backend ?? ''), `--backend wants an image sha (7–40 hex), not ${JSON.stringify(backend)}`);
const aheadOf = arg('--ahead-of');
if (has('--ahead-of')) {
  assert(IMAGE.test(aheadOf ?? '') && backend, '--ahead-of <the image the server runs now> goes with --backend <the image to come>');
  assert(!sameImage(backend, aheadOf), `--ahead-of ${aheadOf} is --backend itself: leave --ahead-of out`);
  assert(liveRelease && sameImage(aheadOf, liveRelease), `the server runs ${liveRelease ?? 'an unnamed image'}, not --ahead-of ${aheadOf}`);
  console.log(`published ahead of the deploy: the server runs ${liveRelease}, the manifest records ${backend}`);
} else if (liveRelease) {
  if (backend) assert(sameImage(backend, liveRelease), `--backend ${backend} is not the image the server runs (X-P0-Release ${liveRelease}): leave it out, deploy first, or --ahead-of ${liveRelease}`);
  else backend = liveRelease;
} else {
  assert(backend, `${API} sends no X-P0-Release: pass --backend <the image it runs>`);
}

const PREFIX = process.env.P0_OSS_PREFIX ?? (PREVIEW ? 'p0/demo/preview' : 'p0/demo/releases');
assert.match(PREFIX, PREVIEW ? /^p0\/demo\/(preview|test(\/[a-z0-9-]+)*)$/ : /^p0\/demo\/(releases|test(\/[a-z0-9-]+)*)$/,
  PREVIEW ? 'P0_OSS_PREFIX is p0/demo/preview or under p0/demo/test' : 'P0_OSS_PREFIX is p0/demo/releases or under p0/demo/test');
const LIVE_PREFIX = PREVIEW ? 'p0/demo/preview' : 'p0/demo/releases';
const releaseId = (PREVIEW ? 'p0-preview-' : 'p0-demo-') + code.slice(0, 8);
const name = releaseId + '-' + hash.slice(0, 12), path = `${PREFIX}/${name}`;
const filename = `sensen-${PREVIEW ? 'p0-preview' : 'p0-demo'}-${build.version_name}.apk`;
const url = `${OSS.host}/${path}/${filename}`;
const manifest = {package: PACKAGE, version: build.version_name, versionCode: build.version_code, bytes: apk.length,
  sha256: hash, certificate_sha256: CERTIFICATE, api: API, backend_image: 'p0-server:' + backend, client_release: releaseId,
  source_commit: build.source_commit, url, internal_only: true, server_min_version_at_publish: health.min_version ?? 0,
  emulator_validation: evidence.emulator_validation, physical_installation_verified: evidence.physical_installation_verified,
  ...(PREVIEW ? {preview: true} : {})};
// One versionCode, one APK: a second build the same day with an unchanged code would be indistinguishable to
// min-version (周瑜 on #163). Other releases of this day are listed (read-only) and their manifests compared, in the
// release bucket and in the old one (which never held a preview).
for (const where of PREVIEW ? [OSS] : [OSS, OLD_OSS]) {
  const root = `oss://${where.bucket}/`;
  const listed = (await run('aliyun', [...where.cli, 'ossutil', 'ls', `${root}${PREFIX}/${releaseId}-`, '-d', ...where.ossutil], {timeout: 60000})).stdout;
  for (const other of new Set(listed.split(/\s+/).filter((w) => w.startsWith(`${root}${PREFIX}/`) && w.endsWith('/')))) {
    if (where === OSS && other.endsWith(`/${name}/`)) continue;
    const res = await fetch(`${where.host}/${other.slice(root.length)}release.json`, {signal: AbortSignal.timeout(30000), cache: 'no-store'});
    if (res.status === 404) continue;
    assert.equal(res.status, 200, `cannot read ${other}release.json`);
    const theirs = await res.json();
    assert.notEqual(theirs.versionCode, build.version_code, `versionCode ${code} is already ${other} (sha ${theirs.sha256}): build again with --code …${String(Number(code.slice(8)) + 1).padStart(2, '0')}`);
  }
}
const dir = `output/p0-demo/release/${has('--dry-run') ? 'dryrun-' : ''}${PREFIX === LIVE_PREFIX ? '' : 'test-'}${name}`;
await mkdir(dir, {recursive: true});
const manifestBytes = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
const checksumBytes = Buffer.from(`${hash}  ${filename}\n`);
await copyFile(apkPath, `${dir}/${filename}`);
await writeFile(`${dir}/release.json`, manifestBytes);
await writeFile(`${dir}/SHA256SUMS`, checksumBytes);
await writeFile(`${dir}/server-health.json`, JSON.stringify(health, null, 2) + '\n');
assert.equal(digest(await readFile(`${dir}/${filename}`)), hash);
if (has('--check-only')) {
  console.log(JSON.stringify({preflight_passed: true, publishing: false, dry_run: has('--dry-run'), dir, url,
    oss: `oss://${OSS.bucket}/${path}/`}, null, 2));
  process.exit(0);
}

// The path is immutable: an object already there must be byte-identical (a re-run after a failed read-back), never
// replaced. ossutil's --ignore-existing skips silently, so look first (周瑜 on #163) and stop on any difference.
const base = `${OSS.host}/${path}/`;
for (const file of [filename, 'release.json', 'SHA256SUMS']) {
  const head = await fetch(base + file, {method: 'HEAD', signal: AbortSignal.timeout(30000), cache: 'no-store'});
  if (head.status === 404) {
    await run('aliyun', [...OSS.cli, 'ossutil', 'cp', `${dir}/${file}`, `oss://${OSS.bucket}/${path}/${file}`,
      '--acl', 'public-read', '--content-type', contentType(file), '--ignore-existing', '--quiet', ...OSS.ossutil], {timeout: 600000});
    continue;
  }
  assert.equal(head.status, 200, `${file}: unexpected HEAD ${head.status}`);
  const there = Buffer.from(await (await fetch(base + file, {signal: AbortSignal.timeout(600000), cache: 'no-store'})).arrayBuffer());
  assert.equal(digest(there), digest(await readFile(`${dir}/${file}`)),
    `${path}/${file} already exists with different bytes: this immutable path is taken, do not overwrite it`);
  console.log(JSON.stringify({phase: 'already_uploaded', file}));
}
console.log(JSON.stringify({phase: 'oss_uploaded', url}));
const response = await fetch(url, {signal: AbortSignal.timeout(600000), cache: 'no-store'});
assert.equal(response.status, 200);
assert.equal(response.headers.get('content-type'), 'application/vnd.android.package-archive');
const bytes = Buffer.from(await response.arrayBuffer());
assert.equal(bytes.length, apk.length);
assert.equal(digest(bytes), hash);
const start = 1048576, end = 2097151;
const range = await fetch(url, {headers: {range: `bytes=${start}-${end}`}, signal: AbortSignal.timeout(90000)});
assert.equal(range.status, 206);
assert.equal(range.headers.get('content-range'), `bytes ${start}-${end}/${apk.length}`);
assert(Buffer.from(await range.arrayBuffer()).equals(apk.subarray(start, end + 1)), 'Range bytes differ');
const manifestResponse = await fetch(base + 'release.json', {signal: AbortSignal.timeout(30000), cache: 'no-store'});
assert.equal(manifestResponse.status, 200, 'release.json not readable');
const publicManifest = Buffer.from(await manifestResponse.arrayBuffer());
assert(publicManifest.equals(manifestBytes), 'public manifest differs');
assert(isDeepStrictEqual(JSON.parse(publicManifest.toString()), manifest));
const checksumResponse = await fetch(base + 'SHA256SUMS', {signal: AbortSignal.timeout(30000), cache: 'no-store'});
assert.equal(checksumResponse.status, 200, 'SHA256SUMS not readable');
const publicChecksum = Buffer.from(await checksumResponse.arrayBuffer());
assert(publicChecksum.equals(checksumBytes), 'public checksum differs');
const verification = {passed: true, url, full_download_verified: true, sha256: hash, bytes: apk.length,
  range_206_verified: true, manifest_verified: true, checksum_verified: true};
await writeFile(`${dir}/verification.json`, JSON.stringify(verification, null, 2) + '\n');
console.log(JSON.stringify({...manifest, downloads_verified: true}, null, 2));
