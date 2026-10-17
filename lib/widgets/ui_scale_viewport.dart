import 'package:flutter/material.dart';

/// Scales the complete route tree while laying it out in its logical viewport.
/// Popups and dialogs therefore use the same scale and hit-test coordinates.
class UiScaleViewport extends StatelessWidget {
  const UiScaleViewport({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final viewport = constraints.biggest / scale;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: viewport.width,
          maxWidth: viewport.width,
          minHeight: viewport.height,
          maxHeight: viewport.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: viewport,
              child: MediaQuery(
                data: media.copyWith(
                  size: viewport,
                  padding: media.padding / scale,
                  viewPadding: media.viewPadding / scale,
                  viewInsets: media.viewInsets / scale,
                  systemGestureInsets: media.systemGestureInsets / scale,
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}
