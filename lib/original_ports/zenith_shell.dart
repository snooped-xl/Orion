import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';

import '../widgets/bridge_client_manager.dart';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/interface_preset.dart';
import '../models/orion_models.dart';
import '../services/desktop_close_service.dart';
import '../services/monaco_editor_service.dart';
import '../services/native_window_service.dart';
import '../services/file_paths.dart';
import '../state/orion_controller.dart';
import '../widgets/monaco_editor.dart';
import 'zenith_ui.dart';
import 'zenith_pages.dart';

class ZenithShell extends StatefulWidget {
  const ZenithShell({
    super.key,
    required this.controller,
    required this.nativeWindow,
    required this.onBackToOrion,
    this.editorService,
    this.onSelectInterface,
    this.bridgeReady = false,
    this.pickScriptPath,
    this.pickSavePath,
  });
  final OrionController controller;
  final bool nativeWindow, bridgeReady;
  final Future<String?> Function()? pickScriptPath;
  final Future<String?> Function(String suggestedName)? pickSavePath;
  final MonacoEditorService? editorService;
  final VoidCallback onBackToOrion;
  final Future<void> Function(InterfacePreset)? onSelectInterface;
  @override
  State<ZenithShell> createState() => ZenithShellState();
}

class ZenithShellState extends State<ZenithShell>
    with TickerProviderStateMixin, WindowListener {
  final _editor = TextEditingController();
  final _username = TextEditingController(),
      _password = TextEditingController();
  final _editorFocus = FocusNode(), _passwordFocus = FocusNode();
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final _loadingFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Timer? _loadingTimer, _navTimer;
  bool _loading = true, _loggedIn = false, _visiblePassword = false;
  bool _expandedNav = false, _syncing = false, _closing = false;
  bool _fileListExpanded = true,
      _scriptsExpanded = false,
      _autoExecExpanded = false;
  bool _outputExpanded = true;
  bool _outputHint = true;
  double _outputHeight = 140, _editorStackHeight = 400;
  final Set<String> _clearedOutput = {}, _hoveredTabs = {};
  int _page = 0;
  final _visitedPages = <int>{0};
  int _settingsVisit = 0;
  String? _helpArticle;
  List<File> _scriptFiles = [], _autoFiles = [];
  String _documentId = '';
  OrionController get c => widget.controller;
  MonacoEditorService? get service => widget.editorService;
  Map<String, Object?> get preferences =>
      c.getInterfacePreferences(InterfacePreset.zenithV2);
  bool pref(String key, [bool fallback = false]) =>
      preferences[key] is bool ? preferences[key] as bool : fallback;
  bool get reduced =>
      c.reducedMotion || (mounted && MediaQuery.disableAnimationsOf(context));
  static const names = [
    'Home',
    'Execution',
    'Script Hub',
    'Documentation',
    'Help',
    'Settings',
  ];
  static const glyphs = [
    'Home',
    'Execution',
    'ScriptHub',
    'Documentation',
    'Help',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    service?.addListener(_nativeChanged);
    _editor.addListener(_edited);
    _entrance.addListener(_updateOpacity);
    _loadingFade.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _loading = false);
      }
    });
    _syncEditor();
    unawaited(refreshLocalFiles());
    _loadingTimer = Timer(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      if (c.reducedMotion) {
        setState(() => _loading = false);
      } else {
        _loadingFade.forward();
      }
    });
    _entrance.value = 1;
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
  }

  void _nativeChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    _syncEditor();
    setState(() {});
  }

  void _syncEditor() {
    final doc = c.activeDocument;
    if (_documentId != doc.id || _editor.text != doc.content) {
      _syncing = true;
      final offset = _documentId == doc.id
          ? _editor.selection.extentOffset.clamp(0, doc.content.length)
          : 0;
      _editor.value = TextEditingValue(
        text: doc.content,
        selection: TextSelection.collapsed(offset: offset),
      );
      _documentId = doc.id;
      _syncing = false;
    }
  }

  void _edited() {
    if (!_syncing) c.updateDocumentContent(_documentId, _editor.text);
  }

  void _updateOpacity() {
    final t = ((.65 * _entrance.value - .1) / .3).clamp(0.0, 1.0);
    service?.setOpacity(
      _page == 1 ? const Cubic(0, 0, .58, 1).transform(t) : 1,
      owner: 'original-zenith',
    );
  }

  Future<void> flushEditor() async {
    try {
      await service?.flush();
    } on Object {
      /* Preserve the latest received draft. */
    }
  }

  Directory get scriptsDirectory {
    final custom = preferences['scriptsDirectory'];
    if (custom is String && custom.isNotEmpty) return Directory(custom);
    return c.scriptsDirectory;
  }

  Future<void> refreshLocalFiles() async {
    Future<List<File>> files(Directory directory) async {
      if (!await directory.exists()) return [];
      final items = await directory
          .list()
          .where(
            (entry) =>
                entry is File &&
                RegExp(
                  r'\.(lua|luau|txt|md)$',
                  caseSensitive: false,
                ).hasMatch(entry.path),
          )
          .cast<File>()
          .toList();
      items.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      return items.take(18).toList();
    }

    try {
      final scriptFiles = await files(scriptsDirectory);
      final custom = preferences['scriptsDirectory'];
      final customAutoexec = Directory(
        '${scriptsDirectory.parent.path}/AutoExec',
      );
      final autoFiles = await files(
        custom is String && custom.isNotEmpty && await customAutoexec.exists()
            ? customAutoexec
            : c.autoexecuteDirectory,
      );
      if (mounted) {
        setState(() {
          _scriptFiles = scriptFiles;
          _autoFiles = autoFiles;
        });
      }
    } on FileSystemException {
      /* A missing folder stays empty. */
    }
  }

  Future<void> _openLocal(File file) async {
    await flushEditor();
    if (mounted) await c.importDocumentFromPath(file.path);
  }

  Future<void> _go(int page) async {
    if (page == _page && _loggedIn) return;
    await flushEditor();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _page = page;
      _visitedPages.add(page);
      if (page == 5) _settingsVisit++;
    });
    service?.setActive(_loggedIn && page == 1);
    if (reduced) {
      _entrance.value = 1;
    } else {
      _entrance.forward(from: 0);
    }
  }

  void _login() {
    _password.clear();
    setState(() {
      _loggedIn = true;
      _page = 0;
    });
    if (reduced) {
      _entrance.value = 1;
    } else {
      _entrance.forward(from: 0);
    }
  }

  Future<void> _file(bool save, {bool saveAs = false}) async {
    await flushEditor();
    if (!mounted) return;
    await service?.freezeForOverlay(owner: 'zenith-file');
    try {
      if (save) {
        final document = c.activeDocument;
        final suggested = document.name.contains('.')
            ? document.name
            : '${document.name}.lua';
        final path = widget.pickSavePath != null
            ? await widget.pickSavePath!(suggested)
            : (await files.getSaveLocation(
                suggestedName: suggested,
                initialDirectory: scriptsDirectory.path,
                confirmButtonText: 'Save script',
                acceptedTypeGroups: const [
                  files.XTypeGroup(label: 'Lua script', extensions: ['lua']),
                  files.XTypeGroup(label: 'Luau script', extensions: ['luau']),
                  files.XTypeGroup(label: 'Text file', extensions: ['txt']),
                ],
              ))?.path;
        if (path != null && mounted) {
          if (await c.saveDocumentToPath(document.id, path)) {
            c.renameDocument(document.id, document.name);
          }
        }
      } else {
        final path = widget.pickScriptPath != null
            ? await widget.pickScriptPath!()
            : (await files.openFile(
                confirmButtonText: 'Open script',
                acceptedTypeGroups: const [
                  files.XTypeGroup(
                    label: 'Script files',
                    extensions: ['lua', 'luau', 'txt', 'md', 'json'],
                  ),
                ],
              ))?.path;
        if (path != null && mounted) await c.importDocumentFromPath(path);
      }
    } finally {
      service?.setObscured(false, owner: 'zenith-file');
    }
  }

  Future<void> _closeTab(String id) async {
    await flushEditor();
    if (!mounted || c.documents.length <= 1) return;
    final index = c.documents.indexWhere((d) => d.id == id);
    if (index < 0) return;
    final previous = c.documents[math.max(0, index - 1)].id;
    final active = c.activeDocumentId == id;
    c.closeDocument(id);
    if (active && previous != id) c.selectDocument(previous);
  }

  String _tabTitle(EditorDocument document) => document.name.replaceFirst(
    RegExp(r'\.(lua|luau|txt|md|json)$', caseSensitive: false),
    '',
  );

  void _clearOutput() {
    setState(() {
      _outputHint = false;
      _clearedOutput.addAll(c.activities.map((line) => line.id));
    });
  }

  Future<void> _maximize() async {
    if (!widget.nativeWindow || !pref('resizable', true)) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  void handleEditorShortcut(String name) {
    switch (name) {
      case 'show-editor':
        unawaited(_go(1));
      case 'new':
        unawaited(
          flushEditor().then(
            (_) => c.newDocument(name: 'Tab ${c.documents.length + 1}'),
          ),
        );
      case 'open':
        unawaited(_file(false));
      case 'save':
        unawaited(_file(true));
      case 'saveAs':
      case 'save-as':
        unawaited(_file(true, saveAs: true));
      case 'console':
        setState(() => _outputExpanded = !_outputExpanded);
      case 'clear':
        c.updateDocumentContent(c.activeDocumentId, '');
      case 'find':
      case 'replace':
      case 'suggest':
        unawaited(service?.action(name) ?? Future<void>.value());
      case 'execute':
        if (widget.bridgeReady) c.execute();
      case 'palette':
        if (_page == 1) {
          unawaited(service?.action('commands') ?? Future<void>.value());
        }
      case 'close-tab':
        unawaited(_closeTab(c.activeDocumentId));
      case 'help':
        unawaited(_go(4));
    }
  }

  Future<void> requestFind() async {
    await service?.action('find');
  }

  @override
  void onWindowClose() {
    unawaited(_close());
  }

  Future<void> _close() async {
    if (_closing || !widget.nativeWindow) return;
    _closing = true;
    try {
      await DesktopCloseService.closeApp(
        controller: c,
        nativeWindow: widget.nativeWindow,
        flushEditor: flushEditor,
      );
    } finally {
      _closing = false;
    }
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _navTimer?.cancel();
    if (widget.nativeWindow) windowManager.removeListener(this);
    c.removeListener(_changed);
    service?.removeListener(_nativeChanged);
    service?.setOpacity(1, owner: 'original-zenith');
    _entrance.dispose();
    _loadingFade.dispose();
    _editor.dispose();
    _username.dispose();
    _password.dispose();
    _editorFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _syncNative() {
    service?.setActive(_loggedIn && _page == 1 && !_loading);
    unawaited(
      service?.synchronize({
            'documents': [
              for (final doc in c.documents)
                {'id': doc.id, 'name': doc.name, 'content': doc.content},
            ],
            'activeId': c.activeDocumentId,
            'options': {
              'shell': 'originalZenith',
              'brightness': 'dark',
              'animateReveal': false,
              'uiScale': c.uiScale,
              'reducedMotion': reduced,
              'fontSize': 14,
              'lineHeight': 20,
              'wordWrap': true,
              'lineNumbers': true,
              'background': '#0d0d0d',
              'foreground': '#d4d4d4',
              'accent': '#39a2ff',
              'muted': '#ffffff',
              'border': '#3a3b3c',
              'autocomplete': true,
              'showEditorHints': pref('showEditorHints', true),
              'formatOnPaste': pref('formatOnPaste', true),
            },
          }) ??
          Future<void>.value(),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncNative();
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: false,
        fontFamily: 'OriginalNunito',
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: zenithBackground,
        colorScheme: const ColorScheme.dark(
          surface: zenithBackground,
          primary: Color(0xff39a2ff),
        ),
        textTheme: TextTheme(bodyMedium: zenithText(14)),
        tooltipTheme: TooltipThemeData(textStyle: zenithText(12)),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
              handleEditorShortcut('open'),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              handleEditorShortcut('save'),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              handleEditorShortcut('new'),
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
              handleEditorShortcut('new'),
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
              handleEditorShortcut('close-tab'),
          const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
              handleEditorShortcut('palette'),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              handleEditorShortcut('palette'),
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Container(
            decoration: BoxDecoration(
              color: zenithBackground,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xff3a3b3c)),
            ),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Stack(
                children: [
                  if (pref('statusGlow', true))
                    Positioned(
                      left: -293,
                      top: -279,
                      width: 600,
                      height: 600,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: const [
                                Color(0x664e4d72),
                                Color(0x594e4d72),
                                Color(0x404e4d72),
                                Color(0x264e4d72),
                                Color(0x144e4d72),
                                Color(0x0a4e4d72),
                                Color(0x004e4d72),
                              ],
                              stops: const [0, .04, .1, .2, .33, .5, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Column(
                    children: [
                      _titleBar(),
                      Expanded(
                        child: _loggedIn
                            ? Row(
                                children: [
                                  _navigation(),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: _currentPage(),
                                    ),
                                  ),
                                ],
                              )
                            : _loginPage(),
                      ),
                    ],
                  ),
                  if (_loading)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _loadingFade,
                        builder: (_, _) => IgnorePointer(
                          ignoring: _loadingFade.isCompleted,
                          child: Opacity(
                            opacity:
                                1 -
                                Curves.easeOutCubic.transform(
                                  _loadingFade.value,
                                ),
                            child: ColoredBox(
                              color: zenithBackground,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox.square(
                                      dimension: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xffc0c0c0),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Initializing...',
                                      style: zenithText(
                                        15,
                                        color: const Color(0xff7f7f7f),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleBar() => Container(
    height: 42,
    key: const ValueKey('zenith-titlebar'),
    decoration: const BoxDecoration(
      color: zenithCard,
      border: Border(bottom: BorderSide(color: Color(0xff3a3b3c))),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              if (widget.nativeWindow) unawaited(windowManager.startDragging());
            },
            onDoubleTap: () => unawaited(_maximize()),
          ),
        ),
        Positioned(
          left: 12,
          top: 0,
          bottom: 0,
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.bridgeConnected
                      ? const Color(0xff63d8a4)
                      : const Color(0xff4e4d72),
                  boxShadow: [
                    BoxShadow(color: Color(0x664e4d72), blurRadius: 12),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                c.bridgeConnected
                    ? '${c.bridgeClients.length} connected'
                    : 'Inactive',
                style: zenithText(
                  16,
                  weight: FontWeight.w500,
                  color: const Color(0xff9a9a9a),
                ),
              ),
            ],
          ),
        ),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Zenith',
                style: zenithText(
                  18,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) => const LinearGradient(
                  colors: [
                    Color(0xff667eea),
                    Color(0xff9c66ff),
                    Color(0xffff6b96),
                    Color(0xffffa87a),
                    Color(0xff667eea),
                  ],
                ).createShader(rect),
                child: Text(
                  'V2',
                  style: zenithText(
                    18,
                    color: Colors.white,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: Row(
            children: [
              _chrome('Minimize', () {
                if (widget.nativeWindow) unawaited(windowManager.minimize());
              }),
              const SizedBox(width: 12),
              _chrome('Maximize', () => unawaited(_maximize())),
              const SizedBox(width: 12),
              _chrome('Close', () => unawaited(_close())),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _chrome(String glyph, VoidCallback press) => Tooltip(
    message: glyph,
    child: ZenithButton(
      '',
      icon: glyph,
      chrome: true,
      iconSize: glyph == 'Close' ? 26 : 24,
      color: const Color(0xff7a7a7a),
      width: glyph == 'Close' ? 26 : 24,
      height: 26,
      background: Colors.transparent,
      padding: EdgeInsets.zero,
      onPressed: press,
    ),
  );

  Widget _loginPage() => Padding(
    padding: const EdgeInsets.all(12),
    child: zenithPanel(
      Center(
        child: SizedBox(
          width: 216,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Login', style: zenithText(18, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              _loginInput(
                _username,
                'Username',
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  _loginInput(
                    _password,
                    '••••phrase',
                    password: true,
                    onSubmitted: (_) => _login(),
                  ),
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 0,
                    child: ZenithButton(
                      '',
                      icon: _visiblePassword ? 'LoginEye' : 'LoginEyeOff',
                      chrome: true,
                      color: const Color(0xff9a9a9a),
                      iconStroke: true,
                      width: 32,
                      height: 38,
                      background: Colors.transparent,
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          setState(() => _visiblePassword = !_visiblePassword),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ZenithButton(
                'Login',
                key: const ValueKey('zenith-login'),
                icon: 'LoginUser',
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(8),
                width: 216,
                height: 38,
                fontSize: 16,
                background: const Color(0x1a626262),
                hoverBackground: const Color(0x25626262),
                pressedBackground: const Color(0x2a626262),
                onPressed: _login,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _loginInput(
    TextEditingController controller,
    String hint, {
    bool password = false,
    ValueChanged<String>? onSubmitted,
  }) => SizedBox(
    height: 38,
    child: TextField(
      controller: controller,
      focusNode: password ? _passwordFocus : null,
      obscureText: password && !_visiblePassword,
      cursorColor: const Color(0xbfffffff),
      obscuringCharacter: '●',
      onSubmitted: onSubmitted,
      style: zenithText(16, color: const Color(0xffdedede)),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: zenithText(16, color: const Color(0xff777777)),
        filled: true,
        fillColor: const Color(0x0c626262),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0x1fdedede)),
        ),
      ),
    ),
  );

  Widget _navigation() => MouseRegion(
    onEnter: (_) {
      _navTimer?.cancel();
      if (pref('navigationSlideOut', true)) setState(() => _expandedNav = true);
    },
    onExit: (_) {
      _navTimer?.cancel();
      _navTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _expandedNav = false);
      });
    },
    child: AnimatedContainer(
      key: const ValueKey('zenith-navigation'),
      width: _expandedNav ? 200 : 56,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 300),
      curve: zenithCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: zenithCard),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var i = 0; i < 4; i++) ...[_nav(i), const SizedBox(height: 8)],
          const Spacer(),
          _nav(4),
          const SizedBox(height: 8),
          _nav(5),
        ],
      ),
    ),
  );
  Widget _nav(int index) => SizedBox(
    height: 40,
    child: InkWell(
      key: ValueKey('zenith-nav-$index'),
      onTap: () => unawaited(_go(index)),
      borderRadius: BorderRadius.circular(8),
      hoverColor: const Color(0x0affffff),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 184,
          maxWidth: 184,
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      opacity: _page == index ? 1 : 0,
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          height: _page == index ? 40 : 20,
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          curve: zenithCurve,
                          child: Container(
                            width: 3,
                            height: 40,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xff3b82f6), Color(0xff2563eb)],
                              ),
                              borderRadius: BorderRadius.horizontal(
                                left: Radius.circular(20),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ZenithGlyph(glyphs[index]),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: AnimatedOpacity(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: zenithCurve,
                  opacity: _expandedNav ? 1 : 0,
                  child: Text(
                    names[index],
                    style: zenithText(
                      16,
                      color: zenithMuted,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _currentPage() => IndexedStack(
    index: _page,
    children: [
      for (var page = 0; page < names.length; page++)
        if (_visitedPages.contains(page))
          _pageView(page)
        else
          const SizedBox.shrink(),
    ],
  );
  Widget _pageView(int page) => switch (page) {
    0 => ZenithHome(animation: _entrance),
    1 => _execution(),
    2 => ZenithHub(
      controller: c,
      animation: _entrance,
      onOpen: (script) async {
        await flushEditor();
        await c.openRemoteScript(script);
        if (mounted) unawaited(_go(1));
      },
      bridgeReady: widget.bridgeReady,
    ),
    3 => ZenithDocumentation(
      animation: _entrance,
      onVisitHelp: (title) {
        _helpArticle = title;
        unawaited(_go(4));
      },
    ),
    4 => ZenithHelp(
      animation: _entrance,
      initialArticle: _helpArticle,
      onOpenSettings: () => unawaited(_go(5)),
    ),
    _ => ZenithSettings(
      key: ValueKey('zenith-settings-$_settingsVisit'),
      controller: c,
      animation: _entrance,
      onBack: widget.onBackToOrion,
      onPreference: _setPreference,
      onTutorial: () => unawaited(_go(1)),
    ),
  };
  void _setPreference(String name, Object? value) {
    c.setInterfacePreference(InterfacePreset.zenithV2, name, value);
    if (widget.nativeWindow && name == 'alwaysOnTop') {
      unawaited(NativeWindowService.setAlwaysOnTop(value == true));
    }
    if (widget.nativeWindow && name == 'resizable') {
      unawaited(NativeWindowService.setResizable(value == true));
    }
  }

  Widget _execution() => Column(
    children: [
      ZenithFade(
        animation: _entrance,
        duration: .2,
        offset: 3,
        css: true,
        child: _tabs(),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ZenithFade(
          animation: _entrance,
          delay: .1,
          duration: .3,
          css: true,
          child: LayoutBuilder(
            builder: (_, box) {
              _editorStackHeight = box.maxHeight;
              final fileWidth = _fileListExpanded ? 200.0 : 30.0;
              final outputHeight = pref('hideOutputConsole')
                  ? 0.0
                  : _outputExpanded
                  ? math.min(_outputHeight, math.max(80.0, box.maxHeight * .65))
                  : 32.0;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: zenithPanel(
                            _code(),
                            key: const ValueKey('zenith-editor-body'),
                            radius: 12,
                            color: const Color(0xff0d0d0d),
                            padding: const EdgeInsets.all(4),
                          ),
                        ),
                        if (outputHeight > 0) ...[
                          const SizedBox(height: 8),
                          SizedBox(height: outputHeight, child: _output()),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: fileWidth, child: _fileList()),
                ],
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      ZenithFade(
        animation: _entrance,
        delay: .2,
        duration: .3,
        css: true,
        child: _actions(),
      ),
    ],
  );
  Widget _tabs() => SizedBox(
    height: 46,
    child: zenithPanel(
      Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Row(
                  children: [
                    for (final doc in c.documents) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: InkWell(
                          onHover: (value) => setState(
                            () => value
                                ? _hoveredTabs.add(doc.id)
                                : _hoveredTabs.remove(doc.id),
                          ),
                          onTap: () => unawaited(
                            flushEditor().then((_) => c.selectDocument(doc.id)),
                          ),
                          borderRadius: BorderRadius.circular(6),
                          hoverColor: const Color(0x1fffffff),
                          highlightColor: Colors.transparent,
                          splashFactory: NoSplash.splashFactory,
                          child: Container(
                            height: 32,
                            constraints: const BoxConstraints(
                              minWidth: 84,
                              maxWidth: 190,
                            ),
                            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                            decoration: BoxDecoration(
                              color: _hoveredTabs.contains(doc.id)
                                  ? const Color(0x1fffffff)
                                  : doc.id == c.activeDocumentId
                                  ? const Color(0x14ffffff)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (doc.id == c.activeDocumentId)
                                  Positioned(
                                    left: -8,
                                    top: -4,
                                    bottom: -4,
                                    width: 4,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0xff3b82f6),
                                            Color(0xff2563eb),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.horizontal(
                                          right: Radius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _tabTitle(doc),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: zenithText(
                                          16,
                                          color: doc.id == c.activeDocumentId
                                              ? Colors.white
                                              : const Color(0x80ffffff),
                                        ),
                                      ),
                                    ),
                                    ZenithButton(
                                      '×',
                                      chrome: true,
                                      fontSize: 16,
                                      color: zenithMuted,
                                      hoverForeground: const Color(0xffff3737),
                                      width: 20,
                                      height: 20,
                                      padding: EdgeInsets.zero,
                                      background: Colors.transparent,
                                      onPressed: () =>
                                          unawaited(_closeTab(doc.id)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
            child: ZenithButton(
              '+',
              width: 50,
              height: 34,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              hoverBackground: const Color(0x1fffffff),
              pressedBackground: const Color(0x29ffffff),
              background: const Color(0x14ffffff),
              onPressed: () => handleEditorShortcut('new'),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _code() =>
      service != null &&
          widget.nativeWindow &&
          (Platform.isLinux || Platform.isWindows)
      ? MonacoEditor(
          service: service!,
          active: _page == 1 && _loggedIn && !_loading,
          backgroundColor: const Color(0xff0d0d0d),
        )
      : TextField(
          key: const ValueKey('code-editor'),
          controller: _editor,
          focusNode: _editorFocus,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          style: zenithText(
            14,
            height: 20 / 14,
            family: 'JetBrainsMono',
            color: const Color(0xffd4d4d4),
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
        );
  Widget _output() {
    final lines = c.activities
        .where(
          (line) =>
              line.kind == ActivityKind.execution &&
              !_clearedOutput.contains(line.id),
        )
        .toList()
        .reversed
        .toList();
    return zenithPanel(
      key: const ValueKey('zenith-output'),
      Stack(
        children: [
          Column(
            children: [
              SizedBox(
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Script Output',
                          style: zenithText(
                            14,
                            weight: FontWeight.w500,
                            color: zenithMuted,
                          ),
                        ),
                      ),
                      ZenithButton(
                        'Clear',
                        width: 52,
                        height: 32,
                        chrome: true,
                        background: Colors.transparent,
                        padding: EdgeInsets.zero,
                        onPressed: _clearOutput,
                      ),
                      ZenithButton(
                        '',
                        icon: _outputExpanded ? 'ChevronDown' : 'ChevronUp',
                        iconStroke: true,
                        iconSize: 16,
                        width: 32,
                        height: 32,
                        chrome: true,
                        padding: EdgeInsets.zero,
                        background: Colors.transparent,
                        onPressed: () =>
                            setState(() => _outputExpanded = !_outputExpanded),
                      ),
                    ],
                  ),
                ),
              ),
              if (_outputExpanded)
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: SelectableText.rich(
                        TextSpan(
                          style: zenithText(
                            11,
                            family: 'OriginalConsolas',
                            height: 15 / 11,
                            color: const Color(0xffc5c5c5),
                          ),
                          children: lines.isEmpty
                              ? [
                                  TextSpan(
                                    text: _outputHint
                                        ? 'Output from printconsole() → will appear here. Enable Error Spoofing → for errors too.'
                                        : '',
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Color(0x807c8293),
                                    ),
                                  ),
                                ]
                              : [
                                  for (
                                    var index = 0;
                                    index < lines.length;
                                    index++
                                  ) ...[
                                    if (index > 0) const TextSpan(text: '\n'),
                                    TextSpan(
                                      text:
                                          '${lines[index].timestamp.hour.toString().padLeft(2, '0')}:${lines[index].timestamp.minute.toString().padLeft(2, '0')}:${lines[index].timestamp.second.toString().padLeft(2, '0')} ',
                                      style: const TextStyle(
                                        color: Color(0xff555555),
                                      ),
                                    ),
                                    TextSpan(
                                      text: lines[index].message,
                                      style: TextStyle(
                                        color: switch (lines[index].severity) {
                                          ActivitySeverity.error => const Color(
                                            0xffe06c75,
                                          ),
                                          ActivitySeverity.warning =>
                                            const Color(0xffe5c07b),
                                          ActivitySeverity.info => const Color(
                                            0xff61afef,
                                          ),
                                          _ => const Color(0xffc5c5c5),
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_outputExpanded)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 5,
              child: MouseRegion(
                key: const ValueKey('zenith-output-resize'),
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (event) => setState(
                    () => _outputHeight = (_outputHeight - event.delta.dy)
                        .clamp(72, math.max(80, _editorStackHeight * .65)),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
      radius: 8,
    );
  }

  Widget _fileList() => zenithPanel(
    Column(
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              if (_fileListExpanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'File List',
                    style: zenithText(
                      14,
                      color: zenithMuted,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              ZenithButton(
                '',
                icon: _fileListExpanded ? 'PanelTriangle' : 'ChevronLeft',
                chrome: true,
                width: 32,
                height: 32,
                iconSize: 14,
                background: Colors.transparent,
                padding: EdgeInsets.zero,
                onPressed: () =>
                    setState(() => _fileListExpanded = !_fileListExpanded),
              ),
            ],
          ),
        ),
        if (_fileListExpanded)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
              children: [
                _folder(
                  'Scripts',
                  _scriptsExpanded,
                  () => setState(() => _scriptsExpanded = !_scriptsExpanded),
                ),
                if (_scriptsExpanded) ..._files(_scriptFiles),
                const SizedBox(height: 4),
                _folder(
                  'AutoExec',
                  _autoExecExpanded,
                  () => setState(() => _autoExecExpanded = !_autoExecExpanded),
                ),
                if (_autoExecExpanded) ..._files(_autoFiles),
              ],
            ),
          ),
      ],
    ),
    radius: 8,
  );
  List<Widget> _files(List<File> files) => [
    if (files.isEmpty)
      Padding(
        padding: const EdgeInsets.only(left: 20, top: 2),
        child: Text(
          'Empty. What is this? →',
          style: zenithText(12, color: const Color(0x999a9a9a)).copyWith(
            fontStyle: FontStyle.italic,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    for (final file in files)
      Padding(
        padding: const EdgeInsets.only(left: 16),
        child: ZenithButton(
          FilePaths.basename(file.path).replaceFirst(RegExp(r'\.[^.]+$'), ''),
          icon: 'File',
          iconStroke: true,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          hoverBackground: const Color(0x14ffffff),
          radius: 5,
          height: 27,
          fontSize: 13,
          background: Colors.transparent,
          onPressed: () => unawaited(_openLocal(file)),
        ),
      ),
  ];
  Widget _folder(String name, bool expanded, VoidCallback press) => SizedBox(
    height: 27,
    child: InkWell(
      onTap: press,
      borderRadius: BorderRadius.circular(4),
      hoverColor: const Color(0x14ffffff),
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Transform.rotate(
            angle: expanded ? math.pi / 2 : 0,
            child: const ZenithGlyph(
              'Chevron',
              size: 14,
              stroke: true,
              color: Color(0x80ffffff),
            ),
          ),
          const SizedBox(width: 7),
          const ZenithGlyph(
            'Folder',
            size: 16,
            stroke: true,
            color: Color(0xb3ffffff),
          ),
          const SizedBox(width: 7),
          Text(name, style: zenithText(13, weight: FontWeight.w500)),
        ],
      ),
    ),
  );
  Widget _actions() => LayoutBuilder(
    builder: (_, box) {
      final narrow = box.maxWidth < 560;
      Widget action(
        String title,
        double width,
        VoidCallback? callback,
        String icon,
        List<Color>? colors,
        Offset? offset,
      ) => ZenithButton(
        title,
        width: width,
        action: true,
        fontSize: 16,
        color: zenithMuted,
        icon: icon,
        onPressed: callback,
        blobColors: colors,
        blobOffset: offset,
        padding: const EdgeInsets.symmetric(horizontal: 6),
      );
      final attach = action('Attach', 92, () => _bridgeInfo(), 'Attach', const [
        Color(0xff667eea),
        Color(0xff764ba2),
      ], const Offset(-12, 17));
      final execute = action(
        'Execute',
        98,
        widget.bridgeReady ? () => c.execute() : null,
        'Execute',
        const [Color(0xff4facfe), Color(0xff00f2fe)],
        const Offset(58, -3),
      );
      final editing = [
        if (!pref('hideOpenButton'))
          action(
            'Open File',
            115,
            () => unawaited(_file(false)),
            'Open',
            const [Color(0xfff093fb), Color(0xfff5576c)],
            const Offset(75, 15),
          ),
        if (!pref('hideSaveButton'))
          action('Save File', 108, () => unawaited(_file(true)), 'Save', const [
            Color(0xff2cff35),
            Color(0xff2cff35),
          ], const Offset(-2, 15)),
        if (!pref('hideClearButton'))
          action(
            'Clear',
            80,
            () => c.updateDocumentContent(c.activeDocumentId, ''),
            'Clear',
            const [Color(0xffff3737), Color(0xffff3737)],
            const Offset(48, -3),
          ),
      ];
      if (narrow) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [attach, execute, _clientsButton(), ...editing],
        );
      }
      return SizedBox(
        height: 36,
        child: Row(
          children: [
            if (pref('swapAttachExecute')) execute else attach,
            const SizedBox(width: 8),
            if (pref('swapAttachExecute')) attach else execute,
            const SizedBox(width: 6),
            _clientsButton(),
            const Spacer(),
            for (var i = 0; i < editing.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              editing[i],
            ],
          ],
        ),
      );
    },
  );
  Widget _clientsButton() => Tooltip(
    message: 'Client manager',
    child: SizedBox(
      width: 32,
      height: 32,
      child: InkWell(
        key: const ValueKey('zenith-clients'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => unawaited(_bridgeInfo()),
        child: const Icon(Icons.devices_rounded, size: 20, color: zenithMuted),
      ),
    ),
  );
  Future<void> _bridgeInfo() =>
      showBridgeClientManager(context, controller: c, editorService: service);
}
