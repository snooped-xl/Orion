import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/orion_theme_preferences.dart';
import '../models/interface_preset.dart';
import '../services/monaco_editor_service.dart';
import '../services/synapse_theme_studio_service.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import '../widgets/logo_control.dart';
import '../widgets/orion_glass.dart';
import '../widgets/orion_overlay.dart';
import '../widgets/theme_color_picker.dart';
import '../widgets/selected_builder.dart';

Widget _glassPanel(
  OrionColors colors,
  Widget child, {
  double radius = 20,
  bool interactive = false,
}) => colors.glassEnabled
    ? Builder(
        builder: (context) => OrionGlassSurface.hasMaterialAncestor(context)
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.ink.withValues(alpha: .025),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: child,
              )
            : OrionGlassSurface(
                radius: radius,
                tint: colors.panel.withValues(alpha: .035),
                interactive: interactive,
                child: child,
              ),
      )
    : child;

class ThemeControlScreen extends StatefulWidget {
  const ThemeControlScreen({
    super.key,
    required this.controller,
    this.editorService,
  });
  final OrionController controller;
  final MonacoEditorService? editorService;
  @override
  State<ThemeControlScreen> createState() => _ThemeControlScreenState();
}

class _ThemeControlScreenState extends State<ThemeControlScreen> {
  static const _sectionRadius = BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
    bottomLeft: Radius.circular(20),
    bottomRight: Radius.circular(5),
  );

  OrionController get c => widget.controller;
  OrionThemePreferences get preferences => c.orionTheme;

  void _edit(OrionThemePreferences value) =>
      c.setOrionTheme(value.copyWith(presetId: 'custom'));

  Future<void> _pick(
    String title,
    Color color,
    ValueChanged<Color> apply,
  ) async {
    final result = await showThemeColorPicker(
      context,
      color: color,
      title: title,
      controller: c,
    );
    if (mounted && result != null) apply(result);
  }

  void _message(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _save() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => OrionOverlayTheme(
        controller: c,
        builder: (_) => const _ThemeNameDialog(),
      ),
    );
    if (!mounted || name == null) return;
    c.saveOrionTheme(name);
    _message('Theme saved');
  }

  Future<void> _import() => showDialog<void>(
    context: context,
    builder: (_) => OrionOverlayTheme(
      controller: c,
      builder: (_) => _ThemeImportDialog(importTheme: c.importOrionTheme),
    ),
  );

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: c.exportOrionTheme()));
    if (mounted) _message('Theme JSON copied');
  }

  @override
  Widget build(BuildContext context) => SelectedBuilder(
    listenable: c,
    select: () => (
      preferences: c.orionTheme,
      savedThemes: _SavedThemeSelection(c.savedOrionThemes),
      logo: c.customLogoBytes,
      scale: c.uiScale,
      reducedMotion: c.reducedMotion,
    ),
    builder: (context, _) {
      final colors = OrionColors.of(context);
      return SingleChildScrollView(
        key: const PageStorageKey('theme-control-scroll'),
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Theme Control', style: OrionType.pageTitle),
                ),
                IconButton(
                  tooltip: 'Save current theme',
                  onPressed: _save,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 19),
                ),
                TextButton.icon(
                  key: const ValueKey('theme-reset'),
                  onPressed: c.resetOrionTheme,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Reset to default'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _section(
              padding: EdgeInsets.zero,
              interactive: true,
              child: ListTile(
                key: const ValueKey('orion-theme-studio'),
                contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                shape: RoundedRectangleBorder(
                  borderRadius: colors.glassEnabled
                      ? BorderRadius.circular(20)
                      : _sectionRadius,
                ),
                leading: Icon(
                  Icons.design_services_rounded,
                  color: colors.readableAccent,
                ),
                title: const Text(
                  'Theme Studio',
                  style: OrionType.sectionTitle,
                ),
                subtitle: const Text(
                  'Advanced Theme Editing, saving, exporting, and more',
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                onTap: () => openThemeStudio(
                  context,
                  controller: c,
                  preset: InterfacePreset.orion,
                  editorService: widget.editorService,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _presetGrid(),
            const SizedBox(height: 12),
            _section(child: _easyTheme()),
            const SizedBox(height: 10),
            _expansion(
              key: const ValueKey('theme-fine-tuning'),
              title: 'Fine tuning',
              icon: Icons.tune_rounded,
              child: _fineTuning(colors),
            ),
            const SizedBox(height: 6),
            _expansion(
              key: const ValueKey('theme-saved-themes'),
              title: 'Saved themes',
              icon: Icons.bookmarks_outlined,
              child: _savedThemes(),
            ),
            const SizedBox(height: 6),
            _expansion(
              key: const ValueKey('theme-layout-controls'),
              title: 'Layout & motion',
              icon: Icons.view_compact_alt_outlined,
              child: _layoutControls(),
            ),
            const SizedBox(height: 6),
            _expansion(
              key: const ValueKey('theme-branding'),
              title: 'Logo',
              icon: Icons.image_outlined,
              child: LogoControl(
                controller: c,
                image: c.customLogoBytes,
                onChanged: c.setCustomLogo,
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _section({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 10, 14, 10),
    bool interactive = false,
  }) {
    final colors = OrionColors.of(context);
    return _glassPanel(
      colors,
      Material(
        color: colors.chrome(colors.panel, role: 'panel'),
        shape: RoundedRectangleBorder(
          borderRadius: colors.glassEnabled
              ? BorderRadius.circular(20)
              : _sectionRadius,
          side: colors.glassEnabled
              ? BorderSide.none
              : BorderSide(color: colors.outline(.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
      interactive: interactive,
    );
  }

  Widget _presetGrid() => LayoutBuilder(
    builder: (context, box) {
      const gap = 10.0;
      final columns = box.maxWidth < 340 ? 1 : 2;
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        key: const ValueKey('theme-default-presets'),
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final preset in OrionThemePreferences.builtInPresets.take(
            OrionThemePreferences.primaryPresetCount,
          ))
            SizedBox(
              width: width,
              child: _PresetCard(
                preset: preset,
                selected: preferences.presetId == preset.id,
                onPressed: () => c.setOrionTheme(preset.preferences),
              ),
            ),
        ],
      );
    },
  );

  Widget _expansion({
    required Key key,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final colors = OrionColors.of(context);
    return KeyedSubtree(
      key: PageStorageKey(key),
      child: _glassPanel(
        colors,
        Material(
          color: colors.chrome(colors.panel, role: 'panel'),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: key,
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            leading: Icon(icon, size: 18, color: colors.muted),
            title: Text(title, style: OrionType.label),
            shape: const Border(),
            collapsedShape: const Border(),
            children: [child],
          ),
        ),
        radius: 16,
      ),
    );
  }

  Widget _easyTheme() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text('Easy theme', style: OrionType.sectionTitle),
          ),
          Text('Gradient', style: OrionType.label),
          const SizedBox(width: 8),
          Switch(
            key: const ValueKey('theme-gradient-switch'),
            value: preferences.gradientEnabled,
            onChanged: (value) =>
                _edit(preferences.copyWith(gradientEnabled: value)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
      const SizedBox(height: 4),
      _row(
        'Accent',
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final color in const [
              Color(0xff88b5ff),
              Color(0xffc7b9f8),
              Color(0xffd5f58d),
              Color(0xfff3bba1),
            ])
              _Swatch(
                color: color,
                selected: preferences.accent == color,
                tooltip: 'Accent ${themeColorHex(color)}',
                onPressed: () => _edit(preferences.copyWith(accent: color)),
              ),
            SizedBox(
              height: 30,
              child: OutlinedButton.icon(
                key: const ValueKey('theme-accent-custom'),
                onPressed: () => _pick(
                  'Accent',
                  preferences.accent,
                  (color) => _edit(preferences.copyWith(accent: color)),
                ),
                icon: Icon(
                  Icons.colorize_rounded,
                  size: 14,
                  color: OrionColors.of(context).readableAccent,
                ),
                label: Text(
                  themeColorHex(preferences.accent),
                  style: OrionType.metadata,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 30),
                ),
              ),
            ),
          ],
        ),
      ),
      if (preferences.gradientEnabled) ...[
        const SizedBox(height: 10),
        _row(
          'Color stops',
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (
                var index = 0;
                index < preferences.gradientColors.length;
                index++
              )
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Swatch(
                      key: ValueKey('theme-gradient-stop-$index'),
                      color: preferences.gradientColors[index],
                      tooltip: 'Edit gradient stop ${index + 1}',
                      onPressed: () => _pick(
                        'Gradient stop ${index + 1}',
                        preferences.gradientColors[index],
                        (color) {
                          final stops = List<Color>.of(
                            preferences.gradientColors,
                          )..[index] = color;
                          _edit(preferences.copyWith(gradientColors: stops));
                        },
                      ),
                    ),
                    if (preferences.gradientColors.length > 2)
                      SizedBox(
                        width: 23,
                        height: 30,
                        child: IconButton(
                          tooltip: 'Remove stop ${index + 1}',
                          onPressed: () {
                            final stops = List<Color>.of(
                              preferences.gradientColors,
                            )..removeAt(index);
                            _edit(preferences.copyWith(gradientColors: stops));
                          },
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close_rounded, size: 13),
                        ),
                      ),
                  ],
                ),
              if (preferences.gradientColors.length < 4)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton.filledTonal(
                    key: const ValueKey('theme-gradient-add'),
                    tooltip: 'Add color stop',
                    onPressed: () => _edit(
                      preferences.copyWith(
                        gradientColors: [
                          ...preferences.gradientColors,
                          Color.lerp(
                            preferences.gradientColors.last,
                            preferences.accent,
                            .5,
                          )!,
                        ],
                      ),
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add_rounded, size: 17),
                  ),
                ),
            ],
          ),
        ),
        _slider(
          'Angle',
          preferences.gradientAngle,
          0,
          360,
          '${preferences.gradientAngle.round()}°',
          (value) => _edit(preferences.copyWith(gradientAngle: value)),
          key: const ValueKey('theme-gradient-angle'),
        ),
      ],
      _slider(
        'Surface tint',
        preferences.surfaceTint,
        0,
        1,
        '${(preferences.surfaceTint * 100).round()}%',
        (value) => _edit(preferences.copyWith(surfaceTint: value)),
        key: const ValueKey('theme-surface-tint'),
      ),
      _slider(
        'Outlines',
        preferences.outlineStrength,
        0,
        2,
        '${preferences.outlineStrength.toStringAsFixed(1)}×',
        (value) => _edit(preferences.copyWith(outlineStrength: value)),
        key: const ValueKey('theme-outline-strength'),
      ),
    ],
  );

  Widget _fineTuning(OrionColors colors) {
    final roles = <String, (String, Color)>{
      'background': ('Background', colors.background),
      'panel': ('Panels', colors.panel),
      'elevated': ('Raised surfaces', colors.elevated),
      'border': ('Borders', colors.border),
      'ink': ('Text', colors.ink),
      'muted': ('Secondary text', colors.muted),
      'editor': ('Editor', colors.editorColor),
      'lavender': ('Lavender', colors.lavender),
      'peach': ('Peach', colors.peach),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in OrionThemePreferences.builtInPresets.skip(
              OrionThemePreferences.primaryPresetCount,
            ))
              ActionChip(
                label: Text(preset.name),
                onPressed: () => c.setOrionTheme(preset.preferences),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (final role in roles.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(role.value.$1, style: OrionType.body)),
                _Swatch(
                  key: ValueKey('theme-role-${role.key}'),
                  color: preferences.overrides[role.key] ?? role.value.$2,
                  tooltip: 'Edit ${role.value.$1.toLowerCase()}',
                  onPressed: () => _pick(
                    role.value.$1,
                    preferences.overrides[role.key] ?? role.value.$2,
                    (color) => _edit(
                      preferences.copyWith(
                        overrides: {...preferences.overrides, role.key: color},
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: Text(
                    themeColorHex(
                      preferences.overrides[role.key] ?? role.value.$2,
                    ),
                    style: OrionType.metadata.copyWith(color: colors.muted),
                  ),
                ),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    key: ValueKey('theme-reset-role-${role.key}'),
                    tooltip: 'Reset ${role.value.$1.toLowerCase()}',
                    onPressed: preferences.overrides.containsKey(role.key)
                        ? () {
                            final overrides = Map<String, Color>.of(
                              preferences.overrides,
                            )..remove(role.key);
                            _edit(preferences.copyWith(overrides: overrides));
                          }
                        : null,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.undo_rounded, size: 15),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _savedThemes() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          FilledButton.tonalIcon(
            onPressed: _save,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Save current'),
          ),
          OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Import'),
          ),
          OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: const Text('Export JSON'),
          ),
        ],
      ),
      if (c.savedOrionThemes.isNotEmpty) const SizedBox(height: 8),
      for (final theme in c.savedOrionThemes)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  key: ValueKey('theme-saved-${theme.id}'),
                  onPressed: () => c.applySavedOrionTheme(theme.id),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: theme.preferences.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          theme.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_outward_rounded, size: 14),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Delete ${theme.name}',
                onPressed: () => c.deleteSavedOrionTheme(theme.id),
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _layoutControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _row(
        'Mode',
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.system, label: Text('System')),
          ],
          selected: {preferences.themeMode},
          onSelectionChanged: (values) =>
              c.setOrionTheme(preferences.copyWith(themeMode: values.first)),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      _ThemeUiScaleControl(controller: c),
      _switch('Reduce motion', c.reducedMotion, c.setReducedMotion),
      _switch(
        'Rain effect',
        preferences.rainEnabled,
        (value) => _edit(preferences.copyWith(rainEnabled: value)),
      ),
      _switch(
        'Glassy',
        preferences.liquidGlassEnabled,
        (value) => _edit(preferences.copyWith(liquidGlassEnabled: value)),
      ),
      _slider(
        'Window opacity',
        preferences.windowOpacity,
        .5,
        1,
        '${(preferences.windowOpacity * 100).round()}%',
        (value) => _edit(preferences.copyWith(windowOpacity: value)),
        key: const ValueKey('theme-window-opacity'),
      ),
    ],
  );

  Widget _row(String label, Widget child) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 360) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: OrionType.body),
            const SizedBox(height: 6),
            child,
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 94, child: Text(label, style: OrionType.body)),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      );
    },
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String display,
    ValueChanged<double> onChanged, {
    Key? key,
  }) => Row(
    children: [
      SizedBox(width: 94, child: Text(label, style: OrionType.body)),
      Expanded(
        child: SizedBox(
          height: 34,
          child: Slider(
            key: key,
            value: value,
            min: min,
            max: max,
            label: display,
            onChanged: onChanged,
          ),
        ),
      ),
      SizedBox(
        width: 38,
        child: Text(
          display,
          style: OrionType.metadata,
          textAlign: TextAlign.end,
        ),
      ),
    ],
  );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          canRequestFocus: false,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              Expanded(child: Text(label, style: OrionType.body)),
              Semantics(
                label: label,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      );
}

