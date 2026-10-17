import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/orion_models.dart';
import '../models/interface_preset.dart';
import '../models/synapse_studio_theme.dart';
import '../services/synapse_theme_catalog.dart';
import '../widgets/synapse_theme_surface.dart';
import '../services/monaco_editor_service.dart';
import '../state/orion_controller.dart';
import '../widgets/monaco_editor.dart';
import '../widgets/luau_syntax.dart';
import '../widgets/bridge_client_manager.dart';
import 'synapse_v3_theme.dart';
import 'v3_icon.dart';

/// Framework's independent V3 editor. The bootstrap owns its native window,
/// pinned companion controller and isolated Monaco service.
class V3UndockedEditor extends StatefulWidget {
  const V3UndockedEditor({
    super.key,
    required this.controller,
    required this.nativeWindow,
    this.editorService,
    this.bridgeReady = false,
    this.pickScriptPath,
    this.pickSavePath,
  });
  final OrionController controller;
  final bool nativeWindow, bridgeReady;
  final MonacoEditorService? editorService;
  final Future<String?> Function()? pickScriptPath;
  final Future<String?> Function(String suggestedName)? pickSavePath;
  @override
  State<V3UndockedEditor> createState() => V3UndockedEditorState();
}

class V3UndockedEditorState extends State<V3UndockedEditor> {
  final _text = LuauSyntaxController();
  final _focus = FocusNode();
  bool _syncing = false, _redocking = false;
  late final String _documentId;
  OrionController get c => widget.controller;
  static const _studioPreset = InterfacePreset.synapseV3;
  static const _studioWindow = 'undockedEditor';
  SynapseStudioWindow get _studio =>
      SynapseThemeCatalog.current(c, _studioPreset).window(_studioWindow);
  Widget _element(String id, Widget child) => SynapseThemeElement(
    controller: c,
    preset: _studioPreset,
    windowId: _studioWindow,
    elementId: id,
    child: child,
  );
  Map<String, Object?> get _studioEditorOptions {
    final image = _studio.elements['editor']?.image ?? _studio.background;
    final element = _studio.elements['editor'];
    String hex(int value) =>
        '#${(value & 0xffffff).toRadixString(16).padLeft(6, '0')}';
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
          (element?.opacity ?? 1) * (_studio.elements['content']?.opacity ?? 1),
      'studioEditorRadius': element?.radius,
      if (element?.fill != null) 'background': hex(element!.fill!),
      if (element?.foreground != null) 'foreground': hex(element!.foreground!),
    };
  }

  MonacoEditorService? get _monaco => widget.editorService;
  EditorDocument get _document =>
      c.documents.where((d) => d.id == _documentId).firstOrNull ??
      c.activeDocument;
  V3Colors get _colors => V3Colors.fromColors(
    background: c.synapsePreferences.themeBackground,
    accent: c.synapsePreferences.themeAccent,
    legacyFramework: c.synapsePreferences.themePreset == 'legacyFramework',
    overrides: SynapseThemeCatalog.colors(c, _studioPreset, _studioWindow),
  );
  TextStyle _type(double size, {Color color = Colors.white}) => V3Type.text(
    size,
    color: color,
    family:
        SynapseThemeCatalog.current(c, _studioPreset).fontFamily ??
        c.synapsePreferences.uiFontFamily,
  );

  @override
  void initState() {
    super.initState();
    _documentId = c.companionWindows?.documentId ?? c.activeDocumentId;
    c.addListener(_changed);
    _monaco?.addListener(_nativeChanged);
    _text.addListener(_edited);
    _changed();
  }

  void _changed() {
    final content = _document.content;
    if (_text.text != content) {
      _syncing = true;
      _text.value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(
          offset: _text.selection.extentOffset.clamp(0, content.length),
        ),
      );
      _syncing = false;
    }
    if (mounted) setState(() {});
  }

  void _nativeChanged() {
    if (mounted) setState(() {});
  }

  void _edited() {
    if (!_syncing) c.updateDocumentContent(_documentId, _text.text);
  }

  Future<void> flushEditor() async => _monaco?.flush();

  void _synchronize() {
    final palette = _colors;
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    _monaco?.setActive(!_redocking);
    unawaited(
      _monaco?.synchronize({
            'documents': [
              {
                'id': _document.id,
                'name': _document.name,
                'content': _document.content,
              },
            ],
            'activeId': _documentId,
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

  Future<void> redock() async {
    if (_redocking) return;
    await flushEditor();
    if (!mounted || _redocking) return;
    setState(() => _redocking = true);
    _monaco?.setActive(false);
    try {
      await c.flushPersistence();
      await c.companionWindows?.close();
    } on Object {
      if (mounted) {
        setState(() => _redocking = false);
        _monaco?.setActive(true);
      }
    }
  }

  String _sourceTitle(String path) {
    final base = path
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.lua$', caseSensitive: false), '');
    final title = base
        .split(RegExp('[-_]+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
    return title.substring(0, math.min(80, title.length));
  }

  Future<T?> _dialog<T>(Future<T?> Function() callback) async {
    try {
      await _monaco?.freezeForOverlay(owner: 'v3-undocked-file');
      if (!mounted) return null;
      return await callback();
    } finally {
      _monaco?.setObscured(false, owner: 'v3-undocked-file');
    }
  }

  Future<String?> _pickOpen() => _dialog(() async {
    if (widget.pickScriptPath != null) return widget.pickScriptPath!();
    return (await files.openFile(
      confirmButtonText: 'Open script',
      acceptedTypeGroups: const [
        files.XTypeGroup(label: 'Lua', extensions: ['lua']),
      ],
    ))?.path;
  });

  Future<void> _open() async {
    if (_redocking) return;
    await flushEditor();
    final path = await _pickOpen();
    if (path == null || !mounted) return;
    if (await c.importDocumentFromPath(path, replaceId: _documentId) != null) {
      c.renameDocument(_documentId, _sourceTitle(path));
    }
  }

  Future<void> _save({bool saveAs = false}) async {
    if (_redocking) return;
    await flushEditor();
    final document = _document;
    var path = saveAs ? null : document.filePath;
    path ??= await _dialog(() async {
      final name =
          '${document.name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim()}.lua';
      if (widget.pickSavePath != null) return widget.pickSavePath!(name);
      return (await files.getSaveLocation(
        suggestedName: name,
        confirmButtonText: 'Save script',
        acceptedTypeGroups: const [
          files.XTypeGroup(label: 'Lua', extensions: ['lua']),
        ],
      ))?.path;
    });
    if (path == null || !mounted) return;
    if (await c.saveDocumentToPath(_documentId, path)) {
      c.renameDocument(_documentId, _sourceTitle(path));
    }
  }

  Future<void> _clear() async {
    if (_redocking) return;
    await flushEditor();
    if (!mounted) return;
    c.updateDocumentContent(_documentId, '');
    await _monaco?.action('clear');
    _focus.requestFocus();
  }

  Future<void> _execute({bool file = false}) async {
    if (!widget.bridgeReady || _redocking) return;
    await flushEditor();
    if (file) {
      final path = await _pickOpen();
      if (path != null && mounted) {
        c.executeSource(
          await File(path).readAsString(),
          name: path.split('/').last,
        );
      }
    } else {
      c.execute(source: _document.content, name: _document.name);
    }
  }

  void handleEditorShortcut(String name) {
    switch (name) {
      case 'save':
        unawaited(_save());
      case 'saveAs':
      case 'save-as':
        unawaited(_save(saveAs: true));
      case 'open':
        unawaited(_open());
      case 'clear':
        unawaited(_clear());
      case 'execute':
        unawaited(_execute());
      case 'close-tab':
      case 'redock':
        unawaited(redock());
      case 'find':
      case 'replace':
      case 'suggest':
      case 'commands':
        unawaited(_monaco?.action(name) ?? Future<void>.value());
    }
  }

  Future<void> _maximize() async {
    if (!widget.nativeWindow) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    _synchronize();
    final palette = _colors;
    final radius = BorderRadius.circular(c.synapsePreferences.cornerRadius);
    return Theme(
      data: V3ThemeData.theme(
        palette.accent,
        palette.background,
        legacyFramework: c.synapsePreferences.themePreset == 'legacyFramework',
        overrides: SynapseThemeCatalog.colors(c, _studioPreset, _studioWindow),
        family:
            SynapseThemeCatalog.current(c, _studioPreset).fontFamily ??
            c.synapsePreferences.uiFontFamily,
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
              handleEditorShortcut('open'),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              handleEditorShortcut('save'),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () =>
              handleEditorShortcut('saveAs'),
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
              handleEditorShortcut('execute'),
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
              unawaited(redock()),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: radius,
              child: SynapseThemeSurface(
                controller: c,
                preset: _studioPreset,
                windowId: _studioWindow,
                child: Container(
                  key: const ValueKey('v3-undocked-shell'),
                  decoration: BoxDecoration(color: palette.background),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: palette.shellBorder),
                  ),
                  child: _redocking
                      ? Center(
                          child: Text(
                            'Returning…',
                            style: _type(14, color: const Color(0xffd4d4d4)),
                          ),
                        )
                      : _element(
                          'content',
                          Stack(
                            children: [
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: 44,
                                child: _element('titleBar', _chrome(palette)),
                              ),
                              Positioned(
                                top: 45,
                                bottom: 46,
                                left: 1,
                                right: 1,
                                child: ColoredBox(
                                  color: palette.editor,
                                  child: _element('editor', _editor(palette)),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 46,
                                child: _element('actions', _actions(palette)),
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

  Widget _chrome(V3Colors palette) => ColoredBox(
    color: palette.topBar,
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              if (widget.nativeWindow) unawaited(windowManager.startDragging());
            },
          ),
        ),
        Positioned(
          left: 12,
          top: 14,
          right: 110,
          child: Text(
            'Undocked editor - ${_document.name.trim().isEmpty ? 'Script' : _document.name.trim()}',
            key: const ValueKey('v3-undocked-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _type(12, color: const Color(0xff9a9a9a)),
          ),
        ),
        Positioned(
          right: 82,
          top: 0,
          width: 11,
          height: 32,
          child: _UndockedChromeHit(
            label: 'Minimize',
            onPressed: () {
              if (widget.nativeWindow) unawaited(windowManager.minimize());
            },
            child: Text(
              '_',
              style: _type(24),
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
        Positioned(
          right: 40,
          top: 12,
          width: 24,
          height: 24,
          child: _UndockedChromeHit(
            label: 'Maximize',
            onPressed: () => unawaited(_maximize()),
            child: const CustomPaint(
              size: Size.square(11),
              painter: _UndockedSymbol('maximize'),
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 12,
          width: 24,
          height: 24,
          child: _UndockedChromeHit(
            label: 'Redock editor',
            onPressed: () => unawaited(redock()),
            child: const CustomPaint(
              size: Size.square(11),
              painter: _UndockedSymbol('close'),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _editor(V3Colors palette) {
    _text.useTheme(
      'synapse-v3',
      foreground: SynapseThemeCatalog.hasStudio(c, _studioPreset)
          ? Color(
              _studio.elements['editor']?.foreground ?? palette.text.toARGB32(),
            )
          : null,
    );
    return MediaQuery.withNoTextScaling(
      child: _monaco != null
          ? MonacoEditor(
              key: const ValueKey('v3-undocked-editor'),
              service: _monaco!,
              active: !_redocking,
              backgroundColor: palette.editor,
              fallback: LuauCodePreview(
                controller: _text,
                gutterWidth: 0,
                showLineNumbers: false,
                wordWrap: c.wordWrap,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: c.editorFontSize,
                  height: 20 / c.editorFontSize,
                  color: Color(
                    _studio.elements['editor']?.foreground ??
                        palette.text.toARGB32(),
                  ),
                ),
              ),
            )
          : TextField(
              key: const ValueKey('v3-undocked-editor'),
              controller: _text,
              focusNode: _focus,
              maxLines: null,
              expands: true,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: c.editorFontSize,
                height: 20 / c.editorFontSize,
                color: _studio.elements['editor']?.foreground == null
                    ? palette.text
                    : Color(_studio.elements['editor']!.foreground!),
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                visualDensity: VisualDensity.standard,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
    );
  }

  Widget _actions(V3Colors palette) => ColoredBox(
    color: palette.actionBar,
    child: LayoutBuilder(
      builder: (_, box) => Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: math.max(602.0, box.maxWidth - 8),
              height: 33,
              child: Row(
                children: [
                  _action(
                    'Execute',
                    'play20Filled',
                    'Execute script',
                    palette,
                    widget.bridgeReady ? () => unawaited(_execute()) : null,
                  ),
                  const SizedBox(width: 4),
                  _action(
                    'Clear',
                    'eraser20Filled',
                    'Clear script',
                    palette,
                    () => unawaited(_clear()),
                  ),
                  const SizedBox(width: 4),
                  _action(
                    'Open',
                    'documentArrowUp20Filled',
                    'Open file',
                    palette,
                    () => unawaited(_open()),
                  ),
                  const SizedBox(width: 4),
                  _action(
                    'Save',
                    'save20Filled',
                    'Save file',
                    palette,
                    () => unawaited(_save()),
                  ),
                  const SizedBox(width: 4),
                  _action(
                    'Execute',
                    'settings20Filled',
                    'Execute file',
                    palette,
                    widget.bridgeReady
                        ? () => unawaited(_execute(file: true))
                        : null,
                  ),
                  const Spacer(),
                  _element(
                    'clientsButton',
                    IconButton(
                      key: const ValueKey('v3-undocked-clients'),
                      tooltip: 'Client manager',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.devices_rounded,
                        size: 18,
                        color: palette.text,
                      ),
                      onPressed: () => unawaited(
                        showBridgeClientManager(
                          context,
                          controller: c,
                          editorService: _monaco,
                        ),
                      ),
                    ),
                  ),
                  _action(
                    'Redock',
                    null,
                    'Redock',
                    palette,
                    () => unawaited(redock()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _action(
    String label,
    String? icon,
    String tooltip,
    V3Colors palette,
    VoidCallback? callback,
  ) {
    final id = switch (tooltip) {
      'Execute script' => 'executeButton',
      'Execute file' => 'executeFileButton',
      'Open file' => 'openButton',
      'Save file' => 'saveButton',
      'Clear script' => 'clearButton',
      _ => 'redockButton',
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
    return _element(
      switch (tooltip) {
        'Execute script' => 'executeButton',
        'Execute file' => 'executeFileButton',
        'Open file' => 'openButton',
        'Save file' => 'saveButton',
        'Clear script' => 'clearButton',
        _ => 'redockButton',
      },
      Tooltip(
        message: tooltip,
        child: SizedBox(
          key: ValueKey('v3-undocked-action-$tooltip'),
          width: 91,
          height: 33,
          child: TextButton(
            onPressed: callback,
            style:
                TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  disabledBackgroundColor: hasImage
                      ? Colors.transparent
                      : palette.buttonDisabled,
                  disabledForegroundColor: palette.buttonDisabledText,
                  foregroundColor: foreground,
                  backgroundColor: fill,
                  textStyle: _type(14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(element?.radius ?? 4),
                    side: BorderSide(
                      color: element?.border == null
                          ? palette.buttonBorder
                          : Color(element!.border!),
                    ),
                  ),
                ).copyWith(
                  overlayColor: WidgetStatePropertyAll(
                    callback == null ? Colors.transparent : palette.buttonHover,
                  ),
                ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null)
                  V3Icon(
                    icon,
                    size: 14,
                    color: callback == null
                        ? palette.buttonDisabledIcon
                        : palette.buttonIcon,
                  )
                else
                  CustomPaint(
                    size: const Size.square(14),
                    painter: _UndockedSymbol(
                      'redock',
                      color: palette.buttonIcon,
                    ),
                  ),
                const SizedBox(width: 4),
                Text(label, style: _type(14, color: foreground)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _monaco?.removeListener(_nativeChanged);
    _monaco?.setObscured(false, owner: 'v3-undocked-file');
    _text.removeListener(_edited);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }
}

class _UndockedChromeHit extends StatefulWidget {
  const _UndockedChromeHit({
    required this.label,
    required this.onPressed,
    required this.child,
  });
  final String label;
  final VoidCallback onPressed;
  final Widget child;
  @override
  State<_UndockedChromeHit> createState() => _UndockedChromeHitState();
}

class _UndockedChromeHitState extends State<_UndockedChromeHit> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.label,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Center(
          child: Opacity(opacity: _hover ? .8 : 1, child: widget.child),
        ),
      ),
    ),
  );
}

class _UndockedSymbol extends CustomPainter {
  const _UndockedSymbol(this.symbol, {this.color = Colors.white});
  final String symbol;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final viewport = symbol == 'redock' ? 24.0 : 11.0;
    canvas.scale(size.width / viewport, size.height / viewport);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = symbol == 'redock' ? 2 : 1.1;
    if (symbol == 'maximize') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(.5, .5, 10, 10),
          const Radius.circular(1.25),
        ),
        paint,
      );
    } else if (symbol == 'close') {
      canvas.translate(0, 11);
      canvas.scale(1, -1);
      canvas.drawPath(
        Path()
          ..moveTo(10.5, 10.5)
          ..lineTo(.5, .5)
          ..moveTo(1, 10.5)
          ..lineTo(10.5, .5),
        paint,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(4, 8)
          ..lineTo(4, 4)
          ..lineTo(8, 4)
          ..moveTo(20, 16)
          ..lineTo(20, 20)
          ..lineTo(16, 20)
          ..moveTo(4, 4)
          ..lineTo(10, 10)
          ..moveTo(20, 20)
          ..lineTo(14, 14),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 8, 8, 8),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_UndockedSymbol old) =>
      old.symbol != symbol || old.color != color;
}
