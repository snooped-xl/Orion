import '../widgets/synapse_theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blue_theme.dart';

class BlueButton extends StatefulWidget {
  const BlueButton(
    this.label, {
    super.key,
    required this.palette,
    this.onPressed,
    this.width = 91,
    this.height = 36,
    this.fontSize = 13,
    this.family = 'SynapseInter',
    this.kind = 'editor',
    this.selected = false,
    this.tooltip,
  });
  final String label, family, kind;
  final BluePalette palette;
  final VoidCallback? onPressed;
  final double? width;
  final double height, fontSize;
  final bool selected;
  final String? tooltip;
  @override
  State<BlueButton> createState() => _BlueButtonState();
}

class _BlueButtonState extends State<BlueButton> {
  bool _hover = false, _focus = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final element = SynapseThemeElementStyleScope.maybeOf(context);
    final tool = widget.kind == 'tool';
    final hub = widget.kind == 'hub';
    final yes = widget.kind == 'yes';
    final no = widget.kind == 'no';
    var color = hub
        ? Colors.white
        : tool
        ? p.color('toolPanelsTheme.toolbarButtonText')
        : (yes || no)
        ? p.color('confirmationTheme.${yes ? 'yes' : 'no'}ButtonText')
        : p.color('editorControlBarText');
    var border = hub
        ? p.color('scriptHubTheme.ctaBorder')
        : tool
        ? p.color('toolPanelsTheme.toolbarButtonBorder')
        : (yes || no)
        ? p.color('confirmationTheme.${yes ? 'yes' : 'no'}ButtonBorder')
        : p.color('editorControlBarBorder');
    var gradient = tool || hub
        ? null
        : (yes || no)
        ? p.gradient(
            'confirmationTheme.${yes ? 'yes' : 'no'}ButtonFrom',
            'confirmationTheme.${yes ? 'yes' : 'no'}ButtonTo',
          )
        : _hover && widget.kind == 'attach'
        ? p.gradient('attachButtonHoverFrom', 'attachButtonHoverTo')
        : p.gradient(
            _hover ? 'editorControlBarHoverFrom' : 'editorControlBarButtonFrom',
            _hover ? 'editorControlBarHoverTo' : 'editorControlBarButtonTo',
          );
    var fill = tool
        ? p.color(
            widget.selected
                ? 'toolPanelsTheme.tabActiveBackground'
                : _hover
                ? 'toolPanelsTheme.toolbarButtonHoverBackground'
                : 'toolPanelsTheme.toolbarButtonBackground',
          )
        : hub
        ? p.color(
            _hover
                ? 'scriptHubTheme.ctaHoverBackground'
                : 'scriptHubTheme.ctaBackground',
          )
        : null;
    if (element?.image?.isValid == true && element!.image!.opacity > 0) {
      fill = Colors.transparent;
      gradient = null;
    } else if (element?.fill != null) {
      fill = Color(element!.fill!);
      gradient = null;
    }
    if (element?.foreground != null) color = Color(element!.foreground!);
    if (element?.border != null) border = Color(element!.border!);
    Widget button = Opacity(
      opacity: widget.onPressed == null ? .5 : 1,
      child: Semantics(
        button: true,
        enabled: widget.onPressed != null,
        label: widget.label,
        child: FocusableActionDetector(
          enabled: widget.onPressed != null,
          mouseCursor: widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: widget.onPressed,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: widget.width,
                height: widget.height,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: fill,
                  gradient: gradient,
                  border: Border.all(
                    color: _focus
                        ? p.color('surfaceElementsTheme.surfaceListFocusRing')
                        : border,
                  ),
                  borderRadius: element?.radius != null
                      ? BorderRadius.circular(element!.radius!)
                      : hub
                      ? BorderRadius.circular(4)
                      : null,
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.label,
                      style: blueText(
                        widget.fontSize,
                        color: color,
                        family:
                            SynapseThemeElementStyleScope.fontFamilyOf(
                              context,
                            ) ??
                            widget.family,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

class BlueOption extends StatelessWidget {
  const BlueOption(
    this.title,
    this.description, {
    super.key,
    required this.value,
    required this.onChanged,
    required this.palette,
    this.family = 'SynapseInter',
  });
  final String title, description, family;
  final bool value;
  final VoidCallback onChanged;
  final BluePalette palette;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Semantics(
            label: title,
            checked: value,
            button: true,
            child: FocusableActionDetector(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    onChanged();
                    return null;
                  },
                ),
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onChanged,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 14,
                    height: 13,
                    decoration: BoxDecoration(
                      color: Color(value ? 0xff5a9e5f : 0xffc0c0c0),
                      border: Border.all(color: const Color(0xff5a5a5a)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: blueText(
                  16,
                  weight: FontWeight.w500,
                  height: 1.42,
                  color: palette.color('toolPanelsTheme.sectionTitle'),
                  family: family,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: blueText(
                  10,
                  height: 1.42,
                  color: palette.color('toolPanelsTheme.sectionBody'),
                  family: family,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

InputDecoration blueInput(
  BluePalette p, {
  String? hint,
  EdgeInsets? padding,
}) => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: p.color('toolPanelsTheme.fieldBackground'),
  hintText: hint,
  hintStyle: blueText(10, color: p.color('toolPanelsTheme.fieldPlaceholder')),
  contentPadding:
      padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: p.color('toolPanelsTheme.fieldBorder')),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: p.color('toolPanelsTheme.fieldBorder')),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: p.color('toolPanelsTheme.fieldFocusBorder')),
  ),
);

class BlueDropdown extends StatelessWidget {
  const BlueDropdown({
    super.key,
    required this.value,
    required this.values,
    required this.onChanged,
    required this.palette,
    this.family = 'SynapseInter',
    this.height = 38,
  });
  final String value, family;
  final Map<String, String> values;
  final ValueChanged<String> onChanged;
  final BluePalette palette;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 7),
    color: const Color(0xff484848),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: values.containsKey(value) ? value : values.keys.first,
        isExpanded: true,
        isDense: true,
        dropdownColor: const Color(0xff484848),
        style: blueText(13, family: family),
        icon: const Icon(
          Icons.keyboard_arrow_down,
          size: 10,
          color: Color(0xff777777),
        ),
        items: [
          for (final entry in values.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ),
  );
}
