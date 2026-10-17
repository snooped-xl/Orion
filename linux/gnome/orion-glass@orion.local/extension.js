// Orion's compositor companion. It does not capture screenshots, export
// textures, replace wallpaper, or change any other extension or shell setting.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Config from 'resource:///org/gnome/shell/misc/config.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {BackdropGlass} from './dist/rendering/backdropGlass.js';
import {MAX_RULES, RequestEpochs, validateRequest, ruleKey, windowMatches, pointerMonitor, centeredStartupFrame} from './policy.js';

const BUS_NAME = 'org.orion.Glass';
const OBJECT_PATH = '/org/orion/Glass';
const INTERFACE = `<node><interface name="org.orion.Glass1">
  <method name="GetCapabilities"><arg type="s" direction="out"/></method>
  <method name="Configure"><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="b" direction="in"/><arg type="d" direction="in"/><arg type="s" direction="out"/></method>
  <method name="TrackStartupResize"><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
  <method name="FinishStartupPlacement"><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
  <method name="CenterOnPointerMonitor"><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
  <method name="SetAlwaysOnTop"><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="b" direction="in"/><arg type="s" direction="out"/></method>
  <method name="GetTopmostStatus"><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
  <method name="GetStatus"><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
</interface></node>`;

export default class OrionDesktopGlass extends Extension {
  enable() {
    this._disabled = false;
    this._rules = new Map();
    this._requests = new RequestEpochs();
    this._states = new Map();
    this._topRules = new Map();
    this._topStates = new Map();
    this._placementRules = new Map();
    this._placementStates = new Map();
    this._callers = new Map();
    this._signals = [];
    this._connection = Gio.DBus.session;
    this._bus = Gio.DBusExportedObject.wrapJSObject(INTERFACE, this);
    this._bus.export(this._connection, OBJECT_PATH);
    this._name = Gio.bus_own_name_on_connection(this._connection, BUS_NAME,
      Gio.BusNameOwnerFlags.NONE, null, null);
    this._signals.push([global.window_manager, global.window_manager.connect('map', () => this._reconcile())]);
    this._signals.push([global.display, global.display.connect('restacked', () => this._reconcile())]);
    this._signals.push([global.stage, global.stage.connect('before-update', () => {
      for (const state of [...this._states.values()]) {
        try { this._sync(state); }
        catch (error) { this._remove(state); console.error(`Orion Glass: ${error}`); }
      }
    })]);
  }

  disable() {
    this._disabled = true;
    for (const [object, id] of this._signals ?? []) {
      try { object.disconnect(id); } catch (_) {}
    }
    this._signals = [];
    for (const state of [...this._states?.values() ?? []]) this._remove(state);
    this._states?.clear();
    for (const state of [...this._topStates?.values() ?? []]) this._removeTopmost(state);
    this._topStates?.clear();
    this._topRules?.clear();
    for (const state of [...this._placementStates?.values() ?? []]) this._removeStartupPlacement(state);
    for (const rule of this._placementRules?.values() ?? [])
      if (rule.timeout) GLib.Source.remove(rule.timeout);
    this._placementRules?.clear();
    this._rules?.clear();
    this._requests?.clear();
    for (const id of this._callers?.values() ?? []) Gio.bus_unwatch_name(id);
    this._callers?.clear();
    this._bus?.unexport();
    this._bus = null;
    if (this._name) Gio.bus_unown_name(this._name);
    this._name = 0;
    this._connection = null;
  }

  GetCapabilities() {
    return JSON.stringify({apiVersion: 1, supported: true,
      gnomeVersion: Config.PACKAGE_VERSION, mode: 'compositor-backdrop',
      captureScope: 'window-background-rect', exportsPixels: false,
      configuredWindows: this._rules.size, activeWindows: this._states.size,
      startupPlacement: true, startupPlacementPendingWindows: this._placementRules.size + this._placementStates.size, alwaysOnTop: true, topmostConfiguredWindows: this._topRules.size,
      topmostActiveWindows: this._topStates.size});
  }

  async _callerPid(invocation) {
    const sender = invocation.get_sender();
    const result = await new Promise((resolve, reject) => {
      this._connection.call('org.freedesktop.DBus', '/org/freedesktop/DBus',
        'org.freedesktop.DBus', 'GetConnectionUnixProcessID',
        new GLib.Variant('(s)', [sender]), new GLib.VariantType('(u)'),
        Gio.DBusCallFlags.NONE, 1000, null, (connection, response) => {
          try { resolve(connection.call_finish(response).deep_unpack()[0]); }
          catch (error) { reject(error); }
        });
    });
    return {pid: result, sender};
  }

