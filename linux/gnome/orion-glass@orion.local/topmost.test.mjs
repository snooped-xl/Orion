import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

// Run the production helper class, replacing only GNOME transport/rendering.
// Window state, lifecycle, authorization and request ordering stay production.
const policySource = await readFile(new URL('./policy.js', import.meta.url), 'utf8');
const policy = await import(`data:text/javascript,${encodeURIComponent(policySource)}`);
const source = (await readFile(new URL('./extension.js', import.meta.url), 'utf8'))
  .replace(/^import .*;\n/gm, '')
  .replace('export default class OrionDesktopGlass extends Extension', 'globalThis.OrionDesktopGlass = class OrionDesktopGlass extends Extension');

class Signals {
  constructor() { this.handlers = new Map(); this.serial = 0; }
  connect(name, callback) { const id = ++this.serial; this.handlers.set(id, {name, callback}); return id; }
  disconnect(id) { this.handlers.delete(id); }
  emit(name) { for (const {name: signal, callback} of [...this.handlers.values()]) if (signal === name) callback(); }
}
class Window extends Signals {
  constructor(pid, title, above = false) { super(); this.pid = pid; this.title = title; this.above = above; this.makeCalls = 0; this.unmakeCalls = 0; }
  get_pid() { return this.pid; }
  get_title() { return this.title; }
  is_above() { return this.above; }
  make_above() { this.makeCalls++; if (!this.above) { this.above = true; this.emit('notify::above'); } }
  unmake_above() { this.unmakeCalls++; if (this.above) { this.above = false; this.emit('notify::above'); } }
  rename(title) { this.title = title; this.emit('notify::title'); }
}
class Actor extends Signals {
  constructor(window) { super(); this.window = window; }
  get_meta_window() { return this.window; }
  get_first_child() { return {}; }
  get_parent() { return {}; }
}
function harness(windows = [new Window(100, 'Orion')]) {
  const actors = windows.map(window => new Actor(window));
  const watchers = new Map(); let serial = 0;
  const Gio = {
    DBus: {session: {}}, BusNameOwnerFlags: {NONE: 0}, BusNameWatcherFlags: {NONE: 0},
    DBusExportedObject: {wrapJSObject: () => ({export() {}, unexport() {}})},
    bus_own_name_on_connection: () => ++serial, bus_unown_name() {},
    bus_watch_name_on_connection(_connection, sender, _flags, _appeared, vanished) { const id = ++serial; watchers.set(id, {sender, vanished}); return id; },
    bus_unwatch_name(id) { watchers.delete(id); },
  };
  const shell = {window_manager: new Signals(), display: new Signals(), stage: new Signals(), get_window_actors: () => actors};
  const scope = {Extension: class {}, Gio, GLib: {}, Config: {PACKAGE_VERSION: '46'}, global: shell, console, ...policy};
  vm.runInNewContext(source, scope);
  const extension = new scope.OrionDesktopGlass();
  extension.enable();
  extension._reply = (invocation, value) => { invocation.value = value; };
  extension._callerPid = async invocation => ({pid: invocation.pid ?? 100, sender: invocation.get_sender()});
  // GPU attachment is outside these policy tests. Keep actual material maps and
  // removal/reconciliation, so shared cleanup and feature independence execute.
  extension._attach = (actor, rule) => extension._states.set(actor, {actor, rule, signals: [], glass: {cleanup() {}, destroy() {}}});
  const invoke = async (method, args, pid = 100, sender = ':owned') => {
    const invocation = {pid, get_sender: () => sender};
    await extension[method](args, invocation);
    assert.ok(invocation.value, `${method} must always reply`);
    return invocation.value;
  };
  const top = (enabled, title = 'Orion', pid = 100, sender = ':owned') => invoke('SetAlwaysOnTopAsync', [pid, title, enabled], pid, sender);
  const glass = (enabled, title = 'Orion', pid = 100, sender = ':owned') => invoke('ConfigureAsync', [pid, title, enabled, 24], pid, sender);
  const disconnect = sender => { for (const entry of [...watchers.values()]) if (entry.sender === sender) entry.vanished(); };
  return {extension, windows, actors, watchers, top, glass, invoke, disconnect};
}

