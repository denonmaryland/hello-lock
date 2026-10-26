// Exercise the actual QML JavaScript methods with fake compositor/PAM objects.
// No QML service is instantiated and no lock/password IPC is sent.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const rootDir = process.env.HELLO_LOCK_TEST_ROOT || path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(rootDir, 'Service.qml'), 'utf8');
const presetScope = {};
vm.createContext(presetScope);
vm.runInContext(fs.readFileSync(path.join(rootDir, 'Presets.js'), 'utf8').replace('.pragma library', ''), presetScope);
const methods = [...source.matchAll(/^  function (\w+)\(([^\n]*)\) \{\n([\s\S]*?)^  \}/gm)];
function context() {
  const timer = () => ({running: false, stop() { this.running = false }, start() { this.running = true }, restart() { this.running = true }});
  const c = {
    console: {warn() {}, log() {}}, Date, Object, Math,
    Presets: presetScope, realUnlockSplash: false, userConfig: {}, lockBranding: {}, lastBrandingPreset: "", brandingRotationKey: "",
    passwordPamConfigured: true, config: {powerDown: false, sounds: false},
    typingEffect: 'cells', unlockTransition: false, unlockGateDone: false,
    builtinSymbolNames: ['radar', 'bolt', 'gear'], symbolBag: [], lockSymbol: '',
    lockRequested: false, pendingSessionLock: false, strandedLockResolved: false,
    snapshotReady: false, snapshotDir: '', snapshotFiles: {}, snapshotPending: [],
    snapshotEpoch: 0, snapshotCleanupQueue: [], pluginDir: '/plugin',
    sessionLock: {locked: false, secure: false},
    unlockGate: timer(), snapshotExpiry: timer(), idleBlankTimer: timer(),
    sessionLockStabilizeTimer: timer(), pendingSessionLockTimer: timer(),
    fingerprintRetryTimer: timer(), typingListProc: {running: false},
    snapshotProc: {running: false}, cleanSnapshotProc: {running: false},
    passwordPam: {active: false}, fingerprintPam: {active: false},
    authenticatingPassword: false, fingerprintAuthenticating: false,
    enteredPassword: '', pendingPassword: '', failureMessage: '', failedAttempts: 0,
    wakeProcess: {running: false},
    unlockSplashLoader: {item: null}, Quickshell: {screens: [{name: 'eDP-1'}]},
    Qt: {callLater() {}},
  };
  c.root = c;
  vm.createContext(c);
  for (const m of methods) vm.runInContext(`function ${m[1]}(${m[2]}) {${m[3]}\n}`, c);
  c.refreshMotion = c.refreshStatus = c.refreshBackground = c.refreshFingerprintStatus = () => {};
  c.splashContext = () => ({});
  return c;
}

