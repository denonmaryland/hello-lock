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
    coverRuleProc: {running: false}, lockCover: {instances: []}, coverKeyboardMisses: 0, lockCoverGuarding: false,
    coverRuleResync: false, barrierResync: false, barrierProc: {running: false, wanted: false, command: []}, compositorBarrierWanted: false,
    barrierOnLua: 'ON', barrierOffLua: 'OFF', coverRuleLua: 'RULE', barrierLinger: false, barrierLingerTimer: timer(), compositorBarrierState: 'unknown', coverRuleLaunches: 0, coverRuleEpoch: 0, coverRuleValid: false,
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
// Issue #2 follow-up. Quickshell 0.3.2 (WlSessionLock::realizeLockTarget) ends a
// lock attempt it cannot complete by calling unlock() while nothing is locked:
// no lockStateChanged, no secureStateChanged, and the target reset to false.
// Model exactly that: a write of true that silently reads back false.
function refusingLock(c) {
  let target = false;
  const lock = {refuse: true, writes: [], secure: false};
  Object.defineProperty(lock, 'locked', {
    get() { return target },
    set(value) { lock.writes.push(value); target = value && !lock.refuse },
  });
  c.sessionLock = lock;
  return lock;
}
for (const start of ['first-lock', 'after-loss']) {
  const c = lockLossContext();
  const lock = refusingLock(c);
  if (start === 'first-lock') {
    c.lockRequested = false;
    assert.equal(c.beginLock(), true);
  } else {
    c.lockCoverArmed = true; // It was secure once; then the lock was lost.
    c.relockLostLock();
  }
  assert.equal(c.pendingSessionLock, true);
  c.sessionLockStabilizeTimer.stop();
  c.requestSessionLock(); // Quickshell refuses without any signal.
  assert.equal(lock.locked, false);
  assert.equal(c.lockRequested, true, `${start}: a refused attempt keeps the request`);
  assert.equal(c.pendingSessionLock, true, `${start}: a refused attempt must be retried, not dropped`);
  assert.equal(c.pendingSessionLockTimer.running, true, `${start}: the retry is scheduled`);
  assert.equal(c.lockCoverArmed, true, `${start}: a refused attempt keeps the desktop covered`);
  assert.equal(c.wakeProcess.running, false, `${start}: a refused attempt must not wake the desktop`);
  lock.refuse = false;
  lock.writes.length = 0;
  c.sessionLockStabilizeTimer.stop();
  c.requestSessionLock();
  assert.equal(lock.locked, true, `${start}: the retry acquires the lock`);
  assert.deepEqual(lock.writes.slice(-1), [true]);
}
{
  // Any missed notification: the request is latched, the lock is absent and
  // nothing is pending. The guard timer must notice it on its own.
  const guard = source.match(/  Timer \{\n    id: lockGuardTimer\n([\s\S]*?)^  \}/m);
  assert.ok(guard, 'a lock guard timer exists');
  assert.match(guard[1], /running: root\.lockRequested\n/, 'the guard runs for the whole lock request');
  assert.match(guard[1], /repeat: true/);
  assert.match(guard[1], /onTriggered: \{\n      root\.relockLostLock\(\)\n      root\.ensureCompositorBarrier\(\)\n    \}/);
  const interval = Number((guard[1].match(/interval: (\d+)/) || [])[1]);
  assert.ok(interval > 0 && interval <= 1000, 'the guard checks at least once a second');
  const c = lockLossContext();
  c.relockLostLock(); // What the guard does on a silent loss.
  assert.equal(c.pendingSessionLock, true, 'a silent loss is caught by the guard');
  c.sessionLock.locked = true;
  c.sessionLock.secure = true;
  c.pendingSessionLock = false;
  c.relockLostLock();
  assert.equal(c.pendingSessionLock, false, 'the guard leaves a held lock alone');
}
{
  // The fail-closed cover: armed once the lock is secure, cleared only by an
  // authenticated unlock, hidden for the post-authentication gate.
  const c = lockLossContext();
  c.startFingerprint = () => {};
  c.sessionLock.locked = true;
  c.sessionLock.secure = true;
  c.emitSecureStateChanged();
  assert.equal(c.lockCoverArmed, true, 'a secure lock arms the cover');
  c.sessionLock.secure = false;
  c.sessionLock.locked = false;
  c.emitSecureStateChanged();
  c.emitLockStateChanged();
  c.flushDeferred();
  assert.equal(c.lockCoverArmed, true, 'a lost lock keeps the cover armed');
  c.sessionLock.locked = true;
  c.finishUnlock();
  assert.equal(c.lockCoverArmed, true, 'the cover stays armed until release');
  c.unlockGateDone = true;
  c.finishUnlock();
  assert.equal(c.lockCoverArmed, false, 'an authenticated unlock disarms the cover');
  c.emitSecureStateChanged();
  assert.equal(c.lockCoverArmed, false, 'no request: a late secure signal cannot arm it');

  const shown = source.match(/readonly property bool lockCoverShown: ([^\n]*)/);
  assert.ok(shown, 'the cover visibility is one binding');
  const visible = (state) => vm.runInNewContext(`(${shown[1]})`, state);
  assert.equal(visible({lockRequested: true, lockCoverArmed: true, unlockTransition: false}), true);
  assert.equal(visible({lockRequested: true, lockCoverArmed: false, unlockTransition: false}), false,
    'the first lock keeps its power-down: no cover before the lock is secure');
  assert.equal(visible({lockRequested: true, lockCoverArmed: true, unlockTransition: true}), false,
    'PAM success reveals the splash, not the cover');
  assert.equal(visible({lockRequested: false, lockCoverArmed: true, unlockTransition: false}), false);

  const cover = source.match(/  Variants \{\n    id: lockCover\n([\s\S]*?)^  \}/m);
  assert.ok(cover, 'the cover exists on every screen');
  assert.match(cover[1], /model: Quickshell\.screens/);
  assert.match(cover[1], /visible: root\.lockCoverShown/);
  assert.match(cover[1], /WlrLayershell\.layer: WlrLayer\.Overlay/);
  assert.match(cover[1], /WlrLayershell\.namespace: "hello-lock-cover"/);
  assert.match(cover[1], /exclusionMode: ExclusionMode\.Ignore/);
  assert.match(cover[1], /color: "#000000"/, 'the cover is opaque');
}
{
  // T29 P2: Hyprland fades a new layer in from alpha 0, so the cover must be
  // exempt from layer animations before it can ever map.
  const c = context();
  assert.equal(c.beginLock(), true);
  assert.equal(c.coverRuleProc.running, true, 'every lock request applies the instant-cover rule');
  const rule = source.match(/  Process \{\n    id: coverRuleProc\n([\s\S]*?)^  \}/m);
  assert.ok(rule, 'the cover rule process exists');
  const command = rule[1].match(/command: (\[[^\n]*\])/);
  assert.ok(command);
  const argv = JSON.parse(JSON.stringify(vm.runInNewContext(command[1], {root: {coverRuleLua: 'RULE'}})));
  assert.deepEqual(argv, ['hyprctl', 'eval', 'RULE'], 'the rule text is checked with the barrier below');
  assert.match(source, /  Component\.onCompleted: \{\n    applyCoverRule\(\)\n/, 'the rule is applied at startup too');
}
{
  // T29 P1: an exclusive layer is not an input barrier; Hyprland runs its
  // keybindings unless the focused surface inhibits shortcuts.
  const cover = source.match(/  Variants \{\n    id: lockCover\n([\s\S]*?)^  \}/m)[1];
  assert.match(cover, /source: Qt\.resolvedUrl\("platform\/CoverShortcutInhibitor\.qml"\)/);
  assert.match(cover, /onLoaded: item\.window = coverWindow/);
  assert.match(cover, /readonly property bool keyboardHeld: coverKeys\.activeFocus/);
  const inhibitor = fs.readFileSync(path.join(rootDir, 'platform/CoverShortcutInhibitor.qml'), 'utf8');
  assert.match(inhibitor, /ShortcutInhibitor \{\n    id: inhibitor\n    window: guard\.window\n    enabled: guard\.window !== null\n  \}/);
  const focus = cover.match(/WlrLayershell\.keyboardFocus: ([^\n]*)/);
  assert.ok(focus, 'the cover keyboard mode is one binding');
  const WlrKeyboardFocus = {None: 'none', Exclusive: 'exclusive'};
  const mode = (reclaiming, guarding) => vm.runInNewContext(`(${focus[1]})`, {reclaiming, root: {lockCoverGuarding: guarding}, WlrKeyboardFocus});
  assert.equal(mode(false, true), 'exclusive');
  assert.equal(mode(true, true), 'none', 'a reclaim drops exclusivity for one tick');
  assert.equal(mode(true, false), 'exclusive', 'a reclaim left over when the lock returns cannot release the keyboard');
  const guarding = source.match(/readonly property bool lockCoverGuarding: ([^\n]*)/);
  const guard = (state) => vm.runInNewContext(`(${guarding[1]})`, state);
  assert.equal(guard({lockCoverShown: true, sessionLock: {secure: false}}), true, 'guard while the cover shows without a lock');
  assert.equal(guard({lockCoverShown: true, sessionLock: {secure: true}}), false, 'the lock owns the keyboard while it holds');
  assert.equal(guard({lockCoverShown: false, sessionLock: {secure: false}}), false);
  const timer = source.match(/  Timer \{\n    id: coverKeyboardTimer\n([\s\S]*?)^  \}/m);
  assert.ok(timer);
  assert.match(timer[1], /running: root\.lockCoverGuarding\n/);
  assert.match(timer[1], /repeat: true/);
  assert.match(timer[1], /onTriggered: root\.guardCoverKeyboard\(\)/);
  assert.ok(Number(timer[1].match(/interval: (\d+)/)[1]) <= 100);

  const c = context();
  const events = [];
  c.lastEvent = 'init';
  c.logEvent = (event) => { events.push(event); c.lastEvent = event };
  const a = {keyboardHeld: true, reclaiming: false}, b = {keyboardHeld: false, reclaiming: false};
  c.lockCover.instances = [a, b];
  c.lockCoverGuarding = true;
  for (let i = 0; i < 5; i++) c.guardCoverKeyboard();
  assert.equal(a.reclaiming || b.reclaiming, false, 'a cover that holds the keyboard is never touched');
  a.keyboardHeld = false; // Another exclusive layer took the keyboard.
  c.guardCoverKeyboard();
  assert.equal(a.reclaiming, false, 'one miss may be a focus change in flight: wait');
  c.guardCoverKeyboard();
  assert.equal(a.reclaiming, true, 'a second miss reclaims the keyboard');
  assert.deepEqual(events, ['cover-keyboard: reclaiming']);
  c.guardCoverKeyboard();
  assert.equal(a.reclaiming, false, 'the next tick makes it exclusive again, which takes the keyboard');
  a.keyboardHeld = true;
  c.guardCoverKeyboard();
  c.guardCoverKeyboard();
  assert.equal(a.reclaiming, false);
  a.keyboardHeld = false;
  c.lockCoverGuarding = false; // The lock is back.
  c.guardCoverKeyboard();
  c.guardCoverKeyboard();
  assert.equal(a.reclaiming, false, 'no reclaim while the lock holds the keyboard');
  c.lockCover.instances = [];
  c.lockCoverGuarding = true;
  c.guardCoverKeyboard();
  c.guardCoverKeyboard(); // No covers yet (output appearing): nothing to do.
}
{
  // T32 P1: the barrier must not depend on focus. A submap whose only bind is
  // a catchall swallows every key in Hyprland for the whole loss.
  const prop = (name) => {
    const m = source.match(new RegExp(`readonly property string ${name}: ([\\s\\S]*?)\\n  (?:readonly property|onCompositor|//)`));
    assert.ok(m, name);
    return m[1];
  };
  const strings = vm.runInNewContext(`(function() { var coverRuleLua = ${prop('coverRuleLua')}; return {coverRuleLua: coverRuleLua, barrierOnLua: ${prop('barrierOnLua')}, barrierOffLua: ${prop('barrierOffLua')}} })()`);
  assert.match(strings.coverRuleLua, /^hl\.layer_rule\(\{ name = "hello-lock-cover", match = \{ namespace = "\^hello-lock-cover\$" \}, no_anim = true, animation = "none" \}\)$/);
  const on = strings.barrierOnLua.split('\n');
  assert.equal(on[0], strings.coverRuleLua, 'entering the barrier restores the no-fade rule first');
  assert.ok(on.includes('  hl.define_submap("hello-lock-barrier", function() HELLO_LOCK_BARRIER_BIND = hl.bind("catchall", function() end, { ignore_mods = true, dont_inhibit = true }) end)'),
    'the barrier submap holds only a catchall no-op, for keys with any modifiers, even to a surface that inhibits shortcuts');
  assert.ok(on.includes('if HELLO_LOCK_BARRIER_BIND == nil or tostring(HELLO_LOCK_BARRIER_BIND) == "HL.Keybind(expired)" then'),
    'the catchall is rebuilt when a reload expired it, not judged by the submap name');
  assert.ok(on.includes('hl.dispatch(hl.dsp.submap("hello-lock-barrier"))'), 'the barrier is entered every time');
  assert.equal(on.filter(line => line.includes('hl.bind(')).length, 1, 'no other bind lives in the barrier');
  assert.match(strings.barrierOnLua, /if hl\.get_current_submap\(\) ~= "hello-lock-barrier" then error\(/, 'a barrier that did not take reports failure');
  assert.equal(strings.barrierOffLua, 'if hl.get_current_submap() == "hello-lock-barrier" then hl.dispatch(hl.dsp.submap("reset")) end\n'
    + 'if hl.get_current_submap() == "hello-lock-barrier" then error("hello-lock barrier still active") end',
    'reset leaves any other submap alone, and a reset that did not take reports failure');
  assert.ok(!/locked|submap_universal/.test(strings.barrierOnLua), 'the catchall must not run under the real lock, where typing goes to the password field');

  const wanted = source.match(/readonly property bool compositorBarrierWanted: ([^\n]*)/);
  const want = (state) => vm.runInNewContext(`(${wanted[1]})`, state);
  assert.equal(want({lockRequested: true, lockCoverGuarding: true, barrierLinger: true}), true, 'on for the whole loss');
  assert.equal(want({lockRequested: true, lockCoverGuarding: false, barrierLinger: true}), true,
    'a relock keeps it on for a while, so a flapping lock leaves no gap');
  assert.equal(want({lockRequested: true, lockCoverGuarding: false, barrierLinger: false}), false,
    'a lock that held lifts it, so locked binds (lid switch) work again');
  assert.equal(want({lockRequested: false, lockCoverGuarding: false, barrierLinger: true}), false, 'never without a lock request');
  const linger = source.match(/  onLockCoverGuardingChanged: \{\n([\s\S]*?)^  \}/m);
  assert.ok(linger);
  const lingerState = {lockCoverGuarding: true, barrierLinger: false, started: 0, stopped: 0};
  lingerState.barrierLingerTimer = {stop() { lingerState.stopped++ }, restart() { lingerState.started++ }};
  const runLinger = () => vm.runInNewContext(`with (state) {${linger[1]}}`, {state: lingerState});
  runLinger();
  assert.equal(lingerState.barrierLinger, true);
  assert.equal(lingerState.stopped, 1, 'a new loss cancels a pending lift');
  lingerState.lockCoverGuarding = false;
  runLinger();
  assert.equal(lingerState.started, 1, 'a relock starts the lift countdown');
  const timer = source.match(/  Timer \{\n    id: barrierLingerTimer\n([\s\S]*?)^  \}/m);
  assert.match(timer[1], /interval: 5000/);
  assert.match(timer[1], /onTriggered: root\.barrierLinger = false/);
  const unlocked = context();
  unlocked.barrierLinger = true;
  unlocked.barrierLingerTimer = {running: true, stop() { this.running = false }};
  unlocked.lockRequested = true;
  unlocked.sessionLock.locked = true;
  unlocked.unlockGateDone = true;
  unlocked.finishUnlock();
  assert.equal(unlocked.barrierLinger, false, 'authenticated unlock lifts it at once');
  assert.equal(unlocked.barrierLingerTimer.running, false);
  assert.match(source, /  onCompositorBarrierWantedChanged: syncCompositorBarrier\(\)\n/);
  assert.match(source, /  Component\.onCompleted: \{\n    applyCoverRule\(\)\n    \/\/ [^\n]*\n    syncCompositorBarrier\(\)\n/,
    'startup resets a barrier a crashed shell left on');

  const c = context();
  c.compositorBarrierWanted = true;
  c.syncCompositorBarrier();
  assert.deepEqual(JSON.parse(JSON.stringify(c.barrierProc.command)), ['hyprctl', 'eval', 'ON']);
  assert.equal(c.barrierProc.wanted, true);
  c.compositorBarrierWanted = false;
  c.syncCompositorBarrier(); // Still running: queued, not dropped.
  assert.equal(c.barrierResync, true);
  assert.deepEqual(JSON.parse(JSON.stringify(c.barrierProc.command)), ['hyprctl', 'eval', 'ON']);
  c.barrierProc.running = false;
  c.barrierResync = false; // What onExited does before resyncing.
  c.syncCompositorBarrier();
  assert.deepEqual(JSON.parse(JSON.stringify(c.barrierProc.command)), ['hyprctl', 'eval', 'OFF'], 'the latest wish wins');
  assert.equal(c.barrierProc.wanted, false);

  // A refused or lost barrier attempt is retried by the guard tick.
  const retry = context();
  retry.compositorBarrierWanted = true;
  retry.compositorBarrierState = 'unknown';
  retry.ensureCompositorBarrier();
  assert.equal(retry.barrierProc.running, true, 'an unconfirmed barrier is retried');
  const held = context();
  held.compositorBarrierWanted = true;
  held.compositorBarrierState = 'on';
  held.ensureCompositorBarrier();
  assert.equal(held.barrierProc.running, false, 'a confirmed barrier is left alone');
  const idle = context();
  idle.compositorBarrierState = 'off';
  idle.ensureCompositorBarrier();
  assert.equal(idle.barrierProc.running, false, 'a barrier confirmed off is left alone');

  // T46 (3): a failed removal must not pass for off. Run the actual reply
  // handler with a refused OFF, as after an unlock or at startup.
  const collector = source.match(/    id: barrierProc\n[\s\S]*?      onStreamFinished: \{\n([\s\S]*?)\n      \}\n/);
  assert.ok(collector, 'the barrier reply handler exists');
  const off = context();
  off.lockRequested = false;
  off.compositorBarrierWanted = false;
  off.compositorBarrierState = 'on';
  off.logEvent = () => {};
  off.syncCompositorBarrier();
  assert.deepEqual(JSON.parse(JSON.stringify(off.barrierProc.command)), ['hyprctl', 'eval', 'OFF']);
  const reply = (text) => vm.runInNewContext(`(function() {${collector[1]}\n})()`, {root: off, barrierProc: off.barrierProc, text});
  reply('hello-lock barrier still active');
  assert.equal(off.compositorBarrierState, 'unknown', 'a refused removal leaves the barrier unknown, not off');
  off.barrierProc.running = false;
  for (let i = 0; i < 5; i++) {
    off.ensureCompositorBarrier();
    assert.equal(off.barrierProc.running, true, 'removal is retried without a lock request');
    assert.deepEqual(JSON.parse(JSON.stringify(off.barrierProc.command)), ['hyprctl', 'eval', 'OFF']);
    reply('');
    assert.equal(off.compositorBarrierState, 'unknown', 'no answer is not off either');
    off.barrierProc.running = false;
  }
  off.ensureCompositorBarrier();
  reply('ok');
  assert.equal(off.compositorBarrierState, 'off', 'a confirmed removal ends the retries');
  off.barrierProc.running = false;
  off.ensureCompositorBarrier();
  assert.equal(off.barrierProc.running, false);
  const settle = source.match(/  Timer \{\n    id: barrierSettleTimer\n([\s\S]*?)^  \}/m);
  assert.ok(settle, 'a settle timer retries removal');
  assert.match(settle[1], /running: !root\.compositorBarrierWanted && root\.compositorBarrierState !== "off"\n/,
    'it runs whenever the barrier is not wanted and not confirmed off, lock request or not');
  assert.match(settle[1], /repeat: true/);
  assert.match(settle[1], /onTriggered: root\.ensureCompositorBarrier\(\)/);
  assert.match(source, /  property string compositorBarrierState: "unknown"\n/, 'a fresh service does not assume the barrier is off');

  // T32 P2: the rule must survive a compositor config reload.
  const r = context();
  r.coverRuleProc.running = true;
  r.applyCoverRule();
  assert.equal(r.coverRuleResync, true, 'a rule request during a run is applied after it, not dropped');
  const reload = context();
  reload.logEvent = () => {};
  reload.compositorBarrierWanted = true;
  reload.compositorBarrierState = 'on';
  reload.handleCompositorReload();
  assert.equal(reload.compositorBarrierState, 'unknown', 'a reload leaves the barrier unconfirmed until rebuilt');
  assert.equal(reload.coverRuleProc.running, true, 'a reload reapplies the rule');
  assert.equal(reload.barrierProc.running, true, 'a reload during a loss rebuilds the barrier');
  const loss = lockLossContext();
  loss.relockLostLock();
  assert.equal(loss.coverRuleProc.running, true, 'a loss reapplies the rule');
  assert.match(source, /function onScreensChanged\(\) \{\n      root\.applyCoverRule\(\)\n/, 'a screen change reapplies the rule');
  assert.match(source, /function onConfigReloaded\(\) \{ root\.handleCompositorReload\(\) \}/);
  const events = fs.readFileSync(path.join(rootDir, 'platform/HyprlandEvents.qml'), 'utf8');
  assert.match(events, /if \(event\.name === "configreloaded"\) events\.configReloaded\(\)/);
}
{
  // T46 (4): a cover must not map before the no-fade rule is in place.
  const c = context();
  c.coverRuleProc = {running: false, launch: 0};
  c.applyCoverRule();
  assert.equal(c.coverRuleProc.launch, 1, 'each rule run gets a launch number');
  const rule = source.match(/    id: coverRuleProc\n[\s\S]*?      onStreamFinished: \{\n([\s\S]*?)\n      \}\n/);
  assert.ok(rule);
  const answer = (text) => vm.runInNewContext(`(function() {${rule[1]}\n})()`, {root: c, coverRuleProc: c.coverRuleProc, text, Math});
  c.logEvent = () => {};
  answer('ok');
  assert.equal(c.coverRuleEpoch, 1);
  assert.equal(c.coverRuleValid, true);
  c.compositorBarrierWanted = false;
  c.coverRuleProc.running = false;
  c.handleCompositorReload();
  assert.equal(c.coverRuleValid, false, 'a reload invalidates the rule until a new run succeeds');
  assert.equal(c.coverRuleProc.launch, 2);
  answer('refused');
  assert.equal(c.coverRuleValid, false, 'a refused run does not validate it');

  const cover = source.match(/  Variants \{\n    id: lockCover\n([\s\S]*?)^  \}/m)[1];
  const visible = cover.match(/\n      visible: ([^\n]*)/)[1];
  const ready = cover.match(/readonly property bool ruleReady: ([^\n]*)/)[1];
  const show = (state) => {
    const w = Object.assign({shownLatched: false, ruleWaitExpired: false, ruleLaunchNeeded: 3}, state.w);
    const root = Object.assign({lockCoverShown: true, coverRuleValid: true, coverRuleEpoch: 3}, state.root);
    w.ruleReady = vm.runInNewContext(`(${ready})`, {root, ruleLaunchNeeded: w.ruleLaunchNeeded});
    return vm.runInNewContext(`(${visible})`, Object.assign({root}, w));
  };
  assert.equal(show({}), true, 'a cover maps once a rule run started after it has succeeded');
  assert.equal(show({root: {coverRuleEpoch: 2}}), false, 'an older run, perhaps before a reload, does not count');
  assert.equal(show({root: {coverRuleValid: false}}), false, 'not after a reload until the rule is back');
  assert.equal(show({root: {coverRuleValid: false}, w: {ruleWaitExpired: true}}), true, 'if Hyprland never confirms it, the cover maps anyway');
  assert.equal(show({root: {coverRuleValid: false}, w: {shownLatched: true}}), true, 'a mapped cover is never unmapped by a reload');
  assert.equal(show({root: {lockCoverShown: false}, w: {shownLatched: true}}), false);
  assert.match(cover, /Component\.onCompleted: \{\n        ruleLaunchNeeded = root\.coverRuleLaunches \+ 1\n        root\.applyCoverRule\(\)\n      \}/,
    'a new cover asks for a fresh rule run and waits for it');
  assert.match(cover, /interval: 300\n        running: root\.lockCoverShown && !coverWindow\.visible && !coverWindow\.ruleReady\n/);
}
console.log('Lock-loss recovery regressions passed (mock compositor; no real lock).');
{
  // Marketplace review of 0.6.3 (omarchy-plugin-marketplace#14051): Qt reads
  // clipboard offers into any writable TextInput, focused or not, and
  // `enabled: false` does not make one read-only.
  const view = fs.readFileSync(path.join(rootDir, 'LockView.qml'), 'utf8');
  const input = view.match(/          TextInput \{\n            id: passwordInput\n([\s\S]*?)\n          \}/);
  assert.ok(input, 'the lock view has one password field');
  const readOnly = input[1].match(/\n            readOnly: ([^\n]*)/);
  assert.ok(readOnly, 'the password field declares readOnly');
  const ro = (inputEnabled, authenticatingPassword) => vm.runInNewContext(`(${readOnly[1]})`, {root: {inputEnabled, authenticatingPassword}});
  assert.equal(ro(false, false), true, 'a lock view that takes no input (preview, idle) is read-only');
  assert.equal(ro(true, true), true, 'read-only while a password is checked');
  assert.equal(ro(true, false), false, 'the real lock still takes typing');
  assert.equal((view.match(/TextInput \{/g) || []).length, 1, 'no other text input in the lock view');

  const preview = source.match(/  PanelWindow \{\n    id: previewWindow\n([\s\S]*?)\n  \}\n/);
  assert.ok(preview, 'the preview window exists');
  assert.match(preview[1], /    Loader \{\n      id: previewLockView\n      anchors\.fill: parent\n      active: root\.previewVisible\n\n      sourceComponent: LockView \{\n/,
    'the preview lock view exists only while the preview is shown');
  assert.equal((preview[1].match(/LockView \{/g) || []).length, 1);
  // Every lock view in the service is the preview (on demand) or a session
  // lock surface's (which exist only while locked).
  const views = [...source.matchAll(/^( *)(?:sourceComponent: )?LockView \{/gm)].map(m => m.index);
  assert.equal(views.length, 2, 'two lock views: the session lock surface and the preview');
  const lockSurface = source.indexOf('    WlSessionLockSurface {');
  assert.ok(lockSurface > 0 && views[0] > lockSurface && views[0] < source.indexOf('  PanelWindow {', lockSurface),
    'the other lock view lives on the session lock surface');
  const standalone = fs.readFileSync(path.join(rootDir, 'standalone/shell.qml'), 'utf8');
  assert.match(standalone, /Hello\.LockView \{[\s\S]*?inputEnabled: false/, 'the standalone preview takes no input, so its field is read-only');
}
console.log('Preview clipboard regressions passed (no QML instantiated).');

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
{
  // Omarchy 4.5 video wallpapers: the lock draws the poster from 4.5's own
  // lock/poster.sh, and passes the path through where that script is missing.
  const c = context();
  c.posterProc = {running: false, sourcePath: ''};
  const still = '/home/u/Wallpapers/still.png';
  const video = '/home/u/Wallpapers/clip.MP4';
  assert.equal(c.isVideoPath(still), false);
  assert.equal(c.isVideoPath(video), true);
  assert.equal(c.lockWallpaperFor(still, '', ''), still, 'a still wallpaper is drawn as before');
  assert.equal(c.lockWallpaperFor(still, '/cache/p.jpg', 'yes'), still);
  assert.equal(c.lockWallpaperFor(video, '', ''), '', 'no video path is drawn while support is unknown');
  assert.equal(c.lockWallpaperFor(video, '/cache/p.jpg', 'yes'), '/cache/p.jpg');
  assert.equal(c.lockWallpaperFor(video, '', 'yes'), '', 'a failed poster leaves the plain background');
  assert.equal(c.lockWallpaperFor(video, '', 'no'), video, 'Omarchy 4.0 keeps the 0.6.0 behaviour');

  c.backgroundPath = still; c.videoBackground = false; c.videoPosterPath = '/cache/old.jpg';
  c.refreshPoster();
  assert.equal(c.posterProc.running, false, 'still wallpapers never run the poster script');
  assert.equal(c.videoPosterPath, '');

  c.backgroundPath = video; c.videoBackground = true;
  c.refreshPoster();
  assert.equal(c.posterProc.running, true);
  assert.equal(c.posterProc.sourcePath, video);
  c.posterProc.running = false;
  c.posterFinished(video, 0, '/cache/omarchy/lock-poster/poster-1.jpg\n');
  assert.equal(c.posterSupport, 'yes');
  assert.equal(c.videoPosterPath, '/cache/omarchy/lock-poster/poster-1.jpg');
  c.posterFinished(video, 1, '');
  assert.equal(c.videoPosterPath, '', 'a failing script leaves no poster');
  c.posterFinished(video, 0, 'relative.jpg\n');
  assert.equal(c.videoPosterPath, '', 'only an absolute image path is accepted');
  c.posterFinished(video, 0, 'unsupported\n');
  assert.equal(c.posterSupport, 'no');
  assert.equal(c.videoPosterPath, '');

  c.backgroundPath = '/home/u/Wallpapers/other.webm';
  c.posterFinished(video, 0, '/cache/stale.jpg');
  assert.equal(c.videoPosterPath, '', 'a result for a previous wallpaper is dropped');
  assert.equal(c.posterProc.sourcePath, '/home/u/Wallpapers/other.webm', 'and the new one is requested');

  assert.match(source, /command: \["bash", "-c", "\[\[ -f \$1 \]\] \|\| \{ echo unsupported; exit 0; \}; exec bash \\"\$1\\" \\"\$2\\"", "hello-lock-poster",\n      root\.posterScript, sourcePath\]/,
    'the wallpaper path reaches the script only as an argument');
  for (const binding of ['backgroundPath: root.wallpaperPath', 'value: root.wallpaperPath', 'item.backgroundPath = root.wallpaperPath'])
    assert.ok(source.includes(binding), binding);
  assert.ok(!/backgroundPath: root\.backgroundPath|item\.backgroundPath = root\.backgroundPath|value: root\.backgroundPath/.test(source),
    'every wallpaper consumer draws the resolved path');
}
console.log('Video wallpaper poster regressions passed (no QML instantiated).');

// Caps Lock without a keyboard LED: hyprctl's per-keyboard capsLock decides,
// the LED is the fallback, and the preview override always wins.
{
  const view = fs.readFileSync(path.join(rootDir, 'LockView.qml'), 'utf8');
  const fn = view.match(/^  function hyprCaps\(kbs\) \{\n[\s\S]*?^  \}/m);
  const binding = view.match(/readonly property bool capsLock: ([^\n]*\n[^\n]*)/);
  assert.ok(fn && binding);
  const scope = vm.createContext({});
  vm.runInContext(fn[0].replace('  function hyprCaps', 'function hyprCaps'), scope);
  const caps = (state) => vm.runInNewContext(`(${binding[1]})`, state);
  const parse = (json) => scope.hyprCaps(JSON.parse(json).keyboards || []);
  const kb = (extra) => Object.assign({name: 'k', main: false}, extra);

  assert.equal(scope.hyprCaps([kb({main: true, capsLock: true})]), 1);
  assert.equal(scope.hyprCaps([kb({main: true, capsLock: false})]), 0);
  // main is preferred over a secondary keyboard, either way round
  assert.equal(scope.hyprCaps([kb({capsLock: true}), kb({main: true, capsLock: false})]), 0);
  assert.equal(scope.hyprCaps([kb({capsLock: false}), kb({main: true, capsLock: true})]), 1);
  // no main marked: any keyboard that reports it
  assert.equal(scope.hyprCaps([kb({capsLock: false}), kb({capsLock: true})]), 1);
  assert.equal(scope.hyprCaps([kb({capsLock: false}), kb({capsLock: false})]), 0);
  // nothing usable: unknown, so the LED decides
  assert.equal(parse('{}'), -1);
  assert.equal(parse('{"keyboards":[]}'), -1);
  assert.equal(scope.hyprCaps([kb({main: true})]), -1);

  const state = (o) => Object.assign({capsOverride: -1, capsHypr: -1, capsLed: false}, o);
  assert.equal(caps(state({capsHypr: 1})), true, 'hyprctl on, no LED');
  assert.equal(caps(state({capsHypr: 0, capsLed: true})), false, 'hyprctl is authoritative when it reports');
  assert.equal(caps(state({capsLed: true})), true, 'LED fallback when hyprctl fails');
  assert.equal(caps(state({})), false);
  assert.equal(caps(state({capsOverride: 1, capsHypr: 0})), true, 'override forces on');
  assert.equal(caps(state({capsOverride: 0, capsHypr: 1, capsLed: true})), false, 'override forces off');
  // a failed query resets to unknown
  assert.match(view, /catch \(e\) \{\n\s+root\.capsHypr = -1/);
}
console.log('Caps Lock hyprctl regressions passed.');
