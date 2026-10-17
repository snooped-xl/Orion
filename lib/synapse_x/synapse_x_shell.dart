import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';

import '../widgets/bridge_client_manager.dart';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/interface_preset.dart';
import '../models/companion_window.dart';
import '../models/orion_models.dart';
import '../services/desktop_close_service.dart';
import '../services/file_paths.dart';
import '../services/monaco_editor_service.dart';
import '../services/native_window_service.dart';
import '../state/orion_controller.dart';
import '../models/synapse_studio_theme.dart';
import '../services/synapse_theme_catalog.dart';
import '../services/synapse_theme_studio_service.dart';
import '../widgets/synapse_theme_surface.dart';
import '../widgets/monaco_editor.dart';
import '../widgets/luau_syntax.dart';
import '../synapse_v3/v3_gists.dart';
import 'synapse_x_theme.dart';
import 'synapse_x_pages.dart';

/// WPF Synapse X chrome and source-sized companion pages, backed by Orion's
/// actual local workspace and the shared native Monaco models.
class SynapseXShell extends StatefulWidget {
  const SynapseXShell({
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
  State<SynapseXShell> createState() => SynapseXShellState();
}

class SynapseXShellState extends State<SynapseXShell>
    with TickerProviderStateMixin, WindowListener {
  final _editor = LuauSyntaxController(themeId: 'net-theme-dark');
  final _editorFocus = FocusNode(debugLabel: 'Synapse X editor');
  final _find = TextEditingController();
  final _tabs = ScrollController();
  final _gistClient = V3Gists.load;
  late final AnimationController _loading, _fade;
  MonacoEditorService? _monaco;
  bool _ownsMonaco = false,
      _syncing = false,
      _intro = false,
      _loaderOut = false,
      _showFind = false;
  String _documentId = '', _page = 'main';
  String? _renaming, _loadingGist;
  String _renameDraft = '';
  int _windowSequence = 0;
  final _localExpanded = <String>{};
  OrionController get c => widget.controller;
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
          c,
          InterfacePreset.synapseX,
        ).fontFamily,
      );

