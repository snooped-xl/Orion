import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';

import '../widgets/bridge_client_manager.dart';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/orion_models.dart';
import '../models/interface_preset.dart';
import '../models/companion_window.dart';
import '../models/remote_script.dart';
import '../services/desktop_close_service.dart';
import '../services/monaco_editor_service.dart';
import '../state/orion_controller.dart';
import '../models/synapse_studio_theme.dart';
import '../services/synapse_theme_catalog.dart';
import '../services/synapse_theme_studio_service.dart';
import '../widgets/synapse_theme_surface.dart';
import '../widgets/monaco_editor.dart';
import '../widgets/luau_syntax.dart';
import 'synapse_v3_pages.dart';
import 'synapse_v3_theme.dart';
import 'v3_editor_layout.dart';
import 'v3_icon.dart';
import 'v3_gists.dart';

/// A separate V3 shell: original top navigation, editor, script list and chrome.
class SynapseV3Shell extends StatefulWidget {
  const SynapseV3Shell({
    super.key,
    required this.controller,
    required this.nativeWindow,
    required this.onBackToOrion,
    this.editorService,
    this.previewWindowId,
    this.bridgeReady = false,
  });
  final String? previewWindowId;
  final OrionController controller;
  final bool nativeWindow;
  final VoidCallback onBackToOrion;
  final MonacoEditorService? editorService;
  final bool bridgeReady;
  @override
  State<SynapseV3Shell> createState() => SynapseV3ShellState();
}

class SynapseV3ShellState extends State<SynapseV3Shell> with WindowListener {
  final _editor = LuauSyntaxController();
  final _editorFocus = FocusNode(debugLabel: 'Synapse V3 editor');
  final _shellFocus = FocusNode(debugLabel: 'Synapse V3 shortcuts');
  final _findFocus = FocusNode();
  final _find = TextEditingController();
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _tabs = ScrollController();
  MonacoEditorService? _monaco;
  bool _ownsMonaco = false;
  String _documentId = '';
  String _query = '';
  String _findMessage = '';
  bool _syncing = false;
  bool _showFind = false;
  bool _consoleOpen = false;
  bool _localOpen = false;
  bool _bookmarksOpen = false;
  bool _gistsOpen = false;
  String? _loadingGist;
  final _bookmarks = <String>{};
  double _consoleHeight = 160;
  double _workAreaHeight = 328;
  int _page = 0;
  final _visitedPages = <int>{0};
  OrionController get c => widget.controller;
  static const _studioPreset = InterfacePreset.synapseV3;
  String get _studioWindow => switch (_page) {
    1 => 'settings',
    2 => 'scriptHub',
    _ => 'main',
  };
  SynapseStudioWindow get _studio =>
      SynapseThemeCatalog.current(c, _studioPreset).window(_studioWindow);
  Widget _element(String id, Widget child) => SynapseThemeElement(
    controller: c,
    preset: _studioPreset,
    windowId: _studioWindow,
    elementId: id,
    child: child,
  );
  Widget _surface(Widget child) => SynapseThemeSurface(
    controller: c,
    preset: _studioPreset,
    windowId: _studioWindow,
    child: child,
  );
  Widget _logo(Widget child) => SynapseThemeLogo(
    controller: c,
    preset: _studioPreset,
    windowId: _studioWindow,
    child: child,
  );
  Future<void> _themeStudio() async {
    await flushEditor();
    if (!mounted) return;
    await openSynapseThemeStudio(
      context,
      controller: c,
      preset: _studioPreset,
      editorService: _monaco,
    );
  }

