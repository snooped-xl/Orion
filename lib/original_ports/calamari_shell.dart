import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/bridge_client_manager.dart';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/interface_preset.dart';
import '../services/desktop_close_service.dart';
import '../services/monaco_editor_service.dart';
import '../services/desktop_launcher.dart';
import '../state/orion_controller.dart';
import 'calamari_controls.dart';

/// Local Calamari-M login, executor, and Tools & Tricks preservation frontend.
/// Its original editor is a plain Arial text box, rather than Monaco.
class CalamariShell extends StatefulWidget {
  const CalamariShell({
    super.key,
    required this.controller,
    required this.nativeWindow,
    required this.onBackToOrion,
    this.editorService,
    this.onSelectInterface,
    this.bridgeReady = false,
  });
  final OrionController controller;
  final bool nativeWindow, bridgeReady;
  final VoidCallback onBackToOrion;
  final MonacoEditorService? editorService;
  final Future<void> Function(InterfacePreset)? onSelectInterface;
  @override
  State<CalamariShell> createState() => CalamariShellState();
}

class CalamariShellState extends State<CalamariShell> with WindowListener {
  static const _presets = {
    'Dex by Moon': 'DexRaw',
    'Save Place': 'PlaceSaver',
    'RemoteSpy-M': 'CalamariRemoteSpy',
    'Infinite Yield': 'InfiniteYiff',
    'ESP': 'ESP',
    'Internal UI': 'Internal',
    'Enable Fly': 'fly',
    'Enable Noclip': 'noclip',
    'Click to TP': 'ClickTP',
    'c00lgui': 'c00lgui',
    'RoXploit 6.0': 'RoXploit',
    'TopK3k': 'TopK3k',
    'FE Animation GUI': 'FEAnimations',
    'Headspin': 'headspin',
    'Dex v4': 'Dex',
    'Lustris Sword': 'LustrisSword',
    'True Hero Ultima': 'TrueHeroUltima',
    'Double Tails Music': 'DoubleMusicTails',
    'God Claws': 'GodClaws',
    'Starglitcher': 'Starglitcher',
    'Wings Script': 'Wings',
  };
  static const _extraFiles = ['FPSUnlocker', 'trial'];
  final _editor = TextEditingController(),
      _outputText = TextEditingController(
        text: 'please execute the Orion Bridge in your executor.',
      ),
      _username = TextEditingController(),
      _password = TextEditingController(),
      _number = TextEditingController(text: '150'),
      _find = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Calamari editor');
  final _horizontalEditor = ScrollController();
  bool _login = true,
      _tools = false,
      _syncing = false,
      _showFind = false,
      _closing = false;
  String _documentId = '';
  Color _outputColor = const Color(0xffbe4039);
  OrionController get c => widget.controller;
  Map<String, Object?> get preferences =>
      c.getInterfacePreferences(InterfacePreset.calamari);
  @override
  void initState() {
    super.initState();
    // No username/password is persisted: the source accepts blank fields locally.
    _login = preferences['localLoginCompleted'] != true;
    _number.text = preferences['numberValue'] is String
        ? preferences['numberValue'] as String
        : '150';
    _sync();
    _editor.addListener(_edited);
    c.addListener(_sync);
    widget.editorService?.setActive(false);
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
  }

  @override
  void dispose() {
    c.removeListener(_sync);
    _editor.removeListener(_edited);
    if (widget.nativeWindow) windowManager.removeListener(this);
    _editor.dispose();
    _outputText.dispose();
    _username.dispose();
    _password.dispose();
    _number.dispose();
    _find.dispose();
    _focus.dispose();
    _horizontalEditor.dispose();
    super.dispose();
  }

