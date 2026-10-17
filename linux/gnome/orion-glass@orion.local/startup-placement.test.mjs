import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const policySource = await readFile(new URL('./policy.js', import.meta.url), 'utf8');
const policy = await import(`data:text/javascript,${encodeURIComponent(policySource)}`);
const source = (await readFile(new URL('./extension.js', import.meta.url), 'utf8'))
  .replace(/^import .*;\n/gm, '')
  .replace('export default class OrionDesktopGlass extends Extension', 'globalThis.OrionDesktopGlass = class OrionDesktopGlass extends Extension');
class Signals {
  constructor() { this.handlers = new Map(); this.serial = 0; }
  connect(name, callback) { const id = ++this.serial; this.handlers.set(id, {name, callback}); return id; }
  disconnect(id) { this.handlers.delete(id); }
  emit(name) { for (const {name: signal, callback} of [...this.handlers.values()]) if (name === signal) callback(); }
}
class Window extends Signals {
  constructor(pid = 100, title = 'Orion', width = 822, height = 523) {
    super(); Object.assign(this, {pid, title, x: 0, y: 0, width, height, moves: []});
  }
  get_pid() { return this.pid; }
  get_title() { return this.title; }
  get_frame_rect() { return {x: this.x, y: this.y, width: this.width, height: this.height}; }
  move_to_monitor(index) { this.monitor = index; }
  move_frame(_user, x, y) { Object.assign(this, {x, y}); this.moves.push([x, y]); this.emit('position-changed'); }
}
const monitors = [{index: 0, x: 0, y: 0, width: 1920, height: 1080},
  {index: 1, x: -2560, y: -200, width: 2560, height: 1440}];
