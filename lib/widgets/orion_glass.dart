import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'native_desktop_glass.dart';

/// A shared, explicit backdrop for the Skia lens pipeline. The source excludes
/// foreground UI, so text stays sharp and glass never captures itself.
class OrionGlassScene extends StatefulWidget {
  const OrionGlassScene({
    super.key,
    required this.backdrop,
    required this.child,
    this.enabled = true,
    this.reducedMotion = false,
    this.pixelRatio = .75,
  });

  final Widget backdrop, child;
  final bool enabled, reducedMotion;
  final double pixelRatio;

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassScope>()?.active ??
      false;

  static Future<void> preload() => LiquidGlassShaders.ensureLoaded(false);

  @override
  State<OrionGlassScene> createState() => _OrionGlassSceneState();
}

class _OrionGlassSceneState extends State<OrionGlassScene> {
  final _capture = LiquidGlassViewController();
  final _foreground = GlobalKey();
  bool _ready = LiquidGlassShaders.isLoadedFor(false);
  Future<void>? _loading;
  bool _captureScheduled = false;
  bool _capturing = false;
  int _requestedCapture = 0;
  int _completedCapture = -1;
  Size? _size;
  bool _nativeBackdrop = false;

  @override
  void initState() {
    super.initState();
    _loadIfEnabled();
  }

  void _loadIfEnabled() {
    if (widget.enabled && !_ready && _loading == null) {
      _loading = OrionGlassScene.preload()
          .then((_) {
            if (mounted) setState(() => _ready = true);
          })
          .catchError((Object _) {
            // A shader compilation failure leaves a functional frosted material.
            // The normal Linux path is verified with real shader pixel tests.
          })
          .whenComplete(() => _loading = null);
    }
  }

  @override
  void didUpdateWidget(OrionGlassScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadIfEnabled();
    final sameBackdrop =
        oldWidget.backdrop == widget.backdrop ||
        (oldWidget.backdrop is OrionGlassBackdrop &&
            widget.backdrop is OrionGlassBackdrop &&
            (oldWidget.backdrop as OrionGlassBackdrop).tint ==
                (widget.backdrop as OrionGlassBackdrop).tint &&
            (oldWidget.backdrop as OrionGlassBackdrop).authoredGradient ==
                (widget.backdrop as OrionGlassBackdrop).authoredGradient &&
            (oldWidget.backdrop as OrionGlassBackdrop).useAuthoredBackground ==
                (widget.backdrop as OrionGlassBackdrop).useAuthoredBackground &&
            (oldWidget.backdrop as OrionGlassBackdrop).backdropOpacity ==
                (widget.backdrop as OrionGlassBackdrop).backdropOpacity &&
            (oldWidget.backdrop as OrionGlassBackdrop).child ==
                (widget.backdrop as OrionGlassBackdrop).child);
    if (!sameBackdrop ||
        oldWidget.pixelRatio != widget.pixelRatio ||
        oldWidget.enabled != widget.enabled) {
      _requestCapture();
    }
  }

  void _requestCapture() {
    _requestedCapture++;
    _scheduleCapture();
  }

