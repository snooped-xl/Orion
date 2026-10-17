import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import 'orion_overlay.dart';

const logoOutputSize = Size(1408, 387);
const maximumLogoInputBytes = 20 * 1024 * 1024;

/// Source image placement in output-pixel coordinates, independent of UI scale.
@immutable
class LogoCropTransform {
  const LogoCropTransform({
    required this.imageSize,
    this.zoom = 1,
    this.offset = Offset.zero,
  });
  final Size imageSize;
  final double zoom;
  final Offset offset;
  double get fitScale => math.min(
    logoOutputSize.width / imageSize.width,
    logoOutputSize.height / imageSize.height,
  );
  double get fillZoom =>
      math.max(
        logoOutputSize.width / imageSize.width,
        logoOutputSize.height / imageSize.height,
      ) /
      fitScale;
  double get maximumZoom => math.max(8, fillZoom);
  Rect get destination => Rect.fromCenter(
    center: logoOutputSize.center(Offset.zero) + offset,
    width: imageSize.width * fitScale * zoom,
    height: imageSize.height * fitScale * zoom,
  );
  LogoCropTransform fit() => LogoCropTransform(imageSize: imageSize);
  LogoCropTransform fill() =>
      LogoCropTransform(imageSize: imageSize, zoom: fillZoom);
  LogoCropTransform withZoom(double value) => LogoCropTransform(
    imageSize: imageSize,
    zoom: value.isFinite ? value.clamp(.1, maximumZoom) : zoom,
    offset: offset,
  );
  LogoCropTransform moved(Offset delta) => LogoCropTransform(
    imageSize: imageSize,
    zoom: zoom,
    offset: offset + delta,
  );
}

bool _supportedImage(Uint8List data) {
  bool signature(List<int> expected, [int at = 0]) =>
      data.length >= at + expected.length &&
      List.generate(
        expected.length,
        (index) => data[at + index] == expected[index],
      ).every((value) => value);
  return signature([137, 80, 78, 71, 13, 10, 26, 10]) ||
      signature([255, 216, 255]) ||
      (signature([82, 73, 70, 70]) && signature([87, 69, 66, 80], 8));
}

