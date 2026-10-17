import 'package:flutter/widgets.dart';

/// Rebuilds a listening subtree only when the part of its state it reads changes.
///
/// [select] should return an immutable value with meaningful equality, such as a
/// record of relevant fields. Parent updates and inherited changes still rebuild
/// normally, so filtering notifications never freezes layout or theme changes.
class SelectedBuilder<T> extends StatefulWidget {
  const SelectedBuilder({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
    this.child,
  });

  final Listenable listenable;
  final T Function() select;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  State<SelectedBuilder<T>> createState() => _SelectedBuilderState<T>();
}

class _SelectedBuilderState<T> extends State<SelectedBuilder<T>> {
  late T _selection;

  @override
  void initState() {
    super.initState();
    _selection = widget.select();
    widget.listenable.addListener(_handleChange);
  }

  void _handleChange() {
    final next = widget.select();
    if (next == _selection) return;
    setState(() => _selection = next);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selection = widget.select();
  }

  @override
  void didUpdateWidget(SelectedBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_handleChange);
      widget.listenable.addListener(_handleChange);
    }
    _selection = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_handleChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}
