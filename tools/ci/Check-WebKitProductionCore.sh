#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Internal core checks ONLY. No browser IPA, no retired custom-uBO/test-host build.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/wk-production-core.XXXXXX")
results="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/wk-production-core-results"
mkdir -p "$results"
exec > >(tee "$results/build.log") 2>&1
xcodebuild -version > "$results/toolchain.txt"
xcrun --sdk iphoneos --show-sdk-version >> "$results/toolchain.txt"
url=$(node -p "require('./tools/webextensions/official-lite.json').url")
curl --fail --location --retry 2 --max-time 120 "$url" -o "$work/official-lite.zip"
python3 tools/webextensions/test-stage-official-lite.py "$work/official-lite.zip" > "$results/lite-staging-tests.json"
python3 tools/webextensions/stage-official-lite.py "$work/official-lite.zip" "$work/official-lite" > "$results/lite-byte-provenance.json"
ios_sdk=$(xcrun --sdk iphoneos --show-sdk-path)
sim_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun swiftc -sdk "$ios_sdk" -target arm64-apple-ios17.0 -emit-module \
  -module-name ReynardWebKitEngine browser/WebKitEngine/*.swift -o "$work/ReynardWebKitEngine.swiftmodule"
app="$work/WebKitSmoke.app"; mkdir -p "$app"
python3 - "$app/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='local.reynard.WebKitSmoke', CFBundleExecutable='WebKitSmoke',
        CFBundleName='Internal WebKit Core Checks', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1.0', MinimumOSVersion='18.6', UILaunchScreen={}, UIDeviceFamily=[1],
        NSAppTransportSecurity={'NSAllowsLocalNetworking':True}),f)
PY
xcrun swiftc -g -sdk "$sim_sdk" -target "$(uname -m)-apple-ios18.6-simulator" \
  browser/WebKitEngine/*.swift tests/webkit-smoke/*.swift -o "$app/WebKitSmoke"
xcrun simctl list devices available --json > "$results/devices.json"
device=$(node - "$results/devices.json" <<'NODE'
const fs=require('node:fs');
for(const [runtime,devices] of Object.entries(JSON.parse(fs.readFileSync(process.argv[2])).devices).reverse()) {
 if(!runtime.includes('.iOS-'))continue;
 const d=devices.find(d=>d.isAvailable&&d.name.startsWith('iPhone'));if(d){console.log(d.udid);break;}
}
NODE
)
[[ -n "$device" ]] || { echo 'No simulator'; exit 1; }
xcrun simctl boot "$device" > "$results/boot.log" 2>&1 || true
python3 tests/webkit-smoke/server.py > "$results/server.log" 2>&1 &
server_pid=$!
cleanup() { kill "$server_pid" 2>/dev/null || true; xcrun simctl terminate "$device" local.reynard.WebKitSmoke >/dev/null 2>&1 || true; }
trap cleanup EXIT
for attempt in {1..30}; do curl --fail --silent http://127.0.0.1:8765/one.html > /dev/null && break || sleep 1; done
xcrun simctl bootstatus "$device" -b
codesign --force --sign - "$app"
xcrun simctl install "$device" "$app"
container=$(xcrun simctl get_app_container "$device" local.reynard.WebKitSmoke data)
xcrun simctl launch --terminate-running-process --stdout="$results/native.stdout.log" --stderr="$results/native.stderr.log" "$device" local.reynard.WebKitSmoke
for attempt in {1..100}; do [[ ! -f "$container/Documents/result.json" ]] || break; sleep 1; done
[[ -f "$container/Documents/result.json" ]] || { echo 'No core report'; exit 1; }
cp "$container/Documents/result.json" "$results/core.json"
node - "$results/core.json" <<'NODE'
const fs=require('node:fs');const r=JSON.parse(fs.readFileSync(process.argv[2]));console.log(JSON.stringify(r,null,2));
if(r.failures.length||r.passed.length<27)throw Error('Real WebKit core tests failed');
console.log('Core checks only; production UI integration and native official-Lite runtime are NOT verified by this job.');
NODE