Future<ui.Image> decodeLogoImage(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > maximumLogoInputBytes) {
    throw const FormatException('Choose an image smaller than 20 MB.');
  }
  if (!_supportedImage(bytes)) {
    throw const FormatException('Choose a PNG, JPEG or WebP image.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width > 16384 ||
        descriptor.height > 16384 ||
        descriptor.width * descriptor.height > 40000000) {
      throw const FormatException(
        'This image is too large. Choose a smaller image.',
      );
    }
    codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// Draw directly from the decoded source. The checkerboard and controls never
/// enter the exported PNG, and uncovered pixels retain zero alpha.
Future<Uint8List> renderLogoCrop(
  ui.Image source,
  LogoCropTransform transform,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..clipRect(Offset.zero & logoOutputSize);
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    transform.destination,
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  ui.Image? output;
  try {
    output = await picture.toImage(
      logoOutputSize.width.toInt(),
      logoOutputSize.height.toInt(),
    );
    final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('The logo could not be exported.');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    output?.dispose();
    picture.dispose();
  }
}

Future<Uint8List?> showLogoCropDialog(
  BuildContext context,
  Uint8List bytes, {
  OrionController? controller,
}) async {
  final image = await decodeLogoImage(bytes);
  try {
    if (!context.mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (!navigator.mounted) return null;
    final route = DialogRoute<Uint8List>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (_) => controller == null
          ? LogoCropDialog(image: image)
          : OrionOverlayTheme(
              controller: controller,
              builder: (_) => LogoCropDialog(image: image),
            ),
    );
    final result = await navigator.push(route);
    // The reverse transition still paints this source image after pop resolves.
    await route.completed;
    return result;
  } finally {
    image.dispose();
  }
}

class LogoCropDialog extends StatefulWidget {
  const LogoCropDialog({super.key, required this.image});
  final ui.Image image;
  @override
  State<LogoCropDialog> createState() => _LogoCropDialogState();
}

class _LogoCropDialogState extends State<LogoCropDialog> {
  final _canvasFocus = FocusNode(debugLabel: 'Position logo');
  late LogoCropTransform _transform;
  late LogoCropTransform _gestureStart;
  Offset _gesturePosition = Offset.zero;
  bool _exporting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _transform = LogoCropTransform(
      imageSize: Size(
        widget.image.width.toDouble(),
        widget.image.height.toDouble(),
      ),
    );
  }

  void _move(Offset delta) {
    if (!_exporting) setState(() => _transform = _transform.moved(delta));
  }

  Future<void> _apply() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final result = await renderLogoCrop(widget.image, _transform);
      if (mounted) Navigator.pop(context, result);
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'The logo could not be saved. Try again.';
          _exporting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _canvasFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(16),
    child: OrionOverlaySurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: math.max(
            220,
            MediaQuery.sizeOf(context).height -
                32 -
                MediaQuery.viewInsetsOf(context).vertical,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Crop logo',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    'Drag to position',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: LayoutBuilder(
                  builder: (_, constraints) => Center(
                    heightFactor: 1,
                    child: AspectRatio(
                      aspectRatio: logoOutputSize.aspectRatio,
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.arrowLeft,
                          ): () =>
                              _move(const Offset(-16, 0)),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowRight,
                          ): () =>
                              _move(const Offset(16, 0)),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowUp,
                          ): () =>
                              _move(const Offset(0, -16)),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowDown,
                          ): () =>
                              _move(const Offset(0, 16)),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowLeft,
                            shift: true,
                          ): () =>
                              _move(const Offset(-64, 0)),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowRight,
                            shift: true,
                          ): () =>
                              _move(const Offset(64, 0)),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowUp,
                            shift: true,
                          ): () =>
                              _move(const Offset(0, -64)),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowDown,
                            shift: true,
                          ): () =>
                              _move(const Offset(0, 64)),
                        },
                        child: Focus(
                          autofocus: true,
                          focusNode: _canvasFocus,
                          child: Semantics(
                            label:
                                'Logo crop area. Drag or use arrow keys to position the image.',
                            child: LayoutBuilder(
                              builder: (_, viewport) => MouseRegion(
                                cursor: SystemMouseCursors.move,
                                child: GestureDetector(
                                  key: const ValueKey('logo-crop-viewport'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _canvasFocus.requestFocus,
                                  onScaleStart: _exporting
                                      ? null
                                      : (details) {
                                          _canvasFocus.requestFocus();
                                          _gestureStart = _transform;
                                          _gesturePosition =
                                              details.localFocalPoint;
                                        },
                                  onScaleUpdate: _exporting
                                      ? null
                                      : (details) => setState(() {
                                          final delta =
                                              (details.localFocalPoint -
                                                  _gesturePosition) *
                                              (logoOutputSize.width /
                                                  viewport.maxWidth);
                                          _transform = _gestureStart
                                              .withZoom(
                                                _gestureStart.zoom *
                                                    details.scale,
                                              )
                                              .moved(delta);
                                        }),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CustomPaint(
                                      painter: _LogoCropPainter(
                                        widget.image,
                                        _transform,
                                        checkerColors: _logoCheckerPalette(
                                          context,
                                        ),
                                      ),
                                      child: const SizedBox.expand(),
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
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Size'),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('logo-crop-zoom'),
                      label: '${(_transform.zoom * 100).round()}%',
                      semanticFormatterCallback: (value) =>
                          'Logo size ${(math.exp(value) * 100).round()} percent',
                      value: math.log(_transform.zoom),
                      min: math.log(.1),
                      max: math.log(_transform.maximumZoom),
                      onChanged: _exporting
                          ? null
                          : (value) => setState(
                              () => _transform = _transform.withZoom(
                                math.exp(value),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(_transform.zoom * 100).round()}%',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const ValueKey('logo-crop-fit'),
                    icon: const Icon(Icons.fit_screen_rounded),
                    label: const Text('Fit whole image'),
                    onPressed: _exporting
                        ? null
                        : () => setState(() => _transform = _transform.fit()),
                  ),
                  TextButton.icon(
                    key: const ValueKey('logo-crop-fill'),
                    icon: const Icon(Icons.crop_rounded),
                    label: const Text('Fill frame'),
                    onPressed: _exporting
                        ? null
                        : () => setState(() => _transform = _transform.fill()),
                  ),
                ],
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _exporting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('logo-crop-apply'),
                    onPressed: _exporting ? null : _apply,
                    child: _exporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

({Color first, Color second}) _logoCheckerPalette(BuildContext context) {
  final theme = Theme.of(context), colors = theme.extension<OrionColors>();
  final base = colors?.elevated ?? theme.colorScheme.surfaceContainerHigh;
  final foreground = colors?.ink ?? theme.colorScheme.onSurface;
  final dark = theme.brightness == Brightness.dark;
  return (
    first: Color.lerp(base, foreground, dark ? .06 : .08)!,
    second: Color.lerp(base, foreground, dark ? .16 : .22)!,
  );
}

class LogoCheckerboard extends StatelessWidget {
  const LogoCheckerboard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CheckerboardPainter(_logoCheckerPalette(context)),
    child: child,
  );
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter(this.colors);
  final ({Color first, Color second}) colors;
  @override
  void paint(Canvas canvas, Size size) {
    const step = 12.0;
    final paint = Paint();
    for (var y = 0; y < size.height / step; y++) {
      for (var x = 0; x < size.width / step; x++) {
        paint.color = (x + y).isEven ? colors.first : colors.second;
        canvas.drawRect(Rect.fromLTWH(x * step, y * step, step, step), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter old) => old.colors != colors;
}

class _LogoCropPainter extends CustomPainter {
  const _LogoCropPainter(
    this.image,
    this.transform, {
    required this.checkerColors,
  });
  final ({Color first, Color second}) checkerColors;
  final ui.Image image;
  final LogoCropTransform transform;
  @override
  void paint(Canvas canvas, Size size) {
    _CheckerboardPainter(checkerColors).paint(canvas, size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(
      size.width / logoOutputSize.width,
      size.height / logoOutputSize.height,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      transform.destination,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoCropPainter old) =>
      old.image != image ||
      old.transform != transform ||
      old.checkerColors != checkerColors;
}
