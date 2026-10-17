import 'package:flutter/material.dart';
import 'synapse_v3_theme.dart';

class V3PanelButton extends StatelessWidget {
  const V3PanelButton(
    this.label, {
    super.key,
    this.onPressed,
    this.width,
    this.height = 33,
    this.icon,
    this.selected = false,
    this.tooltip,
  });
  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final Widget? icon;
  final bool selected;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    final button = SizedBox(
      width: width,
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10),
          ),
          minimumSize: WidgetStateProperty.all(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          side: WidgetStateProperty.all(
            BorderSide(color: selected ? c.accent : c.settingsBorder),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.hovered)
                ? c.settingsControlHover
                : selected
                ? c.tabActive
                : c.settingsControl,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.muted : c.text,
          ),
          textStyle: WidgetStateProperty.all(
            V3Type.text(
              13,
              family: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 5)],
            Text(label),
          ],
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class V3Checkbox extends StatelessWidget {
  const V3Checkbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    return Semantics(
      label: label,
      checked: value,
      child: SizedBox(
        width: 30,
        height: 30,
        child: TextButton(
          onPressed: () => onChanged(!value),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: c.description),
            backgroundColor: value ? c.checkboxOn : c.checkboxOff,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          child: value
              ? CustomPaint(
                  size: const Size(13, 9),
                  painter: _V3Tick(
                    c.checkboxOn.computeLuminance() > .4
                        ? const Color(0xff0f2433)
                        : Colors.white,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _V3Tick extends CustomPainter {
  const _V3Tick(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 13.5, size.height / 9.5);
    canvas.drawPath(
      Path()
        ..moveTo(12.5, 1)
        ..lineTo(5.50005, 8.5)
        ..lineTo(1.00005, 5),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_V3Tick old) => old.color != color;
}

class V3SectionHeading extends StatelessWidget {
  const V3SectionHeading(this.title, {super.key, this.icon});
  final String title;
  final Widget? icon;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    return Container(
      height: 33,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.settingsHeader,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 9),
        ],
      ),
      child: Row(
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 8)],
          Text(title, style: V3Type.text(16, color: c.text)),
        ],
      ),
    );
  }
}

class V3PreferenceRow extends StatelessWidget {
  const V3PreferenceRow(
    this.label,
    this.description, {
    super.key,
    required this.control,
    this.controlWidth,
  });
  final String label, description;
  final Widget control;
  final double? controlWidth;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: V3Type.text(14, color: c.text, height: 1.4)),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            description,
            style: V3Type.text(13, color: c.description, height: 1.35),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wrap = constraints.maxWidth < 440 && (controlWidth ?? 30) > 150;
          return wrap
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [texts, const SizedBox(height: 9), control],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: texts),
                    const SizedBox(width: 16),
                    if (controlWidth != null)
                      SizedBox(width: controlWidth, child: control)
                    else
                      control,
                  ],
                );
        },
      ),
    );
  }
}

class V3RangeControl extends StatefulWidget {
  const V3RangeControl({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.format,
    this.commitOnRelease = false,
  });
  final String label;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String Function(double) format;
  final bool commitOnRelease;
  @override
  State<V3RangeControl> createState() => _V3RangeControlState();
}

class _V3RangeControlState extends State<V3RangeControl> {
  double? _preview;
  bool _pointerDown = false;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    final value = _preview ?? widget.value;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            widget.format(value),
            style: V3Type.text(12, color: c.accentMuted),
          ),
        ),
        Expanded(
          child: Listener(
            onPointerDown: (_) {
              _pointerDown = true;
            },
            onPointerCancel: (_) {
              setState(() {
                _pointerDown = false;
                _preview = null;
              });
            },
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: c.accent,
                inactiveTrackColor: c.settingsBorder,
                thumbColor: c.accentMuted,
                overlayColor: c.accent.withValues(alpha: .15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(widget.min, widget.max),
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                semanticFormatterCallback: (v) =>
                    '${widget.label}: ${widget.format(v)}',
                onChanged: (v) {
                  if (widget.commitOnRelease && _pointerDown) {
                    setState(() => _preview = v);
                  } else {
                    widget.onChanged(v);
                  }
                },
                onChangeEnd: (v) {
                  _pointerDown = false;
                  _preview = null;
                  widget.onChanged(v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration v3InputDecoration(
  BuildContext context, {
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final c = V3Colors.of(context);
  return InputDecoration(
    hintText: hint,
    hintStyle: V3Type.text(12, color: c.searchPlaceholder),
    filled: true,
    fillColor: c.settingsField,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: c.settingsFieldBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: c.focus),
    ),
  );
}
