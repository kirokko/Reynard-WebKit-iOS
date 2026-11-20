#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify the separate arm64 test-host IPA, not the legacy Gecko IPA format."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import sys
import zipfile


def verify(package, results):
    prefix = 'Payload/ieynecWKTest.app/'
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert len(names) == len(set(names))
        for item in archive.infolist():
            path = PurePosixPath(item.filename)
            assert item.filename.startswith(prefix) and not path.is_absolute() and '..' not in path.parts
            assert ((item.external_attr >> 16) & 0o170000) != 0o120000
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        assert info['CFBundleIdentifier'] == 'net.kirokko.ieynec.webkitprobe'
        assert info['CFBundleDisplayName'] == 'ieynec WK Test'
        assert info['MinimumOSVersion'] == '18.4'
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
        assert info['UIDeviceFamily'] == [1, 2]
        assert 'UIBackgroundModes' not in info
        executable = prefix + info['CFBundleExecutable']
        binary = archive.read(executable)
        header = struct.unpack_from('<8I', binary)
        assert header[0] == 0xfeedfacf and header[1] == 0x0100000c and header[3] == 2, 'Not an arm64 Mach-O executable'
        assert (archive.getinfo(executable).external_attr >> 16) & 0o111, 'Executable bit missing'
        dependencies = []
        offset = 32
        for _ in range(header[4]):
            cmd, size = struct.unpack_from('<II', binary, offset)
            assert size >= 8 and offset + size <= len(binary)
            if cmd in (0xc, 0x80000018, 0x8000001f, 0x80000023):
                start = offset + struct.unpack_from('<I', binary, offset + 8)[0]
                dependencies.append(binary[start:binary.index(b'\0', start, offset + size)].decode())
            offset += size
        assert any('/WebKit.framework/' in name for name in dependencies)
        assert any('/UIKit.framework/' in name for name in dependencies)
        assert not any('Gecko' in name or 'idevice' in name or 'GeckoRuntime' in name for name in dependencies)
        assert b'GeckoRuntime' not in binary and b'RPPairing' not in binary
        assert not any('/PlugIns/' in name or '/Frameworks/' in name for name in names)
        assert not any(name.startswith(prefix + 'ubo/META-INF/') for name in names)
        manifest = json.loads(archive.read(prefix + 'ubo/manifest.json'))
        assert manifest['name'].startswith('[PROBE ONLY]')
        assert manifest['browser_specific_settings']['gecko']['id'] == 'ublock-webkit-probe@kirokko.invalid'
        build = json.loads(archive.read(prefix + 'build.json'))
        assert build['fullUBlockOriginVerified'] is False and build['sideStoreVerified'] is False
        for path, expected in build['addedExtensionDiagnosticFiles'].items():
            assert hashlib.sha256(archive.read(prefix + 'ubo/' + path)).hexdigest() == expected
        for name in ('fixture.html', 'ubo/LICENSE.txt', 'APP-LICENSE.txt', 'ubo/RESEARCH-ONLY.txt', '_CodeSignature/CodeResources'):
            archive.getinfo(prefix + name)
    report = json.loads((results / 'simulator-report.json').read_text())
    provenance = dict(sourceCommit=build['sourceCommit'], bundleIdentifier=info['CFBundleIdentifier'],
        version=info['CFBundleShortVersionString'], buildNumber=info['CFBundleVersion'],
        bytes=package.stat().st_size, sha256=hashlib.sha256(package.read_bytes()).hexdigest(),
        architecture='arm64', minimumIOS=info['MinimumOSVersion'], nativeDependencies=dependencies,
        codesign='ad-hoc; must be development-signed by SideStore before device installation',
        simulatorHostGatesPassed=(report.get('webKitBaseline', {}).get('answer') == 42 and report.get('webKitBaseline', {}).get('status') == 200 and report.get('extensionLoaded') is True),
        controlledDNRPassed=report.get('controlledDNRPassed', False), fullUBlockOriginVerified=False,
        physicalDeviceVerified=False, sideStoreVerified=False,
        warning='Separate disposable test host. Not the original UI migration. No enabled default ad lists. Plugin failures remain visible.')
    (results / 'ieynec-WK-Test.ipa.provenance.json').write_bytes((json.dumps(provenance, indent=2) + '\n').encode())
    (results / 'SHA256SUMS.txt').write_bytes((provenance['sha256'] + '  ' + package.name + '\n').encode())
    print(json.dumps(provenance, indent=2))
    return provenance


if __name__ == '__main__':
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
