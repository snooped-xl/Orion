import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models/interface_preset.dart';
import '../services/monaco_editor_service.dart';
import '../services/desktop_launcher.dart';
import '../services/file_paths.dart';
import '../state/orion_controller.dart';
import '../widgets/monaco_editor.dart';
import 'awp_controls.dart';

abstract class AwpWorkspaceHost extends StatefulWidget {
  const AwpWorkspaceHost({
    super.key,
    required this.controller,
    required this.nativeWindow,
    required this.onBackToOrion,
    this.editorService,
    this.bridgeReady = false,
    this.onSelectInterface,
    this.pickScriptPath,
    this.pickSavePath,
  });
  final OrionController controller;
  final bool nativeWindow, bridgeReady;
  final VoidCallback onBackToOrion;
  final MonacoEditorService? editorService;
  final Future<void> Function(InterfacePreset)? onSelectInterface;
  final Future<String?> Function()? pickScriptPath;
  final Future<String?> Function(String suggestedName)? pickSavePath;
}

/// Shared local file/model plumbing only; the two original source layouts stay separate.
abstract class AwpWorkspaceState<T extends AwpWorkspaceHost> extends State<T>
    with WindowListener {
  final editor = TextEditingController();
  final editorFocus = FocusNode();
  MonacoEditorService? monaco;
  bool _ownsMonaco = false, _syncing = false, maximized = false;
  String _documentId = '';
  List<File> localFiles = [];
  OrionController get c => widget.controller;
  InterfacePreset get preset;
  String get shellName;
  Color get canvasColor;
  bool get editorVisible;
  bool get isCompanionWindow => c.companionWindows?.isChildWindow ?? false;
  bool get replaceActiveOnOpen => false;
  bool get renameOnSave => true;
  bool get showLuauSaveType => true;
  bool get excludeHiddenScripts => true;
  bool get createScriptsDirectory => false;
  List<String> get scriptExtensions => const ['lua', 'luau', 'txt'];
  Size get mainSize;
  Size get mainMinimum;
  Map<String, Object?> get preferences => c.getInterfacePreferences(preset);
  bool option(String name, [bool fallback = false]) =>
      preferences[name] is bool ? preferences[name] as bool : fallback;
  void preference(String name, Object? value) =>
      c.setInterfacePreference(preset, name, value);

  @override
  void initState() {
    super.initState();
    if (!isCompanionWindow && widget.editorService != null) {
      monaco = widget.editorService!..addListener(_nativeChanged);
    } else if (!isCompanionWindow &&
        widget.nativeWindow &&
        (Platform.isLinux || Platform.isWindows)) {
      _ownsMonaco = true;
      monaco = MonacoEditorService(
        onChange: c.updateDocumentContent,
        onShortcut: handleEditorShortcut,
      )..addListener(_nativeChanged);
    }
    editor.addListener(_edited);
    c.addListener(_sync);
    _sync();
    unawaited(refreshLocalFiles());
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
  }

  void _nativeChanged() {
    if (mounted) setState(() {});
  }

  void _sync() {
    final d = c.activeDocument;
    if (d.id != _documentId || d.content != editor.text) {
      final changed = d.id != _documentId;
      _documentId = d.id;
      _syncing = true;
      editor.value = TextEditingValue(
        text: d.content,
        selection: TextSelection.collapsed(
          offset: changed
              ? 0
              : editor.selection.baseOffset.clamp(0, d.content.length),
        ),
      );
      _syncing = false;
    }
    if (mounted) setState(() {});
  }

  void _edited() {
    if (!_syncing) c.updateDocumentContent(_documentId, editor.text);
  }

  Future<void> flushEditor() async {
    await monaco?.flush();
  }

  void setEditorObscured(bool value, {String owner = 'route'}) =>
      monaco?.setObscured(value, owner: owner);
  void setEditorTransitioning(bool value) => monaco?.setTransitioning(value);
  Future<void> showEditor();

  void handleEditorShortcut(String name) {
    switch (name) {
      case 'show-editor':
        unawaited(showEditor());
        break;
      case 'open':
        unawaited(open());
        break;
      case 'save':
        unawaited(save());
        break;
      case 'saveAs':
        unawaited(save(saveAs: true));
        break;
      case 'new':
        unawaited(newTab());
        break;
      case 'execute':
        if (widget.bridgeReady) unawaited(execute());
        break;
      case 'find':
        if (monaco != null) unawaited(monaco!.action('find'));
        break;
    }
  }

  void synchronizeNative() {
    monaco?.setActive(editorVisible);
    if (monaco == null) return;
    unawaited(
      monaco!.synchronize({
        'documents': [
          for (final d in c.documents)
            {'id': d.id, 'name': d.name, 'content': d.content},
        ],
        'activeId': c.activeDocumentId,
        'options': {
          'shell': shellName,
          'animateReveal': false,
          'fontSize': 13,
          'uiScale': c.uiScale,
          'wordWrap': c.wordWrap,
          'lineNumbers': c.showLineNumbers,
          'minimap': false,
          'reducedMotion': c.reducedMotion,
          'brightness': 'dark',
          'background': shellName == 'originalAwp' ? '#191818' : '#050505',
          'foreground': '#d4d4d4',
          'accent': '#569cd6',
          'muted': '#858585',
          'border': '#2c2c2c',
        },
      }),
    );
  }

  Widget codeEditor() => monaco != null
      ? MonacoEditor(
          key: const ValueKey('code-editor'),
          service: monaco!,
          active: editorVisible,
          backgroundColor: canvasColor,
          foregroundColor: awpText,
        )
      : ColoredBox(
          color: canvasColor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.showLineNumbers)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 10, 2),
                  child: Text(
                    List.generate(
                      c.activeDocument.lineCount,
                      (i) => '${i + 1}',
                    ).join('\n'),
                    style: awpType(
                      13,
                      color: const Color(0xff858585),
                      mono: true,
                      height: 18 / 13,
                    ),
                  ),
                ),
              Expanded(
                child: TextField(
                  key: const ValueKey('code-editor'),
                  controller: editor,
                  focusNode: editorFocus,
                  maxLines: null,
                  expands: true,
                  style: awpType(
                    13,
                    color: const Color(0xffd4d4d4),
                    mono: true,
                    height: 18 / 13,
                  ),
                  cursorColor: const Color(0xffaeafad),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    visualDensity: VisualDensity.standard,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        );

  Future<TValue?> obscured<TValue>(Future<TValue?> Function() action) async {
    await monaco?.freezeForOverlay(owner: shellName);
    try {
      return await action();
    } finally {
      monaco?.setObscured(false, owner: shellName);
    }
  }

  Future<void> open() async {
    await flushEditor();
    if (!mounted) return;
    final path = await obscured(() async {
      if (widget.pickScriptPath != null) return widget.pickScriptPath!();
      return (await files.openFile(
        confirmButtonText: 'Open script',
        acceptedTypeGroups: [
          files.XTypeGroup(label: 'Script files', extensions: scriptExtensions),
        ],
      ))?.path;
    });
    if (path != null && mounted) await importScript(path);
  }

  Future<void> importScript(String path) async {
    await c.importDocumentFromPath(
      path,
      replaceId: replaceActiveOnOpen ? c.activeDocumentId : null,
    );
  }

  Future<bool> savePickedScript() async {
    await flushEditor();
    if (!mounted) return false;
    final document = c.activeDocument;
    final suggested = document.name.contains('.')
        ? document.name
        : '${document.name}.lua';
    final path = await obscured(() async {
      if (widget.pickSavePath != null) {
        return widget.pickSavePath!(suggested);
      }
      return (await files.getSaveLocation(
        suggestedName: suggested,
        initialDirectory: scriptsDirectory.path,
        confirmButtonText: 'Save script',
        acceptedTypeGroups: [
          const files.XTypeGroup(label: 'Lua script', extensions: ['lua']),
          if (showLuauSaveType)
            const files.XTypeGroup(label: 'Luau script', extensions: ['luau']),
          const files.XTypeGroup(label: 'Text file', extensions: ['txt']),
        ],
      ))?.path;
    });
    if (path == null || !mounted) return false;
    final saved = await c.saveDocumentToPath(document.id, path);
    if (saved && !renameOnSave) c.renameDocument(document.id, document.name);
    await refreshLocalFiles();
    return saved;
  }

  Future<void> save({bool saveAs = false}) async => savePickedScript();

  Future<void> clear() async {
    await flushEditor();
    if (!mounted) return;
    c.updateDocumentContent(c.activeDocumentId, '');
    if (monaco != null) {
      await monaco!.action('clear');
    } else {
      editorFocus.requestFocus();
    }
  }

  Future<void> newTab() async {
    await flushEditor();
    if (mounted) c.newDocument(name: 'Untitled Tab');
  }

  Future<void> select(String id) async {
    await flushEditor();
    if (mounted) c.selectDocument(id);
  }

  Future<void> execute() async {
    if (!widget.bridgeReady) return;
    await flushEditor();
    if (mounted) c.execute();
  }

  Future<void> backToOrion() async {
    await flushEditor();
    if (mounted) widget.onBackToOrion();
  }

  Directory get scriptsDirectory {
    final custom = preferences['scriptsDirectory'];
    if (custom is String && custom.isNotEmpty) return Directory(custom);
    return c.scriptsDirectory;
  }

  Future<void> refreshLocalFiles() async {
    try {
      final dir = scriptsDirectory;
      if (createScriptsDirectory) await dir.create(recursive: true);
      final files = await dir.exists()
          ? await dir
                .list()
                .where(
                  (f) =>
                      f is File &&
                      (!excludeHiddenScripts ||
                          !FilePaths.basename(f.path).startsWith('.')),
                )
                .cast<File>()
                .toList()
          : <File>[];
      files.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      if (mounted) setState(() => localFiles = files);
    } catch (_) {
      if (mounted) setState(() => localFiles = []);
    }
  }

  Future<void> openLocal(File file) async {
    await flushEditor();
    if (mounted) await importScript(file.path);
  }

  Future<void> openScriptsFolder() async {
    try {
      final dir = scriptsDirectory;
      await dir.create(recursive: true);
      await DesktopLauncher.openDirectory(dir);
    } catch (_) {}
  }

  Future<void> minimize() async {
    if (widget.nativeWindow) await windowManager.minimize();
  }

  Future<void> maximize() async {
    if (!widget.nativeWindow) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  void drag() {
    if (widget.nativeWindow) unawaited(windowManager.startDragging());
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => maximized = false);
  }

  @override
  void onWindowClose() async {
    try {
      await flushEditor();
    } catch (_) {}
    await c.flushPersistence();
    await c.closeBridge();
    await windowManager.destroy();
  }

  Future<void> closeWindow() async {
    if (widget.nativeWindow) {
      await windowManager.close();
    }
  }

  @override
  void dispose() {
    c.removeListener(_sync);
    editor.removeListener(_edited);
    monaco?.setObscured(false, owner: shellName);
    monaco?.removeListener(_nativeChanged);
    if (_ownsMonaco) monaco?.dispose();
    if (widget.nativeWindow) windowManager.removeListener(this);
    editor.dispose();
    editorFocus.dispose();
    super.dispose();
  }
}
