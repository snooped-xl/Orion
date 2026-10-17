import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/orion_models.dart';
import '../models/remote_script.dart';
import '../state/orion_controller.dart';
import '../widgets/synapse_theme_surface.dart';
import '../services/native_window_service.dart';
import 'synapse_v3_theme.dart';
import 'v3_icon.dart';
import 'v3_panel_controls.dart';

class _PanelSection {
  _PanelSection(this.label, this.icon) : key = GlobalKey();
  final String label, icon;
  final GlobalKey key;
}

/// The source's 58px icon rail links to actual scrollable sections.
class _SectionPage extends StatefulWidget {
  const _SectionPage({
    required this.controller,
    required this.sections,
    required this.children,
  });
  final OrionController controller;
  final List<_PanelSection> sections;
  final List<Widget> children;
  @override
  State<_SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<_SectionPage> {
  int _selected = 0;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    return ColoredBox(
      color: c.content,
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Column(
              children: [
                const SizedBox(height: 4),
                for (var i = 0; i < widget.sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Tooltip(
                      message: widget.sections[i].label,
                      child: Semantics(
                        selected: _selected == i,
                        button: true,
                        label: widget.sections[i].label,
                        child: SizedBox(
                          width: 51,
                          height: 36,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              backgroundColor: _selected == i
                                  ? c.settingsSidebarActive
                                  : Colors.transparent,
                            ),
                            onPressed: () {
                              setState(() => _selected = i);
                              final target =
                                  widget.sections[i].key.currentContext;
                              if (target != null) {
                                Scrollable.ensureVisible(
                                  target,
                                  duration:
                                      widget.controller.reducedMotion ||
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                      ? Duration.zero
                                      : const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                );
                              }
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_selected == i)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width: 3,
                                      height: 16,
                                      color: c.accentMuted,
                                    ),
                                  ),
                                V3Icon(
                                  widget.sections[i].icon,
                                  size: 18,
                                  color: c.sidebarIcon,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SynapseV3SettingsPage extends StatefulWidget {
  const SynapseV3SettingsPage({
    super.key,
    required this.controller,
    this.nativeWindow = false,
    this.onBackToOrion,
  });
  final OrionController controller;
  final bool nativeWindow;
  final VoidCallback? onBackToOrion;
  @override
  State<SynapseV3SettingsPage> createState() => _SynapseV3SettingsPageState();
}

class _SynapseV3SettingsPageState extends State<SynapseV3SettingsPage> {
  final _sections = [
    _PanelSection('Application', 'settingsApplication'),
    _PanelSection('Editor', 'settingsEditor'),
    _PanelSection('Terminal', 'settingsTerminal'),
    _PanelSection('Config', 'settingsConfig'),
  ];
  late final TextEditingController _defaultContent;
  @override
  void initState() {
    super.initState();
    _defaultContent = TextEditingController(
      text: widget.controller.synapsePreferences.defaultTabContent,
    );
  }

  @override
  void dispose() {
    _defaultContent.dispose();
    super.dispose();
  }

  Future<void> _nativeSetting(
    String label,
    bool value,
    Future<void> Function(bool) action,
    VoidCallback save,
  ) async {
    try {
      if (widget.nativeWindow) {
        await action(value);
      }
      save();
    } on Object catch (error) {
      if (mounted) {
        _message(context, '$label could not be changed: $error');
      }
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _V3Dialog(
        title: 'Reset all settings',
        actions: [
          V3PanelButton(
            'Cancel',
            onPressed: () => Navigator.pop(context, false),
          ),
          V3PanelButton('Reset', onPressed: () => Navigator.pop(context, true)),
        ],
        child: Text(
          'Reset V3 and shared editor preferences? Your scripts and favorites will be kept.',
          style: V3Type.text(13, color: V3Colors.of(context).text),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.controller.resetSynapsePreferences();
    _defaultContent.clear();
    if (widget.nativeWindow) {
      await NativeWindowService.setAlwaysOnTop(false);
      await NativeWindowService.setResizable(false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller,
          p = controller.synapsePreferences,
          c = V3Colors.of(context);
      Widget check(String label, bool value, ValueChanged<bool> changed) =>
          V3Checkbox(label: label, value: value, onChanged: changed);
      Widget heading(int i) => V3SectionHeading(
        _sections[i].label,
        key: _sections[i].key,
        icon: V3Icon(_sections[i].icon, size: 14, color: c.text),
      );
      return _SectionPage(
        controller: controller,
        sections: _sections,
        children: [
          heading(0),
          V3PreferenceRow(
            'Reset all settings',
            'Reset V3 and shared editor preferences.',
            control: V3PanelButton('Reset', width: 70, onPressed: _reset),
          ),
          V3PreferenceRow(
            'Top Most',
            'All Synapse windows to stay on top.',
            control: check(
              'Top Most',
              p.alwaysOnTop,
              (v) => _nativeSetting(
                'Top Most',
                v,
                NativeWindowService.setAlwaysOnTop,
                () => controller.updateSynapsePreferences(alwaysOnTop: v),
              ),
            ),
          ),
          V3PreferenceRow(
            'Resizable',
            'Allow dragging the window edges to resize.',
            control: check(
              'Resizable',
              p.resizable,
              (v) => _nativeSetting(
                'Resizable',
                v,
                (value) => NativeWindowService.setResizable(value),
                () => controller.updateSynapsePreferences(resizable: v),
              ),
            ),
          ),
          V3PreferenceRow(
            'Script Hub Source',
            'Choose the provider used by the Scripts tab.',
            controlWidth: 185,
            control: _V3Select<ScriptProvider?>(
              value: controller.selectedProvider,
              items: {
                null: 'All sources',
                for (final provider in ScriptProvider.values)
                  provider: provider == ScriptProvider.robloxScripts
                      ? 'robloxscripts.com'
                      : provider == ScriptProvider.rscripts
                      ? 'rscripts.net'
                      : provider.label,
              },
              onChanged: controller.setScriptProvider,
            ),
          ),
          V3PreferenceRow(
            'UI scale',
            'Scale the entire interface.',
            controlWidth: 190,
            control: V3RangeControl(
              label: 'UI scale',
              value: controller.uiScale,
              min: .8,
              max: 1.25,
              divisions: 9,
              commitOnRelease: true,
              format: (v) => '${(v * 100).round()}%',
              onChanged: controller.setUiScale,
            ),
          ),
          V3PreferenceRow(
            'Reduce motion',
            'Use immediate transitions.',
            control: check(
              'Reduce motion',
              controller.reducedMotion,
              controller.setReducedMotion,
            ),
          ),
          if (widget.onBackToOrion != null)
            V3PreferenceRow(
              'Orion workspace',
              'Return to Orion with your open scripts.',
              controlWidth: 135,
              control: V3PanelButton(
                'Back to Orion',
                key: const ValueKey('v3-back-to-orion'),
                onPressed: widget.onBackToOrion,
              ),
            ),
          heading(1),
          V3PreferenceRow(
            'Toggle script list',
            'Show the editor script list panel.',
            control: check(
              'Toggle script list',
              p.showScriptList,
              (v) => controller.updateSynapsePreferences(showScriptList: v),
            ),
          ),
          V3PreferenceRow(
            'Minimap',
            'Show a miniature view of the entire script on the right side.',
            control: check(
              'Minimap',
              p.minimap,
              (v) => controller.updateSynapsePreferences(minimap: v),
            ),
          ),
          V3PreferenceRow(
            'Compact editor buttons',
            'Reduces the size of editor buttons.',
            control: check(
              'Compact editor buttons',
              p.compactButtons,
              (v) => controller.updateSynapsePreferences(compactButtons: v),
            ),
          ),
          V3PreferenceRow(
            'Compact tabs',
            'Use compact square tabs instead of round padded ones.',
            control: check(
              'Compact tabs',
              p.compactTabs,
              (v) => controller.updateSynapsePreferences(compactTabs: v),
            ),
          ),
          V3PreferenceRow(
            'Editor font size',
            'Text size in the code editor.',
            controlWidth: 190,
            control: V3RangeControl(
              label: 'Editor font size',
              value: controller.editorFontSize,
              min: 11,
              max: 22,
              divisions: 11,
              format: (v) => '${v.round()}px',
              onChanged: controller.setEditorFontSize,
            ),
          ),
          V3PreferenceRow(
            'Word wrap',
            'Wrap long lines to the editor width.',
            control: check(
              'Word wrap',
              controller.wordWrap,
              controller.setWordWrap,
            ),
          ),
          V3PreferenceRow(
            'Line numbers',
            'Show line numbers beside the script.',
            control: check(
              'Line numbers',
              controller.showLineNumbers,
              controller.setShowLineNumbers,
            ),
          ),
          V3PreferenceRow(
            'Autosave',
            'Save changes to scripts with a file path.',
            control: check(
              'Autosave',
              controller.autosave,
              controller.setAutosave,
            ),
          ),
          heading(2),
          V3PreferenceRow(
            'Timestamps',
            'Show timestamps in the console.',
            control: check(
              'Timestamps',
              p.consoleTimestamp,
              (v) => controller.updateSynapsePreferences(consoleTimestamp: v),
            ),
          ),
          V3PreferenceRow(
            'Console font size',
            'Text size in the console.',
            controlWidth: 190,
            control: V3RangeControl(
              label: 'Console font size',
              value: p.consoleFontSize,
              min: 9,
              max: 18,
              divisions: 9,
              format: (v) => '${v.round()}px',
              onChanged: (v) =>
                  controller.updateSynapsePreferences(consoleFontSize: v),
            ),
          ),
          V3PreferenceRow(
            'Clear console',
            'Remove the current local log entries.',
            control: V3PanelButton(
              'Clear',
              width: 70,
              onPressed: controller.clearActivities,
            ),
          ),
          heading(3),
          V3PreferenceRow(
            'Default Tab Content',
            'What will be written to the contents of a new tab.',
            controlWidth: 250,
            control: TextField(
              controller: _defaultContent,
              style: V3Type.text(14, color: c.text),
              decoration: v3InputDecoration(context, hint: 'Content...'),
              onChanged: (v) =>
                  controller.updateSynapsePreferences(defaultTabContent: v),
            ),
          ),
        ],
      );
    },
  );
}

class _V3Select<T> extends StatelessWidget {
  const _V3Select({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    return Container(
      height: 33,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.settingsControl,
        border: Border.all(color: c.settingsBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(items[value] ?? '', style: V3Type.text(13, color: c.text)),
          isExpanded: true,
          isDense: true,
          dropdownColor: c.settingsControl,
          style: V3Type.text(13, color: c.text),
          icon: Icon(Icons.keyboard_arrow_down, size: 16, color: c.muted),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (items.containsKey(v)) onChanged(v as T);
          },
        ),
      ),
    );
  }
}

class _V3Dialog extends StatelessWidget {
  const _V3Dialog({
    required this.title,
    required this.child,
    required this.actions,
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    return Dialog(
      backgroundColor: c.content,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: V3Type.text(15, color: c.text, weight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              child,
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _message(BuildContext context, String message) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );

class SynapseV3ConsolePanel extends StatelessWidget {
  const SynapseV3ConsolePanel({
    super.key,
    required this.controller,
    this.colors,
    this.onClose,
    this.onResize,
    this.compactButtons = false,
  });
  final OrionController controller;
  final V3Colors? colors;
  final VoidCallback? onClose;
  final ValueChanged<double>? onResize;
  final bool compactButtons;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = colors ?? V3Colors.of(context),
          p = controller.synapsePreferences;
      final entries = controller.activities
          .where((entry) => entry.kind == ActivityKind.execution)
          .toList();
      return ColoredBox(
        color: c.editor,
        child: Column(
          children: [
            MouseRegion(
              cursor: onResize == null
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                key: const ValueKey('v3-console-resize'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: onResize == null
                    ? null
                    : (details) => onResize!(details.delta.dy),
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.tabActive,
                    border: Border(bottom: BorderSide(color: c.border)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      V3Icon('windowConsole20Filled', size: 13, color: c.text),
                      const SizedBox(width: 6),
                      Text(
                        'Console',
                        style: V3Type.text(
                          12,
                          color: c.text,
                          family:
                              SynapseThemeElementStyleScope.fontFamilyOf(
                                context,
                              ) ??
                              p.uiFontFamily,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: controller.bridgeConnected
                              ? c.attachConnected
                              : c.attachDisconnected,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          controller.bridgeConnected
                              ? 'Orion Bridge · ${controller.bridgeClients.length} connected'
                              : 'Orion Bridge · Not connected',
                          overflow: TextOverflow.ellipsis,
                          style: V3Type.text(
                            11,
                            color: c.muted,
                            family:
                                SynapseThemeElementStyleScope.fontFamilyOf(
                                  context,
                                ) ??
                                p.uiFontFamily,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: compactButtons ? 52 : 66,
                        height: compactButtons ? 22 : 23,
                        child: TextButton(
                          onPressed: controller.clearActivities,
                          style: ButtonStyle(
                            minimumSize: const WidgetStatePropertyAll(
                              Size.zero,
                            ),
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.zero,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                                side: BorderSide(color: c.buttonBorder),
                              ),
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.hovered)
                                  ? c.buttonHover
                                  : c.button,
                            ),
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              V3Icon(
                                'eraser20Filled',
                                size: compactButtons ? 10 : 12,
                                color: c.buttonIcon,
                              ),
                              SizedBox(width: compactButtons ? 3 : 4),
                              Text(
                                'Clear',
                                style: V3Type.text(
                                  compactButtons ? 10 : 12,
                                  color: c.buttonText,
                                  family:
                                      SynapseThemeElementStyleScope.fontFamilyOf(
                                        context,
                                      ) ??
                                      p.uiFontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (onClose != null)
                        SizedBox(
                          width: 26,
                          height: 24,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Close console',
                            onPressed: onClose,
                            icon: Icon(Icons.close, size: 14, color: c.muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  reverse: true,
                  children: entries.isEmpty
                      ? [
                          Text(
                            'No output yet.',
                            style: V3Type.text(
                              11,
                              color: c.muted,
                              height: 1.375,
                              family:
                                  SynapseThemeElementStyleScope.fontFamilyOf(
                                    context,
                                  ) ??
                                  p.uiFontFamily,
                            ),
                          ),
                        ]
                      : [
                          for (final entry in entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '${p.consoleTimestamp ? '[${_time(entry.timestamp)}] ' : ''}${entry.title}${entry.detail.isEmpty ? '' : ': ${entry.detail}'}',
                                style: TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: p.consoleFontSize,
                                  height: 1.375,
                                  color:
                                      entry.severity == ActivitySeverity.error
                                      ? c.error
                                      : entry.severity ==
                                            ActivitySeverity.warning
                                      ? c.attachDisconnected
                                      : c.rowText,
                                ),
                              ),
                            ),
                        ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
}

class SynapseV3Console extends SynapseV3ConsolePanel {
  const SynapseV3Console({
    super.key,
    required super.controller,
    super.colors,
    super.onClose,
    super.onResize,
    super.compactButtons,
  });
}

class SynapseV3HubPage extends StatefulWidget {
  const SynapseV3HubPage({
    super.key,
    required this.controller,
    this.onOpenEditor,
    this.onOpenScript,
    this.bridgeReady = false,
  });
  final OrionController controller;
  final VoidCallback? onOpenEditor;
  final Future<void> Function(RemoteScript)? onOpenScript;
  final bool bridgeReady;
  @override
  State<SynapseV3HubPage> createState() => _SynapseV3HubPageState();
}

class SynapseV3ScriptHubPage extends SynapseV3HubPage {
  const SynapseV3ScriptHubPage({
    super.key,
    required super.controller,
    super.onOpenEditor,
    super.onOpenScript,
    super.bridgeReady,
  });
}

class _SynapseV3HubPageState extends State<SynapseV3HubPage> {
  late final _search = TextEditingController(
    text: widget.controller.searchQuery,
  );
  int _source = 0, _page = 0;
  final _busy = <String>{};
  static const _pageSize = 12;
  List<RemoteScript> _builtins = [];
  static const _localImages = {
    'synapse-dark-dex': 'assets/synapse_v3/legacy_hub/dex.png',
    'synapse-unnamed-esp': 'assets/synapse_v3/legacy_hub/unnamedesp.png',
    'synapse-remote-spy': 'assets/synapse_v3/legacy_hub/RemoteSpy.png',
    'synapse-script-dumper': 'assets/synapse_v3/legacy_hub/scriptdump.png',
  };
  @override
  void initState() {
    super.initState();
    _loadBuiltins();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.controller.remoteScripts.isEmpty &&
          !widget.controller.remoteLoading) {
        widget.controller.searchRemoteScripts();
      }
    });
  }

  Future<void> _loadBuiltins() async {
    String dump;
    try {
      dump = await rootBundle.loadString(
        'assets/synapse_v3/legacy_hub/scriptDumperLegacy.lua',
      );
    } on Object catch (_) {
      return;
    }
    final scripts = [
      (
        'synapse-dark-dex',
        'Dark Dex',
        'Universal Explorer',
        'loadstring(game:HttpGet("https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua", true))()',
        'https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua',
      ),
      (
        'synapse-unnamed-esp',
        'Unnamed ESP',
        'Global ESP Framework',
        'loadstring(game:HttpGet("https://raw.githubusercontent.com/ic3w0lf22/Unnamed-ESP/master/UnnamedESP.lua"))()',
        'https://raw.githubusercontent.com/ic3w0lf22/Unnamed-ESP/master/UnnamedESP.lua',
      ),
      (
        'synapse-remote-spy',
        'Remote Spy',
        'SimpleSpy V3',
        'loadstring(game:HttpGet("https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua"))()',
        'https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua',
      ),
      (
        'synapse-script-dumper',
        'Script Dumper',
        'Decompile & dump all scripts',
        dump,
        'https://github.com/snooped-xl/Synapse-Framework',
      ),
    ];
    if (!mounted) return;
    setState(
      () => _builtins = [
        for (final s in scripts)
          RemoteScript(
            id: s.$1,
            provider: ScriptProvider.robloxScripts,
            title: s.$2,
            game: s.$3,
            description: s.$3,
            body: s.$4,
            externalUrl: s.$5,
          ),
      ],
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _query(String value) {
    setState(() => _page = 0);
  }

  Future<void> _open(RemoteScript script) async {
    if (_busy.contains(script.key)) return;
    setState(() => _busy.add(script.key));
    try {
      if (widget.onOpenScript != null) {
        await widget.onOpenScript!(script);
      } else {
        await widget.controller.openRemoteScript(script);
        if (mounted) widget.onOpenEditor?.call();
      }
    } on Object catch (error) {
      if (mounted) _message(context, 'Could not open script: $error');
    } finally {
      if (mounted) setState(() => _busy.remove(script.key));
    }
  }

  Future<void> _execute(RemoteScript script) async {
    if (_busy.contains(script.key)) return;
    setState(() => _busy.add(script.key));
    try {
      await widget.controller.executeRemoteScript(script);
      if (mounted) {
        _message(
          context,
          widget.controller.bridgeTargetCount > 0
              ? 'Script queued for ${widget.controller.bridgeTargetCount} ${widget.controller.bridgeTargetCount == 1 ? 'client' : 'clients'}.'
              : 'No clients selected. Open the client manager to choose a target.',
        );
      }
    } on Object catch (error) {
      if (mounted) _message(context, 'Could not load script: $error');
    } finally {
      if (mounted) setState(() => _busy.remove(script.key));
    }
  }

  Future<void> _next(int count) async {
    if ((_page + 1) * _pageSize < count) {
      setState(() => _page++);
      return;
    }
    if (_source == 0 && widget.controller.remoteHasMore) {
      await widget.controller.loadMoreRemoteScripts();
      if (mounted &&
          (_page + 1) * _pageSize < widget.controller.remoteScripts.length) {
        setState(() => _page++);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller, c = V3Colors.of(context);
      final scripts = _source == 1 ? _builtins : controller.remoteScripts;
      final pages = (scripts.length / _pageSize).ceil().clamp(1, 100000);
      final page = _page.clamp(0, pages - 1);
      final visible = _source == 1
          ? scripts
          : scripts.skip(page * _pageSize).take(_pageSize).toList();
      final error = controller.providerErrors.entries
          .map((e) => '${e.key.label}: ${e.value}')
          .join(' · ');
      final font =
          SynapseThemeElementStyleScope.fontFamilyOf(context) ??
          controller.synapsePreferences.uiFontFamily;
      final placeholder =
          'Search ${controller.selectedProvider?.domain ?? 'scripts'}…';
      return ColoredBox(
        color: c.background,
        child: Column(
          children: [
            const SizedBox(height: 1),
            _HubSourceToggle(
              value: _source,
              onChanged: (value) => setState(() => _source = value),
              font: font,
            ),
            Container(
              height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            if (_source == 1)
              const SizedBox(height: 16)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  children: [
                    SizedBox(
                      height: 31,
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        style: V3Type.text(
                          12,
                          color: c.hubSearchText,
                          family: font,
                          height: 1.2,
                        ),
                        decoration: InputDecoration(
                          hintText: placeholder,
                          hintStyle: V3Type.text(
                            12,
                            color: c.hubPlaceholder,
                            family: font,
                            height: 1.2,
                          ),
                          filled: true,
                          fillColor: c.hubSearch,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 8,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: V3Icon(
                              'search20Regular',
                              size: 14,
                              color: c.hubPlaceholder,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 32,
                            maxWidth: 32,
                            minHeight: 14,
                            maxHeight: 14,
                          ),
                          suffixIcon: controller.remoteLoading
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: c.accent,
                                      value:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? .65
                                          : null,
                                    ),
                                  ),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                            maxWidth: 34,
                            minHeight: 14,
                            maxHeight: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: const BorderSide(color: Colors.white10),
                          ),
                        ),
                        onChanged: _query,
                        onSubmitted: (value) {
                          setState(() => _page = 0);
                          controller.searchRemoteScripts(value);
                        },
                      ),
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Tooltip(
                          message: error,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              error,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: V3Type.text(
                                11,
                                color: c.error,
                                family: font,
                                height: 1.375,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: visible.isEmpty
                  ? (_source == 0 && !controller.remoteLoading
                        ? Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Text(
                              _search.text.trim().isEmpty
                                  ? 'No scripts on this page.'
                                  : 'No scripts match your search.',
                              style: V3Type.text(
                                12,
                                color: c.muted,
                                family: font,
                              ),
                            ),
                          )
                        : const SizedBox.shrink())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 750
                            ? 4
                            : constraints.maxWidth >= 520
                            ? 3
                            : 2;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 4 / 3,
                              ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final script = visible[index];
                            return _HubCard(
                              key: ValueKey('v3-hub/${script.key}'),
                              script: script,
                              asset: _localImages[script.id],
                              busy: _busy.contains(script.key),
                              bridgeReady: widget.bridgeReady,
                              radius:
                                  controller.synapsePreferences.cornerRadius,
                              font: font,
                              onOpen: () => _open(script),
                              onExecute: () => _execute(script),
                              onView: () => showDialog<void>(
                                context: context,
                                builder: (context) => _ScriptCodeDialog(
                                  controller: controller,
                                  script: script,
                                  onOpen: () => _open(script),
                                ),
                              ),
                              onWebsite:
                                  _localImages.containsKey(script.id) ||
                                      script.externalUrl.isEmpty
                                  ? null
                                  : () async {
                                      try {
                                        await controller.openScriptPage(script);
                                      } on Object catch (error) {
                                        if (context.mounted) {
                                          _message(
                                            context,
                                            'Could not open source: $error',
                                          );
                                        }
                                      }
                                    },
                            );
                          },
                        );
                      },
                    ),
            ),
            if (_source == 0)
              Container(
                height: 30,
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.tabBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _HubPageLink(
                      'Previous',
                      font: font,
                      onPressed: page <= 0 || controller.remoteLoading
                          ? null
                          : () => setState(() => _page = page - 1),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      'Page ${page + 1}',
                      style: V3Type.text(
                        11,
                        color: c.muted,
                        family: font,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 20),
                    _HubPageLink(
                      'Next',
                      font: font,
                      onPressed:
                          controller.remoteLoading ||
                              controller.remoteLoadingMore ||
                              ((page + 1) * _pageSize >= scripts.length &&
                                  !controller.remoteHasMore)
                          ? null
                          : () => _next(scripts.length),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _HubSourceToggle extends StatelessWidget {
  const _HubSourceToggle({
    required this.value,
    required this.onChanged,
    required this.font,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final String font;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    return ColoredBox(
      color: c.tabBar,
      child: SizedBox(
        height: 32,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Semantics(
                selected: value == i,
                button: true,
                label: i == 0 ? 'Scripts' : 'Synapse Script Hub',
                child: SizedBox(
                  width: 176,
                  height: 32,
                  child: TextButton(
                    onPressed: () => onChanged(i),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: value == i ? c.tabActive : c.tabInactive,
                      foregroundColor: value == i ? c.text : c.muted,
                      overlayColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      textStyle: V3Type.text(12, family: font),
                    ),
                    child: Text(i == 0 ? 'Scripts' : 'Synapse Script Hub'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HubPageLink extends StatelessWidget {
  const _HubPageLink(this.label, {required this.font, this.onPressed});
  final String label, font;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    return Opacity(
      opacity: onPressed == null ? .35 : 1,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: c.muted,
          disabledForegroundColor: c.muted,
          textStyle: V3Type.text(11, family: font, height: 1.2),
          overlayColor: Colors.transparent,
        ),
        child: Text(label),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    super.key,
    required this.script,
    required this.busy,
    required this.bridgeReady,
    required this.onOpen,
    required this.onExecute,
    required this.onView,
    required this.radius,
    required this.font,
    this.onWebsite,
    this.asset,
  });
  final RemoteScript script;
  final bool busy, bridgeReady;
  final VoidCallback onOpen, onExecute, onView;
  final VoidCallback? onWebsite;
  final String? asset;
  final double radius;
  final String font;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    final image = asset != null
        ? Image.asset(
            asset!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: c.settingsHeader),
          )
        : script.imageUrl != null
        ? Image.network(
            script.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: c.settingsHeader),
          )
        : ColoredBox(color: c.settingsHeader);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .25),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('v3-code/${script.key}'),
                  onTap: onView,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: .55,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [c.hubScrim, Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: c.hubCard,
                  border: Border(top: BorderSide(color: c.hubCardBorder)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: '${script.title} — ${script.game}',
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: script.title,
                              style: V3Type.text(
                                12,
                                color: c.hubTitle,
                                weight: FontWeight.w600,
                                family: font,
                                height: 1.25,
                              ),
                            ),
                            TextSpan(
                              text: ' · ${script.game}',
                              style: V3Type.text(
                                12,
                                color: c.hubSubtitle,
                                family: font,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Opacity(
                            opacity: busy ? .72 : 1,
                            child: _CardButton(
                              label: 'Execute',
                              font: font,
                              ready: bridgeReady,
                              tooltip: bridgeReady
                                  ? 'Execute'
                                  : 'Orion Bridge is not attached',
                              onPressed: bridgeReady && !busy
                                  ? onExecute
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _CardButton(
                          glyph: false,
                          font: font,
                          tooltip: 'Open in editor',
                          onPressed: busy ? null : onOpen,
                        ),
                        if (onWebsite != null) ...[
                          const SizedBox(width: 4),
                          _CardButton(
                            glyph: true,
                            font: font,
                            tooltip: 'View on website',
                            onPressed: onWebsite,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    this.label,
    this.glyph,
    this.tooltip,
    this.onPressed,
    required this.font,
    this.ready = false,
  });
  final String? label, tooltip;
  final bool? glyph;
  final VoidCallback? onPressed;
  final String font;
  final bool ready;
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context), icon = glyph != null;
    final button = Opacity(
      opacity: icon && onPressed == null ? .45 : 1,
      child: SizedBox(
        width: icon ? 24 : null,
        height: icon ? 24 : 22,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
            backgroundColor: icon
                ? c.hubIconButton
                : ready
                ? c.hubExecute
                : c.token('scriptHub.cardExecuteDisabledBg'),
            side: icon
                ? BorderSide.none
                : BorderSide(
                    color: ready
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: .2),
                  ),
            foregroundColor: icon
                ? c.buttonIcon
                : ready
                ? c.buttonText
                : const Color(0xffc8c8c8),
            disabledForegroundColor: icon
                ? c.buttonIcon
                : const Color(0xffc8c8c8),
            textStyle: V3Type.text(
              10,
              weight: FontWeight.w500,
              family: font,
              height: 1.2,
            ),
            overlayColor: Colors.transparent,
          ),
          child: icon
              ? CustomPaint(
                  size: const Size(11, 11),
                  painter: _HubActionGlyph(
                    glyph!,
                    glyph! ? c.sidebarIcon : c.buttonIcon,
                  ),
                )
              : Text(label!),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _HubActionGlyph extends CustomPainter {
  const _HubActionGlyph(this.website, this.color);
  final bool website;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 12, size.height / 12);
    final path = website
        ? (Path()
            ..moveTo(4.5, 2)
            ..lineTo(2, 2)
            ..lineTo(2, 10)
            ..lineTo(10, 10)
            ..lineTo(10, 7.5)
            ..moveTo(7, 2)
            ..lineTo(10, 2)
            ..lineTo(10, 5)
            ..moveTo(10, 2)
            ..lineTo(5.5, 6.5))
        : (Path()
            ..moveTo(2, 10)
            ..lineTo(10, 2)
            ..lineTo(4.5, 2)
            ..moveTo(10, 2)
            ..lineTo(10, 7.5));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HubActionGlyph old) =>
      old.website != website || old.color != color;
}

class _ScriptCodeDialog extends StatefulWidget {
  const _ScriptCodeDialog({
    required this.controller,
    required this.script,
    required this.onOpen,
  });
  final OrionController controller;
  final RemoteScript script;
  final Future<void> Function() onOpen;
  @override
  State<_ScriptCodeDialog> createState() => _ScriptCodeDialogState();
}

class _ScriptCodeDialogState extends State<_ScriptCodeDialog> {
  late Future<String> _code = widget.controller.loadRemoteScript(widget.script);
  @override
  Widget build(BuildContext context) {
    final c = V3Colors.of(context);
    return FutureBuilder<String>(
      future: _code,
      builder: (context, snapshot) => Dialog(
        backgroundColor: c.content,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(color: c.border),
        ),
        child: SizedBox(
          width: 680,
          height: 420,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.script.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: V3Type.text(
                          15,
                          color: c.text,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, size: 18, color: c.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: snapshot.hasError
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Could not fetch the script.\n${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: V3Type.text(12, color: c.error),
                              ),
                              const SizedBox(height: 12),
                              V3PanelButton(
                                'Retry',
                                onPressed: () => setState(
                                  () => _code = widget.controller
                                      .loadRemoteScript(widget.script),
                                ),
                              ),
                            ],
                          ),
                        )
                      : !snapshot.hasData
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.accent,
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          color: c.editor,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(10),
                            child: SelectableText(
                              snapshot.data!,
                              style: TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 12,
                                height: 1.5,
                                color: c.text,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    V3PanelButton(
                      'Copy code',
                      onPressed: snapshot.hasData
                          ? () async {
                              await Clipboard.setData(
                                ClipboardData(text: snapshot.data!),
                              );
                              if (context.mounted) {
                                _message(context, 'Script code copied.');
                              }
                            }
                          : null,
                    ),
                    V3PanelButton(
                      'Open in editor',
                      onPressed: snapshot.hasData
                          ? () {
                              Navigator.pop(context);
                              widget.onOpen();
                            }
                          : null,
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
