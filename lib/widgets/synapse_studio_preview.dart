import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app.dart' show OrionStudioPreview;
import '../models/interface_preset.dart';
import '../models/synapse_studio_theme.dart';
import '../services/synapse_theme_catalog.dart';
import '../state/orion_controller.dart';
import '../synapse_blue/synapse_blue_shell.dart';
import '../synapse_og/synapse_og_shell.dart';
import '../synapse_v3/synapse_v3_shell.dart';
import '../synapse_v3/v3_undocked_editor.dart';
import '../synapse_x/synapse_x_shell.dart';
import '../theme/orion_theme.dart';
import 'synapse_theme_surface.dart';
import 'ui_scale_viewport.dart';

/// Renders the production Flutter shells on an isolated, memory-only controller.
/// Transparent selection handles use the actual runtime elements' rectangles.
class SynapseStudioPreview extends StatefulWidget {
  const SynapseStudioPreview({
    super.key,
    required this.controller,
    required this.preset,
    required this.theme,
    required this.window,
    required this.selected,
    required this.onSelect,
    required this.onMoveStart,
    required this.onMove,
    this.onResize,
    this.onGeometryChanged,
    this.previewPage = 'editor',
    this.zoom = 1,
  });

  final OrionController controller;
  final InterfacePreset preset;
  final SynapseStudioTheme theme;
  final SynapseStudioWindowDescriptor window;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final VoidCallback onMoveStart;
  final void Function(String id, Offset delta) onMove;
  final void Function(String id, Size size)? onResize;
  final ValueChanged<Map<String, Rect>>? onGeometryChanged;
  final double zoom;
  final String previewPage;

  @override
  State<SynapseStudioPreview> createState() => _SynapseStudioPreviewState();
}

class _SynapseStudioPreviewState extends State<SynapseStudioPreview> {
  final _source = GlobalKey();
  final _canvas = GlobalKey();
  late OrionController _preview;
  Map<String, Rect> _rects = const {};
  bool _measureScheduled = false;
  String? _hovered;
  Offset? _resizeStart;
  Size? _resizeSize;
  double _resizeScale = 1;
  Offset _pan = Offset.zero;
  int? _panPointer;

  @override
  void initState() {
    super.initState();
    _preview = _PreviewController();
    _seed();
  }

  void _seed() {
    final snapshot = widget.controller.exportWindowState();
    final preferences = snapshot['interfacePreferences'];
    _preview.applyWindowState({
      ...snapshot,
      // Stored libraries can contain many images. They are irrelevant to a
      // canvas and should not be serialized into its isolated controller.
      'interfacePreferences': {
        if (preferences is Map)
          for (final entry in preferences.entries)
            if (entry.value is Map)
              entry.key: {
                for (final preference in (entry.value as Map).entries)
                  if (!const {
                    'themeStudioSavedThemes',
                    'themeStudioDraft',
                    'themeStudio',
                  }.contains(preference.key))
                    preference.key: preference.value,
              },
      },
      'bridgeClients': const [],
      // Live execution history can open the console and alter canvas geometry.
      // The design snapshot must not copy private runtime output into previews.
      'activities': const [],
      'bridgeListening': false,
      'bridgeError': null,
      'detachedDocumentIds': const [],
      'remoteLoading': false,
      'remoteLoadingMore': false,
      'busyProviders': const [],
    });
    _preview.setReducedMotion(true);
    _preview.setInterface(widget.preset);
    _preview.completeIntro();
    if (widget.preset == InterfacePreset.orion) {
      _preview.setCustomLogo(widget.controller.customLogoBytes);
    }
    _preview.updateDocumentContent(
      _preview.activeDocumentId,
      'local message = "welcome back"\nprint(message)\n\n-- Your workspace, your way.',
    );
    _syncTheme();
  }

  void _syncTheme() => _preview.applyThemeStudioState(
    widget.preset,
    document: widget.theme.toJson(),
    orionTheme: widget.preset == InterfacePreset.orion
        ? SynapseThemeCatalog.orionPreferencesForTheme(widget.theme)
        : null,
  );

