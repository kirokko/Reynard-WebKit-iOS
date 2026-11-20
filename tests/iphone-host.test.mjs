// SPDX-License-Identifier: GPL-3.0-or-later
// Source safety checks only. Actual UIKit/WebKit execution is a separate CI gate.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';
const read = path => fs.readFileSync(new URL('../' + path, import.meta.url), 'utf8');
test('device host uses isolated ephemeral data and real extension unload, with explicit consent', () => {
    const source = read('tests/iphone-host/DeviceHost.m');
    assert.match(source, /WKWebsiteDataStore\.nonPersistentDataStore/);
    assert.match(source, /WKWebExtensionControllerConfiguration\.nonPersistentConfiguration/);
    assert.match(source, /uniqueIdentifier = NSUUID\.UUID\.UUIDString/);
    assert.match(source, /unloadExtensionContext:self\.context error:/);
    assert.match(source, /同意并测试/);
    assert.match(source, /fullUBlockOriginVerified.*@NO/);
    assert.doesNotMatch(source, /GeckoRuntime|RPPairing|dlopen\(|dlsym\(/);
});
test('device fixture binds loopback only, bounds sockets and never forwards requests or serves files', () => {
    const source = read('tests/iphone-host/FixtureServer.m');
    assert.match(source, /inet_pton\(AF_INET, "127\.0\.0\.1"/);
    assert.match(source, /active >= 8/);
    assert.match(source, /request\.length < 8192/);
    assert.match(source, /SO_RCVTIMEO/);
    assert.doesNotMatch(source, /NSURLSession|connect\(|getaddrinfo\(|INADDR_ANY|contentsOfDirectory/);
});
test('device test awaits JS promises and cannot count timeouts or absent requests as successful filtering', () => {
    const source = read('tests/iphone-host/DeviceHost.m');
    assert.match(source, /callAsyncJavaScript:@"return await runNetworkTest\(\);"/);
    assert.match(source, /!\[r\[@"timeout"\] boolValue\]/);
    assert.match(source, /serverHits.*control\.txt/);
    assert.match(source, /network.*stage.*installed/);
    assert.doesNotMatch(source, /evaluateJavaScript:@"runNetworkTest\(\)"/);
});
test('device IPA build has fixed unofficial extension input and never invokes legacy app builder', () => {
    const build = read('tools/ci/Build-DeviceProbe.sh');
    assert.match(build, /4a1e45c53ffab5c04f8a5a8015a6ed11d045c603ea9a76e7b88e6dc7c09942c2/);
    assert.match(build, /net\.kirokko\.ieynec\.webkitprobe/);
    assert.match(build, /Verify-DeviceProbe\.py/);
    assert.doesNotMatch(build, /xcodebuild .*archive|create-ipa\.sh|build-app\.sh|Build-Gecko/);
    const verifier = read('tools/ci/Verify-DeviceProbe.py');
    assert.match(verifier, /0x0100000c/);
    assert.match(verifier, /physicalDeviceVerified=False, sideStoreVerified=False/);
});
