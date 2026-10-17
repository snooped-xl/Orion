import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/orion_theme.dart';

/// The supplied Orion mark, stored with a transparent background.
class OrionLogo extends StatelessWidget {
  final double size;
  const OrionLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/orion-logo.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    color: Theme.of(context).brightness == Brightness.light
        ? Theme.of(context).extension<OrionColors>()?.ink ??
              Theme.of(context).colorScheme.onSurface
        : null,
    colorBlendMode: BlendMode.srcIn,
    // The supplied art is reduced by more than 20x in the shell. Mipmapped
    // sampling preserves its thin curves; bicubic sampling skips detail here.
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Orion logo',
  );
}

/// The supplied transparent wordmark, framed around its visible artwork.
class OrionWordmark extends StatelessWidget {
  final double height;
  final Uint8List? customImage;
  const OrionWordmark({super.key, this.height = 30, this.customImage});

  @override
  Widget build(BuildContext context) {
    // Keep the original PNG intact while excluding its transparent margins.
    const sourceSize = Size(1692, 929);
    const artwork = Rect.fromLTWH(152, 275, 1408, 387);
    final scale = height / artwork.height;
    final custom = customImage;
    return SizedBox(
      width: artwork.width * scale,
      height: height,
      child: custom != null
          ? Image.memory(
              custom,
              width: artwork.width * scale,
              height: height,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'Custom Orion logo',
              errorBuilder: (_, _, _) => OrionWordmark(height: height),
            )
          : Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: -artwork.left * scale,
                  top: -artwork.top * scale,
                  width: sourceSize.width * scale,
                  height: sourceSize.height * scale,
                  child: Image.asset(
                    'assets/branding/orion-wordmark.png',
                    fit: BoxFit.contain,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Theme.of(context).extension<OrionColors>()?.ink ??
                              Theme.of(context).colorScheme.onSurface
                        : null,
                    colorBlendMode: BlendMode.srcIn,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: 'Orion logo',
                  ),
                ),
              ],
            ),
    );
  }
}
