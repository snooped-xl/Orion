import 'package:flutter/material.dart';

/// Exact SVG paths copied from the pinned Synapse V3 source and Microsoft Fluent.
/// They paint as native Flutter vectors, with no browser or SVG runtime.
class V3Icon extends StatelessWidget {
  const V3Icon(
    this.name, {
    super.key,
    this.size = 20,
    this.color = Colors.white,
  });
  final String name;
  final double size;
  final Color color;
  static bool contains(String name) => _v3Glyphs.containsKey(name);
  @override
  Widget build(BuildContext context) {
    assert(contains(name), 'Unknown source V3 icon: $name');
    return CustomPaint(
      size: Size.square(size),
      painter: _V3IconPainter(name, color),
    );
  }
}

class _V3Glyph {
  const _V3Glyph(
    this.size,
    this.paths, {
    this.stroke = 0,
    this.fillBeforeStroke = false,
  });
  final Size size;
  final List<Path> paths;
  final double stroke;
  final bool fillBeforeStroke;
}

class _V3IconPainter extends CustomPainter {
  _V3IconPainter(this.name, this.color);
  final String name;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final glyph = _v3Glyphs[name];
    if (glyph == null) return;
    canvas.save();
    canvas.scale(
      size.width / glyph.size.width,
      size.height / glyph.size.height,
    );
    final paint = Paint()
      ..color = color
      ..style = glyph.stroke > 0 ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = glyph.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in glyph.paths) {
      if (glyph.fillBeforeStroke) {
        paint.style = PaintingStyle.fill;
        canvas.drawPath(path, paint);
        paint.style = PaintingStyle.stroke;
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_V3IconPainter old) =>
      name != old.name || color != old.color;
}

