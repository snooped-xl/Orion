import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../models/interface_preset.dart';
import '../models/companion_window.dart';
import '../models/orion_models.dart';
import '../services/desktop_close_service.dart';
import '../services/monaco_editor_service.dart';
import '../services/desktop_launcher.dart';
import '../services/native_window_service.dart';
import '../state/orion_controller.dart';
import '../models/synapse_studio_theme.dart';
import '../services/synapse_theme_catalog.dart';
import '../services/synapse_theme_studio_service.dart';
import '../widgets/synapse_theme_surface.dart';
import '../widgets/monaco_editor.dart';
import '../widgets/luau_syntax.dart';
import '../widgets/bridge_client_manager.dart';
import '../synapse_v3/v3_gists.dart';
import '../synapse_v3/v3_icon.dart';
import 'og_theme.dart';
import 'og_pages.dart';
import 'og_window_geometry.dart';

enum OgPage { editor, settings, hub, console }

abstract final class OgGeometry {
  static const main = Size(838, 372),
      loading = Size(265, 171),
      settings = Size(649, 705),
      hub = Size(612, 384),
      console = Size(520, 300);
  static Size size(OgPage page) => switch (page) {
    OgPage.editor => main,
    OgPage.settings => settings,
    OgPage.hub => hub,
    OgPage.console => console,
  };
}