  void _scheduleCapture() {
    if (!mounted ||
        !widget.enabled ||
        _nativeBackdrop ||
        !_ready ||
        _captureScheduled ||
        _capturing ||
        _completedCapture >= _requestedCapture) {
      return;
    }
    _captureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _captureScheduled = false;
      if (!mounted || !widget.enabled) return;
      _capturing = true;
      final requested = _requestedCapture;
      try {
        await _capture.captureOnce();
      } finally {
        _completedCapture = requested;
        _capturing = false;
        if (mounted && requested != _requestedCapture) _scheduleCapture();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _foreground, child: widget.child);
    final nativeBackdrop =
        widget.enabled && NativeDesktopGlassScope.isActiveOf(context);
    if (_nativeBackdrop != nativeBackdrop) {
      _nativeBackdrop = nativeBackdrop;
      // The fallback view was detached while the compositor owned the glass.
      // Refresh its texture if that companion disappears or is disabled.
      if (!nativeBackdrop) _requestCapture();
    }
    if (!widget.enabled) return content;
    if (_nativeBackdrop) {
      // The compositor refracts the actual desktop behind this GTK window.
      // Only the palette tint is translucent; labels and controls stay sharp.
      return _GlassScope(
        active: true,
        ready: false,
        nativeBackdrop: true,
        reducedMotion:
            widget.reducedMotion || MediaQuery.disableAnimationsOf(context),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: NativeDesktopGlassScope.opacityOf(context),
                  child: widget.backdrop,
                ),
              ),
            ),
            content,
          ],
        ),
      );
    }
    return _GlassScope(
      active: true,
      ready: _ready,
      reducedMotion:
          widget.reducedMotion || MediaQuery.disableAnimationsOf(context),
      child: _GlassLayoutReporter(
        onLayout: (size) {
          if (_size != size) {
            _size = size;
            _requestCapture();
          }
        },
        child: !_ready
            ? Stack(
                fit: StackFit.passthrough,
                children: [
                  Positioned.fill(child: widget.backdrop),
                  content,
                ],
              )
            : LiquidGlassView(
                controller: _capture,
                backgroundWidget: widget.backdrop,
                honorBackdropAlpha: true,
                useImpellerBackdrop: false,
                realTimeCapture: false,
                pixelRatio: widget.pixelRatio.isFinite
                    ? widget.pixelRatio.clamp(.4, 1)
                    : .75,
                useSync: true,
                // Skia already shares the captured image. Avoid a shared blur
                // backdrop ID because Orion deliberately nests some surfaces.
                batch: false,
                shrinkWrap: true,
                child: content,
              ),
      ),
    );
  }
}

class _GlassScope extends InheritedWidget {
  const _GlassScope({
    required this.active,
    required this.ready,
    required this.reducedMotion,
    this.nativeBackdrop = false,
    required super.child,
  });
  final bool active, ready, reducedMotion, nativeBackdrop;
  @override
  bool updateShouldNotify(_GlassScope oldWidget) =>
      active != oldWidget.active ||
      ready != oldWidget.ready ||
      nativeBackdrop != oldWidget.nativeBackdrop ||
      reducedMotion != oldWidget.reducedMotion;
}

class _GlassLayoutReporter extends SingleChildRenderObjectWidget {
  const _GlassLayoutReporter({required this.onLayout, required super.child});
  final ValueChanged<Size> onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _GlassLayoutBox(onLayout);
  @override
  void updateRenderObject(BuildContext context, _GlassLayoutBox renderObject) =>
      renderObject.onLayout = onLayout;
}

class _GlassLayoutBox extends RenderProxyBox {
  _GlassLayoutBox(this.onLayout);
  ValueChanged<Size> onLayout;
  @override
  void performLayout() {
    super.performLayout();
    onLayout(size);
  }
}

/// A broad refractive sheet over the scene's captured desktop-like substrate.
/// Its 1.65 IOR, 52px bend band and 2.25px frost match WindowsGlass optics.
/// Optional custom shapes clip both lens and content; their optics use a
/// conservative rectangular SDF when the corners differ.
class OrionGlassSurface extends StatefulWidget {
  const OrionGlassSurface({
    super.key,
    required this.child,
    this.enabled = true,
    this.radius = 20,
    this.tint,
    this.blur = 0,
    this.interactive = false,
    this.materialOpacity = defaultMaterialOpacity,
    this.fullSheetRefraction = false,
    this.edgeRefraction = true,
    this.showRim = true,
    this.borderRadius,
    this.shape,
  });
  final Widget child;
  final double radius, blur;
  final Color? tint;
  final bool enabled, interactive;
  static const defaultMaterialOpacity = 1.0;
  static const defaultBlur = 2.25;
  static const windowsGlassRefractionIndex = 1.65;
  static const windowsGlassRefractionWidth = 52.0;
  final double materialOpacity;