  Map<String, Object?> get _studioEditorOptions {
    final image = _studio.elements['editor']?.image ?? _studio.background;
    final editor = _studio.elements['editor'];
    String hex(int color) =>
        '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    return {
      'studioWindowBackground': hex(
        _studio.colors['shell.windowBg'] ??
            SynapseThemeCatalog.current(
              c,
              _studioPreset,
            ).colors['shell.windowBg'] ??
            SynapseThemeCatalog.defaults(
              _studioPreset,
            ).colors['shell.windowBg']!,
      ),
      'studioBackgroundImage': image?.data,
      'studioBackgroundLocal': _studio.elements['editor']?.image != null,
      'studioBackgroundOpacity': image?.opacity,
      'studioBackgroundFit': image?.fit,
      'studioOverlayImage': _studio.overlay?.data,
      'studioOverlayOpacity': _studio.overlay?.opacity,
      'studioOverlayFit': _studio.overlay?.fit,
      'studioEditorTransparent': image != null,
      'studioEditorEnabled': SynapseThemeCatalog.hasStudio(c, _studioPreset),
      'studioEditorOpacity':
          (editor?.opacity ?? 1) * (_studio.elements['content']?.opacity ?? 1),
      'studioEditorRadius': editor?.radius,
      if (editor?.fill != null) 'background': hex(editor!.fill!),
      if (editor?.foreground != null) 'foreground': hex(editor!.foreground!),
    };
  }

  bool get _activeDetached =>
      c.detachedDocumentIds.contains(c.activeDocumentId);
  V3Colors get colors => V3Colors.fromColors(
    background: c.synapsePreferences.themeBackground,
    accent: c.synapsePreferences.themeAccent,
    legacyFramework: c.synapsePreferences.themePreset == 'legacyFramework',
    overrides: SynapseThemeCatalog.colors(c, _studioPreset, _studioWindow),
  );
  TextStyle _type(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) => V3Type.text(
    size,
    color: color ?? Colors.white,
    weight: weight,
    height: height,
    family:
        SynapseThemeCatalog.current(c, _studioPreset).fontFamily ??
        c.synapsePreferences.uiFontFamily,
  );

  @override
  void initState() {
    super.initState();
    _page = switch (widget.previewWindowId) {
      'settings' => 1,
      'scriptHub' => 2,
      _ => 0,
    };
    _visitedPages.add(_page);
    if (widget.editorService != null) {
      _monaco = widget.editorService!..addListener(_nativeChanged);
    } else if (widget.nativeWindow &&
        (Platform.isLinux || Platform.isWindows)) {
      _ownsMonaco = true;
      _monaco = MonacoEditorService(
        onChange: (id, content) => c.updateDocumentContent(id, content),
        onShortcut: _shortcut,
      )..addListener(_nativeChanged);
    }
    _sync();
    _editor.addListener(_edited);
    c.addListener(_sync);
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
  }

  @override
  void dispose() {
    if (widget.nativeWindow) windowManager.removeListener(this);
    c.removeListener(_sync);
    _editor.removeListener(_edited);
    _monaco?.removeListener(_nativeChanged);
    if (_ownsMonaco) _monaco?.dispose();
    _editor.dispose();
    _editorFocus.dispose();
    _shellFocus.dispose();
    _findFocus.dispose();
    _find.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _sync() {
    _consoleHeight =
        SynapseThemeCatalog.current(
          c,
          _studioPreset,
        ).window('console').elements['consoleOutput']?.height ??
        c.synapsePreferences.consoleHeight;
    _consoleOpen =
        (c.getInterfacePreferences(InterfacePreset.synapseV3)['consoleOpen'] ==
            true ||
        widget.previewWindowId == 'console');
    _monaco?.setActive(_page == 0 && !_activeDetached);
    _bookmarks
      ..clear()
      ..addAll(c.synapsePreferences.bookmarkedDocumentIds);
    final document = c.activeDocument;
    if (document.id != _documentId || document.content != _editor.text) {
      _syncing = true;
      final changedDocument = document.id != _documentId;
      _documentId = document.id;
      _editor.value = TextEditingValue(
        text: document.content,
        selection: TextSelection.collapsed(
          offset: changedDocument
              ? 0
              : _editor.selection.baseOffset.clamp(0, document.content.length),
        ),
      );
      _syncing = false;
    }
    if (mounted) setState(() {});
  }

  void _edited() {
    if (!_syncing) c.updateDocumentContent(_documentId, _editor.text);
    if (mounted) setState(() {});
  }

  void _nativeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> flushEditor() async => _monaco?.flush();
  void setEditorObscured(bool value, {String owner = 'route'}) =>
      _monaco?.setObscured(value, owner: owner);
  void setEditorTransitioning(bool value) => _monaco?.setTransitioning(value);
  void handleEditorShortcut(String name) => _shortcut(name);
  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  void onWindowClose() async {
    await DesktopCloseService.closeApp(
      controller: c,
      nativeWindow: widget.nativeWindow,
      flushEditor: flushEditor,
    );
  }

  void _message(String message) {
    if (!mounted) return;
    unawaited(
      _dialog<void>(
        title: 'Synapse V3',
        content: Text(message, style: _type(12)),
        actions: (ctx) => [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }

  Future<void> _navigate(int page) async {
    if (page == 3) {
      await _themeStudio();
      return;
    }
    if (_page == page) return;
    await flushEditor();
    if (!mounted) return;
    _monaco?.setActive(page == 0 && !_activeDetached);
    _shellFocus.requestFocus();
    setState(() {
      _page = page;
      _visitedPages.add(page);
    });
  }

  Future<void> _new() async {
    await flushEditor();
    if (!mounted) return;
    c.newDocument(content: c.synapsePreferences.defaultTabContent);
    await _navigate(0);
    _editorFocus.requestFocus();
  }

  Future<void> _select(String id) async {
    await flushEditor();
    if (mounted) c.selectDocument(id);
  }

  Future<void> _open() async {
    await flushEditor();
    try {
      await _monaco?.freezeForOverlay(owner: 'native-dialog');
      if (!mounted) return;
      await c.openFile();
      if (mounted) await _navigate(0);
    } catch (error) {
      _message('Could not open file: $error');
    } finally {
      setEditorObscured(false, owner: 'native-dialog');
    }
  }

  Future<void> _save({bool saveAs = false, String? id}) async {
    final documentId = id ?? c.activeDocumentId;
    await flushEditor();
    final document = c.documents.where((d) => d.id == documentId).firstOrNull;
    if (document == null) return;
    final picker = saveAs || document.filePath == null;
    try {
      if (picker) await _monaco?.freezeForOverlay(owner: 'native-dialog');
      if (!mounted) return;
      if (saveAs) {
        await c.saveAs(documentId);
      } else {
        await c.saveDocument(documentId);
      }
    } finally {
      if (picker) setEditorObscured(false, owner: 'native-dialog');
    }
  }

  Future<void> _execute() async {
    if (!widget.bridgeReady) {
      await showBridgeClientManager(
        context,
        controller: c,
        editorService: _monaco,
      );
      return;
    }
    await flushEditor();
    c.execute();
  }

  Future<void> _executeFile() async {
    if (!widget.bridgeReady) return;
    try {
      await _monaco?.freezeForOverlay(owner: 'native-dialog');
      if (!mounted) return;
      final file = await files.openFile(
        acceptedTypeGroups: const [
          files.XTypeGroup(
            label: 'Lua scripts',
            extensions: ['lua', 'luau', 'txt'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final source = await file.readAsString();
      if (!mounted) return;
      c.execute(source: source, name: file.name);
    } catch (error) {
      _message('Could not read script: $error');
    } finally {
      setEditorObscured(false, owner: 'native-dialog');
    }
  }

  Future<void> _openRemote(RemoteScript script) async {
    await flushEditor();
    await c.openRemoteScript(script);
    if (mounted) await _navigate(0);
  }

  void _shortcut(String name) {
    switch (name) {
      case 'new':
        unawaited(_new());
      case 'open':
        unawaited(_open());
      case 'save':
        unawaited(_save());
      case 'saveAs':
      case 'save-as':
        unawaited(_save(saveAs: true));
      case 'execute':
        unawaited(_execute());
      case 'find':
        requestFind();
      case 'console':
        _toggleConsole();
      case 'escape':
        if (_showFind) {
          setState(() => _showFind = false);
          _editorFocus.requestFocus();
        }
    }
  }

  void _toggleConsole() {
    final next = !_consoleOpen;
    if (next) {
      final target = (_workAreaHeight * .45).roundToDouble();
      final height = math
          .max(_consoleHeight, target)
          .clamp(64.0, math.max(64.0, _workAreaHeight - 96));
      if (height != _consoleHeight) {
        c.updateSynapsePreferences(consoleHeight: height.toDouble());
      }
    }
    c.setInterfacePreference(InterfacePreset.synapseV3, 'consoleOpen', next);
  }

  Future<T?> _dialog<T>({
    required String title,
    required Widget content,
    required List<Widget> Function(BuildContext) actions,
  }) async {
    try {
      await _monaco?.freezeForOverlay(owner: 'v3-dialog');
      if (!mounted) return null;
      return await showDialog<T>(
        context: context,
        builder: (ctx) => Theme(
          data: V3ThemeData.theme(
            colors.accent,
            colors.background,
            legacyFramework:
                c.synapsePreferences.themePreset == 'legacyFramework',
            overrides: SynapseThemeCatalog.colors(
              c,
              _studioPreset,
              _studioWindow,
            ),
            family:
                SynapseThemeCatalog.current(c, _studioPreset).fontFamily ??
                c.synapsePreferences.uiFontFamily,
          ),
          child: AlertDialog(
            backgroundColor: colors.tabActive,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: colors.border),
            ),
            title: Text(title, style: _type(16)),
            content: content,
            actions: actions(ctx),
          ),
        ),
      );
    } finally {
      setEditorObscured(false, owner: 'v3-dialog');
    }
  }

  Future<void> _rename(EditorDocument document) async {
    final name = await _inputPopup(initial: document.name);
    if (name != null && mounted) c.renameDocument(document.id, name);
  }

  Future<String?> _inputPopup({String initial = '', bool gist = false}) async {
    final input = TextEditingController(text: initial);
    String? name;
    try {
      await _monaco?.freezeForOverlay(owner: 'v3-dialog');
      if (!mounted) return null;
      name = await showDialog<String>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 384,
            height: 203,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF131312),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF808080)),
                    ),
                  ),
                ),
                Positioned(
                  left: 1,
                  right: 1,
                  top: 1,
                  height: 137,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF212120),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(7),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: gist ? 10 : 19,
                  top: gist ? 14 : 22,
                  child: V3Icon(gist ? 'github24' : 'edit20Regular', size: 20),
                ),
                Positioned(
                  left: 50,
                  top: 17,
                  child: Text(
                    gist ? 'Add GitHub Gist' : 'Rename tab',
                    style: _type(20, color: Colors.white),
                  ),
                ),
                Positioned(
                  left: 50,
                  top: gist ? 50 : 54,
                  right: 12,
                  child: Text(
                    gist
                        ? 'Paste a raw link — updates when you reopen or refresh.'
                        : 'Input the new tab name below.',
                    style: _type(
                      gist ? 11 : 16,
                      color: gist ? const Color(0xFFB3B3B3) : Colors.white,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 9,
                  top: 92,
                  height: 37,
                  child: TextField(
                    key: ValueKey(
                      gist ? 'v3-gist-url-input' : 'v3-rename-input',
                    ),
                    controller: input,
                    autofocus: true,
                    onSubmitted: (value) {
                      if (!gist || V3Gists.parse(value) != null) {
                        Navigator.pop(ctx, value);
                      }
                    },
                    style: _type(14, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: gist
                          ? 'Place a URL to a raw .lua script here'
                          : 'New tab name...',
                      hintStyle: _type(14, color: const Color(0xFF8D8D8D)),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF2D2D2D),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 240,
                  top: 154,
                  width: 50,
                  height: 32,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: input,
                    builder: (_, value, _) => _popupButton(
                      'Ok',
                      !gist || V3Gists.parse(value.text) != null
                          ? () => Navigator.pop(ctx, input.text)
                          : null,
                    ),
                  ),
                ),
                Positioned(
                  left: 298,
                  top: 154,
                  width: 77,
                  height: 32,
                  child: _popupButton('Cancel', () => Navigator.pop(ctx)),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      setEditorObscured(false, owner: 'v3-dialog');
      WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    }
    return name;
  }

  Widget _popupButton(String label, VoidCallback? onPressed) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      backgroundColor: const Color(0xFF373737),
      foregroundColor: const Color(0xFFB3B3B3),
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0xFF3F3F3F)),
      ),
      textStyle: _type(14),
    ),
    child: Text(label),
  );

  Future<void> _close(EditorDocument original) async {
    await flushEditor();
    if (!mounted) return;
    final document = c.documents.where((d) => d.id == original.id).firstOrNull;
    if (document == null) return;
    if (document.isDirty) {
      final result = await _dialog<String>(
        title: 'Save changes?',
        content: Text(
          '${document.name} has unsaved changes.',
          style: _type(12),
        ),
        actions: (ctx) => [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save'),
          ),
        ],
      );
      if (result == 'save') {
        try {
          await _monaco?.freezeForOverlay(owner: 'native-dialog');
          if (!mounted) return;
          if (!await c.saveDocument(document.id)) return;
        } finally {
          setEditorObscured(false, owner: 'native-dialog');
        }
      } else if (result != 'discard') {
        return;
      }
    }
    if (mounted) c.closeDocument(document.id);
  }

  Future<void> _clear() async {
    await flushEditor();
    if (!mounted) return;
    if (HardwareKeyboard.instance.isShiftPressed) {
      final previousIds = c.documents.map((document) => document.id).toList();
      c.newDocument(content: c.synapsePreferences.defaultTabContent);
      for (final id in previousIds) {
        c.closeDocument(id);
      }
      return;
    }
    if (_monaco != null) {
      await _monaco!.action('clear');
      await flushEditor();
    } else {
      _editor.clear();
      _editorFocus.requestFocus();
    }
  }

  Future<void> _paste() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text == null || !mounted) return;
    if (_monaco != null) {
      await _monaco!.action('paste', text: text);
    } else {
      final selection = _editor.selection;
      final start = selection.isValid ? selection.start : _editor.text.length;
      final end = selection.isValid ? selection.end : start;
      _editor.value = TextEditingValue(
        text: _editor.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length),
      );
      _editorFocus.requestFocus();
    }
  }

  void requestFind() {
    if (_activeDetached) return;
    if (_monaco != null) {
      unawaited(_monaco!.action('find'));
    } else {
      setState(() => _showFind = true);
      _findFocus.requestFocus();
    }
  }

  void _nextMatch() {
    final term = _find.text.toLowerCase();
    if (term.isEmpty) return;
    final source = _editor.text.toLowerCase();
    var position = source.indexOf(
      term,
      _editor.selection.end.clamp(0, source.length),
    );
    if (position < 0) position = source.indexOf(term);
    setState(() => _findMessage = position < 0 ? 'No matches' : 'Match found');
    if (position >= 0) {
      _editor.selection = TextSelection(
        baseOffset: position,
        extentOffset: position + term.length,
      );
      if (_vertical.hasClients) {
        final line = source.substring(0, position).split('\n').length - 1;
        _vertical.jumpTo(
          (line * 23.0).clamp(0, _vertical.position.maxScrollExtent),
        );
      }
    }
  }

  void _indent() {
    final selection = _editor.selection;
    if (!selection.isValid) return;
    _editor.value = TextEditingValue(
      text: _editor.text.replaceRange(selection.start, selection.end, '    '),
      selection: TextSelection.collapsed(offset: selection.start + 4),
    );
  }

  void _synchronizeNative(V3Colors palette) {
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    unawaited(
      _monaco?.synchronize({
            'documents': [
              for (final document in c.documents)
                {
                  'id': document.id,
                  'name': document.name,
                  'content': document.content,
                },
            ],
            'activeId': c.activeDocumentId,
            'options': {
              'shell': 'synapseV3',
              'diagnosticEnabled': false,
              'fontSize': c.editorFontSize,
              'uiScale': c.uiScale,
              'wordWrap': c.wordWrap,
              'lineNumbers': c.showLineNumbers,
              'minimap': c.synapsePreferences.minimap,
              'reducedMotion':
                  c.reducedMotion || MediaQuery.disableAnimationsOf(context),
              'brightness': 'dark',
              'background': hex(palette.editor),
              'foreground': hex(palette.text),
              'accent': hex(palette.accent),
              'muted': hex(palette.muted),
              'border': hex(palette.border),
              ..._studioEditorOptions,
            },
          }) ??
          Future<void>.value(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.previewWindowId == 'console') {
      final palette = colors;
      return SynapseThemeSurface(
        controller: c,
        preset: _studioPreset,
        windowId: 'console',
        child: Theme(
          data: V3ThemeData.theme(
            palette.accent,
            palette.background,
            overrides: SynapseThemeCatalog.colors(c, _studioPreset, 'console'),
            family:
                SynapseThemeCatalog.current(c, _studioPreset).fontFamily ??
                c.synapsePreferences.uiFontFamily,
          ),
          child: SynapseThemeElement(
            controller: c,
            preset: _studioPreset,
            windowId: 'console',
            elementId: 'consoleOutput',
            child: SynapseV3Console(controller: c, compactButtons: true),
          ),
        ),
      );
    }
    final palette = colors;
    _synchronizeNative(palette);
    final radius = BorderRadius.circular(c.synapsePreferences.cornerRadius);
    return ClipRRect(
      borderRadius: radius,
      child: Theme(
        data: V3ThemeData.theme(
          palette.accent,
          palette.background,
          legacyFramework:
              c.synapsePreferences.themePreset == 'legacyFramework',
          overrides: SynapseThemeCatalog.colors(
            c,
            _studioPreset,
            _studioWindow,
          ),
          family:
              SynapseThemeCatalog.current(c, _studioPreset).fontFamily ??
              c.synapsePreferences.uiFontFamily,
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
            const SingleActivator(
              LogicalKeyboardKey.enter,
              control: true,
            ): () =>
                unawaited(_execute()),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                requestFind,
            const SingleActivator(LogicalKeyboardKey.f9): _toggleConsole,
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _shortcut('escape'),
          },
          child: Focus(
            focusNode: _shellFocus,
            autofocus: true,
            child: Scaffold(
              backgroundColor: palette.background,
              body: _surface(
                LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      Positioned.fill(
                        child: IndexedStack(
                          index: _page,
                          children: [
                            _editorPage(palette, constraints.maxWidth),
                            if (_visitedPages.contains(1))
                              Padding(
                                padding: const EdgeInsets.only(top: 44),
                                child: _element(
                                  'content',
                                  _element(
                                    'settingsControls',
                                    SynapseV3SettingsPage(
                                      controller: c,
                                      nativeWindow: widget.nativeWindow,
                                      onBackToOrion: widget.onBackToOrion,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            if (_visitedPages.contains(2))
                              Padding(
                                padding: const EdgeInsets.only(top: 44),
                                child: _element(
                                  'content',
                                  _element(
                                    'scriptCards',
                                    SynapseV3ScriptHubPage(
                                      controller: c,
                                      onOpenScript: _openRemote,
                                      bridgeReady: widget.bridgeReady,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                      _topBar(palette, constraints.maxWidth),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              border: Border.all(
                                color: c.synapsePreferences.color(
                                  'shell.shellBorder',
                                  fallback: const Color(0xFF4B4D4C),
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
        ),
      ),
    );
  }

  Widget _topBar(V3Colors palette, double width) => Positioned(
    left: 0,
    top: 0,
    right: 0,
    height: 44,
    child: _element(
      'titleBar',
      ColoredBox(
        color: palette.topBar,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.nativeWindow
                    ? (_) => windowManager.startDragging()
                    : null,
                onDoubleTap: widget.nativeWindow ? _toggleMaximize : null,
              ),
            ),
            Positioned(
              left: 9,
              top: 8,
              width: 105,
              height: 26,
              child: _logo(
                Image.asset(
                  'assets/synapse_v3/v3-logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              left: (width - 108) / 2,
              top: 8,
              width: 108,
              height: 27,
              child: Row(
                children: [
                  for (final entry in const [
                    ('Editor', 'windowConsole20Filled'),
                    ('Settings', 'settings20Filled'),
                    ('Script Hub', 'globe20Filled'),
                    ('Theme', 'paintBrush20Filled'),
                  ].indexed)
                    Tooltip(
                      message: entry.$2.$1,
                      child: SizedBox(
                        width: 27,
                        height: 27,
                        child: InkWell(
                          onTap: () => _navigate(entry.$1),
                          splashFactory: NoSplash.splashFactory,
                          overlayColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: _page == entry.$1 ? 3.3 : 3.5,
                                top: _page == entry.$1 ? 1.3 : 1.5,
                                child: V3Icon(
                                  entry.$2.$2,
                                  size: _page == entry.$1 ? 20.4 : 20,
                                  color: palette.text,
                                ),
                              ),
                              if (_page == entry.$1)
                                Positioned(
                                  left: 3.75,
                                  right: 3.75,
                                  bottom: 0,
                                  height: 1.1,
                                  child: ColoredBox(
                                    color: palette.navUnderline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              width: 106,
              height: 44,
              child: Stack(
                children: [
                  _windowButton('Minimize', 0, () => windowManager.minimize()),
                  _windowButton('Maximize', 1, _toggleMaximize),
                  _windowButton('Close', 2, onWindowClose),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _windowButton(String tooltip, int glyph, VoidCallback onTap) =>
      Positioned(
        right: const [72.0, 37.0, 5.0][glyph],
        top: 9,
        width: 30,
        height: 30,
        child: _V3WindowControl(
          tooltip: tooltip,
          glyph: glyph,
          onTap: widget.nativeWindow ? onTap : null,
        ),
      );

  Widget _editorPage(V3Colors palette, double width) {
    // Original metrics at the reference size; compact chrome keeps all actions
    // accessible when desktop scaling reduces the available logical viewport.
    final showList = c.synapsePreferences.showScriptList && width >= 700;
    final rightInset = showList ? 200.0 : 0.0;
    final editorWidth = width - rightInset;
    final layout = V3EditorLayout(
      compactTabs: c.synapsePreferences.compactTabs,
      compactButtons: c.synapsePreferences.compactButtons || editorWidth < 610,
    );
    return _element(
      'content',
      Stack(
        children: [
          Positioned(
            left: 0,
            right: rightInset + (showList ? 3 : 0),
            top: layout.tabTop,
            height: layout.tabHeight,
            child: _tabBar(palette, layout),
          ),
          Positioned(
            left: 1,
            right: rightInset,
            top: layout.editorTop,
            bottom: layout.actionHeight,
            child: ColoredBox(
              color: palette.editor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _workAreaHeight = constraints.maxHeight;
                  final consoleHeight = _consoleHeight
                      .clamp(64.0, math.max(64.0, constraints.maxHeight - 96))
                      .toDouble();
                  return Column(
                    children: [
                      if (_showFind && _monaco == null) _findBar(palette),
                      Expanded(
                        key: const ValueKey('v3-editor-body'),
                        child: _element('editor', _codeArea(palette)),
                      ),
                      if (_consoleOpen)
                        SizedBox(
                          height: consoleHeight,
                          child: _element(
                            'content',
                            SynapseThemeSurface(
                              controller: c,
                              preset: _studioPreset,
                              windowId: 'console',
                              child: Theme(
                                data: V3ThemeData.theme(
                                  palette.accent,
                                  palette.background,
                                  overrides: SynapseThemeCatalog.colors(
                                    c,
                                    _studioPreset,
                                    'console',
                                  ),
                                  family:
                                      SynapseThemeCatalog.current(
                                        c,
                                        _studioPreset,
                                      ).fontFamily ??
                                      c.synapsePreferences.uiFontFamily,
                                ),
                                child: SynapseThemeElement(
                                  controller: c,
                                  preset: _studioPreset,
                                  windowId: 'console',
                                  elementId: 'consoleOutput',
                                  child: SynapseV3Console(
                                    controller: c,
                                    compactButtons: layout.compactButtons,
                                    onResize: (delta) =>
                                        c.updateSynapsePreferences(
                                          consoleHeight:
                                              (_consoleHeight - delta)
                                                  .clamp(
                                                    64.0,
                                                    math.max(
                                                      64.0,
                                                      constraints.maxHeight -
                                                          96,
                                                    ),
                                                  )
                                                  .toDouble(),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          // Source depth treatment is a narrow shadow, without card outlines.
          Positioned(
            left: 0,
            right: rightInset,
            top: layout.editorTop - 2,
            height: 6,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x59000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          if (showList)
            Positioned(
              right: 0,
              width: 197,
              top: layout.tabTop,
              bottom: 0,
              child: _element('scriptList', _scriptList(palette)),
            ),
          Positioned(
            left: 0,
            right: rightInset,
            bottom: 0,
            height: layout.actionHeight,
            child: _actionBar(palette, layout),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(V3Colors palette, V3EditorLayout layout) => _element(
    'tabs',
    ColoredBox(
      color: palette.tabBar,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _tabs,
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    for (final document in c.documents.where(
                      (document) =>
                          !c.detachedDocumentIds.contains(document.id),
                    )) ...[
                      _tab(document, palette, layout),
                      SizedBox(width: layout.tabGap),
                    ],
                    _iconButton(
                      'New script',
                      'add20Regular',
                      _new,
                      palette,
                      size: 12,
                      hitSize: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tab(
    EditorDocument document,
    V3Colors palette,
    V3EditorLayout layout,
  ) => GestureDetector(
    onSecondaryTapDown: (details) => _tabMenu(document, details.globalPosition),
    child: Container(
      key: ValueKey('v3-tab-${document.id}'),
      width: layout.tabWidth,
      height: layout.tabHeight,
      decoration: BoxDecoration(
        color: document.id == c.activeDocumentId
            ? palette.tabActive
            : palette.tabInactive,
        borderRadius: BorderRadius.circular(layout.tabRadius),
      ),
      child: InkWell(
        onTap: () => _select(document.id),
        child: Stack(
          children: [
            Positioned(
              left: layout.compactTabs ? 6 : 8,
              top: layout.compactTabs ? 5 : 9,
              child: V3Icon(
                'textAsterisk20Filled',
                size: layout.compactTabs ? 11 : 13,
                color: palette.tabText,
              ),
            ),
            Positioned(
              left: layout.compactTabs ? 24 : 31,
              right: layout.compactTabs ? 20 : 25,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  document.name,
                  overflow: TextOverflow.ellipsis,
                  style: _type(layout.tabFontSize, color: palette.tabText),
                ),
              ),
            ),
            Positioned(
              right: layout.compactTabs ? 2 : 4,
              top: 0,
              bottom: 0,
              child: _iconButton(
                'Close ${document.name}',
                'dismiss20Regular',
                () => _close(document),
                palette,
                size: layout.compactTabs ? 9 : 11,
                hitSize: 20,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _tabMenu(EditorDocument document, Offset globalPosition) async {
    String? result;
    try {
      await _monaco?.freezeForOverlay(owner: 'v3-menu');
      if (!mounted) return;
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final position = overlay.globalToLocal(globalPosition);
      result = await showMenu<String>(
        context: context,
        color: colors.tabActive,
        position: RelativeRect.fromRect(
          position & const Size(1, 1),
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem(
            value: 'undock',
            height: 32,
            enabled:
                c.companionWindows != null &&
                !c.companionWindows!.isChildWindow,
            child: Text('Undock', style: _type(16)),
          ),
          PopupMenuItem(
            value: 'duplicate',
            height: 32,
            child: Text('Duplicate', style: _type(16)),
          ),
          const PopupMenuDivider(),
          for (final action in const [
            ('rename', 'Rename'),
            ('saveAs', 'Save as…'),
            ('paste', 'Paste'),
            ('close', 'Close'),
          ])
            PopupMenuItem(
              value: action.$1,
              height: 28,
              child: Text(action.$2, style: _type(12)),
            ),
        ],
      );
    } finally {
      setEditorObscured(false, owner: 'v3-menu');
    }
    if (!mounted) return;
    switch (result) {
      case 'undock':
        await flushEditor();
        await c.companionWindows?.open(
          CompanionWindowKind.synapseV3Editor,
          documentId: document.id,
        );
      case 'duplicate':
        await flushEditor();
        final current = c.documents
            .where((doc) => doc.id == document.id)
            .firstOrNull;
        if (current != null) {
          c.newDocument(
            name: '${current.name} (Copy)',
            content: current.content,
          );
        }
      case 'rename':
        await _rename(document);
      case 'saveAs':
        await _save(saveAs: true, id: document.id);
      case 'paste':
        await _select(document.id);
        await _paste();
      case 'close':
        await _close(document);
    }
  }

  Widget _actionBar(V3Colors palette, V3EditorLayout layout) => _element(
    'actions',
    ColoredBox(
      color: palette.actionBar,
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 10, layout.buttonBottom),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final action in [
              (
                'Execute',
                'play20Filled',
                'Execute script · Ctrl Enter',
                _execute,
              ),
              ('Clear', 'eraser20Filled', 'Clear script', _clear),
              ('Open', 'documentArrowUp20Filled', 'Open file · Ctrl O', _open),
              ('Execute', 'settings20Filled', 'Execute file', _executeFile),
              ('Save', 'save20Filled', 'Save file · Ctrl S', () => _save()),
            ].indexed) ...[
              if (action.$1 > 0) SizedBox(width: layout.buttonGap),
              _element(
                const [
                  'executeButton',
                  'clearButton',
                  'openButton',
                  'executeFileButton',
                  'saveButton',
                ][action.$1],
                _actionButton(
                  action.$2.$1,
                  action.$2.$2,
                  action.$2.$3,
                  action.$2.$4,
                  palette,
                  layout,
                  disabled: action.$1 == 0 || action.$1 == 3
                      ? !widget.bridgeReady
                      : false,
                ),
              ),
            ],
            const Spacer(),
            _element(
              'clientsButton',
              Tooltip(
                message: 'Client manager',
                child: SizedBox(
                  width: layout.utilitySize,
                  height: layout.utilitySize,
                  child: InkWell(
                    key: const ValueKey('v3-clients'),
                    onTap: () => unawaited(
                      showBridgeClientManager(
                        context,
                        controller: c,
                        editorService: _monaco,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: Icon(
                      Icons.devices_rounded,
                      size: layout.utilitySize - 3,
                      color: palette.text,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: layout.utilityGap),
            _element(
              'attachButton',
              _iconButton(
                c.bridgeConnected
                    ? 'Orion Bridge connected'
                    : 'Connect Orion Bridge',
                'plugDisconnected20Filled',
                () => unawaited(
                  showBridgeClientManager(
                    context,
                    controller: c,
                    editorService: _monaco,
                  ),
                ),
                palette,
                size: layout.utilitySize,
                color: c.bridgeConnected
                    ? palette.accent
                    : palette.attachDisconnected,
                hitSize: layout.utilitySize,
              ),
            ),
            SizedBox(width: layout.utilityGap),
            _iconButton(
              _consoleOpen ? 'Hide console' : 'Show console',
              'windowConsole20Filled',
              _toggleConsole,
              palette,
              size: layout.utilitySize,
              hitSize: layout.utilitySize,
            ),
            SizedBox(width: layout.utilityGap),
            _iconButton(
              'Find in editor (Ctrl+F)',
              'searchSquare20Regular',
              requestFind,
              palette,
              size: layout.utilitySize,
              hitSize: layout.utilitySize,
              disabled: _activeDetached,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _actionButton(
    String label,
    String icon,
    String tooltip,
    VoidCallback onTap,
    V3Colors palette,
    V3EditorLayout layout, {
    bool disabled = false,
  }) {
    final id = tooltip == 'Execute file'
        ? 'executeFileButton'
        : switch (label) {
            'Execute' => 'executeButton',
            'Clear' => 'clearButton',
            'Open' => 'openButton',
            _ => 'saveButton',
          };
    final element = _studio.elements[id];
    final hasImage =
        element?.image?.isValid == true && element!.image!.opacity > 0;
    final fill = hasImage
        ? Colors.transparent
        : element?.fill == null
        ? palette.button
        : Color(element!.fill!);
    final foreground = element?.foreground == null
        ? palette.buttonText
        : Color(element!.foreground!);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: layout.buttonWidth,
        height: layout.buttonHeight,
        child: TextButton(
          style:
              TextButton.styleFrom(
                backgroundColor: hasImage
                    ? Colors.transparent
                    : disabled
                    ? palette.buttonDisabled
                    : fill,
                foregroundColor: disabled
                    ? palette.buttonDisabledText
                    : foreground,
                disabledForegroundColor: palette.buttonDisabledText,
                disabledBackgroundColor: hasImage
                    ? Colors.transparent
                    : palette.buttonDisabled,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(element?.radius ?? 4),
                  side: BorderSide(
                    color: element?.border == null
                        ? palette.buttonBorder
                        : Color(element!.border!),
                  ),
                ),
                textStyle: _type(layout.buttonFontSize),
              ).copyWith(
                overlayColor: WidgetStatePropertyAll(
                  disabled ? Colors.transparent : palette.buttonHover,
                ),
                mouseCursor: WidgetStatePropertyAll(
                  disabled
                      ? SystemMouseCursors.forbidden
                      : SystemMouseCursors.click,
                ),
              ),
          onPressed: disabled ? null : onTap,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                V3Icon(
                  icon,
                  size: layout.buttonIconSize,
                  color: disabled
                      ? palette.buttonDisabledIcon
                      : element?.foreground == null
                      ? palette.buttonIcon
                      : foreground,
                ),
                SizedBox(width: layout.compactButtons ? 3 : 4),
                Text(
                  label,
                  style: _type(layout.buttonFontSize, color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(
    String tooltip,
    String icon,
    VoidCallback onTap,
    V3Colors palette, {
    double size = 16,
    double hitSize = 24,
    Color? color,
    bool disabled = false,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: hitSize,
      height: hitSize,
      child: Semantics(
        button: true,
        enabled: !disabled,
        child: InkWell(
          onTap: disabled ? () {} : onTap,
          mouseCursor: disabled
              ? SystemMouseCursors.forbidden
              : SystemMouseCursors.click,
          child: Center(
            child: V3Icon(
              icon,
              size: size,
              color: disabled
                  ? palette.buttonDisabledIcon
                  : color ?? palette.text,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _scriptList(V3Colors palette) {
    final documents = c.documents
        .where(
          (d) =>
              d.filePath != null &&
              d.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return ColoredBox(
      color: palette.background,
      child: Column(
        children: [
          SizedBox(
            height: 31,
            child: TextField(
              key: const ValueKey('v3-script-search'),
              onChanged: (value) => setState(() => _query = value),
              style: _type(11, color: palette.text),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: _type(11, color: palette.searchPlaceholder),
                filled: true,
                fillColor: palette.search,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(8),
                  child: V3Icon(
                    'search20Regular',
                    size: 16,
                    color: palette.sectionIcon,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: 31,
                  height: 31,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _sectionHeader(
                    'Local Filesystem',
                    'hardDrive20Filled',
                    _localOpen,
                    () => setState(() => _localOpen = !_localOpen),
                    palette,
                  ),
                  if (_localOpen) ...[
                    for (final document in documents)
                      _scriptRow(document, palette),
                    if (documents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'No local scripts yet. Open or save a file.',
                          style: _type(11, color: palette.rowMuted),
                        ),
                      ),
                  ],
                  _sectionHeader(
                    'Bookmarks',
                    'bookmark20Filled',
                    _bookmarksOpen,
                    () => setState(() => _bookmarksOpen = !_bookmarksOpen),
                    palette,
                  ),
                  if (_bookmarksOpen) ...[
                    for (final document in documents.where(
                      (d) => _bookmarks.contains(d.id),
                    ))
                      _scriptRow(document, palette),
                    for (final url in c.synapsePreferences.gistUrls.where(
                      (url) =>
                          _bookmarks.contains(url) &&
                          V3Gists.title(
                            Uri.parse(url),
                          ).toLowerCase().contains(_query.toLowerCase()),
                    ))
                      _gistRow(url, palette),
                    if (!documents.any((d) => _bookmarks.contains(d.id)) &&
                        !c.synapsePreferences.gistUrls.any(_bookmarks.contains))
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'No bookmarked scripts',
                          style: _type(11, color: palette.muted),
                        ),
                      ),
                  ],
                  _sectionHeader(
                    'Github Gists',
                    'github24',
                    _gistsOpen,
                    () => setState(() => _gistsOpen = !_gistsOpen),
                    palette,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _iconButton(
                          'Add gist URL',
                          'add20Regular',
                          _addGist,
                          palette,
                          size: 16,
                          hitSize: 18,
                        ),
                        _iconButton(
                          'Refresh active gist',
                          'arrowClockwise20Filled',
                          _refreshGist,
                          palette,
                          size: 14,
                          hitSize: 18,
                        ),
                      ],
                    ),
                  ),
                  if (_gistsOpen) ...[
                    for (final url in c.synapsePreferences.gistUrls.where(
                      (url) => V3Gists.title(
                        Uri.parse(url),
                      ).toLowerCase().contains(_query.toLowerCase()),
                    ))
                      _gistRow(url, palette),
                    if (c.synapsePreferences.gistUrls.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'No gists yet. Click + and paste a raw .lua URL.',
                          style: _type(11, color: palette.rowMuted),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    String icon,
    bool expanded,
    VoidCallback onTap,
    V3Colors palette, {
    Widget? trailing,
  }) {
    final section = title == 'Local Filesystem'
        ? 'localFilesystem'
        : title == 'Bookmarks'
        ? 'bookmarks'
        : 'githubGists';
    final prefix = 'scriptList.sections.$section';
    return Container(
      height: 29,
      decoration: BoxDecoration(
        color: palette.sectionHeader,
        border: Border(
          bottom: BorderSide(color: palette.token('$prefix.borderColor')),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, right: 2),
          child: Row(
            children: [
              Transform.rotate(
                angle: expanded ? 0 : -math.pi / 2,
                child: V3Icon(
                  'chevronDown20Regular',
                  size: 10,
                  color: palette.token('$prefix.iconColor'),
                ),
              ),
              const SizedBox(width: 2),
              V3Icon(icon, size: 16, color: palette.token('$prefix.iconColor')),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  title,
                  style: _type(16, color: palette.token('$prefix.labelText')),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  void _toggleBookmark(String id) {
    final bookmarks = {..._bookmarks};
    if (!bookmarks.add(id)) bookmarks.remove(id);
    c.updateSynapsePreferences(bookmarkedDocumentIds: bookmarks.toList());
  }

  Future<void> _executeDocument(String id) async {
    if (!widget.bridgeReady) return;
    await flushEditor();
    if (!mounted) return;
    final document = c.documents
        .where((document) => document.id == id)
        .firstOrNull;
    if (document == null) return;
    c.execute(source: document.content, name: document.name);
  }

  Future<void> _addGist() async {
    final value = await _inputPopup(gist: true);
    if (!mounted || value == null) return;
    final uri = V3Gists.parse(value);
    if (uri == null) return;
    c.updateSynapsePreferences(
      gistUrls: {...c.synapsePreferences.gistUrls, uri.toString()}.toList(),
    );
    setState(() => _gistsOpen = true);
  }

  Future<void> _loadGist(
    String url, {
    bool execute = false,
    bool refresh = false,
  }) async {
    if (execute && !widget.bridgeReady) return;
    if (_loadingGist != null) return;
    final targetId = c.activeDocumentId;
    setState(() => _loadingGist = url);
    try {
      final body = await V3Gists.load(Uri.parse(url));
      if (!mounted) return;
      if (execute) {
        c.execute(source: body, name: V3Gists.title(Uri.parse(url)));
      } else {
        await flushEditor();
        if (!mounted) return;
        final bindings = {...c.synapsePreferences.gistDocumentUrls};
        final existingId = refresh
            ? targetId
            : bindings.entries
                  .where(
                    (entry) =>
                        entry.value == url &&
                        c.documents.any((doc) => doc.id == entry.key),
                  )
                  .firstOrNull
                  ?.key;
        if (existingId != null &&
            c.documents.any((doc) => doc.id == existingId)) {
          c.updateDocumentContent(existingId, body);
          c.selectDocument(existingId);
        } else {
          final document = c.newDocument(
            name: '${V3Gists.title(Uri.parse(url))}.lua',
            content: body,
          );
          bindings[document.id] = url;
          c.updateSynapsePreferences(gistDocumentUrls: bindings);
        }
      }
    } catch (error) {
      _message('Could not fetch gist: $error');
    } finally {
      if (mounted) setState(() => _loadingGist = null);
    }
  }

  void _refreshGist() {
    final url = c.synapsePreferences.gistDocumentUrls[c.activeDocumentId];
    if (url == null) {
      _message('Open a gist tab before refreshing.');
      return;
    }
    unawaited(_loadGist(url, refresh: true));
  }

  Widget _gistRow(String url, V3Colors palette) {
    final title = V3Gists.title(Uri.parse(url));
    return SizedBox(
      height: 26,
      child: InkWell(
        onTap: () => _loadGist(url),
        hoverColor: palette.rowHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              V3Icon('github24', size: 16, color: palette.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: _type(12, color: palette.rowText),
                ),
              ),
              if (_loadingGist == url)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else ...[
                _iconButton(
                  'Bookmark $title',
                  'bookmark20Filled',
                  () => _toggleBookmark(url),
                  palette,
                  size: 12,
                  hitSize: 18,
                  color: _bookmarks.contains(url)
                      ? palette.text
                      : palette.muted,
                ),
                _iconButton(
                  'Execute gist $title',
                  'play20Filled',
                  () => _loadGist(url, execute: true),
                  palette,
                  size: 14,
                  hitSize: 18,
                ),
                _iconButton(
                  'Remove gist $title',
                  'dismiss20Regular',
                  () {
                    c.updateSynapsePreferences(
                      gistUrls: c.synapsePreferences.gistUrls
                          .where((value) => value != url)
                          .toList(),
                      bookmarkedDocumentIds: _bookmarks
                          .where((value) => value != url)
                          .toList(),
                    );
                  },
                  palette,
                  size: 11,
                  hitSize: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _scriptRow(EditorDocument document, V3Colors palette) => SizedBox(
    height: 26,
    child: InkWell(
      hoverColor: palette.rowHover,
      onTap: () => _select(document.id),
      onDoubleTap: () => _rename(document),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            V3Icon('document20Regular', size: 16, color: palette.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                document.name,
                overflow: TextOverflow.ellipsis,
                style: _type(12, color: palette.rowText),
              ),
            ),
            _iconButton(
              'Bookmark ${document.name}',
              'bookmark20Filled',
              () => _toggleBookmark(document.id),
              palette,
              size: 12,
              hitSize: 18,
              disabled: !widget.bridgeReady,
              color: _bookmarks.contains(document.id)
                  ? palette.text
                  : palette.muted,
            ),
            _iconButton(
              'Execute ${document.name}',
              'play20Filled',
              () => _executeDocument(document.id),
              palette,
              size: 14,
              hitSize: 18,
              disabled: !widget.bridgeReady,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _findBar(V3Colors palette) => SizedBox(
    height: 40,
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _find,
            focusNode: _findFocus,
            onSubmitted: (_) => _nextMatch(),
            style: _type(12),
            decoration: const InputDecoration(
              hintText: 'Find in script…',
              isDense: true,
            ),
          ),
        ),
        Text(_findMessage, style: _type(10, color: palette.muted)),
        _iconButton('Next match', 'chevronDown20Regular', _nextMatch, palette),
        _iconButton(
          'Close find',
          'dismiss20Regular',
          () => setState(() => _showFind = false),
          palette,
        ),
      ],
    ),
  );

  Widget _codeArea(V3Colors palette) {
    _editor.useTheme(
      'synapse-v3',
      foreground: SynapseThemeCatalog.hasStudio(c, _studioPreset)
          ? Color(
              _studio.elements['editor']?.foreground ?? palette.text.toARGB32(),
            )
          : null,
    );
    if (_activeDetached) {
      return Center(
        child: Text(
          'This tab is open in a separate window.',
          style: _type(14, color: const Color(0xff9a9a9a)),
        ),
      );
    }
    if (_monaco != null) {
      return MonacoEditor(
        service: _monaco!,
        active: _page == 0,
        backgroundColor: palette.editor,
        foregroundColor: palette.tabText,
        fallback: LuauCodePreview(
          controller: _editor,
          gutterWidth: 45,
          gutterColor: palette.muted,
          showLineNumbers: c.showLineNumbers,
          wordWrap: c.wordWrap,
          padding: const EdgeInsets.only(top: 16),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: c.editorFontSize,
            height: 23 / c.editorFontSize,
            color: Color(
              _studio.elements['editor']?.foreground ?? palette.text.toARGB32(),
            ),
          ),
        ),
      );
    }
    final lines = _editor.text.split('\n');
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final longest = lines.fold(
            0,
            (length, line) => math.max(length, line.length),
          );
          final gutter = c.showLineNumbers ? 45.0 : 8.0;
          final width = c.wordWrap
              ? constraints.maxWidth - gutter
              : math.max(
                  constraints.maxWidth - gutter,
                  longest * c.editorFontSize * .65 + 36,
                );
          final style = TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: c.editorFontSize,
            color: _studio.elements['editor']?.foreground == null
                ? palette.text
                : Color(_studio.elements['editor']!.foreground!),
            height: 23 / c.editorFontSize,
          );
          return SingleChildScrollView(
            controller: _vertical,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: gutter,
                  child: c.showLineNumbers
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16, right: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var index = 0; index < lines.length; index++)
                                SizedBox(
                                  height: 23,
                                  child: Text(
                                    '${index + 1}',
                                    style: style.copyWith(color: palette.muted),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.tab):
                              _indent,
                        },
                        child: TextField(
                          key: const ValueKey('code-editor'),
                          controller: _editor,
                          focusNode: _editorFocus,
                          maxLines: null,
                          minLines: math.max(
                            1,
                            (constraints.maxHeight / 23).floor(),
                          ),
                          style: style,
                          cursorColor: palette.text,
                          autocorrect: false,
                          enableSuggestions: false,
                          spellCheckConfiguration:
                              const SpellCheckConfiguration.disabled(),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.fromLTRB(0, 16, 16, 16),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _V3WindowControl extends StatefulWidget {
  const _V3WindowControl({
    required this.tooltip,
    required this.glyph,
    this.onTap,
  });
  final String tooltip;
  final int glyph;
  final VoidCallback? onTap;
  @override
  State<_V3WindowControl> createState() => _V3WindowControlState();
}

class _V3WindowControlState extends State<_V3WindowControl> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: Opacity(
            opacity: _hover ? .8 : 1,
            child: SizedBox(
              width: 10,
              height: 10,
              child: CustomPaint(painter: _WindowGlyph(widget.glyph)),
            ),
          ),
        ),
      ),
    ),
  );
}

class _WindowGlyph extends CustomPainter {
  const _WindowGlyph(this.glyph);
  final int glyph;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = glyph == 0 ? 1.3 : 1.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (glyph == 0) {
      canvas.drawLine(const Offset(0, 5.25), const Offset(10, 5.25), paint);
    } else if (glyph == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 10, 10),
          const Radius.circular(1.25),
        ),
        paint,
      );
    } else {
      canvas.drawLine(Offset.zero, const Offset(10, 10), paint);
      canvas.drawLine(const Offset(0, 10), const Offset(10, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_WindowGlyph oldDelegate) => oldDelegate.glyph != glyph;
}
