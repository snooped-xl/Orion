import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/bridge_client_manager.dart';
import 'package:flutter/services.dart';
import '../models/interface_preset.dart';
import '../models/orion_models.dart';
import '../models/remote_script.dart';
import '../state/orion_controller.dart';
import '../services/synapse_theme_catalog.dart';
import '../widgets/synapse_theme_surface.dart';
import 'og_theme.dart';

class OgSettingsPage extends StatefulWidget {
  const OgSettingsPage({
    super.key,
    required this.controller,
    required this.theme,
    required this.preferences,
    required this.onFlag,
    required this.onThemeStudio,
    required this.onClose,
    required this.onBackToOrion,
    required this.onSwitch,
    required this.nativeWindow,
    this.onDragStart,
  });
  final OrionController controller;
  final OgTheme theme;
  final Map<String, Object?> preferences;
  final Future<void> Function(String, bool) onFlag;
  final VoidCallback onThemeStudio;
  final VoidCallback onClose;
  final VoidCallback onBackToOrion;
  final Future<void> Function(InterfacePreset) onSwitch;
  final bool nativeWindow;
  final VoidCallback? onDragStart;
  @override
  State<OgSettingsPage> createState() => _OgSettingsPageState();
}

class _OgSettingsPageState extends State<OgSettingsPage> {
  TextStyle _type(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) => ogText(size, color: color, weight: weight, height: height).copyWith(
    fontFamily: SynapseThemeCatalog.current(
      widget.controller,
      InterfacePreset.synapse2017,
    ).fontFamily,
  );

