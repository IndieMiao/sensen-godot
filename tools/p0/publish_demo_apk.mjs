#!/usr/bin/env node
// P0 internal demo APK → Aliyun OSS (SGODOT-232; the user's choice of 2026-10-09: OSS for now, internal only).
// Like the Journey releases (docs/qa/release-playbook-android-ios.md §1.5, server/deploy/downloads/README.md): one
// immutable directory per build, p0/demo/releases/p0-demo-<YYYYMMDD>-<sha256 first 12>/, holding the APK, release.json
// (the manifest) and SHA256SUMS. Nothing is ever overwritten: an object already at the path must be byte-identical,
// else the script stops; a new build is a new path.
//
//   node tools/p0/publish_demo_apk.mjs --apk build/p0-demo.apk --evidence <evidence.json> --backend <p0 image sha>
//        --check-only     builds the release directory under output/p0-demo/release/ and checks the live server; no upload
//        --publish        uploads it to OSS, then downloads it back: full SHA-256, Range 206, manifest and checksum bytes
//        --dry-run        (with --check-only only) accepts a …00 dry-run versionCode
//
// Inputs: output/p0-demo/build.json, written by tools/p0/build_demo_apk.sh for this exact APK (the script checks the
// hash), and an evidence.json {sha256, emulator_validation, physical_installation_verified, notes?} saying what was
// really verified on this APK; the manifest copies those two flags, never more (playbook: no claims not made).
// Publishing needs the user's approval each time (AGENTS.md: the demo is internal only). The Update button a player
// sees opens the URL the server sends with 426 (deploy-hk.sh min-version <code> <url>), so the URL printed here is
// what a later min-version uses; the APK itself carries no update address.
// Needs the aliyun CLI with ossutil 2.x (`aliyun ossutil version`; 2.4.0 on 2026-10-09), logged in for bucket sensenjoy.
import {execFile} from 'node:child_process';
import {promisify, isDeepStrictEqual} from 'node:util';
import {readFile, writeFile, mkdir, copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const arg = (name) => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : undefined; };
const has = (name) => process.argv.includes(name);
assert(has('--check-only') !== has('--publish'), 'select exactly one mode: --check-only or --publish');
assert(!(has('--dry-run') && has('--publish')), 'a dry run is never published');
const apkPath = arg('--apk'), evidencePath = arg('--evidence'), backend = arg('--backend');
assert(apkPath && evidencePath && backend, 'usage: --apk <apk> --evidence <evidence.json> --backend <p0 image sha>');

const run = promisify(execFile);
const API = 'https://farm.sensenjoy.cn/preview/p0/v1';
const PACKAGE = 'com.sensen.p0demo';
const CERTIFICATE = '38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673';   // this Mac's debug keystore
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

const apk = await readFile(apkPath), hash = digest(apk);
const build = JSON.parse(await readFile('output/p0-demo/build.json', 'utf8'));
assert.equal(build.sha256, hash, 'output/p0-demo/build.json is not for this APK: rebuild, or pass the APK that was built last');
assert.equal(build.package, PACKAGE);
assert.equal(build.signer_sha256, CERTIFICATE, 'demo updates must keep the same certificate');
assert.equal(build.server, API, 'the APK must point at the Hong Kong P0 server');
assert.equal(build.key_baked, true, 'the demo key is missing from the APK');
assert.equal(build.version_baked, build.version_code, 'x-p0-version must equal the versionCode');
assert.match(build.version_name, /^\d+\.\d+\.\d+$/, 'versionName like 0.1.0');
const code = String(build.version_code);
assert.match(code, /^20\d{6}\d{2}$/, 'versionCode YYYYMMDDNN');
if (!has('--dry-run')) assert(!code.endsWith('00'), 'a …00 versionCode is a dry run and is never published');
assert.equal(build.source_dirty, false, 'built from uncommitted changes');
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
const health = await (await fetch(API + '/healthz', {signal: AbortSignal.timeout(20000), cache: 'no-store'})).json();
assert.equal(health.ok, true);
assert.equal(health.maintenance?.on, false, 'the P0 server is in maintenance');

const releaseId = 'p0-demo-' + code.slice(0, 8);
const name = releaseId + '-' + hash.slice(0, 12), path = 'p0/demo/releases/' + name;
const filename = `sensen-p0-demo-${build.version_name}.apk`;
const url = `https://oss.sensenjoy.cn/${path}/${filename}`;
const manifest = {package: PACKAGE, version: build.version_name, versionCode: build.version_code, bytes: apk.length,
  sha256: hash, certificate_sha256: CERTIFICATE, api: API, backend_image: 'p0-server:' + backend, client_release: releaseId,
  source_commit: build.source_commit, url, internal_only: true, server_min_version_at_publish: health.min_version ?? 0,
  emulator_validation: evidence.emulator_validation, physical_installation_verified: evidence.physical_installation_verified};
// One versionCode, one APK: a second build the same day with an unchanged code would be indistinguishable to
// min-version (周瑜 on #163). Other releases of this day are listed (read-only) and their manifests compared.
const dayPrefix = `oss://sensenjoy/p0/demo/releases/${releaseId}-`;
const listed = (await run('aliyun', ['ossutil', 'ls', dayPrefix, '-d'], {timeout: 60000})).stdout;
for (const other of new Set(listed.match(/oss:\/\/sensenjoy\/p0\/demo\/releases\/[^/\s]+\//g) ?? [])) {
  if (other.endsWith(`/${name}/`)) continue;
  const res = await fetch(`https://oss.sensenjoy.cn/${other.slice('oss://sensenjoy/'.length)}release.json`, {signal: AbortSignal.timeout(30000), cache: 'no-store'});
  if (res.status === 404) continue;
  assert.equal(res.status, 200, `cannot read ${other}release.json`);
  const theirs = await res.json();
  assert.notEqual(theirs.versionCode, build.version_code, `versionCode ${code} is already ${other} (sha ${theirs.sha256}): build again with --code …${String(Number(code.slice(8)) + 1).padStart(2, '0')}`);
}
const dir = `output/p0-demo/release/${has('--dry-run') ? 'dryrun-' : ''}${name}`;
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
    oss: `oss://sensenjoy/${path}/`}, null, 2));
  process.exit(0);
}

// The path is immutable: an object already there must be byte-identical (a re-run after a failed read-back), never
// replaced. ossutil's --ignore-existing skips silently, so look first (周瑜 on #163) and stop on any difference.
const base = `https://oss.sensenjoy.cn/${path}/`;
for (const file of [filename, 'release.json', 'SHA256SUMS']) {
  const head = await fetch(base + file, {method: 'HEAD', signal: AbortSignal.timeout(30000), cache: 'no-store'});
  if (head.status === 404) {
    await run('aliyun', ['ossutil', 'cp', `${dir}/${file}`, `oss://sensenjoy/${path}/${file}`,
      '--acl', 'public-read', '--ignore-existing', '--quiet'], {timeout: 600000});
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
