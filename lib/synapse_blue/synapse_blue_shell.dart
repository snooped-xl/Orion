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
import '../models/remote_script.dart';
import '../services/monaco_editor_service.dart';
import '../state/orion_controller.dart';
import '../models/synapse_studio_theme.dart';
import '../services/synapse_theme_catalog.dart';
import '../services/synapse_theme_studio_service.dart';
import '../widgets/synapse_theme_surface.dart';
import '../widgets/monaco_editor.dart';
import '../widgets/luau_syntax.dart';
import '../synapse_v3/v3_gists.dart';
import 'blue_controls.dart';
import 'blue_icon.dart';
import 'blue_intro.dart';
import 'blue_pages.dart';
import 'blue_theme.dart';

class SynapseBlueShell extends StatefulWidget {
  const SynapseBlueShell({
    super.key,
    required this.controller,
    required this.nativeWindow,
    required this.onBackToOrion,
    this.editorService,
    this.previewWindowId,
    this.bridgeReady = false,
    this.playIntro = true,
    this.onIntroCompleted,
    this.onSelectInterface,
  });
  final String? previewWindowId;
  final OrionController controller;
  final bool nativeWindow, bridgeReady, playIntro;
  final MonacoEditorService? editorService;
  final VoidCallback onBackToOrion;
  final VoidCallback? onIntroCompleted;
  final Future<void> Function(InterfacePreset)? onSelectInterface;
  @override
  State<SynapseBlueShell> createState() => SynapseBlueShellState();
}

