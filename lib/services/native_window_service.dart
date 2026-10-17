import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// GTK retains an initial default size separately from its current allocation.
/// Keep both in sync when locking the size, so V3 cannot jump to that old size.
abstract final class NativeWindowService {
  static const _channel = MethodChannel('orion/window');
  static bool _followingStartupResize = false;

  /// Remember the monitor containing the pointer once, before loading settings.
  /// The compositor places the final chosen profile at that monitor's center.
  static Future<Map<String, Object?>> prepareStartupPlacement() =>
      _startupPlacement('prepareStartupPlacement');

  /// Apply the remembered logical monitor geometry after profile sizing. This
  /// runs before showing the window; Wayland placement is applied at mapping by
  /// Orion's authenticated compositor companion.
  static Future<Map<String, Object?>> applyStartupPlacement({
    bool followInitialResize = false,
  }) async {
    final result = await _startupPlacement('applyStartupPlacement', {
      'followInitialResize': followInitialResize,
    });
    _followingStartupResize = followInitialResize && result['ok'] == true;
    return result;
  }

  /// Stop following a source loader's authored resize sequence. Calling this
  /// later from a replay or another UI has no effect on normal window moves.
  static Future<Map<String, Object?>> completeStartupPlacement() async {
    if (!_followingStartupResize) return {'ok': true, 'reason': 'completed'};
    _followingStartupResize = false;
    return _startupPlacement('completeStartupPlacement');
  }

  static Future<Map<String, Object?>> _startupPlacement(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!Platform.isLinux && !Platform.isWindows) {
      return {'ok': false, 'reason': 'unsupported-platform'};
    }
    try {
      final response = await _channel.invokeMethod<String>(method, arguments);
      if (response != null) {
        final decoded = jsonDecode(response);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      }
    } on MissingPluginException {
      return {'ok': false, 'reason': 'native-placement-unavailable'};
    } on PlatformException {
      return {'ok': false, 'reason': 'native-placement-unavailable'};
    } on FormatException {
      // A placement failure must not prevent opening the application.
    }
    return {'ok': false, 'reason': 'invalid-native-placement-response'};
  }

  static Future<void> destroyCompanion() =>
      _channel.invokeMethod<void>('destroyCompanion');

  static Future<void> registerWindow(
    String id, {
    String? parentId,
    bool owned = false,
    bool modal = false,
  }) => _channel.invokeMethod<void>('registerWindow', {
    'id': id,
    'parentId': parentId,
    'owned': owned,
    'modal': modal,
  });

  /// Request topmost through GTK/X11 or Orion's authenticated GNOME helper.
  /// The plugin retains the requested hint; [above] in the returned native
  /// metadata reports the compositor's actual state rather than that cache.
  static Future<Map<String, Object?>> setAlwaysOnTop(bool value) async {
    await windowManager.setAlwaysOnTop(value);
    if (!Platform.isLinux) {
      return {'ok': true, 'requested': value, 'mode': 'platform-hint'};
    }
    try {
      final response = await _channel.invokeMethod<String>('setAlwaysOnTop', {
        'enabled': value,
      });
      if (response != null) {
        final decoded = jsonDecode(response);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      }
    } on MissingPluginException {
      return {
        'ok': false,
        'active': false,
        'requested': value,
        'reason': 'native-window-policy-unavailable',
      };
    } on FormatException {
      // A failed control reply must never become a cached success indication.
    }
    return {
      'ok': false,
      'active': false,
      'requested': value,
      'reason': 'invalid-native-window-policy-response',
    };
  }

  /// Match the desktop input region to Flutter's transparent curved corners.
  /// GTK uses square edges while maximized or fullscreen and restores this
  /// radius on returning to a normal window.
  static Future<void> setCornerRadius(double radius) async {
    if (!radius.isFinite || radius < 0 || radius > 64) {
      throw ArgumentError.value(radius, 'radius', 'Expected 0 to 64 pixels.');
    }
    if (Platform.isLinux || Platform.isWindows) {
      await _channel.invokeMethod<void>('setCornerRadius', {'radius': radius});
    }
  }

  /// Keep the plugin's compositor hints and GTK's internal minimum in sync.
  /// GTK otherwise overwrites the plugin hints while changing source profiles.
  static Future<void> setMinimumSize(Size size) async {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width < 1 ||
        size.height < 1 ||
        size.width > 16384 ||
        size.height > 16384) {
      throw ArgumentError.value(
        size,
        'size',
        'Expected a finite positive minimum size.',
      );
    }
    await windowManager.setMinimumSize(size);
    if (Platform.isLinux) {
      await _channel.invokeMethod<void>('setMinimumSize', {
        'width': size.width,
        'height': size.height,
      });
    }
  }

  static Future<void> setResizable(bool value, {Size? size}) async {
    if (Platform.isLinux) {
      await _channel.invokeMethod<void>('setResizable', {
        'resizable': value,
        if (size != null) 'width': size.width,
        if (size != null) 'height': size.height,
      });
      return;
    }
    if (size != null) await windowManager.setSize(size);
    await windowManager.setResizable(value);
  }
}
