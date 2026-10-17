import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/interface_preset.dart';
import '../models/orion_models.dart';
import '../models/remote_script.dart';
import '../services/native_window_service.dart';
import '../services/synapse_theme_catalog.dart';
import '../state/orion_controller.dart';
import 'blue_controls.dart';
import 'blue_theme.dart';

class BlueSettingsPage extends StatelessWidget {
  const BlueSettingsPage({
    super.key,
    required this.controller,
    required this.palette,
    required this.family,
    required this.nativeWindow,
    required this.onBackToOrion,
    this.onSelectInterface,
  });
  final OrionController controller;
  final BluePalette palette;
  final String family;
  final bool nativeWindow;
  final VoidCallback onBackToOrion;
  final Future<void> Function(InterfacePreset)? onSelectInterface;
  Map<String, Object?> get preferences =>
      controller.getInterfacePreferences(InterfacePreset.synapseBlue);
  void _set(String key, Object? value) => controller.setInterfacePreference(
    InterfacePreset.synapseBlue,
    key,
    value,
  );
  bool _bool(String key, [bool fallback = false]) =>
      preferences[key] is bool ? preferences[key] as bool : fallback;
  @override
  Widget build(BuildContext context) {
    Widget option(
      String key,
      String title,
      String description, {
      bool fallback = false,
    }) => BlueOption(
      title,
      description,
      value: _bool(key, fallback),
      palette: palette,
      family: family,
      onChanged: () async {
        final next = !_bool(key, fallback);
        if (nativeWindow && key == 'resizableWindow') {
          final custom = SynapseThemeCatalog.current(
            controller,
            InterfacePreset.synapseBlue,
          ).window('main');
          final size = Size(custom.width ?? 714, custom.height ?? 393);
          await NativeWindowService.setMinimumSize(size);
          await NativeWindowService.setResizable(
            next,
            size: next ? null : size,
          );
          if (!next) await windowManager.center();
        }
        if (nativeWindow && key == 'alwaysOnTop') {
          await NativeWindowService.setAlwaysOnTop(next);
        }
        _set(key, next);
      },
    );
    Widget switcher(InterfacePreset preset, String name, String copy) =>
        BlueOption(
          name,
          copy,
          value: false,
          palette: palette,
          family: family,
          onChanged: () {
            if (onSelectInterface != null) {
              unawaited(onSelectInterface!(preset));
            } else {
              controller.setInterface(preset);
            }
          },
        );
    return ColoredBox(
      color: palette.color('pageAreaBg'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: BlueHeading('Options', family: family),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 12, 17, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      option(
                        'playLoadingScreenOnShellChange',
                        'Play loading screen on shell change',
                        "When enabled, switching between Synapse Blue, 2017, X, and V3 replays that shell's loading intro instead of jumping straight to the main window. Applies everywhere this setting appears.",
                      ),
                      const SizedBox(height: 10),
                      option(
                        'clearConfirmation',
                        'Clear confirmation',
                        'When enabled, Clear asks before clearing the active tab’s script, and Shift+Clear asks before closing all tabs and starting fresh.',
                        fallback: true,
                      ),
                      const SizedBox(height: 10),
                      option(
                        'closeFileConfirmation',
                        'Close tab confirmation',
                        'Ask before closing a script tab from the tab context menu when more than one tab is open.',
                        fallback: true,
                      ),
                      const SizedBox(height: 10),
                      option(
                        'resizableWindow',
                        'Resizable window',
                        'Allow dragging the window edges to resize the Synapse desktop window. Turning this off restores the default shell size and recenters the window.',
                      ),
                      const SizedBox(height: 10),
                      option(
                        'alwaysOnTop',
                        'Always on top',
                        'Keep the Synapse desktop window above other windows. Turning off restores normal stacking.',
                      ),
                      const SizedBox(height: 10),
                      option(
                        'edgeCurveDefault',
                        'Edge curve',
                        'Apply rounded corners to the Synapse desktop window. Turn this off for sharp square corners.',
                      ),
                      const SizedBox(height: 10),
                      option(
                        'enhancedScriptListDefault',
                        'Enhanced script list',
                        'Search, sections, bookmarks, gists, row actions, and full script-list theming in the editor.',
                      ),
                      const SizedBox(height: 10),
                      option(
                        'minimapEnabled',
                        'Minimap',
                        'Show a miniature preview of the entire script on the right side of the editor for quick navigation.',
                      ),
                      const SizedBox(height: 10),
                      const SizedBox(height: 10),
                      switcher(
                        InterfacePreset.synapse2017,
                        'Synapse 2017',
                        'The original Synapse multi-window shell. Switch back via the Synapse 2017 Settings window.',
                      ),
                      const SizedBox(height: 10),
                      switcher(
                        InterfacePreset.synapseX,
                        'Synapse X',
                        'The Synapse X shell. Switch back via the Synapse X Options window.',
                      ),
                      const SizedBox(height: 10),
                      switcher(
                        InterfacePreset.synapseV3,
                        'Synapse V3',
                        'The Synapse V3 shell. Switch back via Synapse V3 Settings.',
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Return to the Orion workspace with your open scripts.',
                                style: blueText(
                                  10,
                                  height: 1.42,
                                  family: family,
                                  color: palette.color(
                                    'toolPanelsTheme.sectionBody',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            BlueButton(
                              'Back to Orion',
                              key: const ValueKey('blue-back-to-orion'),
                              onPressed: onBackToOrion,
                              palette: palette,
                              family: family,
                              kind: 'tool',
                              width: 120,
                              height: 33,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Script Hub Source',
                              style: blueText(
                                16,
                                family: family,
                                weight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose which website to search for scripts. This affects all script hub UIs.',
                              style: blueText(
                                10,
                                family: family,
                                color: palette.color(
                                  'toolPanelsTheme.sectionBody',
                                ),
                                height: 1.42,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final provider in ScriptProvider.values)
                                  BlueButton(
                                    provider == ScriptProvider.robloxScripts
                                        ? 'robloxscripts.com'
                                        : provider.label,
                                    width: null,
                                    height: 28,
                                    fontSize: 10,
                                    kind: 'tool',
                                    palette: palette,
                                    family: family,
                                    selected:
                                        (preferences['scriptHubApi'] ??
                                            'robloxScripts') ==
                                        provider.name,
                                    onPressed: () {
                                      _set('scriptHubApi', provider.name);
                                      controller.setScriptProvider(provider);
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BlueConsolePage extends StatelessWidget {
  const BlueConsolePage({
    super.key,
    required this.controller,
    required this.palette,
    required this.family,
  });
  final OrionController controller;
  final BluePalette palette;
  final String family;
  @override
  Widget build(BuildContext context) {
    final output = controller.activities
        .where((entry) => entry.kind == ActivityKind.execution)
        .toList()
        .reversed
        .toList();
    return ColoredBox(
      color: palette.color('pageAreaBg'),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BlueHeading('Console', family: family),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: controller.bridgeConnected
                                  ? const Color(0xff63c78c)
                                  : const Color(0xffc45c5c),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              controller.bridgeConnected
                                  ? '${controller.bridgeClients.length} connected'
                                  : 'Disconnected · Attach required',
                              style: blueText(
                                11,
                                family: family,
                                color: const Color(0xffcccccc),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                BlueButton(
                  'Copy',
                  palette: palette,
                  family: family,
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text: output.map((e) => e.message).join('\n'),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                BlueButton(
                  'Clear',
                  palette: palette,
                  family: family,
                  kind: 'attach',
                  onPressed: controller.clearActivities,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: palette.color(
                    'surfaceElementsTheme.surfacePanelBackground',
                  ),
                  border: Border.all(
                    color: palette.color(
                      'surfaceElementsTheme.surfacePanelBorder',
                    ),
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    if (output.isEmpty)
                      Text(
                        'No output yet. Attach, run your bridge script, then Execute — prints, warns, and errors appear here.',
                        style: blueText(
                          11,
                          family: family,
                          color: palette
                              .color('surfaceElementsTheme.surfaceListText')
                              .withValues(alpha: .7),
                        ),
                      ),
                    for (final entry in output)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          entry.message,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            height: 1.35,
                            color: switch (entry.severity) {
                              ActivitySeverity.error => const Color(0xffcf6363),
                              ActivitySeverity.warning => const Color(
                                0xffeab308,
                              ),
                              _ => palette.color(
                                'surfaceElementsTheme.surfaceListText',
                              ),
                            },
                          ),
                        ),
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

class BlueHubPage extends StatefulWidget {
  const BlueHubPage({
    super.key,
    required this.controller,
    required this.palette,
    required this.family,
    required this.onOpen,
    required this.onOpenSource,
    required this.onModal,
  });
  final OrionController controller;
  final BluePalette palette;
  final String family;
  final Future<void> Function(RemoteScript) onOpen;
  final Future<void> Function(String, String) onOpenSource;
  final ValueChanged<bool> onModal;
  @override
  State<BlueHubPage> createState() => _BlueHubPageState();
}

class _BlueHubPageState extends State<BlueHubPage> {
  bool _search = false;
  String? _opening;
  final _query = TextEditingController();
  OrionController get c => widget.controller;
  static const bundled = [
    (
      'Dark Dex',
      'Universal Explorer',
      'dex.png',
      'loadstring(game:HttpGet("https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua", true))()',
    ),
    (
      'Unnamed ESP',
      'Global ESP Framework',
      'unnamedesp.png',
      'loadstring(game:HttpGet("https://raw.githubusercontent.com/ic3w0lf22/Unnamed-ESP/master/UnnamedESP.lua"))()',
    ),
    (
      'Remote Spy',
      'SimpleSpy V3',
      'RemoteSpy.png',
      'loadstring(game:HttpGet("https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua"))()',
    ),
    ('Script Dumper', 'Decompile & dump all scripts', 'scriptdump.png', ''),
  ];
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _beginSearch() async {
    setState(() => _search = true);
    final name =
        c.getInterfacePreferences(
          InterfacePreset.synapseBlue,
        )['scriptHubApi'] ??
        'robloxScripts';
    final provider = ScriptProvider.values.firstWhere(
      (p) => p.name == name,
      orElse: () => ScriptProvider.robloxScripts,
    );
    if (c.selectedProvider != provider) {
      c.setScriptProvider(provider);
    } else {
      await c.searchRemoteScripts();
    }
  }

  Future<void> _open(RemoteScript script) async {
    if (_opening != null) return;
    setState(() => _opening = script.key);
    try {
      await widget.onOpen(script);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _bundle(int index) async {
    var source = bundled[index].$4;
    if (index == 3) {
      source = await rootBundle.loadString(
        'assets/synapse_v3/legacy_hub/scriptDumperLegacy.lua',
      );
    }
    if (mounted) {
      await widget.onOpenSource(
        bundled[index].$1,
        '-- Synapse Legacy Script: ${bundled[index].$1}\n$source',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final family = widget.family;
    final provider = c.selectedProvider;
    return ColoredBox(
      color: p.color('pageAreaBg'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _search
                      ? const SizedBox()
                      : BlueHeading('Script hub', family: family),
                ),
                BlueButton(
                  _search ? 'Back' : 'Script search',
                  width: 125,
                  palette: p,
                  family: family,
                  onPressed: _search
                      ? () => setState(() => _search = false)
                      : () => unawaited(_beginSearch()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_search) ...[
              TextField(
                controller: _query,
                style: blueText(14, family: family),
                decoration:
                    blueInput(
                      p,
                      hint: 'Search ${provider?.domain ?? 'scripts'}…',
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ).copyWith(
                      prefixIcon: const Icon(Icons.search, size: 16),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                      fillColor: p.color('scriptHubTheme.searchBackground'),
                    ),
                onChanged: c.setRemoteSearchQuery,
                onSubmitted: (value) => unawaited(c.searchRemoteScripts(value)),
              ),
              const SizedBox(height: 12),
              Text(
                'Source: ${provider?.label ?? 'All sources'}',
                style: blueText(
                  11,
                  family: family,
                  color: p.color('scriptHubTheme.subtitleColor'),
                ),
              ),
              const SizedBox(height: 12),
              if (c.remoteLoading)
                LinearProgressIndicator(
                  minHeight: 2,
                  value:
                      c.reducedMotion || MediaQuery.disableAnimationsOf(context)
                      ? 0
                      : null,
                ),
              for (final entry in c.providerErrors.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    entry.value,
                    style: blueText(
                      12,
                      family: family,
                      color: p.color('scriptHubTheme.subtitleColor'),
                    ),
                  ),
                ),
            ] else ...[
              Text(
                'Synapse legacy scripts — open in the editor to run or edit.',
                style: blueText(
                  12,
                  family: family,
                  color: p.color('scriptHubTheme.subtitleColor'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final two = MediaQuery.sizeOf(context).width >= 640;
                final width = two
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (!_search)
                      for (var i = 0; i < bundled.length; i++)
                        SizedBox(
                          width: width,
                          child: _card(
                            bundled[i].$1,
                            bundled[i].$2,
                            Image.asset(
                              'assets/synapse_v3/legacy_hub/${bundled[i].$3}',
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                            ),
                            () => unawaited(_bundle(i)),
                          ),
                        ),
                    if (_search)
                      for (final script in c.remoteScripts)
                        SizedBox(
                          width: width,
                          child: _card(
                            script.title,
                            script.game,
                            script.imageUrl == null
                                ? null
                                : Image.network(
                                    script.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const SizedBox(),
                                  ),
                            _opening == null
                                ? () => unawaited(_open(script))
                                : null,
                            loading: _opening == script.key,
                          ),
                        ),
                  ],
                );
              },
            ),
            if (_search && c.remoteHasMore)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: BlueButton(
                    c.remoteLoadingMore ? 'Loading…' : 'Load more',
                    palette: p,
                    family: family,
                    onPressed: c.remoteLoadingMore
                        ? null
                        : () => unawaited(c.loadMoreRemoteScripts()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    String name,
    String description,
    Widget? image,
    VoidCallback? onOpen, {
    bool loading = false,
  }) {
    final p = widget.palette;
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: p.color('scriptHubTheme.cardBackground'),
        border: Border.all(color: p.color('scriptHubTheme.cardBorderColor')),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth / 3,
              child: ColoredBox(
                color: p.color('scriptHubTheme.thumbFallbackBg'),
                child: image,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: blueText(
                        14,
                        weight: FontWeight.w600,
                        height: 1.35,
                        family: widget.family,
                        color: p.color('scriptHubTheme.titleColor'),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: blueText(
                          11,
                          height: 1.35,
                          family: widget.family,
                          color: p.color('scriptHubTheme.subtitleColor'),
                        ),
                      ),
                    ),
                    BlueButton(
                      loading ? 'Loading…' : 'OPEN IN EDITOR',
                      palette: p,
                      family: widget.family,
                      kind: 'hub',
                      width: null,
                      height: 28,
                      fontSize: 10,
                      onPressed: onOpen,
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
