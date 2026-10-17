import 'package:flutter/material.dart';

import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import '../widgets/common.dart';
import '../widgets/orion_logo.dart';
import '../widgets/selected_builder.dart';

class SettingsScreen extends StatelessWidget {
  final OrionController controller;
  final VoidCallback onReplayIntro;

  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onReplayIntro,
  });

  @override
  Widget build(BuildContext context) => SelectedBuilder(
    listenable: controller,
    select: () => (
      controller.orionCompactMode,
      controller.orionEnlargedMode,
      controller.alwaysOnTop,
      controller.autosave,
      controller.persistenceError,
      controller.editorFontSize,
      controller.showMinimap,
      controller.showLineNumbers,
      controller.wordWrap,
      controller.autocomplete,
      controller.bracketPairColorization,
      controller.renderWhitespace,
    ),
    builder: (context, _) {
      final colors = OrionColors.of(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final preferences = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsSection(
                title: 'Window',
                icon: Icons.web_asset_rounded,
                children: [
                  _PreferenceSwitch(
                    preferenceKey: 'compact-mode',
                    title: 'Compact mode',
                    description: 'A smaller window with denser controls.',
                    value: controller.orionCompactMode,
                    onChanged: controller.setOrionCompactMode,
                  ),
                  _PreferenceSwitch(
                    preferenceKey: 'enlarged-mode',
                    title: 'Enlarged mode',
                    description: 'More room at the regular control size.',
                    value: controller.orionEnlargedMode,
                    onChanged: controller.setOrionEnlargedMode,
                  ),
                  _PreferenceSwitch(
                    preferenceKey: 'always-on-top',
                    title: 'Always on top',
                    description: 'Keep Orion above other windows.',
                    value: controller.alwaysOnTop,
                    onChanged: controller.setAlwaysOnTop,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Editor(controller: controller),
              const SizedBox(height: 12),
              _SettingsSection(
                title: 'Workspace',
                icon: Icons.restore_rounded,
                children: [
                  _PreferenceSwitch(
                    preferenceKey: 'local-recovery',
                    title: 'Local recovery',
                    description: 'Restore unsaved scripts when Orion opens.',
                    value: controller.autosave,
                    onChanged: controller.setAutosave,
                  ),
                ],
              ),
            ],
          );
          final shortcuts = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Shortcuts(),
              const SizedBox(height: 16),
              _About(onReplayIntro: onReplayIntro),
            ],
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Settings', style: OrionType.pageTitle),
                    ),
                    if (constraints.maxWidth > 500)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            controller.persistenceError == null
                                ? Icons.check_rounded
                                : Icons.warning_amber_rounded,
                            size: 14,
                            color: controller.persistenceError == null
                                ? colors.muted
                                : colors.readablePeach,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            controller.persistenceError == null
                                ? 'Saved locally'
                                : 'Could not save',
                            style: OrionType.metadata.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (constraints.maxWidth >= 860)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: preferences),
                      const SizedBox(width: 24),
                      SizedBox(width: 290, child: shortcuts),
                    ],
                  )
                else ...[
                  preferences,
                  const SizedBox(height: 22),
                  shortcuts,
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

class _Editor extends StatelessWidget {
  final OrionController controller;
  const _Editor({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    return _SettingsSection(
      title: 'Editor',
      icon: Icons.code_rounded,
      children: [
        _ControlRow(
          title: 'Font size',
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('settings-editor-font-size'),
                  value: controller.editorFontSize.clamp(11, 22),
                  min: 11,
                  max: 22,
                  divisions: 11,
                  label: '${controller.editorFontSize.round()} px',
                  semanticFormatterCallback: (value) =>
                      'Editor font size, ${value.round()} pixels',
                  onChanged: controller.setEditorFontSize,
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '${controller.editorFontSize.round()} px',
                  textAlign: TextAlign.end,
                  style: OrionType.metadata.copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
        ),
        _PreferenceSwitch(
          preferenceKey: 'minimap',
          title: 'Minimap',
          value: controller.showMinimap,
          onChanged: controller.setShowMinimap,
        ),
        _PreferenceSwitch(
          preferenceKey: 'line-numbers',
          title: 'Line numbers',
          value: controller.showLineNumbers,
          onChanged: controller.setShowLineNumbers,
        ),
        _PreferenceSwitch(
          preferenceKey: 'word-wrap',
          title: 'Word wrap',
          value: controller.wordWrap,
          onChanged: controller.setWordWrap,
        ),
        _PreferenceSwitch(
          preferenceKey: 'autocomplete',
          title: 'Autocomplete',
          description: 'Show suggestions while typing.',
          value: controller.autocomplete,
          onChanged: controller.setAutocomplete,
        ),
        _PreferenceSwitch(
          preferenceKey: 'bracket-colors',
          title: 'Bracket colors',
          value: controller.bracketPairColorization,
          onChanged: controller.setBracketPairColorization,
        ),
        _PreferenceSwitch(
          preferenceKey: 'whitespace',
          title: 'Show whitespace',
          value: controller.renderWhitespace,
          onChanged: controller.setRenderWhitespace,
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    return SurfaceCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: colors.readableAccent),
                const SizedBox(width: 9),
                Text(title, style: OrionType.sectionTitle),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final String title;
  final Widget child;
  const _ControlRow({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 330) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: OrionType.body),
            const SizedBox(height: 2),
            Align(alignment: Alignment.centerLeft, child: child),
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 92, child: Text(title, style: OrionType.body)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: child),
          ),
        ],
      );
    },
  );
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Keyboard shortcuts', style: OrionType.sectionTitle),
      const SizedBox(height: 12),
      for (final shortcut in const [
        ('New script', 'Ctrl + N'),
        ('Save script', 'Ctrl + S'),
        ('Open a file', 'Ctrl + O'),
        ('Find in script', 'Ctrl + F'),
        ('Replace', 'Ctrl + H'),
        ('Luau completion', 'Ctrl + Space'),
        ('Format indentation', 'Shift + Alt + F'),
        ('Undo', 'Ctrl + Z'),
        ('Redo', 'Shift + Ctrl + Z'),
        ('Execute', 'Ctrl + Enter'),
        ('Command palette', 'Ctrl + K'),
      ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(shortcut.$1, style: OrionType.body)),
              const SizedBox(width: 12),
              _KeyCap(shortcut.$2),
            ],
          ),
        ),
    ],
  );
}

