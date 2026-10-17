import 'package:flutter/material.dart';
import '../state/orion_controller.dart';
import 'orion_overlay.dart';

Future<Color?> showThemeColorPicker(
  BuildContext context, {
  required Color color,
  required String title,
  OrionController? controller,
}) => controller == null
    ? showDialog<Color>(
        context: context,
        builder: (_) => ThemeColorPicker(color: color, title: title),
      )
    : showOrionDialog<Color>(
        context,
        controller: controller,
        builder: (_) => ThemeColorPicker(color: color, title: title),
      );

/// Edits a local color draft. The caller receives a value only after Apply.
class ThemeColorPicker extends StatefulWidget {
  const ThemeColorPicker({super.key, required this.color, required this.title});
  final Color color;
  final String title;
  @override
  State<ThemeColorPicker> createState() => _ThemeColorPickerState();
}

class _ThemeColorPickerState extends State<ThemeColorPicker> {
  late HSVColor _hsv;
  late final TextEditingController _hex;
  bool _valid = true;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
    _hex = TextEditingController(text: themeColorHex(widget.color));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor value) {
    setState(() {
      _hsv = value;
      _valid = true;
      _hex.text = themeColorHex(value.toColor());
    });
  }

  void _setHex(String value) {
    final text = value.trim().replaceFirst(RegExp(r'^#'), '');
    final valid = RegExp(r'^(?:[a-fA-F0-9]{6}|[a-fA-F0-9]{8})$').hasMatch(text);
    setState(() {
      _valid = valid;
      if (valid) {
        final parsed = int.parse(text, radix: 16);
        _hsv = HSVColor.fromColor(
          Color(text.length == 6 ? 0xff000000 | parsed : parsed),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: OrionOverlaySurface(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(6),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 390,
            maxHeight: MediaQuery.sizeOf(context).height - 32,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Container(
                      key: const ValueKey('theme-color-preview'),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _hsv.toColor(),
                        border: Border.all(color: scheme.outline),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 132,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              void select(Offset point) => _setHsv(
                                _hsv
                                    .withSaturation(
                                      (point.dx / box.maxWidth).clamp(0, 1),
                                    )
                                    .withValue(
                                      (1 - point.dy / box.maxHeight).clamp(
                                        0,
                                        1,
                                      ),
                                    ),
                              );
                              return Semantics(
                                label: 'Saturation and brightness',
                                child: GestureDetector(
                                  key: const ValueKey('theme-color-plane'),
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (event) =>
                                      select(event.localPosition),
                                  onPanStart: (event) =>
                                      select(event.localPosition),
                                  onPanUpdate: (event) =>
                                      select(event.localPosition),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: CustomPaint(
                                      painter: _SaturationPainter(_hsv),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.red,
                                  Colors.yellow,
                                  Colors.green,
                                  Colors.cyan,
                                  Colors.blue,
                                  Colors.purple,
                                  Colors.red,
                                ],
                              ),
                            ),
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 24,
                                activeTrackColor: Colors.transparent,
                                inactiveTrackColor: Colors.transparent,
                                overlayColor: Colors.transparent,
                                thumbColor: Colors.white,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                              ),
                              child: SizedBox(
                                height: 26,
                                child: Slider(
                                  key: const ValueKey('theme-hue-slider'),
                                  value: _hsv.hue,
                                  min: 0,
                                  max: 360,
                                  semanticFormatterCallback: (value) =>
                                      'Hue ${value.round()} degrees',
                                  onChanged: (value) =>
                                      _setHsv(_hsv.withHue(value)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('theme-color-hex'),
                          controller: _hex,
                          maxLength: 9,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Hex',
                            hintText: '#RRGGBB',
                            counterText: '',
                            errorText: _valid ? null : 'Use 6 or 8 hex digits',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          onChanged: _setHex,
                          onSubmitted: (_) {
                            if (_valid) Navigator.pop(context, _hsv.toColor());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      key: const ValueKey('theme-color-apply'),
                      onPressed: _valid
                          ? () => Navigator.pop(context, _hsv.toColor())
                          : null,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String themeColorHex(Color color) {
  final argb = color.toARGB32();
  return '#${(color.a == 1 ? argb & 0xffffff : argb).toRadixString(16).padLeft(color.a == 1 ? 6 : 8, '0').toUpperCase()}';
}

class _SaturationPainter extends CustomPainter {
  const _SaturationPainter(this.hsv);
  final HSVColor hsv;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final point = Offset(
      (hsv.saturation * size.width).clamp(7, size.width - 7),
      ((1 - hsv.value) * size.height).clamp(7, size.height - 7),
    );
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.black.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      point,
      5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SaturationPainter oldDelegate) => oldDelegate.hsv != hsv;
}
