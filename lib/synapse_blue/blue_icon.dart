import 'package:flutter/material.dart';

/// Original Blue SVG paths painted directly in Flutter.
class BlueIcon extends StatelessWidget {
  const BlueIcon(
    this.name, {
    super.key,
    this.color = Colors.white,
    this.width = 60,
    this.height = 64,
  });
  final String name;
  final Color color;
  final double width, height;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, height),
    painter: _BlueIconPainter(name, color),
  );
}

class _BlueIconPainter extends CustomPainter {
  const _BlueIconPainter(this.name, this.color);
  final String name;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final glyph = _glyphs[name];
    if (glyph == null) return;
    canvas.save();
    canvas.scale(size.width / glyph.$1.width, size.height / glyph.$1.height);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in glyph.$2) {
      canvas.drawPath(path, p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlueIconPainter old) =>
      old.name != name || old.color != color;
}

final _glyphs = <String, (Size, List<Path>)>{
  'execution': (
    const Size(60, 64),
    [
      Path()
        ..moveTo(44.5, 17)
        ..lineTo(15, 31.5)
        ..lineTo(26, 35.5)
        ..moveTo(44.5, 17)
        ..lineTo(29.5, 46.5)
        ..lineTo(26, 35.5)
        ..moveTo(44.5, 17)
        ..lineTo(30.5, 30.5)
        ..lineTo(26, 35.5),
    ],
  ),
  'hub': (
    const Size(60, 64),
    [
      Path()
        ..moveTo(46.5, 28.5)
        ..lineTo(13, 28.5)
        ..moveTo(13, 45.5)
        ..lineTo(46.5, 45.5)
        ..lineTo(46.5, 23)
        ..lineTo(27, 23)
        ..lineTo(22.5, 19)
        ..lineTo(13, 19)
        ..lineTo(13, 45.5)
        ..close(),
    ],
  ),
  'console': (
    const Size(60, 64),
    [
      Path()
        ..moveTo(37.5, 22)
        ..lineTo(47, 32)
        ..lineTo(37, 41.5)
        ..moveTo(32, 20)
        ..lineTo(27.5, 43.5),
      Path()
        ..moveTo(22.5, 22)
        ..lineTo(13, 32)
        ..lineTo(22, 41.5),
    ],
  ),
  'settings': (
    const Size(60, 64),
    [
      Path()
        ..moveTo(45.5, 31.5)
        ..lineTo(15, 31.5)
        ..moveTo(45.5, 18)
        ..lineTo(15, 18)
        ..moveTo(45.5, 45)
        ..lineTo(15, 45)
        ..moveTo(35.5, 41.5)
        ..lineTo(35.5, 47.5)
        ..moveTo(19.5, 28.5)
        ..lineTo(19.5, 34.5)
        ..moveTo(41, 15)
        ..lineTo(41, 21),
    ],
  ),
  'themes': (
    const Size(60, 64),
    [
      Path()
        ..moveTo(34.0014, 33.4465)
        ..lineTo(13.4039, 50.208)
        ..cubicTo(13.0864, 50.4664, 12.7047, 50.6337, 12.2996, 50.6923)
        ..cubicTo(11.8211, 50.7614, 11.333, 50.6753, 10.907, 50.4467)
        ..lineTo(10.6691, 50.319)
        ..cubicTo(10.463, 50.2085, 10.2854, 50.0517, 10.1501, 49.861)
        ..cubicTo(9.64208, 49.1453, 9.65462, 48.1833, 10.1811, 47.481)
        ..lineTo(10.4492, 47.1233)
        ..lineTo(27.6323, 27.105)
        ..moveTo(34.0014, 33.4465)
        ..lineTo(27.6323, 27.105)
        ..moveTo(34.0014, 33.4465)
        ..lineTo(40.1873, 25.8398)
        ..moveTo(27.6323, 27.105)
        ..lineTo(35.6564, 21.5619)
        ..moveTo(35.6564, 21.5619)
        ..cubicTo(36.4554, 24.3005, 37.3311, 25.3655, 40.1873, 25.8398)
        ..moveTo(35.6564, 21.5619)
        ..cubicTo(33.8484, 15.3005, 50.8418, 12.062, 51.8155, 14.844)
        ..moveTo(40.1873, 25.8398)
        ..cubicTo(44.2367, 26.2064, 46.1409, 24.7257, 48.3212, 18.7217)
        ..cubicTo(48.5474, 18.0988, 48.9123, 17.5305, 49.3987, 17.0805)
        ..lineTo(51.8155, 14.844)
        ..moveTo(51.8155, 14.844)
        ..cubicTo(48.6794, 16.4202, 46.3462, 16.6022, 45.2033, 19.7226),
    ],
  ),
  'window': (
    const Size(32, 11),
    [
      Path()
        ..moveTo(31, 1.00007)
        ..lineTo(25.5, 8.50007)
        ..moveTo(31, 8.50007)
        ..lineTo(25.5, 1.00007),
      Path()
        ..moveTo(6, 10.0001)
        ..lineTo(1, 10.0001),
    ],
  ),
  'warning': (
    const Size(36, 36),
    [
      Path()
        ..moveTo(18, 20.5)
        ..lineTo(18, 5.5)
        ..moveTo(18, 30.5)
        ..lineTo(18, 28)
        ..moveTo(35, 18)
        ..cubicTo(35, 27.3888, 27.3888, 35, 18, 35)
        ..cubicTo(8.61116, 35, 1, 27.3888, 1, 18)
        ..cubicTo(1, 8.61116, 8.61116, 1, 18, 1)
        ..cubicTo(27.3888, 1, 35, 8.61116, 35, 18)
        ..close(),
    ],
  ),
};

final blueInitHeaderPath = Path()
  ..moveTo(16.3, 5.3)
  ..lineTo(306.3, 5.3)
  ..lineTo(306.3, 133.3)
  ..lineTo(162.8, 117.3)
  ..lineTo(16.3, 100.3)
  ..lineTo(16.3, 5.3)
  ..close();
