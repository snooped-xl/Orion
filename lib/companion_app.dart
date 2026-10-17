import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models/companion_window.dart';
import 'models/companion_window_profile.dart';
import 'models/interface_preset.dart';
import 'original_ports/krnl_shell.dart';
import 'original_ports/xeno_shell.dart';
import 'services/companion_controller.dart';
import 'services/monaco_editor_service.dart';
import 'services/native_window_service.dart';
import 'synapse_og/synapse_og_shell.dart';
import 'synapse_x/synapse_x_shell.dart';
import 'synapse_v3/v3_undocked_editor.dart';
import 'theme/orion_theme.dart';
import 'widgets/ui_scale_viewport.dart';
import 'widgets/desktop_frame.dart';
import 'widgets/orion_glass.dart';
import 'widgets/native_desktop_glass.dart';
import 'screens/synapse_theme_studio.dart';
import 'services/synapse_theme_catalog.dart';

Future<void> runCompanionWindow(
  WindowController window,
  Map<String, Object?> arguments,
) async {
  final host = _ChildWindowHost(window, arguments);
  final c = CompanionController(
    initialState: Map<String, Object?>.from(arguments['state'] as Map),
    documentId: arguments['documentId'] as String?,
    sendCommand: (operation, payload, sequence) async =>
        Map<String, Object?>.from(
          (await host.request('command', {
                'operation': operation,
                'payload': payload,
                'sequence': sequence,
              }))
              as Map,
        ),
  );
  c.companionWindows = host;
  host.controller = c;
  await host.initialize();
  runApp(_CompanionApp(host: host));
}

class _ChildWindowHost extends WindowListener implements CompanionWindowHost {
  _ChildWindowHost(this.window, this.arguments)
    : kind = CompanionWindowKind.values.byName(arguments['kind'] as String),
      documentId = arguments['documentId'] as String?,
      parent = WindowController.fromWindowId(arguments['parentId'] as String);
  final WindowController window, parent;
  final Map<String, Object?> arguments;
  late final CompanionController controller;
  MonacoEditorService? editor;
  @override
  final CompanionWindowKind kind;
  @override
  final String? documentId;
  @override
  bool get isChildWindow => true;
  bool _closing = false;
  bool _destroying = false;
  bool? _lastTop, _lastResizable;
  Future<void>? _closeFuture;
  Future<bool> Function()? confirmClose;
  Future<void> Function()? beforeOwnerClose;
  String? _lastWindowSize;
  CompanionWindowProfile get profile {
    final original = CompanionWindowProfile.forKind(kind);
    final target = switch (kind) {
      CompanionWindowKind.synapseXOptions => (
        InterfacePreset.synapseX,
        'settings',
      ),
      CompanionWindowKind.synapseXHub => (
        InterfacePreset.synapseX,
        'scriptHub',
      ),
      CompanionWindowKind.synapseXConsole => (
        InterfacePreset.synapseX,
        'console',
      ),
      CompanionWindowKind.synapseOgSettings => (
        InterfacePreset.synapse2017,
        'settings',
      ),
      CompanionWindowKind.synapseOgHub => (
        InterfacePreset.synapse2017,
        'scriptHub',
      ),
      CompanionWindowKind.synapseOgConsole => (
        InterfacePreset.synapse2017,
        'console',
      ),
      CompanionWindowKind.synapseV3Editor => (
        InterfacePreset.synapseV3,
        'undockedEditor',
      ),
      _ => null,
    };
    if (target == null) return original;
    final custom = SynapseThemeCatalog.current(
      controller,
      target.$1,
    ).window(target.$2);
    if (custom.width == null && custom.height == null) return original;
    final minimum = SynapseThemeCatalog.windows(
      target.$1,
    ).firstWhere((descriptor) => descriptor.id == target.$2).minimumSize;
    return CompanionWindowProfile(
      original.title,
      Size(
        (custom.width ?? original.size.width).clamp(minimum.width, 4096),
        (custom.height ?? original.size.height).clamp(minimum.height, 2160),
      ),
      minimumSize: minimum,
      resizable: original.resizable,
      owned: original.owned,
      modal: original.modal,
      skipTaskbar: original.skipTaskbar,
      cornerRadius: original.cornerRadius,
    );
  }