  bool _clientsTab = false;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool flag(String key) => widget.preferences[key] == true;
  void pref(String key, Object? value) => widget.controller
      .setInterfacePreference(InterfacePreset.synapse2017, key, value);
  Widget _toggle(String key, String label, String description) => _ToggleRow(
    theme: widget.theme,
    label: label,
    description: description,
    on: flag(key),
    onPressed: () => widget.onFlag(key, !flag(key)),
  );
  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return ColoredBox(
      color: t.window,
      child: Column(
        children: [
          SizedBox(
            height: 58,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SynapseThemeElement(
                    controller: widget.controller,
                    preset: InterfacePreset.synapse2017,
                    windowId: 'settings',
                    elementId: 'titleBar',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => widget.onDragStart?.call(),
                      child: ColoredBox(color: t.panel),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 16,
                  width: 126,
                  height: 26,
                  child: SynapseThemeLogo(
                    controller: widget.controller,
                    preset: InterfacePreset.synapse2017,
                    windowId: 'settings',
                    child: OgLogo(theme: t),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Text(
                        'Settings & Clients',
                        style: _type(14, color: t.text, height: 1.25),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 28,
                  child: TextButton(
                    onPressed: widget.onClose,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      textStyle: _type(13),
                      foregroundColor: t.text,
                    ),
                    child: const Text('X'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 110,
                  decoration: BoxDecoration(
                    color: t.panel,
                    border: const Border(
                      right: BorderSide(color: Color(0xff424242)),
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      OgButton(
                        'General',
                        theme: t,
                        height: 30,
                        width: 94,
                        selected: !_clientsTab,
                        background: _clientsTab
                            ? t.panel
                            : const Color(0xff323232),
                        border: Color(_clientsTab ? 0xff323232 : 0xff3a3a3a),
                        onPressed: () => setState(() {
                          _clientsTab = false;
                        }),
                      ),
                      const SizedBox(height: 4),
                      OgButton(
                        'Theme Studio',
                        theme: t,
                        height: 30,
                        width: 94,
                        onPressed: widget.onThemeStudio,
                      ),
                      const SizedBox(height: 4),
                      OgButton(
                        'Clients',
                        key: const ValueKey('og-clients'),
                        theme: t,
                        height: 30,
                        width: 94,
                        selected: _clientsTab,
                        background: _clientsTab
                            ? const Color(0xff323232)
                            : t.panel,
                        border: Color(_clientsTab ? 0xff3a3a3a : 0xff323232),
                        onPressed: () => setState(() {
                          _clientsTab = true;
                        }),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Scrollbar(
                          controller: _scroll,
                          child: SingleChildScrollView(
                            controller: _scroll,
                            padding: const EdgeInsets.all(12),
                            child: _clientsTab
                                ? BridgeClientManagerPanel(
                                    controller: widget.controller,
                                  )
                                : Column(
                                    children: [
                                      _toggle(
                                        'alwaysOnTop',
                                        'Top Most',
                                        'All Synapse windows to stay on top.',
                                      ),
                                      const SizedBox(height: 8),
                                      _toggle(
                                        'enhancedList',
                                        'Enhanced List',
                                        'Search, sections, bookmarks, gists, row actions, and full script-list theming.',
                                      ),
                                      const SizedBox(height: 8),
                                      _toggle(
                                        'minimap',
                                        'Minimap',
                                        'Show a miniature preview of the entire script on the right side.',
                                      ),
                                      const SizedBox(height: 8),
                                      if (flag('minimap')) ...[
                                        _minimapScale(t),
                                        const SizedBox(height: 8),
                                      ],
                                      const SizedBox(height: 8),
                                      _toggle(
                                        'resizable',
                                        'Resizable',
                                        'Allow dragging the OG main window edges to resize. Off snaps it back to the default 838×372.',
                                      ),
                                      const SizedBox(height: 8),
                                      _sourceRow(t),
                                      const SizedBox(height: 8),
                                      _toggle(
                                        'edgeCurve',
                                        'Edge Curve',
                                        'Apply Windows 11 rounded corners to OG windows. Off makes the corners sharp and square.',
                                      ),
                                      const SizedBox(height: 8),
                                      _ToggleRow(
                                        theme: t,
                                        label: 'Synapse X',
                                        description:
                                            'Switch to the Synapse X UI.',
                                        on: false,
                                        onPressed: () => widget.onSwitch(
                                          InterfacePreset.synapseX,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _ToggleRow(
                                        theme: t,
                                        label: 'Synapse Blue',
                                        description:
                                            'Return to the Synapse Blue desktop UI.',
                                        on: false,
                                        onPressed: () => widget.onSwitch(
                                          InterfacePreset.synapseBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _ToggleRow(
                                        theme: t,
                                        label: 'Synapse v3',
                                        description:
                                            'Switch to the Synapse v3 UI.',
                                        on: false,
                                        onPressed: () => widget.onSwitch(
                                          InterfacePreset.synapseV3,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _RowFrame(
                                        child: Row(
                                          children: [
                                            OgButton(
                                              'Back to Orion',
                                              key: const ValueKey(
                                                'og-back-to-orion',
                                              ),
                                              theme: t,
                                              width: 120,
                                              height: 33,
                                              fontSize: 13,
                                              border: const Color(0xff323232),
                                              onPressed: widget.onBackToOrion,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'Return to Orion with your open scripts.',
                                                style: _type(
                                                  12,
                                                  color: const Color(
                                                    0xffa3a3a3,
                                                  ),
                                                  height: 1.375,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      Container(
                        height: 46,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xff424242)),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        alignment: Alignment.centerRight,
                        child: OgButton(
                          'Close',
                          theme: t,
                          height: 29,
                          width: 88,
                          border: const Color(0xff323232),
                          onPressed: widget.onClose,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _minimapScale(OgTheme t) {
    final raw = widget.preferences['minimapScale'];
    final value = raw is num && raw.isFinite
        ? raw.toDouble().clamp(1.0, 3.0).toDouble()
        : 1.0;
    return _RowFrame(
      child: Column(
        children: [
          Row(
            children: [
              OgButton('Minimap size', theme: t, width: 120),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Scale of the minimap preview (1× is default).',
                  style: _type(
                    12,
                    color: const Color(0xffa3a3a3),
                    height: 1.375,
                  ),
                ),
              ),
              Text('${value.toStringAsFixed(0)}×', style: _type(12)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 132),
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: value,
                    min: 1,
                    max: 3,
                    divisions: 2,
                    onChanged: (v) => pref('minimapScale', v),
                  ),
                ),
                TextButton(
                  onPressed: value == 1 ? null : () => pref('minimapScale', 1),
                  child: Text(
                    'Reset to default',
                    style: _type(11, color: const Color(0xffb0d8e5)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(OgTheme t) => _RowFrame(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OgButton(
          'Script Source',
          theme: t,
          width: 120,
          border: const Color(0xff323232),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Script search website.',
                style: _type(12, color: const Color(0xffa3a3a3), height: 1.375),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final p in ScriptProvider.values)
                    SizedBox(
                      height: 25,
                      child: TextButton(
                        onPressed: () => widget.controller.setScriptProvider(p),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor:
                              (widget.controller.selectedProvider ??
                                      ScriptProvider.robloxScripts) ==
                                  p
                              ? const Color(0xffb0d8e5)
                              : const Color(0xff272727),
                          foregroundColor:
                              (widget.controller.selectedProvider ??
                                      ScriptProvider.robloxScripts) ==
                                  p
                              ? const Color(0xff0f2433)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(3),
                          ),
                          side: BorderSide(
                            color:
                                (widget.controller.selectedProvider ??
                                        ScriptProvider.robloxScripts) ==
                                    p
                                ? const Color(0xffb0d8e5)
                                : const Color(0xff323232),
                          ),
                          textStyle: _type(11),
                        ),
                        child: Text(
                          p == ScriptProvider.robloxScripts ||
                                  p == ScriptProvider.rscripts
                              ? p.domain
                              : p.label,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RowFrame extends StatelessWidget {
  const _RowFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 60),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xff282827),
        border: Border.all(color: const Color(0xff313131)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: child,
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.theme,
    required this.label,
    required this.description,
    required this.on,
    required this.onPressed,
  });
  final OgTheme theme;
  final String label, description;
  final bool on;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => _RowFrame(
    child: Row(
      children: [
        Semantics(
          toggled: on,
          child: OgButton(
            label,
            theme: theme,
            width: 120,
            height: 33,
            fontSize: 13,
            border: const Color(0xff323232),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            description,
            style: ogText(12, color: const Color(0xffa3a3a3), height: 1.375),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          on ? 'ON' : 'OFF',
          style: ogText(
            12,
            color: on ? const Color(0xff008b00) : const Color(0xff860000),
          ),
        ),
      ],
    ),
  );
}

class OgHubPage extends StatefulWidget {
  const OgHubPage({
    super.key,
    required this.controller,
    required this.theme,
    required this.onClose,
    required this.bridgeReady,
    required this.onOpen,
    this.onDragStart,
  });
  final OrionController controller;
  final OgTheme theme;
  final VoidCallback onClose;
  final bool bridgeReady;
  final Future<void> Function(RemoteScript) onOpen;
  final VoidCallback? onDragStart;
  @override
  State<OgHubPage> createState() => _OgHubPageState();
}

class _OgHubPageState extends State<OgHubPage> {
  TextStyle _type(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) => ogText(size, color: color, weight: weight, height: height).copyWith(
    fontFamily: SynapseThemeCatalog.current(
      widget.controller,
      InterfacePreset.synapse2017,
    ).fontFamily,
  );

  bool _searchTab = false, _busy = false;
  final _search = TextEditingController();
  String _selectedLocal = 'dark-dex';
  String? _selectedRemote, _runError;
  List<RemoteScript> _locals = [];
  static const _images = {
    'dark-dex': 'dex.png',
    'unnamed-esp': 'unnamedesp.png',
    'remote-spy': 'RemoteSpy.png',
    'script-dumper': 'scriptdump.png',
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _locals = [
      for (final row in [
        (
          'dark-dex',
          'Dark Dex',
          'Universal Explorer',
          'loadstring(game:HttpGet("https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua", true))()',
        ),
        (
          'unnamed-esp',
          'Unnamed ESP',
          'Global ESP Framework',
          'loadstring(game:HttpGet("https://raw.githubusercontent.com/ic3w0lf22/Unnamed-ESP/master/UnnamedESP.lua"))()',
        ),
        (
          'remote-spy',
          'Remote Spy',
          'SimpleSpy V3',
          'loadstring(game:HttpGet("https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua"))()',
        ),
        (
          'script-dumper',
          'Script Dumper',
          'Decompile & dump all scripts',
          null,
        ),
      ])
        RemoteScript(
          id: row.$1,
          provider: ScriptProvider.robloxScripts,
          title: row.$2,
          game: row.$3,
          description: row.$3,
          body: row.$4,
          externalUrl: '',
        ),
    ];
  }

  Future<RemoteScript> _resolved(RemoteScript item) async {
    if (item.id != 'script-dumper' || item.body != null) return item;
    return RemoteScript(
      id: item.id,
      provider: item.provider,
      title: item.title,
      game: item.game,
      description: item.description,
      externalUrl: item.externalUrl,
      body: await rootBundle.loadString(
        'assets/synapse_og/scriptDumperLegacy.lua',
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<RemoteScript> get scripts => _searchTab
      ? widget.controller.remoteScripts
            .where(
              (s) => s.title.toLowerCase().contains(_search.text.toLowerCase()),
            )
            .toList()
      : _locals;
  RemoteScript? get selected => scripts
      .where((s) => s.id == (_searchTab ? _selectedRemote : _selectedLocal))
      .firstOrNull;
  Future<void> _run() async {
    final item = selected;
    if (item == null || !widget.bridgeReady || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.controller.executeRemoteScript(await _resolved(item));
      if (mounted) {
        setState(
          () => _runError = widget.controller.bridgeTargetCount == 0
              ? 'No clients selected.'
              : null,
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _runError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _code() async {
    final selectedItem = selected;
    if (selectedItem == null) return;
    try {
      final item = await _resolved(selectedItem);
      final code = await widget.controller.loadRemoteScript(item);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 580,
            height: 340,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        code,
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 12,
                          color: Color(0xffc0c0c0),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OgButton(
                        'Copy',
                        theme: widget.theme,
                        width: 75,
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: code)),
                      ),
                      const SizedBox(width: 6),
                      OgButton(
                        'Open in editor',
                        theme: widget.theme,
                        width: 110,
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onOpen(item);
                        },
                      ),
                      const SizedBox(width: 6),
                      OgButton(
                        'Close',
                        theme: widget.theme,
                        width: 75,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _runError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme, item = selected;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth,
            h = constraints.maxHeight,
            rightW = math.max(120.0, w - 303),
            imageH = math.min(
              162.0,
              math.max(40.0, h - 63 - 6 - 36.81 - 3 - 113),
            ),
            descriptionH = math.max(40.0, h - 63 - 6 - 36.81 - 3 - imageH);
        final image = item == null
            ? Image.asset(
                'assets/synapse_og/script-preview.png',
                fit: BoxFit.cover,
              )
            : _searchTab && item.imageUrl != null
            ? Image.network(
                item.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Image.asset(
                  'assets/synapse_og/script-preview.png',
                  fit: BoxFit.cover,
                ),
              )
            : Image.asset(
                'assets/synapse_og/${_images[item.id] ?? 'script-preview.png'}',
                fit: BoxFit.cover,
              );
        return Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: t.window)),
            Positioned(
              left: 6,
              top: 64,
              width: 93.818,
              height: 36.81,
              child: OgButton(
                'Synapse Hub',
                theme: t,
                height: 36.81,
                fontSize: 13,
                selected: !_searchTab,
                labelChild: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 6,
                      top: 9,
                      width: 83,
                      child: Text(
                        'Synapse Hub',
                        style: _type(13, height: 16 / 13),
                      ),
                    ),
                  ],
                ),
                border: Color(_searchTab ? 0xff2d2d2d : 0xff3a3a3a),
                onPressed: () => setState(() => _searchTab = false),
              ),
            ),
            Positioned(
              left: 6,
              top: 111,
              width: 94,
              height: 36.81,
              child: OgButton(
                'Script Search',
                theme: t,
                height: 36.81,
                fontSize: 13,
                selected: _searchTab,
                labelChild: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 13,
                      top: 9,
                      width: 82,
                      child: Text(
                        'Script Search',
                        style: _type(13, height: 16 / 13),
                      ),
                    ),
                  ],
                ),
                border: Color(_searchTab ? 0xff3a3a3a : 0xff2d2d2d),
                onPressed: () {
                  setState(() => _searchTab = true);
                  if (widget.controller.selectedProvider == null) {
                    widget.controller.setScriptProvider(
                      ScriptProvider.robloxScripts,
                    );
                  } else if (widget.controller.remoteScripts.isEmpty) {
                    widget.controller.searchRemoteScripts();
                  }
                },
              ),
            ),
            Positioned(
              left: 109,
              top: 63,
              width: 171,
              bottom: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xff282827),
                  border: Border.all(color: const Color(0xff212120)),
                ),
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    if (_searchTab) ...[
                      SizedBox(
                        height: 26,
                        child: TextField(
                          controller: _search,
                          style: _type(11, color: const Color(0xffc0c0c0)),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText:
                                'Search ${widget.controller.selectedProvider?.domain ?? 'scripts'}…',
                            hintStyle: _type(
                              11,
                              color: const Color(0xff6e6e6e),
                            ),
                            filled: true,
                            fillColor: const Color(0xff272727),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 5,
                            ),
                            enabledBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.zero,
                              borderSide: BorderSide(color: Color(0xff2d2d2d)),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.zero,
                              borderSide: BorderSide(color: Color(0xff3a3a3a)),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (v) =>
                              widget.controller.searchRemoteScripts(v),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Expanded(
                      child: ListView(
                        children: [
                          if (_searchTab && widget.controller.remoteLoading)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Loading…',
                                style: _type(
                                  10,
                                  color: const Color(0xffa3a3a3),
                                ),
                              ),
                            )
                          else
                            for (final script in scripts) ...[
                              SizedBox(
                                height: 27.125,
                                child: TextButton(
                                  onPressed: () => setState(() {
                                    if (_searchTab) {
                                      _selectedRemote = script.id;
                                    } else {
                                      _selectedLocal = script.id;
                                    }
                                  }),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: const RoundedRectangleBorder(),
                                    alignment: Alignment.centerLeft,
                                    backgroundColor: item?.id == script.id
                                        ? const Color(0xff3c3c3c)
                                        : Colors.transparent,
                                    foregroundColor: item?.id == script.id
                                        ? const Color(0xffe8e8e8)
                                        : const Color(0xffc0c0c0),
                                    textStyle: _type(11, height: 1.375),
                                    visualDensity: VisualDensity.standard,
                                  ),
                                  child: Text(script.title),
                                ),
                              ),
                              const SizedBox(height: 1),
                            ],
                          if (_searchTab &&
                              widget.controller.providerErrors.isNotEmpty)
                            Text(
                              widget.controller.providerErrors.values.join(
                                '\n',
                              ),
                              style: _type(10, color: const Color(0xffcc6e6e)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 289,
              top: 63,
              width: rightW,
              height: imageH,
              child: SynapseThemeElement(
                controller: widget.controller,
                preset: InterfacePreset.synapse2017,
                windowId: 'scriptHub',
                elementId: 'titleBar',
                child: GestureDetector(onTap: _code, child: image),
              ),
            ),
            Positioned(
              left: 289,
              top: 63 + imageH,
              width: rightW,
              height: descriptionH,
              child: ColoredBox(
                color: const Color(0xff282827),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            item == null
                                ? 'Pick a script on the left to preview it.'
                                : _searchTab
                                ? '${item.title}\nSource: ${item.provider.domain}'
                                : item.description,
                            style: _type(
                              14,
                              color: const Color(0xffc0c0c0),
                              height: 1.375,
                            ),
                          ),
                        ),
                      ),
                      if (_runError != null)
                        Text(
                          _runError!,
                          style: _type(11, color: const Color(0xffcc6e6e)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 289,
              bottom: 6.19,
              width: rightW,
              height: 36.81,
              child: Row(
                children: [
                  Expanded(
                    child: OgButton(
                      _busy ? 'Running…' : 'Run Script',
                      theme: t,
                      height: 36.81,
                      fontSize: 14,
                      onPressed: widget.bridgeReady && item != null
                          ? _run
                          : null,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: OgButton(
                      'Close',
                      theme: t,
                      height: 36.81,
                      fontSize: 14,
                      onPressed: widget.onClose,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 58,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => widget.onDragStart?.call(),
                child: ColoredBox(color: t.panel),
              ),
            ),
            Positioned(
              left: 6,
              top: 16,
              width: 126,
              height: 26,
              child: SynapseThemeLogo(
                controller: widget.controller,
                preset: InterfacePreset.synapse2017,
                windowId: 'scriptHub',
                child: OgLogo(theme: t),
              ),
            ),
          ],
        );
      },
    );
  }
}

class OgConsolePage extends StatelessWidget {
  TextStyle _type(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) => ogText(size, color: color, weight: weight, height: height).copyWith(
    fontFamily: SynapseThemeCatalog.current(
      controller,
      InterfacePreset.synapse2017,
    ).fontFamily,
  );

  const OgConsolePage({
    super.key,
    required this.controller,
    required this.theme,
    required this.onClose,
    this.onDragStart,
  });
  final OrionController controller;
  final OgTheme theme;
  final VoidCallback onClose;
  final VoidCallback? onDragStart;
  @override
  Widget build(BuildContext context) {
    final logs = controller.activities
        .where((a) => a.kind == ActivityKind.execution)
        .toList()
        .reversed
        .toList();
    final text = logs.map((a) => '${a.title}: ${a.detail}').join('\n');
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: theme.window)),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 42,
          child: SynapseThemeElement(
            controller: controller,
            preset: InterfacePreset.synapse2017,
            windowId: 'console',
            elementId: 'titleBar',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => onDragStart?.call(),
              child: ColoredBox(color: theme.panel),
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 11,
          width: 110,
          height: 20,
          child: SynapseThemeLogo(
            controller: controller,
            preset: InterfacePreset.synapse2017,
            windowId: 'console',
            child: OgLogo(theme: theme),
          ),
        ),
        Positioned(
          left: 132,
          top: 13,
          child: Text(
            'F9 Console',
            style: _type(14, color: theme.text, height: 16 / 14),
          ),
        ),
        Positioned(
          right: 8,
          top: 9,
          child: Row(
            children: [
              OgButton(
                'Copy',
                theme: theme,
                height: 24,
                width: 56,
                fontSize: 12,
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
              ),
              const SizedBox(width: 4),
              OgButton(
                'Clear',
                theme: theme,
                height: 24,
                width: 56,
                fontSize: 12,
                onPressed: controller.clearActivities,
              ),
              const SizedBox(width: 4),
              OgButton(
                '×',
                theme: theme,
                height: 24,
                width: 28,
                fontSize: 12,
                onPressed: onClose,
              ),
            ],
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          top: 50,
          bottom: 8,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xff1d1d1d),
              border: Border.all(color: const Color(0xff313131)),
            ),
            padding: const EdgeInsets.all(8),
            child: SelectionArea(
              child: ListView(
                children: [
                  if (logs.isEmpty)
                    Text(
                      controller.bridgeConnected
                          ? 'No output yet. Execute a script to see client output.'
                          : 'No output yet. Connect a client with Orion Bridge.',
                      style: _type(
                        11,
                        color: const Color(0xff6e6e6e),
                        height: 1.375,
                      ),
                    )
                  else
                    for (final entry in logs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${entry.title}: ${entry.detail}',
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            height: 1.375,
                            color: entry.severity == ActivitySeverity.error
                                ? const Color(0xffcf6363)
                                : entry.severity == ActivitySeverity.warning
                                ? const Color(0xffe8c84a)
                                : const Color(0xffc0c0c0),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