function harness(windows = [], pointer = [-2000, 200]) {
  const actors = windows.map(window => ({get_meta_window: () => window}));
  const watchers = new Map(), timers = new Map(); let serial = 0;
  const Gio = {
    DBus: {session: {}}, BusNameOwnerFlags: {NONE: 0}, BusNameWatcherFlags: {NONE: 0},
    DBusExportedObject: {wrapJSObject: () => ({export() {}, unexport() {}})},
    bus_own_name_on_connection: () => ++serial, bus_unown_name() {},
    bus_watch_name_on_connection(_c, sender, _f, _a, vanished) { const id = ++serial; watchers.set(id, {sender, vanished}); return id; },
    bus_unwatch_name(id) { watchers.delete(id); },
  };
  const GLib = {PRIORITY_DEFAULT: 0, SOURCE_REMOVE: false, Source: {remove(id) { timers.delete(id); }},
    timeout_add(_priority, _duration, callback) { const id = ++serial; timers.set(id, callback); return id; }};
  const shell = {window_manager: new Signals(), display: new Signals(), stage: new Signals(),
    get_window_actors: () => actors, get_pointer: () => pointer};
  const Main = {layoutManager: {monitors: monitors.map(m => ({...m})),
    getWorkAreaForMonitor(index) { const m = this.monitors[index]; return {x: m.x, y: m.y + 32, width: m.width, height: m.height - 32}; }}};
  const scope = {Extension: class {}, Gio, GLib, Main, Config: {PACKAGE_VERSION: '46'}, global: shell, console, ...policy};
  vm.runInNewContext(source, scope);
  const extension = new scope.OrionDesktopGlass(); extension.enable();
  extension._reply = (invocation, value) => { invocation.value = value; };
  extension._callerPid = async invocation => ({pid: invocation.pid ?? 100, sender: invocation.get_sender()});
  const invoke = async (args = [100, 'Orion'], pid = 100, sender = ':owned', method = 'CenterOnPointerMonitorAsync') => {
    const invocation = {pid, get_sender: () => sender};
    await extension[method](args, invocation);
    assert.ok(invocation.value); return invocation.value;
  };
  const add = window => { windows.push(window); actors.push({get_meta_window: () => window}); };
  const disconnect = sender => { for (const entry of [...watchers.values()]) if (entry.sender === sender) entry.vanished(); };
  return {extension, invoke, add, disconnect, windows, actors, pointer, watchers, timers, Main};
}
{
  const h = harness();
  assert.equal((await h.invoke([100, 'Orion'], 101)).reason, 'caller-pid-mismatch');
  for (const title of ['', 'Orion\0', 'x'.repeat(257)]) assert.equal((await h.invoke([100, title])).reason, 'invalid-window-title');
  assert.equal(h.extension._placementRules.size, 0); assert.equal(h.timers.size, 0);
  h.extension.disable();
}
{
  const other = new Window(101), companion = new Window(100, 'Orion Theme Studio');
  const h = harness([other, companion]);
  assert.equal((await h.invoke()).reason, 'waiting-window');
  // Mouse moves to the primary screen while asynchronous startup loads. Only
  // the launch monitor remains the target, regardless of the cursor position.
  h.pointer.splice(0, 2, 1500, 100);
  const main = new Window(); h.add(main); h.extension._reconcile();
  assert.deepEqual(main.moves, [[-1691, 259]]); assert.equal(main.monitor, 1);
  assert.equal(other.moves.length, 0); assert.equal(companion.moves.length, 0);
  assert.equal(h.extension._placementRules.size, 0); assert.equal(h.timers.size, 0); assert.equal(h.watchers.size, 0);
  main.move_frame(true, -1400, 100); main.width = 900; h.extension._reconcile();
  assert.deepEqual(main.moves, [[-1691, 259], [-1400, 100]], 'subsequent manual moves/resizes never recenter');
  h.extension.disable();
}
{
  const main = new Window(100, 'Orion', 1045, 648), h = harness([main], [20, 30]);
  assert.equal((await h.invoke()).reason, 'centered'); assert.deepEqual(main.moves, [[438, 216]]);
  h.extension.disable();
}
{
  const h = harness(); let release;
  h.extension._callerPid = invocation => new Promise(resolve => { release = () => resolve({pid: 100, sender: invocation.get_sender()}); });
  const invocation = {get_sender: () => ':owned'};
  const pending = h.extension.CenterOnPointerMonitorAsync([100, 'Orion'], invocation);
  h.pointer.splice(0, 2, 100, 100); release(); await pending;
  const main = new Window(); h.add(main); h.extension._reconcile();
  assert.deepEqual(main.moves, [[-1691, 259]], 'snapshot predates authorization completion');
  h.extension.disable();
}
{
  const h = harness(); await h.invoke(); h.disconnect(':owned');
  const main = new Window(); h.add(main); h.extension._reconcile();
  assert.equal(main.moves.length, 0); assert.equal(h.timers.size, 0); h.extension.disable();
}
{
  const h = harness(); await h.invoke();
  for (const callback of [...h.timers.values()]) callback(); h.timers.clear();
  assert.equal(h.extension._placementRules.size, 0); assert.equal(h.watchers.size, 0); h.extension.disable();
}
{
  const h = harness(); await h.invoke(); h.extension.disable();
  assert.equal(h.extension._placementRules.size, 0); assert.equal(h.timers.size, 0); assert.equal(h.watchers.size, 0);
}
{
  const h = harness(); await h.invoke(); h.Main.layoutManager.monitors.pop();
  const main = new Window(); h.add(main); h.extension._reconcile();
  assert.equal(main.moves.length, 0); assert.equal(h.extension._placementRules.size, 0); h.extension.disable();
}
{
  const h = harness();
  for (let i = 0; i < policy.MAX_RULES; i++) assert.equal((await h.invoke([100, `Orion ${i}`])).ok, true);
  assert.equal((await h.invoke([100, 'overflow'])).reason, 'window-limit'); h.extension.disable();
}
{
  const h = harness([new Window(), new Window()]); await h.invoke();
  assert.ok(h.windows.every(w => w.moves.length === 0), 'ambiguous titles never move multiple windows'); h.extension.disable();
}
{
  const h = harness();
  await h.invoke();
  assert.equal((await h.invoke([100, 'Orion'], 101, ':other', 'TrackStartupResizeAsync')).reason, 'caller-pid-mismatch');
  assert.equal((await h.invoke([100, 'Orion'], 100, ':other', 'TrackStartupResizeAsync')).reason, 'no-startup-placement');
  assert.equal((await h.invoke([100, 'Orion'], 100, ':owned', 'TrackStartupResizeAsync')).ok, true);
  const main = new Window(100, 'Orion', 290, 355); h.add(main); h.extension._reconcile();
  assert.equal(h.extension._placementStates.size, 1);
  assert.deepEqual(main.moves, [[-1425, 343]]);
  main.width = 714; main.height = 393; main.emit('size-changed');
  assert.deepEqual(main.moves.at(-1), [-1637, 324], 'authored loader morph stays on launch display');
  // Title changes are normal for source loaders. Completing the authenticated
  // startup follows the retained MetaWindow and does not need the former title.
  main.title = 'Synapse Blue';
  await h.invoke([100, 'Synapse Blue'], 100, ':owned', 'FinishStartupPlacementAsync');
  assert.equal(h.extension._placementStates.size, 0); assert.equal(h.timers.size, 0); assert.equal(h.watchers.size, 0);
  const count = main.moves.length; main.width = 800; main.emit('size-changed');
  assert.equal(main.moves.length, count); h.extension.disable();
}
{
  const h = harness(); await h.invoke(); await h.invoke([100, 'Orion'], 100, ':owned', 'TrackStartupResizeAsync');
  const main = new Window(); h.add(main); h.extension._reconcile();
  main.move_frame(true, -1400, 100); // Manual dragging cancels startup tracking.
  assert.equal(h.extension._placementStates.size, 0);
  const count = main.moves.length; main.width = 900; main.emit('size-changed');
  assert.equal(main.moves.length, count); assert.equal(h.timers.size, 0); h.extension.disable();
}
{
  const h = harness(); await h.invoke(); await h.invoke([100, 'Orion'], 100, ':owned', 'TrackStartupResizeAsync');
  const main = new Window(); h.add(main); h.extension._reconcile();
  h.disconnect(':owned');
  assert.equal(h.extension._placementStates.size, 0); assert.equal(h.timers.size, 0); h.extension.disable();
}
{
  const h = harness(); let release;
  h.extension._callerPid = invocation => new Promise(resolve => { release = () => resolve({pid: 100, sender: invocation.get_sender()}); });
  const invocation = {get_sender: () => ':owned'};
  const pending = h.extension.CenterOnPointerMonitorAsync([100, 'Orion'], invocation);
  h.extension.disable(); h.extension.enable(); release(); await pending;
  assert.equal(invocation.value.reason, 'superseded'); assert.equal(h.extension._placementRules.size, 0); h.extension.disable();
}
{
  const h = harness(); const releases = [];
  h.extension._callerPid = invocation => new Promise(resolve => releases.push(() => resolve({pid: 100, sender: invocation.get_sender()})));
  const old = {get_sender: () => ':owned'}, fresh = {get_sender: () => ':owned'};
  const pendingOld = h.extension.CenterOnPointerMonitorAsync([100, 'Orion'], old);
  h.pointer.splice(0, 2, 100, 100);
  const pendingFresh = h.extension.CenterOnPointerMonitorAsync([100, 'Orion'], fresh);
  releases[1](); await pendingFresh; releases[0](); await pendingOld;
  assert.equal(old.value.reason, 'superseded');
  const main = new Window(); h.add(main); h.extension._reconcile();
  assert.deepEqual(main.moves, [[549, 279]]); h.extension.disable();
}
assert.equal(policy.pointerMonitor(monitors, -2000, 100).index, 1);
assert.equal(policy.pointerMonitor(monitors, 0, 0).index, 0);
assert.equal(policy.pointerMonitor(monitors, NaN, 0), null);
assert.equal(policy.pointerMonitor([], 0, 0), null);
assert.equal(policy.pointerMonitor(monitors, 3000, 100).index, 0);
assert.deepEqual(policy.centeredStartupFrame(monitors[1], {x: -2560, y: -168, width: 2560, height: 1408}, 822, 523),
  {x: -1691, y: 259, width: 822, height: 523});
assert.deepEqual(policy.centeredStartupFrame({x: 0, y: 0, width: 800, height: 600}, {x: 0, y: 32, width: 800, height: 568}, 1045, 648),
  {x: 0, y: 32, width: 1045, height: 648});
console.log('PASS: pointer-monitor centering, exact main-window isolation, startup snapshot, owner authorization, one-shot moves, bounded lifecycle, negative coordinates and logical-DPI geometry');