  Future<Object?> request(
    String method, [
    Map<String, Object?> args = const {},
  ]) => parent.invokeMethod<Object?>(method, {
    'key': arguments['key'],
    'windowId': window.windowId,
    ...args,
  });

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    final minimum = profile.minimumSize ?? profile.size;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: profile.size,
        minimumSize: minimum,
        maximumSize: profile.resizable ? null : profile.size,
        center: kind != CompanionWindowKind.krnlOptions,
        title: profile.title,
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Colors.transparent,
        skipTaskbar: profile.skipTaskbar,
      ),
    );
    await NativeWindowService.registerWindow(
      window.windowId,
      parentId: parent.windowId,
      owned: profile.owned,
      modal: profile.modal,
    );
    await NativeWindowService.setMinimumSize(minimum);
    await NativeWindowService.setResizable(
      profile.resizable,
      size: profile.size,
    );
    await _syncWindowFlags();
    await windowManager.setPreventClose(true);
    if (kind == CompanionWindowKind.krnlOptions) {
      final anchor = Map<String, Object?>.from(arguments['anchor'] as Map);
      await windowManager.setPosition(
        Offset(
          (anchor['x'] as num).toDouble() +
              ((anchor['width'] as num) - profile.size.width) / 2,
          (anchor['y'] as num).toDouble() +
              ((anchor['height'] as num) - profile.size.height) / 2,
        ),
      );
    }
    windowManager.addListener(this);
    await window.setWindowMethodHandler(_handle);
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'state':
        controller.acceptEnvelope(
          Map<String, Object?>.from(call.arguments as Map),
        );
        await _syncWindowFlags();
      case 'focus':
        await windowManager.show();
        if (await windowManager.isMinimized()) await windowManager.restore();
        await windowManager.focus();
      case 'hide':
        await editor?.flush();
        await controller.flushCommands();
        await windowManager.hide();
      case 'closeFromOwner':
        await beforeOwnerClose?.call();
        await _prepareClose();
        // Complete the native IPC response before GTK tears down this engine.
        if (!_destroying) {
          _destroying = true;
          Timer(
            const Duration(milliseconds: 40),
            NativeWindowService.destroyCompanion,
          );
        }
      default:
        throw MissingPluginException('Unknown owner request ${call.method}');
    }
    return null;
  }

  Future<void> _syncWindowFlags() async {
    final prefs = controller.getInterfacePreferences(
      controller.selectedInterface,
    );
    final v3 = kind == CompanionWindowKind.synapseV3Editor;
    final top = kind.isThemeStudio
        ? false
        : v3
        ? controller.synapsePreferences.alwaysOnTop
        : prefs['alwaysOnTop'] == true;
    final resize =
        kind.isThemeStudio ||
        v3 ||
        (profile.resizable && (prefs['resizable'] as bool? ?? false));
    if (_lastTop != top) {
      _lastTop = top;
      await NativeWindowService.setAlwaysOnTop(top);
    }
    if (_lastResizable != resize) {
      _lastResizable = resize;
      await NativeWindowService.setResizable(resize);
    }
    final size = profile.size;
    final signature = '${size.width}:${size.height}';
    if (!kind.isThemeStudio &&
        _lastWindowSize != null &&
        _lastWindowSize != signature) {
      await windowManager.setResizable(true);
      await windowManager.setSize(size);
      await NativeWindowService.setResizable(resize, size: size);
    }
    _lastWindowSize = signature;
  }

  Future<void> ready() async {
    final envelope = await request('ready');
    controller.acceptEnvelope(Map<String, Object?>.from(envelope as Map));
  }

  Future<void> _prepareClose() => _closeFuture ??= () async {
    if (_closing) return;
    _closing = true;
    try {
      await editor?.flush();
      await controller.flushCommands();
      await request('closed');
    } catch (_) {
      _closing = false;
      _closeFuture = null;
      rethrow;
    }
  }();

  @override
  void onWindowClose() => unawaited(close());
  @override
  Future<void> close() async {
    if (!_closing && !(await confirmClose?.call() ?? true)) return;
    await _prepareClose();
    if (!_destroying) {
      _destroying = true;
      await NativeWindowService.destroyCompanion();
    }
  }

  @override
  Future<void> closeAll() => close();
  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) async {
    await editor?.flush();
    await controller.flushCommands();
    await request('open', {'kind': kind.name, 'documentId': documentId});
  }

  @override
  Future<void> focusMain() async {
    await request('focusMain');
  }

  Future<void> selectInterface(InterfacePreset preset) async {
    await editor?.flush();
    await controller.flushCommands();
    await request('switchInterface', {'preset': preset.name});
  }

  @override
  Future<void> returnToOrion() => selectInterface(InterfacePreset.orion);
  @override
  Future<void> updateOwnerWindow({
    bool? alwaysOnTop,
    bool? resizable,
    double? opacity,
  }) async {
    await request('updateOwnerWindow', {
      'alwaysOnTop': ?alwaysOnTop,
      'resizable': ?resizable,
      'opacity': ?opacity,
    });
  }
}

