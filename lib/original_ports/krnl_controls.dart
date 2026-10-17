import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

abstract final class KrnlSource {
  static const window = Color(0xff121212);
  static const title = Color(0xff1d1d1d);
  static const menu = Color(0xff212121);
  static const button = Color(0xff242424);
  static const editor = Color(0xff282828);
  static TextStyle type(
    double size, {
    String font = 'OriginalSegoeUI',
    Color color = Colors.white,
    FontWeight weight = FontWeight.normal,
  }) => TextStyle(
    fontFamily: font,
    fontFamilyFallback: const ['OriginalSymbols', 'OriginalEmoji'],
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: 0,
    height: 1.15,
  );
}

/// Source flat WinForms/Bunifu rectangle, including its two hover colors.
class KrnlButton extends StatefulWidget {
  const KrnlButton(
    this.label, {
    super.key,
    this.onPressed,
    this.child,
    this.background = KrnlSource.button,
    this.hover = const Color(0xff272727),
    this.size = 13,
    this.font = 'OriginalSans',
    this.tooltip,
  });
  final String label, font;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Widget? child;
  final Color background, hover;
  final double size;
  @override
  State<KrnlButton> createState() => _KrnlButtonState();
}

class _KrnlButtonState extends State<KrnlButton> {
  bool hover = false, pressed = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.onPressed != null;
    Widget result = MouseRegion(
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() {
        hover = false;
        pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: active ? (_) => setState(() => pressed = true) : null,
        onTapUp: (_) => setState(() => pressed = false),
        onTapCancel: () => setState(() => pressed = false),
        child: Semantics(
          button: true,
          enabled: active,
          label: widget.label,
          child: ColoredBox(
            color: !active
                ? const Color(0xff1b1b1b)
                : pressed
                ? const Color(0xff282828)
                : hover
                ? widget.hover
                : widget.background,
            child: Center(
              child:
                  widget.child ??
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: KrnlSource.type(widget.size, font: widget.font),
                  ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

/// KrnlTabControl.cs draws on native content-sized tab rectangles. In Normal
/// size mode ItemSize.Width=240 is ignored; the Win32 minimum width is 54px.
/// This strip keeps those rectangles separate from the centered form buttons.
class KrnlTabStrip extends StatefulWidget {
  const KrnlTabStrip({
    super.key,
    required this.tabs,
    required this.activeId,
    required this.onSelect,
    required this.onAdd,
    required this.onSwap,
    required this.onMenu,
  });
  final List<({String id, String title})> tabs;
  final String activeId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final void Function(String sourceId, String targetId) onSwap;
  final void Function(String id, Offset position) onMenu;

  @override
  State<KrnlTabStrip> createState() => _KrnlTabStripState();
}

class _KrnlTabStripState extends State<KrnlTabStrip> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  String? _draggedId, _lastTarget;
  double _availableWidth = 0;

  List<double> get _widths => [
    for (final tab in widget.tabs)
      (() {
        final painter = TextPainter(
          text: TextSpan(text: tab.title, style: KrnlSource.type(11)),
          textDirection: TextDirection.ltr,
        )..layout();
        return (painter.width.ceilToDouble() + 12).clamp(54.0, double.infinity);
      })(),
    54,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }

  @override
  void didUpdateWidget(covariant KrnlTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeId != widget.activeId ||
        oldWidget.tabs.length != widget.tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealActive() {
    if (!mounted || !_scroll.hasClients || _availableWidth <= 0) return;
    final index = widget.tabs.indexWhere((tab) => tab.id == widget.activeId);
    if (index < 0) return;
    final widths = _widths;
    final left = widths.take(index).fold(0.0, (a, b) => a + b);
    // Keep the final add tab alongside a newly created/selected final script.
    final right =
        left + widths[index] + (index == widget.tabs.length - 1 ? 54 : 0);
    final offset = left < _scroll.offset
        ? left
        : right > _scroll.offset + _availableWidth
        ? right - _availableWidth
        : _scroll.offset;
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
  }

  void _step(bool forward) {
    if (!_scroll.hasClients) return;
    final boundaries = <double>[0];
    for (final width in _widths) {
      boundaries.add(boundaries.last + width);
    }
    final offset = forward
        ? boundaries.firstWhere(
            (x) => x > _scroll.offset + .5,
            orElse: () => _scroll.position.maxScrollExtent,
          )
        : boundaries.lastWhere((x) => x < _scroll.offset - .5, orElse: () => 0);
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
  }

  void _move(PointerMoveEvent event) {
    if (_draggedId == null || event.buttons & kPrimaryButton == 0) return;
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final point = box.globalToLocal(event.position);
    if (point.dy < 0 || point.dy >= 20) return;
    if (point.dx < 0) _step(false);
    if (point.dx >= _availableWidth) _step(true);
    final at = point.dx + _scroll.offset;
    var left = 0.0;
    final widths = _widths;
    for (var index = 0; index < widget.tabs.length; index++) {
      final right = left + widths[index];
      if (at >= left && at < right) {
        final target = widget.tabs[index].id;
        if (target != _draggedId && target != _lastTarget) {
          _lastTarget = target;
          widget.onSwap(_draggedId!, target);
        } else if (target == _draggedId) {
          _lastTarget = null;
        }
        return;
      }
      left = right;
    }
  }

  Widget _arrow(bool forward) => SizedBox(
    key: ValueKey('krnl-tabs-scroll-${forward ? 'right' : 'left'}'),
    width: 17,
    height: 18,
    child: Semantics(
      button: true,
      label: forward ? 'Scroll tabs right' : 'Scroll tabs left',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _step(forward),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xfff0f0f0),
            border: Border.all(color: const Color(0xffa0a0a0)),
          ),
          child: CustomPaint(painter: _KrnlTabArrowPainter(forward)),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final widths = _widths;
      final total = widths.fold(0.0, (a, b) => a + b);
      final overflow = total > box.maxWidth;
      _availableWidth = box.maxWidth - (overflow ? 34 : 0);
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _availableWidth,
            child: Listener(
              key: _viewport,
              behavior: HitTestBehavior.opaque,
              onPointerMove: _move,
              onPointerUp: (_) {
                _draggedId = null;
                _lastTarget = null;
              },
              onPointerCancel: (_) {
                _draggedId = null;
                _lastTarget = null;
              },
              child: SingleChildScrollView(
                controller: _scroll,
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.tabs.length; i++)
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) {
                          final id = widget.tabs[i].id;
                          if (event.buttons & kSecondaryButton != 0) {
                            widget.onMenu(id, event.position);
                          } else if (event.buttons & kPrimaryButton != 0) {
                            _draggedId = id;
                            _lastTarget = null;
                            widget.onSelect(id);
                          }
                        },
                        child: Semantics(
                          selected: widget.tabs[i].id == widget.activeId,
                          button: true,
                          label: widget.tabs[i].title,
                          onTap: () => widget.onSelect(widget.tabs[i].id),
                          child: SizedBox(
                            key: ValueKey('krnl-tab-${widget.tabs[i].id}'),
                            width: widths[i],
                            height: 20,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (widget.tabs[i].id == widget.activeId)
                                  Positioned(
                                    left: -3,
                                    top: -3,
                                    width: widths[i],
                                    height: 21,
                                    child: const ColoredBox(
                                      color: KrnlSource.button,
                                    ),
                                  ),
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 2),
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: SizedBox(
                                        height: 16,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            widget.tabs[i].title,
                                            maxLines: 1,
                                            overflow: TextOverflow.clip,
                                            style: KrnlSource.type(11),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      key: const ValueKey('krnl-add-tab'),
                      width: 54,
                      height: 20,
                      child: Semantics(
                        button: true,
                        label: 'Add script tab',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onAdd,
                          child: Stack(
                            children: [
                              Positioned(
                                right: 8,
                                top: -4,
                                child: Text(
                                  '+',
                                  style: KrnlSource.type(
                                    18.6666667,
                                    font: 'OriginalSans',
                                    color: const Color(0xfff5f5f5),
                                    weight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 3.5,
            child: IgnorePointer(child: ColoredBox(color: KrnlSource.button)),
          ),
          if (overflow)
            Positioned(
              right: 0,
              top: 0,
              height: 18,
              child: Row(children: [_arrow(false), _arrow(true)]),
            ),
        ],
      );
    },
  );
}

class _KrnlTabArrowPainter extends CustomPainter {
  const _KrnlTabArrowPainter(this.forward);
  final bool forward;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final direction = forward ? 1 : -1;
    final path = Path()
      ..moveTo(center.dx + direction * 2, center.dy)
      ..lineTo(center.dx - direction * 2, center.dy - 3)
      ..lineTo(center.dx - direction * 2, center.dy + 3)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xff202020));
  }

  @override
  bool shouldRepaint(_KrnlTabArrowPainter oldDelegate) =>
      oldDelegate.forward != forward;
}

class KrnlToggle extends StatelessWidget {
  const KrnlToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.reducedMotion,
  });
  final bool value, reducedMotion;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 54,
          height: 21,
          child: Stack(
            children: [
              Positioned(
                left: 5,
                top: 7,
                width: 27,
                height: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff232323),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 70),
                curve: Curves.linear,
                left: value ? 20 : 1,
                top: 2,
                width: 18,
                height: 18,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xff5b5b5b),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