{
  const c = context();
  c.passwordPamConfigured = false;
  assert.equal(c.beginLock(), false);
  assert.equal(c.lockRequested, false, 'missing PAM must never initiate locking');
}
{
  const c = context();
  c.unlockSplashLoader.item = {finish() { throw Error('broken cosmetic cleanup') }};
  assert.equal(c.beginLock(), true);
  assert.equal(c.lockRequested, true, 'a splash exception must not prevent locking');
  assert.equal(c.pendingSessionLock, true);
}
{
  const c = context();
  c.lockRequested = true;
  c.sessionLock.locked = true;
  c.unlockSplashLoader.item = {prime() { throw Error('prime failed') }, play() { throw Error('play failed') }};
  c.finishUnlock(); // This private method is called by PAM success, not IPC.
  assert.equal(c.sessionLock.locked, true, 'release waits for the fixed gate');
  assert.equal(c.unlockGate.running, true, 'a failed splash cannot block the gate');
  c.unlockGateDone = true; // Simulate its timer, no real compositor involved.
  c.finishUnlock();
  assert.equal(c.sessionLock.locked, false);
  assert.equal(c.lockRequested, false);
}
{
  const c = context();
  c.lockRequested = true;
  c.sessionLock.locked = true;
  c.pendingPassword = 'dummy-test-input';
  c.handlePasswordFailure();
  assert.equal(c.sessionLock.locked, true);
  assert.equal(c.unlockGate.running, false);
  assert.equal(c.pendingPassword, '');
  assert.equal(c.failedAttempts, 1);
}
{
  const c = context();
  c.snapshotDir = '/runtime/hello-lock-snapshot-first';
  c.snapshotReady = true;
  c.snapshotPending = ['eDP-1', 'HDMI-A-1'];
  c.snapshotFinished({name: 'eDP-1'});
  assert.equal(c.snapshotReady, true, 'the first monitor cannot delete the second snapshot');
  c.snapshotFinished({name: 'HDMI-A-1'});
  assert.equal(c.snapshotReady, false);
  assert.equal(c.snapshotEpoch, 1, 'cleanup invalidates in-flight captures');
  assert.equal(c.cleanSnapshotProc.command[2], '/runtime/hello-lock-snapshot-first');
  c.queueSnapshotCleanup('/runtime/hello-lock-snapshot-second');
  assert.equal(c.snapshotCleanupQueue.length, 1, 'cleanup must not interrupt another cleanup');
  c.cleanSnapshotProc.running = false;
  c.queueSnapshotCleanup('');
  assert.equal(c.cleanSnapshotProc.command[2], '/runtime/hello-lock-snapshot-second');
}
{
  const c = context();
  c.snapshotReady = true;
  c.snapshotVersion = 1;
  c.snapshotFiles = {'odd output': '/runtime/hello-lock-snapshot-1/a #?.jpg'};
  const url = c.snapshotUrlFor({name: 'odd output'});
  assert.ok(url.includes('a%20%23%3F.jpg?v=1'), 'encode the complete file path');
}
{
  const c = context();
  const callback = source.match(/id: snapshotProc[\s\S]*?onExited: function\(exitCode\) \{\n([\s\S]*?)^    \}/m);
  assert.ok(callback);
  vm.runInContext(`function captured(exitCode) {${callback[1]}\n}`, c);
  c.epoch = 1;
  c.snapshotEpoch = 2; // The session unlocked while grim was still running.
  c.snapshotOutput = {text: JSON.stringify({directory: '/runtime/hello-lock-snapshot-late', files: {'eDP-1': '/frame.jpg'}})};
  c.captured(0);
  assert.equal(c.snapshotReady, false);
  assert.equal(c.cleanSnapshotProc.command[2], '/runtime/hello-lock-snapshot-late');
  c.lockRequested = true;
  c.snapshotEpoch = 3; // A new lock also must reject the previous lock's capture.
  c.captured(0);
  assert.equal(c.snapshotReady, false);
  c.epoch = 3;
  c.snapshotVersion = 0;
  c.captured(0);
  assert.equal(c.snapshotReady, true);
  assert.equal(c.snapshotExpiry.running, true);
}
console.log('7 service regression scenarios passed (mock compositor; no real lock).');

// Branding rotates once, stays separate from personal settings, and tolerates
// removed/empty presets. No compositor or authentication is involved.
{
  const c = context();
  c.userConfig = {name: 'Person', brand: 'Base', selectedPreset: 'a', presetMode: 'cycle',
    brandingPresets: [{id:'a', name:'A', branding:{brand:'A', symbol:'@radar'}},
                     {id:'b', name:'B', branding:{brand:'B', symbolParts:['one','two'], name:'Wrong'}}]};
  c.selectLockBranding();
  assert.equal(c.lockBranding.brand, 'B');
  assert.equal(c.lockBranding.name, undefined);
  c.selectLockBranding();
  assert.equal(c.lockBranding.brand, 'A');
  assert.equal(c.lockBranding.symbolParts.length, 0);
  c.userConfig.presetMode = 'shuffle';
  c.selectLockBranding();
  for (let i=0;i<20;i++) {
    const previous = c.lastBrandingPreset;
    c.selectLockBranding();
    assert.notEqual(c.lastBrandingPreset, previous);
  }
  c.userConfig.brandingPresets = [c.userConfig.brandingPresets[0]];
  c.selectLockBranding();
  assert.equal(c.lockBranding.brand, 'A');
  c.userConfig.brandingPresets = [];
  c.selectLockBranding();
  assert.equal(c.lockBranding.brand, 'Base');
  c.userConfig.presetMode = 'manual';
  c.selectLockBranding();
  assert.equal(c.lockBranding.brand, 'Base');
}
console.log('Branding preset rotation scenarios passed.');

