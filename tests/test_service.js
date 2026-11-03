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
const typingSoundScope = {};
vm.createContext(typingSoundScope);
vm.runInContext(fs.readFileSync(path.join(rootDir, 'TypingSounds.js'), 'utf8').replace('.pragma library', ''), typingSoundScope);
const methods = [...source.matchAll(/^  function (\w+)\(([^\n]*)\) \{\n([\s\S]*?)^  \}/gm)];
function context() {
  const timer = () => ({running: false, stop() { this.running = false }, start() { this.running = true }, restart() { this.running = true }});
  const c = {
    console: {warn() {}, log() {}}, Date, Object, Math,
    Presets: presetScope, realUnlockSplash: false, userConfig: {}, lockBranding: {}, lastBrandingPreset: "", brandingRotationKey: "",
    TypingSounds: typingSoundScope, typingSound: 'shuffle', lockTypingSound: 'pulse', typingSoundBag: [],
    reducedMotion: false, typingSoundLoader: {item: null},
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

// Sound selection advances once per real lock; previews and repeated requests
// cannot consume the bag. Muted/off/reduced/unlocking paths cannot play.
{
  const c = context();
  c.beginLock();
  const first = c.lockTypingSound;
  const remaining = JSON.stringify(c.typingSoundBag);
  c.beginLock();
  assert.equal(c.lockTypingSound, first);
  assert.equal(JSON.stringify(c.typingSoundBag), remaining);
  const seen = new Set([first]);
  for (let i = 0; i < 5; i++) { c.selectTypingSound(); seen.add(c.lockTypingSound) }
  assert.equal(seen.size, 6, 'each patch before a repeat');
  let previous = c.lockTypingSound;
  for (let i = 0; i < 90; i++) {
    c.selectTypingSound();
    assert.notEqual(c.lockTypingSound, previous, 'no repeat across bag refills');
    previous = c.lockTypingSound;
  }
  c.typingSound = 'phase'; c.selectTypingSound();
  assert.equal(c.lockTypingSound, 'phase');
  c.typingSound = 'off'; c.selectTypingSound();
  assert.equal(c.lockTypingSound, 'phase');
  assert.equal(typingSoundScope.normalize('../../bad'), 'shuffle');
  for (const [old, current] of Object.entries({wood:'pulse', clay:'phase', rubber:'flux', felt:'grain', relay:'circuit', pluck:'drift'}))
    assert.equal(typingSoundScope.normalize(old), current, 'preserve earlier saved choices');
  let plays = 0;
  c.typingSoundLoader.item = {play() { plays++ }};
  c.playTypingSound(); assert.equal(plays, 0);
  c.config.sounds = true;
  c.typingSound = 'shuffle'; c.playTypingSound(); assert.equal(plays, 1);
  for (const [key, value] of [['authenticatingPassword', true], ['unlockTransition', true],
                             ['reducedMotion', true], ['lockRequested', false]]) {
    const before = c[key]; c[key] = value;
    c.playTypingSound(); assert.equal(plays, 1, key);
    c[key] = before;
  }
  c.config.sounds = false; c.playTypingSound(); assert.equal(plays, 1);
  c.config.sounds = true;
  c.typingSoundLoader.item = {play() { throw Error('optional audio failure') }};
  assert.doesNotThrow(() => c.playTypingSound());
}

// Exercise the actual edit handler: synchronized monitor fields and inactive
// input never emit sound. The sound signal takes no password or key argument.
{
  const view = fs.readFileSync(path.join(rootDir, 'LockView.qml'), 'utf8');
  const handler = view.match(/onTextEdited: \{([\s\S]*?)^            \}/m);
  assert.ok(handler);
  let pulses = 0;
  const scope = {root: {syncingPasswordText: false, inputEnabled: true,
    authenticatingPassword: false, unlocking: false,
    typingSoundRequested(...args) { assert.equal(args.length, 0); pulses++ }}};
  vm.createContext(scope);
  vm.runInContext(`function edit() {${handler[1]}\n}`, scope);
  scope.edit(); assert.equal(pulses, 1);
  for (const [key, value] of [['syncingPasswordText', true], ['inputEnabled', false],
                             ['authenticatingPassword', true], ['unlocking', true]]) {
    const before = scope.root[key]; scope.root[key] = value;
    scope.edit(); assert.equal(pulses, 1, key);
    scope.root[key] = before;
  }
}

// Bounded native playback: no queue, no stealing a ringing voice, no playback
// on stale/missing policy, and no more than one sound per edit pulse.
{
  const audio = fs.readFileSync(path.join(rootDir, 'TypingSound.qml'), 'utf8');
  const method = audio.match(/^  function play\(\) \{\n([\s\S]*?)^  \}/m);
  let now = 1000, plays = 0;
  const voices = Array.from({length: 3}, () => ({effect: {status: 2, playing: false,
    play() { this.playing = true; plays++ }}}));
  const c = {engaged: true, allowed: true, validFamily: true, volume: 0.5,
    nextVoice: 0, lastTick: 0, policyValidUntil: 3000,
    Date: {now: () => now}, SoundEffect: {Ready: 2},
    voices: {count: 3, itemAt: i => voices[i]}};
  vm.createContext(c); vm.runInContext(`function play() {${method[1]}\n}`, c);
  assert.equal(c.play(), true);
  now += 10; assert.equal(c.play(), false, 'auto-repeat rate limit');
  now += 40; assert.equal(c.play(), true);
  now += 50; assert.equal(c.play(), true);
  now += 50; assert.equal(c.play(), false, 'all voices busy; drop instead of queue');
  assert.equal(plays, 3);
  voices.forEach(v => { v.effect.playing = false });
  c.allowed = false; assert.equal(c.play(), false);
  c.allowed = true; now = 4000; assert.equal(c.play(), false, 'expired policy');
  c.policyValidUntil = 5000; c.volume = 0; assert.equal(c.play(), false);
  c.volume = 0.5; voices.forEach(v => { v.effect.status = 3 });
  assert.equal(c.play(), false, 'missing/failed WAVs');
}
console.log('Typing sound selection, edit isolation and bounded playback scenarios passed.');

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

// Run the actual WlSessionLock signal handlers, including deferred checks.
// Model secureStateChanged arriving before Quickshell clears locked, and the
// 0.3.2 path where secure drops without a lockStateChanged notification.
function lockLossContext() {
  const c = context();
  const deferred = [];
  c.Qt.callLater = callback => deferred.push(callback);
  c.flushDeferred = () => { while (deferred.length) deferred.shift()() };
  c.Quickshell.screens = [{name: 'eDP-1', width: 1920, height: 1080}];
  for (const signal of ['SecureState', 'LockState']) {
    const handler = source.match(new RegExp(`    on${signal}Changed: \\{\\n([\\s\\S]*?)^    \\}`, 'm'));
    assert.ok(handler, `${signal} handler exists`);
    vm.runInContext(`function emit${signal}Changed() { const {locked, secure} = sessionLock; ${handler[1]}\n}`, c);
  }
  c.lockRequested = true;
  return c;
}
for (const notifications of [['LockState'], ['SecureState'], ['SecureState', 'LockState']]) {
  const c = lockLossContext();
  c.sessionLock.locked = true; // Still true during secureStateChanged.
  for (const signal of notifications) {
    if (signal === 'LockState') c.sessionLock.locked = false;
    c[`emit${signal}Changed`]();
  }
  assert.equal(c.pendingSessionLock, false, 'recovery waits for the lock object to settle');
  c.sessionLock.locked = false;
  let queued = 0;
  const queue = c.queueSessionLock;
  c.queueSessionLock = () => { queued++; queue() };
  c.flushDeferred();
  assert.equal(c.lockRequested, true, 'loss must preserve the lock request');
  assert.equal(c.pendingSessionLock, true, 'loss must queue recovery');
  assert.equal(queued, 1, 'duplicate loss notifications must not restart recovery');
  assert.equal(c.wakeProcess.running, false, 'loss must not wake an unlocked desktop');
  assert.equal(c.unlockGate.running, false, 'loss must not start an unlock');
  c.requestSessionLock();
  assert.equal(c.sessionLock.locked, false, 'recovery respects stabilization');
  c.sessionLockStabilizeTimer.stop();
  c.Quickshell.screens = [];
  c.requestSessionLock();
  assert.equal(c.sessionLock.locked, false, 'recovery waits for a real screen');
  c.Quickshell.screens = [{name: 'eDP-1', width: 1920, height: 1080}];
  c.requestSessionLock();
  assert.equal(c.sessionLock.locked, true, 'recovery requests the compositor lock');
  c.sessionLock.secure = true;
  let fingerprintStarts = 0;
  c.startFingerprint = () => { fingerprintStarts++ };
  c.emitLockStateChanged();
  c.emitSecureStateChanged();
  assert.equal(c.pendingSessionLock, false);
  assert.equal(c.pendingSessionLockTimer.running, false);
  assert.equal(fingerprintStarts, 1, 'secure recovery resumes the existing fingerprint flow');
}
for (const phase of ['before-check', 'during-gate', 'after-unlock']) {
  const c = lockLossContext();
  c.sessionLock.locked = true;
  c.finishUnlock(); // PAM success starts the existing gate.
  assert.equal(c.unlockGate.running, true);
  c.sessionLock.locked = false;
  if (phase !== 'after-unlock') c.emitSecureStateChanged();
  if (phase === 'during-gate') {
    c.flushDeferred();
    assert.equal(c.pendingSessionLock, true, 'loss during the gate still queues recovery');
  }
  c.unlockGateDone = true;
  c.finishUnlock();
  c.emitLockStateChanged();
  c.emitSecureStateChanged();
  c.flushDeferred();
  assert.equal(c.lockRequested, false, `${phase}: authenticated unlock stays unlocked`);
  assert.equal(c.pendingSessionLock, false);
  assert.equal(c.sessionLockStabilizeTimer.running, false);
  assert.equal(c.pendingSessionLockTimer.running, false);
  assert.equal(c.sessionLock.locked, false);
}
{
  const c = lockLossContext();
  c.emitSecureStateChanged();
  c.sessionLock.locked = true;
  c.sessionLock.secure = true;
  c.flushDeferred();
  assert.equal(c.pendingSessionLock, false, 'a recovered lock must not be queued again');
}
console.log('Lock-loss recovery regressions passed (mock compositor; no real lock).');

// Instant mode removes only cosmetics; failure still cannot release the lock.
for (const brokenSplash of [false, true]) {
  const c = context();
  c.lockRequested = true;
  c.sessionLock.locked = true;
  c.config.unlockAnimation = false;
  c.unlockSplashLoader.item = {
    prime() { assert.fail('instant unlock must not prime a splash') },
    play() { assert.fail('instant unlock must not play a splash') },
    finish() { if (brokenSplash) throw Error('broken optional splash') }
  };
  c.handlePasswordFailure();
  assert.equal(c.sessionLock.locked, true);
  assert.equal(c.unlockGate.running, false);
  c.finishUnlock(); // The private PAM-success path.
  assert.equal(c.sessionLock.locked, false);
  assert.equal(c.lockRequested, false);
  assert.equal(c.unlockGate.running, false);
  assert.equal(c.unlockTransition, false);
  assert.equal(c.realUnlockSplash, false);
}
{
  const c = context();
  c.configFile = {reloads: 0, reload() { this.reloads++ }};
  c.settingsOpen = true;
  const saved = source.match(/function onConfigSaved\(\) \{([^\n]*)\}/);
  const closed = source.match(/function onClosed\(\) \{( configFile.reload\(\); root.settingsOpen = false )\}/);
  assert.ok(saved && closed);
  vm.runInContext(saved[1], c);
  assert.equal(c.configFile.reloads, 1, 'successful save explicitly reloads even if a file-change notification is missed');
  vm.runInContext(closed[1], c);
  assert.equal(c.configFile.reloads, 2);
  assert.equal(c.settingsOpen, false);
  c.tryUnlockTimer = {restart() { this.restarted = true }};
  const setup = source.match(/function onTryUnlockRequested\(\) \{([^\n]*)\}/);
  assert.ok(setup);
  vm.runInContext(setup[1], c);
  assert.equal(c.configFile.reloads, 3, 'saved setup explicitly reloads before its demo');
  assert.equal(c.tryUnlockTimer.restarted, true);
}
console.log('Instant unlock and explicit configuration reload regressions passed.');
