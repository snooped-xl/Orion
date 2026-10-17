import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/monaco_editor_service.dart';
import '../theme/orion_theme.dart';

/// Positions the native Linux WebKit surface inside the Flutter editor panel.
class MonacoEditor extends StatefulWidget {
  const MonacoEditor({
    super.key,
    required this.service,
    required this.active,
    this.backgroundColor,
    this.foregroundColor,
    this.fallback,
  });
  final MonacoEditorService service;
  final bool active;
  final Color? backgroundColor, foregroundColor;
  final Widget? fallback;

  @override
  State<MonacoEditor> createState() => _MonacoEditorState();
}

class _MonacoEditorState extends State<MonacoEditor>
    with WidgetsBindingObserver {
  final _surface = GlobalKey();
  final _presentationOwner = Object();
  final _mirrorPaintBounds = ValueNotifier<Rect?>(null);
  bool _tickerEnabled = true;
  bool _windowVisible = true;
  Object? _presentation;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _windowVisible = _isWindowVisible(WidgetsBinding.instance.lifecycleState);
    widget.service.setActive(widget.active);
    widget.service.addListener(_changed);
    _updatePresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.service.initialize());
    });
  }

  bool _isWindowVisible(AppLifecycleState? state) =>
      state != AppLifecycleState.hidden &&
      state != AppLifecycleState.paused &&
      state != AppLifecycleState.detached;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _updatePresentation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasVisible = _windowVisible;
    _windowVisible = _isWindowVisible(state);
    _updatePresentation();
    if (!wasVisible && _windowVisible) widget.service.refreshLayout();
  }

  void _updatePresentation() => widget.service.setMirrorPresentationActive(
    widget.active && _tickerEnabled && _windowVisible,
    owner: _presentationOwner,
  );

  void _changed() {
    final service = widget.service;
    final next = (
      service.ready,
      service.error,
      service.visible,
      service.visualMirror,
      service.frozenPreview,
    );
    if (next != _presentation) {
      _presentation = next;
      if (mounted) setState(() {});
    }
  }

  void _measure() {
    if (!mounted) return;
    final box = _surface.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    // RenderBox.size is logical layout size; the native surface must occupy
    // its painted rectangle after viewport scaling and page transforms.
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    if (!bounds.isFinite) return;
    if (widget.service.visualMirror) {
      // GTK allocates integer logical pixels. Paint its complete image at
      // that same global rectangle, then undo UI scale in local space. Only
      // this image needs a geometry update: rebuilding the entire native
      // editor also schedules an unnecessary second bounds measurement.
      final nativeBounds = Rect.fromLTWH(
        bounds.left.floorToDouble(),
        bounds.top.floorToDouble(),
        bounds.width.ceilToDouble(),
        bounds.height.ceilToDouble(),
      );
      _mirrorPaintBounds.value = Rect.fromPoints(
        box.globalToLocal(nativeBounds.topLeft),
        box.globalToLocal(nativeBounds.bottomRight),
      );
    }
    unawaited(
      widget.service.setBounds(
        x: bounds.left,
        y: bounds.top,
        width: bounds.width,
        height: bounds.height,
      ),
    );
  }

  @override
  void didUpdateWidget(MonacoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      oldWidget.service.removeListener(_changed);
      oldWidget.service.setMirrorPresentationActive(
        false,
        owner: _presentationOwner,
      );
      widget.service.addListener(_changed);
      unawaited(widget.service.initialize());
    }
    widget.service.setActive(widget.active);
    _updatePresentation();
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    widget.service.setMirrorPresentationActive(
      false,
      owner: _presentationOwner,
    );
    WidgetsBinding.instance.removeObserver(this);
    _mirrorPaintBounds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final theme = Theme.of(context);
    final colors = theme.extension<OrionColors>();
    final background =
        widget.backgroundColor ?? colors?.panel ?? theme.colorScheme.surface;
    final foreground =
        widget.foregroundColor ??
        colors?.muted ??
        theme.colorScheme.onSurfaceVariant;
    return _EditorLayoutReporter(
      onLayout: _measure,
      child: ColoredBox(
        key: _surface,
        color: background,
        child: SizedBox.expand(
          child: widget.service.ready
              ? !widget.service.visible
                    ? widget.service.frozenPreview != null
                          ? IgnorePointer(
                              child: Image.memory(
                                widget.service.frozenPreview!,
                                key: const ValueKey('monaco-frozen-preview'),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.none,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) =>
                                    widget.fallback ?? const SizedBox.shrink(),
                              ),
                            )
                          : widget.fallback
                    : widget.service.visualMirror
                    ? RepaintBoundary(
                        child: ValueListenableBuilder<ui.Image?>(
                          valueListenable: widget.service.visualMirrorFrame,
                          builder: (context, image, _) {
                            if (image == null) return const SizedBox.shrink();
                            final service = widget.service;
                            void painted() {
                              if (mounted &&
                                  identical(service, widget.service)) {
                                service.mirrorFramePresented(image);
                              }
                            }

                            return IgnorePointer(
                              child: ValueListenableBuilder<Rect?>(
                                valueListenable: _mirrorPaintBounds,
                                child: _MirrorPaintReporter(
                                  onPainted: painted,
                                  child: RawImage(
                                    key: const ValueKey('monaco-visual-mirror'),
                                    image: image,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.none,
                                  ),
                                ),
                                builder: (context, bounds, image) => Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned.fromRect(
                                      rect: bounds ?? Rect.zero,
                                      child: image!,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : null
              : widget.service.error == null && widget.fallback != null
              ? widget.fallback
              : Center(
                  child: widget.service.error == null
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.code_off_rounded),
                              const SizedBox(height: 12),
                              Text(
                                widget.service.error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: foreground),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: widget.service.initialize,
                                child: const Text('Retry editor'),
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

/// A build/post-frame callback alone does not establish that pixels appeared:
/// an offstage child or a zero-size mirror can build without ever painting.
class _MirrorPaintReporter extends SingleChildRenderObjectWidget {
  const _MirrorPaintReporter({required this.onPainted, required super.child});
  final VoidCallback onPainted;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MirrorPaintRenderBox(onPainted);
  @override
  void updateRenderObject(
    BuildContext context,
    _MirrorPaintRenderBox renderObject,
  ) => renderObject.onPainted = onPainted;
}

class _MirrorPaintRenderBox extends RenderProxyBox {
  _MirrorPaintRenderBox(this.onPainted);
  VoidCallback onPainted;
  bool _queued = false;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_queued || size.isEmpty || !size.isFinite) return;
    _queued = true;
    final callback = onPainted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (attached) callback();
    });
  }
}

class _EditorLayoutReporter extends SingleChildRenderObjectWidget {
  const _EditorLayoutReporter({required this.onLayout, required super.child});
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _EditorLayoutRenderBox(onLayout);
  @override
  void updateRenderObject(
    BuildContext context,
    _EditorLayoutRenderBox renderObject,
  ) => renderObject.onLayout = onLayout;
}

class _EditorLayoutRenderBox extends RenderProxyBox {
  _EditorLayoutRenderBox(this.onLayout);
  VoidCallback onLayout;
  bool _queued = false;
  @override
  void performLayout() {
    super.performLayout();
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (attached) onLayout();
    });
  }
}
