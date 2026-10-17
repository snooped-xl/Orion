import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/companion_window.dart';
import '../models/interface_preset.dart';
import '../state/orion_controller.dart';
import 'companion_commands.dart';
import 'native_window_service.dart';

/// The primary engine owns documents, preferences and disk persistence. Native
/// companion engines receive snapshots and send ordered, acknowledged commands.
class CompanionWindowService implements CompanionWindowHost {
  CompanionWindowService(this.controller, this.window)
    : _commands = CompanionCommands(controller);

  final OrionController controller;
  final WindowController window;
  final CompanionCommands _commands;
  final _entries = <String, _CompanionEntry>{};
  StreamSubscription<void>? _windowsSubscription;
  Timer? _broadcastTimer;
  Future<void> _lifetime = Future<void>.value();
  int _revision = 0;
  bool _closingAll = false;
  bool _shuttingDown = false;
  bool _disposed = false;
  int _openGeneration = 0, _pendingCloseRequests = 0;
  bool acceptsOpens = true;
  Future<void> Function(InterfacePreset)? onSelectInterface;
  Future<void> Function()? flushEditor;

  @override
  bool get isChildWindow => false;
  @override
  CompanionWindowKind? get kind => null;
  @override
  String? get documentId => null;

  Future<void> initialize() async {
    await NativeWindowService.registerWindow(window.windowId);
    await window.setWindowMethodHandler(_handle);
    controller.companionWindows = this;
    controller.addListener(_changed);
    _windowsSubscription = onWindowsChanged.listen((_) => _checkWindows());
  }

  void _changed() {
    _revision++;
    _broadcastTimer ??= Timer(const Duration(milliseconds: 16), () {
      _broadcastTimer = null;
      for (final entry in _entries.values.toList()) {
        if (!entry.ready.isCompleted || entry.window == null) continue;
        unawaited(
          entry.window!
              .invokeMethod<void>('state', _envelope(entry))
              .catchError((Object _) {}),
        );
      }
    });
  }

  Map<String, Object?> _envelope(_CompanionEntry entry) => {
    'state': controller.exportWindowState(),
    'ack': entry.ack,
    'revision': _revision,
  };

  Future<void> _queue(Future<void> Function() action) {
    final result = _lifetime.then((_) => action());
    _lifetime = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) {
    if (!acceptsOpens || _pendingCloseRequests > 0) return Future<void>.value();
    final generation = _openGeneration;
    return _queue(() async {
      if (generation != _openGeneration || !acceptsOpens) return;
      await _open(kind, documentId, generation);
    });
  }

