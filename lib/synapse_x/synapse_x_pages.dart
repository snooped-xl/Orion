import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/interface_preset.dart';
import '../models/orion_models.dart';
import '../models/remote_script.dart';
import '../state/orion_controller.dart';
import '../services/synapse_theme_catalog.dart';
import 'synapse_x_theme.dart';

class SynapseXOptions extends StatefulWidget {
  const SynapseXOptions({
    super.key,
    required this.controller,
    required this.theme,
    required this.nativeWindow,
    required this.onClose,
    required this.onBackToOrion,
    required this.onSelectInterface,
    required this.onNativePreferenceChanged,
    required this.obscure,
    required this.onThemeStudio,
  });
  final VoidCallback onThemeStudio;
  final OrionController controller;
  final SynapseXTheme theme;
  final bool nativeWindow;
  final VoidCallback onClose;
  final VoidCallback onBackToOrion;
  final Future<void> Function(InterfacePreset) onSelectInterface;
  final Future<void> Function() onNativePreferenceChanged;
  final Future<T?> Function<T>(Future<T?> Function()) obscure;
  @override
  State<SynapseXOptions> createState() => _SynapseXOptionsState();
}

class _SynapseXOptionsState extends State<SynapseXOptions> {
  TextStyle _type(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    bool segoe = false,
    double? height,
  }) =>
      SynapseXTheme.type(
        size,
        color: color,
        weight: weight,
        segoe: segoe,
        height: height,
      ).copyWith(
        fontFamily: SynapseThemeCatalog.current(
          widget.controller,
          InterfacePreset.synapseX,
        ).fontFamily,
      );

  OrionController get c => widget.controller;
  Map<String, Object?> get prefs =>
      c.getInterfacePreferences(InterfacePreset.synapseX);
  void set(String key, Object? value) =>
      c.setInterfacePreference(InterfacePreset.synapseX, key, value);
  bool option(String key) => prefs[key] == true;
  SynapseXTheme get p => widget.theme;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 110,
        decoration: BoxDecoration(
          color: p.panel,
          border: const Border(right: BorderSide(color: Color(0x4d000000))),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (final label in ['General', 'Theme'])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SizedBox(
                  height: 30,
                  width: double.infinity,
                  child: XButton(
                    label,
                    weight: FontWeight.w500,
                    lineHeight: 1.5,
                    onPressed: label == 'Theme' ? widget.onThemeStudio : () {},
                    theme: p,
                    size: 13,
                    background: label == 'General'
                        ? const Color(0xff4a4a4a)
                        : p.panel,
                    border: label == 'General'
                        ? const Color(0xff5a5a5a)
                        : const Color(0xff2a2a2a),
                  ),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _general(),
              ),
            ),
            Container(
              height: 46,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x4d000000))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 88,
                    height: 29,
                    child: XButton(
                      'Close',
                      onPressed: widget.onClose,
                      theme: p,
                      size: 13,
                      border: const Color(0xff2a2a2a),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _general() => Column(
    children: [
      _toggle(
        'Top Most',
        'All Synapse windows to stay on top.',
        'alwaysOnTop',
        native: true,
      ),
      _toggle(
        'Enhanced List',
        'Search, bookmarks, gists, and script-list theming.',
        'enhancedList',
      ),
      _toggle(
        'Minimap',
        'Show a miniature preview of the entire script on the right side.',
        'minimap',
      ),
      if (option('minimap'))
        _row(
          'Minimap size',
          'Change the size of the minimap.',
          Expanded(
            child: Slider(
              value: (prefs['minimapScale'] as num? ?? 1).toDouble().clamp(
                1,
                3,
              ),
              min: 1,
              max: 3,
              divisions: 2,
              onChanged: (v) => set('minimapScale', v),
            ),
          ),
        ),
      _toggle(
        'Resizable',
        'Drag edges to resize. Off restores the default 801×355.',
        'resizable',
        native: true,
      ),
      _sourceRow(),
      _toggle(
        'Edge Curve',
        'Win11 rounded corners. Off uses sharp square corners.',
        'edgeCurve',
      ),
      _switch(
        'Synapse 2017',
        'Switch to the Synapse 2017 multi-window UI.',
        InterfacePreset.synapse2017,
      ),
      _switch(
        'Synapse Blue',
        'Return to the Synapse Blue desktop UI.',
        InterfacePreset.synapseBlue,
      ),
      _switch(
        'Synapse v3',
        'Switch to the Synapse v3 UI.',
        InterfacePreset.synapseV3,
      ),
      _row(
        'Back to Orion',
        'Return to Orion with your open scripts.',
        const SizedBox.shrink(),
        buttonKey: const ValueKey('x-back-to-orion'),
        onTap: widget.onBackToOrion,
      ),
    ],
  );
  Widget _toggle(
    String label,
    String description,
    String key, {
    bool native = false,
  }) => _row(
    label,
    description,
    Text(
      option(key) ? 'ON' : 'OFF',
      style: _type(
        12,
        color: option(key) ? const Color(0xff5a9e5f) : const Color(0xffcf6363),
      ),
    ),
    onTap: () async {
      set(key, !option(key));
      if (native) await widget.onNativePreferenceChanged();
    },
  );
  Widget _switch(String label, String description, InterfacePreset preset) =>
      _row(
        label,
        description,
        Text('OFF', style: _type(12, color: const Color(0xffcf6363))),
        onTap: () => widget.onSelectInterface(preset),
      );
  Widget _row(
    String label,
    String description,
    Widget trailing, {
    VoidCallback? onTap,
    Key? buttonKey,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border.all(color: const Color(0xff2a2a2a)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 33,
            child: XButton(
              label,
              key: buttonKey,
              onPressed: onTap,
              theme: p,
              size: 12,
              background: const Color(0xff2d2d2d),
              border: const Color(0xff2a2a2a),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Text(
                description,
                style: _type(11, color: const Color(0xffa3a3a3), height: 1.375),
              ),
            ),
          ),
          trailing,
        ],
      ),
    ),
  );
  Widget _sourceRow() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      decoration: BoxDecoration(
        color: p.panel,
        border: Border.all(color: const Color(0xff2a2a2a)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 120,
                height: 33,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xff2d2d2d),
                  border: Border.all(color: const Color(0xff2a2a2a)),
                ),
                child: Text('Script Source', style: _type(12)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Script search website.',
                  style: _type(11, color: const Color(0xffa3a3a3)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final provider in ScriptProvider.values)
                SizedBox(
                  height: 25,
                  child: XButton(
                    provider == ScriptProvider.robloxScripts
                        ? 'robloxscripts.com'
                        : provider == ScriptProvider.rscripts
                        ? 'rscripts.net'
                        : provider.label,
                    onPressed: () {
                      set('scriptSource', provider.name);
                      c.setScriptProvider(provider);
                    },
                    theme: p,
                    size: 11,
                    border: Color(
                      c.selectedProvider == provider ? 0xffb0d8e5 : 0xff2a2a2a,
                    ),
                    background: Color(
                      c.selectedProvider == provider ? 0xffb0d8e5 : 0xff2d2d2d,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class SynapseXConsole extends StatelessWidget {
  TextStyle _type(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    bool segoe = false,
    double? height,
  }) =>
      SynapseXTheme.type(
        size,
        color: color,
        weight: weight,
        segoe: segoe,
        height: height,
      ).copyWith(
        fontFamily: SynapseThemeCatalog.current(
          controller,
          InterfacePreset.synapseX,
        ).fontFamily,
      );

  const SynapseXConsole({
    super.key,
    required this.controller,
    required this.theme,
    required this.onClose,
  });
  final OrionController controller;
  final SynapseXTheme theme;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final entries = controller.activities
        .where((e) => e.kind == ActivityKind.execution)
        .toList()
        .reversed
        .toList();
    return Column(
      children: [
        Container(
          height: 31,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x4d000000))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 22,
                child: XButton(
                  'Copy',
                  weight: FontWeight.w500,
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text: entries.map((e) => e.message).join('\n'),
                    ),
                  ),
                  theme: theme,
                  size: 12,
                  border: const Color(0x4d000000),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 56,
                height: 22,
                child: XButton(
                  'Clear',
                  weight: FontWeight.w500,
                  onPressed: controller.clearActivities,
                  theme: theme,
                  size: 12,
                  border: const Color(0x4d000000),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xff1e1e1e),
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (entries.isEmpty)
                  Text(
                    'No output yet. Attach, run the bridge script for your selected method, then Execute scripts that print/warn.',
                    style: _type(
                      11,
                      color: const Color(0xff6e6e6e),
                      height: 1.375,
                    ),
                  ),
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      e.message,
                      style: TextStyle(
                        fontFamily: 'SynapseXMono',
                        fontSize: 11,
                        height: 1.375,
                        color: switch (e.severity) {
                          ActivitySeverity.error => const Color(0xfff44747),
                          ActivitySeverity.warning => const Color(0xffcca700),
                          _ => const Color(0xffc0c0c0),
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SynapseXHub extends StatefulWidget {
  const SynapseXHub({
    super.key,
    required this.controller,
    required this.theme,
    required this.onClose,
    this.bridgeReady = false,
  });
  final OrionController controller;
  final SynapseXTheme theme;
  final VoidCallback onClose;
  final bool bridgeReady;
  @override
  State<SynapseXHub> createState() => _SynapseXHubState();
}

class _SynapseXHubState extends State<SynapseXHub> {
  TextStyle _type(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    bool segoe = false,
    double? height,
  }) =>
      SynapseXTheme.type(
        size,
        color: color,
        weight: weight,
        segoe: segoe,
        height: height,
      ).copyWith(
        fontFamily: SynapseThemeCatalog.current(
          widget.controller,
          InterfacePreset.synapseX,
        ).fontFamily,
      );

  bool _search = false, _running = false;
  int _selected = 0;
  RemoteScript? _remote;
  String? _error;
  final _query = TextEditingController();
  static const catalog = [
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
  OrionController get c => widget.controller;
  SynapseXTheme get p => widget.theme;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _setTab(bool search) async {
    setState(() => _search = search);
    if (search && c.remoteScripts.isEmpty && !c.remoteLoading) {
      c.setScriptProvider(c.selectedProvider ?? ScriptProvider.robloxScripts);
      await c.searchRemoteScripts();
    }
  }

  Future<void> _run() async {
    if (!widget.bridgeReady || _running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      if (_search) {
        if (_remote != null) await c.executeRemoteScript(_remote!);
      } else {
        final item = catalog[_selected];
        final body = item.$4.isEmpty
            ? await rootBundle.loadString(
                'assets/synapse_x/hub/scriptDumperLegacy.lua',
              )
            : item.$4;
        c.executeSource(body, name: item.$1);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = _search
        ? (_remote?.title ??
              (c.remoteLoading
                  ? 'Loading ${c.selectedProvider?.domain ?? 'scripts'} catalogue…'
                  : c.providerErrors.values.firstOrNull ??
                        'Pick a script on the left to preview it.'))
        : catalog[_selected].$2;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (ctx, box) {
          final listWidth = (box.maxWidth < 520 ? box.maxWidth * .28 : 171)
              .toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 33,
                      child: XButton(
                        'Synapse Hub',
                        weight: FontWeight.w500,
                        horizontalPadding: 8,
                        lineHeight: 1.5,
                        wrap: true,
                        onPressed: () => _setTab(false),
                        theme: p,
                        size: 13,
                        border: Color(!_search ? 0xff5a5a5a : 0xff2a2a2a),
                        background: !_search
                            ? const Color(0xff4a4a4a)
                            : p.panel,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 33,
                      child: XButton(
                        'Script Search',
                        weight: FontWeight.w500,
                        horizontalPadding: 8,
                        lineHeight: 1.5,
                        wrap: true,
                        onPressed: () => _setTab(true),
                        theme: p,
                        size: 13,
                        border: Color(_search ? 0xff5a5a5a : 0xff2a2a2a),
                        background: _search ? const Color(0xff4a4a4a) : p.panel,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: listWidth,
                decoration: BoxDecoration(
                  color: p.panel,
                  border: Border.all(color: const Color(0xff212120)),
                ),
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    if (_search)
                      SizedBox(
                        height: 26,
                        child: TextField(
                          controller: _query,
                          style: _type(11, color: const Color(0xffc0c0c0)),
                          decoration: InputDecoration(
                            hintText:
                                'Search ${c.selectedProvider?.domain ?? 'robloxscripts.com'}…',
                            hintStyle: _type(
                              11,
                              color: const Color(0xff6e6e6e),
                            ),
                            fillColor: const Color(0xff2d2d2d),
                            filled: true,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.zero,
                              borderSide: BorderSide(color: Color(0xff2a2a2a)),
                            ),
                          ),
                          onSubmitted: (query) {
                            c.setRemoteSearchQuery(query);
                            c.searchRemoteScripts();
                          },
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: _search
                            ? [
                                if (c.remoteLoading)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                for (final script in c.remoteScripts)
                                  _listItem(
                                    script.title,
                                    _remote?.key == script.key,
                                    () => setState(() => _remote = script),
                                  ),
                                if (!c.remoteLoading && c.remoteScripts.isEmpty)
                                  Text(
                                    c.providerErrors.values.firstOrNull ??
                                        'Empty page.',
                                    style: _type(
                                      10,
                                      color: const Color(0xff6e6e6e),
                                    ),
                                  ),
                              ]
                            : [
                                for (var i = 0; i < catalog.length; i++)
                                  _listItem(
                                    catalog[i].$1,
                                    _selected == i,
                                    () => setState(() => _selected = i),
                                  ),
                              ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: math.min(162, box.maxHeight * .48),
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xff252525),
                          border: Border.all(color: const Color(0xff212120)),
                        ),
                        child: _search
                            ? (_remote?.imageUrl != null
                                  ? Image.network(
                                      _remote!.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Image.asset(
                                        'assets/synapse_x/hub/script-preview.png',
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Image.asset(
                                      'assets/synapse_x/hub/script-preview.png',
                                      fit: BoxFit.cover,
                                    ))
                            : Image.asset(
                                'assets/synapse_x/hub/${catalog[_selected].$3}',
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: p.panel,
                          border: Border.all(color: const Color(0xff212120)),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  description,
                                  style: _type(
                                    13,
                                    color: const Color(0xffc0c0c0),
                                    height: 1.375,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              'Source: ${c.selectedProvider?.domain ?? 'robloxscripts.com'}',
                              style: _type(10, color: const Color(0xff7a7a7a)),
                            ),
                            if (_error != null)
                              Text(
                                _error!,
                                style: _type(
                                  11,
                                  color: const Color(0xffcc6e6e),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 33,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: XButton(
                              _running ? 'Running…' : 'Run Script',
                              onPressed:
                                  widget.bridgeReady &&
                                      (!_search || _remote != null)
                                  ? _run
                                  : null,
                              theme: p,
                              size: 13,
                              weight: FontWeight.w500,
                              horizontalPadding: 8,
                              lineHeight: 1.5,
                              border: const Color(0xff2a2a2a),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: XButton(
                              'Close',
                              onPressed: widget.onClose,
                              theme: p,
                              size: 13,
                              weight: FontWeight.w500,
                              horizontalPadding: 8,
                              lineHeight: 1.5,
                              border: const Color(0xff2a2a2a),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _listItem(String title, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 1),
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xff4a4a4a)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 6),
        visualDensity: VisualDensity.standard,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
        shape: const RoundedRectangleBorder(),
      ),
      child: Text(
        title,
        style: _type(
          11,
          color: Color(selected ? 0xffe8e8e8 : 0xffc0c0c0),
          height: 1.375,
          weight: FontWeight.w500,
        ),
      ),
    ),
  );
}
