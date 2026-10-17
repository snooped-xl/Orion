import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'state/orion_controller.dart';
import 'theme/orion_theme.dart';
import 'theme/expressive_motion.dart';
import 'theme/orion_density.dart';
import 'widgets/common.dart';
import 'widgets/orion_logo.dart';
import 'widgets/desktop_frame.dart';
import 'widgets/orion_overlay.dart';
import 'widgets/native_rain_viewport.dart';
import 'widgets/native_desktop_glass.dart';
import 'widgets/ui_scale_viewport.dart';
import 'widgets/orion_studio_layer.dart';
import 'widgets/orion_glass.dart';
import 'widgets/synapse_theme_surface.dart';
import 'models/interface_preset.dart';
import 'models/interface_window_profile.dart';
import 'services/monaco_editor_service.dart';
import 'services/companion_window_service.dart';
import 'services/native_window_service.dart';
import 'services/desktop_launcher.dart';
import 'services/desktop_close_service.dart';
import 'services/window_morph_service.dart';
import 'services/synapse_theme_catalog.dart';
import 'services/synapse_theme_studio_service.dart';
import 'synapse_v3/synapse_v3_shell.dart';
import 'synapse_v3/v3_entrance.dart';
import 'synapse_blue/synapse_blue_shell.dart';
import 'synapse_x/synapse_x_shell.dart';
import 'synapse_og/synapse_og_shell.dart';
import 'original_ports/awp_shell.dart';
import 'original_ports/xeno_shell.dart';
import 'original_ports/krnl_shell.dart';
import 'original_ports/calamari_shell.dart';
import 'original_ports/zenith_shell.dart';
import 'screens/workspace_screen.dart';
import 'screens/library_screen.dart';
import 'screens/ui_selection_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/theme_control_screen.dart';
import 'theme/orion_surfaces.dart';
import 'screens/intro_screen.dart';
import 'screens/onboarding_screen.dart';
import 'widgets/orion_startup_reveal.dart';
import 'widgets/selected_builder.dart';
import 'widgets/retained_page.dart';

class OrionApp extends StatefulWidget {
  final OrionController controller;
  final bool nativeWindow;
  final bool showcase;
  const OrionApp({
    super.key,
    required this.controller,
    this.nativeWindow = true,
    this.showcase = false,
  });
  @override
  State<OrionApp> createState() => _OrionAppState();
}