  void _sync() {
    final d = c.activeDocument;
    if (d.id != _documentId || d.content != _editor.text) {
      final changed = d.id != _documentId;
      _documentId = d.id;
      _syncing = true;
      _editor.value = TextEditingValue(
        text: d.content,
        selection: TextSelection.collapsed(
          offset: changed
              ? 0
              : _editor.selection.baseOffset.clamp(0, d.content.length),
        ),
      );
      _syncing = false;
    }
    if (mounted) setState(() {});
  }

  void _edited() {
    if (!_syncing) c.updateDocumentContent(_documentId, _editor.text);
  }

  Future<void> flushEditor() async {
    /* This source editor synchronizes on every edit. */
  }
  void setEditorObscured(bool value, {String owner = 'route'}) =>
      widget.editorService?.setObscured(value, owner: owner);
  void setEditorTransitioning(bool value) =>
      widget.editorService?.setTransitioning(value);
  void handleEditorShortcut(String name) {
    switch (name) {
      case 'show-editor':
        setState(() => _tools = false);
        break;
      case 'new':
        c.newDocument();
        break;
      case 'open':
        unawaited(c.openFile());
        break;
      case 'save':
        unawaited(c.saveDocument());
        break;
      case 'saveAs':
        unawaited(c.saveAs());
        break;
      case 'execute':
        _execute(_editor.text, 'editor script');
        break;
      case 'find':
        setState(() => _showFind = true);
        break;
    }
  }

  void requestFind() => handleEditorShortcut('find');
  void _setOutput(String text, {Color color = const Color(0xffbe4039)}) {
    if (mounted) {
      setState(() {
        _outputText.text = text;
        _outputColor = color;
      });
    }
  }

  void _execute(String source, String label) {
    if (!widget.bridgeReady) {
      _setOutput('please execute the Orion Bridge in your executor.');
      return;
    }
    if (source.trim().isEmpty) {
      _setOutput('Nothing to execute.');
      return;
    }
    c.executeSource(source, name: label);
    if (c.bridgeTargetCount == 0) {
      _setOutput('No clients selected. Open Clients to choose a target.');
      return;
    }
    _setOutput(
      'Queued $label for ${c.bridgeTargetCount} ${c.bridgeTargetCount == 1 ? 'client' : 'clients'}.',
      color: const Color(0xff398849),
    );
  }

  Future<void> _preset(String label) async {
    if (!widget.bridgeReady) {
      _setOutput('please execute the Orion Bridge in your executor.');
      return;
    }
    try {
      final source = label == 'Give Btools'
          ? '''local backpack = game:GetService("Players").LocalPlayer.Backpack
for _, binType in ipairs({1, 4, 3}) do
    local tool = Instance.new("HopperBin")
    tool.BinType = binType
    tool.Parent = backpack
end'''
          : await rootBundle.loadString(
              'assets/original_calamari/scripts/${_presets[label]}.lua',
            );
      if (mounted) _execute(source, label);
    } catch (e) {
      _setOutput('Could not read $label: $e');
    }
  }