// The controller returns a fresh unmodifiable list on every read. The saved
// objects themselves are immutable, so comparing their references captures save,
// delete and import changes without rebuilding this entire page while typing.
class _SavedThemeSelection {
  const _SavedThemeSelection(this.themes);
  final List<SavedOrionTheme> themes;

  @override
  bool operator ==(Object other) =>
      other is _SavedThemeSelection && listEquals(themes, other.themes);

  @override
  int get hashCode => Object.hashAll(themes);
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.onPressed,
    required this.tooltip,
    this.selected = false,
  });
  final Color color;
  final VoidCallback onPressed;
  final String tooltip;
  final bool selected;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      label: tooltip,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outline,
              width: selected ? 2 : .7,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: color.computeLuminance() > .4
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    ),
  );
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onPressed,
  });
  final OrionThemePreset preset;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final p = preset.preferences;
    final preview = orionTheme(
      p.themeMode == ThemeMode.light ? Brightness.light : Brightness.dark,
      p.accent,
      preferences: p,
    ).extension<OrionColors>()!;
    final radius = colors.glassEnabled
        ? BorderRadius.circular(18)
        : const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(5),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: preset.name,
      child: _glassPanel(
        colors,
        Material(
          color: colors.chrome(colors.panel, role: 'panel'),
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('theme-preset-${preset.id}'),
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                border: colors.glassEnabled && !selected
                    ? null
                    : Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary.withValues(
                                alpha: colors.glassEnabled ? .65 : 1,
                              )
                            : colors.outline(.55),
                        width: colors.glassEnabled ? .5 : 1,
                      ),
                borderRadius: radius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    key: ValueKey('theme-preview-${preset.id}'),
                    height: 49,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: preview.backgroundGradient == null
                          ? preview.background
                          : null,
                      gradient: preview.backgroundGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 18,
                          decoration: BoxDecoration(
                            color: preview.chrome(preview.panel, role: 'panel'),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: p.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: DecoratedBox(
                            key: ValueKey('theme-preview-editor-${preset.id}'),
                            decoration: BoxDecoration(
                              color: preview.chrome(
                                preview.editorColor,
                                role: 'editor',
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: preview.outline(.5),
                                width: .5,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FractionallySizedBox(
                                    widthFactor: .52,
                                    child: Container(
                                      height: 3,
                                      color: p.accent,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  FractionallySizedBox(
                                    widthFactor: .9,
                                    child: Container(
                                      height: 3,
                                      color: preview.ink.withValues(alpha: .25),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  FractionallySizedBox(
                                    widthFactor: .68,
                                    child: Container(
                                      height: 3,
                                      color: p.accent.withValues(alpha: .35),
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
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 18,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            preset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OrionType.label,
                          ),
                        ),
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: selected
                              ? const Icon(Icons.check_circle_rounded, size: 15)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        radius: 18,
        interactive: true,
      ),
    );
  }
}

class _ThemeUiScaleControl extends StatefulWidget {
  const _ThemeUiScaleControl({required this.controller});
  final OrionController controller;
  @override
  State<_ThemeUiScaleControl> createState() => _ThemeUiScaleControlState();
}

class _ThemeUiScaleControlState extends State<_ThemeUiScaleControl> {
  final _focus = FocusNode();
  bool _pointerInteraction = false;
  double? _preview;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ThemeUiScaleControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _preview = null;
  }

  @override
  Widget build(BuildContext context) {
    final value = _preview ?? widget.controller.uiScale;
    return Row(
      children: [
        const SizedBox(
          width: 94,
          child: Text('UI scale', style: OrionType.body),
        ),
        Expanded(
          child: Listener(
            onPointerDown: (_) => _pointerInteraction = true,
            onPointerUp: (_) => _pointerInteraction = false,
            onPointerCancel: (_) => _pointerInteraction = false,
            child: Slider(
              key: const ValueKey('ui-scale-slider'),
              focusNode: _focus,
              value: value,
              min: .8,
              max: 1.25,
              divisions: 9,
              label: '${(value * 100).round()}%',
              semanticFormatterCallback: (value) =>
                  'UI scale, ${(value * 100).round()} percent',
              onChangeStart: (value) {
                if (_pointerInteraction) setState(() => _preview = value);
              },
              onChanged: (value) {
                if (_pointerInteraction || _preview != null) {
                  setState(() => _preview = value);
                } else {
                  widget.controller.setUiScale(value);
                }
              },
              onChangeEnd: (value) {
                setState(() => _preview = null);
                widget.controller.setUiScale(value);
              },
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${(value * 100).round()}%',
            style: OrionType.metadata,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _ThemeNameDialog extends StatefulWidget {
  const _ThemeNameDialog();
  @override
  State<_ThemeNameDialog> createState() => _ThemeNameDialogState();
}

class _ThemeNameDialogState extends State<_ThemeNameDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    child: OrionOverlaySurface(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Save theme', style: OrionType.sectionTitle),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('theme-save-name'),
              controller: _input,
              autofocus: true,
              maxLength: 48,
              decoration: const InputDecoration(
                labelText: 'Name',
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(context, value.trim());
                }
              },
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('theme-save-confirm'),
                  onPressed: _input.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(context, _input.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ThemeImportDialog extends StatefulWidget {
  const _ThemeImportDialog({required this.importTheme});
  final bool Function(String) importTheme;
  @override
  State<_ThemeImportDialog> createState() => _ThemeImportDialogState();
}

class _ThemeImportDialogState extends State<_ThemeImportDialog> {
  final _input = TextEditingController();
  bool _invalid = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    child: OrionOverlaySurface(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Import theme', style: OrionType.sectionTitle),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey('theme-import-json'),
                controller: _input,
                minLines: 3,
                maxLines: 6,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'Paste theme JSON',
                  errorText: _invalid ? 'Invalid Orion theme' : null,
                ),
                onChanged: (_) {
                  if (_invalid) setState(() => _invalid = false);
                },
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (widget.importTheme(_input.text)) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _invalid = true);
                      }
                    },
                    child: const Text('Import'),
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