class SynapseOgShell extends StatefulWidget {
  const SynapseOgShell({
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
  State<SynapseOgShell> createState() => SynapseOgShellState();
}

class SynapseOgShellState extends State<SynapseOgShell>
    with SingleTickerProviderStateMixin, WindowListener {
  final _editor = LuauSyntaxController(themeId: 'og-2017-custom'),
      _rename = TextEditingController(),
      _listSearch = TextEditingController();
  final _editorFocus = FocusNode(), _shellFocus = FocusNode();
  final _tabs = ScrollController(),
      _vertical = ScrollController(),
      _horizontal = ScrollController();
  late final _loader = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  );
  MonacoEditorService? _monaco;
  bool _ownsMonaco = false,
      _syncing = false,
      _loading = false,
      _pageBusy = false;
  Timer? _introTimer;
  bool _introFinished = false;
  String _documentId = '', _query = '';
  String? _renamingId;
  OgPage _page = OgPage.editor;
  Rect? _rememberedMainBounds;
  final _openSections = <String>{'Local Filesystem'};
  OrionController get c => widget.controller;
  TextStyle _type(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) => ogText(size, color: color, weight: weight, height: height).copyWith(
    fontFamily: SynapseThemeCatalog.current(
      c,
      InterfacePreset.synapse2017,
    ).fontFamily,
  );

  static const _studioPreset = InterfacePreset.synapse2017;
  String get _studioWindow => switch (_page) {
    OgPage.settings => 'settings',
    OgPage.hub => 'scriptHub',
    OgPage.console => 'console',
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
        _studio.colors['windowBg'] ??
            SynapseThemeCatalog.current(c, _studioPreset).colors['windowBg'] ??
            SynapseThemeCatalog.defaults(_studioPreset).colors['windowBg']!,
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

  CompanionWindowHost? get _windows => c.companionWindows;
  bool get _isChildWindow => _windows?.isChildWindow == true;
  Map<String, Object?> get prefs =>
      c.getInterfacePreferences(InterfacePreset.synapse2017);
  OgTheme get palette => OgTheme({
    ...prefs,
    'theme': {
      ...OgTheme(prefs).data,
      ...SynapseThemeCatalog.colors(c, _studioPreset, _studioWindow),
    },
  });
  OgTheme _buttonPalette(String id, OgTheme base) {
    final e = _studio.elements[id];
    return OgTheme({
      'theme': {
        ...base.data,
        if (e?.fill != null) 'buttonBg': e!.fill,
        if (e?.fill != null)
          'buttonHoverBg': Color(e!.fill!).withValues(alpha: .85).toARGB32(),
        if (e?.foreground != null) 'buttonText': e!.foreground,
        if (e?.border != null) 'buttonBorder': e!.border,
      },
    });
  }

  bool flag(String key, [bool fallback = false]) =>
      prefs[key] is bool ? prefs[key] as bool : fallback;
  void preference(String key, Object? value) =>
      c.setInterfacePreference(InterfacePreset.synapse2017, key, value);
  @override
  void initState() {
    super.initState();
    _page = switch (_windows?.kind) {
      CompanionWindowKind.synapseOgSettings => OgPage.settings,
      CompanionWindowKind.synapseOgHub => OgPage.hub,
      CompanionWindowKind.synapseOgConsole => OgPage.console,
      _ => OgPage.editor,
    };
    if (widget.previewWindowId != null) {
      _page = switch (widget.previewWindowId) {
        'settings' => OgPage.settings,
        'scriptHub' => OgPage.hub,
        'console' => OgPage.console,
        _ => OgPage.editor,
      };
    }
    _loading = widget.playIntro && !_isChildWindow;
    if (!_isChildWindow) _monaco = widget.editorService;
    if (_monaco == null &&
        !_isChildWindow &&
        widget.nativeWindow &&
        (Platform.isLinux || Platform.isWindows)) {
      _ownsMonaco = true;
      _monaco = MonacoEditorService(
        onChange: (id, text) => c.updateDocumentContent(id, text),
        onShortcut: handleEditorShortcut,
      );
    }
    _monaco?.addListener(_nativeChanged);
    c.addListener(_sync);
    _sync();
    _editor.addListener(_edited);
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
    if (_loading) {
      _loader.forward();
      _introTimer = Timer(
        const Duration(milliseconds: 2500),
        () => unawaited(_finishIntro()),
      );
    }
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    if (widget.nativeWindow) windowManager.removeListener(this);
    c.removeListener(_sync);
    _monaco?.removeListener(_nativeChanged);
    if (_ownsMonaco) _monaco?.dispose();
    _editor.removeListener(_edited);
    _editor.dispose();
    _rename.dispose();
    _listSearch.dispose();
    _editorFocus.dispose();
    _shellFocus.dispose();
    _tabs.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    _loader.dispose();
    super.dispose();
  }

  void _nativeChanged() {
    if (mounted) setState(() {});
  }

  void _sync() {
    final doc = c.activeDocument;
    if (_documentId != doc.id || _editor.text != doc.content) {
      _syncing = true;
      final same = _documentId == doc.id;
      _documentId = doc.id;
      _editor.value = TextEditingValue(
        text: doc.content,
        selection: TextSelection.collapsed(
          offset: same
              ? _editor.selection.baseOffset.clamp(0, doc.content.length)
              : 0,
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
    try {
      await _monaco?.flush();
    } on Object {
      /* Keep the latest received workspace text after renderer failure. */
    }
  }

  Future<void> _nativeSize(OgPage page) async {
    if (_isChildWindow) return;
    if (!widget.nativeWindow) return;
    final sourceSize = OgGeometry.size(page);
    final custom = SynapseThemeCatalog.current(c, _studioPreset).window(
      switch (page) {
        OgPage.settings => 'settings',
        OgPage.hub => 'scriptHub',
        OgPage.console => 'console',
        _ => 'main',
      },
    );
    final canonical = Size(
      custom.width ?? sourceSize.width,
      custom.height ?? sourceSize.height,
    );
    final previous = await windowManager.getBounds();
    final remembered = page == OgPage.editor ? _rememberedMainBounds : null;
    final requested = remembered != null && flag('resizable')
        ? remembered.size
        : canonical;
    Rect target;
    if (remembered != null) {
      // Companion pages never move the editor's remembered native position.
      target = remembered.topLeft & requested;
    } else {
      var workAreas = <Rect>[];
      try {
        final displays = await screenRetriever.getAllDisplays();
        workAreas = [
          for (final display in displays)
            (display.visiblePosition ?? Offset.zero) &
                (display.visibleSize ?? display.size),
        ];
        if (workAreas.isEmpty) {
          final primary = await screenRetriever.getPrimaryDisplay();
          workAreas = [
            (primary.visiblePosition ?? Offset.zero) &
                (primary.visibleSize ?? primary.size),
          ];
        }
      } on Object {
        // Compositors without work-area metadata still retain the previous centre.
      }
      target = ogWindowBounds(
        anchor: previous,
        size: requested,
        workAreas: workAreas,
      );
    }
    final minimum = Size(
      math.min(canonical.width, target.width),
      math.min(canonical.height, target.height),
    );
    await NativeWindowService.setResizable(true);
    await NativeWindowService.setMinimumSize(minimum);
    await NativeWindowService.setResizable(
      page == OgPage.editor && flag('resizable'),
      size: target.size,
    );
    await windowManager.setPosition(target.topLeft);
    await NativeWindowService.setAlwaysOnTop(flag('alwaysOnTop'));
  }

  Future<void> _finishIntro() async {
    if (!mounted || _introFinished) return;
    _introFinished = true;
    try {
      await _nativeSize(OgPage.editor);
    } on Object {
      /* The Flutter editor remains available if a window manager declines the request. */
    }
    if (!mounted) return;
    setState(() => _loading = false);
    widget.onIntroCompleted?.call();
    _editorFocus.requestFocus();
  }

  Future<void> openPage(OgPage page) async {
    final windows = _windows;
    if (windows != null) {
      if (_pageBusy || _loading) return;
      _pageBusy = true;
      try {
        await flushEditor();
        if (!mounted) return;
        if (page == OgPage.editor) {
          if (_isChildWindow) await windows.close();
        } else {
          await windows.open(switch (page) {
            OgPage.settings => CompanionWindowKind.synapseOgSettings,
            OgPage.hub => CompanionWindowKind.synapseOgHub,
            _ => CompanionWindowKind.synapseOgConsole,
          });
        }
      } finally {
        _pageBusy = false;
      }
      return;
    }
    if (_pageBusy || _loading || page == _page) return;
    _pageBusy = true;
    _monaco?.setObscured(true, owner: 'og-page-change');
    try {
      await flushEditor();
      if (widget.nativeWindow &&
          _page == OgPage.editor &&
          page != OgPage.editor) {
        _rememberedMainBounds = await windowManager.getBounds();
      }
      await _nativeSize(page);
      if (!mounted) return;
      setState(() {
        _page = page;
        if (page == OgPage.editor) _rememberedMainBounds = null;
      });
      _monaco?.setActive(page == OgPage.editor);
    } on Object catch (error) {
      if (mounted) await _message('Could not open this window: $error');
    } finally {
      _monaco?.setObscured(false, owner: 'og-page-change');
      _pageBusy = false;
    }
  }

  void _startDragging() {
    if (widget.nativeWindow) unawaited(windowManager.startDragging());
  }

  Future<void> _closePage() => openPage(OgPage.editor);
  @override
  void onWindowClose() async {
    if (_isChildWindow) {
      await _windows?.close();
      return;
    }
    await DesktopCloseService.closeApp(
      controller: c,
      nativeWindow: widget.nativeWindow,
      flushEditor: flushEditor,
    );
  }

  Future<T?> _dialog<T>(Widget child) async {
    try {
      await _monaco?.freezeForOverlay(owner: 'og-dialog');
      if (!mounted) return null;
      return await showDialog<T>(
        context: context,
        builder: (context) => Theme(data: _theme(), child: child),
      );
    } finally {
      _monaco?.setObscured(false, owner: 'og-dialog');
    }
  }

  ThemeData _theme() => ThemeData(
    brightness: Brightness.dark,
    useMaterial3: false,
    fontFamily: 'SynapseInter',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: palette.window,
    colorScheme: ColorScheme.dark(
      surface: palette.window,
      primary: const Color(0xffb0d8e5),
    ),
    textTheme: TextTheme(bodyMedium: _type(13)),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.window,
      shape: const RoundedRectangleBorder(),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: _type(11),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: const Color(0xff424242)),
      ),
    ),
  );
  Future<void> _message(String text) async {
    if (!mounted) return;
    await _dialog(
      Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: _type(13)),
              const SizedBox(height: 16),
              OgButton(
                'Ok',
                theme: palette,
                width: 75,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirm(String text) async =>
      await _dialog<bool>(
        Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, style: _type(13)),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OgButton(
                      'Yes',
                      theme: palette,
                      width: 75,
                      onPressed: () => Navigator.pop(context, true),
                    ),
                    const SizedBox(width: 8),
                    OgButton(
                      'No',
                      theme: palette,
                      width: 75,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
  Future<void> _clear() async {
    if (_editor.text.isNotEmpty &&
        !await _confirm('Are you sure you want to clear the editor?')) {
      return;
    }
    if (_monaco != null) {
      await _monaco!.action('clear');
    } else {
      c.updateDocumentContent(c.activeDocumentId, '');
    }
  }

  Future<void> _openFile() async {
    await flushEditor();
    try {
      await _monaco?.freezeForOverlay(owner: 'og-picker');
      if (!mounted) return;
      await c.openFile();
    } finally {
      _monaco?.setObscured(false, owner: 'og-picker');
    }
  }

  Future<void> _save() async {
    await flushEditor();
    try {
      await _monaco?.freezeForOverlay(owner: 'og-picker');
      if (!mounted) return;
      await c.saveDocument();
    } finally {
      _monaco?.setObscured(false, owner: 'og-picker');
    }
  }

  Future<void> _closeTab(EditorDocument doc) async {
    await flushEditor();
    if (doc.isDirty && !await _confirm('Close ${doc.name} without saving?')) {
      return;
    }
    c.closeDocument(doc.id);
  }

  void handleEditorShortcut(String name) {
    switch (name) {
      case 'show-editor':
        unawaited(openPage(OgPage.editor));
      case 'new':
        c.newDocument();
      case 'open':
        unawaited(_openFile());
      case 'save':
        unawaited(_save());
      case 'closeTab':
        unawaited(_closeTab(c.activeDocument));
      case 'execute':
        if (widget.bridgeReady) c.execute();
      case 'attach':
        unawaited(
          showBridgeClientManager(
            context,
            controller: c,
            editorService: _monaco,
          ),
        );
      case 'console':
        unawaited(openPage(OgPage.console));
      case 'find':
        if (_monaco != null) unawaited(_monaco!.action('find'));
      case 'replace':
        if (_monaco != null) unawaited(_monaco!.action('replace'));
    }
  }

  void _nativeSnapshot() {
    final t = palette;
    unawaited(
      _monaco?.synchronize({
            'documents': [
              for (final doc in c.documents)
                {'id': doc.id, 'name': doc.name, 'content': doc.content},
            ],
            'activeId': c.activeDocumentId,
            'options': {
              'shell': 'synapseOriginal',
              'animateReveal': false,
              'editorThemeId': prefs['editorThemeId'] ?? 'og-2017-custom',
              'fontSize': 13,
              'lineHeight': 18,
              'uiScale': c.uiScale,
              'wordWrap': c.wordWrap,
              'lineNumbers': c.showLineNumbers,
              'minimap': flag('minimap'),
              'minimapScale': prefs['minimapScale'] ?? 1,
              'diagnosticEnabled': false,
              'reducedMotion':
                  c.reducedMotion || MediaQuery.disableAnimationsOf(context),
              'brightness': 'dark',
              'background': t.hex('editorBg'),
              'foreground': t.hex('text'),
              'border': t.hex('tabBorder'),
              'accent': '#b0d8e5',
              'muted': '#7a7a7a',
              ..._studioEditorOptions,
            },
          }) ??
          Future.value(),
    );
  }

  Future<void> _setFlag(String key, bool value) async {
    preference(key, value);
    if (_windows != null) {
      if (key == 'alwaysOnTop' || key == 'resizable') {
        await _windows!.updateOwnerWindow(
          alwaysOnTop: key == 'alwaysOnTop' ? value : null,
          resizable: key == 'resizable' ? value : null,
        );
      }
      return;
    }
    if (key == 'alwaysOnTop' && widget.nativeWindow) {
      await NativeWindowService.setAlwaysOnTop(value);
    }
    if (key == 'resizable') await _nativeSize(_page);
  }

  Future<void> _switch(InterfacePreset preset) async {
    await flushEditor();
    if (widget.onSelectInterface != null) {
      await widget.onSelectInterface!(preset);
    } else {
      c.setInterface(preset);
    }
  }

  Future<void> _backToOrion() async {
    await flushEditor();
    if (_windows != null) {
      await _windows!.returnToOrion();
    } else if (mounted) {
      widget.onBackToOrion();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = palette;
    if (!_loading) _nativeSnapshot();
    final radius = flag('edgeCurve') ? 7.0 : 0.0;
    return Theme(
      data: _theme(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.window,
            border: flag('edgeCurve')
                ? Border.all(color: const Color(0xff414342))
                : null,
            borderRadius: BorderRadius.circular(radius),
          ),
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
                LogicalKeyboardKey.keyW,
                control: true,
              ): () =>
                  handleEditorShortcut('closeTab'),
              const SingleActivator(
                LogicalKeyboardKey.keyF,
                control: true,
              ): () =>
                  handleEditorShortcut('find'),
              const SingleActivator(LogicalKeyboardKey.f9): () =>
                  handleEditorShortcut('console'),
            },
            child: _surface(
              Focus(
                focusNode: _shellFocus,
                autofocus: true,
                child: _loading
                    ? _loadingScreen(t)
                    : switch (_page) {
                        OgPage.editor => _main(t),
                        OgPage.settings => _element(
                          'content',
                          _element(
                            'settingsControls',
                            OgSettingsPage(
                              controller: c,
                              theme: t,
                              preferences: prefs,
                              onFlag: _setFlag,
                              onThemeStudio: () => unawaited(_themeStudio()),
                              onClose: _closePage,
                              onBackToOrion: () => unawaited(_backToOrion()),
                              onSwitch: _switch,
                              nativeWindow: widget.nativeWindow,
                              onDragStart: _startDragging,
                            ),
                          ),
                        ),
                        OgPage.hub => _element(
                          'content',
                          _element(
                            'scriptCards',
                            OgHubPage(
                              controller: c,
                              theme: t,
                              onClose: _closePage,
                              bridgeReady: widget.bridgeReady,
                              onDragStart: _startDragging,
                              onOpen: (script) async {
                                await c.openRemoteScript(script);
                                await _closePage();
                              },
                            ),
                          ),
                        ),
                        OgPage.console => _element(
                          'content',
                          _element(
                            'consoleOutput',
                            OgConsolePage(
                              controller: c,
                              theme: t,
                              onClose: _closePage,
                              onDragStart: _startDragging,
                            ),
                          ),
                        ),
                      },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadingScreen(OgTheme t) => AnimatedBuilder(
    animation: _loader,
    builder: (context, _) {
      final elapsed = _loader.value * 2500,
          progress = (elapsed / 2000).clamp(0.0, 1.0),
          reduce = c.reducedMotion || MediaQuery.disableAnimationsOf(context);
      return Align(
        alignment: Alignment.topLeft,
        child: Opacity(
          opacity: reduce
              ? 1
              : elapsed < 2000
              ? 1
              : (1 - (elapsed - 2000) / 500).clamp(0.0, 1.0),
          child: SizedBox(
            width: 265,
            height: 171,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: t.window)),
                Positioned(
                  left: 17,
                  top: 37,
                  width: 231,
                  height: 48,
                  child: OgLogo(theme: t),
                ),
                Positioned(
                  left: 14,
                  top: 117,
                  width: 237,
                  height: 23,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xff878788)),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 117,
                  width: 237 * progress,
                  height: 23,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xff008b00),
                      border: Border.all(color: const Color(0xff539b59)),
                    ),
                  ),
                ),
                Positioned(
                  left: 85,
                  top: 145,
                  child: Text(
                    '[ Loading${'.' * ((elapsed / 500).floor() % 4)} ]',
                    style: _type(16, color: const Color(0xffc0c0c0)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _main(OgTheme t) {
    return _element(
      'content',
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final footerHeight = compact ? 83.0 : 39.0;
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: t.window)),

              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 58,
                child: _element(
                  'titleBar',
                  GestureDetector(
                    onPanStart: widget.nativeWindow
                        ? (_) => windowManager.startDragging()
                        : null,
                    onDoubleTap: widget.nativeWindow && flag('resizable')
                        ? () async {
                            await windowManager.isMaximized()
                                ? await windowManager.unmaximize()
                                : await windowManager.maximize();
                          }
                        : null,
                    child: ColoredBox(color: t.panel),
                  ),
                ),
              ),
              Positioned(
                left: 9,
                top: 15,
                width: 139,
                height: 29,
                child: IgnorePointer(child: _logo(OgLogo(theme: t))),
              ),

              Positioned(
                right: 6,
                top: 4,
                width: 33,
                height: 13,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: OgGlyph('window', Colors.white),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 13.2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.nativeWindow
                            ? () => windowManager.minimize()
                            : null,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 18.15,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onWindowClose,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 8,
                top: 70,
                right: 158,
                bottom: footerHeight + 22,
                child: Column(
                  children: [
                    SizedBox(
                      height: 17,
                      child: Row(
                        children: [
                          Expanded(
                            child: _element(
                              'tabs',
                              ListView.separated(
                                controller: _tabs,
                                scrollDirection: Axis.horizontal,
                                itemCount: c.documents.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 4),
                                itemBuilder: (context, index) =>
                                    _tab(c.documents[index], t),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          _smallGlyph('save', 'Save script as', _save, t),
                          const SizedBox(width: 2),
                          _smallGlyph(
                            'add',
                            'Add script tab',
                            () => c.newDocument(),
                            t,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Expanded(
                      child: _element(
                        'editor',
                        ColoredBox(color: t.editor, child: _code(t)),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                top: 69,
                width: 139,
                bottom: footerHeight + 22,
                child: _element(
                  'scriptList',
                  ColoredBox(
                    color: t.panel,
                    child: flag('enhancedList')
                        ? _enhancedList(t)
                        : ListView(
                            padding: const EdgeInsets.all(4),
                            children: [
                              if (_localScripts.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    'Add .lua files to scripts.',
                                    style: _type(
                                      9,
                                      color: const Color(0xffa3a3a3),
                                      height: 1.375,
                                    ),
                                  ),
                                ),
                              for (final doc in _localScripts)
                                _scriptRow(doc, t, false),
                            ],
                          ),
                  ),
                ),
              ),
              Positioned(
                left: 9,
                right: 12,
                bottom: 10,
                height: footerHeight,
                child: _element('actions', _footer(t, compact)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _bookmark(EditorDocument doc) {
    final ids = c.synapsePreferences.bookmarkedDocumentIds.toSet();
    if (!ids.add(doc.id)) ids.remove(doc.id);
    c.updateSynapsePreferences(bookmarkedDocumentIds: ids.toList());
  }

  Widget _rowAction(
    String label,
    String icon,
    VoidCallback? action,
    OgTheme t,
  ) => SizedBox(
    width: 16,
    height: 16,
    child: Tooltip(
      message: label,
      child: TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Opacity(
          opacity: action == null ? .4 : 1,
          child: V3Icon(
            icon,
            size: 11,
            color: t.color('scriptList.sectionIcon'),
          ),
        ),
      ),
    ),
  );
  Widget _footer(OgTheme t, bool compact) {
    final items = <(String, int, VoidCallback?)>[
      ('Execute', 116, widget.bridgeReady ? () => c.execute() : null),
      ('Clear', 116, () => _clear()),
      ('Open File', 116, () => _openFile()),
      (
        'Attach',
        116,
        () => unawaited(
          showBridgeClientManager(
            context,
            controller: c,
            editorService: _monaco,
          ),
        ),
      ),
      ('Script Hub', 144, () => openPage(OgPage.hub)),
      ('Settings & Clients', 184, () => openPage(OgPage.settings)),
    ];
    Widget row(List<(String, int, VoidCallback?)> buttons) => Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            flex: buttons[i].$2,
            child: _element(
              switch (buttons[i].$1) {
                'Execute' => 'executeButton',
                'Clear' => 'clearButton',
                'Open File' => 'openButton',
                'Attach' => 'attachButton',
                'Script Hub' => 'hubButton',
                _ => 'settingsButton',
              },
              OgButton(
                buttons[i].$1,
                theme: _buttonPalette(switch (buttons[i].$1) {
                  'Execute' => 'executeButton',
                  'Clear' => 'clearButton',
                  'Open File' => 'openButton',
                  'Attach' => 'attachButton',
                  'Script Hub' => 'hubButton',
                  _ => 'settingsButton',
                }, t),
                height: 39,
                fontSize: 20,
                onPressed: buttons[i].$3,
                key: ValueKey('og-action/${buttons[i].$1}'),
              ),
            ),
          ),
        ],
      ],
    );
    return compact
        ? Column(
            children: [
              row(items.take(3).toList()),
              const SizedBox(height: 5),
              row(items.skip(3).toList()),
            ],
          )
        : row(items);
  }

  List<EditorDocument> get _localScripts =>
      c.documents.where((d) => d.filePath != null).toList();
  Widget _tab(EditorDocument doc, OgTheme t) {
    final active = doc.id == c.activeDocumentId;
    final textWidth = TextPainter(
      text: TextSpan(text: doc.name, style: _type(10)),
      textDirection: TextDirection.ltr,
    )..layout();
    return SizedBox(
      width: (textWidth.width + 22).clamp(72, 260),
      height: 16,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => c.selectDocument(doc.id),
              onDoubleTap: () {
                setState(() {
                  _renamingId = doc.id;
                  _rename.text = doc.name;
                });
              },
              child: _renamingId == doc.id
                  ? TextField(
                      controller: _rename,
                      autofocus: true,
                      style: _type(10, height: 1.4),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onSubmitted: (v) {
                        c.renameDocument(doc.id, v);
                        setState(() => _renamingId = null);
                      },
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        doc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _type(
                          10,
                          color: active ? Colors.white : t.color('tabText'),
                          weight: active ? FontWeight.w500 : FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(
            width: 14,
            height: 16,
            child: Tooltip(
              message: 'Close ${doc.name}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _closeTab(doc),
                child: Center(
                  child: CustomPaint(
                    size: const Size(9, 9),
                    painter: OgGlyph('close', t.color('iconColor')),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallGlyph(
    String name,
    String tooltip,
    VoidCallback callback,
    OgTheme t,
  ) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 15,
      height: 15,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: callback,
        child: CustomPaint(painter: OgGlyph(name, t.color('iconColor'))),
      ),
    ),
  );
  Widget _code(OgTheme t) {
    _editor.useTheme(
      prefs['editorThemeId'] as String? ?? 'og-2017-custom',
      foreground: SynapseThemeCatalog.hasStudio(c, _studioPreset)
          ? Color(_studio.elements['editor']?.foreground ?? t.text.toARGB32())
          : null,
    );
    if (_monaco != null) {
      return MonacoEditor(
        service: _monaco!,
        active: _page == OgPage.editor && !_loading,
        backgroundColor: t.editor,
        foregroundColor: const Color(0xffd4d4d4),
        fallback: LuauCodePreview(
          controller: _editor,
          gutterWidth: 35,
          gutterColor: const Color(0xff7a7a7a),
          showLineNumbers: c.showLineNumbers,
          wordWrap: c.wordWrap,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 13,
            height: 18 / 13,
            color: Color(
              _studio.elements['editor']?.foreground ?? t.text.toARGB32(),
            ),
          ),
        ),
      );
    }
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lines = _editor.text.split('\n');
          final width = math.max(
            constraints.maxWidth - 35,
            lines.fold<int>(0, (a, b) => math.max(a, b.length)) * 8.0 + 20,
          );
          return SingleChildScrollView(
            controller: _vertical,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 35,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < lines.length; i++)
                          SizedBox(
                            height: 18,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 13,
                                color: Color(0xff7a7a7a),
                                height: 18 / 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: TextField(
                        key: const ValueKey('code-editor'),
                        controller: _editor,
                        focusNode: _editorFocus,
                        maxLines: null,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 13,
                          height: 18 / 13,
                          color: Color(
                            _studio.elements['editor']?.foreground ??
                                t.text.toARGB32(),
                          ),
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
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

  Widget _scriptRow(EditorDocument doc, OgTheme t, bool enhanced) => Listener(
    onPointerDown: (e) {
      if (e.buttons == 2) _scriptMenu(doc, e.position);
    },
    child: TextButton(
      onPressed: () => c.selectDocument(doc.id),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: enhanced ? 4 : 0,
          vertical: 2,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
        foregroundColor: t.color('listText'),
        textStyle: _type(11, height: 1.375),
        shape: const RoundedRectangleBorder(),
      ),
      child: enhanced
          ? Row(
              children: [
                V3Icon(
                  'document20Filled',
                  size: 12,
                  color: t.color('scriptList.sectionIcon'),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    doc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _rowAction(
                  'Execute ${doc.name}',
                  'play20Filled',
                  widget.bridgeReady
                      ? () => c.execute(source: doc.content, name: doc.name)
                      : null,
                  t,
                ),
                _rowAction(
                  'Bookmark ${doc.name}',
                  'bookmark20Filled',
                  () => _bookmark(doc),
                  t,
                ),
              ],
            )
          : Text(doc.name),
    ),
  );
  Future<void> _scriptMenu(EditorDocument doc, Offset position) async {
    String? action;
    try {
      await _monaco?.freezeForOverlay(owner: 'og-menu');
      if (!mounted) return;
      action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
        items: [
          const PopupMenuItem(value: 'open', child: Text('(Open in editor)')),
          if (flag('enhancedList'))
            const PopupMenuItem(
              value: 'bookmark',
              child: Text('Toggle bookmark'),
            ),
          const PopupMenuItem(
            value: 'reveal',
            child: Text('Open in file explorer'),
          ),
        ],
      );
    } finally {
      _monaco?.setObscured(false, owner: 'og-menu');
    }
    if (!mounted) return;
    if (action == 'open') c.selectDocument(doc.id);
    if (action == 'bookmark') _bookmark(doc);
    if (action == 'reveal' && doc.filePath != null) {
      await DesktopLauncher.revealFile(File(doc.filePath!));
    }
  }

  Widget _enhancedList(OgTheme t) {
    final docs = _localScripts
        .where((d) => d.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Column(
      children: [
        SizedBox(
          height: 24,
          child: TextField(
            controller: _listSearch,
            style: _type(10, color: t.color('listText')),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              filled: true,
              fillColor: t.color('scriptList.searchBg'),
              hintText: 'Search',
              hintStyle: _type(
                10,
                color: t.color('scriptList.searchPlaceholder'),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: ListView(
            children: [
              for (final name in [
                'Local Filesystem',
                'Bookmarks',
                'Github Gists',
              ]) ...[
                SizedBox(
                  height: 22,
                  child: TextButton(
                    onPressed: () => setState(() {
                      if (!_openSections.add(name)) _openSections.remove(name);
                    }),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: t.color('scriptList.sectionHeaderBg'),
                      shape: const RoundedRectangleBorder(),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      children: [
                        V3Icon(
                          name == 'Local Filesystem'
                              ? 'hardDrive20Filled'
                              : name == 'Bookmarks'
                              ? 'bookmark20Filled'
                              : 'github24',
                          size: 12,
                          color: t.color('scriptList.sectionIcon'),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            name,
                            style: _type(
                              11,
                              color: t.color('scriptList.sectionHeaderText'),
                            ),
                          ),
                        ),
                        V3Icon(
                          _openSections.contains(name)
                              ? 'chevronDown20Regular'
                              : 'chevronRight20Regular',
                          size: 8,
                          color: t.color('iconColor'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_openSections.contains(name))
                  ...name == 'Github Gists'
                      ? [_gistControls(t)]
                      : [
                          for (final doc in docs.where(
                            (d) =>
                                name != 'Bookmarks' ||
                                c.synapsePreferences.bookmarkedDocumentIds
                                    .contains(d.id),
                          ))
                            _scriptRow(doc, t, true),
                          if (docs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: Text(
                                name == 'Bookmarks'
                                    ? 'No bookmarked scripts'
                                    : 'No scripts found',
                                style: _type(
                                  9,
                                  color: t.color('scriptList.rowMutedText'),
                                ),
                              ),
                            ),
                        ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _gistControls(OgTheme t) => Column(
    children: [
      for (final url in c.synapsePreferences.gistUrls)
        TextButton(
          onPressed: () => _loadGist(url),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            textStyle: _type(11),
            foregroundColor: t.color('listText'),
          ),
          child: Text(V3Gists.title(Uri.parse(url))),
        ),
      TextButton(
        onPressed: _addGist,
        style: TextButton.styleFrom(
          textStyle: _type(10),
          foregroundColor: t.color('listText'),
        ),
        child: const Text('Add gist URL'),
      ),
    ],
  );
  Future<void> _addGist() async {
    final url = await _dialog<String>(
      OgInputDialog(title: 'Add Gist URL', theme: palette),
    );
    if (url == null) return;
    final uri = V3Gists.parse(url);
    if (uri == null) {
      await _message('Enter an HTTP or HTTPS raw script URL.');
      return;
    }
    c.updateSynapsePreferences(
      gistUrls: [...c.synapsePreferences.gistUrls, uri.toString()],
    );
  }

  Future<void> _loadGist(String url) async {
    try {
      final uri = V3Gists.parse(url)!;
      final content = await V3Gists.load(uri);
      final doc = c.newDocument(
        name: '${V3Gists.title(uri)}.lua',
        content: content,
      );
      c.updateSynapsePreferences(
        gistDocumentUrls: {
          ...c.synapsePreferences.gistDocumentUrls,
          doc.id: url,
        },
      );
    } on Object catch (error) {
      await _message('Could not load gist: $error');
    }
  }
}

class OgGlyph extends CustomPainter {
  const OgGlyph(this.name, this.color);
  final String name;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    final path = Path();
    switch (name) {
      case 'window':
        canvas.scale(size.width / 33, size.height / 13);
        paint.strokeWidth = 2;
        path
          ..moveTo(11, 12)
          ..lineTo(1, 12)
          ..moveTo(32, 1)
          ..lineTo(21, 12)
          ..moveTo(32, 12)
          ..lineTo(21, 1);
      case 'close':
        canvas.scale(size.width / 9, size.height / 9);
        paint.strokeWidth = 2;
        path
          ..moveTo(8, 1)
          ..lineTo(1, 8)
          ..moveTo(8, 8)
          ..lineTo(1, 1);
      case 'add':
        canvas.scale(size.width / 15, size.height / 15);
        paint.strokeWidth = 2;
        path
          ..moveTo(7.5, 3)
          ..lineTo(7.5, 12)
          ..moveTo(12, 7.5)
          ..lineTo(3, 7.5);
      case 'save':
        canvas.scale(size.width / 15, size.height / 15);
        paint.strokeWidth = 1.1;
        path
          ..moveTo(4, 3.5)
          ..lineTo(8.5, 3.5)
          ..lineTo(10.5, 5.5)
          ..lineTo(10.5, 11.5)
          ..lineTo(4, 11.5)
          ..close()
          ..moveTo(5.2, 3.5)
          ..lineTo(5.2, 5.8)
          ..lineTo(7.7, 5.8)
          ..lineTo(7.7, 3.5)
          ..addRect(const Rect.fromLTWH(5, 8.5, 5, 2.5));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(OgGlyph old) => old.name != name || old.color != color;
}