  void _numeric(String action) {
    final value = double.tryParse(_number.text);
    if (value == null || !value.isFinite) {
      _setOutput('Enter a valid number first.');
      return;
    }
    c.setInterfacePreference(
      InterfacePreset.calamari,
      'numberValue',
      _number.text,
    );
    // .NET's invariant round-trip format omits a redundant fractional zero.
    final literal = value.toString().replaceFirst(RegExp(r'\.0(?=$|[eE])'), '');
    final source = switch (action) {
      'walkspeed' =>
        "game:GetService('Players').LocalPlayer.Character.Humanoid.WalkSpeed=$literal",
      'jumppower' =>
        "game:GetService('Players').LocalPlayer.Character.Humanoid.JumpHeight=$literal; game:GetService('Players').LocalPlayer.Character.Humanoid.JumpPower=$literal",
      'hipheight' =>
        "game:GetService('Players').LocalPlayer.Character.Humanoid.HipHeight=$literal",
      _ => 'workspace.Gravity=$literal',
    };
    _execute(source, 'LocalPlayer action');
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      _editor.value = TextEditingValue(
        text: data?.text ?? '',
        selection: TextSelection.collapsed(offset: data?.text?.length ?? 0),
      );
      _focus.requestFocus();
    } catch (_) {
      _setOutput('Clipboard access is currently unavailable.');
    }
  }

  void _loginLocally() {
    _password.clear();
    c.setInterfacePreference(
      InterfacePreset.calamari,
      'localLoginCompleted',
      true,
    );
    setState(() {
      _login = false;
      _tools = false;
      _outputText.text = 'please execute the Orion Bridge in your executor.';
      _outputColor = const Color(0xffbe4039);
    });
  }

  Future<void> _openSaves() async {
    final directory = Directory('${c.scriptsDirectory.path}/Calamari Defaults');
    try {
      await directory.create(recursive: true);
      for (final name in {..._presets.values, ..._extraFiles}) {
        final file = File('${directory.path}/$name.lua');
        if (!await file.exists()) {
          await file.writeAsString(
            await rootBundle.loadString(
              'assets/original_calamari/scripts/$name.lua',
            ),
          );
        }
      }
      if (widget.nativeWindow) {
        await DesktopLauncher.openDirectory(directory);
      }
    } catch (e) {
      _setOutput('Could not open saves: $e');
    }
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await DesktopCloseService.closeApp(
        controller: c,
        nativeWindow: widget.nativeWindow,
      );
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      brightness: Brightness.light,
      fontFamily: 'OriginalArial',
      splashFactory: NoSplash.splashFactory,
      colorScheme: const ColorScheme.light(
        surface: CalamariSource.window,
        primary: Color(0xff1688e7),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        selectionColor: Color(0xffb8d9f5),
        cursorColor: Color(0xff111111),
      ),
    ),
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            unawaited(c.openFile()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(c.saveDocument()),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            requestFind,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.transparent,
          child: LayoutBuilder(
            builder: (context, box) {
              final width = math.max(521.0, box.maxWidth),
                  height = math.max(365.0, box.maxHeight);
              final content = _window(Size(width, height));
              if (box.maxWidth >= 521 && box.maxHeight >= 365) return content;
              return FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                child: SizedBox(width: 521, height: 365, child: content),
              );
            },
          ),
        ),
      ),
    ),
  );
  Widget _window(Size size) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xffb6b6b6)),
      color: CalamariSource.title,
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(0, 6),
          blurRadius: 18,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        children: [
          Positioned(left: 1, right: 1, top: 1, height: 28, child: _titlebar()),
          Positioned(
            left: 1,
            right: 1,
            top: 29,
            bottom: 1,
            child: _login ? _loginPage() : _main(),
          ),
        ],
      ),
    ),
  );
  Widget _titlebar() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xfff7f7f7), Color(0xffeaeaea), Color(0xffd1d1d1)],
        stops: [0, .45, 1],
      ),
      border: Border(bottom: BorderSide(color: Color(0xffafafaf))),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.nativeWindow
                ? (_) => windowManager.startDragging()
                : null,
          ),
        ),
        Positioned(
          left: 8,
          top: 4,
          width: 56,
          height: 18,
          child: Row(
            children: [
              _light(
                const Color(0xffe5e5e5),
                const Color(0xffbdbdbd),
                widget.onBackToOrion,
                'Back to Orion',
              ),
              const SizedBox(width: 1),
              _light(
                const Color(0xffffbd2e),
                const Color(0xffd9a326),
                () => widget.nativeWindow ? windowManager.minimize() : null,
                'Minimize',
              ),
              const SizedBox(width: 1),
              _light(
                const Color(0xffe5e5e5),
                const Color(0xffbdbdbd),
                null,
                'Full screen is unavailable',
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Text(
                'Calamari',
                style: CalamariSource.type(13, color: const Color(0xff4d4d4d)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _light(
    Color fill,
    Color border,
    VoidCallback? action,
    String tooltip,
  ) => SizedBox(
    width: 18,
    height: 18,
    child: CalamariButton(
      '',
      link: true,
      tooltip: tooltip,
      onPressed: action,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: border),
        ),
      ),
    ),
  );
  Widget _canvas(Widget child) => OverflowBox(
    alignment: Alignment.center,
    minWidth: 521,
    maxWidth: 521,
    minHeight: 337,
    maxHeight: 337,
    child: SizedBox(width: 521, height: 337, child: child),
  );
  Widget _loginPage() => _canvas(
    Stack(
      children: [
        const Positioned(
          left: 1,
          top: 1,
          width: 275,
          height: 335,
          child: ColoredBox(color: Colors.white),
        ),
        _label(
          'Calamari-M is updated',
          1,
          25,
          width: 275,
          size: 16,
          color: const Color(0xffa000a0),
          center: true,
          // The native source resolves its DemiBold Arial request to the normal
          // Linux face. Keep the measured source glyph width rather than synthesize.
          weight: FontWeight.normal,
        ),
        Positioned(
          left: 29,
          top: 68,
          width: 222,
          height: 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/original_calamari/showcase.jpg',
                    fit: BoxFit.fill,
                  ),
                ),
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x29000000)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 22,
                  child: Text(
                    'How to make:Cri...',
                    textAlign: TextAlign.center,
                    style: CalamariSource.type(16, color: Colors.white),
                  ),
                ),
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xc74e453b),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Center(
                        child: Text(
                          '▶',
                          style: CalamariSource.type(27, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _label(
          "Watch cutedoot's showcase",
          1,
          222,
          width: 275,
          size: 16,
          center: true,
        ),
        const Positioned(
          left: 9,
          top: 248,
          width: 259,
          height: 1,
          child: ColoredBox(color: Color(0xff999999)),
        ),
        Positioned(
          left: 1,
          top: 258,
          width: 275,
          height: 18,
          child: CalamariButton(
            'Click here to buy this',
            link: true,
            size: 15,
            onPressed: () {},
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CalamariLinkIcon(),
                const SizedBox(width: 3),
                Text(
                  'Click here to buy this',
                  style: CalamariSource.type(
                    15,
                    color: const Color(0xff0000ee),
                  ).copyWith(decoration: TextDecoration.underline),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 1,
          top: 276,
          width: 275,
          height: 18,
          child: CalamariButton(
            'Click to Join the Discord',
            link: true,
            size: 15,
            onPressed: () {},
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CalamariLinkIcon(group: true),
                const SizedBox(width: 3),
                Text(
                  'Click to Join the Discord',
                  style: CalamariSource.type(
                    15,
                    color: const Color(0xff0000ee),
                  ).copyWith(decoration: TextDecoration.underline),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 343,
          top: 42,
          width: 100,
          height: 100,
          child: Image.asset(
            'assets/original_calamari/AppLogo.png',
            fit: BoxFit.contain,
          ),
        ),
        Positioned(
          left: 283,
          top: 172,
          width: 236,
          height: 32,
          child: CalamariInput(
            key: const ValueKey('calamari-username'),
            controller: _username,
            hint: 'Username...',
          ),
        ),
        Positioned(
          left: 283,
          top: 199,
          width: 236,
          height: 32,
          child: CalamariInput(
            key: const ValueKey('calamari-password'),
            controller: _password,
            hint: 'Password...',
            obscure: true,
          ),
        ),
        Positioned(
          left: 283,
          top: 227,
          width: 236,
          height: 23,
          child: CalamariButton(
            'Login',
            key: const ValueKey('calamari-login'),
            border: const Color(0xffb8b8b8),
            onPressed: _loginLocally,
          ),
        ),
        _label(
          '© 2020 Inspect',
          283,
          323,
          size: 14,
          color: const Color(0xff333333),
        ),
      ],
    ),
  );
  Widget _main() => ColoredBox(
    color: CalamariSource.window,
    child: _canvas(
      Stack(
        children: [
          Positioned(
            left: 173,
            top: 4,
            width: 78,
            height: 23,
            child: CalamariButton(
              'Executor',
              key: const ValueKey('calamari-executor-tab'),
              selected: !_tools,
              radius: 4,
              border: const Color(0xffb7b7b7),
              onPressed: () => setState(() => _tools = false),
            ),
          ),
          Positioned(
            left: 251,
            top: 4,
            width: 110,
            height: 23,
            child: CalamariButton(
              'Tools & Tricks',
              key: const ValueKey('calamari-tools-tab'),
              selected: _tools,
              radius: 4,
              border: const Color(0xffb7b7b7),
              onPressed: () => setState(() => _tools = true),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 30,
            bottom: 0,
            // The source toggles IsVisible on two existing canvases. Preserve
            // the editor's selection, scrolling and undo state across tabs.
            child: IndexedStack(
              index: _tools ? 1 : 0,
              children: [
                ExcludeFocus(excluding: _tools, child: _executorPage()),
                ExcludeFocus(excluding: !_tools, child: _toolsPage()),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _executorPage() => Stack(
    children: [
      Positioned(left: 5, top: 5, width: 353, height: 207, child: _textArea()),
      Positioned(
        left: 7,
        top: 220,
        width: 25,
        height: 28,
        child: CalamariButton(
          '',
          key: const ValueKey('calamari-execute'),
          radius: 4,
          onPressed: () => _execute(_editor.text, 'editor script'),
          tooltip: 'Execute',
          child: Image.asset(
            'assets/original_calamari/play.png',
            width: 20,
            height: 20,
          ),
        ),
      ),
      Positioned(
        left: 7,
        top: 251,
        width: 25,
        height: 28,
        child: CalamariButton(
          '',
          key: const ValueKey('calamari-paste'),
          radius: 4,
          onPressed: () => unawaited(_paste()),
          tooltip: 'Paste clipboard',
          child: Image.asset(
            'assets/original_calamari/clipboard.png',
            width: 20,
            height: 20,
          ),
        ),
      ),
      Positioned(
        left: 8,
        top: 286,
        width: 22,
        height: 22,
        child: Image.asset(
          'assets/original_calamari/AppLogo.png',
          fit: BoxFit.contain,
        ),
      ),
      Positioned(
        left: 40,
        top: 220,
        width: 322,
        height: 85,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xffc8c8c8)),
          ),
          child: TextField(
            key: const ValueKey('calamari-output'),
            controller: _outputText,
            readOnly: true,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: CalamariSource.type(13, color: _outputColor),
            cursorColor: const Color(0xff111111),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.all(4),
            ),
          ),
        ),
      ),
      _label('Calamari-M - Selects', 374, 4, size: 14),
      _panel(369, 21, 145, 250),
      Positioned(
        left: 376,
        top: 27,
        width: 130,
        child: Column(
          children: [
            _presetButton('Dex by Moon'),
            const SizedBox(height: 4),
            _presetButton('Save Place'),
            _divider(),
            _presetButton('RemoteSpy-M'),
            const SizedBox(height: 4),
            _presetButton('Infinite Yield'),
            _divider(),
            _presetButton('ESP'),
            const SizedBox(height: 4),
            _presetButton('Internal UI'),
            _divider(),
            SizedBox(
              height: 23,
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerLeft,
                child: IntrinsicWidth(
                  child: CalamariButton(
                    'Open Saves',
                    onPressed: () => unawaited(_openSaves()),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('📁', style: CalamariSource.type(14)),
                        const SizedBox(width: 4),
                        Text('Open Saves', style: CalamariSource.type(14)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Positioned(
        left: 369,
        top: 282,
        width: 119,
        height: 23,
        child: CalamariButton(
          'Attach Calamari',
          key: const ValueKey('calamari-attach'),
          onPressed: () => unawaited(
            showBridgeClientManager(
              context,
              controller: c,
              editorService: widget.editorService,
            ),
          ),
        ),
      ),
      Positioned(
        left: 493,
        top: 282,
        width: 23,
        height: 23,
        child: CalamariButton(
          '',
          key: const ValueKey('calamari-clients'),
          tooltip: 'Client manager',
          onPressed: () => unawaited(
            showBridgeClientManager(
              context,
              controller: c,
              editorService: widget.editorService,
            ),
          ),
          child: const Icon(
            Icons.devices_rounded,
            size: 14,
            color: Color(0xff222222),
          ),
        ),
      ),
    ],
  );
  Widget _textArea() => DecoratedBox(
    key: const ValueKey('calamari-editor-viewport'),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffc8c8c8)),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) {
              final text = TextPainter(
                text: TextSpan(
                  text: _editor.text,
                  style: CalamariSource.type(13),
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              final width = math.max(
                box.maxWidth,
                text.width.ceilToDouble() + 8,
              );
              return SingleChildScrollView(
                controller: _horizontalEditor,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: box.maxHeight,
                  child: TextField(
                    key: const ValueKey('code-editor'),
                    controller: _editor,
                    focusNode: _focus,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: CalamariSource.type(13),
                    cursorColor: const Color(0xff111111),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.all(4),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_showFind)
          Positioned(
            top: 0,
            right: 0,
            width: 220,
            height: 24,
            child: ColoredBox(
              color: const Color(0xffececec),
              child: Row(
                children: [
                  Expanded(
                    child: CalamariInput(
                      controller: _find,
                      hint: 'Find',
                      rounded: false,
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    child: CalamariButton('↓', onPressed: _findNext),
                  ),
                  SizedBox(
                    width: 24,
                    child: CalamariButton(
                      '×',
                      onPressed: () => setState(() => _showFind = false),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  void _findNext() {
    final term = _find.text;
    if (term.isEmpty) return;
    final after = _editor.text.indexOf(
      term,
      math.max(0, _editor.selection.end),
    );
    final start = after >= 0 ? after : _editor.text.indexOf(term);
    if (start >= 0) {
      _editor.selection = TextSelection(
        baseOffset: start,
        extentOffset: start + term.length,
      );
      _focus.requestFocus();
    }
  }

  Widget _toolsPage() => Stack(
    children: [
      _label('LocalPlayer', 14, 7, size: 11, color: const Color(0xff222222)),
      _panel(8, 19, 217, 282),
      _label('Number Value:', 14, 40, size: 14),
      Positioned(
        left: 109,
        top: 27,
        width: 105,
        height: 32,
        child: CalamariInput(
          key: const ValueKey('calamari-number'),
          controller: _number,
          rounded: false,
        ),
      ),
      const Positioned(
        left: 14,
        top: 58,
        width: 205,
        height: 1,
        child: ColoredBox(color: Color(0xffc6c6c6)),
      ),
      Positioned(
        left: 14,
        top: 66,
        width: 205,
        child: Column(
          children: [
            _numericRow(
              'Set WalkSpeed',
              'walkspeed',
              "game:GetService('Players').LocalPlayer.Character.Humanoid.WalkSpeed=16",
            ),
            const SizedBox(height: 4),
            _numericRow(
              'Set JumpPower',
              'jumppower',
              "game:GetService('Players').LocalPlayer.Character.Humanoid.JumpHeight=7.2; game:GetService('Players').LocalPlayer.Character.Humanoid.JumpPower=50",
            ),
            const SizedBox(height: 4),
            _numericRow(
              'Set HipHeight',
              'hipheight',
              "game:GetService('Players').LocalPlayer.Character.Humanoid.HipHeight=1.998",
            ),
            const SizedBox(height: 4),
            _numericRow(
              'Set Gravity (Local)',
              'gravity',
              'workspace.Gravity=196.2',
            ),
            _divider(),
            _actionRow('Enable Fly', '_G.unfly()'),
            const SizedBox(height: 4),
            _actionRow('Enable Noclip', '_G.unnoclip()'),
            _divider(),
            _presetButton('Give Btools'),
            const SizedBox(height: 4),
            _presetButton('Click to TP'),
          ],
        ),
      ),
      _label('GUIs', 235, 7, size: 11, color: const Color(0xff222222)),
      _panel(229, 19, 145, 282),
      Positioned(
        left: 236,
        top: 61,
        width: 131,
        child: Column(
          children: [
            _presetButton('c00lgui'),
            const SizedBox(height: 4),
            _presetButton('RoXploit 6.0'),
            const SizedBox(height: 4),
            _presetButton('TopK3k'),
            const SizedBox(height: 4),
            _presetButton('FE Animation GUI'),
            _divider(),
            _presetButton('Headspin'),
            const SizedBox(height: 4),
            _presetButton('Dex v4'),
            _divider(),
            SizedBox(
              height: 23,
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _sourceButton(
                  'Back to Orion',
                  widget.onBackToOrion,
                  key: const ValueKey('calamari-back-to-orion'),
                ),
              ),
            ),
          ],
        ),
      ),
      _label('Classics', 385, 7, size: 11, color: const Color(0xff222222)),
      _panel(380, 19, 136, 282),
      Positioned(
        left: 387,
        top: 61,
        width: 122,
        child: Column(
          children: [
            _presetButton('Lustris Sword'),
            const SizedBox(height: 4),
            _presetButton('True Hero Ultima'),
            const SizedBox(height: 4),
            _presetButton('Double Tails Music'),
            const SizedBox(height: 4),
            _presetButton('God Claws'),
            _divider(),
            _presetButton('Starglitcher'),
            const SizedBox(height: 4),
            _presetButton('Wings Script'),
            const SizedBox(height: 2),
            Text(
              "NOTE: These tricks\nwon't be visible to\nothers. Use for tests.",
              style: CalamariSource.type(14),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _sourceButton(String label, VoidCallback action, {Key? key}) {
    final text = TextPainter(
      text: TextSpan(text: label, style: CalamariSource.type(14)),
      textDirection: TextDirection.ltr,
    )..layout();
    return SizedBox(
      width: text.width.ceilToDouble() + 2,
      height: 23,
      child: CalamariButton(label, key: key, onPressed: action),
    );
  }

  Widget _presetButton(String label) => SizedBox(
    height: 23,
    width: double.infinity,
    child: Align(
      alignment: Alignment.centerLeft,
      child: _sourceButton(label, () => unawaited(_preset(label))),
    ),
  );
  Widget _numericRow(String label, String action, String reset) => SizedBox(
    height: 23,
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _sourceButton(label, () => _numeric(action)),
          ),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 62,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _sourceButton('Reset', () => _execute(reset, 'action')),
          ),
        ),
      ],
    ),
  );
  Widget _actionRow(String label, String reset) => SizedBox(
    height: 23,
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _sourceButton(label, () => unawaited(_preset(label))),
          ),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 62,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _sourceButton('Reset', () => _execute(reset, 'action')),
          ),
        ),
      ],
    ),
  );
  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 6),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: Color(0xffc6c6c6)),
    ),
  );
  Widget _panel(double x, double y, double w, double h) => Positioned(
    left: x,
    top: y,
    width: w,
    height: h,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffeaeaea),
        border: Border.all(color: const Color(0xffe2e2e2)),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
  Widget _label(
    String label,
    double x,
    double y, {
    double? width,
    double size = 14,
    Color color = const Color(0xff111111),
    bool center = false,
    FontWeight weight = FontWeight.normal,
  }) => Positioned(
    left: x,
    top: y,
    width: width,
    child: Text(
      label,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: CalamariSource.type(size, color: color, weight: weight),
    ),
  );
}
