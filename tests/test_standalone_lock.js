// Execute the actual security-core JS. These are mocks, separate from real VM PAM tests.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../standalone/lock.qml'), 'utf8');
const methods = [...source.matchAll(/^  function (\w+)\(([^\n]*)\) \{\n([\s\S]*?)^  \}/gm)];
function context() {
  const timer = () => ({running: false, start() { this.running = true }, restart() { this.running = true }, stop() { this.running = false }});
  const c = {Qt: {exit(code) { this.code = code }}, busy: false, pending: '', entered: '', failure: '', attempts: 0, granted: false,
    released: false, releasing: false, everSecure: false, answered: false, phase: 'locked', generation: 'fixture', lockPlan: {}, statusReady: false,
    extras: {item: null}, lockStartedAt: Date.now() - 120000,
    session: {secure: true, locked: true}, stateFile: {setText(s) { this.value = s }},
    authTimeout: timer(), releaseGate: timer(), exitDelay: timer(), quickExit: timer(), Loader: {Error: 3},
    Quickshell: {screens: [{}], env() { return '' }}, PamResult: {Success: 0},
    pam: {active: false, responseRequired: false, responseVisible: false,
      start() { this.active = true; return true }, abort() { this.active = false },
      respond(value) { this.response = value }}, splash: {item: null}, config: {}, calm: true};
  c.root = c; vm.createContext(c);
  for (const m of methods) vm.runInContext(`function ${m[1]}(${m[2]}) {${m[3]}\n}`, c);
  return c;
}
{
  const c = context(); c.session.secure = false; c.submit('fixture');
  assert.equal(c.busy, false); assert.equal(c.pam.active, false);
  c.completeAuthentication(c.PamResult.Success); c.releaseAuthenticated();
  assert.equal(c.session.locked, true, 'unarmed/stale success cannot release');
}
{
  const c = context(); c.submit('private-fixture');
  assert.equal(c.session.locked, true); assert.equal(c.releaseGate.running, false);
  assert.ok(!c.stateFile.value.includes('private-fixture'), 'runtime state never contains input');
  c.pam.responseRequired = true; c.answerPrompt();
  assert.equal(c.pam.response, 'private-fixture'); assert.equal(c.pending, '');
  c.completeAuthentication(1);
  assert.equal(c.session.locked, true); assert.equal(c.granted, false); assert.equal(c.attempts, 1);
}
{
  const c = context(); c.submit('fixture'); c.pam.responseRequired = true; c.pam.responseVisible = true;
  c.answerPrompt(); assert.equal(c.pam.response, undefined, 'no password to echo-on prompts');
  assert.equal(c.pending, ''); assert.equal(c.session.locked, true);
}
{
  const c = context(); c.submit('fixture'); c.pam.responseRequired = true; c.answerPrompt();
  c.answerPrompt(); assert.equal(c.busy, false, 'additional-factor prompt refuses password replay');
  assert.equal(c.session.locked, true);
}
{
  const c = context(); c.submit('fixture'); c.pam.responseRequired = true; c.answerPrompt();
  Object.defineProperty(c.splash, 'active', {set() { throw Error('broken visual') }});
  c.completeAuthentication(c.PamResult.Success);
  assert.equal(c.session.locked, true); assert.equal(c.releaseGate.running, true);
  c.splash.item = {play() { throw Error('broken visual') }};
  c.releaseAuthenticated(); assert.equal(c.session.locked, false); assert.equal(c.released, true);
  assert.equal(c.exitDelay.running, true);
}
{
  const c = context(); c.busy = true; c.pending = 'fixture'; c.fail('timeout');
  c.completeAuthentication(c.PamResult.Success); c.releaseAuthenticated();
  assert.equal(c.session.locked, true); assert.equal(c.pending, '');
}
{
  const c = context(); c.config.unlockAnimation = false;
  c.completeAuthentication(c.PamResult.Success);
  assert.equal(c.session.locked, true, 'instant mode still rejects unarmed success');
  c.submit('fixture'); c.pam.responseRequired = true; c.answerPrompt();
  c.completeAuthentication(c.PamResult.Success);
  assert.equal(c.session.locked, false, 'instant release requires the real armed PAM-success path');
  assert.equal(c.releaseGate.running, false);
  assert.equal(c.splash.active, undefined);
}
console.log('Standalone authentication guards passed (mock PAM/compositor).');

{
  const c = context(); c.cosmeticFinishRequested = true;
  c.finishCosmetic();
  assert.equal(c.session.locked, true, 'cosmetic finish cannot release a lock');
  assert.equal(c.quickExit.running, false, 'cosmetic finish cannot close an unauthenticated locker');
}

{
  const c = context(); c.everSecure = true; c.busy = true; c.granted = true;
  c.pending = 'fixture'; c.entered = 'fixture'; c.pam.active = true;
  c.releaseGate.start(); c.session.secure = false;
  c.lockLost();
  assert.equal(c.phase, 'lock-lost'); assert.equal(c.Qt.code, 3);
  assert.equal(c.busy, false); assert.equal(c.granted, false);
  assert.equal(c.pending, ''); assert.equal(c.entered, '');
  assert.equal(c.releaseGate.running, false); assert.equal(c.pam.active, false);
  c.session.secure = true;
  c.completeAuthentication(c.PamResult.Success); c.releaseAuthenticated();
  assert.equal(c.session.locked, true, 'late PAM completion after lock loss cannot release');
}
{
  const c = context(); c.everSecure = true; c.releasing = true;
  c.lockLost(); assert.notEqual(c.phase, 'lock-lost', 'intentional authenticated release is not a loss');
}