  /// Uses the broad, native-window refraction profile from WindowsGlass.
  final bool fullSheetRefraction;

  /// Bends the backdrop in a narrow bevel around this surface's edge.
  /// Disable for nested workspace panels that inherit the window's glass.
  final bool edgeRefraction;

  /// Paints the polished highlight around the surface boundary.
  final bool showRim;
  final BorderRadiusGeometry? borderRadius;
  final ShapeBorder? shape;

  /// Foreground controls on a glass sheet should use quiet tonal fills rather
  /// than another refractive sheet. Zero-opacity layout wrappers preserve the
  /// nearest real material ancestor and do not count as sheets themselves.
  static bool hasMaterialAncestor(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GlassMaterialScope>()
          ?.hasMaterial ??
      false;

  @override
  State<OrionGlassSurface> createState() => _OrionGlassSurfaceState();
}

class _GlassMaterialScope extends InheritedWidget {
  const _GlassMaterialScope({required this.hasMaterial, required super.child});
  final bool hasMaterial;

  @override
  bool updateShouldNotify(_GlassMaterialScope oldWidget) =>
      hasMaterial != oldWidget.hasMaterial;
}

class _OrionGlassSurfaceState extends State<OrionGlassSurface> {
  final _foreground = GlobalKey();
  bool _hovered = false;
  Offset _pointer = const Offset(.5, .5);
  int? _pressPointer;

