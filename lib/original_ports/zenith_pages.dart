import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/interface_preset.dart';
import '../models/remote_script.dart';
import '../state/orion_controller.dart';
import '../services/desktop_launcher.dart';
import '../widgets/bridge_client_manager.dart';
import 'zenith_ui.dart';

class ZenithHome extends StatelessWidget {
  const ZenithHome({super.key, required this.animation});
  final Animation<double> animation;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 73,
        child: _glowCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hey there, orion!',
                style: zenithText(20, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  text:
                      'Your license expires in 11 months and 30 days. You can ',
                  children: [
                    TextSpan(
                      text: 'add time here.',
                      style: zenithText(14, color: const Color(0xffa473ff)),
                    ),
                  ],
                ),
                style: zenithText(14, color: zenithMuted),
              ),
            ],
          ),
          const [Color(0xff667eea), Color(0xff764ba2)],
          Alignment.topRight,
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Row(
          children: [
            Expanded(
              child: _glowCard(
                ZenithFade(
                  animation: animation,
                  delay: .3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Changelog',
                        style: zenithText(20, weight: FontWeight.w600),
                      ),
                      Text(
                        'Below you can find a changelog for the last few updates.',
                        style: zenithText(14, color: zenithMuted),
                      ),
                      const SizedBox(height: 25),
                      Center(
                        child: Text(
                          "You're all caught up! 🎊",
                          style: zenithText(14, color: zenithMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                const [Color(0xfff093fb), Color(0xfff5576c)],
                Alignment.topLeft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _glowCard(
                ZenithFade(
                  animation: animation,
                  delay: .2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'News',
                        style: zenithText(20, weight: FontWeight.w600),
                      ),
                      Text(
                        "Right now, there's no news to be seen. Come back later.",
                        style: zenithText(14, weight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const [Color(0xff4facfe), Color(0xff00f2fe)],
                Alignment.bottomLeft,
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _glowCard(Widget content, List<Color> colors, Alignment alignment) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: zenithPanel(
          Stack(
            children: [
              Positioned(
                left: alignment.x < 0 ? -135 : null,
                right: alignment.x > 0 ? -125 : null,
                top: alignment.y < 0 ? (alignment.x < 0 ? -96 : -136) : null,
                bottom: alignment.y > 0 ? -137 : null,
                width: 288,
                height: 292,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: alignment.x > 0
                        ? .24
                        : alignment.y < 0
                        ? .28
                        : .22,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 96, sigmaY: 96),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                child: content,
              ),
            ],
          ),
        ),
      );
}

Widget _search(
  TextEditingController controller,
  String placeholder,
  ValueChanged<String> changed, {
  double height = 40,
}) => SizedBox(
  height: height,
  child: TextField(
    controller: controller,
    onChanged: changed,
    style: zenithText(14),
    decoration: InputDecoration(
      isDense: true,
      hintText: placeholder,
      hintStyle: zenithText(14, color: const Color(0xff929292)),
      prefixIcon: const Padding(
        padding: EdgeInsets.all(12),
        child: ZenithGlyph(
          'Search',
          size: 16,
          stroke: true,
          color: Color(0xff929292),
        ),
      ),
      filled: true,
      fillColor: const Color(0x08000000),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff3a3b3c)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff3a3b3c)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff5a5b5c)),
      ),
    ),
  ),
);

class ZenithSettings extends StatefulWidget {
  const ZenithSettings({
    super.key,
    required this.controller,
    required this.animation,
    required this.onBack,
    required this.onPreference,
    required this.onTutorial,
  });
  final OrionController controller;
  final Animation<double> animation;
  final VoidCallback onBack, onTutorial;
  final void Function(String, Object?) onPreference;
  @override
  State<ZenithSettings> createState() => _ZenithSettingsState();
}

class _ZenithSettingsState extends State<ZenithSettings> {
  final search = TextEditingController();
  String? section;
  static const interfaceRows = <(String, String, String, bool)>[
    (
      'alwaysOnTop',
      'Always on Top',
      'Keep the window above all other windows',
      false,
    ),
    (
      'navigationSlideOut',
      'Navigation Slide-Out',
      'Enables the sliding animation/feature for the left-side navigation panel',
      true,
    ),
    (
      'statusGlow',
      'Status Indicator Glow',
      'Shows a glow effect behind the status indicator in the top-left corner',
      true,
    ),
    (
      'formatOnPaste',
      'Format Code on Paste',
      'Automatically format code when pasting into the editor',
      true,
    ),
    (
      'swapAttachExecute',
      'Swap Attach & Execute Buttons',
      'Swaps the positions of the Attach and Execute buttons',
      false,
    ),
    (
      'hideOpenButton',
      'Hide Open Button',
      'Hides the Open button from the UI',
      false,
    ),
    (
      'hideSaveButton',
      'Hide Save Button',
      'Hides the Save button from the UI',
      false,
    ),
    (
      'hideClearButton',
      'Hide Clear Button',
      'Hides the Clear button from the UI',
      false,
    ),
    (
      'hideOutputConsole',
      'Hide Output Console',
      'Completely hides the output console from the UI',
      false,
    ),
    (
      'showEditorHints',
      'Show Editor Hints',
      'Display helpful keyboard shortcut hints at the bottom of empty editor tabs',
      true,
    ),
  ];
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.toLowerCase();
    final preferences = widget.controller.getInterfacePreferences(
      InterfacePreset.zenithV2,
    );
    return Column(
      children: [
        SizedBox(
          height: section == null ? 78 : 55,
          child: Align(
            alignment: Alignment.topLeft,
            child: section == null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(4, 7, 0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: zenithText(25, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Configure Zeniths execution and appearance  (Help?)',
                          style: zenithText(14, color: zenithMuted),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      ZenithButton(
                        '‹',
                        width: 38,
                        height: 38,
                        fontSize: 31,
                        background: Colors.transparent,
                        onPressed: () => setState(() {
                          section = null;
                          search.clear();
                        }),
                      ),
                      const SizedBox(width: 13),
                      Text(
                        section!,
                        style: zenithText(25, color: Colors.white),
                      ),
                    ],
                  ),
          ),
        ),
        ZenithFade(
          animation: widget.animation,
          delay: .1,
          child: _search(
            search,
            section == null ? 'Search all settings...' : 'Search settings...',
            (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ZenithFade(
            animation: widget.animation,
            delay: .2,
            child: ListView(
              padding: const EdgeInsets.only(right: 8),
              children: section == null
                  ? [
                      for (final entry in const [
                        (
                          'Execution Settings',
                          'Configure how scripts are executed and your preferences',
                        ),
                        (
                          'Interface Settings',
                          'Customise the appearance and behavior of the interface',
                        ),
                        (
                          'Other Settings',
                          'Additional configuration options and preferences',
                        ),
                      ])
                        if ('${entry.$1} ${entry.$2}'.toLowerCase().contains(
                          query,
                        ))
                          _card(
                            entry.$1,
                            entry.$2,
                            ZenithButton(
                              '›',
                              width: 30,
                              background: Colors.transparent,
                              fontSize: 28,
                              onPressed: () => setState(() {
                                section = entry.$1;
                                search.clear();
                              }),
                            ),
                            press: () => setState(() {
                              section = entry.$1;
                              search.clear();
                            }),
                          ),
                      if ('restart tutorial'.contains(query))
                        _card(
                          'Restart Tutorial',
                          "Start the guided tour of Zenith's interface again",
                          ZenithButton(
                            'Start Tutorial',
                            background: const Color(0xff0d4aff),
                            onPressed: null,
                          ),
                        ),
                      if ('orion'.contains(query))
                        _card(
                          'Orion',
                          "Return to Orion's interface selection",
                          ZenithButton(
                            'Back to Orion',
                            key: const ValueKey('zenith-back-to-orion'),
                            onPressed: widget.onBack,
                          ),
                        ),
                    ]
                  : section == 'Interface Settings'
                  ? [
                      if ('theme'.contains(query))
                        _card(
                          'Theme',
                          'Customise the appearance of Zenith with themes',
                          ZenithButton('Dark', width: 110),
                        ),
                      for (final row in interfaceRows)
                        if ('${row.$2} ${row.$3}'.toLowerCase().contains(query))
                          _card(
                            row.$2,
                            row.$3,
                            ZenithToggle(
                              value: preferences[row.$1] is bool
                                  ? preferences[row.$1] as bool
                                  : row.$4,
                              onChanged: (value) =>
                                  widget.onPreference(row.$1, value),
                            ),
                          ),
                    ]
                  : [
                      _card(
                        'Orion Bridge',
                        widget.controller.bridgeConnected
                            ? '${widget.controller.bridgeClients.length} clients connected'
                            : 'Run Orion Bridge in your executor to connect.',
                        ZenithButton(
                          'Clients',
                          onPressed: () => unawaited(
                            showBridgeClientManager(
                              context,
                              controller: widget.controller,
                            ),
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

  Widget _card(
    String title,
    String description,
    Widget trailing, {
    VoidCallback? press,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: InkWell(
      onTap: press,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: section != null || press != null
              ? const Color(0x18ffffff)
              : zenithCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: zenithText(16, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(description, style: zenithText(14, color: zenithMuted)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            trailing,
          ],
        ),
      ),
    ),
  );
}

class ZenithHub extends StatefulWidget {
  const ZenithHub({
    super.key,
    required this.controller,
    required this.animation,
    required this.onOpen,
    required this.bridgeReady,
  });
  final OrionController controller;
  final Animation<double> animation;
  final Future<void> Function(RemoteScript) onOpen;
  final bool bridgeReady;
  @override
  State<ZenithHub> createState() => _ZenithHubState();
}

class _ZenithHubState extends State<ZenithHub> {
  final query = TextEditingController();
  String filter = 'Recent';
  final busy = <String>{};
  OrionController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (c.selectedProvider == null) {
        c.setScriptProvider(ScriptProvider.robloxScripts);
      } else if (c.remoteScripts.isEmpty) {
        unawaited(c.searchRemoteScripts());
      }
    });
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> _load(RemoteScript script, {bool copy = false}) async {
    if (busy.contains(script.key)) return;
    setState(() => busy.add(script.key));
    try {
      if (copy) {
        await Clipboard.setData(
          ClipboardData(text: await c.loadRemoteScript(script)),
        );
      } else {
        await widget.onOpen(script);
      }
    } on Object catch (error) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Script Hub', style: zenithText(18)),
            content: Text('$error', style: zenithText(14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy.remove(script.key));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (_, _) => Column(
      children: [
        SizedBox(
          height: 73,
          child: ZenithFade(
            animation: widget.animation,
            duration: .2,
            offset: 2,
            css: true,
            child: zenithHeader(
              'Script Hub',
              'Discover and run scripts from ${c.selectedProvider?.domain ?? 'robloxscripts.com'}',
            ),
          ),
        ),
        const SizedBox(height: 12),
        ZenithFade(
          animation: widget.animation,
          duration: .3,
          offset: 2,
          css: true,
          child: LayoutBuilder(
            builder: (_, box) => Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: (box.maxWidth - 445).clamp(120, box.maxWidth),
                  child: _search(
                    query,
                    'Search for scripts...',
                    c.setRemoteSearchQuery,
                  ),
                ),
                Container(
                  width: 174,
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x0dffffff),
                    border: Border.all(color: const Color(0xff3a3b3c)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ScriptProvider>(
                      value: c.selectedProvider ?? ScriptProvider.robloxScripts,
                      isExpanded: true,
                      dropdownColor: const Color(0xff121212),
                      style: zenithText(14),
                      items: [
                        for (final provider in ScriptProvider.values)
                          DropdownMenuItem(
                            value: provider,
                            child: Text(
                              provider == ScriptProvider.robloxScripts
                                  ? provider.domain
                                  : provider.label,
                            ),
                          ),
                      ],
                      onChanged: c.setScriptProvider,
                    ),
                  ),
                ),
                for (final name in ['Recent', 'Popular', 'Universal'])
                  ZenithButton(
                    name,
                    height: 32,
                    radius: 16,
                    background: filter == name
                        ? const Color(0xff39a2ff)
                        : const Color(0x0dffffff),
                    onPressed: () {
                      setState(() => filter = name);
                      unawaited(c.searchRemoteScripts(query.text));
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              final scripts = [...c.remoteScripts];
              if (filter == 'Popular') {
                scripts.sort((a, b) => b.views.compareTo(a.views));
              }
              final filtered = filter == 'Universal'
                  ? scripts
                        .where(
                          (s) => s.game.toLowerCase().contains('universal'),
                        )
                        .toList()
                  : scripts;
              if (filtered.isEmpty) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c.remoteLoading)
                          const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xff39a2ff),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          c.remoteLoading
                              ? 'Loading scripts...'
                              : 'No scripts found',
                          style: zenithText(20),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.providerErrors.isEmpty
                              ? 'Search for scripts or browse another provider.'
                              : c.providerErrors.values.join('\n'),
                          style: zenithText(14, color: zenithMuted),
                        ),
                        const SizedBox(height: 16),
                        if (!c.remoteLoading)
                          ZenithButton(
                            'Retry',
                            onPressed: () =>
                                unawaited(c.searchRemoteScripts(query.text)),
                          ),
                      ],
                    ),
                  ),
                );
              }
              final count = box.maxWidth >= 900
                  ? 3
                  : box.maxWidth >= 560
                  ? 2
                  : 1;
              final width = (box.maxWidth - (count - 1) * 16) / count;
              return SingleChildScrollView(
                child: Column(
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final script in filtered)
                          SizedBox(
                            width: width,
                            height: 320,
                            child: _card(script),
                          ),
                      ],
                    ),
                    if (c.remoteHasMore)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ZenithButton(
                          c.remoteLoadingMore ? 'Loading...' : 'Load more',
                          onPressed: c.remoteLoadingMore
                              ? null
                              : () => unawaited(c.loadMoreRemoteScripts()),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
  Widget _card(RemoteScript script) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0x03ffffff),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xff3a3b3c)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 144,
            width: double.infinity,
            child: ColoredBox(
              color: const Color(0x80000000),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  script.imageUrl == null
                      ? const Center(
                          child: ZenithGlyph(
                            'ScriptHub',
                            size: 38,
                            color: Color(0x667c8293),
                          ),
                        )
                      : Image.network(
                          script.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: ZenithGlyph(
                              'ScriptHub',
                              size: 38,
                              color: Color(0x667c8293),
                            ),
                          ),
                        ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 48,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x80000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (script.isVerified)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _badge('Verified', const Color(0xff22c55e)),
                    ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (script.hasKey)
                          _badge('Key', const Color(0xffff7940)),
                        if (script.hasKey &&
                            script.game.toLowerCase().contains('universal'))
                          const SizedBox(width: 8),
                        if (script.game.toLowerCase().contains('universal'))
                          _badge('Universal', const Color(0xe69a9a9a)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          script.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: zenithText(16, color: Colors.white, weight: FontWeight.w500),
        ),
        if (script.updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Updated ${_relative(script.updatedAt!)}',
              style: zenithText(12, color: zenithMuted),
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              script.isPaid ? 'Paid' : 'Free',
              style: zenithText(
                12,
                color: script.isPaid
                    ? const Color(0xffff7940)
                    : const Color(0x809a9a9a),
              ),
            ),
            const Spacer(),
            const ZenithGlyph('HubEye', size: 12, stroke: true),
            const SizedBox(width: 4),
            Text('${script.views}', style: zenithText(12, color: zenithMuted)),
          ],
        ),
        const Spacer(),
        Text(
          script.game.toLowerCase().contains('universal')
              ? 'Works in any game'
              : 'Game: ${script.game}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: zenithText(12, color: zenithMuted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ZenithButton(
                'Execute',
                icon: 'HubPlay',
                background: const Color(0x207c8293),
                onPressed: widget.bridgeReady
                    ? () => unawaited(c.executeRemoteScript(script))
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Open in editor',
              child: ZenithButton(
                '',
                icon: 'HubEdit',
                iconStroke: true,
                width: 36,
                onPressed: busy.contains(script.key)
                    ? null
                    : () => unawaited(_load(script)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: text == 'Universal' ? .05 : .2),
      border: Border.all(color: color.withValues(alpha: .3)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: zenithText(12, color: color)),
  );
  String _relative(DateTime value) {
    final seconds = DateTime.now().difference(value).inSeconds;
    for (final unit in const [
      ('year', 31536000),
      ('month', 2592000),
      ('week', 604800),
      ('day', 86400),
      ('hour', 3600),
      ('minute', 60),
    ]) {
      final count = seconds ~/ unit.$2;
      if (count > 0) return '$count ${unit.$1}${count == 1 ? '' : 's'} ago';
    }
    return 'just now';
  }
}

class ZenithDocumentation extends StatefulWidget {
  const ZenithDocumentation({
    super.key,
    required this.animation,
    this.onVisitHelp,
  });
  final Animation<double> animation;
  final ValueChanged<String?>? onVisitHelp;
  @override
  State<ZenithDocumentation> createState() => _ZenithDocumentationState();
}

class _ZenithDocumentationState extends State<ZenithDocumentation> {
  static const categories = [
    'All',
    'Actors',
    'Bit',
    'Cache',
    'Closures',
    'Crypt',
    'CSV',
    'Debug',
    'DirectoryWatcher',
    'Drawing',
    'DrawingImmediate',
    'Duration',
    'Filesystem',
    'HTTP',
    'Input',
    'Instance',
    'Math',
    'Metatable',
    'Miscellaneous',
    'Regex',
    'Scripts',
    'SecureTable',
    'Stopwatch',
    'WebSocket',
  ];
  final search = TextEditingController(), scroll = ScrollController();
  final searchFocus = FocusNode();
  List<Map<String, dynamic>> functions = [];
  String category = 'General';
  String? expanded;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final data =
        jsonDecode(
              await rootBundle.loadString(
                'assets/original_zenith/Data/function-documentation.json',
              ),
            )
            as List;
    if (mounted) setState(() => functions = data.cast<Map<String, dynamic>>());
  }

  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  void _category(String value) {
    setState(() {
      category = value;
      expanded = null;
      if (value == 'General') search.clear();
    });
    _resetKnowledgeScroll(scroll);
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final inCategory = functions
        .where((f) => category == 'All' || f['category'] == category)
        .toList();
    final results =
        inCategory
            .where(
              (f) => [
                f['name'],
                f['description'],
                ...(f['aliases'] as List? ?? []),
              ].any((value) => '$value'.toLowerCase().contains(query)),
            )
            .toList()
          ..sort(
            (a, b) => '${a['name']}'.toLowerCase().compareTo(
              '${b['name']}'.toLowerCase(),
            ),
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          if (category != 'General') {
            searchFocus.requestFocus();
            search.selection = TextSelection(
              baseOffset: 0,
              extentOffset: search.text.length,
            );
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: _knowledgeShell(
          'Function Documentation',
          "Browse and search Zenith's custom Lua functions and API",
          widget.animation,
          sidebarWidth: 224,
          sidebar: ListView(
            padding: EdgeInsets.zero,
            children: [
              _knowledgeLabel('DOCUMENTATION'),
              _knowledgeSidebar(
                'General',
                category == 'General',
                () => _category('General'),
                key: const ValueKey('zenith-doc-general'),
              ),
              _knowledgeDivider(),
              _knowledgeLabel('CATEGORIES'),
              for (final name in categories.where(
                (n) => n == 'All' || functions.any((f) => f['category'] == n),
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _knowledgeSidebar(
                    name,
                    category == name,
                    () => _category(name),
                    key: ValueKey('zenith-doc-category-$name'),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (category != 'General')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0x1affffff)),
                    ),
                  ),
                  child: _knowledgeSearch(
                    search,
                    'Search functions...',
                    (_) {
                      setState(() => expanded = null);
                      _resetKnowledgeScroll(scroll);
                    },
                    focusNode: searchFocus,
                    key: const ValueKey('zenith-doc-search'),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.all(32),
                  child: _knowledgeStack(
                    functions.isEmpty
                        ? [
                            _knowledgeEmpty(
                              'Documentation unavailable',
                              'The preserved Zenith function reference could not be loaded.',
                            ),
                          ]
                        : category == 'General'
                        ? [_welcome()]
                        : results.isEmpty
                        ? [
                            _knowledgeEmpty(
                              'No functions found',
                              query.isEmpty
                                  ? 'There are no functions in this category.'
                                  : 'Couldn’t find any functions matching "${search.text.trim()}".',
                              action: query.isEmpty
                                  ? null
                                  : () => setState(search.clear),
                            ),
                          ]
                        : [
                            _knowledgeText(
                              query.isEmpty
                                  ? category
                                  : '${results.length} result${results.length == 1 ? '' : 's'} out of ${inCategory.length} ${category == 'All' ? 'total' : 'in $category'}',
                              12,
                            ),
                            for (final item in results) _function(item),
                          ],
                    spacing: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcome() => Padding(
    padding: const EdgeInsets.all(20),
    child: _knowledgeStack([
      _knowledgeText(
        "Welcome to Zenith's In-App Function Documentation",
        30,
        color: _knowledgeSecondary,
        weight: FontWeight.w700,
      ),
      _knowledgeInfo('Zenith has it all (and more)!', [
        'We have the most expanded custom Lua environment on the market (typically 100% UNC + more), which comes with many novelty and QoL features for you to adopt. As a scripter, you can navigate our documentation here and get familiar with our environment.',
        'Browse the categories in the sidebar or use the search functionality to find specific functions. Each function entry includes syntax, parameters, return values, and example usage.',
      ]),
      _knowledgeStack([
        _knowledgeText(
          'FAQ',
          16,
          color: _knowledgeSecondary,
          weight: FontWeight.w600,
        ),
        _knowledgeInfo("I'm still confused with X!", [
          "You're welcome to try either our official documentation or ask our community. You can find our Discord server by heading over to the Settings page and going to the bottom of the main page.",
        ]),
        _knowledgeStack([
          _knowledgeText(
            'Can I suggest a function to you?',
            16,
            color: _knowledgeSecondary,
            weight: FontWeight.w600,
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _knowledgeText(
                'Yes, we welcome suggestions openly. Learn more in our ',
                16,
              ),
              _knowledgeLink(
                'Help Center guide',
                () => widget.onVisitHelp?.call(
                  'Can I contribute or suggest features?',
                ),
              ),
              _knowledgeText('.', 16),
            ],
          ),
        ], spacing: 8),
        _knowledgeStack([
          _knowledgeInfo("I'm confused on how to actually even use Zenith...?", [
            "This documentation covers our environment. If you're confused on other aspects, visit our Help Center for comprehensive guides.",
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: _KnowledgeButton(
              onPressed: () => widget.onVisitHelp?.call(null),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              background: const Color(0x1839a2ff),
              border: const Color(0x4d39a2ff),
              child: _knowledgeText(
                'Visit Help Center',
                13,
                color: _knowledgeInfoColor,
                weight: FontWeight.w500,
              ),
            ),
          ),
        ], spacing: 8),
      ], spacing: 16),
    ], spacing: 24),
  );
  Widget _function(Map<String, dynamic> f) {
    final name = '${f['name']}', open = expanded == f['name'];
    final aliases = (f['aliases'] as List? ?? []).cast<String>();
    return _knowledgeFrame(
      _knowledgeStack([
        _KnowledgeButton(
          key: ValueKey('zenith-function-$name'),
          onPressed: () => setState(() => expanded = open ? null : name),
          padding: const EdgeInsets.all(12),
          radius: 12,
          child: Row(
            children: [
              Expanded(
                child: _knowledgeStack([
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _knowledgeText(
                        name,
                        14,
                        color: _knowledgePrimary,
                        weight: FontWeight.w500,
                        mono: true,
                      ),
                      if (aliases.isNotEmpty)
                        _knowledgeText(
                          '  (or ${aliases.join(', ')})',
                          12,
                          mono: true,
                        ),
                    ],
                  ),
                  _knowledgeText('${f['description']}', 12),
                ], spacing: 4),
              ),
              const SizedBox(width: 12),
              _knowledgeTag(
                '${f['category']}',
                color: _knowledgeExpanded,
                radius: 6,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              const SizedBox(width: 10),
              _knowledgeText(open ? '⌃' : '⌄', 16, color: _knowledgeSecondary),
            ],
          ),
        ),
        if (open)
          Container(
            decoration: const BoxDecoration(
              color: _knowledgeExpanded,
              border: Border(top: BorderSide(color: _knowledgeBorder)),
            ),
            padding: const EdgeInsets.all(12),
            child: _knowledgeStack([
              _knowledgeTitled('Syntax', _KnowledgeCode('${f['syntax']}')),
              if ((f['params'] as List? ?? []).isNotEmpty)
                _knowledgeInset(
                  'Parameters',
                  _knowledgeStack([
                    for (final p in f['params'] as List)
                      _knowledgeStack([
                        Wrap(
                          children: [
                            _knowledgeText(
                              '${p['name']}',
                              12,
                              color: _knowledgeWarning,
                              mono: true,
                            ),
                            _knowledgeText('  (${p['type']})', 12),
                            if (p['optional'] == true)
                              _knowledgeText('  (optional)', 11),
                          ],
                        ),
                        _knowledgeText('${p['description']}', 12),
                      ], spacing: 4),
                  ], spacing: 8),
                ),
              if ((f['returns'] as List? ?? []).isNotEmpty)
                _knowledgeInset(
                  'Returns',
                  _knowledgeStack([
                    for (final r in f['returns'] as List)
                      _knowledgeStack([
                        _knowledgeText('${r['type']}', 12, mono: true),
                        _knowledgeText('${r['description']}', 12),
                      ], spacing: 4),
                  ], spacing: 8),
                ),
              if ((f['examples'] as List? ?? []).isNotEmpty)
                _knowledgeTitled(
                  'Examples',
                  _knowledgeStack([
                    for (final e in f['examples'] as List) ...[
                      if ('${e['description'] ?? ''}'.isNotEmpty)
                        _knowledgeText('${e['description']}', 12),
                      _KnowledgeCode('${e['code']}'),
                    ],
                  ], spacing: 10),
                ),
              if ('${f['notes'] ?? ''}'.isNotEmpty)
                _knowledgeInset('Notes', _knowledgeText('${f['notes']}', 12)),
            ], spacing: 12),
          ),
      ], spacing: 0),
      radius: 12,
    );
  }
}

const _knowledgePrimary = Color(0xfff0f0f0),
    _knowledgeSecondary = Color(0xffd8d8d8),
    _knowledgeMuted = Color(0xff8d8d8d),
    _knowledgeInfoColor = Color(0xff39a2ff),
    _knowledgeWarning = Color(0xffe4b958),
    _knowledgeCard = Color(0xff101217),
    _knowledgeExpanded = Color(0xff0c0e12),
    _knowledgeSelected = Color(0xff1e1e1e),
    _knowledgeHover = Color(0xff252525),
    _knowledgeBorder = Color(0xff272b36);

Widget _knowledgeShell(
  String title,
  String subtitle,
  Animation<double> animation, {
  required Widget sidebar,
  required Widget body,
  required double sidebarWidth,
}) => Column(
  children: [
    SizedBox(
      height: 73,
      child: ZenithFade(
        animation: animation,
        delay: .1,
        child: zenithHeader(title, subtitle),
      ),
    ),
    const SizedBox(height: 12),
    Expanded(
      child: Row(
        children: [
          SizedBox(
            key: ValueKey(
              title == 'Function Documentation'
                  ? 'zenith-doc-sidebar'
                  : 'zenith-help-sidebar',
            ),
            width: sidebarWidth,
            child: ZenithFade(
              animation: animation,
              delay: .2,
              child: zenithPanel(sidebar, padding: const EdgeInsets.all(12)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ZenithFade(
              animation: animation,
              delay: .3,
              child: zenithPanel(body),
            ),
          ),
        ],
      ),
    ),
  ],
);

Widget _knowledgeText(
  String text,
  double size, {
  Color color = _knowledgeMuted,
  FontWeight weight = FontWeight.w400,
  bool mono = false,
}) => Text(
  text,
  style: zenithText(
    size,
    color: color,
    weight: weight,
    height: 1.48,
    family: mono ? 'OriginalConsolas' : 'OriginalNunito',
  ),
);
Widget _knowledgeStack(List<Widget> children, {double spacing = 12}) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (final entry in children.indexed) ...[
      if (entry.$1 > 0) SizedBox(height: spacing),
      entry.$2,
    ],
  ],
);
Widget _knowledgeFrame(
  Widget child, {
  double radius = 8,
  Color color = _knowledgeCard,
  EdgeInsets padding = EdgeInsets.zero,
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: color,
    border: Border.all(color: _knowledgeBorder),
    borderRadius: BorderRadius.circular(radius),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);
Widget _knowledgeLabel(String text) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
  child: _knowledgeText(text, 11, weight: FontWeight.w500),
);
Widget _knowledgeDivider() => const Padding(
  padding: EdgeInsets.symmetric(vertical: 8),
  child: ColoredBox(color: _knowledgeBorder, child: SizedBox(height: 1)),
);
Widget _knowledgeSidebar(
  String label,
  bool selected,
  VoidCallback action, {
  Key? key,
}) => _KnowledgeButton(
  key: key,
  onPressed: action,
  background: selected ? _knowledgeSelected : Colors.transparent,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  child: Text(
    label,
    style: zenithText(
      13,
      color: selected ? _knowledgePrimary : _knowledgeMuted,
      weight: FontWeight.w500,
    ),
  ),
);
Widget _knowledgeInfo(String title, List<String> paragraphs) =>
    _knowledgeStack([
      _knowledgeText(
        title,
        16,
        color: _knowledgeSecondary,
        weight: FontWeight.w600,
      ),
      for (final p in paragraphs) _knowledgeText(p, 16),
    ], spacing: 8);
Widget _knowledgeTitled(String title, Widget child) =>
    _knowledgeStack([_knowledgeText(title, 11), child], spacing: 5);
Widget _knowledgeInset(String title, Widget child) => _knowledgeTitled(
  title,
  _knowledgeFrame(child, padding: const EdgeInsets.all(9)),
);
Widget _knowledgeLink(String label, VoidCallback callback) => _KnowledgeButton(
  onPressed: callback,
  padding: EdgeInsets.zero,
  hover: Colors.transparent,
  child: _knowledgeText(
    label,
    16,
    color: _knowledgeInfoColor,
    weight: FontWeight.w500,
  ),
);
Widget _knowledgeTag(
  String text, {
  bool emphasis = false,
  Color color = const Color(0x08ffffff),
  double radius = 4,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: emphasis ? const Color(0x1839a2ff) : color,
    border: emphasis ? null : Border.all(color: _knowledgeBorder),
    borderRadius: BorderRadius.circular(radius),
  ),
  child: _knowledgeText(
    text,
    11,
    color: emphasis ? _knowledgeSecondary : _knowledgeMuted,
  ),
);
Widget _knowledgeSearch(
  TextEditingController controller,
  String hint,
  ValueChanged<String> change, {
  Key? key,
  FocusNode? focusNode,
}) => SizedBox(
  height: 36,
  child: TextField(
    key: key,
    controller: controller,
    focusNode: focusNode,
    onChanged: change,
    style: zenithText(14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: zenithText(14, color: const Color(0x99ffffff)),
      isDense: true,
      filled: true,
      fillColor: const Color(0x08000000),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      prefixIcon: const Padding(
        padding: EdgeInsets.all(11),
        child: ZenithGlyph(
          'Search',
          size: 16,
          color: Color(0xff929292),
          stroke: true,
        ),
      ),
      prefixIconConstraints: const BoxConstraints.tightFor(
        width: 36,
        height: 36,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff3a3b3c)),
      ),
    ),
  ),
);
Widget _knowledgeEmpty(
  String title,
  String description, {
  VoidCallback? action,
}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
  child: _knowledgeStack([
    _knowledgeText(
      title,
      18,
      color: _knowledgeSecondary,
      weight: FontWeight.w500,
    ),
    _knowledgeText(description, 13),
    if (action != null)
      Align(
        alignment: Alignment.centerLeft,
        child: _KnowledgeButton(
          onPressed: action,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          background: const Color(0x1839a2ff),
          border: const Color(0x4d39a2ff),
          child: _knowledgeText('Clear search', 13, color: _knowledgeInfoColor),
        ),
      ),
  ], spacing: 10),
);
void _resetKnowledgeScroll(ScrollController scroll) =>
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(0);
    });

class _KnowledgeButton extends StatelessWidget {
  const _KnowledgeButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.padding = EdgeInsets.zero,
    this.background = Colors.transparent,
    this.hover = _knowledgeHover,
    this.border,
    this.radius = 8,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final Color background, hover;
  final Color? border;
  final double radius;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: ButtonStyle(
      padding: WidgetStatePropertyAll(padding),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: Alignment.centerLeft,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      side: WidgetStatePropertyAll(
        border == null ? BorderSide.none : BorderSide(color: border!),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.hovered) ? hover : background,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    child: child,
  );
}

class _KnowledgeCode extends StatefulWidget {
  const _KnowledgeCode(this.code, {this.helpStyle = false});
  final String code;
  final bool helpStyle;
  @override
  State<_KnowledgeCode> createState() => _KnowledgeCodeState();
}

class _KnowledgeCodeState extends State<_KnowledgeCode> {
  String _copy = 'Copy';
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copyText() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.code));
      if (mounted) setState(() => _copy = 'Copied');
    } on Object {
      if (mounted) setState(() => _copy = 'Failed');
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copy = 'Copy');
    });
  }

  @override
  Widget build(BuildContext context) => _knowledgeFrame(
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            widget.code,
            style: zenithText(
              widget.helpStyle ? 14 : 12,
              family: 'OriginalConsolas',
              color: widget.helpStyle ? _knowledgeWarning : _knowledgeSecondary,
              height: 1.48,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _KnowledgeButton(
          onPressed: _copyText,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: _knowledgeText(_copy, 10),
        ),
      ],
    ),
    padding: EdgeInsets.all(widget.helpStyle ? 16 : 9),
  );
}

class ZenithHelp extends StatefulWidget {
  const ZenithHelp({
    super.key,
    required this.animation,
    this.initialArticle,
    this.onOpenSettings,
  });
  final Animation<double> animation;
  final String? initialArticle;
  final VoidCallback? onOpenSettings;
  @override
  State<ZenithHelp> createState() => _ZenithHelpState();
}

class _ZenithHelpState extends State<ZenithHelp> {
  static const categories = [
    'Getting Started',
    'FAQs',
    'Troubleshooting',
    'Feature Tutorials',
  ];
  static const descriptions = {
    'Getting Started':
        'Learn the basics and get up and running quickly with Zenith.',
    'Feature Tutorials':
        "Step-by-step guides for using Zenith's features effectively.",
    'Troubleshooting':
        'Find solutions to common issues and problems you might encounter.',
    'FAQs': 'Frequently asked questions and answers about Zenith.',
  };
  static const overviewDescriptions = {
    'Getting Started': 'Learn the basics and get up and running quickly',
    'Feature Tutorials': "Step-by-step guides for using Zenith's features",
    'Troubleshooting': 'Solutions to common issues and problems',
    'FAQs': 'Frequently asked questions and answers',
  };
  final search = TextEditingController(), scroll = ScrollController();
  final searchFocus = FocusNode();
  List<Map<String, dynamic>> articles = [];
  Map<String, dynamic>? current;
  String? category;
  final history = <({String? article, String? category})>[
    (article: null, category: null),
  ];
  int historyIndex = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final data =
        jsonDecode(
              await rootBundle.loadString(
                'assets/original_zenith/Data/help-articles.json',
              ),
            )
            as List;
    if (mounted) {
      setState(() => articles = data.cast<Map<String, dynamic>>());
      if (widget.initialArticle != null) _articleNamed(widget.initialArticle!);
    }
  }

  @override
  void didUpdateWidget(ZenithHelp old) {
    super.didUpdateWidget(old);
    if (old.initialArticle != widget.initialArticle &&
        widget.initialArticle != null) {
      _articleNamed(widget.initialArticle!);
    }
  }

  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  void _show({
    Map<String, dynamic>? article,
    String? nextCategory,
    bool push = true,
  }) {
    setState(() {
      current = article;
      category = nextCategory;
      search.clear();
      if (push) {
        final record = (
          article: article?['title'] as String?,
          category: nextCategory,
        );
        if (history[historyIndex] != record) {
          history.removeRange(historyIndex + 1, history.length);
          history.add(record);
          historyIndex = history.length - 1;
        }
      }
    });
    _resetKnowledgeScroll(scroll);
  }

  void _articleNamed(String title) {
    for (final a in articles) {
      if ('${a['title']}'.toLowerCase() == title.toLowerCase()) {
        _show(article: a);
        return;
      }
    }
  }

  void _history(int direction) {
    final target = (historyIndex + direction).clamp(0, history.length - 1);
    if (target == historyIndex) return;
    historyIndex = target;
    final record = history[target];
    Map<String, dynamic>? article;
    for (final a in articles) {
      if (a['title'] == record.article) article = a;
    }
    _show(article: article, nextCategory: record.category, push: false);
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final found =
        articles
            .where(
              (a) => [
                a['title'],
                _helpSearchText('${a['content']}'),
                ...(a['tags'] as List? ?? []),
              ].any((value) => '$value'.toLowerCase().contains(query)),
            )
            .toList()
          ..sort((a, b) => '${a['title']}'.compareTo('${b['title']}'));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _history(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _history(1),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            searchFocus.requestFocus,
      },
      child: Focus(
        autofocus: true,
        child: _knowledgeShell(
          'Help & Guides',
          'Learn how to use Zenith with comprehensive guides and tutorials',
          widget.animation,
          sidebarWidth: 256,
          sidebar: Column(
            children: [
              _knowledgeSearch(
                search,
                'Search articles...',
                (_) => setState(() {}),
                focusNode: searchFocus,
                key: const ValueKey('zenith-help-search'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _knowledgeLabel('HELP & GUIDES'),
                    _knowledgeSidebar(
                      'Overview',
                      current == null && category == null,
                      () => _show(),
                      key: const ValueKey('zenith-help-overview'),
                    ),
                    _knowledgeDivider(),
                    if (query.isNotEmpty) ...[
                      _knowledgeText(
                        '${found.length} result${found.length == 1 ? '' : 's'}',
                        11,
                        weight: FontWeight.w500,
                      ),
                      if (found.isEmpty)
                        _knowledgeEmpty(
                          'No articles found',
                          'No articles found for "${query.length > 30 ? query.substring(0, 30) : query}".',
                          action: () => setState(search.clear),
                        ),
                      for (final a in found)
                        _articleButton(a, includeCategory: true),
                    ] else
                      for (final name in categories) ...[
                        _KnowledgeButton(
                          onPressed: () => _show(nextCategory: name),
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                          child: _knowledgeText(
                            name.toUpperCase(),
                            11,
                            weight: FontWeight.w500,
                          ),
                        ),
                        for (final a in articles.where(
                          (a) => a['category'] == name,
                        ))
                          _articleButton(a),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.all(32),
            child: articles.isEmpty
                ? _knowledgeEmpty(
                    'Help unavailable',
                    'The preserved Zenith Help Center articles could not be loaded.',
                  )
                : current != null
                ? _articleContent(current!)
                : category != null
                ? _categoryContent(category!)
                : _overview(),
          ),
        ),
      ),
    );
  }

  Widget _articleButton(
    Map<String, dynamic> a, {
    bool includeCategory = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: _KnowledgeButton(
      key: ValueKey('zenith-help-article-${a['title']}'),
      onPressed: () => _show(article: a),
      background: current?['title'] == a['title']
          ? _knowledgeSelected
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: _knowledgeStack([
        _knowledgeText(
          '${a['title']}',
          13,
          color: current?['title'] == a['title']
              ? _knowledgePrimary
              : _knowledgeMuted,
          weight: FontWeight.w500,
        ),
        if (includeCategory) _knowledgeText('${a['category']}', 11),
      ], spacing: 3),
    ),
  );
  Widget _overview() => Padding(
    padding: const EdgeInsets.all(32),
    child: _knowledgeStack([
      _knowledgeText(
        'Welcome to Zenith Help Center',
        30,
        color: _knowledgeSecondary,
        weight: FontWeight.w700,
      ),
      _knowledgeText(
        'Find guides, help, tutorials, and answers to common questions about using Zenith. Browse articles by category or use the search to find specific topics.',
        16,
      ),
      for (var row = 0; row < 2; row++)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final name in categories.skip(row * 2).take(2))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _KnowledgeButton(
                      onPressed: () => _show(nextCategory: name),
                      background: _knowledgeCard,
                      border: _knowledgeBorder,
                      radius: 12,
                      padding: const EdgeInsets.all(20),
                      child: _knowledgeStack([
                        _knowledgeText(
                          name,
                          18,
                          color: _knowledgeSecondary,
                          weight: FontWeight.w600,
                        ),
                        _knowledgeText(overviewDescriptions[name]!, 14),
                        _knowledgeText(
                          '${articles.where((a) => a['category'] == name).length} articles',
                          12,
                          color: _knowledgeInfoColor,
                        ),
                      ], spacing: 7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      _knowledgeFrame(
        _knowledgeStack([
          _knowledgeText(
            'Still Need Help?',
            18,
            color: _knowledgeSecondary,
            weight: FontWeight.w600,
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _knowledgeText("Have a question that isn't covered here? ", 14),
              _knowledgeLink(
                'Join our Discord community',
                () => widget.onOpenSettings?.call(),
              ),
              _knowledgeText(' to get help from our team and other users.', 14),
            ],
          ),
        ], spacing: 10),
        radius: 12,
        padding: const EdgeInsets.all(24),
      ),
    ], spacing: 20),
  );
  Widget _categoryContent(String name) => Padding(
    padding: const EdgeInsets.all(32),
    child: _knowledgeStack([
      _breadcrumb([
        (label: 'Help Center', press: () => _show()),
        (label: name, press: null),
      ]),
      _knowledgeText(
        name,
        30,
        color: _knowledgeSecondary,
        weight: FontWeight.w700,
      ),
      _knowledgeText(descriptions[name]!, 16),
      _knowledgeStack([
        for (final a in articles.where((a) => a['category'] == name))
          _articleCard(a),
      ], spacing: 14),
    ], spacing: 18),
  );
  Widget _articleCard(
    Map<String, dynamic> a, {
    bool related = false,
  }) => _KnowledgeButton(
    onPressed: () => _show(article: a),
    padding: EdgeInsets.all(related ? 16 : 20),
    background: _knowledgeCard,
    border: _knowledgeBorder,
    radius: 12,
    child: _knowledgeStack([
      _knowledgeText(
        '${a['title']}',
        related ? 14 : 18,
        color: _knowledgeSecondary,
        weight: related ? FontWeight.w500 : FontWeight.w600,
      ),
      _knowledgeText(
        '${_helpExcerpt('${a['content']}', related ? 120 : 180)}${related ? '' : '...'}',
        related ? 13 : 14,
      ),
      if (!related) _tags((a['tags'] as List? ?? []).take(3)),
    ], spacing: related ? 4 : 9),
  );
  Widget _articleContent(Map<String, dynamic> a) {
    final related = articles
        .where(
          (b) => b['category'] == a['category'] && b['title'] != a['title'],
        )
        .take(3)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(32),
      child: _knowledgeStack([
        _breadcrumb([
          (label: 'Help Center', press: () => _show()),
          (
            label: '${a['category']}',
            press: () => _show(nextCategory: '${a['category']}'),
          ),
          (label: '${a['title']}', press: null),
        ]),
        _knowledgeText(
          '${a['title']}',
          30,
          color: _knowledgeSecondary,
          weight: FontWeight.w700,
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _knowledgeTag('${a['category']}', emphasis: true),
            for (final t in (a['tags'] as List? ?? []).take(3))
              _knowledgeTag('$t'),
          ],
        ),
        _markdown('${a['content']}'),
        if (related.isNotEmpty) ...[
          _knowledgeDivider(),
          _knowledgeText(
            'Related Articles',
            16,
            color: _knowledgeSecondary,
            weight: FontWeight.w600,
          ),
          _knowledgeStack([
            for (final r in related) _articleCard(r, related: true),
          ], spacing: 10),
        ],
      ], spacing: 18),
    );
  }

  Widget _tags(Iterable<dynamic> tags) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [for (final t in tags) _knowledgeTag('$t')],
  );
  Widget _breadcrumb(List<({String label, VoidCallback? press})> parts) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final p in parts.indexed) ...[
        if (p.$1 > 0) _knowledgeText('  /  ', 13),
        if (p.$2.press != null)
          _knowledgeLink(p.$2.label, p.$2.press!)
        else
          _knowledgeText(p.$2.label, 13, color: _knowledgeSecondary),
      ],
    ],
  );
  Widget _markdown(String content) {
    final children = <Widget>[], paragraph = <String>[], code = <String>[];
    var inCode = false;
    void flush() {
      if (paragraph.isNotEmpty) {
        children.add(_inline(paragraph.join(' ')));
        paragraph.clear();
      }
    }

    void flushCode() {
      if (code.isNotEmpty) {
        children.add(_KnowledgeCode(code.join('\n'), helpStyle: true));
        code.clear();
      }
    }

    for (final line in content.replaceAll('\r\n', '\n').split('\n')) {
      final text = line.trim();
      if (text.startsWith('```')) {
        flush();
        if (inCode) flushCode();
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        code.add(line);
        continue;
      }
      if (text.isEmpty) {
        flush();
        continue;
      }
      final heading = RegExp(r'^(#{1,3})\s+(.+)').firstMatch(text);
      if (heading != null) {
        flush();
        final level = heading.group(1)!.length;
        children.add(
          _knowledgeText(
            heading.group(2)!,
            level == 1
                ? 24
                : level == 2
                ? 20
                : 18,
            color: _knowledgeSecondary,
            weight: level == 1
                ? FontWeight.w700
                : level == 2
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        );
        continue;
      }
      final image = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$').firstMatch(text);
      if (image != null) {
        flush();
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _knowledgeFrame(
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: Image.asset(
                  'assets/original_zenith/Help/${image.group(2)!.replaceAll('\\', '/').split('/').last}',
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      _knowledgeEmpty('Image unavailable', image.group(1)!),
                ),
              ),
              radius: 8,
            ),
          ),
        );
        continue;
      }
      if (text.startsWith('[youtube:') && text.endsWith(']')) {
        flush();
        final id = text.substring(9, text.length - 1);
        children.add(
          _KnowledgeButton(
            onPressed: () =>
                _openExternal('https://www.youtube.com/watch?v=$id'),
            padding: const EdgeInsets.all(24),
            background: _knowledgeCard,
            border: _knowledgeBorder,
            radius: 12,
            child: SizedBox(
              height: 352,
              child: Center(
                child: _knowledgeStack([
                  Center(
                    child: _knowledgeText('▶', 30, color: _knowledgeInfoColor),
                  ),
                  Center(
                    child: _knowledgeText(
                      'Open video tutorial',
                      14,
                      color: _knowledgeSecondary,
                      weight: FontWeight.w500,
                    ),
                  ),
                ], spacing: 10),
              ),
            ),
          ),
        );
        continue;
      }
      final ordered = RegExp(r'^\s*(\d+)\.\s+(.+)$').firstMatch(line);
      final bullet = RegExp(r'^\s*[-*]\s+(.+)$').firstMatch(line);
      if (ordered != null || bullet != null) {
        flush();
        final nested = line.length - line.trimLeft().length >= 3;
        children.add(
          Padding(
            padding: EdgeInsets.only(left: nested ? 24 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: _knowledgeText(
                    ordered == null ? '•' : '${ordered.group(1)}.',
                    16,
                  ),
                ),
                Expanded(
                  child: _inline(ordered?.group(2) ?? bullet!.group(1)!),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      paragraph.add(text);
    }
    flush();
    flushCode();
    return _knowledgeStack(children, spacing: 12);
  }

  static final tokens = RegExp(
    r'(\*\*.+?\*\*|`.+?`|\*[^*].*?\*|\[article:[^\]]+\]|\[setting:[^\]]+\]|\[button-defender:[^\]]+\]|\[[^\]]+\]\([^)]+\)|https?://[^\s]+)',
  );
  Widget _inline(String text) {
    final widgets = <Widget>[];
    var cursor = 0;
    void words(
      String value, {
      Color color = _knowledgeMuted,
      FontWeight weight = FontWeight.w400,
      bool italic = false,
    }) {
      for (final word in RegExp(r'\S+\s*|\s+').allMatches(value)) {
        widgets.add(
          Text(
            word.group(0)!,
            style: zenithText(
              16,
              color: color,
              weight: weight,
              height: 1.48,
            ).copyWith(fontStyle: italic ? FontStyle.italic : FontStyle.normal),
          ),
        );
      }
    }

    for (final match in tokens.allMatches(text)) {
      if (match.start > cursor) words(text.substring(cursor, match.start));
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        words(
          token.substring(2, token.length - 2),
          color: _knowledgeSecondary,
          weight: FontWeight.w600,
        );
      } else if (token.startsWith('`')) {
        widgets.add(
          _knowledgeFrame(
            _knowledgeText(
              token.substring(1, token.length - 1),
              13,
              color: _knowledgeWarning,
              mono: true,
            ),
            radius: 4,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          ),
        );
      } else if (token.startsWith('*')) {
        words(token.substring(1, token.length - 1), italic: true);
      } else if (token.startsWith('[article:')) {
        final title = token.substring(9, token.length - 1);
        widgets.add(_knowledgeLink(title, () => _articleNamed(title)));
      } else if (token.startsWith('[setting:')) {
        final key = token.substring(9, token.length - 1);
        widgets.add(
          _knowledgeLink(
            _settingPaths[key] ?? key,
            () => widget.onOpenSettings?.call(),
          ),
        );
      } else if (token.startsWith('[button-defender:')) {
        widgets.add(
          _knowledgeText(
            token.substring(17, token.length - 1),
            16,
            color: _knowledgeInfoColor,
          ),
        );
      } else {
        final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(token);
        final label = link?.group(1) ?? token;
        final uri =
            link?.group(2) ?? token.replaceFirst(RegExp(r'[.,)]+$'), '');
        widgets.add(
          _knowledgeLink(
            label,
            () => _openExternal(uri.contains('://') ? uri : 'https://$uri'),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) words(text.substring(cursor));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }

  Future<void> _openExternal(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    try {
      await DesktopLauncher.openUrl(uri);
    } on Object {
      /* Keep local knowledge views available when no browser is configured. */
    }
  }

  static const _settingPaths = {
    'enableAutoExec': 'Settings → Execution Settings → Enable Auto Execute',
    'createLocalScript': 'Settings → Execution Settings → Create LocalScript',
    'errorSpoofing':
        'Settings → Execution Settings → Error Spoofing/Redirection',
    'unlockFPS': 'Settings → Execution Settings → Unlock FPS',
    'fpsCapValue': 'Settings → Execution Settings → FPS Cap',
    'internalInterface': 'Settings → Execution Settings → Internal Interface',
    'internalKeybind': 'Settings → Execution Settings → Internal Key-bind',
    'multiInstance': 'Settings → Execution Settings → Enable Multi-instance',
    'autoAttach': 'Settings → Other Settings → Auto-Attach',
    'autoAttachDelay': 'Settings → Other Settings → Auto-Attach Delay',
    'skipVersionCheck': 'Settings → Other Settings → Skip Version Check',
    'skipValidation': 'Settings → Other Settings → Skip Validation',
    'alwaysOnTop': 'Settings → Interface Settings → Always on Top',
    'navigationSlideOut':
        'Settings → Interface Settings → Navigation Slide-Out',
    'statusGlow': 'Settings → Interface Settings → Status Indicator Glow',
    'formatOnPaste': 'Settings → Interface Settings → Format Code on Paste',
    'swapAttachExecute':
        'Settings → Interface Settings → Swap Attach & Execute Buttons',
    'hideOpenButton': 'Settings → Interface Settings → Hide Open Button',
    'hideSaveButton': 'Settings → Interface Settings → Hide Save Button',
    'hideClearButton': 'Settings → Interface Settings → Hide Clear Button',
    'hideOutputConsole': 'Settings → Interface Settings → Hide Output Console',
    'showEditorHints': 'Settings → Interface Settings → Show Editor Hints',
    'theme': 'Settings → Interface Settings → Theme',
  };
}

String _helpSearchText(String text) => text
    .replaceAll(RegExp(r'```[\s\S]*?```'), '')
    .replaceAll(RegExp(r'\[setting:[^\]]+\]'), '')
    .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
    .replaceAll(RegExp(r'[*`#]'), '');
String _helpExcerpt(String text, int maximum) {
  final paragraphs = text.split('\n\n');
  var candidate = '';
  for (final p in paragraphs) {
    if (p.trim().isNotEmpty && !p.trim().startsWith('#')) {
      candidate = p.trim();
      break;
    }
  }
  candidate = candidate
      .replaceAll(RegExp(r'\[(?:setting|article):[^\]]+\]'), '')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
      .replaceAll(RegExp(r'[*`]'), '')
      .trim();
  return candidate.length > maximum
      ? candidate.substring(0, maximum).trimRight()
      : candidate;
}