  _reply(invocation, value) {
    invocation.return_value(new GLib.Variant('(s)', [JSON.stringify(value)]));
  }

  async ConfigureAsync([pid, title, enabled, radius], invocation) {
    const invalidShape = validateRequest(pid, pid, title, radius);
    if (invalidShape) return this._reply(invocation, invalidShape);
    const requestKey = `glass:${invocation.get_sender()}:${ruleKey(pid, title)}`;
    // Authorization may finish after this extension has been disabled and
    // enabled again. Keep this lifecycle's request table, not only its serial:
    // a fresh table can reuse the same epoch number.
    const requests = this._requests;
    const epoch = requests.begin(requestKey);
    if (epoch === null) return this._reply(invocation, {ok: false, active: false, reason: 'request-limit'});
    try {
      const caller = await this._callerPid(invocation);
      if (this._disabled) return this._reply(invocation, {ok: false, active: false, reason: 'extension-disabled'});
      const invalid = validateRequest(caller.pid, pid, title, radius);
      if (invalid) return this._reply(invocation, invalid);
      if (this._requests !== requests || !requests.isCurrent(requestKey, epoch))
        return this._reply(invocation, {...this._status(pid, title), reason: 'superseded'});
      const key = ruleKey(pid, title);
      if (enabled) {
        if (!this._rules.has(key) && this._rules.size >= MAX_RULES)
          return this._reply(invocation, {ok: false, active: false, reason: 'window-limit'});
        this._rules.set(key, {pid, title, radius, sender: caller.sender});
        this._watchCaller(caller.sender);
      } else {
        this._rules.delete(key);
      }
      this._reconcile();
      this._pruneCallers();
      this._reply(invocation, this._status(pid, title));
    } catch (error) {
      this._reply(invocation, {ok: false, active: false, reason: `authorization-failed: ${error.message ?? error}`});
    } finally { requests.finish(requestKey, epoch); }
  }

  async CenterOnPointerMonitorAsync([pid, title], invocation) {
    const invalidShape = validateRequest(pid, pid, title, 0);
    if (invalidShape) return this._reply(invocation, invalidShape);
    // Capture before awaiting authorization, so moving the pointer while Orion
    // loads settings cannot silently change its launch display.
    let monitor, target;
    try {
      const [x, y] = global.get_pointer();
      monitor = pointerMonitor(Main.layoutManager.monitors, x, y);
      if (!monitor) return this._reply(invocation, {ok: false, reason: 'no-monitor'});
      const area = Main.layoutManager.getWorkAreaForMonitor(monitor.index);
      target = {...monitor, workarea: {
        x: area.x, y: area.y, width: area.width, height: area.height,
      }};
    } catch (_) { return this._reply(invocation, {ok: false, reason: 'no-monitor'}); }
    const requestKey = `placement:${invocation.get_sender()}:${ruleKey(pid, title)}`;
    const requests = this._requests;
    const epoch = requests.begin(requestKey);
    if (epoch === null) return this._reply(invocation, {ok: false, reason: 'request-limit'});
    try {
      const caller = await this._callerPid(invocation);
      if (this._disabled) return this._reply(invocation, {ok: false, reason: 'extension-disabled'});
      const invalid = validateRequest(caller.pid, pid, title, 0);
      if (invalid) return this._reply(invocation, invalid);
      if (this._requests !== requests || !requests.isCurrent(requestKey, epoch))
        return this._reply(invocation, {ok: false, reason: 'superseded'});
      const key = ruleKey(pid, title);
      if (!this._placementRules.has(key) && this._placementRules.size + this._placementStates.size >= MAX_RULES)
        return this._reply(invocation, {ok: false, reason: 'window-limit'});
      const previous = this._placementRules.get(key);
      if (previous?.timeout) GLib.Source.remove(previous.timeout);
      const rule = {pid, title, sender: caller.sender, target, timeout: 0};
      this._placementRules.set(key, rule);
      this._watchCaller(caller.sender);
      // Bounded by the authenticated caller's connection as well as a timeout.
      // Disk initialization may legitimately take longer on a first launch.
      this._armStartupTimeout(rule, 120000);
      this._reconcilePlacement();
      this._reply(invocation, {ok: true, mode: 'gnome-window-policy',
        reason: rule.result ?? 'waiting-window',
        monitor: monitor.index});
    } catch (_) {
      this._reply(invocation, {ok: false, reason: 'placement-unavailable'});
    } finally { requests.finish(requestKey, epoch); }
  }

