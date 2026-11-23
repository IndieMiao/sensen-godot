"""Pre-seed the Gradle wrapper distribution in build_worker_apk.sh's disposable Gradle home (C-64).

The worker build starts every export with an empty GRADLE_USER_HOME, so the wrapper downloads
the whole Gradle distribution each time. A host may keep the official distribution zip in a
seed directory with the wrapper's own layout (`<dist name>/<url hash>/<dist>.zip`, like
~/.gradle/wrapper/dists). Only that zip is copied, after its SHA-256 matches the official value;
dependency caches are never shared. Without a usable seed nothing is written and the wrapper
downloads exactly as before. Messages go to stderr only: stdout of the build is the receipt.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlparse

SEED_ENV = 'CARDIGAN_GRADLE_DIST_SEED'
DEFAULT_SEED = '.local/share/sensen-godot/gradle-wrapper-dists'  # under $HOME
# Official digests published at https://gradle.org/release-checksums/ ; add a version only from there.
OFFICIAL_SHA256 = {
    'gradle-8.11.1-bin.zip': 'f397b287023acdba1e9f6fc5ea72d22dd63669d59ed4a289a29b1a76eee151c6',
}
WRAPPER_DEFAULTS = {'distributionBase': 'GRADLE_USER_HOME', 'distributionPath': 'wrapper/dists',
                    'zipStoreBase': 'GRADLE_USER_HOME', 'zipStorePath': 'wrapper/dists'}
PREFIX = 'worker APK: Gradle distribution seed'


def note(message):
    print(f'{PREFIX}: {message}', file=sys.stderr)


def seed_dir(env=os.environ):
    if env.get(SEED_ENV):
        return Path(env[SEED_ENV])
    return Path(env.get('HOME') or Path.home()) / DEFAULT_SEED


def read_properties(text):
    # Only the subset the wrapper file uses: key=value lines, '#' comments, backslash escapes.
    props = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line[0] in '#!' or '=' not in line:
            continue
        key, value = line.split('=', 1)
        out, chars = [], iter(value.strip())
        for ch in chars:
            out.append(next(chars, '') if ch == '\\' else ch)
        props[key.strip()] = ''.join(out)
    return props


def url_hash(url):
    # Gradle's PathAssembler: MD5 of the distribution URI, as an unsigned base-36 number.
    n = int(hashlib.md5(url.encode()).hexdigest(), 16)
    digits = '0123456789abcdefghijklmnopqrstuvwxyz'
    out = ''
    while n:
        n, r = divmod(n, 36)
        out = digits[r] + out
    return out or '0'


def plan(properties_text):
    """Return (zip name, relative wrapper dir, expected sha256) or raise ValueError with a reason."""
    props = read_properties(properties_text)
    for key, value in WRAPPER_DEFAULTS.items():
        if props.get(key, value) != value:
            raise ValueError(f'wrapper uses a non-default {key}')
    url = props.get('distributionUrl', '')
    name = Path(urlparse(url).path).name
    if not url.startswith('https://') or not name.endswith('.zip'):
        raise ValueError('wrapper has no https distributionUrl to a zip')
    # Only the built-in official digest is trusted; a value pinned in the template is not a substitute.
    official, pinned = OFFICIAL_SHA256.get(name), props.get('distributionSha256Sum', '').lower() or None
    if not official:
        raise ValueError(f'no official sha256 known for {name}')
    if pinned and official != pinned:
        raise ValueError(f'pinned sha256 for {name} differs from the official value')
    return name, Path(name[:-len('.zip')]) / url_hash(url), official


def seed(properties, gradle_home, state, source_root):
    """Copy a verified seed zip into the fresh Gradle home. Never fails the build: falls back to download."""
    if not source_root.is_dir():
        return False  # No seed on this host: unchanged behavior, no output.
    try:
        name, relative, expected = plan(properties.read_text())
    except (OSError, ValueError) as error:
        note(f'not used ({error}); Gradle wrapper will download the distribution')
        return False
    source, target_dir = source_root / relative / name, gradle_home / 'wrapper/dists' / relative
    target = target_dir / name
    if target.exists() or target.is_symlink():
        note(f'not used ({name} already present in the Gradle home)')
        return False
    part = target_dir / (name + '.seed-part')
    digest = hashlib.sha256()
    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        # Hash the copy itself, so a seed replaced mid-copy can never be installed unverified.
        with open(source, 'rb') as src, open(part, 'xb') as dst:
            for block in iter(lambda: src.read(1 << 20), b''):
                digest.update(block)
                dst.write(block)
    except OSError as error:
        part.unlink(missing_ok=True)
        reason = 'no ' + name if isinstance(error, FileNotFoundError) else f'cannot read {name}'
        note(f'not used ({reason} in seed); Gradle wrapper will download the distribution')
        return False
    if digest.hexdigest() != expected:
        part.unlink()
        note(f'not used (sha256 mismatch for {name}: expected {expected}, got {digest.hexdigest()}); '
             'Gradle wrapper will download the distribution')
        return False
    try:
        os.rename(part, target)
        info = target.stat()
        state.write_text(json.dumps({'zip': str(target), 'sha256': expected, 'inode': info.st_ino,
                                     'size': info.st_size, 'mtime_ns': info.st_mtime_ns}) + '\n')
    except OSError:
        for leftover in (part, target, state):
            leftover.unlink(missing_ok=True)
        note(f'not used (cannot install {name} into the Gradle home); Gradle wrapper will download the distribution')
        return False
    note(f'{name} sha256 verified and copied; Gradle wrapper download skipped')
    return True


def check(state):
    """After export: report whether the wrapper used the seeded zip instead of downloading another."""
    if not state.exists():
        return None
    recorded = json.loads(state.read_text())
    target = Path(recorded['zip'])
    try:
        info = target.stat()
    except OSError:
        info = None
    reused = bool(info and (info.st_ino, info.st_size, info.st_mtime_ns) ==
                  (recorded['inode'], recorded['size'], recorded['mtime_ns'])
                  and target.with_name(target.name + '.ok').exists())
    note(f'{target.name} installed from the local seed, not downloaded' if reused else
         f'warning: Gradle wrapper did not use the seeded {target.name}')
    return reused


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest='command', required=True)
    s = sub.add_parser('seed')
    s.add_argument('properties', type=Path, help='gradle/wrapper/gradle-wrapper.properties of the staged build')
    s.add_argument('gradle_home', type=Path, help='the disposable GRADLE_USER_HOME')
    s.add_argument('state', type=Path, help='new file recording the seeded zip, for `check`')
    c = sub.add_parser('check')
    c.add_argument('state', type=Path)
    args = parser.parse_args(argv)
    if args.command == 'seed':
        seed(args.properties, args.gradle_home, args.state, seed_dir())
    else:
        check(args.state)


if __name__ == '__main__':
    main()