final _v3Glyphs = <String, _V3Glyph>{
  'windowConsole20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(5.64645, 9.14645)
        ..cubicTo(5.84171, 8.95118, 6.15829, 8.95118, 6.35355, 9.14645)
        ..lineTo(8.35355, 11.1464)
        ..cubicTo(8.44732, 11.2402, 8.5, 11.3674, 8.5, 11.5)
        ..cubicTo(8.5, 11.6326, 8.44732, 11.7598, 8.35355, 11.8536)
        ..lineTo(6.35355, 13.8536)
        ..cubicTo(6.15829, 14.0488, 5.84171, 14.0488, 5.64645, 13.8536)
        ..cubicTo(5.45118, 13.6583, 5.45118, 13.3417, 5.64645, 13.1464)
        ..lineTo(7.29289, 11.5)
        ..lineTo(5.64645, 9.85355)
        ..cubicTo(5.45118, 9.65829, 5.45118, 9.34171, 5.64645, 9.14645)
        ..close()
        ..moveTo(14.5, 13)
        ..lineTo(9.5, 13)
        ..cubicTo(9.22386, 13, 9, 13.2239, 9, 13.5)
        ..cubicTo(9, 13.7761, 9.22386, 14, 9.5, 14)
        ..lineTo(14.5, 14)
        ..cubicTo(14.7761, 14, 15, 13.7761, 15, 13.5)
        ..cubicTo(15, 13.2239, 14.7761, 13, 14.5, 13)
        ..close()
        ..moveTo(2.99609, 5.5)
        ..cubicTo(2.99609, 4.11929, 4.11538, 3, 5.49609, 3)
        ..lineTo(14.4961, 3)
        ..cubicTo(15.8768, 3, 16.9961, 4.11929, 16.9961, 5.5)
        ..lineTo(16.9961, 6)
        ..lineTo(16.999, 6)
        ..lineTo(16.999, 7)
        ..lineTo(16.9961, 7)
        ..lineTo(16.9961, 14.5)
        ..cubicTo(16.9961, 15.8807, 15.8768, 17, 14.4961, 17)
        ..lineTo(5.49609, 17)
        ..cubicTo(4.11538, 17, 2.99609, 15.8807, 2.99609, 14.5)
        ..lineTo(2.99609, 5.5)
        ..close()
        ..moveTo(3.99609, 7)
        ..lineTo(3.99609, 14.5)
        ..cubicTo(3.99609, 15.3284, 4.66767, 16, 5.49609, 16)
        ..lineTo(14.4961, 16)
        ..cubicTo(15.3245, 16, 15.9961, 15.3284, 15.9961, 14.5)
        ..lineTo(15.9961, 7)
        ..lineTo(3.99609, 7)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'paintBrush20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(10, 4.49902)
        ..lineTo(10, 1.99902)
        ..lineTo(5.5, 1.99902)
        ..cubicTo(5.22386, 1.99902, 5, 2.22288, 5, 2.49902)
        ..lineTo(5, 8.99988)
        ..lineTo(15, 8.99988)
        ..lineTo(15, 2.49902)
        ..cubicTo(15, 2.22288, 14.7761, 1.99902, 14.5, 1.99902)
        ..lineTo(13, 1.99902)
        ..lineTo(13, 5.50125)
        ..cubicTo(13, 5.77739, 12.7761, 6.00125, 12.5, 6.00125)
        ..cubicTo(12.2239, 6.00125, 12, 5.77739, 12, 5.50125)
        ..lineTo(12, 1.99902)
        ..lineTo(11, 1.99902)
        ..lineTo(11, 4.49902)
        ..cubicTo(11, 4.77517, 10.7761, 4.99902, 10.5, 4.99902)
        ..cubicTo(10.2239, 4.99902, 10, 4.77517, 10, 4.49902)
        ..close()
        ..moveTo(15, 9.99988)
        ..lineTo(5, 9.99988)
        ..lineTo(5, 11.0034)
        ..cubicTo(5, 12.108, 5.89543, 13.0034, 7, 13.0034)
        ..lineTo(8.5, 13.0034)
        ..lineTo(8.5, 16.5007)
        ..cubicTo(8.5, 17.3292, 9.17157, 18.0007, 10, 18.0007)
        ..cubicTo(10.8284, 18.0007, 11.5, 17.3292, 11.5, 16.5007)
        ..lineTo(11.5, 13.0034)
        ..lineTo(13, 13.0034)
        ..cubicTo(14.1046, 13.0034, 15, 12.108, 15, 11.0034)
        ..lineTo(15, 9.99988)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'puzzlePiece20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(11, 2)
        ..cubicTo(9.89543, 2, 9, 2.89543, 9, 4)
        ..lineTo(6.5, 4)
        ..cubicTo(5.67157, 4, 5, 4.67157, 5, 5.5)
        ..lineTo(5, 8)
        ..cubicTo(3.89543, 8, 3, 8.89543, 3, 10)
        ..cubicTo(3, 11.1046, 3.89543, 12, 5, 12)
        ..lineTo(5, 14.5)
        ..cubicTo(5, 15.3284, 5.67157, 16, 6.5, 16)
        ..lineTo(9, 16)
        ..cubicTo(9, 17.1046, 9.89543, 18, 11, 18)
        ..cubicTo(12.1046, 18, 13, 17.1046, 13, 16)
        ..lineTo(15.5, 16)
        ..cubicTo(16.3284, 16, 17, 15.3284, 17, 14.5)
        ..lineTo(17, 12)
        ..lineTo(16, 12)
        ..cubicTo(14.8954, 12, 14, 11.1046, 14, 10)
        ..cubicTo(14, 8.89543, 14.8954, 8, 16, 8)
        ..lineTo(17, 8)
        ..lineTo(17, 5.5)
        ..cubicTo(17, 4.67157, 16.3284, 4, 15.5, 4)
        ..lineTo(13, 4)
        ..cubicTo(13, 2.89543, 12.1046, 2, 11, 2)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'globe20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(7.98747, 4.17997)
        ..cubicTo(7.71458, 4.84269, 7.48643, 5.62692, 7.31842, 6.5)
        ..lineTo(12.6816, 6.5)
        ..cubicTo(12.5136, 5.62692, 12.2854, 4.84269, 12.0125, 4.17997)
        ..cubicTo(11.7106, 3.44666, 11.3637, 2.88614, 11.0041, 2.51675)
        ..cubicTo(10.646, 2.14894, 10.3069, 2, 10, 2)
        ..cubicTo(9.69311, 2, 9.35398, 2.14894, 8.99591, 2.51675)
        ..cubicTo(8.6363, 2.88614, 8.28942, 3.44666, 7.98747, 4.17997)
        ..close()
        ..moveTo(7.89053, 2.28104)
        ..cubicTo(7.57693, 2.70725, 7.30036, 3.22224, 7.06279, 3.79922)
        ..cubicTo(6.74205, 4.57814, 6.48315, 5.49258, 6.3012, 6.5)
        ..lineTo(2.80423, 6.5)
        ..cubicTo(3.80285, 4.45074, 5.65108, 2.89163, 7.89053, 2.28104)
        ..close()
        ..moveTo(12.1095, 2.28105)
        ..cubicTo(12.4231, 2.70725, 12.6996, 3.22225, 12.9372, 3.79922)
        ..cubicTo(13.2579, 4.57814, 13.5169, 5.49258, 13.6988, 6.5)
        ..lineTo(17.1958, 6.5)
        ..cubicTo(16.1972, 4.45074, 14.3489, 2.89163, 12.1095, 2.28105)
        ..close()
        ..moveTo(17.6016, 7.5)
        ..lineTo(13.85, 7.5)
        ..cubicTo(13.9479, 8.2949, 14, 9.13416, 14, 10)
        ..cubicTo(14, 10.8658, 13.9479, 11.7051, 13.85, 12.5)
        ..lineTo(17.6016, 12.5)
        ..cubicTo(17.8601, 11.7135, 18, 10.8731, 18, 10)
        ..cubicTo(18, 9.12694, 17.8601, 8.28655, 17.6016, 7.5)
        ..close()
        ..moveTo(17.1958, 13.5)
        ..lineTo(13.6988, 13.5)
        ..cubicTo(13.5169, 14.5074, 13.2579, 15.4219, 12.9372, 16.2008)
        ..cubicTo(12.6996, 16.7778, 12.4231, 17.2928, 12.1095, 17.719)
        ..cubicTo(14.3489, 17.1084, 16.1972, 15.5493, 17.1958, 13.5)
        ..close()
        ..moveTo(10, 18)
        ..cubicTo(10.3069, 18, 10.646, 17.8511, 11.0041, 17.4832)
        ..cubicTo(11.3637, 17.1139, 11.7106, 16.5533, 12.0125, 15.82)
        ..cubicTo(12.2854, 15.1573, 12.5136, 14.3731, 12.6816, 13.5)
        ..lineTo(7.31842, 13.5)
        ..cubicTo(7.48643, 14.3731, 7.71458, 15.1573, 7.98747, 15.82)
        ..cubicTo(8.28942, 16.5533, 8.6363, 17.1139, 8.99591, 17.4832)
        ..cubicTo(9.35398, 17.8511, 9.69311, 18, 10, 18)
        ..close()
        ..moveTo(7.89053, 17.719)
        ..cubicTo(5.65107, 17.1084, 3.80285, 15.5493, 2.80423, 13.5)
        ..lineTo(6.3012, 13.5)
        ..cubicTo(6.48315, 14.5074, 6.74205, 15.4219, 7.06279, 16.2008)
        ..cubicTo(7.30036, 16.7778, 7.57693, 17.2928, 7.89053, 17.719)
        ..close()
        ..moveTo(2.39838, 12.5)
        ..lineTo(6.14996, 12.5)
        ..cubicTo(6.0521, 11.7051, 6, 10.8658, 6, 10)
        ..cubicTo(6, 9.13416, 6.0521, 8.2949, 6.14996, 7.5)
        ..lineTo(2.39838, 7.5)
        ..cubicTo(2.13985, 8.28655, 2, 9.12694, 2, 10)
        ..cubicTo(2, 10.8731, 2.13985, 11.7135, 2.39838, 12.5)
        ..close()
        ..moveTo(7, 10)
        ..cubicTo(7, 9.1253, 7.0557, 8.28549, 7.15793, 7.5)
        ..lineTo(12.8421, 7.5)
        ..cubicTo(12.9443, 8.28549, 13, 9.1253, 13, 10)
        ..cubicTo(13, 10.8747, 12.9443, 11.7145, 12.8421, 12.5)
        ..lineTo(7.15793, 12.5)
        ..cubicTo(7.0557, 11.7145, 7, 10.8747, 7, 10)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'play20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(17.222, 8.685)
        ..arcToPoint(
          Offset(17.222, 11.313),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(7.222, 16.811)
        ..arcToPoint(
          Offset(5, 15.496),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(5, 4.502)
        ..arcToPoint(
          Offset(7.223, 3.188),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'eraser20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(11.197, 2.44)
        ..arcToPoint(
          Offset(13.318, 2.44),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(17.561, 6.682)
        ..arcToPoint(
          Offset(17.561, 8.803),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(9.364, 17)
        ..lineTo(14.5, 17)
        ..arcToPoint(
          Offset(14.5, 18),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: true,
          clockwise: true,
        )
        ..lineTo(7.82, 18)
        ..arcToPoint(
          Offset(6.68, 17.563),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(2.437, 13.32)
        ..arcToPoint(
          Offset(2.437, 11.199),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close()
        ..moveTo(9.781, 15.168)
        ..lineTo(4.831, 10.218)
        ..lineTo(3.144, 11.905)
        ..arcToPoint(
          Offset(3.144, 12.612),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(7.387, 16.855)
        ..arcToPoint(
          Offset(8.094, 16.855),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'documentArrowUp20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(10, 2)
        ..lineTo(10, 6.5)
        ..arcToPoint(
          Offset(11.5, 8),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(16, 8)
        ..lineTo(16, 16.5)
        ..arcToPoint(
          Offset(14.5, 18),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(9.743, 18)
        ..arcToPoint(
          Offset(4, 9.207),
          radius: Radius.elliptical(5.5, 5.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(4, 3.5)
        ..arcToPoint(
          Offset(5.5, 2),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close()
        ..moveTo(11, 2.25)
        ..lineTo(11, 6.5)
        ..arcToPoint(
          Offset(11.5, 7),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(15.75, 7)
        ..close()
        ..moveTo(5.5, 19)
        ..arcToPoint(
          Offset(5.5, 10),
          radius: Radius.elliptical(4.5, 4.5),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..arcToPoint(
          Offset(5.5, 19),
          radius: Radius.elliptical(4.5, 4.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..moveTo(7.854, 14.147)
        ..arcToPoint(
          Offset(7.146, 14.854),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: true,
          clockwise: true,
        )
        ..lineTo(6, 13.707)
        ..lineTo(6, 16.5)
        ..arcToPoint(
          Offset(5, 16.5),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(5, 13.707)
        ..lineTo(3.854, 14.854)
        ..arcToPoint(
          Offset(3.146, 14.147),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: true,
          clockwise: true,
        )
        ..lineTo(5.146, 12.147)
        ..arcToPoint(
          Offset(5.497, 12),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(5.503, 12)
        ..arcToPoint(
          Offset(5.851, 12.144),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(5.854, 12.147)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'settings20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(1.911, 7.383)
        ..arcToPoint(
          Offset(3.691, 4.303),
          radius: Radius.elliptical(8.5, 8.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(4.231, 4.168),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(6.149, 4.854)
        ..arcToPoint(
          Offset(7.469, 4.092),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(7.835, 2.086)
        ..arcToPoint(
          Offset(8.223, 1.686),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(11.777, 1.686),
          radius: Radius.elliptical(8.5, 8.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(12.165, 2.086),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(12.531, 4.092)
        ..arcToPoint(
          Offset(13.851, 4.854),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(15.77, 4.168)
        ..arcToPoint(
          Offset(16.31, 4.304),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(18.09, 7.383),
          radius: Radius.elliptical(8.5, 8.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(17.937, 7.918),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(16.382, 9.238)
        ..arcToPoint(
          Offset(16.382, 10.762),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(17.937, 12.082)
        ..arcToPoint(
          Offset(18.089, 12.617),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(16.309, 15.697),
          radius: Radius.elliptical(8.5, 8.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(15.769, 15.832),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(13.851, 15.146)
        ..arcToPoint(
          Offset(12.531, 15.908),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(12.165, 17.915)
        ..arcToPoint(
          Offset(11.777, 18.314),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(8.223, 18.314),
          radius: Radius.elliptical(8.5, 8.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(7.835, 17.914),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(7.469, 15.908)
        ..arcToPoint(
          Offset(6.149, 15.146),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(4.231, 15.832)
        ..arcToPoint(
          Offset(3.691, 15.696),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(1.911, 12.617),
          radius: Radius.elliptical(8.5, 8.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(2.063, 12.082),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(3.618, 10.762)
        ..arcToPoint(
          Offset(3.618, 9.238),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(2.063, 7.918)
        ..arcToPoint(
          Offset(1.911, 7.383),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..moveTo(8.001, 10)
        ..arcToPoint(
          Offset(12.001, 10),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..arcToPoint(
          Offset(8.001, 10),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        ),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'save20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(3, 5)
        ..arcToPoint(
          Offset(5, 3),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(6, 3)
        ..lineTo(6, 6.5)
        ..arcToPoint(
          Offset(7.5, 8),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(11.5, 8)
        ..arcToPoint(
          Offset(13, 6.5),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(13, 3)
        ..lineTo(13.379, 3)
        ..arcToPoint(
          Offset(14.793, 3.586),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(16.414, 5.207)
        ..arcToPoint(
          Offset(17, 6.621),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(17, 15)
        ..arcToPoint(
          Offset(15, 17),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(15, 11.5)
        ..arcToPoint(
          Offset(13.5, 10),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(6.5, 10)
        ..arcToPoint(
          Offset(5, 11.5),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(5, 17)
        ..arcToPoint(
          Offset(3, 15),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close()
        ..moveTo(12, 3)
        ..lineTo(7, 3)
        ..lineTo(7, 6.5)
        ..arcToPoint(
          Offset(7.5, 7),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(11.5, 7)
        ..arcToPoint(
          Offset(12, 6.5),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close()
        ..moveTo(14, 11.5)
        ..lineTo(14, 17)
        ..lineTo(6, 17)
        ..lineTo(6, 11.5)
        ..arcToPoint(
          Offset(6.5, 11),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(13.5, 11)
        ..arcToPoint(
          Offset(14, 11.5),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        ),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'pulseSquare20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(8.97, 6.332)
        ..arcToPoint(
          Offset(8.032, 6.324),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(6.654, 10)
        ..lineTo(5.5, 10)
        ..arcToPoint(
          Offset(5.5, 11),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(7, 11)
        ..arcToPoint(
          Offset(7.468, 10.676),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(8.488, 7.955)
        ..lineTo(10.529, 13.668)
        ..arcToPoint(
          Offset(11.447, 13.724),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(12.81, 11)
        ..lineTo(14.5, 11)
        ..arcToPoint(
          Offset(14.5, 10),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(12.5, 10)
        ..arcToPoint(
          Offset(12.053, 10.276),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(11.077, 12.228)
        ..close()
        ..moveTo(5, 3)
        ..arcToPoint(
          Offset(3, 5),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(3, 15)
        ..arcToPoint(
          Offset(5, 17),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(15, 17)
        ..arcToPoint(
          Offset(17, 15),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(17, 5)
        ..arcToPoint(
          Offset(15, 3),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close()
        ..moveTo(4, 5)
        ..arcToPoint(
          Offset(5, 4),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(15, 4)
        ..arcToPoint(
          Offset(16, 5),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(16, 15)
        ..arcToPoint(
          Offset(15, 16),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(5, 16)
        ..arcToPoint(
          Offset(4, 15),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'searchSquare20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(9, 12.5)
        ..cubicTo(9.786, 12.5, 10.512, 12.24, 11.096, 11.803)
        ..lineTo(13.646, 14.353)
        ..arcToPoint(
          Offset(14.354, 13.646),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..lineTo(11.804, 11.096)
        ..arcToPoint(
          Offset(9, 12.5),
          radius: Radius.elliptical(3.5, 3.5),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..moveTo(9, 11.5)
        ..arcToPoint(
          Offset(9, 6.5),
          radius: Radius.elliptical(2.5, 2.5),
          rotation: 0,
          largeArc: true,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(9, 11.5),
          radius: Radius.elliptical(2.5, 2.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..moveTo(6, 3)
        ..arcToPoint(
          Offset(3, 6),
          radius: Radius.elliptical(3, 3),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(3, 14)
        ..arcToPoint(
          Offset(6, 17),
          radius: Radius.elliptical(3, 3),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(14, 17)
        ..arcToPoint(
          Offset(17, 14),
          radius: Radius.elliptical(3, 3),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(17, 6)
        ..arcToPoint(
          Offset(14, 3),
          radius: Radius.elliptical(3, 3),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close()
        ..moveTo(4, 6)
        ..arcToPoint(
          Offset(6, 4),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(14, 4)
        ..arcToPoint(
          Offset(16, 6),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(16, 14)
        ..arcToPoint(
          Offset(14, 16),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(6, 16)
        ..arcToPoint(
          Offset(4, 14),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'bot20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(14.69, 11.503)
        ..cubicTo(15.69, 11.503, 16.5, 12.313, 16.5, 13.313)
        ..lineTo(16.5, 14.002)
        ..lineTo(16.495, 14.002)
        ..cubicTo(16.461, 14.782, 16.247, 15.759, 15.372, 16.557)
        ..cubicTo(14.416, 17.43, 12.765, 18, 10, 18)
        ..cubicTo(7.234, 18, 5.584, 17.43, 4.628, 16.557)
        ..cubicTo(3.753, 15.759, 3.539, 14.781, 3.505, 14.002)
        ..lineTo(3.5, 14.002)
        ..lineTo(3.5, 13.312)
        ..cubicTo(3.5, 12.313, 4.31, 11.503, 5.31, 11.503)
        ..close()
        ..moveTo(6.5, 3)
        ..arcToPoint(
          Offset(5, 4.5),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(5, 8.5)
        ..arcToPoint(
          Offset(6.5, 10),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(13.5, 10)
        ..arcToPoint(
          Offset(15, 8.5),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(15, 4.5)
        ..arcToPoint(
          Offset(13.5, 3),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(10.5, 3)
        ..lineTo(10.5, 2.5)
        ..arcToPoint(
          Offset(10, 2),
          radius: Radius.elliptical(0.48, 0.48),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..cubicTo(9.724, 2, 9.5, 2.23, 9.5, 2.5)
        ..lineTo(9.5, 3)
        ..close()
        ..moveTo(7, 6.5)
        ..arcToPoint(
          Offset(9, 6.5),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: true,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(7, 6.5),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..moveTo(11, 6.5)
        ..arcToPoint(
          Offset(13, 6.5),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: true,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(11, 6.5),
          radius: Radius.elliptical(1, 1),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        ),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'plugConnected20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(17.78, 3.28)
        ..arcToPoint(
          Offset(16.72, 2.22),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(14.274, 4.665)
        ..arcToPoint(
          Offset(9.146, 5.146),
          radius: Radius.elliptical(4.04, 4.04),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(8.846, 5.446)
        ..arcToPoint(
          Offset(8.846, 7.554),
          radius: Radius.elliptical(1.49, 1.49),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(12.446, 11.154)
        ..arcToPoint(
          Offset(14.553, 11.154),
          radius: Radius.elliptical(1.49, 1.49),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(14.853, 10.854)
        ..arcToPoint(
          Offset(15.335, 5.726),
          radius: Radius.elliptical(4.04, 4.04),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close()
        ..moveTo(7.554, 8.846)
        ..arcToPoint(
          Offset(5.447, 8.846),
          radius: Radius.elliptical(1.49, 1.49),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(5.147, 9.146)
        ..arcToPoint(
          Offset(4.666, 14.274),
          radius: Radius.elliptical(4.04, 4.04),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(2.22, 16.72)
        ..arcToPoint(
          Offset(3.28, 17.78),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..lineTo(5.726, 15.334)
        ..arcToPoint(
          Offset(10.854, 14.854),
          radius: Radius.elliptical(4.04, 4.04),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(11.154, 14.554)
        ..arcToPoint(
          Offset(11.154, 12.446),
          radius: Radius.elliptical(1.49, 1.49),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'plugDisconnected20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(17.78, 2.22)
        ..arcToPoint(
          Offset(17.78, 3.28),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(16.335, 4.726)
        ..arcToPoint(
          Offset(15.854, 9.853),
          radius: Radius.elliptical(4.04, 4.04),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(15.554, 10.153)
        ..lineTo(15.551, 10.156)
        ..lineTo(15.242, 10.465)
        ..arcToPoint(
          Offset(13.758, 10.465),
          radius: Radius.elliptical(1.05, 1.05),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(9.535, 6.242)
        ..arcToPoint(
          Offset(9.535, 4.757),
          radius: Radius.elliptical(1.05, 1.05),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(10.146, 4.147)
        ..quadraticBezierTo(10.409, 3.885, 10.703, 3.681)
        ..arcToPoint(
          Offset(15.274, 3.665),
          radius: Radius.elliptical(4.04, 4.04),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(16.72, 2.22)
        ..arcToPoint(
          Offset(17.78, 2.22),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..moveTo(8.78, 8.47)
        ..arcToPoint(
          Offset(8.78, 9.53),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(7.51, 10.802)
        ..lineTo(9.2, 12.492)
        ..lineTo(10.47, 11.22)
        ..arcToPoint(
          Offset(11.531, 12.28),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: true,
          clockwise: true,
        )
        ..lineTo(10.255, 13.557)
        ..arcToPoint(
          Offset(10.155, 15.554),
          radius: Radius.elliptical(1.49, 1.49),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(9.855, 15.854)
        ..arcToPoint(
          Offset(4.727, 16.334),
          radius: Radius.elliptical(4.04, 4.04),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(3.28, 17.78)
        ..arcToPoint(
          Offset(2.22, 16.72),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(3.665, 15.274)
        ..arcToPoint(
          Offset(4.146, 10.147),
          radius: Radius.elliptical(4.04, 4.04),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(4.446, 9.847)
        ..arcToPoint(
          Offset(6.443, 9.747),
          radius: Radius.elliptical(1.49, 1.49),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(7.72, 8.47)
        ..arcToPoint(
          Offset(8.78, 8.47),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        ),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'hardDrive20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(4, 10)
        ..cubicTo(3.412, 10, 2.864, 10.169, 2.401, 10.461)
        ..lineTo(4.651, 5.212)
        ..arcToPoint(
          Offset(6.489, 4),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(13.593, 4)
        ..cubicTo(14.335, 4, 15.023, 4.41, 15.356, 5.088)
        ..cubicTo(15.9, 6.194, 16.886, 8.295, 17.689, 10.52)
        ..arcToPoint(
          Offset(16, 10),
          radius: Radius.elliptical(3, 3),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close()
        ..moveTo(16, 11)
        ..arcToPoint(
          Offset(18, 13),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(18, 14)
        ..arcToPoint(
          Offset(16, 16),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(3.987, 16)
        ..arcToPoint(
          Offset(2, 14),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(2, 13)
        ..arcToPoint(
          Offset(4, 11),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close()
        ..moveTo(15.5, 14.25)
        ..arcToPoint(
          Offset(15.5, 12.75),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..arcToPoint(
          Offset(15.5, 14.25),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        ),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'bookmark20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(4, 4.5)
        ..arcToPoint(
          Offset(6.5, 2),
          radius: Radius.elliptical(2.5, 2.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(13.5, 2)
        ..arcToPoint(
          Offset(16, 4.5),
          radius: Radius.elliptical(2.5, 2.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(16, 17.5)
        ..arcToPoint(
          Offset(15.206, 17.904),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(10, 14.118)
        ..lineTo(4.794, 17.904)
        ..arcToPoint(
          Offset(4, 17.5),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'document20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(10, 2)
        ..lineTo(10, 6.5)
        ..arcToPoint(
          Offset(11.5, 8),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(16, 8)
        ..lineTo(16, 16.5)
        ..arcToPoint(
          Offset(14.5, 18),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(5.5, 18)
        ..arcToPoint(
          Offset(4, 16.5),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(4, 3.5)
        ..arcToPoint(
          Offset(5.5, 2),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..close()
        ..moveTo(11, 2.25)
        ..lineTo(11, 6.5)
        ..arcToPoint(
          Offset(11.5, 7),
          radius: Radius.elliptical(0.5, 0.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(15.75, 7)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'textAsterisk20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(10.6, 2.5)
        ..arcToPoint(
          Offset(9.4, 2.5),
          radius: Radius.elliptical(0.6, 0.6),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..lineTo(9.4, 8.552)
        ..lineTo(5.121, 4.272)
        ..arcToPoint(
          Offset(4.273, 5.122),
          radius: Radius.elliptical(0.6, 0.6),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..lineTo(8.552, 9.4)
        ..lineTo(2.5, 9.4)
        ..arcToPoint(
          Offset(2.5, 10.6),
          radius: Radius.elliptical(0.6, 0.6),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..lineTo(8.552, 10.6)
        ..lineTo(4.273, 14.88)
        ..arcToPoint(
          Offset(5.122, 15.728),
          radius: Radius.elliptical(0.6, 0.6),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(9.4, 11.449)
        ..lineTo(9.4, 17.5)
        ..arcToPoint(
          Offset(10.6, 17.5),
          radius: Radius.elliptical(0.6, 0.6),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..lineTo(10.6, 11.45)
        ..lineTo(14.88, 15.729)
        ..arcToPoint(
          Offset(15.728, 14.88),
          radius: Radius.elliptical(0.6, 0.6),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(11.449, 10.6)
        ..lineTo(17.5, 10.6)
        ..arcToPoint(
          Offset(17.5, 9.4),
          radius: Radius.elliptical(0.6, 0.6),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..lineTo(11.45, 9.4)
        ..lineTo(15.728, 5.121)
        ..arcToPoint(
          Offset(14.88, 4.273),
          radius: Radius.elliptical(0.6, 0.6),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(10.6, 8.552)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'star24Filled': _V3Glyph(
    Size(24, 24),
    [
      Path()
        ..moveTo(10.788, 3.102)
        ..cubicTo(11.283, 2.099, 12.714, 2.099, 13.209, 3.102)
        ..lineTo(15.567, 7.88)
        ..lineTo(20.84, 8.646)
        ..cubicTo(21.947, 8.806, 22.389, 10.168, 21.588, 10.949)
        ..lineTo(17.772, 14.668)
        ..lineTo(18.673, 19.918)
        ..cubicTo(18.863, 21.022, 17.705, 21.863, 16.714, 21.342)
        ..lineTo(11.998, 18.862)
        ..lineTo(7.283, 21.342)
        ..cubicTo(6.293, 21.862, 5.135, 21.022, 5.323, 19.919)
        ..lineTo(6.224, 14.668)
        ..lineTo(2.409, 10.948)
        ..cubicTo(1.608, 10.168, 2.05, 8.807, 3.157, 8.646)
        ..lineTo(8.43, 7.88)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'github24': _V3Glyph(
    Size(24, 24),
    [
      Path()
        ..moveTo(12.026, 2)
        ..arcToPoint(
          Offset(8.873, 21.439),
          radius: Radius.elliptical(9.975, 9.975),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..cubicTo(9.373, 21.529, 9.552, 21.222, 9.552, 20.958)
        ..cubicTo(9.552, 20.721, 9.544, 20.093, 9.541, 19.258)
        ..cubicTo(6.766, 19.858, 6.18, 17.92, 6.18, 17.92)
        ..arcToPoint(
          Offset(5.073, 16.461),
          radius: Radius.elliptical(2.635, 2.635),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..cubicTo(4.173, 15.842, 5.142, 15.856, 5.142, 15.856)
        ..cubicTo(5.782, 15.944, 6.347, 16.323, 6.669, 16.884)
        ..arcToPoint(
          Offset(9.569, 17.713),
          radius: Radius.elliptical(2.124, 2.124),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..cubicTo(9.615, 17.207, 9.841, 16.734, 10.204, 16.379)
        ..cubicTo(7.99, 16.128, 5.662, 15.272, 5.662, 11.449)
        ..arcToPoint(
          Offset(6.688, 8.778),
          radius: Radius.elliptical(3.865, 3.865),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(6.788, 6.138),
          radius: Radius.elliptical(3.588, 3.588),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..cubicTo(6.788, 6.138, 7.625, 5.869, 9.53, 7.159)
        ..arcToPoint(
          Offset(14.522, 7.159),
          radius: Radius.elliptical(9.439, 9.439),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..cubicTo(16.428, 5.868, 17.264, 6.138, 17.264, 6.138)
        ..cubicTo(17.634, 6.973, 17.669, 7.918, 17.364, 8.778)
        ..arcToPoint(
          Offset(18.388, 11.453),
          radius: Radius.elliptical(3.84, 3.84),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..cubicTo(18.388, 15.286, 16.058, 16.128, 13.836, 16.375)
        ..cubicTo(14.316, 16.865, 14.561, 17.537, 14.511, 18.221)
        ..cubicTo(14.511, 19.555, 14.499, 20.631, 14.499, 20.958)
        ..cubicTo(14.499, 21.225, 14.677, 21.535, 15.186, 21.437)
        ..arcToPoint(
          Offset(12.026, 2),
          radius: Radius.elliptical(9.975, 9.975),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'arrowClockwise20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(4, 10)
        ..arcToPoint(
          Offset(13.969, 5.5),
          radius: Radius.elliptical(6, 6),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(12.75, 5.5)
        ..arcToPoint(
          Offset(12.75, 7),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(15.75, 7)
        ..arcToPoint(
          Offset(16.5, 6.25),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(16.5, 3.25)
        ..arcToPoint(
          Offset(15, 3.25),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(15, 4.41)
        ..arcToPoint(
          Offset(17.495, 9.723),
          radius: Radius.elliptical(7.5, 7.5),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..arcToPoint(
          Offset(15.995, 9.777),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..quadraticBezierTo(16.001, 9.887, 16, 10)
        ..arcToPoint(
          Offset(4, 10),
          radius: Radius.elliptical(6, 6),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        ),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'eye20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(10, 3.5)
        ..cubicTo(5.305, 3.5, 1.5, 7.305, 1.5, 12)
        ..cubicTo(1.5, 16.695, 5.305, 20.5, 10, 20.5)
        ..cubicTo(14.695, 20.5, 18.5, 16.695, 18.5, 12)
        ..cubicTo(18.5, 7.305, 14.695, 3.5, 10, 3.5)
        ..moveTo(10, 17)
        ..arcToPoint(
          Offset(10, 7),
          radius: Radius.elliptical(5, 5),
          rotation: 0,
          largeArc: true,
          clockwise: true,
        )
        ..arcToPoint(
          Offset(10, 17),
          radius: Radius.elliptical(5, 5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..moveTo(10, 14.5)
        ..arcToPoint(
          Offset(10, 9.5),
          radius: Radius.elliptical(2.5, 2.5),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..arcToPoint(
          Offset(10, 14.5),
          radius: Radius.elliptical(2.5, 2.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        ),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'folderLink20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(10.5, 3)
        ..lineTo(6.914, 3)
        ..arcToPoint(
          Offset(5.854, 3.44),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(5.44, 4.854)
        ..arcToPoint(
          Offset(4.378, 5.5),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(3.5, 5.5)
        ..arcToPoint(
          Offset(2, 7),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(2, 15.5)
        ..arcToPoint(
          Offset(3.5, 17),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(16.5, 17)
        ..arcToPoint(
          Offset(18, 15.5),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(18, 7.5)
        ..arcToPoint(
          Offset(16.5, 6),
          radius: Radius.elliptical(1.5, 1.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(11, 6)
        ..lineTo(10.5, 3)
        ..moveTo(15, 8.5)
        ..lineTo(15, 14.5)
        ..lineTo(4, 14.5)
        ..lineTo(4, 7.5)
        ..lineTo(16, 7.5),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'arrowSync20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(3.5, 10)
        ..arcToPoint(
          Offset(14.219, 5.022),
          radius: Radius.elliptical(6.5, 6.5),
          rotation: 0,
          largeArc: false,
          clockwise: true,
        )
        ..lineTo(11.75, 5.022)
        ..arcToPoint(
          Offset(11.75, 6.522),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(14.75, 6.522)
        ..arcToPoint(
          Offset(15.5, 5.772),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(15.5, 2.772)
        ..arcToPoint(
          Offset(14, 2.772),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(14, 3.932)
        ..arcToPoint(
          Offset(18.5, 10),
          radius: Radius.elliptical(8, 8),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..arcToPoint(
          Offset(17, 10),
          radius: Radius.elliptical(0.75, 0.75),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        ),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'desktop20Filled': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(4.25, 2)
        ..cubicTo(3.00736, 2, 2, 3.00736, 2, 4.25)
        ..lineTo(2, 13.75)
        ..cubicTo(2, 14.9926, 3.00736, 16, 4.25, 16)
        ..lineTo(8.5, 16)
        ..lineTo(8.5, 18)
        ..lineTo(6.75, 18)
        ..cubicTo(6.33579, 18, 6, 18.3358, 6, 18.75)
        ..cubicTo(6, 19.1642, 6.33579, 19.5, 6.75, 19.5)
        ..lineTo(13.25, 19.5)
        ..cubicTo(13.6642, 19.5, 14, 19.1642, 14, 18.75)
        ..cubicTo(14, 18.3358, 13.6642, 18, 13.25, 18)
        ..lineTo(11.5, 18)
        ..lineTo(11.5, 16)
        ..lineTo(15.75, 16)
        ..cubicTo(16.9926, 16, 18, 14.9926, 18, 13.75)
        ..lineTo(18, 4.25)
        ..cubicTo(18, 3.00736, 16.9926, 2, 15.75, 2)
        ..lineTo(4.25, 2)
        ..close()
        ..moveTo(3.5, 4.25)
        ..cubicTo(3.5, 3.83579, 3.83579, 3.5, 4.25, 3.5)
        ..lineTo(15.75, 3.5)
        ..cubicTo(16.1642, 3.5, 16.5, 3.83579, 16.5, 4.25)
        ..lineTo(16.5, 13.75)
        ..cubicTo(16.5, 14.1642, 16.1642, 14.5, 15.75, 14.5)
        ..lineTo(4.25, 14.5)
        ..cubicTo(3.83579, 14.5, 3.5, 14.1642, 3.5, 13.75)
        ..lineTo(3.5, 4.25)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'add20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(10, 2.5)
        ..cubicTo(10.2761, 2.5, 10.5, 2.72386, 10.5, 3)
        ..lineTo(10.5, 9.5)
        ..lineTo(17, 9.5)
        ..cubicTo(17.2761, 9.5, 17.5, 9.72386, 17.5, 10)
        ..cubicTo(17.5, 10.2761, 17.2761, 10.5, 17, 10.5)
        ..lineTo(10.5, 10.5)
        ..lineTo(10.5, 17)
        ..cubicTo(10.5, 17.2761, 10.2761, 17.5, 10, 17.5)
        ..cubicTo(9.72386, 17.5, 9.5, 17.2761, 9.5, 17)
        ..lineTo(9.5, 10.5)
        ..lineTo(3, 10.5)
        ..cubicTo(2.72386, 10.5, 2.5, 10.2761, 2.5, 10)
        ..cubicTo(2.5, 9.72386, 2.72386, 9.5, 3, 9.5)
        ..lineTo(9.5, 9.5)
        ..lineTo(9.5, 3)
        ..cubicTo(9.5, 2.72386, 9.72386, 2.5, 10, 2.5)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'plugConnected20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(17.8536, 2.85355)
        ..cubicTo(18.0488, 2.65829, 18.0488, 2.34171, 17.8536, 2.14645)
        ..cubicTo(17.6583, 1.95118, 17.3417, 1.95118, 17.1464, 2.14645)
        ..lineTo(14.4781, 4.81475)
        ..cubicTo(12.8949, 3.57957, 10.6024, 3.69014, 9.14607, 5.14646)
        ..lineTo(8.84607, 5.44646)
        ..cubicTo(8.26421, 6.02832, 8.26421, 6.97171, 8.84607, 7.55357)
        ..lineTo(12.4461, 11.1536)
        ..cubicTo(13.0279, 11.7354, 13.9713, 11.7354, 14.5532, 11.1536)
        ..lineTo(14.8532, 10.8536)
        ..cubicTo(16.3094, 9.39737, 16.42, 7.10518, 15.1852, 5.52191)
        ..lineTo(17.8536, 2.85355)
        ..close()
        ..moveTo(13.8461, 10.4465)
        ..cubicTo(13.6547, 10.6378, 13.3445, 10.6378, 13.1532, 10.4465)
        ..lineTo(9.55318, 6.84646)
        ..cubicTo(9.36184, 6.65513, 9.36184, 6.34491, 9.55318, 6.15357)
        ..lineTo(9.85318, 5.85357)
        ..cubicTo(11.0386, 4.66812, 12.9606, 4.66812, 14.1461, 5.85357)
        ..cubicTo(15.3315, 7.03902, 15.3315, 8.96101, 14.1461, 10.1465)
        ..lineTo(13.8461, 10.4465)
        ..close()
        ..moveTo(7.55393, 8.84643)
        ..cubicTo(6.97207, 8.26457, 6.02869, 8.26457, 5.44682, 8.84643)
        ..lineTo(5.14683, 9.14643)
        ..cubicTo(3.69063, 10.6026, 3.57995, 12.8948, 4.8148, 14.4781)
        ..lineTo(2.14645, 17.1464)
        ..cubicTo(1.95118, 17.3417, 1.95118, 17.6583, 2.14645, 17.8536)
        ..cubicTo(2.34171, 18.0488, 2.65829, 18.0488, 2.85355, 17.8536)
        ..lineTo(5.52186, 15.1852)
        ..cubicTo(7.10515, 16.4204, 9.39761, 16.3099, 10.8539, 14.8535)
        ..lineTo(11.1539, 14.5535)
        ..cubicTo(11.7358, 13.9717, 11.7358, 13.0283, 11.1539, 12.4464)
        ..lineTo(7.55393, 8.84643)
        ..close()
        ..moveTo(6.15393, 9.55354)
        ..cubicTo(6.34527, 9.3622, 6.65549, 9.3622, 6.84682, 9.55354)
        ..lineTo(10.4468, 13.1535)
        ..cubicTo(10.6382, 13.3449, 10.6382, 13.6551, 10.4468, 13.8464)
        ..lineTo(10.1468, 14.1464)
        ..cubicTo(8.96137, 15.3319, 7.03938, 15.3319, 5.85393, 14.1464)
        ..cubicTo(4.66848, 12.961, 4.66848, 11.039, 5.85393, 9.85354)
        ..lineTo(6.15393, 9.55354)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'document20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(6, 2)
        ..cubicTo(4.89543, 2, 4, 2.89543, 4, 4)
        ..lineTo(4, 16)
        ..cubicTo(4, 17.1046, 4.89543, 18, 6, 18)
        ..lineTo(14, 18)
        ..cubicTo(15.1046, 18, 16, 17.1046, 16, 16)
        ..lineTo(16, 7.41421)
        ..cubicTo(16, 7.01639, 15.842, 6.63486, 15.5607, 6.35355)
        ..lineTo(11.6464, 2.43934)
        ..cubicTo(11.3651, 2.15804, 10.9836, 2, 10.5858, 2)
        ..lineTo(6, 2)
        ..close()
        ..moveTo(5, 4)
        ..cubicTo(5, 3.44772, 5.44772, 3, 6, 3)
        ..lineTo(10, 3)
        ..lineTo(10, 6.5)
        ..cubicTo(10, 7.32843, 10.6716, 8, 11.5, 8)
        ..lineTo(15, 8)
        ..lineTo(15, 16)
        ..cubicTo(15, 16.5523, 14.5523, 17, 14, 17)
        ..lineTo(6, 17)
        ..cubicTo(5.44772, 17, 5, 16.5523, 5, 16)
        ..lineTo(5, 4)
        ..close()
        ..moveTo(14.7929, 7)
        ..lineTo(11.5, 7)
        ..cubicTo(11.2239, 7, 11, 6.77614, 11, 6.5)
        ..lineTo(11, 3.20711)
        ..lineTo(14.7929, 7)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'clipboardPaste20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(4.5, 4)
        ..lineTo(6.08535, 4)
        ..cubicTo(6.29127, 4.5826, 6.84689, 5, 7.5, 5)
        ..lineTo(10.5, 5)
        ..cubicTo(11.1531, 5, 11.7087, 4.5826, 11.9146, 4)
        ..lineTo(13.5, 4)
        ..cubicTo(13.7761, 4, 14, 4.22386, 14, 4.5)
        ..lineTo(14, 5.5)
        ..cubicTo(14, 5.77614, 14.2239, 6, 14.5, 6)
        ..cubicTo(14.7761, 6, 15, 5.77614, 15, 5.5)
        ..lineTo(15, 4.5)
        ..cubicTo(15, 3.67157, 14.3284, 3, 13.5, 3)
        ..lineTo(11.9146, 3)
        ..cubicTo(11.7087, 2.4174, 11.1531, 2, 10.5, 2)
        ..lineTo(7.5, 2)
        ..cubicTo(6.84689, 2, 6.29127, 2.4174, 6.08535, 3)
        ..lineTo(4.5, 3)
        ..cubicTo(3.67157, 3, 3, 3.67157, 3, 4.5)
        ..lineTo(3, 16.5)
        ..cubicTo(3, 17.3284, 3.67157, 18, 4.5, 18)
        ..lineTo(7.5, 18)
        ..cubicTo(7.77614, 18, 8, 17.7761, 8, 17.5)
        ..cubicTo(8, 17.2239, 7.77614, 17, 7.5, 17)
        ..lineTo(4.5, 17)
        ..cubicTo(4.22386, 17, 4, 16.7761, 4, 16.5)
        ..lineTo(4, 4.5)
        ..cubicTo(4, 4.22386, 4.22386, 4, 4.5, 4)
        ..close()
        ..moveTo(7.5, 4)
        ..cubicTo(7.22386, 4, 7, 3.77614, 7, 3.5)
        ..cubicTo(7, 3.22386, 7.22386, 3, 7.5, 3)
        ..lineTo(10.5, 3)
        ..cubicTo(10.7761, 3, 11, 3.22386, 11, 3.5)
        ..cubicTo(11, 3.77614, 10.7761, 4, 10.5, 4)
        ..lineTo(7.5, 4)
        ..close()
        ..moveTo(10.5, 7)
        ..cubicTo(9.67157, 7, 9, 7.67157, 9, 8.5)
        ..lineTo(9, 16.5)
        ..cubicTo(9, 17.3284, 9.67157, 18, 10.5, 18)
        ..lineTo(15.5, 18)
        ..cubicTo(16.3284, 18, 17, 17.3284, 17, 16.5)
        ..lineTo(17, 8.5)
        ..cubicTo(17, 7.67157, 16.3284, 7, 15.5, 7)
        ..lineTo(10.5, 7)
        ..close()
        ..moveTo(10, 8.5)
        ..cubicTo(10, 8.22386, 10.2239, 8, 10.5, 8)
        ..lineTo(15.5, 8)
        ..cubicTo(15.7761, 8, 16, 8.22386, 16, 8.5)
        ..lineTo(16, 16.5)
        ..cubicTo(16, 16.7761, 15.7761, 17, 15.5, 17)
        ..lineTo(10.5, 17)
        ..cubicTo(10.2239, 17, 10, 16.7761, 10, 16.5)
        ..lineTo(10, 8.5)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'chevronDown20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(15.8537, 7.64582)
        ..cubicTo(16.0493, 7.84073, 16.0499, 8.15731, 15.855, 8.35292)
        ..lineTo(10.39, 13.8374)
        ..cubicTo(10.1751, 14.0531, 9.82574, 14.0531, 9.6108, 13.8374)
        ..lineTo(4.14582, 8.35292)
        ..cubicTo(3.9509, 8.15731, 3.95147, 7.84073, 4.14708, 7.64582)
        ..cubicTo(4.34269, 7.4509, 4.65927, 7.45147, 4.85418, 7.64708)
        ..lineTo(10.0004, 12.8117)
        ..lineTo(15.1466, 7.64708)
        ..cubicTo(15.3415, 7.45147, 15.6581, 7.4509, 15.8537, 7.64582)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'chevronRight20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(7.64582, 4.14708)
        ..cubicTo(7.84073, 3.95147, 8.15731, 3.9509, 8.35292, 4.14582)
        ..lineTo(13.8374, 9.6108)
        ..cubicTo(14.0531, 9.82574, 14.0531, 10.1751, 13.8374, 10.39)
        ..lineTo(8.35292, 15.855)
        ..cubicTo(8.15731, 16.0499, 7.84073, 16.0493, 7.64582, 15.8537)
        ..cubicTo(7.4509, 15.6581, 7.45147, 15.3415, 7.64708, 15.1466)
        ..lineTo(12.8117, 10.0004)
        ..lineTo(7.64708, 4.85418)
        ..cubicTo(7.45147, 4.65927, 7.4509, 4.34269, 7.64582, 4.14708)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'search20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(13.7291, 14.4362)
        ..cubicTo(12.5924, 15.411, 11.115, 16, 9.5, 16)
        ..cubicTo(5.91015, 16, 3, 13.0899, 3, 9.5)
        ..cubicTo(3, 5.91015, 5.91015, 3, 9.5, 3)
        ..cubicTo(13.0899, 3, 16, 5.91015, 16, 9.5)
        ..cubicTo(16, 11.115, 15.411, 12.5924, 14.4361, 13.7292)
        ..lineTo(17.8535, 17.1465)
        ..cubicTo(18.0487, 17.3417, 18.0487, 17.6583, 17.8535, 17.8536)
        ..cubicTo(17.6799, 18.0271, 17.4105, 18.0464, 17.2156, 17.9114)
        ..lineTo(17.1464, 17.8536)
        ..lineTo(13.7291, 14.4362)
        ..close()
        ..moveTo(13.0196, 13.7266)
        ..cubicTo(13.276, 13.5128, 13.5127, 13.2761, 13.7265, 13.0197)
        ..cubicTo(14.5216, 12.0659, 15, 10.8388, 15, 9.5)
        ..cubicTo(15, 6.46243, 12.5376, 4, 9.5, 4)
        ..cubicTo(6.46243, 4, 4, 6.46243, 4, 9.5)
        ..cubicTo(4, 12.5376, 6.46243, 15, 9.5, 15)
        ..cubicTo(10.8388, 15, 12.0658, 14.5217, 13.0196, 13.7266)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'dismiss20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(4.08859, 4.21569)
        ..lineTo(4.14645, 4.14645)
        ..cubicTo(4.32001, 3.97288, 4.58944, 3.9536, 4.78431, 4.08859)
        ..lineTo(4.85355, 4.14645)
        ..lineTo(10, 9.293)
        ..lineTo(15.1464, 4.14645)
        ..cubicTo(15.32, 3.97288, 15.5894, 3.9536, 15.7843, 4.08859)
        ..lineTo(15.8536, 4.14645)
        ..cubicTo(16.0271, 4.32001, 16.0464, 4.58944, 15.9114, 4.78431)
        ..lineTo(15.8536, 4.85355)
        ..lineTo(10.707, 10)
        ..lineTo(15.8536, 15.1464)
        ..cubicTo(16.0271, 15.32, 16.0464, 15.5894, 15.9114, 15.7843)
        ..lineTo(15.8536, 15.8536)
        ..cubicTo(15.68, 16.0271, 15.4106, 16.0464, 15.2157, 15.9114)
        ..lineTo(15.1464, 15.8536)
        ..lineTo(10, 10.707)
        ..lineTo(4.85355, 15.8536)
        ..cubicTo(4.67999, 16.0271, 4.41056, 16.0464, 4.21569, 15.9114)
        ..lineTo(4.14645, 15.8536)
        ..cubicTo(3.97288, 15.68, 3.9536, 15.4106, 4.08859, 15.2157)
        ..lineTo(4.14645, 15.1464)
        ..lineTo(9.293, 10)
        ..lineTo(4.14645, 4.85355)
        ..cubicTo(3.97288, 4.67999, 3.9536, 4.41056, 4.08859, 4.21569)
        ..lineTo(4.14645, 4.14645)
        ..lineTo(4.08859, 4.21569)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'folder20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(4.5, 3)
        ..cubicTo(3.11929, 3, 2, 4.11929, 2, 5.5)
        ..lineTo(2, 14.5)
        ..cubicTo(2, 15.8807, 3.11929, 17, 4.5, 17)
        ..lineTo(15.5, 17)
        ..cubicTo(16.8807, 17, 18, 15.8807, 18, 14.5)
        ..lineTo(18, 7.5)
        ..cubicTo(18, 6.11929, 16.8807, 5, 15.5, 5)
        ..lineTo(9.70711, 5)
        ..lineTo(8.21967, 3.51256)
        ..cubicTo(7.89148, 3.18437, 7.44636, 3, 6.98223, 3)
        ..lineTo(4.5, 3)
        ..close()
        ..moveTo(3, 5.5)
        ..cubicTo(3, 4.67157, 3.67157, 4, 4.5, 4)
        ..lineTo(6.98223, 4)
        ..cubicTo(7.18115, 4, 7.37191, 4.07902, 7.51256, 4.21967)
        ..lineTo(8.79289, 5.5)
        ..lineTo(7.43934, 6.85355)
        ..cubicTo(7.34557, 6.94732, 7.21839, 7, 7.08579, 7)
        ..lineTo(3, 7)
        ..lineTo(3, 5.5)
        ..close()
        ..moveTo(3, 8)
        ..lineTo(7.08579, 8)
        ..cubicTo(7.48361, 8, 7.86514, 7.84196, 8.14645, 7.56066)
        ..lineTo(9.70711, 6)
        ..lineTo(15.5, 6)
        ..cubicTo(16.3284, 6, 17, 6.67157, 17, 7.5)
        ..lineTo(17, 14.5)
        ..cubicTo(17, 15.3284, 16.3284, 16, 15.5, 16)
        ..lineTo(4.5, 16)
        ..cubicTo(3.67157, 16, 3, 15.3284, 3, 14.5)
        ..lineTo(3, 8)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'arrowDownload20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(15.5, 16.9997)
        ..cubicTo(15.7761, 16.9997, 16, 17.2236, 16, 17.4997)
        ..cubicTo(16, 17.7452, 15.8231, 17.9494, 15.5899, 17.9917)
        ..lineTo(15.5, 17.9997)
        ..lineTo(4.5, 17.9997)
        ..cubicTo(4.22386, 17.9997, 4, 17.7759, 4, 17.4997)
        ..cubicTo(4, 17.2543, 4.17688, 17.0501, 4.41012, 17.0078)
        ..lineTo(4.5, 16.9997)
        ..lineTo(15.5, 16.9997)
        ..close()
        ..moveTo(10.0001, 2.00195)
        ..cubicTo(10.2456, 2.00195, 10.4497, 2.17896, 10.492, 2.41222)
        ..lineTo(10.5, 2.5021)
        ..lineTo(10.496, 14.296)
        ..lineTo(14.1414, 10.6476)
        ..cubicTo(14.3148, 10.4739, 14.5842, 10.4544, 14.7792, 10.5892)
        ..lineTo(14.8485, 10.647)
        ..cubicTo(15.0222, 10.8204, 15.0418, 11.0898, 14.907, 11.2848)
        ..lineTo(14.8492, 11.3541)
        ..lineTo(10.3574, 15.8541)
        ..cubicTo(10.285, 15.9267, 10.1957, 15.9724, 10.1021, 15.9911)
        ..lineTo(9.99608, 16.0008)
        ..cubicTo(9.83511, 16.0008, 9.69192, 15.9247, 9.60051, 15.8065)
        ..lineTo(5.14386, 11.3547)
        ..cubicTo(4.94846, 11.1595, 4.94823, 10.8429, 5.14336, 10.6475)
        ..cubicTo(5.3168, 10.4739, 5.58621, 10.4544, 5.78117, 10.5892)
        ..lineTo(5.85046, 10.647)
        ..lineTo(9.496, 14.288)
        ..lineTo(9.5, 2.50181)
        ..cubicTo(9.50008, 2.22567, 9.724, 2.00195, 10.0001, 2.00195)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'arrowUpload20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(15, 3.00195)
        ..cubicTo(15.2761, 3.00195, 15.5, 2.7781, 15.5, 2.50195)
        ..cubicTo(15.5, 2.25649, 15.3231, 2.05235, 15.0899, 2.01001)
        ..lineTo(15, 2.00195)
        ..lineTo(4, 2.00195)
        ..cubicTo(3.72386, 2.00195, 3.5, 2.22581, 3.5, 2.50195)
        ..cubicTo(3.5, 2.74741, 3.67688, 2.95156, 3.91012, 2.9939)
        ..lineTo(4, 3.00195)
        ..lineTo(15, 3.00195)
        ..close()
        ..moveTo(9.50014, 17.9997)
        ..cubicTo(9.7456, 17.9997, 9.9497, 17.8227, 9.99197, 17.5895)
        ..lineTo(10, 17.4996)
        ..lineTo(9.996, 5.70574)
        ..lineTo(13.6414, 9.35408)
        ..cubicTo(13.8148, 9.5278, 14.0842, 9.54734, 14.2792, 9.41252)
        ..lineTo(14.3485, 9.35473)
        ..cubicTo(14.5222, 9.18132, 14.5418, 8.91192, 14.407, 8.71692)
        ..lineTo(14.3492, 8.64762)
        ..lineTo(9.85745, 4.14762)
        ..cubicTo(9.78495, 4.07499, 9.69568, 4.02931, 9.60207, 4.01059)
        ..lineTo(9.49608, 4.00085)
        ..cubicTo(9.33511, 4.00085, 9.19192, 4.07697, 9.10051, 4.19517)
        ..lineTo(4.64386, 8.64704)
        ..cubicTo(4.44846, 8.84217, 4.44823, 9.15875, 4.64336, 9.35415)
        ..cubicTo(4.8168, 9.52784, 5.08621, 9.54732, 5.28117, 9.41246)
        ..lineTo(5.35046, 9.35465)
        ..lineTo(8.996, 5.71374)
        ..lineTo(9, 17.4999)
        ..cubicTo(9.00008, 17.776, 9.224, 17.9997, 9.50014, 17.9997)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'checkmark20Regular': _V3Glyph(
    Size(20, 20),
    [
      Path()
        ..moveTo(3.37371, 10.1678)
        ..cubicTo(3.19025, 9.96143, 2.87421, 9.94284, 2.66782, 10.1263)
        ..cubicTo(2.46143, 10.3098, 2.44284, 10.6258, 2.6263, 10.8322)
        ..lineTo(6.6263, 15.3322)
        ..cubicTo(6.81743, 15.5472, 7.15013, 15.557, 7.35356, 15.3536)
        ..lineTo(17.8536, 4.85355)
        ..cubicTo(18.0488, 4.65829, 18.0488, 4.34171, 17.8536, 4.14645)
        ..cubicTo(17.6583, 3.95118, 17.3417, 3.95118, 17.1465, 4.14645)
        ..lineTo(7.02141, 14.2715)
        ..lineTo(3.37371, 10.1678)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'settingsApplication': _V3Glyph(
    Size(18, 18),
    [
      Path()
        ..moveTo(17.982, 4.37503)
        ..cubicTo(17.9682, 4.2148, 17.6105, 3.90708, 17.4592, 3.85219)
        ..cubicTo(17.3075, 3.79697, 17.1376, 3.83456, 17.0235, 3.94809)
        ..lineTo(14.7339, 6.23769)
        ..lineTo(11.7599, 3.26374)
        ..lineTo(14.0954, 0.93712)
        ..cubicTo(14.2096, 0.823371, 14.2469, 0.654134, 14.1919, 0.503243)
        ..cubicTo(14.1363, 0.352052, 13.7696, 0.0317521, 13.6084, 0.0178711)
        ..cubicTo(12.1901, -0.10387, 10.8004, 0.400614, 9.79562, 1.40174)
        ..cubicTo(8.41951, 2.77278, 8.05509, 4.77488, 8.7004, 6.48143)
        ..cubicTo(8.62987, 6.54063, 8.56028, 6.60336, 8.49162, 6.671)
        ..lineTo(0.696028, 13.9993)
        ..cubicTo(0.693279, 14.002, 0.690568, 14.0049, 0.687593, 14.0075)
        ..cubicTo(-0.229198, 14.9209, -0.229198, 16.407, 0.687593, 17.3206)
        ..cubicTo(1.60453, 18.2339, 3.08537, 18.2228, 4.00201, 17.3094)
        ..cubicTo(4.00596, 17.3057, 4.00958, 17.302, 4.01319, 17.2979)
        ..lineTo(11.305, 9.47122)
        ..cubicTo(11.3715, 9.40471, 11.4332, 9.33511, 11.4914, 9.26368)
        ..cubicTo(13.2049, 9.90773, 15.2158, 9.54554, 16.5931, 8.1736)
        ..cubicTo(17.5977, 7.1724, 18.1044, 5.78782, 17.982, 4.37503)
        ..close(),
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'settingsEditor': _V3Glyph(
    Size(18, 18),
    [
      Path()
        ..moveTo(7, 11.5)
        ..lineTo(4.5, 9)
        ..lineTo(7, 6.5)
        ..moveTo(11, 6.5)
        ..lineTo(13.5, 9)
        ..lineTo(11, 11.5)
        ..moveTo(3, 17)
        ..cubicTo(1.89543, 17, 1, 16.1046, 1, 15)
        ..lineTo(1, 3)
        ..cubicTo(1, 1.89543, 1.89543, 1, 3, 1)
        ..lineTo(15, 1)
        ..cubicTo(16.1046, 1, 17, 1.89543, 17, 3)
        ..lineTo(17, 15)
        ..cubicTo(17, 16.1046, 16.1046, 17, 15, 17)
        ..lineTo(3, 17)
        ..close(),
    ],
    stroke: 1.1,
    fillBeforeStroke: false,
  ),
  'settingsTerminal': _V3Glyph(
    Size(18, 18),
    [
      Path()
        ..moveTo(5, 8.5)
        ..lineTo(7.5, 11)
        ..lineTo(5, 13.5)
        ..moveTo(1.5, 5.5)
        ..lineTo(16.5, 5.5)
        ..moveTo(3, 17)
        ..cubicTo(1.89543, 17, 1, 16.1046, 1, 15)
        ..lineTo(1, 3)
        ..cubicTo(1, 1.89543, 1.89543, 1, 3, 1)
        ..lineTo(15, 1)
        ..cubicTo(16.1046, 1, 17, 1.89543, 17, 3)
        ..lineTo(17, 15)
        ..cubicTo(17, 16.1046, 16.1046, 17, 15, 17)
        ..lineTo(3, 17)
        ..close(),
    ],
    stroke: 1.1,
    fillBeforeStroke: false,
  ),
  'settingsConfig': _V3Glyph(
    Size(18, 18),
    [
      Path()
        ..moveTo(10.6763, 1.31627)
        ..cubicTo(10.2488, -0.438757, 7.75121, -0.438757, 7.3237, 1.31627)
        ..cubicTo(7.25987, 1.57999, 7.13468, 1.82492, 6.95831, 2.03112)
        ..cubicTo(6.78194, 2.23732, 6.55938, 2.39897, 6.30874, 2.50291)
        ..cubicTo(6.0581, 2.60684, 5.78646, 2.65014, 5.51592, 2.62927)
        ..cubicTo(5.24538, 2.60839, 4.9836, 2.52394, 4.75187, 2.38279)
        ..cubicTo(3.20832, 1.44227, 1.44201, 3.20855, 2.38254, 4.75207)
        ..cubicTo(2.99006, 5.74884, 2.45117, 7.04936, 1.31713, 7.32499)
        ..cubicTo(-0.439045, 7.75137, -0.439045, 10.25, 1.31713, 10.6753)
        ..cubicTo(1.58093, 10.7392, 1.8259, 10.8645, 2.03211, 11.041)
        ..cubicTo(2.23831, 11.2175, 2.39991, 11.4402, 2.50375, 11.691)
        ..cubicTo(2.6076, 11.9418, 2.65074, 12.2135, 2.62968, 12.4841)
        ..cubicTo(2.60862, 12.7547, 2.52394, 13.0165, 2.38254, 13.2482)
        ..cubicTo(1.44201, 14.7917, 3.20832, 16.558, 4.75187, 15.6175)
        ..cubicTo(4.98356, 15.4761, 5.24536, 15.3914, 5.51597, 15.3704)
        ..cubicTo(5.78658, 15.3493, 6.05834, 15.3924, 6.30912, 15.4963)
        ..cubicTo(6.5599, 15.6001, 6.7826, 15.7617, 6.95911, 15.9679)
        ..cubicTo(7.13561, 16.1741, 7.26091, 16.4191, 7.32482, 16.6829)
        ..cubicTo(7.75121, 18.439, 10.2499, 18.439, 10.6752, 16.6829)
        ..cubicTo(10.7393, 16.4192, 10.8647, 16.1744, 11.0413, 15.9684)
        ..cubicTo(11.2178, 15.7623, 11.4405, 15.6008, 11.6912, 15.497)
        ..cubicTo(11.9419, 15.3932, 12.2135, 15.35, 12.4841, 15.3709)
        ..cubicTo(12.7546, 15.3919, 13.0164, 15.4764, 13.2481, 15.6175)
        ..cubicTo(14.7917, 16.558, 16.558, 14.7917, 15.6175, 13.2482)
        ..cubicTo(15.4763, 13.0165, 15.3918, 12.7547, 15.3709, 12.4842)
        ..cubicTo(15.35, 12.2136, 15.3932, 11.942, 15.497, 11.6913)
        ..cubicTo(15.6008, 11.4406, 15.7623, 11.2179, 15.9683, 11.0414)
        ..cubicTo(16.1744, 10.8648, 16.4192, 10.7394, 16.6829, 10.6753)
        ..cubicTo(18.439, 10.2489, 18.439, 7.75025, 16.6829, 7.32499)
        ..cubicTo(16.4191, 7.26108, 16.1741, 7.13578, 15.9679, 6.95928)
        ..cubicTo(15.7617, 6.78278, 15.6001, 6.56007, 15.4962, 6.3093)
        ..cubicTo(15.3924, 6.05853, 15.3493, 5.78677, 15.3703, 5.51617)
        ..cubicTo(15.3914, 5.24556, 15.4761, 4.98376, 15.6175, 4.75207)
        ..cubicTo(16.558, 3.20855, 14.7917, 1.44227, 13.2481, 2.38279)
        ..cubicTo(13.0164, 2.52418, 12.7546, 2.60886, 12.484, 2.62992)
        ..cubicTo(12.2134, 2.65098, 11.9417, 2.60784, 11.6909, 2.504)
        ..cubicTo(11.4401, 2.40016, 11.2174, 2.23856, 11.0409, 2.03236)
        ..cubicTo(10.8644, 1.82616, 10.7391, 1.58119, 10.6752, 1.3174)
        ..lineTo(10.6763, 1.31627)
        ..close()
        ..moveTo(9, 11)
        ..cubicTo(10.1046, 11, 11, 10.1046, 11, 9)
        ..cubicTo(11, 7.89543, 10.1046, 7, 9, 7)
        ..cubicTo(7.89543, 7, 7, 7.89543, 7, 9)
        ..cubicTo(7, 10.1046, 7.89543, 11, 9, 11)
        ..close()
        ..fillType = PathFillType.evenOdd,
    ],
    stroke: 0,
    fillBeforeStroke: false,
  ),
  'settingsLayers': _V3Glyph(
    Size(17.2, 17.2),
    [
      Path()
        ..moveTo(16.2002, 8.58031)
        ..lineTo(8.60021, 12.4759)
        ..lineTo(1.00021, 8.58031)
        ..moveTo(16.2002, 12.3044)
        ..lineTo(8.60021, 16.2)
        ..lineTo(1.00021, 12.3044)
        ..moveTo(8.60021, 1)
        ..lineTo(16.2002, 4.89559)
        ..lineTo(8.60021, 8.79118)
        ..lineTo(1.00021, 4.89559)
        ..lineTo(8.60021, 1)
        ..close(),
    ],
    stroke: 1.1,
    fillBeforeStroke: false,
  ),
  'settingsCode': _V3Glyph(
    Size(14, 14),
    [
      Path()
        ..moveTo(5.5, 8.875)
        ..lineTo(3.625, 7)
        ..lineTo(5.5, 5.125)
        ..moveTo(8.5, 5.125)
        ..lineTo(10.375, 7)
        ..lineTo(8.5, 8.875)
        ..moveTo(2.5, 13)
        ..cubicTo(1.67157, 13, 1, 12.3284, 1, 11.5)
        ..lineTo(1, 2.5)
        ..cubicTo(1, 1.67157, 1.67157, 1, 2.5, 1)
        ..lineTo(11.5, 1)
        ..cubicTo(12.3284, 1, 13, 1.67157, 13, 2.5)
        ..lineTo(13, 11.5)
        ..cubicTo(13, 12.3284, 12.3284, 13, 11.5, 13)
        ..lineTo(2.5, 13)
        ..close(),
    ],
    stroke: 1.1,
    fillBeforeStroke: false,
  ),
  'settingsBrush': _V3Glyph(
    Size(18, 18),
    [
      Path()
        ..moveTo(6.14689, 8.59134)
        ..lineTo(12.8842, 0.803237)
        ..cubicTo(12.9881, 0.683194, 13.1225, 0.593584, 13.2733, 0.543961)
        ..cubicTo(13.4514, 0.485346, 13.6436, 0.485346, 13.8217, 0.543961)
        ..lineTo(13.9211, 0.576696)
        ..cubicTo(14.0073, 0.605042, 14.0857, 0.652944, 14.1502, 0.716649)
        ..cubicTo(14.3924, 0.955791, 14.4524, 1.324, 14.2986, 1.62765)
        ..lineTo(14.2203, 1.78231)
        ..lineTo(9.00621, 10.5842)
        ..moveTo(6.14689, 8.59134)
        ..lineTo(9.00621, 10.5842)
        ..moveTo(6.14689, 8.59134)
        ..lineTo(4.29674, 11.9128)
        ..moveTo(9.00621, 10.5842)
        ..lineTo(6.31513, 13.2414)
        ..moveTo(6.31513, 13.2414)
        ..cubicTo(5.82556, 12.2493, 5.41943, 11.9016, 4.29674, 11.9128)
        ..moveTo(6.31513, 13.2414)
        ..cubicTo(7.42723, 15.5108, 1.15564, 17.8919, 0.59648, 16.895)
        ..moveTo(4.29674, 11.9128)
        ..cubicTo(2.86431, 12.0338, 2.21628, 12.6211, 1.78841, 14.5728)
        ..cubicTo(1.6465, 15.2201, 1.39581, 15.8427, 0.994989, 16.3704)
        ..lineTo(0.59648, 16.895)
        ..moveTo(0.59648, 16.895)
        ..cubicTo(1.68798, 16.0819, 2.56677, 15.8553, 2.7931, 14.5867),
    ],
    stroke: 1.1,
    fillBeforeStroke: false,
  ),
  'edit20Regular': _V3Glyph(
    Size(20, 21),
    [
      Path()
        ..moveTo(15.076, 9.63326)
        ..lineTo(10.911, 5.60096)
        ..lineTo(2.60398, 14.4788)
        ..lineTo(1.00003, 20)
        ..lineTo(6.34655, 18.3437)
        ..lineTo(15.076, 9.63326)
        ..close(),
      Path()
        ..moveTo(18.1487, 6.12421)
        ..cubicTo(19.2838, 4.95197, 19.2838, 3.05141, 18.1487, 1.87917)
        ..cubicTo(17.0135, 0.70694, 15.173, 0.706943, 14.0379, 1.87918)
        ..lineTo(12.5842, 3.4328)
        ..lineTo(16.8286, 7.44135)
        ..lineTo(18.1487, 6.12421)
        ..close(),
    ],
    stroke: 2,
    fillBeforeStroke: true,
  ),
};
