import 'package:flutter/widgets.dart';

/// Keeps an invisible mounted page out of window-size and theme animations.
///
/// Offstage pages still lay out and inherit changing viewport/theme values.
/// Retaining their last presentation avoids that work while preserving their
/// state and controller subscriptions. A visible page (including one leaving
/// during a swap) always receives the current layout and inherited themes.
class RetainedPage extends StatefulWidget {
  const RetainedPage({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<RetainedPage> {
  Widget? _presentation;
  bool _wasVisible = false;
  List<InheritedTheme>? _themes;
  MediaQueryData? _media;
  BoxConstraints? _constraints;
  Widget? _child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (widget.visible || _wasVisible || _presentation == null) {
        // Capture on the first invisible frame too: the new child carries its
        // inactive/native-editor state before its presentation is retained.
        // capture() walks ancestors without subscribing. Visible pages must
        // still follow palette, text and icon animations when their widget
        // identity and layout constraints stay unchanged.
        final types = <Type>{};
        final themes = <InheritedTheme>[];
        context.visitAncestorElements((element) {
          if (element is InheritedElement &&
              element.widget is InheritedTheme &&
              types.add(element.widget.runtimeType)) {
            if (widget.visible) context.dependOnInheritedElement(element);
            themes.add(element.widget as InheritedTheme);
          }
          return true;
        });
        final media = MediaQuery.maybeOf(context);
        final sameThemes =
            _themes != null &&
            _themes!.length == themes.length &&
            Iterable<int>.generate(
              themes.length,
            ).every((index) => identical(_themes![index], themes[index]));
        if (_presentation == null ||
            !identical(_child, widget.child) ||
            _constraints != constraints ||
            _media != media ||
            !sameThemes) {
          Widget child = OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: constraints.minWidth,
            maxWidth: constraints.maxWidth,
            minHeight: constraints.minHeight,
            maxHeight: constraints.maxHeight,
            child: widget.child,
          );
          if (media != null) child = MediaQuery(data: media, child: child);
          _presentation = InheritedTheme.capture(
            from: context,
            to: null,
          ).wrap(child);
          _themes = themes;
          _media = media;
          _constraints = constraints;
          _child = widget.child;
        }
      }
      _wasVisible = widget.visible;
      return _presentation!;
    },
  );
}
