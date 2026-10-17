// Orion-only control policy. No GNOME dependency, so authorization and input
// handling can be tested independently of the compositor.
export const MAX_RULES = 16;
export function validateRequest(callerPid, pid, title, radius) {
  if (!Number.isInteger(pid) || pid < 2 || callerPid !== pid)
    return {ok: false, active: false, reason: 'caller-pid-mismatch'};
  if (typeof title !== 'string' || !title.trim() || title.length > 256 || /[\x00-\x1f]/.test(title))
    return {ok: false, active: false, reason: 'invalid-window-title'};
  if (!Number.isFinite(radius) || radius < 0 || radius > 128)
    return {ok: false, active: false, reason: 'invalid-corner-radius'};
  return null;
}
export function ruleKey(pid, title) { return `${pid}:${title}`; }
export function windowMatches(window, rule) {
  return !!window && window.get_pid() === rule.pid && window.get_title() === rule.title;
}

// Reject an older authorization response after a newer Configure for the same
// window. Removing an old request must never erase the newer request's epoch.
export class RequestEpochs {
  constructor(limit = 64) { this.limit = limit; this.latest = new Map(); this.serial = 0; }
  begin(key) {
    if (!this.latest.has(key) && this.latest.size >= this.limit) return null;
    const epoch = ++this.serial; this.latest.set(key, epoch); return epoch;
  }
  isCurrent(key, epoch) { return this.latest.get(key) === epoch; }
  finish(key, epoch) { if (this.isCurrent(key, epoch)) this.latest.delete(key); }
  clear() { this.latest.clear(); }
}

// GNOME stage and GDK monitor coordinates are logical desktop pixels, including
// negative origins. Pick the display containing the pointer, not the focused
// window. In a layout gap the nearest display is the predictable fallback.
export function pointerMonitor(monitors, x, y) {
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  let nearest = null, distance = Infinity;
  for (const [index, monitor] of monitors.entries()) {
    if (![monitor.x, monitor.y, monitor.width, monitor.height].every(Number.isFinite) ||
        monitor.width <= 0 || monitor.height <= 0) continue;
    const inside = x >= monitor.x && y >= monitor.y &&
      x < monitor.x + monitor.width && y < monitor.y + monitor.height;
    const dx = Math.max(monitor.x - x, 0, x - monitor.x - monitor.width);
    const dy = Math.max(monitor.y - y, 0, y - monitor.y - monitor.height);
    const squared = dx * dx + dy * dy;
    if (inside || squared < distance) {
      nearest = {index: Number.isInteger(monitor.index) ? monitor.index : index,
        x: monitor.x, y: monitor.y, width: monitor.width, height: monitor.height};
      distance = squared;
      if (inside) break;
    }
  }
  return nearest;
}

export function centeredStartupFrame(monitor, workarea, width, height) {
  let x = Math.round(monitor.x + (monitor.width - width) / 2);
  let y = Math.round(monitor.y + (monitor.height - height) / 2);
  if (workarea?.width > 0 && workarea?.height > 0) {
    x = width <= workarea.width
      ? Math.max(workarea.x, Math.min(x, workarea.x + workarea.width - width))
      : workarea.x;
    y = height <= workarea.height
      ? Math.max(workarea.y, Math.min(y, workarea.y + workarea.height - height))
      : workarea.y;
  }
  return {x, y, width, height};
}