class _OrionAppState extends State<OrionApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _shellKey = GlobalKey<_OrionShellState>();
  final _synapseKey = GlobalKey<SynapseV3ShellState>();
  final _blueKey = GlobalKey<SynapseBlueShellState>();
  final _xKey = GlobalKey<SynapseXShellState>();
  final _ogKey = GlobalKey<SynapseOgShellState>();
  final _awpKey = GlobalKey<AwpShellState>();
  final _xenoKey = GlobalKey<XenoShellState>();
  final _krnlKey = GlobalKey<KrnlShellState>();
  final _calamariKey = GlobalKey<CalamariShellState>();
  final _zenithKey = GlobalKey<ZenithShellState>();
  MonacoEditorService? _editorService;
  bool _changingInterface = false;
  bool _v3EntranceCompleted = false;
  bool _orionStartupCompleted = false;
  String _studioSizeKey = '';
  int _studioResizeGeneration = 0;
  Future<void> _studioResizeQueue = Future<void>.value();
  final _completedIntros = <InterfacePreset>{};
  late final _observer = _EditorOverlayObserver(
    (value) => _editorService?.setObscured(value),
  );
  OrionController get controller => widget.controller;
  bool get nativeWindow => widget.nativeWindow;

  void _completeIntro(InterfacePreset preset) {
    if (!mounted || _completedIntros.contains(preset)) return;
    if (nativeWindow) unawaited(NativeWindowService.completeStartupPlacement());
    setState(() => _completedIntros.add(preset));
  }

  @override
  void initState() {
    super.initState();
    // Only the interface opened at process startup gets this entrance. Returning
    // from a source UI or changing pages must never replay the cover.
    _orionStartupCompleted =
        controller.selectedInterface != InterfacePreset.orion;
    _studioSizeKey = _studioSizeSignature();
    controller.addListener(_studioSizeChanged);
    final windows = controller.companionWindows;
    if (windows is CompanionWindowService) {
      windows.onSelectInterface = _switchInterface;
      windows.flushEditor = () async {
        await _editorService?.flush();
      };
    }
    if (nativeWindow && (Platform.isLinux || Platform.isWindows)) {
      _editorService = MonacoEditorService(
        onChange: (id, content) =>
            controller.updateDocumentContent(id, content),
        onShortcut: (name) {
          if (controller.selectedInterface == InterfacePreset.orion &&
              (_shellKey.currentState?._introductionVisible ?? false)) {
            return;
          }
          if (name == 'theme-studio') {
            _openStudio();
            return;
          }
          switch (controller.selectedInterface) {
            case InterfacePreset.synapseV3:
              _synapseKey.currentState?.handleEditorShortcut(name);
            case InterfacePreset.synapseBlue:
              _blueKey.currentState?.handleEditorShortcut(name);
            case InterfacePreset.synapseX:
              _xKey.currentState?.handleEditorShortcut(name);
            case InterfacePreset.synapse2017:
              _ogKey.currentState?.handleEditorShortcut(name);
            case InterfacePreset.awp:
              _awpKey.currentState?.handleEditorShortcut(name);
            case InterfacePreset.xeno:
              _xenoKey.currentState?.handleEditorShortcut(name);
            case InterfacePreset.krnl:
              _krnlKey.currentState?.handleEditorShortcut(name);
            case InterfacePreset.calamari:
              _calamariKey.currentState?.handleEditorShortcut(name);
            case InterfacePreset.zenithV2:
              _zenithKey.currentState?.handleEditorShortcut(name);
            default:
              _shellKey.currentState?._editorShortcut(name);
          }
        },
      );
      // Load the offline editor while the source loading screen is visible.
      // Its native surface remains hidden until the editor supplies bounds.
      unawaited(_editorService!.initialize());
    }
  }

  @override
  void dispose() {
    controller.removeListener(_studioSizeChanged);
    _studioResizeGeneration++;
    _editorService?.dispose();
    final windows = controller.companionWindows;
    if (windows is CompanionWindowService) windows.dispose();
    super.dispose();
  }

  bool get _supportsStudio => const {
    InterfacePreset.orion,
    InterfacePreset.synapseV3,
    InterfacePreset.synapseBlue,
    InterfacePreset.synapseX,
    InterfacePreset.synapse2017,
  }.contains(controller.selectedInterface);

  void _openStudio() {
    if (controller.selectedInterface == InterfacePreset.orion &&
        (_shellKey.currentState?._introductionVisible ?? false)) {
      return;
    }
    final context = _navigatorKey.currentContext;
    if (!_supportsStudio || context == null) return;
    unawaited(
      openThemeStudio(
        context,
        controller: controller,
        preset: controller.selectedInterface,
        editorService: _editorService,
      ),
    );
  }

  String _studioSizeSignature() {
    if (!_supportsStudio) return controller.selectedInterface.name;
    final window = SynapseThemeCatalog.current(
      controller,
      controller.selectedInterface,
    ).window('main');
    return '${controller.selectedInterface.name}:${window.width}:${window.height}';
  }

  void _studioSizeChanged() {
    final key = _studioSizeSignature();
    if (key == _studioSizeKey) return;
    _studioSizeKey = key;
    if (!nativeWindow || !_supportsStudio || _changingInterface) return;
    final preset = controller.selectedInterface;
    if (preset != InterfacePreset.orion &&
        preset != InterfacePreset.synapseV3 &&
        !_completedIntros.contains(preset)) {
      return;
    }
    final generation = ++_studioResizeGeneration;
    _studioResizeQueue = _studioResizeQueue
        .catchError((Object _) {})
        .then((_) async {
          if (!mounted ||
              generation != _studioResizeGeneration ||
              controller.selectedInterface != preset) {
            return;
          }
          final profile = InterfaceWindowProfile.forInterface(
            controller,
            preset,
          );
          _editorService?.setTransitioning(true);
          try {
            if (preset == InterfacePreset.orion) {
              await _shellKey.currentState?._prepareStudioResize();
            }
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            }
            final bounds = await windowManager.getBounds();
            await windowManager.setResizable(true);
            await NativeWindowService.setMinimumSize(profile.minimumSize);
            await windowManager.setBounds(
              Rect.fromCenter(
                center: bounds.center,
                width: profile.size.width,
                height: profile.size.height,
              ),
            );
            await NativeWindowService.setResizable(
              profile.resizable,
              size: profile.size,
            );
            if (preset == InterfacePreset.orion) {
              _shellKey.currentState?._rememberStudioSize(bounds.center);
            }
          } finally {
            await WidgetsBinding.instance.endOfFrame;
            _editorService?.setTransitioning(false);
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _switchInterface(InterfacePreset preset) async {
    if (_changingInterface) return;
    if (controller.selectedInterface == preset) {
      switch (preset) {
        case InterfacePreset.synapseBlue:
          _blueKey.currentState?.handleEditorShortcut('show-editor');
        case InterfacePreset.synapseX:
          _xKey.currentState?.handleEditorShortcut('show-editor');
        case InterfacePreset.synapse2017:
          _ogKey.currentState?.handleEditorShortcut('show-editor');
        case InterfacePreset.synapseV3:
          _synapseKey.currentState?.handleEditorShortcut('show-editor');
        case InterfacePreset.awp:
          _awpKey.currentState?.handleEditorShortcut('show-editor');
        case InterfacePreset.xeno:
          _xenoKey.currentState?.handleEditorShortcut('show-editor');
        case InterfacePreset.krnl:
          _krnlKey.currentState?.handleEditorShortcut('show-editor');
        case InterfacePreset.calamari:
          _calamariKey.currentState?.handleEditorShortcut('show-editor');
        case InterfacePreset.zenithV2:
          _zenithKey.currentState?.handleEditorShortcut('show-editor');
        default:
          _shellKey.currentState?._go(0);
      }
      return;
    }
    if (nativeWindow) unawaited(NativeWindowService.completeStartupPlacement());
    _changingInterface = true;
    final windows = controller.companionWindows;
    if (windows is CompanionWindowService) windows.acceptsOpens = false;
    try {
      await controller.companionWindows?.closeAll();
      await _shellKey.currentState?._stopCompactMorph();
      try {
        await _editorService?.flush();
      } catch (_) {
        // A terminated renderer cannot flush. Keep the latest received draft
        // and allow switching to the other interface's recovery controls.
      }
      if (!mounted) return;
      _editorService?.setObscured(true, owner: 'interface-switch');
      if (const {
            InterfacePreset.synapseV3,
            InterfacePreset.synapseBlue,
            InterfacePreset.synapseX,
            InterfacePreset.synapse2017,
          }.contains(preset) &&
          controller.getInterfacePreferences(
                InterfacePreset.synapseBlue,
              )['playLoadingScreenOnShellChange'] ==
              true) {
        _completedIntros.remove(preset);
        if (preset == InterfacePreset.synapseV3) _v3EntranceCompleted = false;
      }
      final changingShell =
          preset.isStandalone || controller.selectedInterface.isStandalone;
      if (nativeWindow && changingShell) {
        try {
          final profile = InterfaceWindowProfile.forInterface(
            controller,
            preset,
            coldStart: !_completedIntros.contains(preset),
          );
          final previousBounds = await windowManager.getBounds();
          await windowManager.setResizable(true);
          await NativeWindowService.setMinimumSize(profile.minimumSize);
          if (preset.isStandalone && await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          }
          final maximized = await windowManager.isMaximized();
          await NativeWindowService.setAlwaysOnTop(profile.alwaysOnTop);
          await NativeWindowService.setResizable(
            profile.resizable,
            size: maximized ? null : profile.size,
          );
          if (!maximized) {
            await windowManager.setPosition(
              previousBounds.center -
                  Offset(profile.size.width / 2, profile.size.height / 2),
            );
          }
        } catch (_) {
          // The responsive interface remains usable if the compositor cannot
          // apply new bounds or window flags.
        }
      }
      if (!mounted) return;
      controller.setInterface(preset);
      await controller.flushPersistence();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && preset == InterfacePreset.orion) {
        _shellKey.currentState?._go(0);
      }
    } finally {
      _editorService?.setObscured(false, owner: 'interface-switch');
      _changingInterface = false;
      if (windows is CompanionWindowService) windows.acceptsOpens = true;
    }
  }

  @override
  Widget build(BuildContext context) => SelectedBuilder(
    listenable: controller,
    select: () => (
      controller.selectedInterface,
      controller.themeMode,
      controller.accentColor,
      controller.orionTheme,
      controller.reducedMotion,
      controller.uiScale,
      controller.synapsePreferences,
      controller.getInterfacePreferences(controller.selectedInterface),
      controller.customLogoBytes,
    ),
    builder: (_, _) => MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Orion',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [_observer],
      theme: orionTheme(
        Brightness.light,
        controller.accentColor,
        fontFamily: controller.selectedInterface == InterfacePreset.orion
            ? SynapseThemeCatalog.current(
                controller,
                InterfacePreset.orion,
              ).fontFamily
            : null,
        preferences: controller.selectedInterface == InterfacePreset.orion
            ? controller.orionTheme
            : null,
        reducedMotion: controller.reducedMotion,
        compactMode:
            controller.selectedInterface == InterfacePreset.orion &&
            controller.orionCompactMode,
      ),
      darkTheme: orionTheme(
        Brightness.dark,
        controller.accentColor,
        fontFamily: controller.selectedInterface == InterfacePreset.orion
            ? SynapseThemeCatalog.current(
                controller,
                InterfacePreset.orion,
              ).fontFamily
            : null,
        preferences: controller.selectedInterface == InterfacePreset.orion
            ? controller.orionTheme
            : null,
        reducedMotion: controller.reducedMotion,
        compactMode:
            controller.selectedInterface == InterfacePreset.orion &&
            controller.orionCompactMode,
      ),
      themeMode: controller.themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final mainInterface =
            controller.selectedInterface == InterfacePreset.orion;
        final reducedMotion =
            controller.reducedMotion || media.disableAnimations;
        final cornerRadius = controller.selectedInterface.isStandalone
            ? 0.0
            : mainInterface && controller.orionTheme.liquidGlassEnabled
            ? 24.0
            : OrionDensity.of(context).mix(16, 14);
        return MediaQuery(
          data: media.copyWith(disableAnimations: reducedMotion),
          child: NativeDesktopGlassViewport(
            supported: nativeWindow && (Platform.isLinux || Platform.isWindows),
            enabled:
                mainInterface &&
                controller.orionTheme.liquidGlassEnabled &&
                controller.orionTheme.windowOpacity < 1,
            opacity: controller.orionTheme.windowOpacity,
            cornerRadius: cornerRadius,
            builder: (context, desktopGlassActive) => NativeRainViewport(
              supported:
                  nativeWindow && (Platform.isLinux || Platform.isWindows),
              rainEnabled: mainInterface && controller.orionTheme.rainEnabled,
              windowOpacity: desktopGlassActive
                  ? 1
                  : mainInterface
                  ? controller.orionTheme.windowOpacity
                  : 1,
              reducedMotion: reducedMotion,
              cornerRadius: cornerRadius,
              editorService: _editorService,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.keyT,
                    control: true,
                    alt: true,
                  ): _openStudio,
                  const SingleActivator(
                    LogicalKeyboardKey.keyT,
                    control: true,
                    alt: true,
                    shift: true,
                  ): _openStudio,
                },
                child: DesktopFrame(
                  enabled: nativeWindow,
                  syncNativeCorners:
                      nativeWindow &&
                      mainInterface &&
                      controller.orionTheme.liquidGlassEnabled,
                  reducedMotion: controller.reducedMotion,
                  cornerRadius: cornerRadius,
                  borderColor: controller.selectedInterface.isStandalone
                      ? Colors.transparent
                      : OrionColors.of(context).glassEnabled
                      ? Colors.transparent
                      : null,
                  child: OrionGlassScene(
                    enabled:
                        mainInterface && OrionColors.of(context).glassEnabled,
                    reducedMotion: reducedMotion,
                    backdrop: OrionGlassBackdrop(
                      tint: OrionColors.of(context).background,
                      authoredGradient: OrionColors.of(
                        context,
                      ).backgroundGradient,
                      useAuthoredBackground: true,
                    ),
                    child: OrionGlassSurface(
                      radius: 24,
                      blur: 0,
                      tint: Colors.transparent,
                      child: UiScaleViewport(
                        // Historical loaders have exact, small native card dimensions.
                        // Apply the user's GUI density when the full shell is ready.
                        scale:
                            const {
                                  InterfacePreset.synapseBlue,
                                  InterfacePreset.synapseX,
                                  InterfacePreset.synapse2017,
                                }.contains(controller.selectedInterface) &&
                                !_completedIntros.contains(
                                  controller.selectedInterface,
                                )
                            ? 1
                            : controller.uiScale,
                        child: child!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      themeAnimationDuration:
          controller.reducedMotion ||
              WidgetsBinding
                  .instance
                  .platformDispatcher
                  .accessibilityFeatures
                  .disableAnimations
          ? Duration.zero
          : WindowMorphService.defaultDuration,
      themeAnimationCurve: OrionMotion.spatial,
      home: SelectedBuilder(
        listenable: controller,
        select: () => (
          controller.selectedInterface,
          controller.bridgeConnected,
          controller.reducedMotion,
          controller.synapsePreferences,
          controller.introCompleted,
        ),
        builder: (context, _) => Material(
          type: MaterialType.transparency,
          child: switch (controller.selectedInterface) {
            InterfacePreset.zenithV2 => ZenithShell(
              key: _zenithKey,
              controller: controller,
              bridgeReady: controller.bridgeConnected,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              onSelectInterface: _switchInterface,
            ),
            InterfacePreset.awp => AwpShell(
              key: _awpKey,
              controller: controller,
              bridgeReady: controller.bridgeConnected,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              onSelectInterface: _switchInterface,
            ),
            InterfacePreset.xeno => XenoShell(
              key: _xenoKey,
              controller: controller,
              bridgeReady: controller.bridgeConnected,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              onSelectInterface: _switchInterface,
            ),
            InterfacePreset.krnl => KrnlShell(
              key: _krnlKey,
              controller: controller,
              bridgeReady: controller.bridgeConnected,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              onSelectInterface: _switchInterface,
            ),
            InterfacePreset.calamari => CalamariShell(
              key: _calamariKey,
              controller: controller,
              bridgeReady: controller.bridgeConnected,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              onSelectInterface: _switchInterface,
            ),
            InterfacePreset.synapseBlue => SynapseBlueShell(
              key: _blueKey,
              controller: controller,
              bridgeReady: controller.bridgeConnected,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              onSelectInterface: _switchInterface,
              playIntro: !_completedIntros.contains(
                InterfacePreset.synapseBlue,
              ),
              onIntroCompleted: () =>
                  _completeIntro(InterfacePreset.synapseBlue),
            ),
            InterfacePreset.synapseX => SynapseXShell(
              key: _xKey,
              controller: controller,
              bridgeReady: controller.bridgeConnected,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              onSelectInterface: _switchInterface,
              playIntro: !_completedIntros.contains(InterfacePreset.synapseX),
              onIntroCompleted: () => _completeIntro(InterfacePreset.synapseX),
            ),
            InterfacePreset.synapse2017 => SynapseOgShell(
              key: _ogKey,
              controller: controller,
              bridgeReady: controller.bridgeConnected,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              onSelectInterface: _switchInterface,
              playIntro: !_completedIntros.contains(
                InterfacePreset.synapse2017,
              ),
              onIntroCompleted: () =>
                  _completeIntro(InterfacePreset.synapse2017),
            ),
            InterfacePreset.synapseV3 => V3Entrance(
              play: !_v3EntranceCompleted,
              reducedMotion:
                  controller.reducedMotion ||
                  MediaQuery.disableAnimationsOf(context),
              cornerRadius: controller.synapsePreferences.cornerRadius,
              borderColor: controller.synapsePreferences.color(
                'shell.shellBorder',
                fallback: const Color(0xff4b4d4c),
              ),
              editorService: _editorService,
              onCompleted: () => _v3EntranceCompleted = true,
              child: SynapseV3Shell(
                key: _synapseKey,
                controller: controller,
                bridgeReady: controller.bridgeConnected,
                nativeWindow: nativeWindow,
                editorService: _editorService,
                onBackToOrion: () => _switchInterface(InterfacePreset.orion),
              ),
            ),
            _ => OrionShell(
              key: _shellKey,
              controller: controller,
              nativeWindow: nativeWindow,
              editorService: _editorService,
              onSwitchInterface: _switchInterface,
              showcase: widget.showcase,
              playStartup: !_orionStartupCompleted && !widget.showcase,
              onStartupComplete: () => _orionStartupCompleted = true,
            ),
          },
        ),
      ),
    ),
  );
}

/// The same shell used by the desktop, without native windows or an intro.
class OrionStudioPreview extends StatelessWidget {
  const OrionStudioPreview({
    super.key,
    required this.controller,
    this.previewPage = 'editor',
  });
  final OrionController controller;
  final String previewPage;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final brightness = switch (controller.orionTheme.themeMode) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      };
      return Theme(
        data: orionTheme(
          brightness,
          controller.accentColor,
          fontFamily: SynapseThemeCatalog.current(
            controller,
            InterfacePreset.orion,
          ).fontFamily,
          preferences: controller.orionTheme,
          compactMode: controller.orionCompactMode,
          reducedMotion: true,
        ),
        child: Builder(
          builder: (context) {
            final colors = OrionColors.of(context);
            final radius = colors.glassEnabled
                ? 24.0
                : OrionDensity.of(context).mix(16, 14);
            return LayoutBuilder(
              builder: (context, constraints) => MediaQuery(
                // This is a complete desktop window inside another route.
                // Studio's viewport/insets must not affect its breakpoints,
                // popups, or the logical viewport used by the GUI scale.
                data: MediaQuery.of(context).copyWith(
                  size: constraints.biggest,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                  viewInsets: EdgeInsets.zero,
                  systemGestureInsets: EdgeInsets.zero,
                  disableAnimations: true,
                ),
                child: AnimatedContainer(
                  key: const ValueKey('orion-studio-desktop-frame'),
                  duration: Duration.zero,
                  curve: Curves.easeOutCubic,
                  clipBehavior: Clip.antiAlias,
                  // Match DesktopFrame's visual paint without registering
                  // listeners or controlling the real Studio OS window.
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: colors.glassEnabled
                          ? Colors.transparent
                          : colors.outline(.65),
                    ),
                  ),
                  child: OrionGlassScene(
                    enabled: colors.glassEnabled,
                    reducedMotion: true,
                    backdrop: OrionGlassBackdrop(
                      tint: colors.background,
                      authoredGradient: colors.backgroundGradient,
                      useAuthoredBackground: true,
                    ),
                    child: OrionGlassSurface(
                      radius: 24,
                      blur: 0,
                      tint: Colors.transparent,
                      child: UiScaleViewport(
                        scale: controller.uiScale,
                        child: OrionShell(
                          controller: controller,
                          nativeWindow: false,
                          previewPage: previewPage,
                          onSwitchInterface: (_) async {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class OrionShell extends StatefulWidget {
  final OrionController controller;
  final bool nativeWindow;
  final bool showcase;
  final bool playStartup;
  final VoidCallback? onStartupComplete;
  final String? previewPage;
  final MonacoEditorService? editorService;
  final Future<void> Function(InterfacePreset) onSwitchInterface;
  const OrionShell({
    super.key,
    required this.controller,
    required this.nativeWindow,
    required this.onSwitchInterface,
    this.editorService,
    this.showcase = false,
    this.playStartup = false,
    this.onStartupComplete,
    this.previewPage,
  });
  @override
  State<OrionShell> createState() => _OrionShellState();
}

class _OrionShellState extends State<OrionShell>
    with TickerProviderStateMixin, WindowListener {
  int page = 0;
  late final AnimationController _pageMotion = AnimationController(
    vsync: this,
    duration: OrionMotion.pageDuration,
    value: 1,
  );
  int? _outgoingPage;
  double _pageDirection = 1;
  bool replayIntro = false;
  bool _showcaseIntro = false;
  late bool _startupVisible;
  static const _introductionOwner = 'orion-introduction';
  final workspaceKey = GlobalKey<WorkspaceScreenState>();
  final _shellFocus = FocusNode(debugLabel: 'Orion shortcuts');
  late final WindowMorphService _windowMorph = WindowMorphService(vsync: this);
  Future<void> _windowChanges = Future<void>.value();
  Rect? _normalWindowBounds;
  late (bool, bool) _lastSizeMode;
  late bool _sizeModeStartedNormal;
  late bool _lastAlwaysOnTop;
  bool _compactWindowActive = true;
  int _compactRequest = 0;
  OrionController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    page = _previewPageIndex(widget.previewPage);
    _lastSizeMode = (c.orionCompactMode, c.orionEnlargedMode);
    _sizeModeStartedNormal = !c.orionCompactMode && !c.orionEnlargedMode;
    _lastAlwaysOnTop = c.alwaysOnTop;
    c.addListener(_windowPreferenceChanged);
    _showcaseIntro = widget.showcase;
    _startupVisible = widget.playStartup && widget.previewPage == null;
    _syncIntroductionEditor();
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
    _pageMotion.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _outgoingPage = null);
        workspaceKey.currentState?.setEditorTransitioning(false);
      }
    });
  }

  static int _previewPageIndex(String? value) => switch (value) {
    'scriptHub' => 1,
    'uiSelection' => 2,
    'themeControl' => 3,
    'settings' => 4,
    _ => 0,
  };

  @override
  void didUpdateWidget(covariant OrionShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.previewPage != null &&
        oldWidget.previewPage != widget.previewPage) {
      page = _previewPageIndex(widget.previewPage);
      _outgoingPage = null;
      _pageMotion.value = 1;
    }
  }

  @override
  void dispose() {
    widget.editorService?.setObscured(false, owner: _introductionOwner);
    c.removeListener(_windowPreferenceChanged);
    _compactWindowActive = false;
    _compactRequest++;
    if (widget.nativeWindow) _windowMorph.dispose();
    if (widget.nativeWindow) windowManager.removeListener(this);
    _pageMotion.dispose();
    _shellFocus.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    try {
      await DesktopCloseService.closeApp(
        controller: c,
        nativeWindow: widget.nativeWindow,
        stopWindowChanges: _stopCompactMorph,
        flushEditor: () async => workspaceKey.currentState?.flushEditor(),
      );
    } catch (_) {
      _compactWindowActive = mounted;
      rethrow;
    }
  }

  void _windowPreferenceChanged() {
    _syncIntroductionEditor();
    final topmost = c.alwaysOnTop;
    if (topmost != _lastAlwaysOnTop) {
      _lastAlwaysOnTop = topmost;
      if (widget.nativeWindow && _compactWindowActive) {
        // Share the resize queue so a pending flag cannot leak into another
        // interface after the main window has finished its transition.
        _windowChanges = _windowChanges
            .catchError((Object _) {})
            .then((_) async {
              if (!mounted ||
                  !_compactWindowActive ||
                  c.selectedInterface != InterfacePreset.orion ||
                  c.alwaysOnTop != topmost) {
                return;
              }
              await NativeWindowService.setAlwaysOnTop(topmost);
            })
            .catchError((Object _) {});
      }
    }
    final mode = (c.orionCompactMode, c.orionEnlargedMode);
    if (mode == _lastSizeMode) return;
    _lastSizeMode = mode;
    if (widget.nativeWindow && _compactWindowActive) {
      _queueSizeModeMorph(compact: mode.$1, enlarged: mode.$2);
    }
  }

  void _queueSizeModeMorph({required bool compact, required bool enlarged}) {
    final request = ++_compactRequest;
    // Cancel synchronously before queueing setup, including a resize currently
    // awaiting GTK. The next request starts at the settled native bounds.
    unawaited(_windowMorph.cancel());
    _windowChanges = _windowChanges.then((_) async {
      bool current() =>
          mounted &&
          _compactWindowActive &&
          c.selectedInterface == InterfacePreset.orion &&
          request == _compactRequest;
      try {
        await _windowMorph.cancel();
        if (!current() || await windowManager.isFullScreen()) return;
        if (await windowManager.isMaximized()) {
          if (!current()) return;
          final maximizedBounds = await _windowMorph.getBounds();
          if (!current()) return;
          await windowManager.unmaximize();
          // GTK acknowledges the request before its restored configure event.
          // Wait for a stable normal allocation before saving return bounds.
          Rect? previous;
          var settled = false;
          for (var attempt = 0; attempt < 60 && current(); attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 16));
            if (!current()) return;
            if (await windowManager.isMaximized()) continue;
            final restored = await _windowMorph.getBounds();
            if (restored != maximizedBounds && restored == previous) {
              settled = true;
              break;
            }
            previous = restored;
          }
          if (!settled) return;
        }
        if (!current()) return;
        final bounds = await _windowMorph.getBounds();
        if (!current()) return;
        final normalSize = SynapseThemeCatalog.windowSize(
          SynapseThemeCatalog.current(c, InterfacePreset.orion),
          InterfacePreset.orion,
          'main',
        );
        if (compact || enlarged) {
          // Restored compact/enlarged bounds are not the user's normal size.
          // Only capture live bounds when this shell began in normal mode.
          _normalWindowBounds ??= _sizeModeStartedNormal
              ? bounds
              : Rect.fromCenter(
                  center: bounds.center,
                  width: normalSize.width,
                  height: normalSize.height,
                );
        }
        final targetSize = enlarged
            ? InterfaceWindowProfile.orionEnlargedSize
            : InterfaceWindowProfile.compactOrionSizeFor(
                (_normalWindowBounds ?? bounds).size,
              );
        final target = compact || enlarged
            ? Rect.fromCenter(
                center: bounds.center,
                width: targetSize.width,
                height: targetSize.height,
              )
            : _normalWindowBounds ??
                  Rect.fromCenter(
                    center: bounds.center,
                    width: normalSize.width,
                    height: normalSize.height,
                  );
        // Keep the minimum low throughout both directions so GTK does not
        // snap to the normal minimum ahead of the expanding animation.
        await NativeWindowService.setMinimumSize(
          InterfaceWindowProfile.orionCompactMinimumSize,
        );
        if (!current()) return;
        final completed = await _windowMorph.animateTo(
          target,
          start: bounds,
          reducedMotion: _reduceMotion,
        );
        if (!current() || !completed) return;
        await NativeWindowService.setMinimumSize(
          compact
              ? InterfaceWindowProfile.orionCompactMinimumSize
              : InterfaceWindowProfile.orionMinimumSize,
        );
        if (current() && !compact && !enlarged) {
          _normalWindowBounds = null;
          _sizeModeStartedNormal = true;
        }
      } catch (_) {
        // Density remains usable when a compositor rejects window positioning.
      }
    });
  }

  Future<void> _stopCompactMorph() async {
    _compactWindowActive = false;
    _compactRequest++;
    if (!widget.nativeWindow) return;
    await _windowMorph.cancel();
    await _windowChanges;
  }

  Future<void> _prepareStudioResize() async {
    _compactRequest++;
    await _windowMorph.cancel();
    await _windowChanges;
  }

  void _rememberStudioSize(Offset center) {
    final normalSize = SynapseThemeCatalog.windowSize(
      SynapseThemeCatalog.current(c, InterfacePreset.orion),
      InterfacePreset.orion,
      'main',
    );
    _sizeModeStartedNormal = !c.orionCompactMode && !c.orionEnlargedMode;
    _normalWindowBounds = !_sizeModeStartedNormal
        ? Rect.fromCenter(
            center: center,
            width: normalSize.width,
            height: normalSize.height,
          )
        : null;
  }

  @override
  void onWindowEnterFullScreen() {
    _compactRequest++;
    unawaited(_windowMorph.cancel());
  }

  @override
  void onWindowMaximize() {
    _compactRequest++;
    unawaited(_windowMorph.cancel());
  }

  @override
  void onWindowLeaveFullScreen() {
    if (_compactWindowActive &&
        (c.orionCompactMode ||
            c.orionEnlargedMode ||
            _normalWindowBounds != null)) {
      _queueSizeModeMorph(
        compact: c.orionCompactMode,
        enlarged: c.orionEnlargedMode,
      );
    }
  }

  void _go(int index) {
    if (page == index) return;
    workspaceKey.currentState?.setEditorTransitioning(true);
    _shellFocus.requestFocus();
    final previous = _outgoingPage != null && _pageMotion.value < .25
        ? _outgoingPage!
        : page;
    setState(() {
      _outgoingPage = previous;
      _pageDirection = index > previous ? 1 : -1;
      page = index;
    });
    if (_reduceMotion) {
      setState(() => _outgoingPage = null);
      _pageMotion.value = 1;
      workspaceKey.currentState?.setEditorTransitioning(false);
    } else {
      _pageMotion.forward(from: 0);
    }
  }

  bool get _reduceMotion =>
      c.reducedMotion || MediaQuery.disableAnimationsOf(context);

  bool get _showTutorial =>
      widget.previewPage == null && (!c.introCompleted || replayIntro);

  bool get _introductionVisible =>
      _showTutorial ||
      _startupVisible ||
      (widget.previewPage == null && _showcaseIntro);

  void _syncIntroductionEditor() => widget.editorService?.setObscured(
    _introductionVisible,
    owner: _introductionOwner,
  );

  void _finishStartup() {
    if (!mounted || !_startupVisible) return;
    setState(() => _startupVisible = false);
    _syncIntroductionEditor();
    widget.onStartupComplete?.call();
  }

  void _finishIntro() {
    _shellFocus.requestFocus();
    workspaceKey.currentState?.setEditorTransitioning(!_reduceMotion);
    setState(() {
      replayIntro = false;
      _showcaseIntro = false;
      _outgoingPage = null;
    });
    c.completeIntro();
    // Persist completion immediately, including when workspace recovery is off.
    // Replaying the guide never clears this flag or changes the current page.
    unawaited(c.flushPersistence());
    _syncIntroductionEditor();
    if (_reduceMotion) {
      _pageMotion.value = 1;
      workspaceKey.currentState?.setEditorTransitioning(false);
    } else {
      _pageMotion.forward(from: 0);
    }
  }

  void _replayIntroduction() {
    _shellFocus.requestFocus();
    _pageMotion.stop();
    _pageMotion.value = 1;
    workspaceKey.currentState?.setEditorTransitioning(false);
    setState(() {
      _outgoingPage = null;
      replayIntro = true;
    });
    _syncIntroductionEditor();
  }

  Future<void> _copyIntroBridge() async {
    final source = await c.loadBridgeScript();
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: source));
  }

  Future<void> _openIntroBridgeFolder() async {
    final library = c.scriptLibrary;
    if (library == null) {
      throw const FileSystemException('The scripts folder is unavailable.');
    }
    await library.initialize();
    if (!mounted) return;
    final folder = Directory('${library.directory.path}/Special');
    if (!await folder.exists()) {
      throw const FileSystemException('The Bridge folder is unavailable.');
    }
    await DesktopLauncher.openDirectory(folder);
  }

  Future<void> _new() async {
    await workspaceKey.currentState?.flushEditor();
    c.newDocument();
    _go(0);
  }

  Future<void> _open() async {
    try {
      await workspaceKey.currentState?.flushEditor();
      workspaceKey.currentState?.setEditorObscured(
        true,
        owner: 'native-dialog',
      );
      await c.openFile();
      if (mounted) _go(0);
    } catch (e) {
      if (mounted) toast(context, 'Could not open file: $e');
    } finally {
      workspaceKey.currentState?.setEditorObscured(
        false,
        owner: 'native-dialog',
      );
    }
  }

  Future<void> _save() async {
    final documentId = c.activeDocumentId;
    var needsDialog = false;
    try {
      await workspaceKey.currentState?.flushEditor();
      final document = c.documents
          .where((doc) => doc.id == documentId)
          .firstOrNull;
      if (document == null) return;
      needsDialog = document.filePath == null;
      if (needsDialog) {
        workspaceKey.currentState?.setEditorObscured(
          true,
          owner: 'native-dialog',
        );
      }
      final saved = await c.saveDocument(documentId);
      if (mounted && saved) toast(context, 'Script saved');
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e');
    } finally {
      if (needsDialog) {
        workspaceKey.currentState?.setEditorObscured(
          false,
          owner: 'native-dialog',
        );
      }
    }
  }

  Future<void> _run() async {
    await workspaceKey.currentState?.flushEditor();
    c.execute();
    _go(0);
  }

  void _editorShortcut(String name) {
    if (_introductionVisible) return;
    switch (name) {
      case 'new':
        _new();
      case 'open':
        _open();
      case 'save':
        _save();
      case 'saveAs':
        () async {
          await workspaceKey.currentState?.flushEditor();
          workspaceKey.currentState?.setEditorObscured(
            true,
            owner: 'native-dialog',
          );
          try {
            await c.saveAs();
          } finally {
            workspaceKey.currentState?.setEditorObscured(
              false,
              owner: 'native-dialog',
            );
          }
        }();
      case 'execute':
        _run();
      case 'palette':
        _palette();
    }
  }

  void _find() {
    if (page == 0) {
      workspaceKey.currentState?.requestFind();
      return;
    }
    _go(0);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => workspaceKey.currentState?.requestFind(),
    );
  }

  void _palette() {
    showDialog<void>(
      context: context,
      builder: (ctx) => OrionOverlayTheme(
        controller: c,
        builder: (ctx) => _CommandPalette(
          actions: [
            ('New script', 'Ctrl N', Icons.add_rounded, _new),
            ('Open file', 'Ctrl O', Icons.folder_open_rounded, _open),
            ('Save script', 'Ctrl S', Icons.save_outlined, _save),
            ('Execute', 'Ctrl Enter', Icons.play_arrow_rounded, _run),
            ('Find in editor', 'Ctrl F', Icons.search_rounded, _find),
            ('Script library', '', Icons.widgets_outlined, () => _go(1)),
            (
              'UI Selection',
              '',
              Icons.dashboard_customize_outlined,
              () => _go(2),
            ),
            ('Theme Control', '', Icons.palette_outlined, () => _go(3)),
            ('Settings', '', Icons.tune_rounded, () => _go(4)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final density = OrionDensity.of(context);
    final intro =
        _showTutorial || (widget.previewPage == null && _showcaseIntro);
    final blocked = _introductionVisible;
    final duration = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return CallbackShortcuts(
      bindings: blocked
          ? const {}
          : {
              const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  _new,
              const SingleActivator(LogicalKeyboardKey.keyO, control: true):
                  _open,
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  _save,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _run,
              const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                  _palette,
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _find,
            },
      child: Focus(
        focusNode: _shellFocus,
        autofocus: true,
        child: SynapseThemeSurface(
          controller: c,
          preset: InterfacePreset.orion,
          windowId: 'main',
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _hasStudioBackground || colors.glassEnabled
                        ? Colors.transparent
                        : colors.background,
                    gradient: _hasStudioBackground || colors.glassEnabled
                        ? null
                        : colors.backgroundGradient,
                  ),
                  child: Column(
                    children: [
                      OrionStudioLayer(
                        controller: c,
                        elementId: 'titleBar',
                        child: Builder(
                          builder: (context) {
                            final colors = OrionColors.of(context);
                            return Container(
                              height: density.mix(48, 42),
                              decoration: BoxDecoration(
                                color: colors.chrome(
                                  colors.panel.withValues(alpha: .35),
                                  role: 'panel',
                                ),
                                gradient: orionSurfaceGradient(
                                  colors,
                                  blend: .4,
                                ),
                                border: Border(
                                  bottom: BorderSide(color: colors.outline(.2)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: widget.nativeWindow
                                        ? DragToMoveArea(child: _title(colors))
                                        : _title(colors),
                                  ),
                                  if (!blocked)
                                    IconButton(
                                      tooltip: 'Quick actions · Ctrl K',
                                      onPressed: _palette,
                                      icon: Icon(
                                        Icons.search_rounded,
                                        size: 19,
                                        color: colors.muted,
                                      ),
                                    ),
                                  if (widget.nativeWindow ||
                                      widget.previewPage != null) ...[
                                    IconButton(
                                      tooltip: 'Minimize',
                                      onPressed: () {
                                        if (widget.nativeWindow) {
                                          windowManager.minimize();
                                        }
                                      },
                                      icon: Icon(
                                        Icons.remove_rounded,
                                        size: 17,
                                        color: colors.muted,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Maximize',
                                      onPressed: () async {
                                        if (!widget.nativeWindow) return;
                                        if (await windowManager.isMaximized()) {
                                          await windowManager.unmaximize();
                                        } else {
                                          await windowManager.maximize();
                                        }
                                      },
                                      icon: Icon(
                                        Icons.crop_square_rounded,
                                        size: 14,
                                        color: colors.muted,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Close Orion',
                                      onPressed: () {
                                        if (widget.nativeWindow) {
                                          windowManager.close();
                                        }
                                      },
                                      icon: Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: colors.muted,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 6),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Offstage(
                              offstage: intro,
                              child: ExcludeFocus(
                                excluding: blocked,
                                child: IgnorePointer(
                                  ignoring: blocked,
                                  child: Row(
                                    children: [
                                      OrionStudioLayer(
                                        controller: c,
                                        elementId: 'sidebar',
                                        child: Builder(
                                          builder: (context) => _navigation(
                                            OrionColors.of(context),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: OrionStudioLayer(
                                          controller: c,
                                          elementId: 'content',
                                          child: Builder(
                                            builder: (context) => _pages(
                                              OrionColors.of(context),
                                              blocked,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IgnorePointer(
                              ignoring: !intro,
                              child: AnimatedSwitcher(
                                duration: duration,
                                switchInCurve: OrionMotion.effects,
                                switchOutCurve: OrionMotion.effects,
                                child: _showTutorial
                                    ? OrionOnboardingScreen(
                                        key: const ValueKey('onboarding'),
                                        controller: c,
                                        onComplete: _finishIntro,
                                        onSaveBridge: () => c.saveBridgeScript(
                                          rethrowErrors: true,
                                        ),
                                        onCopyBridge: _copyIntroBridge,
                                        onOpenBridgeFolder:
                                            _openIntroBridgeFolder,
                                      )
                                    : intro
                                    ? IntroScreen(
                                        key: const ValueKey('intro'),
                                        controller: c,
                                        showcase: widget.showcase,
                                        onComplete: _finishIntro,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_startupVisible)
                  Positioned.fill(
                    child: OrionStartupReveal(
                      controller: c,
                      onComplete: _finishStartup,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasStudioBackground =>
      SynapseThemeCatalog.current(
        c,
        InterfacePreset.orion,
      ).window('main').background?.isValid ==
      true;

  Widget _title(OrionColors colors) => Row(
    children: [
      Padding(
        padding: EdgeInsets.only(left: OrionDensity.of(context).mix(16, 12)),
        child: SizedBox(
          width: OrionDensity.of(context).mix(104, 89),
          height: OrionDensity.of(context).mix(28, 24),
          child: SynapseThemeLogo(
            controller: c,
            preset: InterfacePreset.orion,
            windowId: 'main',
            child: OrionWordmark(
              height: OrionDensity.of(context).mix(28, 24),
              customImage: c.customLogoBytes,
            ),
          ),
        ),
      ),
      const Expanded(child: SizedBox()),
    ],
  );

  Widget _pages(OrionColors colors, bool intro) {
    final children = <Widget>[
      WorkspaceScreen(
        key: workspaceKey,
        controller: c,
        onLibrary: () => _go(1),
        onSave: _save,
        onOpen: _open,
        nativeEditor:
            widget.nativeWindow && (Platform.isLinux || Platform.isWindows),
        editorService: widget.editorService,
        active: page == 0 && !intro && !_pageMotion.isAnimating,
        onShortcut: _editorShortcut,
      ),
      LibraryScreen(
        key: const ValueKey('library'),
        controller: c,
        onOpenWorkspace: () => _go(0),
      ),
      UISelectionScreen(
        key: const ValueKey('ui-selection'),
        controller: c,
        onOpenWorkspace: () => _go(0),
        onSelectInterface: widget.onSwitchInterface,
      ),
      ThemeControlScreen(
        key: const ValueKey('theme-control'),
        controller: c,
        editorService: widget.editorService,
      ),
      SettingsScreen(
        key: const ValueKey('settings'),
        controller: c,
        onReplayIntro: _replayIntroduction,
      ),
    ];
    // Keep the page subtree, layout padding and Studio decorators identical
    // between animation frames. Only the opacity/transform above them moves.
    // Their retained paint layer can then be composed without repainting every
    // control and paragraph as the page settles.
    final density = OrionDensity.of(context);
    final padding = EdgeInsets.fromLTRB(
      density.mix(8, 6),
      density.mix(12, 8),
      density.mix(12, 8),
      density.mix(12, 8),
    );
    final pages = <Widget>[
      for (var index = 0; index < children.length; index++)
        RepaintBoundary(
          child: Padding(
            padding: padding,
            child: index == 0
                ? children[index]
                : OrionStudioLayer(
                    controller: c,
                    elementId: [
                      'workspace',
                      'libraryContent',
                      'uiSelection',
                      'themeControls',
                      'settingsControls',
                    ][index],
                    child: children[index],
                  ),
          ),
        ),
    ];
    return AnimatedBuilder(
      animation: _pageMotion,
      builder: (context, _) {
        final t = _reduceMotion ? 1.0 : _pageMotion.value;
        final incoming = OrionMotion.effects
            .transform(((t - .12) / .64).clamp(0, 1))
            .clamp(0.0, 1.0);
        final outgoing =
            1 -
            OrionMotion.effects.transform((t / .3).clamp(0, 1)).clamp(0.0, 1.0);
        final spatial = OrionMotion.spatial.transform(t);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var index = 0; index < children.length; index++)
              Offstage(
                offstage: index != page && index != _outgoingPage,
                child: TickerMode(
                  enabled: !intro && (index == page || index == _outgoingPage),
                  child: IgnorePointer(
                    ignoring: index != page || _pageMotion.isAnimating,
                    child: ExcludeSemantics(
                      excluding: index != page,
                      child: Opacity(
                        opacity: index == page ? incoming : outgoing,
                        child: Transform.translate(
                          offset: Offset(
                            index == page
                                ? _pageDirection * 20 * (1 - spatial)
                                : -_pageDirection * 10 * (1 - outgoing),
                            0,
                          ),
                          child: RetainedPage(
                            visible:
                                !intro &&
                                (index == page || index == _outgoingPage),
                            child: pages[index],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _navigation(OrionColors colors) => SizedBox(
    width: OrionDensity.of(context).mix(84, 68),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final density = OrionDensity.of(context);
        final gap = constraints.maxHeight < 350 ? 3.0 : density.mix(8, 6);
        final itemHeight = ((constraints.maxHeight - 16 - gap * 3) / 5).clamp(
          44.0,
          density.mix(64, 54),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            children: [
              for (int i = 0; i < 4; i++) ...[
                _destination(i, colors, itemHeight),
                if (i < 3) SizedBox(height: gap),
              ],
              const Spacer(),
              _destination(4, colors, itemHeight),
            ],
          ),
        );
      },
    ),
  );

  Widget _destination(int i, OrionColors colors, double height) =>
      OrionStudioLayer(
        controller: c,
        elementId: [
          'navEditor',
          'navScripts',
          'navUis',
          'navTheme',
          'navSettings',
        ][i],
        child: _RailDestination(
          selected: page == i,
          label: ['Editor', 'Scripts', 'UIs', 'Theme', 'Settings'][i],
          tooltip: [
            'Editor',
            'Scripts',
            'UI Selection',
            'Theme Control',
            'Settings',
          ][i],
          icon: [
            Icons.code_rounded,
            page == 1 ? Icons.folder_rounded : Icons.folder_outlined,
            page == 2
                ? Icons.dashboard_customize_rounded
                : Icons.dashboard_customize_outlined,
            page == 3 ? Icons.palette_rounded : Icons.palette_outlined,
            Icons.tune_rounded,
          ][i],
          height: height,
          reducedMotion: c.reducedMotion,
          onTap: () => _go(i),
        ),
      );
}

class _RailDestination extends StatefulWidget {
  const _RailDestination({
    required this.selected,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.reducedMotion,
    required this.onTap,
    required this.height,
  });
  final double height;
  final bool selected, reducedMotion;
  final String label, tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_RailDestination> createState() => _RailDestinationState();
}

class _RailDestinationState extends State<_RailDestination> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final density = OrionDensity.of(context);
    final reducedMotion =
        widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final selected = widget.selected;
    final shape = colors.glassEnabled
        ? BorderRadius.circular(_pressed ? 16 : 20)
        : BorderRadius.only(
            topLeft: Radius.circular(_pressed ? 12 : 18),
            topRight: Radius.circular(_pressed ? 12 : 18),
            bottomLeft: Radius.circular(_pressed ? 12 : 18),
            bottomRight: Radius.zero,
          );
    return Semantics(
      selected: selected,
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OrionGlassSurface(
                    radius: 20,
                    interactive: true,
                    materialOpacity: 0,
                    tint: colors.accent.withValues(
                      alpha: selected ? .13 : .035,
                    ),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: OrionMotion.effects,
                      width: density.mix(54, 46),
                      height: widget.height < 54 ? 27 : density.mix(34, 30),
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.transparentSurfaces
                                  ? colors.stateFill(
                                      _focused ? .14 : (_hovered ? .11 : .08),
                                    )
                                  : Color.lerp(
                                      colors.panel,
                                      colors.accent,
                                      _focused ? .32 : (_hovered ? .26 : .22),
                                    )
                            : _hovered || _focused || _pressed
                            ? colors.transparentSurfaces
                                  ? colors.stateFill(.045)
                                  : colors.elevated
                            : Colors.transparent,
                        borderRadius: shape,
                      ),
                      child: AnimatedScale(
                        scale: _pressed && !reducedMotion ? .94 : 1,
                        duration: duration,
                        curve: OrionMotion.spatialFast,
                        child: Icon(
                          widget.icon,
                          size: widget.height < 54 ? 19 : density.mix(22, 20),
                          color: selected
                              ? colors.readableAccent
                              : colors.muted,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: widget.height < 54 ? 2 : density.mix(6, 4)),
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    style: OrionType.label.copyWith(
                      fontFamily: Theme.of(
                        context,
                      ).textTheme.labelLarge?.fontFamily,
                      color: selected ? colors.ink : colors.muted,
                      fontSize: density.mix(11, 10.5),
                    ),
                    child: Text(widget.label, maxLines: 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandPalette extends StatefulWidget {
  final List<(String, String, IconData, VoidCallback)> actions;
  const _CommandPalette({required this.actions});
  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final c = OrionColors.of(context);
    final list = widget.actions
        .where((a) => a.$1.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Dialog(
      backgroundColor: Colors.transparent,
      child: OrionOverlaySurface(
        child: SizedBox(
          width: 540,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  onChanged: (s) => setState(() => query = s),
                  onSubmitted: (_) {
                    final action = widget.actions
                        .where(
                          (action) => action.$1.toLowerCase().contains(
                            query.toLowerCase(),
                          ),
                        )
                        .firstOrNull;
                    if (action != null) {
                      Navigator.pop(context);
                      action.$4();
                    }
                  },
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search actions',
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...list.map(
                          (a) => ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              a.$3,
                              size: 20,
                              color: c.readableAccent,
                            ),
                            title: Text(a.$1, style: OrionType.body),
                            trailing: Text(
                              a.$2,
                              style: OrionType.metadata.copyWith(
                                color: c.muted,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              a.$4();
                            },
                          ),
                        ),
                        if (list.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No matching actions'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Type to filter · Enter to select · Esc to close',
                  style: OrionType.metadata.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Native surfaces must yield to Flutter popup menus and dialogs for their full
/// transition, including the closing animation.
class _EditorOverlayObserver extends NavigatorObserver {
  _EditorOverlayObserver(this.onObscured);
  final ValueChanged<bool> onObscured;
  final Set<Route<dynamic>> _popups = {};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _popups.add(route);
      onObscured(true);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      route.completed.whenComplete(() {
        _popups.remove(route);
        onObscured(_popups.isNotEmpty);
      });
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _popups.remove(route);
    onObscured(_popups.isNotEmpty);
  }
}
