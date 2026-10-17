import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/interface_preset.dart';
import '../theme/orion_theme.dart';

/// Authored interface marks, optically fitted without changing source images.
class InterfaceLogo extends StatelessWidget {
  const InterfaceLogo({super.key, required this.preset, this.size = 32});

  final InterfacePreset preset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    Widget mark;
    switch (preset) {
      case InterfacePreset.zenithV2:
        mark = SizedBox.square(
          dimension: size,
          child: Center(
            child: FittedBox(
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFF667EEA),
                    Color(0xFF9C66FF),
                    Color(0xFFFF6B96),
                    Color(0xFFFFA87A),
                    Color(0xFF667EEA),
                  ],
                  stops: [0, .25, .5, .75, 1],
                ).createShader(bounds),
                child: const Text(
                  'V2',
                  style: TextStyle(
                    fontFamily: 'OriginalNunito',
                    fontWeight: FontWeight.w600,
                    fontSize: 32,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      case InterfacePreset.awp:
        mark = SizedBox(
          width: size * 1.45,
          height: size,
          child: Center(
            child: FittedBox(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'AWP'),
                    const TextSpan(
                      text: '.',
                      style: TextStyle(color: Color(0xFF6A6A6A)),
                    ),
                    const TextSpan(text: 'GG'),
                  ],
                ),
                style: TextStyle(
                  fontFamily: 'OriginalAwpUI',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1,
                  color: colors.ink,
                  letterSpacing: -.25,
                ),
              ),
            ),
          ),
        );
      case InterfacePreset.synapseV3:
        mark = _image(
          'assets/interface_logos/synapse-s.png',
          source: const Size(1537, 2048),
          artwork: const Rect.fromLTRB(17, 206, 1520, 1842),
        );
      case InterfacePreset.synapseBlue:
      case InterfacePreset.synapse2017:
        mark = _image(
          'assets/interface_logos/synapse-s-2d.png',
          source: const Size(800, 167),
          artwork: const Rect.fromLTWH(0, 0, 140, 167),
          clipper: const _FlatSynapseClipper(),
        );
      case InterfacePreset.synapseX:
        mark = _image(
          'assets/synapse_x/logo.png',
          source: const Size(512, 423),
        );
        if (light) {
          // White S becomes readable ink; the orange X has no blue channel
          // and retains its authored color under this linear transform.
          mark = ColorFiltered(
            colorFilter: ColorFilter.matrix([
              1,
              0,
              colors.ink.r - 1,
              0,
              0,
              0,
              1,
              colors.ink.g - 1,
              0,
              0,
              0,
              0,
              colors.ink.b,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: mark,
          );
        }
      case InterfacePreset.orion:
        mark = _image(
          'assets/branding/orion-icon.png',
          source: const Size(859, 859),
          artwork: const Rect.fromLTRB(24, 40, 835, 820),
          tint: light ? colors.ink : null,
        );
      case InterfacePreset.krnl:
        mark = _image(
          'assets/original_krnl/pictureBox1.png',
          source: const Size(209, 197),
          tint: light ? colors.ink : null,
        );
      case InterfacePreset.calamari:
        mark = _image(
          'assets/original_calamari/AppLogo.png',
          source: const Size(584, 600),
        );
      case InterfacePreset.xeno:
        mark = _image(
          'assets/original_xeno/xeno-icon.png',
          source: const Size(32, 32),
          artwork: const Rect.fromLTRB(0, 5, 32, 27),
          tint: light ? colors.ink : null,
        );
      case InterfacePreset.rc7:
        mark = SizedBox.square(dimension: size);
    }
    return Semantics(
      label: '${preset.label} logo',
      image: true,
      excludeSemantics: true,
      child: mark,
    );
  }

  Widget _image(
    String asset, {
    required Size source,
    Rect? artwork,
    Color? tint,
    CustomClipper<Path>? clipper,
  }) {
    final frame = artwork ?? Offset.zero & source;
    final scale = size / math.max(frame.width, frame.height);
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: SizedBox(
          width: frame.width * scale,
          height: frame.height * scale,
          child: ClipPath(
            clipper: clipper,
            clipBehavior: clipper == null ? Clip.hardEdge : Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  left: -frame.left * scale,
                  top: -frame.top * scale,
                  width: source.width * scale,
                  height: source.height * scale,
                  child: Image.asset(
                    asset,
                    fit: BoxFit.fill,
                    color: tint,
                    colorBlendMode: BlendMode.srcIn,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Follow the edge between S and Y in the authored classic wordmark. A square
/// crop would include part of Y because the two glyphs' bounds overlap.
class _FlatSynapseClipper extends CustomClipper<Path> {
  const _FlatSynapseClipper();

  @override
  Path getClip(Size size) => Path()
    ..addPolygon([
      for (final point in const [
        Offset(0, 0),
        Offset(120, 0),
        Offset(120, 28),
        Offset(127.5, 34),
        Offset(130, 36),
        Offset(130, 41),
        Offset(132, 49),
        Offset(136, 58),
        Offset(138, 70),
        Offset(143, 88),
        Offset(149, 105),
        Offset(150, 167),
        Offset(0, 167),
      ])
        Offset(point.dx / 140 * size.width, point.dy / 167 * size.height),
    ], true);

  @override
  bool shouldReclip(_FlatSynapseClipper oldClipper) => false;
}