  async TrackStartupResizeAsync([pid, title], invocation) {
    const rules = this._placementRules;
    try {
      const caller = await this._callerPid(invocation);
      const invalid = validateRequest(caller.pid, pid, title, 0);
      if (invalid) return this._reply(invocation, invalid);
      if (this._disabled || this._placementRules !== rules)
        return this._reply(invocation, {ok: false, reason: 'superseded'});
      const rule = rules.get(ruleKey(pid, title));
      if (!rule || rule.sender !== caller.sender)
        return this._reply(invocation, {ok: false, reason: 'no-startup-placement'});
      rule.follow = true;
      this._armStartupTimeout(rule, 20000);
      this._reply(invocation, {ok: true, reason: 'tracking-startup-resize'});
    } catch (_) { this._reply(invocation, {ok: false, reason: 'authorization-failed'}); }
  }

  async FinishStartupPlacementAsync([pid, title], invocation) {
    const rules = this._placementRules;
    try {
      const caller = await this._callerPid(invocation);
      const invalid = validateRequest(caller.pid, pid, title, 0);
      if (invalid) return this._reply(invocation, invalid);
      if (this._disabled || this._placementRules !== rules)
        return this._reply(invocation, {ok: false, reason: 'superseded'});
      // Source loaders may rename their own window. The retained state is tied
      // to that authenticated sender and exact MetaWindow, never a broad app ID.
      for (const [key, rule] of rules) {
        if (rule.pid !== pid || rule.sender !== caller.sender) continue;
        rules.delete(key);
        if (rule.timeout) GLib.Source.remove(rule.timeout);
      }
      for (const state of [...this._placementStates.values()])
        if (state.rule.pid === pid && state.rule.sender === caller.sender)
          this._removeStartupPlacement(state);
      this._pruneCallers();
      this._reply(invocation, {ok: true, reason: 'completed'});
    } catch (_) { this._reply(invocation, {ok: false, reason: 'authorization-failed'}); }
  }