{
  const h = harness([new Window(100, 'Orion'), new Window(101, 'Orion'), new Window(100, 'Orion other')]);
  const denied = await h.invoke('SetAlwaysOnTopAsync', [100, 'Orion', true], 101);
  assert.equal(denied.reason, 'caller-pid-mismatch');
  assert.equal(h.extension._topRules.size, 0);
  for (const [args, reason] of [
    [[100, '', true], 'invalid-window-title'],
    [[100, 'Orion\0', true], 'invalid-window-title'],
    [[100, 'Orion', 1], 'invalid-topmost-switch'],
  ]) assert.equal((await h.invoke('SetAlwaysOnTopAsync', args)).reason, reason);
  const active = await h.top(true);
  assert.equal(active.active, true); assert.equal(active.above, true); assert.equal(active.windowCount, 1);
  assert.deepEqual(h.windows.map(window => window.is_above()), [true, false, false]);
  const deniedStatus = await h.invoke('GetTopmostStatusAsync', [100, 'Orion'], 101);
  assert.equal(deniedStatus.reason, 'caller-pid-mismatch');
  const state = h.extension._topStates.get(h.actors[0]);
  const writes = h.windows[0].makeCalls;
  await h.top(true); await h.top(true);
  assert.equal(h.extension._topStates.get(h.actors[0]), state);
  assert.equal(state.originalAbove, false, 'repeat enable must not overwrite original state');
  assert.equal(h.windows[0].makeCalls, writes, 'repeat enable must not issue redundant changes');
  h.windows[0].unmake_above();
  assert.equal(h.windows[0].is_above(), true, 'managed window automatically recovers above flag');
  await h.top(false);
  assert.equal(h.windows[0].is_above(), false);
  assert.equal(h.extension._topStates.size, 0); assert.equal(h.extension._topRules.size, 0); assert.equal(h.watchers.size, 0);
  h.extension.disable();
}
console.log('PASS: actual topmost authorization, exact PID/title matching, status and idempotent enforcement');

{
  const h = harness();
  await h.glass(true); await h.top(true);
  assert.equal(h.extension._states.size, 1); assert.equal(h.extension._topStates.size, 1);
  assert.equal(h.watchers.size, 1, 'shared owner connection requires only one watcher');
  await h.glass(false);
  assert.equal(h.extension._states.size, 0); assert.equal(h.extension._topStates.size, 1); assert.equal(h.windows[0].is_above(), true);
  assert.equal(h.watchers.size, 1, 'topmost retains caller watch when glass turns off');
  await h.glass(true); await h.top(false);
  assert.equal(h.extension._states.size, 1); assert.equal(h.extension._topStates.size, 0); assert.equal(h.windows[0].is_above(), false);
  assert.equal(h.watchers.size, 1, 'glass retains caller watch when topmost turns off');
  await h.top(true); h.disconnect(':owned');
  assert.equal(h.extension._states.size, 0); assert.equal(h.extension._rules.size, 0);
  assert.equal(h.extension._topStates.size, 0); assert.equal(h.extension._topRules.size, 0);
  assert.equal(h.windows[0].is_above(), false); assert.equal(h.watchers.size, 0);
  h.extension.disable();
}
console.log('PASS: independent material/topmost state and shared caller lifecycle');

{
  for (const originallyAbove of [false, true]) {
    for (const cleanup of ['disable-request', 'disconnect', 'title-change', 'extension-disable', 'window-destroy']) {
      const h = harness([new Window(100, 'Orion', originallyAbove)]);
      await h.top(true);
      if (cleanup === 'disable-request') await h.top(false);
      if (cleanup === 'disconnect') h.disconnect(':owned');
      if (cleanup === 'title-change') h.windows[0].rename('Other');
      if (cleanup === 'extension-disable') h.extension.disable();
      if (cleanup === 'window-destroy') {
        const before = [h.windows[0].makeCalls, h.windows[0].unmakeCalls];
        h.actors[0].emit('destroy');
        assert.deepEqual([h.windows[0].makeCalls, h.windows[0].unmakeCalls], before, 'destroyed window must not receive restore calls');
      } else assert.equal(h.windows[0].is_above(), originallyAbove, `${cleanup} restores original ${originallyAbove}`);
      assert.equal(h.extension._topStates.size, 0, cleanup);
      assert.equal(h.windows[0].handlers.size, 0, `${cleanup} disconnects window signals`);
      assert.equal(h.actors[0].handlers.size, 0, `${cleanup} disconnects actor signals`);
      h.extension.disable(); h.extension.disable();
      assert.equal(h.watchers.size, 0);
    }
  }
}
console.log('PASS: false/true original state restored on release, disconnect, rename and disable; destroy safely detaches');