class SynapseBlueShellState extends State<SynapseBlueShell>
    with TickerProviderStateMixin, WindowListener {
  final _editor = LuauSyntaxController(themeId: 'tomorrow-night-eighties');
  final _rename = TextEditingController();
  final _find = TextEditingController();
  final _listSearch = TextEditingController();
  final _expanded = <String>{'Local Filesystem', 'Bookmarks', 'Github Gists'};
  String? _loadingGist;
  List<String> stringsPref(String key) => preferences[key] is List
      ? (preferences[key] as List).whereType<String>().toList()
      : [];
  void setPref(String key, Object? value) =>
      c.setInterfacePreference(InterfacePreset.synapseBlue, key, value);
  final _editorFocus = FocusNode(debugLabel: 'Blue editor');
  final _renameFocus = FocusNode(debugLabel: 'Blue tab rename');
  final _findFocus = FocusNode(debugLabel: 'Blue find');
  final _rail = ScrollController();
  final _tabs = ScrollController();
  final _tabKeys = <String, GlobalKey>{};
  late final AnimationController _mainFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  )..addListener(_opacity);
  late final AnimationController _pageFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  )..addListener(_opacity);
  late final AnimationController _hintFade =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 360),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && _hover == null && mounted) {
          _monaco?.setObscured(false, owner: 'blue-nav-hover');
          setState(() {
            _visibleHint = null;
            _hoverPreview = null;
          });
        }
      });
  late final AnimationController _hintText = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final AnimationController _hoverDim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  )..addListener(_opacity);
  Uint8List? _hoverPreview;
  int? _visibleHint;
  int _hintContent = 0, _hintGeneration = 0;
  bool _hintExiting = false;
  MonacoEditorService? _monaco;
  bool _ownsMonaco = false, _syncing = false, _showFind = false;
  String _id = '', _findStatus = '';
  String? _renaming;
  int _page = 0;
  int? _hover;
  final _visited = <int>{0};
  OrionController get c => widget.controller;
  static const _studioPreset = InterfacePreset.synapseBlue;
  String get _studioWindow => switch (_page) {
    1 => 'scriptHub',
    2 => 'console',
    3 => 'settings',
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
        _studio.colors['shellBg'] ??
            SynapseThemeCatalog.current(c, _studioPreset).colors['shellBg'] ??
            SynapseThemeCatalog.defaults(_studioPreset).colors['shellBg']!,
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

  Map<String, Object?> get preferences =>
      c.getInterfacePreferences(InterfacePreset.synapseBlue);
  bool pref(String key, [bool fallback = false]) =>
      preferences[key] is bool ? preferences[key] as bool : fallback;
  String get family =>
      SynapseThemeCatalog.current(c, _studioPreset).fontFamily ??
      (preferences['uiFontFamily'] is String
          ? preferences['uiFontFamily'] as String
          : 'SynapseInter');
  String? get backgroundImage => null;
  double numberPref(String key, double fallback, double min, double max) =>
      ((preferences[key] is num
              ? (preferences[key] as num).toDouble()
              : fallback))
          .clamp(min, max);
  bool get integratedImage =>
      backgroundImage != null && preferences['backgroundLayer'] != 'above';
  BluePalette get palette =>
      BluePalette(SynapseThemeCatalog.colors(c, _studioPreset, _studioWindow));
  BluePalette _buttonPalette(String id, BluePalette base) {
    final e = _studio.elements[id];
    return BluePalette({
      ...base.overrides,
      if (e?.fill != null) 'editorControlBarButtonFrom': e!.fill,
      if (e?.fill != null) 'editorControlBarButtonTo': e!.fill,
      if (e?.fill != null)
        'editorControlBarHoverFrom': Color(
          e!.fill!,
        ).withValues(alpha: .85).toARGB32(),
      if (e?.fill != null) 'editorControlBarHoverTo': e!.fill,
      if (e?.fill != null) 'attachButtonFrom': e!.fill,
      if (e?.fill != null) 'attachButtonTo': e!.fill,
      if (e?.foreground != null) 'editorControlBarText': e!.foreground,
      if (e?.foreground != null) 'attachButtonText': e!.foreground,
      if (e?.border != null) 'editorControlBarBorder': e!.border,
    });
  }

  bool get reduced =>
      c.reducedMotion ||
      (mounted && MediaQuery.maybeOf(context)?.disableAnimations == true);
  static const destinations = [
    (
      'execution',
      'Execution',
      'Create and run scripts in the current',
      'instance.',
    ),
    (
      'hub',
      'Script Hub',
      'Execute pre-made scripts by the community',
      'and ScriptBlox',
    ),
    ('console', 'Console', 'Integrated Synapse console.', ''),
    (
      'settings',
      'Options',
      'Tweak various preferences that modify',
      'Synapse.',
    ),
    (
      'themes',
      'Theme Control Panel',
      'Customise your theming with precise and',
      'clear control',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _page = switch (widget.previewWindowId) {
      'scriptHub' => 1,
      'console' => 2,
      'settings' => 3,
      _ => 0,
    };
    _visited.add(_page);
    if (widget.editorService != null) {
      _monaco = widget.editorService;
    } else if (widget.nativeWindow &&
        (Platform.isLinux || Platform.isWindows)) {
      _ownsMonaco = true;
      _monaco = MonacoEditorService(
        onChange: (id, content) => c.updateDocumentContent(id, content),
        onShortcut: handleEditorShortcut,
      );
    }
    _monaco?.addListener(_nativeChanged);
    c.addListener(_sync);
    _editor.addListener(_edited);
    _sync();
    _pageFade.value = 1;
    _mainFade.value = widget.playIntro || c.reducedMotion ? 1 : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_monaco != null) unawaited(_monaco!.initialize());
      if (!widget.playIntro && !reduced) _mainFade.forward();
    });
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
  }

  void _nativeChanged() {
    if (mounted) setState(() {});
  }

  void _sync() {
    final document = c.activeDocument;
    if (document.id != _id || document.content != _editor.text) {
      _syncing = true;
      final changed = document.id != _id;
      _id = document.id;
      _editor.value = TextEditingValue(
        text: document.content,
        selection: TextSelection.collapsed(
          offset: changed
              ? 0
              : _editor.selection.baseOffset.clamp(0, document.content.length),
        ),
      );
      _syncing = false;
      if (changed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final tabContext = _tabKeys[document.id]?.currentContext;
          if (mounted && tabContext != null) {
            unawaited(
              Scrollable.ensureVisible(
                tabContext,
                alignment: .5,
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
              ),
            );
          }
        });
      }
    }
    if (mounted) setState(() {});
  }

  void _edited() {
    if (!_syncing) c.updateDocumentContent(_id, _editor.text);
  }

  void _opacity() {
    final main = const Cubic(.12, 0, .08, 1).transform(_mainFade.value);
    final page = const Cubic(0, 0, .22, 1).transform(_pageFade.value);
    _monaco?.setOpacity(
      main * page * (integratedImage ? 1 : _hoverDim.value),
      owner: 'synapse-blue',
    );
  }

  Future<void> flushEditor() async => _monaco?.flush();
  void setEditorObscured(bool value, {String owner = 'route'}) =>
      _monaco?.setObscured(value, owner: owner);
  void setEditorTransitioning(bool value) => _monaco?.setTransitioning(value);

  @override
  void dispose() {
    if (widget.nativeWindow) windowManager.removeListener(this);
    c.removeListener(_sync);
    _monaco?.removeListener(_nativeChanged);
    _monaco?.setOpacity(1, owner: 'synapse-blue');
    _monaco?.setOpacity(1, owner: 'blue-wallpaper');
    _monaco?.setObscured(false, owner: 'blue-nav-hover');
    if (_ownsMonaco) _monaco?.dispose();
    _mainFade.dispose();
    _pageFade.dispose();
    _hintFade.dispose();
    _hintText.dispose();
    _hoverDim.dispose();
    _editor.dispose();
    _rename.dispose();
    _find.dispose();
    _listSearch.dispose();
    _editorFocus.dispose();
    _renameFocus.dispose();
    _findFocus.dispose();
    _rail.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    try {
      await flushEditor();
      await c.companionWindows?.closeAll();
      await c.flushPersistence();
      if (mounted && widget.nativeWindow) {
        await c.closeBridge();
        await windowManager.destroy();
      }
    } on Object catch (error) {
      if (mounted) await _notice('Could not save the session: $error');
    }
  }

  void handleEditorShortcut(String name) {
    switch (name) {
      case 'show-editor':
        unawaited(_go(0));
      case 'new':
        unawaited(_new());
      case 'open':
        unawaited(_open());
      case 'save':
        unawaited(_save());
      case 'save-as':
        unawaited(_save(as: true));
      case 'execute':
        if (widget.bridgeReady) c.execute();
      case 'find':
        _requestFind();
      case 'replace':
        if (_monaco != null) {
          unawaited(_monaco!.action('replace'));
        } else {
          _requestFind();
        }
      case 'console':
        unawaited(_go(_page == 2 ? 0 : 2));
      case 'format':
        unawaited(_monaco?.action('format'));
      case 'escape':
        if (_renaming != null) {
          _cancelRename();
        } else if (_showFind) {
          setState(() => _showFind = false);
        }
    }
  }

  Future<void> _go(int page) async {
    if (page == 4) {
      await _themeStudio();
      return;
    }
    if (_page == page) return;
    await flushEditor();
    if (!mounted) return;
    setState(() {
      _page = page;
      _visited.add(page);
    });
    _monaco?.setActive(page == 0);
    if (reduced) {
      _pageFade.value = 1;
    } else {
      _pageFade.forward(from: 0);
    }
  }

  void _setHover(int? value) {
    if (_hover == value) return;
    final generation = ++_hintGeneration;
    final wasHidden = _visibleHint == null;
    setState(() {
      _hover = value;
    });
    final target = value == null || integratedImage ? 1.0 : .36;
    if (reduced) {
      _hoverDim.value = target;
    } else {
      _hoverDim.animateTo(
        target,
        duration: const Duration(milliseconds: 380),
        curve: const Cubic(.25, 0, .2, 1),
      );
    }
    if (value == null) {
      if (reduced) {
        _hintFade.value = 0;
        _monaco?.setObscured(false, owner: 'blue-nav-hover');
        setState(() {
          _visibleHint = null;
          _hoverPreview = null;
        });
      } else {
        _hintFade.reverse();
      }
      return;
    }
    if (wasHidden && _monaco != null && _page == 0 && _monaco!.ready) {
      unawaited(_captureHoverPreview(value, generation));
    } else {
      _showHoverHint(value, generation, wasHidden);
    }
  }

  Future<void> _captureHoverPreview(int value, int generation) async {
    Uint8List? preview;
    try {
      preview = await _monaco?.capturePreview();
    } on Object {
      // The local editor fallback remains available after a renderer failure.
    }
    if (!mounted || generation != _hintGeneration || _hover != value) return;
    _hoverPreview = _page == 0 ? preview : null;
    _showHoverHint(value, generation, true);
  }

  void _showHoverHint(int value, int generation, bool wasHidden) {
    setState(() => _visibleHint = value);
    _monaco?.setObscured(true, owner: 'blue-nav-hover');
    if (reduced) {
      _hintContent = value;
      _hintFade.value = _hintText.value = 1;
      return;
    }
    _hintFade.forward();
    if (wasHidden) {
      _hintContent = value;
      _hintExiting = false;
      _hintText.forward(from: 0);
    } else if (_hintContent != value) {
      _hintExiting = true;
      _hintText.reverse().then((_) {
        if (!mounted || generation != _hintGeneration || _hover == null) return;
        setState(() {
          _hintContent = value;
          _hintExiting = false;
        });
        _hintText.forward(from: 0);
      });
    }
  }

  Future<void> _select(String id) async {
    await flushEditor();
    if (mounted) c.selectDocument(id);
  }

  Future<void> _new() async {
    await flushEditor();
    if (!mounted) return;
    c.newDocument(
      name: c.documents.any((d) => d.name == 'Script')
          ? 'Script ${c.documents.length + 1}'
          : 'Script',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tabs.hasClients) {
        _tabs.jumpTo(_tabs.position.maxScrollExtent);
      }
    });
  }

  Future<void> _open() async {
    await flushEditor();
    if (!mounted) return;
    _monaco?.setObscured(true, owner: 'blue-file-dialog');
    try {
      await c.openFile();
    } finally {
      _monaco?.setObscured(false, owner: 'blue-file-dialog');
    }
  }

  Future<void> _executeFile() async {
    if (!widget.bridgeReady) return;
    await flushEditor();
    if (!mounted) return;
    await _monaco?.freezeForOverlay(owner: 'blue-file-dialog');
    try {
      final file = await files.openFile(
        acceptedTypeGroups: const [
          files.XTypeGroup(
            label: 'Lua script',
            extensions: ['lua', 'luau', 'txt'],
          ),
        ],
      );
      if (file != null) {
        final source = await file.readAsString();
        if (mounted) c.executeSource(source, name: file.name);
      }
    } on Object catch (error) {
      if (mounted) await _notice('Could not execute file: $error');
    } finally {
      _monaco?.setObscured(false, owner: 'blue-file-dialog');
    }
  }

  Future<void> _save({bool as = false}) async {
    await flushEditor();
    if (!mounted) return;
    _monaco?.setObscured(true, owner: 'blue-file-dialog');
    try {
      if (as) {
        await c.saveAs();
      } else {
        await c.saveDocument();
      }
    } finally {
      _monaco?.setObscured(false, owner: 'blue-file-dialog');
    }
  }

  Future<void> _clear({bool all = false}) async {
    await flushEditor();
    if (!mounted) return;
    if (pref('clearConfirmation', true) &&
        !await _confirm(all ? 'all' : 'current')) {
      return;
    }
    if (!mounted) return;
    if (all) {
      final keep = c.documents.first.id;
      for (final document in [...c.documents]) {
        if (document.id != keep) c.closeDocument(document.id);
      }
      c.selectDocument(keep);
      c.updateDocumentContent(keep, '');
    } else {
      c.updateDocumentContent(c.activeDocumentId, '');
    }
  }

  Future<void> _close(EditorDocument document) async {
    if (c.documents.length <= 1) return;
    await flushEditor();
    if (!mounted) return;
    if (pref('closeFileConfirmation', true) && !await _confirm('tab')) return;
    if (mounted) c.closeDocument(document.id);
  }

  Future<T?> _dialog<T>(Widget Function(BuildContext) builder) async {
    _monaco?.setObscured(true, owner: 'blue-dialog');
    try {
      return await showDialog<T>(
        context: context,
        barrierColor: Colors.black54,
        builder: builder,
      );
    } finally {
      _monaco?.setObscured(false, owner: 'blue-dialog');
    }
  }

  Future<bool> _confirm(String mode) async {
    final p = palette;
    final lines = switch (mode) {
      'all' => (
        'Are you sure you want to clear the editor?',
        'All open script tabs will be replaced with a single empty tab.',
      ),
      'tab' => (
        'Close this script tab?',
        'Unsaved changes in this tab will be lost.',
      ),
      _ => (
        'Are you sure you want to clear this tab?',
        'All unsaved changes in the current script will be lost!',
      ),
    };
    return await _dialog<bool>(
          (context) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540, maxHeight: 264),
              child: ColoredBox(
                color: p.color('confirmationTheme.panelBg'),
                child: Column(
                  children: [
                    SizedBox(height: 55, child: _brandBar(p, dialog: true)),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                          child: Column(
                            children: [
                              BlueIcon(
                                'warning',
                                width: 36,
                                height: 36,
                                color: p.color('confirmationTheme.iconStroke'),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Synapse Warning',
                                style: blueText(
                                  21,
                                  family: family,
                                  color: p.color(
                                    'confirmationTheme.titleColor',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                lines.$1,
                                textAlign: TextAlign.center,
                                style: blueText(16, family: family),
                              ),
                              Text(
                                lines.$2,
                                textAlign: TextAlign.center,
                                style: blueText(16, family: family),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  BlueButton(
                                    'No',
                                    palette: p,
                                    family: family,
                                    kind: 'no',
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                  ),
                                  const SizedBox(width: 12),
                                  BlueButton(
                                    'Yes',
                                    palette: p,
                                    family: family,
                                    kind: 'yes',
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<void> _notice(String message) async {
    await _dialog<void>(
      (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 55, child: _brandBar(palette, dialog: true)),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(message, style: blueText(13, family: family)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: BlueButton(
                  'Close',
                  palette: palette,
                  family: family,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _beginRename(EditorDocument document) {
    _rename.text = document.name;
    _rename.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _rename.text.length,
    );
    setState(() => _renaming = document.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _renameFocus.requestFocus();
    });
  }

  void _finishRename() {
    if (_renaming == null) return;
    c.renameDocument(_renaming!, _rename.text);
    setState(() => _renaming = null);
  }

  void _cancelRename() => setState(() => _renaming = null);
  Future<void> _tabMenu(EditorDocument document, Offset position) async {
    final box = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(position);
    _monaco?.setObscured(true, owner: 'blue-menu');
    String? selection;
    try {
      selection = await showMenu<String>(
        context: context,
        position: RelativeRect.fromSize(
          Rect.fromLTWH(local.dx, local.dy, 1, 1),
          box.size,
        ),
        color: const Color(0xff3d3d3d),
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Color(0xff5a5a5a)),
        ),
        menuPadding: const EdgeInsets.all(2),
        items: [
          PopupMenuItem(
            value: 'rename',
            height: 32,
            child: Text('Rename', style: blueText(13, family: family)),
          ),
          PopupMenuItem(
            value: 'close',
            enabled: c.documents.length > 1,
            height: 32,
            child: Text('Close', style: blueText(13, family: family)),
          ),
        ],
      );
    } finally {
      _monaco?.setObscured(false, owner: 'blue-menu');
    }
    if (!mounted) return;
    if (selection == 'rename') _beginRename(document);
    if (selection == 'close') await _close(document);
  }

  void _requestFind() {
    if (_monaco != null) {
      unawaited(_monaco!.action('find'));
      return;
    }
    setState(() => _showFind = true);
    _findFocus.requestFocus();
  }

  void _findNext() {
    final query = _find.text;
    if (query.isEmpty) return;
    var index = _editor.text.toLowerCase().indexOf(
      query.toLowerCase(),
      math.max(0, _editor.selection.end),
    );
    if (index < 0) {
      index = _editor.text.toLowerCase().indexOf(query.toLowerCase());
    }
    if (index >= 0) {
      _editor.selection = TextSelection(
        baseOffset: index,
        extentOffset: index + query.length,
      );
    }
    setState(() => _findStatus = index < 0 ? 'No matches' : 'Match found');
  }

  Future<void> _openRemote(RemoteScript script) async {
    await flushEditor();
    try {
      final source = await c.loadRemoteScript(script);
      if (!mounted) return;
      c.newDocument(name: script.title, content: source);
      await _go(0);
    } on Object catch (error) {
      if (mounted) await _notice('Could not load script source: $error');
    }
  }

  void _synchronizeNative(BluePalette p) {
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
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
              'shell': 'synapseBlue',
              'animateReveal': false,
              'editorThemeId':
                  preferences['editorThemeId'] ?? 'tomorrow-night-eighties',
              'fontSize': 13,
              'uiScale': c.uiScale,
              'wordWrap': pref('wordWrap'),
              'lineNumbers': true,
              'minimap': pref('minimapEnabled'),
              'diagnosticEnabled': false,
              'reducedMotion': reduced,
              'brightness': 'dark',
              'background': hex(
                p.color('surfaceElementsTheme.editorWorkAreaBackground'),
              ),
              'foreground': '#cccccc',
              'accent': '#3149e8',
              'muted': '#999999',
              'border': '#1e1e1e',
              ..._studioEditorOptions,
            },
          }) ??
          Future<void>.value(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    _synchronizeNative(p);
    _monaco?.setOpacity(
      integratedImage
          ? .88
          : backgroundImage != null
          ? 1 - numberPref('backgroundOpacity', 1, 0, .8)
          : 1,
      owner: 'blue-wallpaper',
    );
    final radius = pref('edgeCurveDefault') ? 7.0 : 0.0;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: _BlueTextScaler(numberPref('uiFontSizeStep', 0, -3, 3)),
      ),
      child: Theme(
        data: blueTheme(family, p),
        child: BlueEntrance(
          palette: p,
          play: widget.playIntro,
          reducedMotion: reduced,
          nativeWindow: widget.nativeWindow,
          resizable: pref('resizableWindow'),
          editorService: _monaco,
          family: family,
          cornerRadius: radius,
          targetSize: Size(
            SynapseThemeCatalog.current(
                  c,
                  _studioPreset,
                ).window('main').width ??
                714,
            SynapseThemeCatalog.current(
                  c,
                  _studioPreset,
                ).window('main').height ??
                393,
          ),
          onCompleted: () {
            _mainFade.value = 1;
            widget.onIntroCompleted?.call();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  control: true,
                ): () =>
                    handleEditorShortcut('new'),
                const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  control: true,
                ): () =>
                    handleEditorShortcut('open'),
                const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  control: true,
                ): () =>
                    handleEditorShortcut('save'),
                const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  control: true,
                  shift: true,
                ): () =>
                    handleEditorShortcut('save-as'),
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  control: true,
                ): () =>
                    handleEditorShortcut('execute'),
                const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  control: true,
                ): () =>
                    handleEditorShortcut('find'),
                const SingleActivator(LogicalKeyboardKey.f9): () =>
                    handleEditorShortcut('console'),
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    handleEditorShortcut('escape'),
              },
              child: Scaffold(
                backgroundColor: p.color('shellBg'),
                body: _surface(
                  AnimatedBuilder(
                    animation: _mainFade,
                    builder: (context, child) => Opacity(
                      opacity: const Cubic(
                        .12,
                        0,
                        .08,
                        1,
                      ).transform(_mainFade.value),
                      child: child,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children: [
                          Positioned(
                            left: 60,
                            top: 55,
                            right: 0,
                            bottom: 0,
                            child: AnimatedBuilder(
                              animation: Listenable.merge([
                                _pageFade,
                                _hoverDim,
                              ]),
                              builder: (context, child) => Opacity(
                                opacity:
                                    const Cubic(
                                      0,
                                      0,
                                      .22,
                                      1,
                                    ).transform(_pageFade.value) *
                                    (integratedImage ? .88 : _hoverDim.value),
                                child: child,
                              ),
                              child: _element(
                                'content',
                                IndexedStack(
                                  index: _page,
                                  children: [
                                    _editorPage(p),
                                    _visited.contains(1)
                                        ? _element(
                                            'scriptCards',
                                            BlueHubPage(
                                              controller: c,
                                              palette: p,
                                              family: family,
                                              onOpen: _openRemote,
                                              onOpenSource:
                                                  (name, source) async {
                                                    await flushEditor();
                                                    if (!mounted) return;
                                                    c.newDocument(
                                                      name: name,
                                                      content: source,
                                                    );
                                                    await _go(0);
                                                  },
                                              onModal: (value) =>
                                                  _monaco?.setObscured(
                                                    value,
                                                    owner: 'blue-hub-dialog',
                                                  ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                    _visited.contains(2)
                                        ? _element(
                                            'consoleOutput',
                                            BlueConsolePage(
                                              controller: c,
                                              palette: p,
                                              family: family,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                    _visited.contains(3)
                                        ? _element(
                                            'settingsControls',
                                            BlueSettingsPage(
                                              controller: c,
                                              palette: p,
                                              family: family,
                                              nativeWindow: widget.nativeWindow,
                                              onBackToOrion:
                                                  widget.onBackToOrion,
                                              onSelectInterface:
                                                  widget.onSelectInterface,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 55,
                            width: 60,
                            bottom: 0,
                            child: _element(
                              'sidebar',
                              ColoredBox(
                                color: p.color('sidebarBg'),
                                child: SingleChildScrollView(
                                  controller: _rail,
                                  child: Column(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < destinations.length;
                                        i++
                                      ) ...[
                                        if (i > 0) const SizedBox(height: 2),
                                        MouseRegion(
                                          onEnter: (_) => _setHover(i),
                                          onExit: (_) => _setHover(null),
                                          cursor: SystemMouseCursors.click,
                                          child: Semantics(
                                            label: destinations[i].$2,
                                            selected: _page == i,
                                            button: true,
                                            child: InkWell(
                                              key: ValueKey('blue-nav-$i'),
                                              onTap: () => unawaited(_go(i)),
                                              onFocusChange: (focused) =>
                                                  _setHover(focused ? i : null),
                                              splashFactory:
                                                  NoSplash.splashFactory,
                                              overlayColor:
                                                  const WidgetStatePropertyAll(
                                                    Colors.transparent,
                                                  ),
                                              child: ColoredBox(
                                                color: p.color(
                                                  _page == i
                                                      ? 'sidebarNavActiveBg'
                                                      : _hover == i
                                                      ? 'sidebarNavHoverBg'
                                                      : 'sidebarNavInactiveBg',
                                                ),
                                                child: BlueIcon(
                                                  destinations[i].$1,
                                                  color: p.color(
                                                    _hover == i
                                                        ? 'sidebarIconStrokeHover'
                                                        : _page == i
                                                        ? 'sidebarIconStrokeActive'
                                                        : 'sidebarIconStrokeInactive',
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: 55,
                            child: _element('titleBar', _brandBar(p)),
                          ),
                          if (_visibleHint != null)
                            AnimatedPositioned(
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 400),
                              curve: const Cubic(.25, 0, .2, 1),
                              left: 67,
                              top: math.max(
                                55,
                                math.min(
                                  constraints.maxHeight - 56,
                                  55 +
                                      _visibleHint! * 66 -
                                      (_rail.hasClients ? _rail.offset : 0),
                                ),
                              ),
                              width: 231,
                              child: IgnorePointer(
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([
                                    _hintFade,
                                    _hintText,
                                  ]),
                                  builder: (context, _) {
                                    final opacity = const Cubic(
                                      .25,
                                      0,
                                      .2,
                                      1,
                                    ).transform(_hintFade.value);
                                    final textOpacity = const Cubic(
                                      .25,
                                      0,
                                      .2,
                                      1,
                                    ).transform(_hintText.value);
                                    return Opacity(
                                      opacity: opacity,
                                      child: Transform.translate(
                                        offset: Offset(-14 * (1 - opacity), 0),
                                        child: Container(
                                          key: const ValueKey('blue-nav-hint'),
                                          constraints: const BoxConstraints(
                                            minHeight: 56,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                            gradient: p.gradient(
                                              'shellHoverPanelFrom',
                                              'shellHoverPanelTo',
                                            ),
                                          ),
                                          child: Opacity(
                                            opacity: textOpacity,
                                            child: Transform.translate(
                                              offset: Offset(
                                                0,
                                                (_hintExiting ? -4 : 5) *
                                                    (1 - textOpacity),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      6,
                                                      3,
                                                      6,
                                                      6,
                                                    ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      destinations[_hintContent]
                                                          .$2,
                                                      style: blueText(
                                                        13,
                                                        family: family,
                                                        weight: FontWeight.w900,
                                                        height: 1.42,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      destinations[_hintContent]
                                                          .$3,
                                                      style: blueText(
                                                        10,
                                                        family: family,
                                                        weight: FontWeight.w600,
                                                        height: 1.42,
                                                      ),
                                                    ),
                                                    if (destinations[_hintContent]
                                                        .$4
                                                        .isNotEmpty)
                                                      Text(
                                                        destinations[_hintContent]
                                                            .$4,
                                                        style: blueText(
                                                          10,
                                                          family: family,
                                                          weight:
                                                              FontWeight.w600,
                                                          height: 1.42,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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
        ),
      ),
    );
  }

  Widget _brandBar(BluePalette p, {bool dialog = false}) => Container(
    decoration: BoxDecoration(
      gradient: p.gradient(
        dialog ? 'confirmationTheme.topBarFrom' : 'topBarFrom',
        dialog ? 'confirmationTheme.topBarTo' : 'topBarTo',
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          offset: Offset(0, 8),
          blurRadius: 15.9,
        ),
      ],
    ),
    child: Stack(
      children: [
        if (widget.nativeWindow && !dialog)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () {
                if (pref('resizableWindow')) {
                  unawaited(
                    windowManager.isMaximized().then(
                      (max) => max
                          ? windowManager.unmaximize()
                          : windowManager.maximize(),
                    ),
                  );
                }
              },
            ),
          ),
        Positioned(
          left: 11,
          top: 9,
          width: 175,
          height: 37,
          child: IgnorePointer(
            child: _logo(
              Image.asset(
                'assets/synapse_blue/wordmark.png',
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ),
        if (!dialog)
          Positioned(
            right: 46,
            top: 7,
            width: 24,
            height: 22,
            child: _element(
              'clientsButton',
              Tooltip(
                message: 'Client manager',
                child: InkWell(
                  key: const ValueKey('blue-clients'),
                  borderRadius: BorderRadius.circular(3),
                  onTap: () => unawaited(
                    showBridgeClientManager(
                      context,
                      controller: c,
                      editorService: _monaco,
                    ),
                  ),
                  child: const Icon(
                    Icons.devices_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        if (!dialog)
          Positioned(
            right: 5,
            top: 9,
            width: 30,
            height: 9,
            child: Stack(
              children: [
                const BlueIcon('window', width: 30, height: 9),
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: 'Minimize',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (widget.nativeWindow) {
                                unawaited(windowManager.minimize());
                              }
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: Tooltip(
                          message: 'Close',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (widget.nativeWindow) {
                                unawaited(windowManager.close());
                              }
                            },
                          ),
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

  Widget _editorPage(BluePalette p) => ColoredBox(
    color: p.color('pageAreaBg'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 5, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 27.328125 + numberPref('uiFontSizeStep', 0, -3, 3) * 1.42,
            child: Text(
              'Execution',
              style: blueText(
                19.25,
                family: family,
                height: 1.42,
                weight: FontWeight.w300,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 26,
                        child: _element(
                          'tabs',
                          SingleChildScrollView(
                            controller: _tabs,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final document in c.documents) ...[
                                  GestureDetector(
                                    onTap: () =>
                                        unawaited(_select(document.id)),
                                    onDoubleTap: () => _beginRename(document),
                                    onSecondaryTapDown: (details) => _tabMenu(
                                      document,
                                      details.globalPosition,
                                    ),
                                    child: Container(
                                      key: _tabKeys.putIfAbsent(
                                        document.id,
                                        () => GlobalKey(
                                          debugLabel: 'Blue tab ${document.id}',
                                        ),
                                      ),
                                      height: 24,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      color: document.id == c.activeDocumentId
                                          ? const Color(0xff535353)
                                          : const Color(0xff474747),
                                      constraints: const BoxConstraints(
                                        maxWidth: 280,
                                      ),
                                      child: Center(
                                        widthFactor: 1,
                                        child: _renaming == document.id
                                            ? SizedBox(
                                                width: math.min(
                                                  250,
                                                  math.max(
                                                    40,
                                                    document.name.length * 7.0,
                                                  ),
                                                ),
                                                child: TextField(
                                                  key: const ValueKey(
                                                    'blue-tab-rename',
                                                  ),
                                                  controller: _rename,
                                                  focusNode: _renameFocus,
                                                  style: blueText(
                                                    13,
                                                    family: family,
                                                  ),
                                                  decoration:
                                                      const InputDecoration(
                                                        isDense: true,
                                                        border:
                                                            InputBorder.none,
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                      ),
                                                  onSubmitted: (_) =>
                                                      _finishRename(),
                                                  onTapOutside: (_) =>
                                                      _finishRename(),
                                                ),
                                              )
                                            : Text(
                                                document.name,
                                                maxLines: 1,
                                                key: ValueKey(
                                                  'blue-tab-${document.id}',
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                style: blueText(
                                                  13,
                                                  family: family,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                Tooltip(
                                  message: 'New script tab',
                                  child: GestureDetector(
                                    onTap: () => unawaited(_new()),
                                    child: Container(
                                      width: 17,
                                      height: 16,
                                      color: const Color(0xff69686b),
                                      child: const Center(
                                        child: Text(
                                          '+',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            height: 1,
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
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              top: -4,
                              right: 0,
                              bottom: 0,
                              child: _code(p),
                            ),
                            if (_showFind && _monaco == null)
                              Positioned(
                                top: 0,
                                right: 2,
                                left: 45,
                                child: Container(
                                  color: const Color(0xff333333),
                                  padding: const EdgeInsets.all(4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _find,
                                          focusNode: _findFocus,
                                          decoration: blueInput(
                                            p,
                                            hint: 'Find',
                                          ),
                                          style: blueText(11, family: family),
                                          onSubmitted: (_) => _findNext(),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _findNext,
                                        child: const Text('↓'),
                                      ),
                                      Tooltip(
                                        message: _findStatus,
                                        child: TextButton(
                                          onPressed: () =>
                                              setState(() => _showFind = false),
                                          child: const Text('×'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: pref('enhancedScriptListDefault')
                      ? math.min(197, MediaQuery.sizeOf(context).width * .27)
                      : 107,
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.color(
                        'surfaceElementsTheme.surfacePanelBackground',
                      ),
                      border: Border.all(
                        color: p.color(
                          'surfaceElementsTheme.surfacePanelBorder',
                        ),
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: _element('scriptList', _scriptList(p)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          _element(
            'actions',
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _element(
                        'executeButton',
                        BlueButton(
                          'Execute',
                          palette: _buttonPalette('executeButton', p),
                          family: family,
                          onPressed: widget.bridgeReady
                              ? () => c.execute()
                              : null,
                        ),
                      ),
                      _element(
                        'clearButton',
                        BlueButton(
                          'Clear',
                          palette: _buttonPalette('clearButton', p),
                          family: family,
                          onPressed: () => unawaited(
                            _clear(
                              all: HardwareKeyboard.instance.isShiftPressed,
                            ),
                          ),
                        ),
                      ),
                      _element(
                        'openButton',
                        BlueButton(
                          'Open File',
                          palette: _buttonPalette('openButton', p),
                          family: family,
                          onPressed: () => unawaited(_open()),
                        ),
                      ),
                      _element(
                        'executeFileButton',
                        BlueButton(
                          'Execute File',
                          palette: _buttonPalette('executeFileButton', p),
                          family: family,
                          onPressed: widget.bridgeReady
                              ? () => unawaited(_executeFile())
                              : null,
                        ),
                      ),
                      _element(
                        'saveButton',
                        BlueButton(
                          'Save File',
                          palette: _buttonPalette('saveButton', p),
                          family: family,
                          onPressed: () => unawaited(_save()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                _element(
                  'attachButton',
                  BlueButton(
                    'Attach',
                    width: 109,
                    palette: _buttonPalette('attachButton', p),
                    family: family,
                    kind: 'attach',
                    onPressed: () => unawaited(
                      showBridgeClientManager(
                        context,
                        controller: c,
                        editorService: _monaco,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _scriptList(BluePalette p) {
    Widget row(
      String title,
      VoidCallback onTap, {
      VoidCallback? trailing,
      String glyph = '☆',
    }) => Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: blueText(
                  10,
                  family: family,
                  color: p.color('surfaceElementsTheme.surfaceListText'),
                ),
              ),
            ),
          ),
        ),
        if (trailing != null)
          SizedBox(
            width: 22,
            child: InkWell(
              onTap: trailing,
              child: Center(
                child: Text(glyph, style: blueText(11, family: family)),
              ),
            ),
          ),
      ],
    );
    final fileDocs = c.documents.where((d) => d.filePath != null).toList();
    if (!pref('enhancedScriptListDefault')) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        children: [
          if (fileDocs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text.rich(
                const TextSpan(
                  text: 'Add ',
                  children: [
                    TextSpan(
                      text: '.lua',
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                        height: 1.2375,
                      ),
                    ),
                    TextSpan(text: ' files to '),
                    TextSpan(
                      text: 'scripts',
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                        height: 1.2375,
                      ),
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
                style: blueText(
                  9,
                  family: family,
                  height: 1.375,
                  color: p
                      .color('surfaceElementsTheme.surfaceListText')
                      .withValues(alpha: .7),
                ),
              ),
            ),
          for (final d in fileDocs) row(d.name, () => unawaited(_select(d.id))),
        ],
      );
    }
    final bookmarks = stringsPref('bookmarkedDocumentIds');
    final gists = stringsPref('gistUrls');
    final query = _listSearch.text.toLowerCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 24,
            child: TextField(
              key: const ValueKey('blue-list-search'),
              controller: _listSearch,
              style: blueText(10, family: family),
              decoration: blueInput(p, hint: 'Search scripts'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final section in [
                'Local Filesystem',
                'Bookmarks',
                'Github Gists',
              ]) ...[
                row(
                  '${_expanded.contains(section) ? '⌄' : '›'} $section',
                  () => setState(
                    () => _expanded.contains(section)
                        ? _expanded.remove(section)
                        : _expanded.add(section),
                  ),
                ),
                if (_expanded.contains(section)) ...[
                  if (section == 'Github Gists') ...[
                    row('+ Add Gist', () => unawaited(_addGist())),
                    for (final url in gists.where(
                      (v) => V3Gists.title(
                        Uri.parse(v),
                      ).toLowerCase().contains(query),
                    ))
                      row(
                        _loadingGist == url
                            ? 'Loading…'
                            : V3Gists.title(Uri.parse(url)),
                        () => unawaited(_loadGist(url)),
                        trailing: () => setPref(
                          'gistUrls',
                          gists.where((v) => v != url).toList(),
                        ),
                        glyph: '×',
                      ),
                  ] else
                    for (final d in c.documents.where(
                      (d) =>
                          (section == 'Bookmarks'
                              ? bookmarks.contains(d.id)
                              : d.filePath != null) &&
                          d.name.toLowerCase().contains(query),
                    ))
                      row(
                        d.name,
                        () => unawaited(_select(d.id)),
                        trailing: () => setPref(
                          'bookmarkedDocumentIds',
                          bookmarks.contains(d.id)
                              ? bookmarks.where((id) => id != d.id).toList()
                              : [...bookmarks, d.id],
                        ),
                        glyph: bookmarks.contains(d.id) ? '★' : '☆',
                      ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addGist() async {
    final text = TextEditingController();
    final url = await _dialog<String>(
      (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 350,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Add Gist URL', style: blueText(16, family: family)),
                const SizedBox(height: 10),
                TextField(
                  controller: text,
                  autofocus: true,
                  style: blueText(12, family: family),
                  decoration: blueInput(palette, hint: 'https://…'),
                  onSubmitted: (value) {
                    if (V3Gists.parse(value) != null) {
                      Navigator.pop(context, value.trim());
                    }
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    BlueButton(
                      'Cancel',
                      palette: palette,
                      family: family,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                    BlueButton(
                      'Add',
                      palette: palette,
                      family: family,
                      onPressed: () {
                        if (V3Gists.parse(text.text) != null) {
                          Navigator.pop(context, text.text.trim());
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    text.dispose();
    if (mounted && url != null) {
      setPref('gistUrls', {...stringsPref('gistUrls'), url}.toList());
    }
  }

  Future<void> _loadGist(String url) async {
    if (_loadingGist != null) return;
    setState(() => _loadingGist = url);
    try {
      final source = await V3Gists.load(Uri.parse(url));
      await flushEditor();
      if (mounted) {
        c.newDocument(
          name: '${V3Gists.title(Uri.parse(url))}.lua',
          content: source,
        );
      }
    } on Object catch (error) {
      if (mounted) await _notice('Could not load gist: $error');
    } finally {
      if (mounted) setState(() => _loadingGist = null);
    }
  }

  Widget _code(BluePalette p) {
    _editor.useTheme(
      preferences['editorThemeId'] as String? ?? 'tomorrow-night-eighties',
      foreground: SynapseThemeCatalog.hasStudio(c, _studioPreset)
          ? Color(_studio.elements['editor']?.foreground ?? 0xffcccccc)
          : null,
    );
    final native = _monaco;
    return _element(
      'editor',
      MediaQuery.withNoTextScaling(
        child: ColoredBox(
          key: const ValueKey('blue-editor-body'),
          color: p.color('surfaceElementsTheme.editorWorkAreaBackground'),
          child: native != null && _visibleHint == null
              ? MonacoEditor(
                  service: native,
                  active: _page == 0,
                  backgroundColor: p.color(
                    'surfaceElementsTheme.editorWorkAreaBackground',
                  ),
                  foregroundColor: const Color(0xffcccccc),
                  fallback: LuauCodePreview(
                    controller: _editor,
                    gutterWidth: 42,
                    gutterColor: const Color(0xff999999),
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 13,
                      height: 18 / 13,
                      color: Color(
                        _studio.elements['editor']?.foreground ?? 0xffcccccc,
                      ),
                    ),
                  ),
                )
              : native != null && _hoverPreview != null
              ? IgnorePointer(
                  child: Image.memory(
                    _hoverPreview!,
                    key: const ValueKey('blue-editor-hover-preview'),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.none,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 42,
                      color: const Color(0xff252525),
                      padding: const EdgeInsets.only(right: 5),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (
                              var i = 1;
                              i <= c.activeDocument.lineCount;
                              i++
                            )
                              SizedBox(
                                height: 18,
                                child: Text(
                                  '$i',
                                  style: const TextStyle(
                                    fontFamily: 'JetBrainsMono',
                                    fontSize: 13,
                                    color: Color(0xff999999),
                                    height: 18 / 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('code-editor'),
                        controller: _editor,
                        focusNode: _editorFocus,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        readOnly: native != null,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 13,
                          height: 18 / 13,
                          color: Color(
                            _studio.elements['editor']?.foreground ??
                                0xffcccccc,
                          ),
                        ),
                        cursorColor: const Color(0xffcccccc),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _BlueTextScaler extends TextScaler {
  const _BlueTextScaler(this.step);
  final double step;
  @override
  double scale(double fontSize) => math.max(5, fontSize + step);
  @override
  double get textScaleFactor => scale(16) / 16;
  @override
  bool operator ==(Object other) =>
      other is _BlueTextScaler && other.step == step;
  @override
  int get hashCode => step.hashCode;
}