  _armStartupTimeout(rule, milliseconds) {
    if (rule.timeout) GLib.Source.remove(rule.timeout);
    rule.timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, milliseconds, () => {
      const key = ruleKey(rule.pid, rule.title);
      if (this._placementRules.get(key) === rule) this._placementRules.delete(key);
      rule.timeout = 0;
      if (rule.state) this._removeStartupPlacement(rule.state);
      this._pruneCallers();
      return GLib.SOURCE_REMOVE;
    });
  }

  _removeStartupPlacement(state) {
    if (!this._placementStates.delete(state.window)) return;
    for (const [object, id] of state.signals) {
      try { object.disconnect(id); } catch (_) {}
    }
    state.signals = [];
    if (state.rule.timeout) GLib.Source.remove(state.rule.timeout);
    state.rule.timeout = 0;
    state.rule.state = null;
  }

  _centerStartupPlacement(window, rule, state = null) {
    const monitor = Main.layoutManager.monitors[rule.target.index];
    // A hot-unplugged target no longer has meaningful desktop coordinates.
    if (!monitor || monitor.x !== rule.target.x || monitor.y !== rule.target.y ||
        monitor.width !== rule.target.width || monitor.height !== rule.target.height)
      return false;
    const frame = window.get_frame_rect();
    if (frame.width < 1 || frame.height < 1) return false;
    const centered = centeredStartupFrame(rule.target, rule.target.workarea, frame.width, frame.height);
    if (state) {
      state.expected = centered;
      state.positioning = true;
    }
    try {
      if (!state || !state.placed) window.move_to_monitor(rule.target.index);
      if (frame.x !== centered.x || frame.y !== centered.y)
        window.move_frame(true, centered.x, centered.y);
      if (state) state.placed = true;
    } finally { if (state) state.positioning = false; }
    return true;
  }

  _reconcilePlacement() {
    if (this._disabled || !this._placementRules.size) return;
    for (const [key, rule] of [...this._placementRules]) {
      const windows = global.get_window_actors().map(actor => actor.get_meta_window())
        .filter(window => windowMatches(window, rule));
      if (windows.length !== 1) continue;
      const window = windows[0];
      if (this._placementStates.has(window)) continue;
      const frame = window.get_frame_rect();
      if (frame.width < 1 || frame.height < 1) continue;
      this._placementRules.delete(key); // Consume before move/restack signals.
      if (rule.follow) {
        const state = {window, rule, expected: null, positioning: false, placed: false, signals: []};
        rule.state = state;
        this._placementStates.set(window, state);
        state.signals.push([window, window.connect('size-changed', () => {
          if (!this._centerStartupPlacement(window, rule, state)) this._removeStartupPlacement(state);
          this._pruneCallers();
        })]);
        state.signals.push([window, window.connect('position-changed', () => {
          if (state.positioning || !state.expected) return;
          const current = window.get_frame_rect(), expected = state.expected;
          // A manual move takes precedence. Ignore intermediate resize events
          // until size-changed supplies the new authored loader dimensions.
          if (current.width === expected.width && current.height === expected.height &&
              (Math.abs(current.x - expected.x) > 1 || Math.abs(current.y - expected.y) > 1)) {
            this._removeStartupPlacement(state);
            this._pruneCallers();
          }
        })]);
        state.signals.push([window, window.connect('unmanaged', () => {
          this._removeStartupPlacement(state);
          this._pruneCallers();
        })]);
        if (!this._centerStartupPlacement(window, rule, state)) this._removeStartupPlacement(state);
      } else {
        if (rule.timeout) GLib.Source.remove(rule.timeout);
        rule.result = this._centerStartupPlacement(window, rule) ? 'centered' : 'monitor-unavailable';
      }
    }
    this._pruneCallers();
  }

  async SetAlwaysOnTopAsync([pid, title, enabled], invocation) {
    const invalidShape = validateRequest(pid, pid, title, 0);
    if (invalidShape) return this._reply(invocation, invalidShape);
    if (typeof enabled !== 'boolean')
      return this._reply(invocation, {ok: false, active: false, reason: 'invalid-topmost-switch'});
    const requestKey = `topmost:${invocation.get_sender()}:${ruleKey(pid, title)}`;
    const requests = this._requests;
    const epoch = requests.begin(requestKey);
    if (epoch === null) return this._reply(invocation, {ok: false, active: false, reason: 'request-limit'});
    try {
      const caller = await this._callerPid(invocation);
      if (this._disabled) return this._reply(invocation, {ok: false, active: false, reason: 'extension-disabled'});
      const invalid = validateRequest(caller.pid, pid, title, 0);
      if (invalid) return this._reply(invocation, invalid);
      if (this._requests !== requests || !requests.isCurrent(requestKey, epoch))
        return this._reply(invocation, {...this._topmostStatus(pid, title), reason: 'superseded'});
      const key = ruleKey(pid, title);
      if (enabled) {
        if (!this._topRules.has(key) && this._topRules.size >= MAX_RULES)
          return this._reply(invocation, {ok: false, active: false, reason: 'window-limit'});
        this._topRules.set(key, {pid, title, sender: caller.sender});
        this._watchCaller(caller.sender);
      } else this._topRules.delete(key);
      this._reconcileTopmost();
      this._pruneCallers();
      this._reply(invocation, this._topmostStatus(pid, title));
    } catch (error) {
      this._reply(invocation, {ok: false, active: false, reason: `authorization-failed: ${error.message ?? error}`});
    } finally { requests.finish(requestKey, epoch); }
  }

  async GetTopmostStatusAsync([pid, title], invocation) {
    try {
      const caller = await this._callerPid(invocation);
      const invalid = validateRequest(caller.pid, pid, title, 0);
      this._reply(invocation, invalid ?? this._topmostStatus(pid, title));
    } catch (_) { this._reply(invocation, {ok: false, active: false, reason: 'authorization-failed'}); }
  }

  _topmostStatus(pid, title) {
    const requested = this._topRules.has(ruleKey(pid, title));
    const windows = global.get_window_actors().map(actor => actor.get_meta_window())
      .filter(window => windowMatches(window, {pid, title}));
    const above = windows.length > 0 && windows.every(window => window.is_above());
    return {ok: true, active: requested && above, requested, above,
      windowCount: windows.length, mode: 'gnome-window-policy',
      reason: !requested ? 'disabled' : !windows.length ? 'waiting-window' : above ? 'active' : 'not-above'};
  }

  _watchCaller(sender) {
    if (this._callers.has(sender)) return;
    const id = Gio.bus_watch_name_on_connection(this._connection, sender,
      Gio.BusNameWatcherFlags.NONE, null, () => this._dropCaller(sender));
    this._callers.set(sender, id);
  }

  _reconcileTopmost() {
    if (this._disabled) return;
    for (const state of [...this._topStates.values()]) {
      const window = state.actor.get_meta_window();
      const rule = window && this._topRules.get(ruleKey(window.get_pid(), window.get_title()));
      if (!rule || !windowMatches(window, state.rule)) this._removeTopmost(state);
      else {
        state.rule = rule;
        if (!window.is_above()) window.make_above();
      }
    }
    if (!this._topRules.size) return;
    for (const actor of global.get_window_actors()) {
      if (this._topStates.has(actor)) continue;
      const window = actor.get_meta_window();
      const rule = window && this._topRules.get(ruleKey(window.get_pid(), window.get_title()));
      if (!rule) continue;
      const state = {actor, window, rule, originalAbove: window.is_above(), signals: []};
      this._topStates.set(actor, state);
      state.signals.push([actor, actor.connect('destroy', () => this._removeTopmost(state, true))]);
      state.signals.push([window, window.connect('notify::title', () => this._reconcileTopmost())]);
      state.signals.push([window, window.connect('notify::above', () => this._reconcileTopmost())]);
      if (!window.is_above()) window.make_above();
    }
  }

  _removeTopmost(state, windowDestroying = false) {
    if (!this._topStates.delete(state.actor)) return;
    for (const [object, id] of state.signals) {
      try { object.disconnect(id); } catch (_) {}
    }
    state.signals = [];
    if (!windowDestroying) {
      try {
        if (state.originalAbove && !state.window.is_above()) state.window.make_above();
        else if (!state.originalAbove && state.window.is_above()) state.window.unmake_above();
      } catch (_) {} // A window may have already been unmanaged by Mutter.
    }
  }

  async GetStatusAsync([pid, title], invocation) {
    try {
      const caller = await this._callerPid(invocation);
      const invalid = validateRequest(caller.pid, pid, title, 0);
      this._reply(invocation, invalid ?? this._status(pid, title));
    } catch (_) {
      this._reply(invocation, {ok: false, active: false, reason: 'authorization-failed'});
    }
  }

  _status(pid, title) {
    const enabled = this._rules.has(ruleKey(pid, title));
    const windowCount = [...this._states.values()].filter(s => windowMatches(s.actor.get_meta_window(), {pid, title})).length;
    return {ok: true, active: windowCount > 0, windowCount,
      reason: !enabled ? 'disabled' : windowCount ? 'active' : 'waiting-window'};
  }

  _pruneCallers() {
    for (const [sender, id] of this._callers) {
      if (![...this._rules.values(), ...this._topRules.values(), ...this._placementRules.values(), ...[...this._placementStates.values()].map(state => state.rule)].some(rule => rule.sender === sender)) {
        Gio.bus_unwatch_name(id);
        this._callers.delete(sender);
      }
    }
  }

  _dropCaller(sender) {
    for (const [key, rule] of this._rules) {
      if (rule.sender === sender) this._rules.delete(key);
    }
    for (const [key, rule] of this._topRules) {
      if (rule.sender === sender) this._topRules.delete(key);
    }
    for (const [key, rule] of this._placementRules) {
      if (rule.sender !== sender) continue;
      this._placementRules.delete(key);
      if (rule.timeout) GLib.Source.remove(rule.timeout);
    }
    for (const state of [...this._placementStates.values()])
      if (state.rule.sender === sender) this._removeStartupPlacement(state);
    this._reconcile();
    this._pruneCallers();
  }

  _reconcile() {
    if (this._disabled) return;
    this._reconcilePlacement();
    this._reconcileTopmost();
    for (const state of [...this._states.values()]) {
      const window = state.actor.get_meta_window();
      const rule = window && this._rules.get(ruleKey(window.get_pid(), window.get_title()));
      if (!rule) this._remove(state);
      else { state.rule = rule; }
    }
    if (!this._rules.size) return;
    for (const actor of global.get_window_actors()) {
      if (this._states.has(actor)) continue;
      const window = actor.get_meta_window();
      const rule = window && this._rules.get(ruleKey(window.get_pid(), window.get_title()));
      if (rule && actor.get_first_child() && actor.get_parent()) this._attach(actor, rule);
    }
  }

  _attach(actor, rule) {
    const glass = new BackdropGlass({extensionPath: this.path, owner: 'orion-desktop', logger: {log: () => {}, error: message => console.error(`Orion Glass: ${message}`)}});
    glass.set_name('orion-live-desktop-glass');
    glass.setPadding(0);
    glass.setCornerRadius(rule.radius);
    glass.setCornerSmoothingEnabled(false);
    glass.setShadowMaxRadius(0);
    this._applyOptics(glass);
    actor.insert_child_below(glass, actor.get_first_child());
    const state = {actor, glass, rule, signals: [], lastGeometry: '', lastRadius: null, frameLocal: null, previousPosition: null};
    this._states.set(actor, state);
    state.signals.push([actor, actor.connect('destroy', () => this._remove(state, true))]);
    const window = actor.get_meta_window();
    state.signals.push([window, window.connect('notify::title', () => this._reconcile())]);
    state.signals.push([window, window.connect('size-changed', () => { state.frameLocal = null; })]);
    this._sync(state);
  }

  _applyOptics(glass) {
    // Only the compositor backdrop is filtered. The native app foreground is
    // painted afterwards, keeping text and controls at their authored contrast.
    // Radius 3 is the first two-level Dual Kawase kernel. Dropping to 2.4
    // removes a whole blur level, so retain its schedule. The kernels are 5%
    // wider than .45/.675; fixed values avoid compounding on refresh.
    const blur = glass._renderer.blur;
    const sameFrost = blur._blurMethod === 1 && blur.passCount === 2 &&
      blur.radius === 3 && blur._blurRadiusDown === .4725 && blur._blurRadiusUp === .70875;
    if (!sameFrost) {
      glass.setBlurRadius(3);
      if (blur._blurMethod === 1 && blur.passCount === 2 && blur.radius === 3) {
        blur._blurRadiusDown = .4725;
        blur._blurRadiusUp = .70875;
        // The renderer's reuse key already includes both kernel offsets.
        blur._repaint();
      }
    }
    glass.setTintStrength(0);
    glass.setSurfaceLightEnabled(true);
    const optical = {
      max_z: 80, displacement_scale: 43.125, body_refraction_px: 34.5,
      profile_shape_n: 2, ior: 1.65,
      rim_width: 2.2, rim_intensity: .72, rim_directional_power: 2.2,
      rim_power: 3, rim_light_color_intensity: 1,
      light_angle_deg: 135, specular_intensity: 0, sheen_intensity: 0,
      shadow_intensity: 0, ao_intensity: .1, ao_radius: 1,
    };
    for (const [name, value] of Object.entries(optical))
      glass._renderer.uniforms.set(name, value);
  }

  _sync(state) {
    const {actor, glass, rule} = state;
    const window = actor.get_meta_window();
    if (!window || !windowMatches(window, rule)) { this._remove(state); return; }
    const workspace = window.get_workspace();
    if (!actor.get_stage() || !actor.mapped || window.minimized ||
        (workspace && !window.is_on_all_workspaces() &&
         workspace !== global.workspace_manager.get_active_workspace())) {
      if (glass.visible) glass.hide();
      state.lastGeometry = '';
      return;
    }
    const rect = window.get_frame_rect();
    const buffer = window.get_buffer_rect();
    if (rect.width < 1 || rect.height < 1) return;
    const stationary = state.previousPosition && state.previousPosition[0] === actor.x && state.previousPosition[1] === actor.y;
    state.previousPosition = [actor.x, actor.y];
    if (!state.frameLocal || stationary) state.frameLocal = [rect.x - buffer.x, rect.y - buffer.y];
    const effectiveRadius = window.is_fullscreen() || window.get_maximized() === 3 ? 0 : rule.radius;
    const signature = [rect.x, rect.y, rect.width, rect.height, effectiveRadius, ...state.frameLocal,
      actor.translation_x, actor.translation_y, actor.scale_x, actor.scale_y].join(':');
    const moved = signature !== state.lastGeometry;
    state.lastGeometry = signature;
    glass.beginBatch();
    try {
      if (!glass.visible) glass.show();
      if (state.lastRadius !== effectiveRadius) {
        state.lastRadius = effectiveRadius;
        glass.setCornerRadius(effectiveRadius);
      }
      if (moved) {
        glass.set_position(...state.frameLocal);
        glass.set_size(rect.width, rect.height);
        glass.setResolution(rect.width, rect.height);
        glass.setGlassGeometry(0, 0, rect.width, rect.height);
      }
      glass.syncSources(moved);
    } finally { glass.endBatch(); }
  }

  _remove(state, actorDestroying = false) {
    if (!this._states.delete(state.actor)) return;
    for (const [object, id] of state.signals) {
      try { object.disconnect(id); } catch (_) {}
    }
    state.signals = [];
    state.glass.cleanup();
    if (!actorDestroying) {
      try { state.glass.destroy(); } catch (_) {}
    }
  }
}