  void _movePointer(Offset position) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final next = Offset(
      (position.dx / box.size.width).clamp(0, 1),
      (position.dy / box.size.height).clamp(0, 1),
    );
    // A small spatial threshold avoids restarting an animation for subpixel
    // mouse noise. Only lens uniforms change; the scene is never recaptured.
    if ((next - _pointer).distance > .025) {
      setState(() => _pointer = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GlassScope>();
    final content = KeyedSubtree(key: _foreground, child: widget.child);
    if (!widget.enabled || scope?.active != true) return content;
    if (scope!.nativeBackdrop) {
      return _GlassMaterialScope(hasMaterial: true, child: content);
    }
    final materialOpacity = widget.materialOpacity.isFinite
        ? widget.materialOpacity.clamp(0.0, 1.0)
        : OrionGlassSurface.defaultMaterialOpacity;
    final hasMaterial =
        materialOpacity > 0 || OrionGlassSurface.hasMaterialAncestor(context);
    final corners = widget.borderRadius?.resolve(Directionality.of(context));
    final radius = widget.radius.isFinite
        ? widget.radius.clamp(0.0, 256.0)
        : 20.0;
    final opticalRadius = corners == null
        ? radius
        : [
            corners.topLeft.x,
            corners.topRight.x,
            corners.bottomLeft.x,
            corners.bottomRight.x,
          ].reduce(math.min);
    final clipShape =
        widget.shape ??
        (corners == null
            ? null
            : RoundedRectangleBorder(borderRadius: corners));
    final reduced = scope.reducedMotion;
    final responds = materialOpacity > 0;
    return _GlassMaterialScope(
      hasMaterial: hasMaterial,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.interactive && responds && !reduced
            ? (event) => setState(() => _pressPointer ??= event.pointer)
            : null,
        onPointerUp: (event) {
          if (_pressPointer == event.pointer) {
            setState(() => _pressPointer = null);
          }
        },
        onPointerCancel: (event) {
          if (_pressPointer == event.pointer) {
            setState(() => _pressPointer = null);
          }
        },
        child: MouseRegion(
          onEnter: responds ? (_) => setState(() => _hovered = true) : null,
          onHover: responds && !reduced
              ? (event) => _movePointer(event.localPosition)
              : null,
          onExit: responds
              ? (_) => setState(() {
                  _hovered = false;
                  _pointer = const Offset(.5, .5);
                })
              : null,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: responds && _hovered ? 1 : 0),
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            builder: (context, hover, _) => TweenAnimationBuilder<Offset>(
              tween: Tween(end: reduced ? const Offset(.5, .5) : _pointer),
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              builder: (context, pointer, _) {
                final tint = widget.tint ?? Colors.transparent;
                final edgeWidth = widget.fullSheetRefraction
                    ? OrionGlassSurface.windowsGlassRefractionWidth
                    : widget.edgeRefraction
                    ? math.min(9.0, math.max(2.0, opticalRadius * .65))
                    : 0.0;
                final refractionIndex = widget.fullSheetRefraction
                    ? OrionGlassSurface.windowsGlassRefractionIndex
                    : widget.edgeRefraction
                    ? 1.075
                    : 1.0;
                final refractionWidth = edgeWidth;
                const lensMagnification = 1.0;
                final lightAngle =
                    -135 + (pointer.dx - .5) * 54 + (pointer.dy - .5) * 22;
                final edge = scope.ready
                    ? LiquidGlassLens(
                        useImpellerBackdrop: false,
                        // Authored glass surfaces are composited over an
                        // intentionally clear scene so refraction can sample
                        // the real desktop (or Flutter UI) behind them.
                        honorBackdropAlpha: true,
                        style: LiquidGlassStyle(
                          shape: LiquidGlassShape.continuousRoundedRectangle(
                            cornerRadius: opticalRadius,
                          ),
                          color: Colors.transparent,
                          blur: widget.blur.isFinite
                              ? widget.blur.clamp(0, 3)
                              : 0,
                          refractionIndex: refractionIndex + hover * .012,
                          refractionWidth: refractionWidth,
                          // A clear sheet has no full-surface zoom or color
                          // wash: only its curved bevel bends the scene.
                          magnification: lensMagnification,
                          dispersion: 0,
                          saturation: 1,
                          specular: widget.showRim
                              ? LiquidGlassLight.specular(
                                  thickness: 2.1,
                                  sharpness: .74,
                                  angle: lightAngle,
                                  spread: .56,
                                  intensity: 1.4 + hover * .25,
                                  oppositeIntensity: .16,
                                  color: const Color(0xe6f4f9ff),
                                )
                              : null,
                          glow: const LiquidGlassLight.glow(intensity: 0),
                        ),
                        child: const SizedBox.expand(),
                      )
                    : ClipRRect(
                        borderRadius: corners ?? BorderRadius.circular(radius),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tint,
                              borderRadius:
                                  corners ?? BorderRadius.circular(radius),
                              border: widget.showRim
                                  ? Border.all(color: const Color(0x30ffffff))
                                  : null,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      );
                final optical = Stack(
                  fit: StackFit.expand,
                  children: [
                    // One optional flat fill; no blurred or magnified copy of
                    // the backdrop is composited over the clear center.
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        shape:
                            clipShape ??
                            ContinuousRectangleBorder(
                              borderRadius: BorderRadius.circular(radius),
                            ),
                        color: tint,
                      ),
                    ),
                    if (widget.fullSheetRefraction)
                      edge
                    else
                      ClipPath(
                        clipper: _GlassEdgeClipper(
                          radius: opticalRadius,
                          width: edgeWidth,
                        ),
                        child: edge,
                      ),
                  ],
                );
                Widget surface = Stack(
                  fit: StackFit.passthrough,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: materialOpacity,
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          child: optical,
                        ),
                      ),
                    ),
                    content,
                  ],
                );
                if (clipShape != null) {
                  surface = ClipPath(
                    clipper: ShapeBorderClipper(shape: clipShape),
                    child: surface,
                  );
                }
                return AnimatedScale(
                  scale: _pressPointer == null || reduced ? 1 : .992,
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  child: surface,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Restricts the standard glass treatment to its polished bevel. Windows-style
/// full-sheet glass deliberately bypasses this inner cutout and bends the scene
/// across the entire pane.
class _GlassEdgeClipper extends CustomClipper<Path> {
  const _GlassEdgeClipper({required this.radius, required this.width});
  final double radius, width;

  @override
  Path getClip(Size size) {
    final outer = Offset.zero & size;
    final inset = math.min(width, size.shortestSide / 2);
    final inner = outer.deflate(inset);
    final result = Path()..fillType = PathFillType.evenOdd;
    result.addRect(outer);
    if (!inner.isEmpty) {
      result.addRRect(
        RRect.fromRectAndRadius(
          inner,
          Radius.circular(math.max(0, radius - inset)),
        ),
      );
    }
    return result;
  }

  @override
  bool shouldReclip(_GlassEdgeClipper oldClipper) =>
      radius != oldClipper.radius || width != oldClipper.width;
}

/// Shared by Flutter glass and the native editor's whole-window background.
/// The authored color film is composited over the platform's blurred desktop
/// material; its opacity does not fade Flutter foreground labels or controls.
class OrionGlassBackdrop extends StatelessWidget {
  const OrionGlassBackdrop({
    super.key,
    this.child,
    this.tint,
    this.authoredGradient,
    this.useAuthoredBackground = false,
    this.backdropOpacity = 1,
  });
  final Widget? child;
  final Color? tint;
  final LinearGradient? authoredGradient;
  final bool useAuthoredBackground;

  /// Fades only the background paint, keeping foreground content crisp.
  final double backdropOpacity;

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff0057ad), Color(0xff173c5e), Color(0xff49525e)],
    stops: [0, .52, 1],
  );
  static const decoration = BoxDecoration(gradient: gradient);

  static LinearGradient gradientFor(
    Color? tint, {
    LinearGradient? authoredGradient,
    bool useAuthoredBackground = false,
  }) {
    final light = tint != null && tint.computeLuminance() > .42;
    if (useAuthoredBackground) {
      Color opaque(Color color) => color.withValues(alpha: 1);
      final source = authoredGradient;
      if (source == null) {
        final solid = opaque(tint ?? const Color(0xff1b1f25));
        return LinearGradient(colors: [solid, solid]);
      }
      return LinearGradient(
        begin: source.begin,
        end: source.end,
        colors: source.colors.map(opaque).toList(),
        stops: source.stops,
        tileMode: source.tileMode,
        transform: source.transform,
      );
    }
    final source = light
        ? const [Color(0xfff1f3f7), Color(0xffe0e4eb), Color(0xfff6f7fa)]
        : gradient.colors;
    return LinearGradient(
      begin: gradient.begin,
      end: gradient.end,
      stops: gradient.stops,
      colors: [
        for (final color in source)
          tint == null
              ? color
              : Color.alphaBlend(
                  tint.withValues(alpha: .12),
                  color,
                ).withValues(alpha: 1),
      ],
    );
  }

  /// Retained for the native editor's shared backdrop contract. Authored
  /// backgrounds receive no synthetic white blooms: broad light layers reduce
  /// contrast and make clear glass look like a stack of frosted gray panels.
  static List<RadialGradient> lightsFor(Color? tint) => const [];

  @override
  Widget build(BuildContext context) {
    final opacity = backdropOpacity.isFinite
        ? backdropOpacity.clamp(0.0, 1.0)
        : 1.0;
    // A refractive lens composites a second copy of its captured backdrop over
    // the scene's already-painted backdrop. Split the requested total alpha
    // evenly across those two layers: 1 - (1 - layerOpacity)^2 = opacity.
    final layerOpacity = 1 - math.sqrt(1 - opacity);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: layerOpacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: gradientFor(
                  tint,
                  authoredGradient: authoredGradient,
                  useAuthoredBackground: useAuthoredBackground,
                ),
              ),
            ),
          ),
        ),
        for (final light in lightsFor(tint))
          Positioned.fill(
            child: Opacity(
              opacity: layerOpacity,
              child: DecoratedBox(decoration: BoxDecoration(gradient: light)),
            ),
          ),
        ?child,
      ],
    );
  }
}
