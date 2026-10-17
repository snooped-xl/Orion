import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models/orion_theme_preferences.dart';
import 'models/bridge_notification_content.dart';
import 'theme/expressive_motion.dart';
import 'theme/orion_theme.dart';
import 'theme/orion_surfaces.dart';
import 'widgets/orion_logo.dart';
import 'widgets/orion_glass.dart';
import 'widgets/native_desktop_glass.dart';

/// A dedicated notification worker, dispatched before the normal app/controller
/// bootstrap. It opens no workspace, bridge listener, hub, or companion engine.
Future<void> runBridgeNotificationWindow(
  Map<String, Object?> definition,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final bounds = Map<String, Object?>.from(definition['bounds'] as Map? ?? {});
  await const MethodChannel(
    'orion/bridge_notification',
  ).invokeMethod<void>('configure', bounds);
  final preferences = OrionThemePreferences.fromJson(definition['theme']);
  if (preferences.liquidGlassEnabled) {
    // A notification worker owns its separate GtkWindow and has no rain host
    // controller changing its opacity after this one-time configuration.
    await windowManager.setOpacity(preferences.windowOpacity);
  }
  runApp(
    NativeDesktopGlassViewport(
      supported: (Platform.isLinux || Platform.isWindows),
      enabled: preferences.liquidGlassEnabled && preferences.windowOpacity < 1,
      opacity: preferences.windowOpacity,
      cornerRadius: 24,
      onActiveChanged: (active) =>
          windowManager.setOpacity(active ? 1 : preferences.windowOpacity),
      builder: (context, _) => BridgeNotificationApp(
        definition: definition,
        onClose: () async {
          await windowManager.hide();
          exit(0);
        },
      ),
    ),
  );
}

class BridgeNotificationApp extends StatelessWidget {
  const BridgeNotificationApp({
    super.key,
    required this.definition,
    required this.onClose,
  });
  final Map<String, Object?> definition;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final prefs = OrionThemePreferences.fromJson(definition['theme']);
    final reduced = definition['reducedMotion'] == true;
    final mode = switch (definition['brightness']) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final duration = definition['durationMs'];
    return MaterialApp(
      title: bridgeNotificationTitle,
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: orionTheme(
        Brightness.light,
        prefs.accent,
        preferences: prefs,
        reducedMotion: reduced,
      ),
      darkTheme: orionTheme(
        Brightness.dark,
        prefs.accent,
        preferences: prefs,
        reducedMotion: reduced,
      ),
      home: Material(
        type: MaterialType.transparency,
        child: BridgeConnectionToast(
          username:
              definition['displayName'] as String? ??
              definition['username'] as String? ??
              'Client',
          executorName: definition['executorName'] as String? ?? '',
          reducedMotion: reduced,
          duration: Duration(
            milliseconds: duration is num
                ? duration.round().clamp(1000, 15000)
                : 4000,
          ),
          onDismiss: onClose,
        ),
      ),
    );
  }
}

/// Expressive spatial entrance, quiet timed progress, and a small asymmetrical
/// corner echo the main app without borrowing the old Orion notification UI.
class BridgeConnectionToast extends StatefulWidget {
  const BridgeConnectionToast({
    super.key,
    required this.username,
    required this.onDismiss,
    this.executorName = '',
    this.reducedMotion = false,
    this.duration = const Duration(seconds: 4),
  });
  final String username;
  final String executorName;
  final VoidCallback onDismiss;
  final bool reducedMotion;
  final Duration duration;

  @override
  State<BridgeConnectionToast> createState() => _BridgeConnectionToastState();
}

