import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/monaco_editor_service.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import 'orion_overlay.dart';

class OrionMenuEntry<T> {
  const OrionMenuEntry({
    required this.value,
    required this.label,
    this.enabled = true,
  }) : divider = false;
  const OrionMenuEntry.divider()
    : value = null,
      label = '',
      enabled = false,
      divider = true;
  final T? value;
  final String label;
  final bool enabled, divider;
}

/// A route-backed anchored menu so native editors yield through both transitions.
Future<T?> showOrionPopupMenu<T>(
  BuildContext anchorContext, {
  required OrionController controller,
  required List<OrionMenuEntry<T>> entries,
  MonacoEditorService? editorService,
  Offset? globalPosition,
}) async {
  const owner = 'orion-popup-menu';
  final navigator = Navigator.of(anchorContext, rootNavigator: true);
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return null;
  final anchor = globalPosition == null
      ? box.localToGlobal(Offset.zero, ancestor: overlay) & box.size
      : overlay.globalToLocal(globalPosition) & Size.zero;
  final reduced =
      controller.reducedMotion || MediaQuery.disableAnimationsOf(anchorContext);
  final firstEnabled = entries.where((entry) => entry.enabled).firstOrNull;
  final route = RawDialogRoute<T>(
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(
      anchorContext,
    ).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 140),
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    pageBuilder: (context, _, _) => OrionOverlayTheme(
      controller: controller,
      builder: (context) => CustomSingleChildLayout(
        delegate: _MenuPosition(
          anchor,
          MediaQuery.paddingOf(context),
          alignStart: globalPosition != null,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 236,
            maxHeight: math.max(64, MediaQuery.sizeOf(context).height - 24),
          ),
          child: OrionOverlaySurface(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(6),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            padding: const EdgeInsets.all(5),
            child: Material(
              key: const ValueKey('orion-popup-menu'),
              type: MaterialType.transparency,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      navigator.pop(),
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      FocusScope.of(context).nextFocus(),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      FocusScope.of(context).previousFocus(),
                },
                child: FocusTraversalGroup(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in entries)
                          if (entry.divider)
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: Divider(),
                            )
                          else
                            TextButton(
                              autofocus: identical(entry, firstEnabled),
                              onPressed: entry.enabled
                                  ? () => navigator.pop(entry.value)
                                  : null,
                              style:
                                  TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    minimumSize: const Size(0, 38),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    foregroundColor: OrionColors.of(
                                      context,
                                    ).ink,
                                    disabledForegroundColor: OrionColors.of(
                                      context,
                                    ).muted.withValues(alpha: .6),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                  ).copyWith(
                                    backgroundBuilder:
                                        OrionColors.of(context).glassEnabled
                                        ? (_, _, child) =>
                                              child ?? const SizedBox.shrink()
                                        : null,
                                  ),
                              child: Text(entry.label),
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
    ),
    transitionBuilder: (context, animation, _, child) =>
        controller.reducedMotion || MediaQuery.disableAnimationsOf(context)
        ? child
        : FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          ),
  );
  try {
    await editorService?.freezeForOverlay(owner: owner);
    if (!anchorContext.mounted) return null;
    final result = await navigator.push(route);
    await route.completed;
    return result;
  } finally {
    editorService?.setObscured(false, owner: owner);
  }
}

class _MenuPosition extends SingleChildLayoutDelegate {
  const _MenuPosition(this.anchor, this.safeArea, {this.alignStart = false});
  final Rect anchor;
  final EdgeInsets safeArea;
  final bool alignStart;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.min(
            236,
            math.max(0, constraints.maxWidth - safeArea.horizontal - 24),
          ),
          math.max(0, constraints.maxHeight - safeArea.vertical - 24),
        ),
      );
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minX = safeArea.left + 12, minY = safeArea.top + 12;
    final maxX = math.max(
      minX,
      size.width - safeArea.right - 12 - childSize.width,
    );
    final maxY = math.max(
      minY,
      size.height - safeArea.bottom - 12 - childSize.height,
    );
    final below = anchor.bottom + 5;
    final y = below + childSize.height <= size.height - safeArea.bottom - 12
        ? below
        : anchor.top - 5 - childSize.height;
    return Offset(
      (alignStart ? anchor.left : anchor.right - childSize.width).clamp(
        minX,
        maxX,
      ),
      y.clamp(minY, maxY),
    );
  }

  @override
  bool shouldRelayout(_MenuPosition old) =>
      anchor != old.anchor ||
      safeArea != old.safeArea ||
      alignStart != old.alignStart;
}
