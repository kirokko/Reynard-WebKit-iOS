#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds ONLY the disposable test host, never the legacy Gecko project.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/wk-device-probe.XXXXXX")
results="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/wk-device-probe-results"
mkdir -p "$results"
exec > >(tee "$results/build.log") 2>&1
xcodebuild -version > "$results/toolchain.txt"
device_app="$work/Payload/ieynecWKTest.app"
mkdir -p "$device_app"
curl --fail --location --retry 2 --max-time 120 \
  https://github.com/kirokko/uBlock-Origin-WebKit/releases/download/v0.1.0-alpha.1/ubo-webkit-v0.1.0-alpha.1-probe-only.zip \
  -o "$work/ubo.zip"
python3 - "$work/ubo.zip" "$device_app" <<'PY'
import hashlib, json, os, pathlib, plistlib, shutil, sys, zipfile
package, app = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
pinned = '4a1e45c53ffab5c04f8a5a8015a6ed11d045c603ea9a76e7b88e6dc7c09942c2'
assert hashlib.sha256(package.read_bytes()).hexdigest() == pinned, 'Probe input hash mismatch'
ubo = app / 'ubo'
with zipfile.ZipFile(package) as archive:
    assert len(archive.infolist()) < 10000
    assert sum(i.file_size for i in archive.infolist()) < 80 * 1024 * 1024
    seen = set()
    for item in archive.infolist():
        path = pathlib.PurePosixPath(item.filename)
        assert not path.is_absolute() and '..' not in path.parts and '\\' not in item.filename and ':' not in item.filename
        assert item.filename not in seen and not ((item.external_attr >> 16) & 0o170000 == 0o120000)
        seen.add(item.filename)
        target = ubo.joinpath(*path.parts)
        if item.is_dir(): target.mkdir(parents=True, exist_ok=True); continue
        target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(archive.read(item))
    for item in archive.infolist():
        if not item.is_dir(): assert archive.read(item) == ubo.joinpath(*pathlib.PurePosixPath(item.filename).parts).read_bytes()
manifest = json.loads((ubo / 'manifest.json').read_text())
assert manifest['browser_specific_settings']['gecko']['id'] == 'ublock-webkit-probe@kirokko.invalid'
assert manifest['name'].startswith('[PROBE ONLY]') and not (ubo / 'META-INF').exists()
overlay = {}
for name in ('device-status.html', 'device-status.js'):
    source = pathlib.Path('tests/iphone-host') / name; target = ubo / 'port' / name
    assert not target.exists(), 'Refusing to shadow extension source'
    shutil.copyfile(source, target); overlay['port/' + name] = hashlib.sha256(target.read_bytes()).hexdigest()
shutil.copyfile('tests/iphone-host/fixture.html', app / 'fixture.html')
shutil.copyfile('LICENSE', app / 'APP-LICENSE.txt')
(app / 'build.json').write_text(json.dumps(dict(sourceCommit=os.environ['GITHUB_SHA'],
    sourceRepository='https://github.com/kirokko/Reynard-WebKit-iOS',
    kind='disposable-test-host-not-production-browser', extensionInputSHA256=pinned,
    extensionInputRelease='https://github.com/kirokko/uBlock-Origin-WebKit/releases/tag/v0.1.0-alpha.1',
    correspondingUpstreamSource='https://github.com/kirokko/uBlock-Origin-WebKit/releases/download/v0.1.0-alpha.1/uBlock-1.76.4-upstream-source.tar.gz',
    addedExtensionDiagnosticFiles=overlay, fullUBlockOriginVerified=False, sideStoreVerified=False), indent=2) + '\n')
info = dict(CFBundleIdentifier='net.kirokko.ieynec.webkitprobe', CFBundleExecutable='ieynecWKTest',
    CFBundleName='ieynecWKTest', CFBundleDisplayName='ieynec WK Test', CFBundlePackageType='APPL',
    CFBundleInfoDictionaryVersion='6.0', CFBundleDevelopmentRegion='en',
    CFBundleVersion=os.environ.get('GITHUB_RUN_NUMBER', '1'), CFBundleShortVersionString='0.0.1',
    MinimumOSVersion='18.4', LSRequiresIPhoneOS=True, UIDeviceFamily=[1, 2],
    CFBundleSupportedPlatforms=['iPhoneOS'], UILaunchScreen={},
    UIRequiredDeviceCapabilities=['arm64'], UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],
    NSAppTransportSecurity=dict(NSAllowsArbitraryLoadsInWebContent=True, NSAllowsLocalNetworking=True),
    NSLocationWhenInUseUsageDescription='测试网页可能请求定位，由你决定。请勿用于真实账号或敏感网页。')