class _BridgeConnectionToastState extends State<BridgeConnectionToast>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: widget.reducedMotion
        ? const Duration(milliseconds: 120)
        : const Duration(milliseconds: 460),
    reverseDuration: widget.reducedMotion
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 220),
  );
  late final AnimationController _remaining = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  late final CurvedAnimation _spatial = CurvedAnimation(
    parent: _entrance,
    curve: OrionMotion.spatial,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _watchdog;
  bool _closing = false, _hovered = false;

  @override
  void initState() {
    super.initState();
    _remaining.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) unawaited(_dismiss());
    });
    _entrance.forward().then((_) {
      if (mounted && !_closing && !_hovered) _remaining.reverse();
    });
    // A lost owner or a pointer abandoned over the card must not leave an
    // invisible native notification worker running forever.
    _watchdog = Timer(const Duration(minutes: 1), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    _remaining.stop();
    await _entrance.reverse();
    if (mounted) widget.onDismiss();
  }

  void _hover(bool hovered) {
    _hovered = hovered;
    if (_closing) return;
    if (hovered) {
      _remaining.stop();
    } else if (_entrance.isCompleted) {
      _remaining.reverse();
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _spatial.dispose();
    _entrance.dispose();
    _remaining.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final subject = bridgeNotificationSubject(widget.executorName);
    // A desktop toast has its own backdrop. Carry the page's gradient through
    // this card while keeping it opaque against arbitrary desktop wallpaper.
    final explicitSurface = colors.opaqueSurfaceRoles.contains('elevated');
    final fill = explicitSurface
        ? colors.elevated
        : Color.lerp(colors.background, colors.elevated, .75)!;
    final gradient = explicitSurface
        ? null
        : colors.transparentSurfaces
        ? colors.backgroundGradient
        : orionSurfaceGradient(colors, base: colors.elevated, blend: .75);
    final shape = RoundedRectangleBorder(
      borderRadius: colors.glassEnabled
          ? BorderRadius.circular(24)
          : const BorderRadius.only(
              topLeft: Radius.circular(25),
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(25),
              bottomRight: Radius.circular(25),
            ),
    );
    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Semantics(
        liveRegion: true,
        label: '$bridgeNotificationTitle. $subject. ${widget.username}',
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (_, child) => Opacity(
              opacity: Curves.easeOut.transform(_entrance.value),
              child: Transform.translate(
                offset: Offset(
                  widget.reducedMotion ? 0 : (1 - _spatial.value) * 44,
                  0,
                ),
                child: Transform.scale(
                  scale: widget.reducedMotion ? 1 : .96 + .04 * _spatial.value,
                  alignment: Alignment.centerRight,
                  child: child,
                ),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 5,
              shadowColor: Colors.black.withValues(alpha: .35),
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: OrionGlassScene(
                enabled: colors.glassEnabled,
                reducedMotion: widget.reducedMotion,
                backdrop: OrionGlassBackdrop(
                  tint: colors.background,
                  authoredGradient: colors.backgroundGradient,
                  useAuthoredBackground: true,
                ),
                child: OrionGlassSurface(
                  radius: 24,
                  blur: 0,
                  tint: Colors.transparent,
                  child: Container(
                    key: const ValueKey('bridge-notification-surface'),
                    decoration: BoxDecoration(
                      color: colors.glassEnabled ? Colors.transparent : fill,
                      gradient: colors.glassEnabled ? null : gradient,
                      borderRadius: shape.borderRadius,
                      border: colors.glassEnabled
                          ? null
                          : Border.all(
                              color: colors.outline(.45),
                              width: colors.transparentSurfaces
                                  ? 1
                                  : .7 + colors.outlineStrength * .3,
                            ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: colors.accent.withValues(alpha: .15),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(18),
                                    topRight: Radius.circular(18),
                                    bottomLeft: Radius.circular(18),
                                    bottomRight: Radius.circular(5),
                                  ),
                                ),
                                child: Center(child: const OrionLogo(size: 28)),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      bridgeNotificationTitle,
                                      key: const ValueKey(
                                        'bridge-notification-title',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.3,
                                        color: colors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      subject,
                                      key: const ValueKey(
                                        'bridge-notification-subject',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.3,
                                        color: colors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.person_rounded,
                                          size: 14,
                                          color: colors.accent,
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            widget.username,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              height: 1.25,
                                              color: colors.muted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 3),
                              Align(
                                alignment: Alignment.topRight,
                                child: IconButton(
                                  tooltip: 'Dismiss',
                                  onPressed: _dismiss,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 32,
                                    height: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 17,
                                    color: colors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: AnimatedBuilder(
                            animation: _remaining,
                            builder: (_, _) => LinearProgressIndicator(
                              value: _remaining.value,
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              color: colors.accent.withValues(alpha: .65),
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
