"""Name-only signing-material guard shared by Android staging, setup and APK readback."""
import argparse
import os
import sys
import zipfile


def check_names(names, *, tracked=False):
    for name in names:
        base = name.replace('\\', '/').rstrip('/').rsplit('/', 1)[-1].casefold()
        if base == 'export_credentials.cfg' or base.endswith(('.keystore', '.jks', '.p12', '.pk8')):
            raise ValueError('unexpected signing material entry')
        if tracked and base == 'mapbox_token.txt':
            raise ValueError('unexpected tracked Mapbox runtime configuration')


def check_template(path):
    # ZIP central directory only. In particular do not call testzip() here:
    # CRC validation decompresses member bodies, including unapproved inputs.
    with zipfile.ZipFile(path) as archive:
        check_names(archive.namelist())


if __name__ == '__main__':
    sub = argparse.ArgumentParser(description=__doc__)
    cmds = sub.add_subparsers(dest='cmd', required=True)
    cmds.add_parser('template').add_argument('zip')
    cmds.add_parser('tracked', help='check NUL-delimited names on stdin')
    args = sub.parse_args()
    try:
        if args.cmd == 'template':
            check_template(args.zip)
        else:
            check_names(map(os.fsdecode, sys.stdin.buffer.read().split(b'\0')), tracked=True)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        raise SystemExit(str(exc))