  static const _studioPreset = InterfacePreset.synapseX;
  String get _studioWindow => switch (_page) {
    'options' => 'settings',
    'hub' => 'scriptHub',
    'console' => 'console',
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
  Map<String, Object?> get preferences =>
      c.getInterfacePreferences(InterfacePreset.synapseX);
  SynapseXTheme get palette => SynapseXTheme({
    ...preferences,
    for (final entry in SynapseThemeCatalog.colors(
      c,
      _studioPreset,
      _studioWindow,
    ).entries)
      'theme.${entry.key}': entry.value,
  });
  SynapseXTheme _buttonPalette(String id, SynapseXTheme base) {
    final e = _studio.elements[id];
    return SynapseXTheme({
      ...base.preferences,
      if (e?.fill != null) 'theme.buttonBg': e!.fill,
      if (e?.fill != null)
        'theme.buttonHoverBg': Color(
          e!.fill!,
        ).withValues(alpha: .85).toARGB32(),
      if (e?.foreground != null) 'theme.buttonText': e!.foreground,
      if (e?.border != null) 'theme.buttonBorder': e!.border,
    });
  }

  bool option(String name, [bool fallback = false]) =>
      preferences[name] is bool ? preferences[name] as bool : fallback;
  bool get _reduceMotion =>
      c.reducedMotion ||
      (mounted && MediaQuery.maybeOf(context)?.disableAnimations == true);

  @override
  void initState() {
    super.initState();
    _page = switch (_windows?.kind) {
      CompanionWindowKind.synapseXOptions => 'options',
      CompanionWindowKind.synapseXHub => 'hub',
      CompanionWindowKind.synapseXConsole => 'console',
      _ => 'main',
    };
    if (widget.previewWindowId != null) {
      _page = switch (widget.previewWindowId) {
        'settings' => 'options',
        'scriptHub' => 'hub',
        'console' => 'console',
        _ => 'main',
      };
    }
    _intro = widget.playIntro && !_isChildWindow;
    _loading = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addListener(_animate);
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_animate);
    if (!_isChildWindow && widget.editorService != null) {
      _monaco = widget.editorService!..addListener(_nativeChanged);
    } else if (!_isChildWindow &&
        widget.nativeWindow &&
        (Platform.isLinux || Platform.isWindows)) {
      _ownsMonaco = true;
      _monaco = MonacoEditorService(
        onChange: (id, body) => c.updateDocumentContent(id, body),
        onShortcut: handleEditorShortcut,
      )..addListener(_nativeChanged);
    }
    _monaco?.setOpacity(0, owner: 'synapse-x');
    _sync();
    _editor.addListener(_edited);
    c.addListener(_sync);
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isChildWindow) {
        _fade.value = 1;
        return;
      }
      if (_intro && !_reduceMotion) {
        _monaco?.setActive(false);
        _loading.forward().then((_) async {
          if (!mounted) return;
          setState(() => _loaderOut = true);
          _fade.duration = const Duration(milliseconds: 500);
          await _fade.forward(from: 0);
          if (mounted) await _finishIntro();
        });
      } else {
        unawaited(_finishIntro());
      }
    });
  }

  void _animate() {
    _monaco?.setOpacity(
      _intro ? 0 : Curves.easeInOut.transform(_fade.value),
      owner: 'synapse-x',
    );
    if (mounted) setState(() {});
  }

  Future<void> _finishIntro() async {
    if (!mounted) return;
    final didIntro = _intro;
    setState(() {
      _intro = false;
      _loaderOut = false;
    });
    await _resizeFor('main');
    if (!mounted) return;
    if (didIntro) widget.onIntroCompleted?.call();
    _fade.duration = const Duration(milliseconds: 700);
    if (_reduceMotion) {
      _fade.value = 1;
    } else {
      unawaited(_fade.forward(from: 0));
    }
    _monaco?.setActive(true);
  }

  @override
  void dispose() {
    ++_windowSequence;
    c.removeListener(_sync);
    _editor.removeListener(_edited);
    _monaco?.removeListener(_nativeChanged);
    _monaco?.setOpacity(1, owner: 'synapse-x');
    if (_ownsMonaco) _monaco?.dispose();
    if (widget.nativeWindow) windowManager.removeListener(this);
    _editor.dispose();
    _editorFocus.dispose();
    _find.dispose();
    _tabs.dispose();
    _loading.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _nativeChanged() {
    if (mounted) setState(() {});
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

  Future<void> flushEditor() async => _monaco?.flush();
  void setEditorObscured(bool value, {String owner = 'route'}) =>
      _monaco?.setObscured(value, owner: owner);
  void setEditorTransitioning(bool value) => _monaco?.setTransitioning(value);
  void handleEditorShortcut(String name) {
    switch (name) {
      case 'show-editor':
        unawaited(_navigate('main'));
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
      case 'save-as':
        unawaited(_save(saveAs: true));
        break;
      case 'execute':
        if (widget.bridgeReady) unawaited(_execute());
        break;
      case 'console':
        unawaited(_navigate('console'));
        break;
      case 'find':
        requestFind();
        break;
    }
  }

  void requestFind() {
    if (_page != 'main') {
      if (_isChildWindow) {
        unawaited(_windows?.focusMain());
        return;
      }
      unawaited(_navigate('main').then((_) => requestFind()));
      return;
    }
    if (_monaco != null) {
      unawaited(_monaco!.action('find'));
      return;
    }
    setState(() => _showFind = true);
  }

  Future<void> _resizeFor(String page) async {
    if (_isChildWindow) return;
    if (!widget.nativeWindow) return;
    final sequence = ++_windowSequence;
    final defaultSize = switch (page) {
      'options' => const Size(528, 460),
      'hub' => const Size(612, 384),
      'console' => const Size(520, 300),
      _ => const Size(801, 355),
    };
    final custom = _studio;
    final size = Size(
      custom.width ?? defaultSize.width,
      custom.height ?? defaultSize.height,
    );
    try {
      final previous = await windowManager.getBounds();
      if (!mounted || sequence != _windowSequence) return;
      await NativeWindowService.setMinimumSize(
        page == 'main' && option('resizable') ? const Size(600, 300) : size,
      );
      if (!mounted || sequence != _windowSequence) return;
      await NativeWindowService.setResizable(
        page == 'main' && option('resizable'),
        size: size,
      );
      if (!mounted || sequence != _windowSequence) return;
      await windowManager.setPosition(
        previous.center - Offset(size.width / 2, size.height / 2),
      );
      await NativeWindowService.setAlwaysOnTop(option('alwaysOnTop'));
    } catch (_) {
      /* Window integration is optional for embedded widget fixtures. */
    }
  }

  Future<void> _navigate(String page) async {
    final windows = _windows;
    if (windows != null) {
      await flushEditor();
      if (!mounted) return;
      if (page == 'main') {
        if (_isChildWindow) await windows.close();
      } else {
        await windows.open(switch (page) {
          'options' => CompanionWindowKind.synapseXOptions,
          'hub' => CompanionWindowKind.synapseXHub,
          _ => CompanionWindowKind.synapseXConsole,
        });
      }
      return;
    }
    if (_page == page) return;
    await flushEditor();
    if (!mounted) return;
    _monaco?.setActive(page == 'main');
    setState(() => _page = page);
    await _resizeFor(page);
  }

  Future<void> _backToOrion() async {
    await flushEditor();
    if (_windows != null) {
      await _windows!.returnToOrion();
    } else if (mounted) {
      widget.onBackToOrion();
    }
  }

  Future<void> _nativePreferencesChanged() async {
    if (_windows != null) {
      await _windows!.updateOwnerWindow(
        alwaysOnTop: option('alwaysOnTop'),
        resizable: option('resizable'),
      );
    } else {
      await _resizeFor(_page);
    }
  }

  Future<void> _new() async {
    await flushEditor();
    if (!mounted) return;
    final content = preferences['defaultTabContent'];
    c.newDocument(content: content is String ? content : '');
    _editorFocus.requestFocus();
  }

  Future<void> _select(String id) async {
    await flushEditor();
    if (mounted) c.selectDocument(id);
  }

  Future<T?> _obscured<T>(Future<T?> Function() action) async {
    try {
      await _monaco?.freezeForOverlay(owner: 'x-dialog');
      if (!mounted) return null;
      return await action();
    } finally {
      _monaco?.setObscured(false, owner: 'x-dialog');
    }
  }

  Future<void> _open() async {
    await flushEditor();
    if (!mounted) return;
    await _obscured(c.openFile);
  }

  Future<void> _save({bool saveAs = false}) async {
    await flushEditor();
    if (!mounted) return;
    await _obscured(() => saveAs ? c.saveAs() : c.saveDocument());
  }

  Future<void> _clear() async {
    await flushEditor();
    if (!mounted) return;
    c.updateDocumentContent(c.activeDocumentId, '');
    if (_monaco != null) {
      await _monaco!.action('clear');
    } else {
      _editorFocus.requestFocus();
    }
  }

  Future<void> _execute() async {
    if (!widget.bridgeReady) return;
    await flushEditor();
    if (mounted) c.execute();
  }

  Future<void> _executeFile() async {
    if (!widget.bridgeReady) return;
    await flushEditor();
    if (!mounted) return;
    try {
      final selected = await _obscured(
        () => files.openFile(
          acceptedTypeGroups: [
            const files.XTypeGroup(
              label: 'Lua scripts',
              extensions: ['lua', 'luau', 'txt'],
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final body = await selected.readAsString();
      if (!mounted) return;
      c.executeSource(body, name: FilePaths.basename(selected.path));
    } catch (e) {
      _message(e.toString());
    }
  }

  Future<void> _closeTab(EditorDocument d) async {
    await flushEditor();
    if (!mounted) return;
    final current = c.documents.firstWhere((v) => v.id == d.id);
    if (current.isDirty) {
      final choice = await _obscured(
        () => showDialog<String>(
          context: context,
          builder: (ctx) =>
              _popup('Unsaved changes', 'Save changes to ${current.name}?', [
                ('Save', () => Navigator.pop(ctx, 'save')),
                ('Discard', () => Navigator.pop(ctx, 'discard')),
                ('Cancel', () => Navigator.pop(ctx)),
              ]),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'save' &&
          !(await _obscured(() => c.saveDocument(current.id)) ?? false)) {
        return;
      }
    }
    if (mounted) c.closeDocument(d.id);
  }

  void _message(String message) {
    if (!mounted) return;
    unawaited(
      _obscured(
        () => showDialog<void>(
          context: context,
          builder: (ctx) =>
              _popup('Synapse X', message, [('Ok', () => Navigator.pop(ctx))]),
        ),
      ),
    );
  }

  Widget _popup(
    String title,
    String message,
    List<(String, VoidCallback)> buttons,
  ) => Dialog(
    shape: const RoundedRectangleBorder(),
    backgroundColor: palette.window,
    child: SizedBox(
      width: 360,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _type(14)),
            const SizedBox(height: 14),
            Text(message, style: _type(12)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final b in buttons)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: SizedBox(
                      width: 80,
                      height: 29,
                      child: XButton(
                        b.$1,
                        onPressed: b.$2,
                        theme: palette,
                        size: 12,
                        border: const Color(0xff2a2a2a),
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

  void _synchronizeNative() {
    if (_monaco == null) return;
    final p = palette;
    _configureSyntax(p);
    unawaited(
      _monaco!.synchronize({
        'documents': [
          for (final d in c.documents)
            {'id': d.id, 'name': d.name, 'content': d.content},
        ],
        'activeId': c.activeDocumentId,
        'options': {
          'shell': 'synapseX',
          'animateReveal': false,
          'editorThemeId': preferences['editorThemeId'] ?? 'net-theme-dark',
          'diagnosticEnabled': false,
          'fontSize': 14,
          'uiScale': c.uiScale,
          'wordWrap': c.wordWrap,
          'lineNumbers': c.showLineNumbers,
          'minimap': option('minimap'),
          'minimapScale': preferences['minimapScale'] ?? 1,
          'reducedMotion': _reduceMotion,
          'brightness': 'dark',
          'background': SynapseXTheme.hex(p.editor),
          'foreground': SynapseXTheme.hex(p.text),
          'accent': '#ff6a00',
          'muted': '#858585',
          'border': '#2a2a2a',
          ..._studioEditorOptions,
        },
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    _synchronizeNative();
    final curved = option('edgeCurve');
    final opacity = _intro
        ? (_loaderOut ? 1 - Curves.easeInOut.transform(_fade.value) : 1)
        : Curves.easeInOut.transform(_fade.value);
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'SynapseInter',
        visualDensity: VisualDensity.standard,
        colorScheme: const ColorScheme.dark(
          surface: Color(0xff333333),
          primary: Color(0xffb0d8e5),
        ),
        splashFactory: NoSplash.splashFactory,
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 500),
        ),
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
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
              unawaited(_execute()),
          const SingleActivator(
            LogicalKeyboardKey.keyL,
            control: true,
            shift: true,
          ): () =>
              unawaited(_navigate('console')),
          const SingleActivator(LogicalKeyboardKey.f9): () =>
              unawaited(_navigate('console')),
        },
        child: Focus(
          autofocus: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(curved ? 7 : 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.window,
                border: curved
                    ? Border.all(color: const Color(0xff414342))
                    : null,
                borderRadius: BorderRadius.circular(curved ? 7 : 0),
              ),
              child: Opacity(
                opacity: opacity.toDouble(),
                child: Scaffold(
                  backgroundColor: p.window,
                  body: _surface(
                    Column(
                      children: [
                        _element('titleBar', _chrome(p)),
                        Expanded(
                          child: _intro
                              ? _loader()
                              : _page == 'options'
                              ? _element(
                                  'content',
                                  _element(
                                    'settingsControls',
                                    SynapseXOptions(
                                      controller: c,
                                      theme: p,
                                      nativeWindow: widget.nativeWindow,
                                      onClose: () =>
                                          unawaited(_navigate('main')),
                                      onBackToOrion: () =>
                                          unawaited(_backToOrion()),
                                      onSelectInterface: (preset) async {
                                        await flushEditor();
                                        if (mounted) {
                                          if (widget.onSelectInterface !=
                                              null) {
                                            await widget.onSelectInterface!(
                                              preset,
                                            );
                                          } else {
                                            c.setInterface(preset);
                                          }
                                        }
                                      },
                                      onNativePreferenceChanged:
                                          _nativePreferencesChanged,
                                      obscure: _obscured,
                                      onThemeStudio: () =>
                                          unawaited(_themeStudio()),
                                    ),
                                  ),
                                )
                              : _page == 'hub'
                              ? _element(
                                  'content',
                                  _element(
                                    'scriptCards',
                                    SynapseXHub(
                                      controller: c,
                                      theme: p,
                                      bridgeReady: widget.bridgeReady,
                                      onClose: () =>
                                          unawaited(_navigate('main')),
                                    ),
                                  ),
                                )
                              : _page == 'console'
                              ? _element(
                                  'content',
                                  _element(
                                    'consoleOutput',
                                    SynapseXConsole(
                                      controller: c,
                                      theme: p,
                                      onClose: () =>
                                          unawaited(_navigate('main')),
                                    ),
                                  ),
                                )
                              : _main(p),
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
    );
  }

  Widget _chrome(SynapseXTheme p) {
    final height = _intro ? 37.0 : 30.0;
    final title = _intro
        ? 'Synapse X'
        : switch (_page) {
            'options' => 'Synapse X - Options',
            'hub' => 'Synapse X - Script Hub',
            'console' => 'Synapse X - F9 Console',
            _ => 'Synapse X',
          };
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: p.panel,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.nativeWindow
                    ? (_) => windowManager.startDragging()
                    : null,
                onDoubleTap: widget.nativeWindow && option('resizable')
                    ? () async {
                        if (await windowManager.isMaximized()) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      }
                    : null,
              ),
            ),
            Positioned(
              left: 8,
              top: (height - (_intro ? 21 : 18)) / 2,
              width: (_intro ? 21 : 18) * 741.0603 / 611.33087,
              height: _intro ? 21 : 18,
              child: _logo(
                Image.asset('assets/synapse_x/logo.png', fit: BoxFit.contain),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(top: _intro ? 6.74 : .6),
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      title,
                      style: _type(
                        12,
                        color: p.text,
                        segoe: true,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!_intro)
              Positioned(
                right: 48,
                top: 3,
                width: 24,
                height: 24,
                child: _element(
                  'clientsButton',
                  Tooltip(
                    message: 'Client manager',
                    child: InkWell(
                      key: const ValueKey('x-clients'),
                      onTap: () => unawaited(
                        showBridgeClientManager(
                          context,
                          controller: c,
                          editorService: _monaco,
                        ),
                      ),
                      child: Icon(
                        Icons.devices_rounded,
                        size: 15,
                        color: p.text,
                      ),
                    ),
                  ),
                ),
              ),
            if (!_intro)
              Positioned(
                right: 0,
                top: 0,
                height: 30,
                width: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_page != 'options')
                      SizedBox(
                        width: 22,
                        child: XButton(
                          '_',
                          weight: FontWeight.w500,
                          lineHeight: 1.5,
                          onPressed: widget.nativeWindow
                              ? () => windowManager.minimize()
                              : () {},
                          theme: p,
                          size: 13,
                          segoe: true,
                          background: Colors.transparent,
                          tooltip: 'Minimize',
                        ),
                      ),
                    if (_page != 'hub')
                      SizedBox(
                        width: 22,
                        child: XButton(
                          'X',
                          weight: FontWeight.w500,
                          lineHeight: 1.5,
                          onPressed: () => _page == 'main'
                              ? onWindowClose()
                              : unawaited(_navigate('main')),
                          theme: p,
                          size: 13,
                          segoe: true,
                          background: Colors.transparent,
                          tooltip: _page == 'main' ? 'Close Orion' : 'Close',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loader() {
    final t = _loading.value;
    final pct = math.min(100, (t * 100 + math.sin(t * 12) * 3).round());
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 10, 12, 0),
      child: Column(
        children: [
          Text('Initializing...', style: _type(14)),
          const SizedBox(height: 12),
          SizedBox(
            height: 21,
            child: LayoutBuilder(
              builder: (ctx, box) => Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xff2d2d2d)),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (box.maxWidth * pct / 100).roundToDouble(),
                    child: const ColoredBox(color: Color(0xff06b025)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _main(SynapseXTheme p) => _element(
    'content',
    LayoutBuilder(
      builder: (context, box) {
        final listWidth = math.min(122.0, box.maxWidth * .19);
        return Stack(
          children: [
            Positioned(
              left: 10,
              right: listWidth + 11,
              top: 4.6,
              bottom: 46,
              child: Column(
                children: [
                  SizedBox(height: 18, child: _tabStrip(p)),
                  Expanded(
                    child: _element(
                      'editor',
                      Stack(
                        children: [
                          Positioned.fill(
                            child: _monaco != null
                                ? MonacoEditor(
                                    key: const ValueKey('code-editor'),
                                    service: _monaco!,
                                    active: !_intro && _page == 'main',
                                    backgroundColor: p.editor,
                                    foregroundColor: const Color(0xffd4d4d4),
                                    fallback: LuauCodePreview(
                                      controller: _editor,
                                      gutterWidth: 40,
                                      showLineNumbers: c.showLineNumbers,
                                      wordWrap: c.wordWrap,
                                      style: TextStyle(
                                        fontFamily: 'SynapseXMono',
                                        fontSize: 14,
                                        height: 19 / 14,
                                        color: Color(
                                          _studio
                                                  .elements['editor']
                                                  ?.foreground ??
                                              p.text.toARGB32(),
                                        ),
                                      ),
                                    ),
                                  )
                                : _fallback(p),
                          ),
                          if (_showFind) _findBar(p),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 6,
              top: 4.6,
              bottom: 46,
              width: listWidth,
              child: _element(
                'scriptList',
                ColoredBox(
                  color: p.panel,
                  child: option('enhancedList')
                      ? _enhancedList(p)
                      : _plainList(p),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 46,
              child: _element(
                'actions',
                LayoutBuilder(
                  builder: (ctx, actions) {
                    const labels = [
                      'Execute',
                      'Clear',
                      'Open File',
                      'Execute File',
                      'Save File',
                      'Options',
                      'Attach',
                      'Script Hub',
                    ];
                    final callbacks = <VoidCallback?>[
                      widget.bridgeReady ? () => unawaited(_execute()) : null,
                      () => unawaited(_clear()),
                      () => unawaited(_open()),
                      widget.bridgeReady
                          ? () => unawaited(_executeFile())
                          : null,
                      () => unawaited(_save()),
                      () => unawaited(_navigate('options')),
                      () => unawaited(
                        showBridgeClientManager(
                          context,
                          controller: c,
                          editorService: _monaco,
                        ),
                      ),
                      () => unawaited(_navigate('hub')),
                    ];
                    if (actions.maxWidth >= 791) {
                      return Stack(
                        children: [
                          for (var i = 0; i < 8; i++)
                            Positioned(
                              left: i < 6 ? 10 + i * 96 : null,
                              right: i == 6
                                  ? 102
                                  : i == 7
                                  ? 6
                                  : null,
                              top: 6,
                              width: 91,
                              height: 33,
                              child: _element(
                                const [
                                  'executeButton',
                                  'clearButton',
                                  'openButton',
                                  'executeFileButton',
                                  'saveButton',
                                  'settingsButton',
                                  'attachButton',
                                  'hubButton',
                                ][i],
                                XButton(
                                  labels[i],
                                  key: ValueKey('x-action-$i'),
                                  onPressed: callbacks[i],
                                  theme: _buttonPalette(
                                    const [
                                      'executeButton',
                                      'clearButton',
                                      'openButton',
                                      'executeFileButton',
                                      'saveButton',
                                      'settingsButton',
                                      'attachButton',
                                      'hubButton',
                                    ][i],
                                    p,
                                  ),
                                  segoe: true,
                                ),
                              ),
                            ),
                        ],
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 6, 7),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 785,
                          height: 33,
                          child: Row(
                            children: [
                              for (var i = 0; i < 8; i++) ...[
                                if (i > 0) SizedBox(width: i == 6 ? 27 : 5),
                                SizedBox(
                                  width: 91,
                                  height: 33,
                                  child: _element(
                                    const [
                                      'executeButton',
                                      'clearButton',
                                      'openButton',
                                      'executeFileButton',
                                      'saveButton',
                                      'settingsButton',
                                      'attachButton',
                                      'hubButton',
                                    ][i],
                                    XButton(
                                      labels[i],
                                      key: ValueKey('x-action-$i'),
                                      onPressed: callbacks[i],
                                      theme: _buttonPalette(
                                        const [
                                          'executeButton',
                                          'clearButton',
                                          'openButton',
                                          'executeFileButton',
                                          'saveButton',
                                          'settingsButton',
                                          'attachButton',
                                          'hubButton',
                                        ][i],
                                        p,
                                      ),
                                      segoe: true,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
  Widget _tabStrip(SynapseXTheme p) => _element(
    'tabs',
    ColoredBox(
      color: p.editor,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _tabs,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in c.documents)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        height: 16,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 72,
                            maxWidth: 260,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: _renaming == d.id
                                    ? SizedBox(
                                        width: 150,
                                        child: TextFormField(
                                          initialValue: d.name,
                                          autofocus: true,
                                          maxLength: 256,
                                          style: _type(
                                            10,
                                            color: p.color('tabText'),
                                            height: 1.4,
                                          ),
                                          decoration: const InputDecoration(
                                            isCollapsed: true,
                                            border: InputBorder.none,
                                            counterText: '',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                          ),
                                          onFieldSubmitted: (name) {
                                            c.renameDocument(d.id, name);
                                            setState(() => _renaming = null);
                                          },
                                          onChanged: (value) =>
                                              _renameDraft = value,
                                          onTapOutside: (_) {
                                            c.renameDocument(
                                              d.id,
                                              _renameDraft,
                                            );
                                            setState(() => _renaming = null);
                                          },
                                        ),
                                      )
                                    : GestureDetector(
                                        onDoubleTap: () => setState(() {
                                          _renaming = d.id;
                                          _renameDraft = d.name;
                                        }),
                                        child: TextButton(
                                          onPressed: () =>
                                              unawaited(_select(d.id)),
                                          style:
                                              TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                    ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ).copyWith(
                                                overlayColor:
                                                    const WidgetStatePropertyAll(
                                                      Colors.transparent,
                                                    ),
                                              ),
                                          child: Text(
                                            d.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: _type(
                                              10,
                                              color: d.id == c.activeDocumentId
                                                  ? Colors.white
                                                  : p.color('tabText'),
                                              weight: d.id == c.activeDocumentId
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
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
                                  message: 'Close ${d.name}',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => unawaited(_closeTab(d)),
                                    child: Center(
                                      child: CustomPaint(
                                        size: const Size(9, 9),
                                        painter: _XGlyph(
                                          p.color('iconColor'),
                                          false,
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
                ],
              ),
            ),
          ),
          SizedBox(
            width: 15,
            height: 15,
            child: Tooltip(
              message: 'Add script tab',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(_new()),
                child: CustomPaint(
                  painter: _XGlyph(p.color('iconColor'), true),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  void _configureSyntax(SynapseXTheme p) {
    _editor.useTheme(
      p.editor.toARGB32() == 0xff1e1e1e
          ? preferences['editorThemeId'] as String? ?? 'net-theme-dark'
          : 'shell-custom',
      foreground: SynapseThemeCatalog.hasStudio(c, _studioPreset)
          ? Color(_studio.elements['editor']?.foreground ?? p.text.toARGB32())
          : null,
    );
  }

  Widget _fallback(SynapseXTheme p) {
    _configureSyntax(p);
    return MediaQuery.withNoTextScaling(
      child: ColoredBox(
        color: p.editor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 40,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: Text(
                    List.generate(
                      _editor.text.split('\n').length,
                      (i) => '${i + 1}',
                    ).join('\n'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'SynapseXMono',
                      fontSize: 14,
                      height: 19 / 14,
                      color: Color(0xff858585),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('code-editor'),
                controller: _editor,
                focusNode: _editorFocus,
                maxLines: null,
                expands: true,
                style: TextStyle(
                  fontFamily: 'SynapseXMono',
                  fontSize: 14,
                  height: 19 / 14,
                  color: Color(
                    _studio.elements['editor']?.foreground ?? p.text.toARGB32(),
                  ),
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _findBar(SynapseXTheme p) => Positioned(
    right: 0,
    top: 0,
    width: math.min(300, MediaQuery.sizeOf(context).width * .5),
    height: 30,
    child: ColoredBox(
      color: p.panel,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _find,
              autofocus: true,
              style: _type(12),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Find in script',
                contentPadding: EdgeInsets.symmetric(horizontal: 6),
              ),
              onSubmitted: _findNext,
            ),
          ),
          SizedBox(
            width: 28,
            child: XButton(
              '›',
              onPressed: () => _findNext(_find.text),
              theme: p,
            ),
          ),
          SizedBox(
            width: 28,
            child: XButton(
              '×',
              onPressed: () => setState(() => _showFind = false),
              theme: p,
            ),
          ),
        ],
      ),
    ),
  );
  void _findNext(String query) {
    if (query.isEmpty) return;
    final start = _editor.selection.end.clamp(0, _editor.text.length);
    var index = _editor.text.indexOf(query, start);
    if (index < 0) index = _editor.text.indexOf(query);
    if (index >= 0) {
      _editor.selection = TextSelection(
        baseOffset: index,
        extentOffset: index + query.length,
      );
    }
  }

  Widget _plainList(SynapseXTheme p) {
    final docs = c.documents.where((d) => d.filePath != null).toList();
    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        if (docs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
            child: Text(
              'Add .lua to scripts.',
              style: _type(9, color: const Color(0xffa3a3a3), height: 1.4),
            ),
          ),
        for (final d in docs)
          Align(
            alignment: Alignment.centerLeft,
            child: XButton(
              d.name,
              onPressed: () => unawaited(_select(d.id)),
              theme: p,
              size: 11,
              background: p.panel,
            ),
          ),
      ],
    );
  }

  Widget _enhancedList(SynapseXTheme p) => ListView(
    padding: EdgeInsets.zero,
    children: [
      for (final section in [
        'Local Filesystem',
        'Bookmarks',
        'Github Gists',
      ]) ...[
        SizedBox(
          height: 26,
          child: TextButton(
            onPressed: () => setState(
              () => _localExpanded.contains(section)
                  ? _localExpanded.remove(section)
                  : _localExpanded.add(section),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.centerLeft,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '${_localExpanded.contains(section) ? '⌄' : '›'} $section',
              maxLines: 1,
              style: _type(10, color: p.color('listText')),
            ),
          ),
        ),
        if (_localExpanded.contains(section)) ...[
          if (section == 'Github Gists') ...[
            SizedBox(
              height: 24,
              child: XButton(
                'Add Gist',
                onPressed: () => unawaited(_addGist()),
                theme: p,
                size: 10,
              ),
            ),
            for (final raw in c.synapsePreferences.gistUrls)
              Row(
                children: [
                  Expanded(
                    child: XButton(
                      _loadingGist == raw
                          ? 'Loading…'
                          : V3Gists.title(Uri.parse(raw)),
                      onPressed: () => unawaited(_openGist(raw)),
                      theme: p,
                      size: 10,
                    ),
                  ),
                  SizedBox(
                    width: 18,
                    child: XButton(
                      '×',
                      onPressed: () => c.updateSynapsePreferences(
                        gistUrls: c.synapsePreferences.gistUrls
                            .where((v) => v != raw)
                            .toList(),
                      ),
                      theme: p,
                      size: 10,
                    ),
                  ),
                ],
              ),
          ] else
            for (final d in c.documents.where(
              (d) => section == 'Bookmarks'
                  ? c.synapsePreferences.bookmarkedDocumentIds.contains(d.id)
                  : d.filePath != null,
            ))
              XButton(
                d.name,
                onPressed: () => unawaited(_select(d.id)),
                theme: p,
                size: 10,
              ),
        ],
      ],
    ],
  );
  Future<void> _addGist() async {
    final text = TextEditingController();
    final raw = await _obscured(
      () => showDialog<String>(
        context: context,
        builder: (ctx) => Dialog(
          shape: const RoundedRectangleBorder(),
          backgroundColor: palette.window,
          child: SizedBox(
            width: 360,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Add Gist URL', style: _type(14)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: text,
                    autofocus: true,
                    style: _type(12),
                    decoration: const InputDecoration(
                      hintText: 'https://…/script.lua',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 29,
                        child: XButton(
                          'Cancel',
                          onPressed: () => Navigator.pop(ctx),
                          theme: palette,
                          size: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 80,
                        height: 29,
                        child: XButton(
                          'Ok',
                          onPressed: () => Navigator.pop(ctx, text.text),
                          theme: palette,
                          size: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    text.dispose();
    if (raw == null || !mounted) return;
    final uri = V3Gists.parse(raw);
    if (uri == null) {
      _message('Enter a valid raw script URL.');
      return;
    }
    c.updateSynapsePreferences(
      gistUrls: {...c.synapsePreferences.gistUrls, uri.toString()}.toList(),
    );
  }

  Future<void> _openGist(String raw) async {
    setState(() => _loadingGist = raw);
    try {
      final body = await _gistClient(Uri.parse(raw));
      await flushEditor();
      if (mounted) {
        c.newDocument(
          name: '${V3Gists.title(Uri.parse(raw))}.lua',
          content: body,
        );
      }
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => _loadingGist = null);
    }
  }
}

class _XGlyph extends CustomPainter {
  _XGlyph(this.color, this.add);
  final Color color;
  final bool add;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (add) {
      canvas.drawLine(
        Offset(size.width / 2, 3),
        Offset(size.width / 2, size.height - 3),
        p,
      );
      canvas.drawLine(
        Offset(3, size.height / 2),
        Offset(size.width - 3, size.height / 2),
        p,
      );
    } else {
      canvas.drawLine(
        const Offset(1, 1),
        Offset(size.width - 1, size.height - 1),
        p,
      );
      canvas.drawLine(Offset(size.width - 1, 1), Offset(1, size.height - 1), p);
    }
  }

  @override
  bool shouldRepaint(_XGlyph old) => old.color != color || old.add != add;
}