class _CompanionApp extends StatefulWidget {
  const _CompanionApp({required this.host});
  final _ChildWindowHost host;
  @override
  State<_CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<_CompanionApp> {
  final _undockedKey = GlobalKey<V3UndockedEditorState>();
  final _studioKey = GlobalKey<SynapseThemeStudioScreenState>();
  _ChildWindowHost get host => widget.host;
  CompanionController get c => host.controller;
  double? _studioOpacity;
  bool _nativeGlassActive = false;

  void _syncStudioOpacity() {
    if (!host.kind.isThemeStudio) return;
    final opacity = _nativeGlassActive
        ? 1.0
        : c.orionTheme.liquidGlassEnabled
        ? c.orionTheme.windowOpacity
        : 1.0;
    if (_studioOpacity == opacity) return;
    _studioOpacity = opacity;
    // This independent window has no NativeRainViewport opacity writer.
    unawaited(windowManager.setOpacity(opacity).catchError((Object _) {}));
  }

  @override
  void initState() {
    super.initState();
    if (host.kind.isThemeStudio) {
      c.addListener(_syncStudioOpacity);
      _syncStudioOpacity();
      host.confirmClose = () async =>
          await _studioKey.currentState?.confirmClose() ?? true;
      host.beforeOwnerClose = () async =>
          await _studioKey.currentState?.preserveDraft();
    }
    if (host.kind == CompanionWindowKind.synapseV3Editor) {
      host.editor = MonacoEditorService(
        onChange: c.updateDocumentContent,
        onShortcut: (shortcut) =>
            _undockedKey.currentState?.handleEditorShortcut(shortcut),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(host.ready()),
    );
  }

  @override
  void dispose() {
    if (host.kind.isThemeStudio) c.removeListener(_syncStudioOpacity);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (_, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: orionTheme(
        host.kind.isThemeStudio && c.orionTheme.liquidGlassEnabled
            ? Brightness.light
            : Brightness.dark,
        c.accentColor,
        reducedMotion: c.reducedMotion,
        preferences: host.kind.isThemeStudio && c.orionTheme.liquidGlassEnabled
            ? c.orionTheme
            : null,
      ),
      darkTheme: host.kind.isThemeStudio && c.orionTheme.liquidGlassEnabled
          ? orionTheme(
              Brightness.dark,
              c.orionTheme.accent,
              preferences: c.orionTheme,
              reducedMotion: c.reducedMotion,
            )
          : null,
      themeMode: host.kind.isThemeStudio && c.orionTheme.liquidGlassEnabled
          ? c.orionTheme.themeMode
          : ThemeMode.system,
      builder: (context, child) {
        final content = UiScaleViewport(scale: c.uiScale, child: child!);
        if (!host.kind.isThemeStudio) return content;
        return NativeDesktopGlassViewport(
          supported: true,
          enabled:
              OrionColors.of(context).glassEnabled &&
              c.orionTheme.windowOpacity < 1,
          opacity: c.orionTheme.windowOpacity,
          cornerRadius: host.profile.cornerRadius,
          onActiveChanged: (active) {
            _nativeGlassActive = active;
            _syncStudioOpacity();
          },
          builder: (context, _) => DesktopFrame(
            enabled: true,
            reducedMotion: c.reducedMotion,
            cornerRadius: host.profile.cornerRadius,
            borderColor: OrionColors.of(context).glassEnabled
                ? Colors.transparent
                : null,
            syncNativeCorners: true,
            child: OrionGlassScene(
              enabled: OrionColors.of(context).glassEnabled,
              reducedMotion: c.reducedMotion,
              backdrop: OrionGlassBackdrop(
                tint: OrionColors.of(context).background,
                authoredGradient: OrionColors.of(context).backgroundGradient,
                useAuthoredBackground: true,
              ),
              child: OrionGlassSurface(
                radius: host.profile.cornerRadius,
                blur: 0,
                tint: Colors.transparent,
                child: content,
              ),
            ),
          ),
        );
      },
      home: Material(
        type: MaterialType.transparency,
        child: switch (host.kind) {
          CompanionWindowKind.krnlOptions => KrnlShell(
            controller: c,
            bridgeReady: c.bridgeConnected,
            nativeWindow: true,
            onBackToOrion: host.returnToOrion,
            onSelectInterface: host.selectInterface,
          ),
          CompanionWindowKind.xenoSettings ||
          CompanionWindowKind.xenoScripts ||
          CompanionWindowKind.xenoClients => XenoShell(
            controller: c,
            bridgeReady: c.bridgeConnected,
            nativeWindow: true,
            onBackToOrion: host.returnToOrion,
            onSelectInterface: host.selectInterface,
          ),
          CompanionWindowKind.synapseXOptions ||
          CompanionWindowKind.synapseXHub ||
          CompanionWindowKind.synapseXConsole => SynapseXShell(
            controller: c,
            bridgeReady: c.bridgeConnected,
            nativeWindow: true,
            playIntro: false,
            onBackToOrion: host.returnToOrion,
            onSelectInterface: host.selectInterface,
          ),
          CompanionWindowKind.synapseOgSettings ||
          CompanionWindowKind.synapseOgHub ||
          CompanionWindowKind.synapseOgConsole => SynapseOgShell(
            controller: c,
            bridgeReady: c.bridgeConnected,
            nativeWindow: true,
            playIntro: false,
            onBackToOrion: host.returnToOrion,
            onSelectInterface: host.selectInterface,
          ),
          CompanionWindowKind.synapseV3Editor => V3UndockedEditor(
            key: _undockedKey,
            controller: c,
            bridgeReady: c.bridgeConnected,
            nativeWindow: true,
            editorService: host.editor,
          ),
          CompanionWindowKind.orionThemeStudio ||
          CompanionWindowKind.synapseV3ThemeStudio ||
          CompanionWindowKind.synapseBlueThemeStudio ||
          CompanionWindowKind.synapseXThemeStudio ||
          CompanionWindowKind.synapseOgThemeStudio => SynapseThemeStudioScreen(
            key: _studioKey,
            controller: c,
            preset: host.kind.themeStudioPreset!,
            nativeWindow: true,
            onClose: host.close,
          ),
        },
      ),
    ),
  );
}