with (app / 'Info.plist').open('wb') as file: plistlib.dump(info, file)
PY
sources=(tests/iphone-host/DeviceHost.m tests/iphone-host/FixtureServer.m)
flags=(-fobjc-arc -fmodules -Werror=implicit-function-declaration -framework UIKit -framework WebKit -framework Foundation)
ios_sdk=$(xcrun --sdk iphoneos --show-sdk-path)
sim_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphoneos clang "${flags[@]}" -isysroot "$ios_sdk" -target arm64-apple-ios18.4 \
  "${sources[@]}" -o "$device_app/ieynecWKTest"
codesign --force --sign - --timestamp=none "$device_app"
codesign --verify --deep --strict "$device_app"
xcrun --sdk iphoneos lipo -info "$device_app/ieynecWKTest" > "$results/device-architecture.txt"
sim_app="$work/Simulator/ieynecWKTest.app"
mkdir -p "$(dirname "$sim_app")"; cp -R "$device_app" "$sim_app"
python3 - "$sim_app/Info.plist" <<'PY'
import plistlib, sys
p=sys.argv[1]
with open(p,'rb') as f: info=plistlib.load(f)
info['CFBundleSupportedPlatforms']=['iPhoneSimulator']
with open(p,'wb') as f: plistlib.dump(info,f)
PY
xcrun --sdk iphonesimulator clang "${flags[@]}" -isysroot "$sim_sdk" -target "$(uname -m)-apple-ios18.4-simulator" \
  "${sources[@]}" -o "$sim_app/ieynecWKTest"
codesign --force --sign - --timestamp=none "$sim_app"
xcrun simctl list devices available --json > "$results/devices.json"
device=$(node - "$results/devices.json" <<'NODE'
const fs=require('node:fs');
for(const [runtime, devices] of Object.entries(JSON.parse(fs.readFileSync(process.argv[2])).devices).reverse()) {
  if(!runtime.includes('.iOS-'))continue;
  const device=devices.find(d=>d.isAvailable&&d.name.startsWith('iPhone'));
  if(device){console.log(device.udid);break;}
}
NODE
)
[[ -n "$device" ]] || { echo 'No iPhone Simulator'; exit 1; }
xcrun simctl boot "$device" > "$results/boot.log" 2>&1 || true
xcrun simctl bootstatus "$device" -b
cleanup() { xcrun simctl terminate "$device" net.kirokko.ieynec.webkitprobe >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun simctl install "$device" "$sim_app"
container=$(xcrun simctl get_app_container "$device" net.kirokko.ieynec.webkitprobe data)
SIMCTL_CHILD_WK_DEVICE_AUTOMATION=1 xcrun simctl launch --terminate-running-process \
  --stdout="$results/native.stdout.log" --stderr="$results/native.stderr.log" "$device" net.kirokko.ieynec.webkitprobe
for attempt in {1..125}; do [[ ! -f "$container/Documents/simulator-report.json" ]] || break; sleep 1; done
[[ -f "$container/Documents/simulator-report.json" ]] || { echo 'Host failed to produce simulator report'; exit 1; }
cp "$container/Documents/simulator-report.json" "$results/"
xcrun simctl io "$device" screenshot "$results/simulator.png"
node - "$results/simulator-report.json" <<'NODE'
const fs=require('node:fs');const r=JSON.parse(fs.readFileSync(process.argv[2]));console.log(JSON.stringify(r,null,2));
if(r.webKitBaseline?.answer!==42||r.webKitBaseline?.status!==200||r.extensionLoaded!==true||r.extensionStoragePersistent!==false)
  throw Error('Test-host gates failed: WK navigation/JS, fixture, isolated native context load required');
if(r.controlledDNRPassed!==true)console.log('::warning::uBO network functionality did not pass; this IPA remains a diagnostic host, NOT a working full-uBO browser.');
if(r.fullUBlockOriginVerified!==false)throw Error('Do not assert full compatibility');
NODE
python3 - "$work/Payload" "$results/ieynec-WK-Test.ipa" <<'PY'
from pathlib import Path
import sys, zipfile
payload, output = Path(sys.argv[1]), Path(sys.argv[2])
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for file in sorted(payload.rglob('*')):
        if file.is_file(): z.write(file, file.relative_to(payload.parent).as_posix())
PY
python3 tools/ci/Verify-DeviceProbe.py "$results/ieynec-WK-Test.ipa" "$results"
echo 'Device IPA built and checked; NOT physical-device/SideStore verification.'