class _About extends StatelessWidget {
  final VoidCallback onReplayIntro;
  const _About({required this.onReplayIntro});

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    return Column(
      children: [
        Divider(color: colors.outline(.5)),
        const SizedBox(height: 16),
        Row(
          children: [
            const OrionLogo(size: 26),
            const SizedBox(width: 10),
            Text(
              '1.0.0',
              style: OrionType.metadata.copyWith(color: colors.muted),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onReplayIntro,
              icon: const Icon(Icons.replay_rounded, size: 15),
              label: const Text('Replay intro'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                textStyle: OrionType.label.copyWith(
                  fontFamily: Theme.of(
                    context,
                  ).textTheme.labelLarge?.fontFamily,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  final String preferenceKey;
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PreferenceSwitch({
    required this.preferenceKey,
    required this.title,
    this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => onChanged(!value),
      canRequestFocus: false,
      excludeFromSemantics: true,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: OrionType.body),
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description!,
                        style: OrionType.metadata.copyWith(
                          color: OrionColors.of(context).muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: title,
              child: Switch(
                key: ValueKey('settings-$preferenceKey'),
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _KeyCap extends StatelessWidget {
  final String text;
  const _KeyCap(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.chrome(
          colors.elevated.withValues(alpha: .5),
          role: 'elevated',
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: OrionType.metadata.copyWith(color: colors.muted),
      ),
    );
  }
}