{
  const c = context();
  c.userConfig = {presetMode:'cycle', brandingPresets:[{id:'a',name:'A',branding:{brand:'A'}},{id:'b',name:'B',branding:{brand:'B'}}]};
  c.beginLock();
  assert.equal(c.lockBranding.brand, 'A');
  c.beginLock();
  assert.equal(c.lockBranding.brand, 'A', 'repeated requests must not change a locked session');
}

// "@shuffle" symbol: one draw per real lock, every built-in once per round,
// no back-to-back repeats; a repeated lock request keeps the drawn symbol.
{
  const c = context();
  const seen = [];
  for (let i = 0; i < 9; i++) {
    c.lockRequested = false;
    c.beginLock();
    const held = c.lockSymbol;
    c.beginLock();
    assert.equal(c.lockSymbol, held, 'repeated lock requests must not draw a new symbol');
    seen.push(held);
  }
  for (let r = 0; r < 9; r += 3) assert.deepEqual(seen.slice(r, r + 3).sort(), ['bolt', 'gear', 'radar']);
  for (let i = 1; i < seen.length; i++) assert.notEqual(seen[i], seen[i - 1], 'no back-to-back repeat');
}
console.log('Symbol shuffle scenarios passed.');

// Evaluate the production bindings, not a separate copy of their logic.
{
  const c = context();
  const frozen = source.match(/readonly property bool brandingFrozen: ([\s\S]*?)\n  readonly property var config:/)[1];
  const effective = source.match(/readonly property var config: (.*)/)[1];
  c.configDefaults = {};
  c.userConfig = {brand:'New brand', symbolParts:['new.svg']};
  c.lockBranding = {brand:'Previous lock', symbolParts:['old.svg']};
  c.unlockSplashLoader.item = {shown:false, prime() { this.shown=true; }, play() { this.shown=true; }};
  const branding = () => {
    c.brandingFrozen = vm.runInContext(frozen, c);
    return vm.runInContext(effective, c);
  };
  c.lockRequested = true;
  c.sessionLock.locked = true;
  c.finishUnlock();
  assert.equal(c.realUnlockSplash, true);
  assert.equal(branding().brand, 'Previous lock');
  c.unlockGateDone = true;
  c.finishUnlock();
  assert.equal(branding().brand, 'Previous lock', 'real splash keeps the lock branding after release');
  // Starting a preview also works while the real splash is still visible.
  c.playUnlockPreview(-1, {});
  assert.equal(branding().brand, 'New brand');
  assert.equal(branding().symbolParts[0], 'new.svg');
  c.unlockSplashLoader.item.shown = false;
  c.playUnlockPreview(-1, {});
  assert.equal(branding().brand, 'New brand');
}
{
  const c = context();
  c.userConfig = {brand:'Fallback', presetMode:'cycle', brandingPresets:[null, {id:'bad',name:7,branding:{}},
    {id:'valid',name:'Valid',branding:{brand:'Good'}}, {id:'valid',name:'Duplicate',branding:{brand:'Wrong'}}]};
  c.selectLockBranding();
  assert.equal(c.lockBranding.brand, 'Good');
}
console.log('Preset review regressions passed.');