  Future<void> _open(
    CompanionWindowKind kind,
    String? documentId,
    int generation,
  ) async {
    if (_disposed) return;
    await flushEditor?.call();
    final key = '${kind.name}:${documentId ?? ''}';
    final previous = _entries[key];
    if (previous != null) {
      await previous.ready.future;
      if (kind == CompanionWindowKind.xenoScripts) {
        await _closeEntry(previous);
      } else if (kind == CompanionWindowKind.xenoClients && previous.visible) {
        await previous.window!.invokeMethod<void>('hide');
        previous.visible = false;
      } else {
        await previous.window!.invokeMethod<void>('focus');
        previous.visible = true;
      }
      return;
    }
    if (kind == CompanionWindowKind.synapseV3Editor &&
        !controller.documents.any((d) => d.id == documentId)) {
      return;
    }
    final anchor = await windowManager.getBounds();
    final entry = _CompanionEntry(key, kind, documentId);
    _entries[key] = entry;
    try {
      final child = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': 'orion-companion',
            'kind': kind.name,
            'parentId': window.windowId,
            'key': key,
            'documentId': documentId,
            'state': {
              ...controller.exportWindowState(),
              // Branding is large and stays out of recurring state broadcasts.
              // Studios receive it once for their switchable source previews.
              if (kind.isThemeStudio)
                'customLogo': controller.customLogoBytes == null
                    ? null
                    : base64Encode(controller.customLogoBytes!),
            },
            'anchor': {
              'x': anchor.left,
              'y': anchor.top,
              'width': anchor.width,
              'height': anchor.height,
            },
          }),
        ),
      );
      entry.window = child;
      await entry.ready.future.timeout(const Duration(seconds: 20));
      if (generation != _openGeneration || !acceptsOpens) return;
      if (kind == CompanionWindowKind.synapseV3Editor) {
        controller.setDocumentDetached(documentId!, true);
        if (controller.activeDocumentId == documentId) {
          final available = controller.documents.where(
            (d) => !controller.detachedDocumentIds.contains(d.id),
          );
          if (available.isEmpty) {
            controller.newDocument(
              content: controller.synapsePreferences.defaultTabContent,
            );
          } else {
            controller.selectDocument(available.last.id);
          }
        }
      }
      await child.invokeMethod<void>('state', _envelope(entry));
      await child.invokeMethod<void>('focus');
      if (kind == CompanionWindowKind.xenoSettings) await windowManager.hide();
    } catch (_) {
      try {
        await entry.window
            ?.invokeMethod<void>('closeFromOwner')
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // A child that never reached its first frame cannot have accepted
        // user input. Destroy its native allocation even if Dart never ran.
        if (entry.window != null) {
          await const MethodChannel(
            'mixin.one/desktop_multi_window',
          ).invokeMethod<void>('window_destroy', {
            'windowId': entry.window!.windowId,
          });
        }
      } finally {
        await _removed(entry);
      }
      rethrow;
    }
  }

  _CompanionEntry _entry(Map<String, Object?> args) {
    final entry = _entries[args['key']];
    if (entry == null) throw StateError('This companion has closed.');
    return entry;
  }

  Future<Object?> _handle(MethodCall call) async {
    final args = Map<String, Object?>.from(call.arguments as Map? ?? {});
    switch (call.method) {
      case 'ready':
        final entry = _entry(args);
        entry.window ??= WindowController.fromWindowId(
          args['windowId'] as String,
        );
        if (!entry.ready.isCompleted) entry.ready.complete();
        return _envelope(entry);
      case 'command':
        final entry = _entry(args);
        final sequence = args['sequence'] as int;
        // A transport retry may follow a committed response whose window was
        // briefly busy. Never run the same execute/toggle/file operation twice.
        return entry.serialize(() async {
          Object? result;
          if (sequence > entry.ack) {
            if (sequence != entry.ack + 1) {
              throw StateError('Out-of-order command.');
            }
            result = await _commands.apply(
              args['operation'] as String,
              Map<String, Object?>.from(args['payload'] as Map),
            );
            entry.ack = sequence;
            entry.lastResult = result;
            _changed();
          } else {
            result = entry.lastResult;
          }
          return {'envelope': _envelope(entry), 'result': result};
        });
      case 'closed':
        final entry = _entries[args['key']];
        if (entry != null) await _removed(entry);
      case 'open':
        _entry(args);
        // Reply before an owned modal window steals input from its caller.
        unawaited(
          open(
            CompanionWindowKind.values.byName(args['kind'] as String),
            documentId: args['documentId'] as String?,
          ),
        );
      case 'focusMain':
        await focusMain();
      case 'switchInterface':
        // The caller is destroyed by closeAll. Do not keep its IPC result
        // pending while waiting for that same child to acknowledge closing.
        scheduleMicrotask(() async {
          await closeAll();
          await onSelectInterface?.call(
            InterfacePreset.values.byName(args['preset'] as String),
          );
        });
      case 'updateOwnerWindow':
        await updateOwnerWindow(
          alwaysOnTop: args['alwaysOnTop'] as bool?,
          resizable: args['resizable'] as bool?,
          opacity: (args['opacity'] as num?)?.toDouble(),
        );
      default:
        throw MissingPluginException(
          'Unknown companion request ${call.method}',
        );
    }
    return null;
  }

  Future<void> _checkWindows() async {
    if (_disposed) return;
    final windows = await WindowController.getAll();
    final ids = windows.map((w) => w.windowId).toSet();
    for (final entry in _entries.values.toList()) {
      if (entry.window == null || !entry.ready.isCompleted) continue;
      if (!ids.contains(entry.window!.windowId)) await _removed(entry);
    }
  }

  Future<void> _removed(_CompanionEntry entry) async {
    if (!identical(_entries[entry.key], entry)) return;
    _entries.remove(entry.key);
    if (entry.documentId != null) {
      controller.setDocumentDetached(entry.documentId!, false);
      if (!_closingAll &&
          controller.documents.any((d) => d.id == entry.documentId)) {
        controller.selectDocument(entry.documentId!);
      }
    }
    if (!_closingAll &&
        (entry.kind == CompanionWindowKind.xenoSettings ||
            entry.kind == CompanionWindowKind.synapseV3Editor)) {
      await focusMain();
    }
  }

  Future<void> _closeEntry(_CompanionEntry entry) async {
    try {
      await entry.ready.future.timeout(const Duration(seconds: 20));
      await entry.window?.invokeMethod<void>('closeFromOwner');
    } on PlatformException {
      if (await _stillExists(entry)) rethrow;
    } on MissingPluginException {
      if (await _stillExists(entry)) rethrow;
    } on WindowChannelException {
      if (await _stillExists(entry)) rethrow;
    }
    await _removed(entry);
  }

  Future<bool> _stillExists(_CompanionEntry entry) async =>
      (await WindowController.getAll()).any(
        (window) => window.windowId == entry.window?.windowId,
      );

  @override
  Future<void> closeAll() {
    ++_openGeneration;
    ++_pendingCloseRequests;
    return _queue(() async {
      _closingAll = true;
      try {
        final hiddenMain = _entries.values.any(
          (entry) => entry.kind == CompanionWindowKind.xenoSettings,
        );
        for (final entry in _entries.values.toList()) {
          await _closeEntry(entry);
        }
        if (hiddenMain) await focusMain();
      } finally {
        _closingAll = false;
      }
    }).whenComplete(() => --_pendingCloseRequests);
  }

  @override
  Future<void> close() => closeAll();

  /// Hide every companion before waiting for its editor or queued commands.
  /// Keep the engines alive so their final updates reach the owner before save.
  Future<void> shutdown() async {
    _shuttingDown = true;
    acceptsOpens = false;
    ++_openGeneration;
    await Future.wait([
      for (final entry in _entries.values.toList())
        if (entry.window != null)
          entry.window!
              .invokeMethod<void>('hideForShutdown')
              .timeout(const Duration(seconds: 1))
              .catchError((Object _) {}),
    ]);
    await closeAll();
  }

  Future<void> cancelShutdown() async {
    _shuttingDown = false;
    acceptsOpens = true;
    for (final entry in _entries.values.toList()) {
      if (entry.window == null || !entry.visible) continue;
      await entry.window!
          .invokeMethod<void>('focus')
          .timeout(const Duration(seconds: 1))
          .catchError((Object _) {});
    }
  }

  @override
  Future<void> focusMain() async {
    if (_shuttingDown) return;
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  @override
  Future<void> returnToOrion() async {
    await closeAll();
    await onSelectInterface?.call(InterfacePreset.orion);
  }

  @override
  Future<void> updateOwnerWindow({
    bool? alwaysOnTop,
    bool? resizable,
    double? opacity,
  }) async {
    if (alwaysOnTop != null) {
      await NativeWindowService.setAlwaysOnTop(alwaysOnTop);
    }
    if (resizable != null) await NativeWindowService.setResizable(resizable);
    if (opacity != null) {
      await windowManager.setOpacity(opacity.clamp(0.1, 1.0));
    }
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_changed);
    _broadcastTimer?.cancel();
    unawaited(_windowsSubscription?.cancel());
  }
}

class _CompanionEntry {
  _CompanionEntry(this.key, this.kind, this.documentId);
  final String key;
  final CompanionWindowKind kind;
  final String? documentId;
  final ready = Completer<void>();
  WindowController? window;
  bool visible = true;
  int ack = 0;
  Object? lastResult;
  Future<Object?> _commands = Future<Object?>.value();

  Future<Object?> serialize(Future<Object?> Function() command) {
    final result = _commands.then((_) => command());
    _commands = result.catchError((Object _) => null);
    return result;
  }
}