{
  const h = harness();
  const releases = [];
  h.extension._callerPid = invocation => new Promise(resolve => releases.push(() => resolve({pid: 100, sender: invocation.get_sender()})));
  const old = {get_sender: () => ':owned'}, newer = {get_sender: () => ':owned'};
  const pendingOld = h.extension.SetAlwaysOnTopAsync([100, 'Orion', true], old);
  const pendingNew = h.extension.SetAlwaysOnTopAsync([100, 'Orion', false], newer);
  releases[1](); await pendingNew; releases[0](); await pendingOld;
  assert.equal(newer.value.reason, 'disabled'); assert.equal(old.value.reason, 'superseded');
  assert.equal(h.windows[0].is_above(), false); assert.equal(h.extension._topRules.size, 0); assert.equal(h.extension._requests.latest.size, 0);
  h.extension.disable();
}
console.log('PASS: late topmost authorization cannot override a newer disable');

{
  const h = harness();
  const releases = [];
  h.extension._callerPid = invocation => new Promise(resolve => releases.push(() => resolve({pid: 100, sender: invocation.get_sender()})));
  const top = {get_sender: () => ':owned'}, glass = {get_sender: () => ':owned'};
  const pendingTop = h.extension.SetAlwaysOnTopAsync([100, 'Orion', true], top);
  const pendingGlass = h.extension.ConfigureAsync([100, 'Orion', true, 24], glass);
  assert.equal(h.extension._requests.latest.size, 2, 'features must have separate request epochs');
  releases[1](); await pendingGlass; releases[0](); await pendingTop;
  assert.equal(glass.value.active, true); assert.equal(top.value.active, true);
  assert.equal(h.extension._states.size, 1); assert.equal(h.extension._topStates.size, 1);
  h.extension.disable();
}
console.log('PASS: simultaneous glass and topmost requests cannot supersede each other');

{
  const h = harness();
  const releases = [];
  h.extension._callerPid = invocation => new Promise(resolve => releases.push(() => resolve({pid: 100, sender: invocation.get_sender()})));
  const old = {get_sender: () => ':owned'}, fresh = {get_sender: () => ':owned'};
  const pendingOld = h.extension.SetAlwaysOnTopAsync([100, 'Orion', true], old);
  const oldRequests = h.extension._requests;
  h.extension.disable(); h.extension.enable();
  const pendingFresh = h.extension.SetAlwaysOnTopAsync([100, 'Orion', false], fresh);
  assert.equal(oldRequests.serial, 1); assert.equal(h.extension._requests.serial, 1, 'simulate epoch-number reuse');
  releases[0](); await pendingOld;
  assert.equal(old.value.reason, 'superseded'); assert.equal(h.windows[0].is_above(), false);
  assert.equal(h.extension._requests.latest.size, 1, 'old finally must not finish new lifecycle request');
  releases[1](); await pendingFresh;
  assert.equal(fresh.value.reason, 'disabled'); assert.equal(h.extension._requests.latest.size, 0);
  h.extension.disable();
}
console.log('PASS: stale authorization cannot cross helper disable/enable lifecycle');

{
  const h = harness([]);
  const waiting = await h.top(true);
  assert.equal(waiting.reason, 'waiting-window'); assert.equal(waiting.active, false);
  const window = new Window(100, 'Orion'); h.windows.push(window); h.actors.push(new Actor(window));
  h.extension._reconcile(); assert.equal(window.is_above(), true, 'late mapping applies retained exact rule');
  for (let i = 1; i < policy.MAX_RULES; i++) assert.equal((await h.top(true, `Orion ${i}`)).ok, true);
  assert.equal((await h.top(true, 'Overflow')).reason, 'window-limit');
  h.extension.disable();
  const bounded = harness([]); bounded.extension._requests = new policy.RequestEpochs(1);
  let release; bounded.extension._callerPid = invocation => new Promise(resolve => { release = () => resolve({pid: 100, sender: invocation.get_sender()}); });
  const first = {get_sender: () => ':owned'};
  const pending = bounded.extension.SetAlwaysOnTopAsync([100, 'First', true], first);
  const rejected = await bounded.top(true, 'Second');
  assert.equal(rejected.reason, 'request-limit');
  bounded.extension.disable(); release(); await pending;
  assert.equal(first.value.reason, 'extension-disabled');
}
console.log('PASS: late maps, bounded window rules and bounded pending authorization');