  @override
  void didUpdateWidget(covariant SynapseStudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preset != widget.preset) _seed();
    if (oldWidget.preset != widget.preset ||
        oldWidget.window.id != widget.window.id ||
        oldWidget.previewPage != widget.previewPage) {
      _rects = const {};
      _hovered = null;
      _pan = Offset.zero;
      _panPointer = null;
      _resizeStart = _resizeSize = null;
    }
    if (widget.zoom <= 1) {
      _pan = Offset.zero;
      _panPointer = null;
    }
    if (!identical(oldWidget.theme, widget.theme)) {
      _syncTheme();
    }
    if (_preview.uiScale != widget.controller.uiScale) {
      _preview.setUiScale(widget.controller.uiScale);
    }
    if (_preview.orionCompactMode != widget.controller.orionCompactMode) {
      _preview.setOrionCompactMode(widget.controller.orionCompactMode);
    }
    if (_preview.orionEnlargedMode != widget.controller.orionEnlargedMode) {
      _preview.setOrionEnlargedMode(widget.controller.orionEnlargedMode);
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final canvas = _canvas.currentContext?.findRenderObject();
      if (canvas is! RenderBox || !canvas.hasSize) return;
      final found = <String, Rect>{};
      void visit(Element element) {
        if (element.widget case Offstage(offstage: true)) return;
        if (element.widget case SynapseThemeElement(
          :final windowId,
          :final elementId,
        )) {
          if (windowId == widget.window.id) {
            final box = element.findRenderObject();
            if (box is RenderBox && box.attached && box.hasSize) {
              RenderBox target = box is RenderTransform && box.child != null
                  ? box.child!
                  : box;
              final edit = widget.theme.window(windowId).elements[elementId];
              if (edit?.width != null || edit?.height != null) {
                RenderBox candidate = target;
                for (var i = 0; i < 8; i++) {
                  if (candidate is RenderPositionedBox &&
                      candidate.child != null) {
                    target = candidate.child!;
                    break;
                  }
                  RenderObject? first;
                  candidate.visitChildren((child) => first ??= child);
                  if (first is! RenderBox) break;
                  candidate = first as RenderBox;
                }
              }
              final rect = MatrixUtils.transformRect(
                target.getTransformTo(canvas),
                Offset.zero & target.size,
              );
              found[elementId] = rect;
            }
          }
        }
        element.visitChildElements(visit);
      }

      _source.currentContext?.visitChildElements(visit);
      if (!mapEquals(found, _rects)) {
        setState(() => _rects = found);
        widget.onGeometryChanged?.call(Map.unmodifiable(found));
      }
    });
  }

  Widget _shell() {
    final key = ValueKey(
      'studio-source:${widget.preset.name}:${widget.window.id}:${widget.previewPage}',
    );
    void back() {}
    if (widget.preset == InterfacePreset.synapseV3 &&
        widget.window.id == 'undockedEditor') {
      return V3UndockedEditor(
        key: key,
        controller: _preview,
        nativeWindow: false,
      );
    }
    return switch (widget.preset) {
      InterfacePreset.orion => OrionStudioPreview(
        key: key,
        controller: _preview,
        previewPage: widget.previewPage,
      ),
      InterfacePreset.synapseV3 => SynapseV3Shell(
        key: key,
        controller: _preview,
        nativeWindow: false,
        onBackToOrion: back,
        previewWindowId: widget.window.id,
      ),
      InterfacePreset.synapseBlue => SynapseBlueShell(
        key: key,
        controller: _preview,
        nativeWindow: false,
        playIntro: false,
        onBackToOrion: back,
        previewWindowId: widget.window.id,
      ),
      InterfacePreset.synapseX => SynapseXShell(
        key: key,
        controller: _preview,
        nativeWindow: false,
        playIntro: false,
        onBackToOrion: back,
        previewWindowId: widget.window.id,
      ),
      InterfacePreset.synapse2017 => SynapseOgShell(
        key: key,
        controller: _preview,
        nativeWindow: false,
        playIntro: false,
        onBackToOrion: back,
        previewWindowId: widget.window.id,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _sourceViewport(BuildContext context, Size size) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      size: size,
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
      viewInsets: EdgeInsets.zero,
      systemGestureInsets: EdgeInsets.zero,
      disableAnimations: true,
    ),
    // Orion owns its desktop frame outside its scaled route, just as the app
    // does. The standalone shells have square frames and scale the full route.
    child: widget.preset == InterfacePreset.orion
        ? _shell()
        : UiScaleViewport(scale: _preview.uiScale, child: _shell()),
  );

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    final size = SynapseThemeCatalog.windowSize(
      widget.theme,
      widget.preset,
      widget.window.id,
      compactMode:
          widget.preset == InterfacePreset.orion && _preview.orionCompactMode,
      enlargedMode:
          widget.preset == InterfacePreset.orion && _preview.orionEnlargedMode,
    );
    final elements = SynapseThemeCatalog.elements(
      widget.preset,
      widget.window.id,
    );
    final colors = OrionColors.of(context);
    return DecoratedBox(
      key: const ValueKey('studio-canvas-surface'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.elevated.withValues(alpha: .45),
          colors.background,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: CustomPaint(
          painter: _CanvasGrid(colors.outline(.12)),
          child: LayoutBuilder(
            builder: (context, available) {
              final scale =
                  math.min(
                    math.max(1, available.maxWidth - 44) / size.width,
                    math.max(1, available.maxHeight - 44) / size.height,
                  ) *
                  widget.zoom;
              final panLimit = Offset(
                math.max(0, (size.width * scale - available.maxWidth) / 2 + 24),
                math.max(
                  0,
                  (size.height * scale - available.maxHeight) / 2 + 24,
                ),
              );
              final pan = Offset(
                _pan.dx.clamp(-panLimit.dx, panLimit.dx),
                _pan.dy.clamp(-panLimit.dy, panLimit.dy),
              );
              void panBy(Offset delta) {
                final next = Offset(
                  (_pan.dx + delta.dx).clamp(-panLimit.dx, panLimit.dx),
                  (_pan.dy + delta.dy).clamp(-panLimit.dy, panLimit.dy),
                );
                if (next != _pan) setState(() => _pan = next);
              }

              return Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      onPointerDown: (event) {
                        if (widget.zoom > 1 &&
                            event.buttons == kMiddleMouseButton) {
                          _panPointer = event.pointer;
                        }
                      },
                      onPointerMove: (event) {
                        if (_panPointer == event.pointer) {
                          panBy(event.localDelta);
                        }
                      },
                      onPointerUp: (event) {
                        if (_panPointer == event.pointer) _panPointer = null;
                      },
                      onPointerCancel: (event) {
                        if (_panPointer == event.pointer) _panPointer = null;
                      },
                      child: MouseRegion(
                        cursor: widget.zoom > 1
                            ? SystemMouseCursors.grab
                            : MouseCursor.defer,
                        child: GestureDetector(
                          key: const ValueKey('studio-preview-canvas'),
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down,
                          onTap: () => widget.onSelect(null),
                          onPanUpdate: widget.zoom > 1
                              ? (details) => panBy(details.delta)
                              : null,
                          child: Center(
                            child: Transform.translate(
                              offset: pan,
                              child: Transform.scale(
                                scale: scale,
                                child: OverflowBox(
                                  minWidth: size.width,
                                  maxWidth: size.width,
                                  minHeight: size.height,
                                  maxHeight: size.height,
                                  child: SizedBox.fromSize(
                                    key: _canvas,
                                    size: size,
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0x42000000),
                                            blurRadius: 26,
                                            offset: Offset(0, 9),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Positioned.fill(
                                            child: ClipRect(
                                              child: RepaintBoundary(
                                                key: _source,
                                                child: ExcludeFocus(
                                                  child: IgnorePointer(
                                                    child: _sourceViewport(
                                                      context,
                                                      size,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          for (final element in elements)
                                            if (_rects[element.id]
                                                case final Rect rect)
                                              _handle(element, rect, colors),
                                          if (_rects[widget.selected]
                                              case final Rect rect)
                                            ..._selection(rect, colors, scale),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.zoom > 1)
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: IgnorePointer(
                        child: Container(
                          key: const ValueKey('studio-canvas-pan-hint'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.panel.withValues(alpha: .92),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.pan_tool_alt_rounded,
                                color: colors.muted,
                                size: 13,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Middle-drag to pan',
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _handle(
    SynapseStudioElementDescriptor element,
    Rect rect,
    OrionColors colors,
  ) => Positioned.fromRect(
    rect: rect,
    child: MouseRegion(
      cursor: SystemMouseCursors.move,
      onEnter: (_) => setState(() => _hovered = element.id),
      onExit: (_) {
        if (_hovered == element.id) setState(() => _hovered = null);
      },
      child: GestureDetector(
        key: ValueKey('studio-preview:${element.id}'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTap: () => widget.onSelect(element.id),
        onPanStart: (_) {
          widget.onSelect(element.id);
          widget.onMoveStart();
        },
        onPanUpdate: (details) =>
            widget.onMove(element.id, details.delta / _preview.uiScale),
        child: _hovered == element.id && widget.selected != element.id
            ? DecoratedBox(
                key: ValueKey('studio-preview-hover:${element.id}'),
                decoration: BoxDecoration(
                  color: colors.readableAccent.withValues(alpha: .055),
                  borderRadius: BorderRadius.circular(8),
                ),
              )
            : const SizedBox.expand(),
      ),
    ),
  );

  Iterable<Widget> _selection(
    Rect rect,
    OrionColors colors,
    double scale,
  ) sync* {
    final id = widget.selected!;
    final label = SynapseThemeCatalog.elements(
      widget.preset,
      widget.window.id,
    ).where((element) => element.id == id).firstOrNull?.label;
    final unit = 1 / scale;
    yield Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: CustomPaint(
          key: ValueKey('studio-preview-selection:$id'),
          painter: _SelectionOutline(colors.readableAccent, unit),
        ),
      ),
    );
    yield Positioned(
      left: rect.left + math.max(0, (rect.width - 32 * unit) / 2),
      top: rect.top - 12 * unit,
      width: 32 * unit,
      height: 24 * unit,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          key: ValueKey('studio-preview-move:$id'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => widget.onSelect(id),
          onPanStart: (_) => widget.onMoveStart(),
          onPanUpdate: (details) =>
              widget.onMove(id, details.delta / _preview.uiScale),
          child: Semantics(
            label: 'Move ${label ?? id}',
            child: Center(
              child: Container(
                width: 26 * unit,
                height: 16 * unit,
                decoration: BoxDecoration(
                  color: colors.elevated,
                  borderRadius: BorderRadius.circular(8 * unit),
                  border: Border.all(
                    color: colors.readableAccent.withValues(alpha: .65),
                    width: unit,
                  ),
                ),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 12 * unit,
                  color: colors.readableAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.onResize == null) return;
    yield Positioned(
      left: rect.right - 12 * unit,
      top: rect.bottom - 12 * unit,
      width: 24 * unit,
      height: 24 * unit,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeDownRight,
        child: GestureDetector(
          key: ValueKey('studio-preview-resize:$id'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => widget.onSelect(id),
          onPanStart: (details) {
            widget.onMoveStart();
            _resizeStart = details.globalPosition;
            _resizeSize = rect.size / _preview.uiScale;
            final canvas = _canvas.currentContext?.findRenderObject();
            _resizeScale = canvas is RenderBox
                ? (canvas.localToGlobal(const Offset(1, 0)) -
                              canvas.localToGlobal(Offset.zero))
                          .distance *
                      _preview.uiScale
                : scale * _preview.uiScale;
          },
          onPanUpdate: (details) {
            if (_resizeStart == null || _resizeSize == null) return;
            final delta =
                (details.globalPosition - _resizeStart!) / _resizeScale;
            widget.onResize!(
              id,
              Size(
                (_resizeSize!.width + delta.dx).clamp(16, 4096),
                (_resizeSize!.height + delta.dy).clamp(16, 2160),
              ),
            );
          },
          onPanEnd: (_) => _resizeStart = _resizeSize = null,
          onPanCancel: () => _resizeStart = _resizeSize = null,
          child: Semantics(
            label: 'Resize ${label ?? id}',
            child: Center(
              child: Container(
                width: 13 * unit,
                height: 13 * unit,
                decoration: BoxDecoration(
                  color: colors.elevated,
                  borderRadius: BorderRadius.circular(5 * unit),
                  border: Border.all(color: colors.readableAccent, width: unit),
                ),
                child: Icon(
                  Icons.south_east_rounded,
                  size: 9 * unit,
                  color: colors.readableAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewController extends OrionController {
  _PreviewController() : super(persistChanges: false);
  // Production hub pages can request a refresh when first mounted. A design
  // canvas uses the cloned snapshot and bundled cards without making requests.
  @override
  Future<void> searchRemoteScripts([String? query]) async {}
}

class _CanvasGrid extends CustomPainter {
  const _CanvasGrid(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 20.0; x < size.width; x += 36) {
      for (var y = 20.0; y < size.height; y += 36) {
        canvas.drawCircle(Offset(x, y), .55, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGrid oldDelegate) =>
      color != oldDelegate.color;
}

class _SelectionOutline extends CustomPainter {
  const _SelectionOutline(this.color, this.unit);
  final Color color;
  final double unit;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(.5 * unit),
        Radius.circular(math.min(9 * unit, size.shortestSide / 2)),
      ),
      Paint()
        ..color = color.withValues(alpha: .88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionOutline oldDelegate) =>
      color != oldDelegate.color || unit != oldDelegate.unit;
}
