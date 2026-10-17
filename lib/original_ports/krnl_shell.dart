import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';

import '../widgets/bridge_client_manager.dart';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/companion_window.dart';
import '../models/interface_preset.dart';
import '../models/orion_models.dart';
import '../services/desktop_close_service.dart';
import '../services/monaco_editor_service.dart';
import '../services/native_window_service.dart';
import '../services/file_paths.dart';
import '../state/orion_controller.dart';
import '../widgets/monaco_editor.dart';
import 'krnl_controls.dart';

/// The 679 × 345 source-measured KRNL WinForms chrome, implemented in Flutter.
class KrnlShell extends StatefulWidget {
  const KrnlShell({
    super.key,
    required this.controller,
    required this.nativeWindow,
    required this.onBackToOrion,
    this.editorService,
    this.onSelectInterface,
    this.bridgeReady = false,
    this.scriptDirectory,
  });
  final OrionController controller;
  final bool nativeWindow, bridgeReady;
  final VoidCallback onBackToOrion;
  final MonacoEditorService? editorService;
  final Future<void> Function(InterfacePreset)? onSelectInterface;
  final Directory? scriptDirectory;
  @override
  State<KrnlShell> createState() => KrnlShellState();
}

class KrnlShellState extends State<KrnlShell>
    with TickerProviderStateMixin, WindowListener {
  final _editor = TextEditingController();
  final _focus = FocusNode(debugLabel: 'KRNL editor');
  final _find = TextEditingController();
  late final AnimationController _accent, _opacity;
  MonacoEditorService? _monaco;
  bool _ownsMonaco = false,
      _syncing = false,
      _options = false,
      _showFind = false,
      _closing = false;
  String _documentId = '';
  final _expanded = <String>{};
  List<_KrnlFile> _scripts = [];
  _KrnlFile? _selectedScript;
  int _directorySequence = 0, _windowSequence = 0, _scriptCount = 1;
  double? _nativeOpacity;
  OrionController get c => widget.controller;
  bool get _isOptionsWindow =>
      c.companionWindows?.kind == CompanionWindowKind.krnlOptions;
  List<EditorDocument> get _orderedDocuments {
    final order = preferences['tabOrder'];
    if (order is! List) return c.documents;
    final documents = c.documents.toList();
    int rank(String id) {
      final index = order.indexOf(id);
      return index >= 0 ? index : order.length;
    }

    documents.sort((a, b) => rank(a.id).compareTo(rank(b.id)));
    return documents;
  }

  Map<String, Object?> get preferences =>
      c.getInterfacePreferences(InterfacePreset.krnl);
  bool option(String name, [bool fallback = false]) =>
      preferences[name] is bool ? preferences[name] as bool : fallback;
  bool get _reduceMotion =>
      c.reducedMotion || MediaQuery.maybeOf(context)?.disableAnimations == true;
  Directory get scriptDirectory {
    if (widget.scriptDirectory != null) return widget.scriptDirectory!;
    final saved = preferences['scriptPath'];
    if (saved is String && saved.isNotEmpty) return Directory(saved);
    return c.scriptsDirectory;
  }

  @override
  void initState() {
    super.initState();
    _accent = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 417),
    )..addListener(_animate);
    _opacity = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      value: 1,
    )..addListener(_animate);
    _options = _isOptionsWindow;
    _scriptCount = c.documents.length;
    if (!_isOptionsWindow && widget.editorService != null) {
      _monaco = widget.editorService!..addListener(_nativeChanged);
    } else if (!_isOptionsWindow &&
        widget.nativeWindow &&
        (Platform.isLinux || Platform.isWindows)) {
      _ownsMonaco = true;
      _monaco = MonacoEditorService(
        onChange: c.updateDocumentContent,
        onShortcut: handleEditorShortcut,
      )..addListener(_nativeChanged);
    }
    _sync();
    _editor.addListener(_edited);
    c.addListener(_sync);
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
    if (!_isOptionsWindow &&
        (widget.nativeWindow || widget.scriptDirectory != null)) {
      unawaited(_reloadScripts());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_options && !_reduceMotion) _accent.repeat();
      _monaco?.setActive(!_options);
    });
  }

  @override
  void dispose() {
    ++_directorySequence;
    ++_windowSequence;
    c.removeListener(_sync);
    _editor.removeListener(_edited);
    _monaco?.removeListener(_nativeChanged);
    _monaco?.setOpacity(1, owner: 'original-krnl');
    if (!_isOptionsWindow && _nativeOpacity != null && _nativeOpacity != 1) {
      unawaited(c.companionWindows?.updateOwnerWindow(opacity: 1));
    }
    if (_ownsMonaco) _monaco?.dispose();
    if (widget.nativeWindow) windowManager.removeListener(this);
    _accent.dispose();
    _opacity.dispose();
    _editor.dispose();
    _focus.dispose();
    _find.dispose();
    super.dispose();
  }

  void _animate() {
    if (c.companionWindows != null) {
      if (!_isOptionsWindow && _nativeOpacity != _opacity.value) {
        _nativeOpacity = _opacity.value;
        unawaited(
          c.companionWindows!.updateOwnerWindow(opacity: _opacity.value),
        );
      }
    } else {
      _monaco?.setOpacity(_opacity.value, owner: 'original-krnl');
    }
    if (mounted) setState(() {});
  }

  void _nativeChanged() {
    if (mounted) setState(() {});
  }

  void _sync() {
    final d = c.activeDocument;
    if (_documentId != d.id || _editor.text != d.content) {
      final changed = _documentId != d.id;
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
    if (!option('opacityFade') && !_closing && _opacity.value != 1) {
      _opacity.value = 1;
    }
    if (mounted) setState(() {});
  }

  void _edited() {
    if (!_syncing) c.updateDocumentContent(_documentId, _editor.text);
  }

  Future<void> flushEditor() async {
    if (!_options) await _monaco?.flush();
  }

  Future<void> reloadScripts() => _reloadScripts();

  void setEditorObscured(bool value, {String owner = 'route'}) =>
      _monaco?.setObscured(value, owner: owner);
  void setEditorTransitioning(bool value) => _monaco?.setTransitioning(value);
  void handleEditorShortcut(String name) {
    switch (name) {
      case 'show-editor':
        unawaited(_navigate(false));
        break;
      case 'new':
        unawaited(_new());
        break;
      case 'open':
        unawaited(_open());
        break;
      case 'save':
        unawaited(_save());
        break;
      case 'saveAs':
        unawaited(_save(saveAs: true));
        break;
      case 'execute':
        if (widget.bridgeReady) unawaited(_execute());
        break;
      case 'find':
        requestFind();
        break;
    }
  }

  void requestFind() {
    if (_options) {
      unawaited(_navigate(false).then((_) => requestFind()));
      return;
    }
    if (_monaco != null) {
      unawaited(_monaco!.action('find'));
      return;
    }
    setState(() => _showFind = true);
  }

  Future<void> _navigate(bool settings) async {
    final companion = c.companionWindows;
    if (companion != null) {
      if (settings && !_isOptionsWindow) {
        await flushEditor();
        if (mounted) await companion.open(CompanionWindowKind.krnlOptions);
      } else if (!settings && _isOptionsWindow) {
        await companion.close();
      }
      return;
    }
    if (_options == settings) return;
    await flushEditor();
    if (!mounted) return;
    _monaco?.setActive(!settings);
    setState(() => _options = settings);
    await _resize();
  }

  Future<void> _resize() async {
    if (!widget.nativeWindow) return;
    final seq = ++_windowSequence,
        size = _options ? const Size(248, 153) : const Size(679, 345);
    try {
      final bounds = await windowManager.getBounds();
      if (!mounted || seq != _windowSequence) return;
      await NativeWindowService.setMinimumSize(size);
      await NativeWindowService.setResizable(
        !_options && option('resizable'),
        size: size,
      );
      if (!mounted || seq != _windowSequence) return;
      await windowManager.setPosition(
        bounds.center - Offset(size.width / 2, size.height / 2),
      );
      await NativeWindowService.setAlwaysOnTop(option('alwaysOnTop'));
    } catch (_) {}
  }

  Future<T?> _obscured<T>(Future<T?> Function() action) async {
    try {
      await _monaco?.freezeForOverlay(owner: 'krnl-dialog');
      if (!mounted) return null;
      return await action();
    } finally {
      _monaco?.setObscured(false, owner: 'krnl-dialog');
    }
  }

  Future<void> _new() async {
    await flushEditor();
    if (!mounted) return;
    c.newDocument(name: 'Script ${++_scriptCount}.lua');
    _focus.requestFocus();
  }

  Future<void> _select(String id) async {
    await flushEditor();
    if (mounted) c.selectDocument(id);
  }

  Future<void> _open() async {
    await flushEditor();
    if (mounted) await _obscured(c.openFile);
  }

  Future<void> _save({bool saveAs = false}) async {
    await flushEditor();
    if (mounted) await _obscured(() => saveAs ? c.saveAs() : c.saveDocument());
  }

  Future<void> _clear() async {
    await flushEditor();
    if (!mounted) return;
    c.updateDocumentContent(c.activeDocumentId, '');
    if (_monaco != null) {
      await _monaco!.action('clear');
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _execute() async {
    if (!widget.bridgeReady) return;
    await flushEditor();
    if (mounted) c.execute();
  }

  Future<void> _back() async {
    await flushEditor();
    if (!mounted) return;
    if (_isOptionsWindow) {
      await c.companionWindows!.returnToOrion();
    } else {
      widget.onBackToOrion();
    }
  }

  Future<void> _closeTab(EditorDocument d) async {
    await flushEditor();
    if (!mounted) return;
    final current = c.documents.where((doc) => doc.id == d.id).firstOrNull;
    if (current == null) return;
    d = current;
    if (d.isDirty) {
      final answer = await _obscured(
        () => showDialog<bool>(
          context: context,
          builder: (ctx) =>
              _dialog('Unsaved changes', 'Discard changes to ${d.name}?', [
                ('Cancel', () => Navigator.pop(ctx, false)),
                ('Discard', () => Navigator.pop(ctx, true)),
              ]),
        ),
      );
      if (answer != true || !mounted) return;
    }
    final order = _orderedDocuments;
    final index = order.indexWhere((doc) => doc.id == d.id);
    final next = order.length > 1 ? order[index > 0 ? index - 1 : 1].id : null;
    c.closeDocument(d.id);
    if (next != null) c.selectDocument(next);
    if (c.documents.length == 1 && c.activeDocument.name == 'untitled.lua') {
      c.renameDocument(c.activeDocumentId, 'Script 1.lua');
    }
  }

  Widget _dialog(
    String title,
    String body,
    List<(String, VoidCallback)> actions,
  ) => Dialog(
    backgroundColor: KrnlSource.title,
    shape: const RoundedRectangleBorder(),
    child: SizedBox(
      width: 340,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: KrnlSource.type(14)),
            const SizedBox(height: 12),
            Text(body, style: KrnlSource.type(12)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final action in actions)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: SizedBox(
                      width: 74,
                      height: 25,
                      child: KrnlButton(
                        action.$1,
                        onPressed: action.$2,
                        size: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _reloadScripts() async {
    final seq = ++_directorySequence;
    Future<List<_KrnlFile>> read(Directory dir, int depth) async {
      if (depth > 12) return [];
      try {
        final entries = await dir.list(followLinks: false).toList();
        entries.sort(
          (a, b) =>
              (a is Directory ? 0 : 1).compareTo(b is Directory ? 0 : 1) != 0
              ? (a is Directory ? 0 : 1).compareTo(b is Directory ? 0 : 1)
              : FilePaths.basename(a.path).toLowerCase().compareTo(
                  FilePaths.basename(b.path).toLowerCase(),
                ),
        );
        return [
          for (final entry in entries.take(1000))
            if (entry is Directory)
              _KrnlFile(entry.path, await read(entry, depth + 1))
            else if (entry is File)
              _KrnlFile(entry.path, null),
        ];
      } catch (_) {
        return [];
      }
    }

    final root = scriptDirectory;
    try {
      await root.create(recursive: true);
    } catch (_) {}
    final entries = await read(root, 0);
    if (mounted && seq == _directorySequence) {
      setState(() {
        _scripts = entries;
        _selectedScript = null;
      });
    }
  }

  Future<void> _loadScript(_KrnlFile f) async {
    if (f.children != null) return;
    await flushEditor();
    try {
      final body = await File(f.path).readAsString();
      if (mounted) c.newDocument(name: f.name, content: body);
    } catch (e) {
      if (mounted) {
        await _obscured(
          () => showDialog<void>(
            context: context,
            builder: (ctx) => _dialog('KRNL', e.toString(), [
              ('OK', () => Navigator.pop(ctx)),
            ]),
          ),
        );
      }
    }
  }

  Future<void> _changePath() async {
    final result = await _obscured(
      () => files.getDirectoryPath(initialDirectory: scriptDirectory.path),
    );
    if (result != null && mounted) {
      c.setInterfacePreference(InterfacePreset.krnl, 'scriptPath', result);
      await _reloadScripts();
    }
  }

  Future<void> _deleteScript(_KrnlFile f) async {
    if (f.children != null) return;
    final result = await _obscured(
      () => showDialog<bool>(
        context: context,
        builder: (ctx) => _dialog('Delete File', 'Delete ${f.name}?', [
          ('Cancel', () => Navigator.pop(ctx, false)),
          ('Delete', () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (result == true) {
      try {
        await File(f.path).delete();
      } catch (_) {}
      await _reloadScripts();
    }
  }

  Future<void> _popup(
    Offset at,
    List<(String, VoidCallback?)> actions, {
    bool system = false,
    int? separatorBefore,
  }) async {
    await _obscured(() async {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final position = overlay.globalToLocal(at);
      final selected = await showMenu<int>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(position.dx, position.dy, 1, 1),
          Offset.zero & overlay.size,
        ),
        color: system ? const Color(0xfff0f0f0) : KrnlSource.menu,
        shape: const RoundedRectangleBorder(),
        elevation: 3,
        items: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i == separatorBefore) const PopupMenuDivider(height: 7),
            PopupMenuItem<int>(
              value: i,
              enabled: actions[i].$2 != null,
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                actions[i].$1,
                style: KrnlSource.type(
                  12,
                  color: actions[i].$2 == null
                      ? const Color(0xff7c7c7c)
                      : system
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ],
        ],
      );
      if (selected != null && mounted) actions[selected].$2?.call();
      return null;
    });
  }

  void _scriptMenu(Offset at, _KrnlFile f) {
    setState(() => _selectedScript = f);
    unawaited(
      _popup(at, [
        (
          'Execute',
          widget.bridgeReady && f.children == null
              ? () => unawaited(
                  File(f.path).readAsString().then(
                    (s) => c.executeSource(s, name: f.name),
                  ),
                )
              : null,
        ),
        (
          'Load Into Editor',
          f.children == null ? () => unawaited(_loadScript(f)) : null,
        ),
        (
          'Delete File',
          f.children == null ? () => unawaited(_deleteScript(f)) : null,
        ),
        ('Change Path', () => unawaited(_changePath())),
        ('Reload', () => unawaited(_reloadScripts())),
      ], system: true),
    );
  }

  Future<void> _tabMenu(Offset at, EditorDocument d) async {
    await _select(d.id);
    if (!mounted) return;
    await _popup(
      at,
      [
        ('Clear', () => unawaited(_clear())),
        ('Open Into', () => unawaited(_openInto(d))),
        ('Save', () => unawaited(_save())),
        ('Close Tab', () => unawaited(_closeTab(d))),
      ],
      system: true,
      separatorBefore: 3,
    );
  }

  Future<void> _openInto(EditorDocument d) async {
    final picked = await _obscured(
      () => files.openFile(
        acceptedTypeGroups: [
          const files.XTypeGroup(
            label: 'Script Files',
            extensions: ['txt', 'lua', 'luau'],
          ),
        ],
      ),
    );
    if (picked == null) return;
    final body = await picked.readAsString();
    if (!mounted) return;
    c.renameDocument(d.id, picked.name);
    c.updateDocumentContent(d.id, body);
  }

  @override
  void onWindowBlur() {
    if (!_isOptionsWindow && option('opacityFade') && !_closing) {
      unawaited(
        _opacity.animateTo(
          .5,
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 100),
        ),
      );
    }
  }

  @override
  void onWindowFocus() {
    if (!_isOptionsWindow && !_closing) {
      unawaited(
        _opacity.animateTo(
          1,
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 100),
        ),
      );
    }
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      if (_isOptionsWindow) {
        await c.companionWindows!.close();
        return;
      }
      await DesktopCloseService.closeApp(
        controller: c,
        nativeWindow: widget.nativeWindow,
        flushEditor: flushEditor,
      );
    } finally {
      _closing = false;
    }
  }

  void _synchronizeNative() {
    if (_monaco == null) return;
    unawaited(
      _monaco!.synchronize({
        'documents': [
          for (final d in c.documents)
            {'id': d.id, 'name': d.name, 'content': d.content},
        ],
        'activeId': c.activeDocumentId,
        'options': {
          'shell': 'originalKrnl',
          'animateReveal': false,
          'fontSize': 13.3333333333,
          'uiScale': c.uiScale,
          'wordWrap': false,
          'lineNumbers': true,
          'minimap': false,
          'diagnosticEnabled': false,
          'reducedMotion': _reduceMotion,
          'brightness': 'dark',
          'background': '#282828',
          'foreground': '#ffffff',
          'accent': '#1e90ff',
          'muted': '#bebebe',
          'border': '#1e1e1e',
        },
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    _synchronizeNative();
    if (_reduceMotion && _accent.isAnimating) _accent.stop();
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'OriginalSegoeUI',
        splashFactory: NoSplash.splashFactory,
        colorScheme: const ColorScheme.dark(surface: KrnlSource.window),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              unawaited(_new()),
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
              unawaited(_open()),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_save()),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () =>
              unawaited(_save(saveAs: true)),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              requestFind,
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: _options ? const Color(0xff191919) : KrnlSource.window,
            child: Opacity(
              opacity: c.companionWindows != null ? 1 : _opacity.value,
              child: _options ? _settings() : _main(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fit(Size minimum, Widget Function(Size) build) => LayoutBuilder(
    builder: (context, box) {
      final size = Size(
        math.max(minimum.width, box.maxWidth),
        math.max(minimum.height, box.maxHeight),
      );
      if (box.maxWidth >= minimum.width && box.maxHeight >= minimum.height) {
        return build(size);
      }
      return FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: minimum, child: build(minimum)),
      );
    },
  );
  Widget _main() => _fit(
    const Size(679, 345),
    (size) => Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 33,
          child: _titleBar(size),
        ),
        Positioned(left: 0, right: 0, top: 33, height: 24, child: _menuBar()),
        Positioned(
          left: 4,
          right: 130,
          top: 59,
          bottom: 32,
          child: DecoratedBox(
            key: const ValueKey('krnl-tabs-container'),
            decoration: BoxDecoration(
              color: const Color(0xff2d2d30),
              border: Border.all(color: const Color(0xff1e1e1e), width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Column(
                children: [
                  SizedBox(height: 20, child: _tabStrip()),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _monaco != null
                                ? MonacoEditor(
                                    key: const ValueKey('code-editor'),
                                    service: _monaco!,
                                    active: !_options,
                                    backgroundColor: KrnlSource.editor,
                                  )
                                : _fallback(),
                          ),
                          if (_showFind)
                            Positioned(
                              top: 0,
                              right: 0,
                              width: 230,
                              height: 27,
                              child: _findBar(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 59,
          width: 121,
          bottom: 32,
          child: _scriptTree(),
        ),
        for (final item in [
          (
            0,
            'EXECUTE',
            4.0,
            widget.bridgeReady ? () => unawaited(_execute()) : null,
          ),
          (1, 'CLEAR', 107.0, () => unawaited(_clear())),
          (2, 'OPEN FILE', 210.0, () => unawaited(_open())),
          (3, 'SAVE FILE', 313.0, () => unawaited(_save())),
          (
            4,
            'INJECT',
            416.0,
            () => unawaited(
              showBridgeClientManager(
                context,
                controller: c,
                editorService: _monaco,
              ),
            ),
          ),
        ])
          Positioned(
            left: item.$3,
            bottom: 4,
            width: 100,
            height: 25,
            child: KrnlButton(
              item.$2,
              key: ValueKey('krnl-action-${item.$1}'),
              onPressed: item.$4,
              tooltip: item.$1 == 4 ? 'Connect Orion Bridge' : null,
            ),
          ),
        Positioned(
          right: 4,
          bottom: 4,
          width: 100,
          height: 25,
          child: KrnlButton(
            'OPTIONS',
            key: const ValueKey('krnl-options'),
            onPressed: () => unawaited(_navigate(true)),
          ),
        ),
      ],
    ),
  );
  Widget _titleBar(Size size) => Stack(
    children: [
      Positioned.fill(
        child: ColoredBox(
          color: KrnlSource.title,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.nativeWindow
                ? (_) => windowManager.startDragging()
                : null,
          ),
        ),
      ),
      Positioned(
        left: 4,
        top: 4,
        width: 25,
        height: 25,
        child: IgnorePointer(
          child: Image.asset(
            'assets/original_krnl/pictureBox1.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
      Positioned(
        left: size.width / 2 - 17.5,
        top: 7,
        width: 45,
        height: 20,
        child: IgnorePointer(child: Text('KRNL', style: KrnlSource.type(15))),
      ),
      Positioned(
        right: 35,
        top: 0,
        width: 35,
        height: 33,
        child: KrnlButton(
          '',
          background: KrnlSource.title,
          hover: const Color(0xff232323),
          tooltip: 'Minimize',
          onPressed: () =>
              widget.nativeWindow ? windowManager.minimize() : null,
          child: Image.asset('assets/original_krnl/button2.png'),
        ),
      ),
      Positioned(
        right: 0,
        top: 0,
        width: 35,
        height: 33,
        child: KrnlButton(
          '',
          background: KrnlSource.title,
          hover: const Color(0xff232323),
          tooltip: 'Close Orion',
          onPressed: onWindowClose,
          child: Image.asset('assets/original_krnl/button1.png'),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: 2,
        child: ColoredBox(
          key: const ValueKey('krnl-blue-accent'),
          color: _accentColor(),
        ),
      ),
    ],
  );
  Color _accentColor() {
    if (_reduceMotion) return const Color(0xff1e90ff);
    final step = (_accent.value * 139).floor().clamp(0, 138);
    return step < 70
        ? Color.fromARGB(255, 30, 144 - step, 255 - step)
        : Color.fromARGB(255, 30, 74 + step - 70, 185 + step - 70);
  }

  Widget _menuBar() => ColoredBox(
    color: KrnlSource.menu,
    child: Row(
      children: [
        for (final menu in [
          'File',
          'Credits',
          'Games',
          'Hot-Scripts',
          'Others',
          'Clients',
        ])
          SizedBox(
            width: switch (menu) {
              'File' => 39,
              'Credits' => 58,
              'Games' => 58,
              'Hot-Scripts' => 88,
              _ => 55,
            },
            child: Builder(
              builder: (ctx) => KrnlButton(
                menu,
                size: 12,
                font: 'OriginalSegoeUI',
                background: KrnlSource.menu,
                hover: const Color(0xff303030),
                key: menu == 'Clients' ? const ValueKey('krnl-clients') : null,
                onPressed: () => menu == 'Clients'
                    ? unawaited(
                        showBridgeClientManager(
                          context,
                          controller: c,
                          editorService: _monaco,
                        ),
                      )
                    : _openTopMenu(ctx, menu),
              ),
            ),
          ),
      ],
    ),
  );
  void _openTopMenu(BuildContext ctx, String menu) {
    final box = ctx.findRenderObject() as RenderBox,
        at = box.localToGlobal(Offset(0, box.size.height));
    final entries = switch (menu) {
      'File' => ['Inject', 'Kill Roblox'],
      'Hot-Scripts' => [
        'DarkDex',
        'OpenGui',
        'Owl Hub',
        'Krnl Hub',
        'Remote Spy',
        'Game Sense',
        'Unnamed ESP',
      ],
      'Others' => ['Get Key', 'Join Discord Server'],
      _ => <String>[],
    };
    if (entries.isEmpty) return;
    unawaited(
      _popup(at, [
        for (final entry in entries)
          (
            entry,
            entry == 'Inject'
                ? () => unawaited(
                    showBridgeClientManager(
                      context,
                      controller: c,
                      editorService: _monaco,
                    ),
                  )
                : null,
          ),
      ]),
    );
  }

  Widget _tabStrip() => KrnlTabStrip(
    tabs: [
      for (final document in _orderedDocuments)
        (id: document.id, title: document.name),
    ],
    activeId: c.activeDocumentId,
    onSelect: (id) => unawaited(_select(id)),
    onAdd: () => unawaited(_new()),
    onSwap: (source, target) {
      final order = _orderedDocuments.map((document) => document.id).toList();
      final from = order.indexOf(source), to = order.indexOf(target);
      if (from < 0 || to < 0 || from == to) return;
      final swapped = order[from];
      order[from] = order[to];
      order[to] = swapped;
      c.reorderDocuments(order);
      // Migrate any previously stored visual-only order to the workspace.
      c.setInterfacePreference(InterfacePreset.krnl, 'tabOrder', null);
      c.selectDocument(source);
    },
    onMenu: (id, position) {
      final document = c.documents.where((doc) => doc.id == id).firstOrNull;
      if (document != null) unawaited(_tabMenu(position, document));
    },
  );

  Widget _fallback() => ColoredBox(
    color: KrnlSource.editor,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 19,
          child: Padding(
            padding: const EdgeInsets.only(top: 2, right: 3),
            child: Text(
              List.generate(
                _editor.text.split('\n').length,
                (i) => '${i + 1}',
              ).join('\n'),
              textAlign: TextAlign.right,
              style: KrnlSource.type(
                10.6666667,
                font: 'OriginalConsolas',
                color: const Color(0xffbebebe),
              ).copyWith(height: 1.5),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            key: const ValueKey('code-editor'),
            controller: _editor,
            focusNode: _focus,
            expands: true,
            minLines: null,
            maxLines: null,
            style: KrnlSource.type(
              13.33333333,
              font: 'OriginalConsolas',
            ).copyWith(height: 1.2),
            cursorColor: Colors.white,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _findBar() => ColoredBox(
    color: KrnlSource.menu,
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _find,
            autofocus: true,
            style: KrnlSource.type(11),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.only(left: 6, bottom: 8),
              border: InputBorder.none,
              hintText: 'Find',
            ),
            onSubmitted: (term) {
              final index = _editor.text.indexOf(
                term,
                math.max(0, _editor.selection.end),
              );
              final match = index >= 0 ? index : _editor.text.indexOf(term);
              if (match >= 0) {
                _editor.selection = TextSelection(
                  baseOffset: match,
                  extentOffset: match + term.length,
                );
              }
            },
          ),
        ),
        SizedBox(
          width: 25,
          child: KrnlButton(
            '×',
            onPressed: () => setState(() => _showFind = false),
          ),
        ),
      ],
    ),
  );
  Widget _scriptTree() => ColoredBox(
    key: const ValueKey('krnl-script-tree'),
    color: KrnlSource.title,
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final f in _scripts) ..._fileRows(f, 0)],
      ),
    ),
  );
  List<Widget> _fileRows(_KrnlFile f, int depth) => [
    GestureDetector(
      onSecondaryTapDown: (details) => _scriptMenu(details.globalPosition, f),
      onDoubleTap: f.children == null ? () => unawaited(_loadScript(f)) : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() {
            _selectedScript = f;
            if (f.children != null) {
              if (!_expanded.add(f.path)) _expanded.remove(f.path);
            }
          }),
          child: ColoredBox(
            color: _selectedScript?.path == f.path
                ? const Color(0xff343434)
                : Colors.transparent,
            child: SizedBox(
              height: 18,
              child: Row(
                children: [
                  SizedBox(width: depth * 15.0 + 5),
                  if (f.children != null)
                    SizedBox(
                      width: 12,
                      child: Text(
                        _expanded.contains(f.path) ? '−' : '+',
                        style: KrnlSource.type(11),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: KrnlSource.type(11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    if (f.children != null && _expanded.contains(f.path))
      for (final child in f.children!) ..._fileRows(child, depth + 1),
  ];
  Widget _settings() => _fit(
    const Size(248, 153),
    (_) => Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 34,
          child: ColoredBox(color: KrnlSource.title),
        ),
        Positioned(
          left: 0,
          right: 55,
          top: 0,
          height: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.nativeWindow
                ? (_) => windowManager.startDragging()
                : null,
          ),
        ),
        Positioned(
          left: -2,
          top: -2,
          width: 35,
          height: 36,
          child: IgnorePointer(
            child: Image.asset(
              'assets/original_krnl/pictureBox1.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        Positioned(
          left: 101,
          top: 8,
          child: IgnorePointer(
            child: Text('Settings', style: KrnlSource.type(12)),
          ),
        ),
        Positioned(
          left: 191,
          top: -4,
          width: 25,
          height: 37,
          child: KrnlButton(
            '—',
            background: KrnlSource.title,
            size: 12,
            onPressed: () =>
                widget.nativeWindow ? windowManager.minimize() : null,
          ),
        ),
        Positioned(
          left: 219,
          top: -4,
          width: 25,
          height: 37,
          child: KrnlButton(
            '✕',
            background: KrnlSource.title,
            size: 12,
            tooltip: 'Close settings',
            onPressed: () => unawaited(_navigate(false)),
          ),
        ),
        Positioned(
          left: 10,
          top: 55,
          child: GestureDetector(
            onTap: () => _setTopMost(!option('alwaysOnTop')),
            child: Text('Top Most', style: KrnlSource.type(12)),
          ),
        ),
        Positioned(
          left: 187,
          top: 52,
          child: KrnlToggle(
            key: const ValueKey('krnl-top-most'),
            value: option('alwaysOnTop'),
            reducedMotion: _reduceMotion,
            onChanged: _setTopMost,
          ),
        ),
        Positioned(
          left: 10,
          top: 84,
          child: GestureDetector(
            onTap: () => _setOpacityFade(!option('opacityFade')),
            child: Text('Opacity Fade-in/out', style: KrnlSource.type(12)),
          ),
        ),
        Positioned(
          left: 187,
          top: 81,
          child: KrnlToggle(
            key: const ValueKey('krnl-opacity-fade'),
            value: option('opacityFade'),
            reducedMotion: _reduceMotion,
            onChanged: _setOpacityFade,
          ),
        ),
        Positioned(
          left: 10,
          top: 118,
          width: 130,
          height: 23,
          child: KrnlButton(
            'Back to Orion',
            key: const ValueKey('krnl-back-to-orion'),
            size: 12,
            font: 'OriginalSegoeUI',
            onPressed: () => unawaited(_back()),
          ),
        ),
      ],
    ),
  );
  void _setTopMost(bool value) {
    c.setInterfacePreference(InterfacePreset.krnl, 'alwaysOnTop', value);
    if (c.companionWindows != null) {
      unawaited(c.companionWindows!.updateOwnerWindow(alwaysOnTop: value));
    } else if (widget.nativeWindow) {
      unawaited(NativeWindowService.setAlwaysOnTop(value));
    }
  }

  void _setOpacityFade(bool value) {
    c.setInterfacePreference(InterfacePreset.krnl, 'opacityFade', value);
    if (!value) {
      unawaited(
        _opacity.animateTo(
          1,
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 100),
        ),
      );
    }
  }
}

class _KrnlFile {
  const _KrnlFile(this.path, this.children);
  final String path;
  final List<_KrnlFile>? children;
  String get name => FilePaths.basename(path);
}
