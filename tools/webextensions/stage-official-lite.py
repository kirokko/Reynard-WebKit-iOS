#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Stage only the pinned official Safari uBO Lite package, without modifications.

Not a generic user-XPI installer. No custom parser, rule compiler, bootstrap,
renaming, background replacement or configuration seed is added.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import stat
import zipfile

PIN_FILE = Path(__file__).with_name('official-lite.json')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def stage(package, output):
    pin = json.loads(PIN_FILE.read_text(encoding='utf-8'))
    data = package.read_bytes()
    if len(data) != pin['bytes'] or digest(data) != pin['sha256']:
        raise ValueError('Not the exact pinned official Safari Lite package')
    if output.exists() or output.is_symlink():
        raise FileExistsError('Refusing to merge into any existing profile/directory')
    with zipfile.ZipFile(package) as archive:
        items = archive.infolist()
        if len(items) > 5000 or sum(i.file_size for i in items) > 64 * 1024 * 1024:
            raise ValueError('Package exceeds pinned-bundle limits')
        paths = set()
        for item in items:
            path = PurePosixPath(item.filename)
            key = path.as_posix().casefold()
            if (path.is_absolute() or '..' in path.parts or not path.parts or
                    chr(92) in item.filename or ':' in item.filename or key in paths or
                    stat.S_ISLNK(item.external_attr >> 16) or item.file_size > 16 * 1024 * 1024):
                raise ValueError('Unsafe/duplicate archive path: ' + item.filename)
            paths.add(key)
        manifest = json.loads(archive.read('manifest.json'))
        if (manifest['version'] != pin['version'] or manifest['manifest_version'] != pin['manifestVersion'] or
                manifest['background'] != pin['background'] or
                manifest['browser_specific_settings']['safari']['strict_min_version'] != pin['minimumSafari']):
            raise ValueError('Official package identity/shape differs from the pin')
        if b'GNU GENERAL PUBLIC LICENSE' not in archive.read('LICENSE.txt'):
            raise ValueError('GPL notice missing')
        # Create exclusively, only after validating the pinned package. Never
        # remove or merge an existing directory, even if it appears disposable.
        output.mkdir(parents=True, exist_ok=False)
        files = {}
        try:
            for item in items:
                target = output.joinpath(*PurePosixPath(item.filename).parts)
                if item.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                original = archive.read(item)
                with target.open('xb') as file:
                    file.write(original)
                if target.read_bytes() != original:
                    raise ValueError('Staged file differs: ' + item.filename)
                files[item.filename] = digest(original)
        except BaseException:
            shutil.rmtree(output)  # Only the new directory created by this call.
            raise
    return dict(input=pin, stagedFiles=len(files), files=files,
                stagedBytesUnchanged=True, modifiedFiles=[], addedFiles=[],
                nativeHostCompatibilityVerified=False,
                warning='Byte-preserving staging only, not production integration or native acceptance.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('new_output_directory', type=Path)
    args = parser.parse_args()
    print(json.dumps(stage(args.package, args.new_output_directory), indent=2))
