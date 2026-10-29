import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/orion_models.dart';
import '../models/interface_preset.dart';
import '../models/synapse_studio_theme.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import '../theme/orion_surfaces.dart';
import '../theme/orion_density.dart';
import '../theme/expressive_motion.dart';
import '../widgets/common.dart';
import '../widgets/bridge_client_manager.dart';
import '../widgets/connected_action_group.dart';
import '../widgets/orion_overlay.dart';
import '../widgets/orion_popup_menu.dart';
import '../widgets/monaco_editor.dart';
import '../widgets/editor_tab_strip.dart';
import '../widgets/native_desktop_glass.dart';
import '../widgets/script_explorer.dart';
import '../widgets/orion_studio_layer.dart';
import '../widgets/orion_glass.dart';
import '../services/synapse_theme_catalog.dart';
import '../services/monaco_editor_service.dart';

class WorkspaceScreen extends StatefulWidget {
  final OrionController controller;
  final VoidCallback onLibrary, onSave, onOpen;
  final bool nativeEditor, active;
  final ValueChanged<String>? onShortcut;
  final MonacoEditorService? editorService;
  const WorkspaceScreen({
    super.key,
    required this.controller,
    required this.onLibrary,
    required this.onSave,
    required this.onOpen,
    this.nativeEditor = false,
    this.active = true,
    this.onShortcut,
    this.editorService,
  });
  @override
  State<WorkspaceScreen> createState() => WorkspaceScreenState();
}

class WorkspaceScreenState extends State<WorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final LuaEditingController _editor;
  late final AnimationController _tabMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
    value: 1,
  );
  late final Animation<double> _tabOpacity = Tween(
    begin: .6,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _tabMotion, curve: OrionMotion.effects));
  final _editorFocus = FocusNode();
  final _findFocus = FocusNode();
  final _find = TextEditingController();
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _consoleScroll = ScrollController();
  double _consoleHeight = 100;
  bool _resizingConsole = false;
  MonacoEditorService? _monaco;
  bool _ownsMonaco = false;
  Object? _nativePresentation;
  OrionColors? _windowColors;
  BuildContext? _editorLayerContext;
  final Map<String, int> _lineCountByDocument = {};
  final Map<String, String> _lastSyncedContentByDocument = {};
  bool _studioGeometryQueued = false;
  (double, double, double)? _lineHeightCacheLayout;
  final Map<int, (String, double)> _lineHeightCache = {};
  String? _lastExecution;
  String _documentId = '';
  bool _syncing = false;
  bool _showFind = false;
  bool _showConsole = false;
  String _findMessage = '';
  OrionController get c => widget.controller;
  OrionDensity get _density => c.selectedInterface == InterfacePreset.orion
      ? OrionDensity.of(context)
      : OrionDensity.comfortable;
  double _space(double comfortable, double compact) =>
      _density.mix(comfortable, compact);
  bool get _compact => _density.isCompact;
  bool get _orionStudio =>
      c.selectedInterface == InterfacePreset.orion &&
      SynapseThemeCatalog.hasStudio(c, InterfacePreset.orion);
  SynapseStudioWindow get _studio =>
      SynapseThemeCatalog.current(c, InterfacePreset.orion).window('main');
  String? get _studioFont => _orionStudio
      ? SynapseThemeCatalog.current(c, InterfacePreset.orion).fontFamily
      : OrionType.family;
  SynapseStudioElement? _studioStyle(String id) =>
      _orionStudio ? _studio.elements[id] : null;
  bool _glassEnabled(OrionColors colors, [String? id]) {
    if (c.selectedInterface != InterfacePreset.orion || !colors.glassEnabled) {
      return false;
    }
    if (id == 'editor' && colors.opaqueSurfaceRoles.contains('editor')) {
      return false;
    }
    for (final layer in {
      'content',
      'workspace',
      if (const {
        'fileActions',
        'executorActions',
        'executeButton',
        'clientsButton',
        'openButton',
        'saveButton',
        'clearButton',
      }.contains(id))
        'actions',
      ?id,
    }) {
      final edit = _studioStyle(layer);
      if (edit?.fill != null && Color(edit!.fill!).a == 1 ||
          edit?.image?.isValid == true && edit!.image!.opacity > 0) {
        return false;
      }
    }
    return true;
  }

  Widget _glassSurface(
    String id,
    OrionColors colors,
    Widget child, {
    double radius = 16,
    bool interactive = false,
  }) {
    final glass = _glassEnabled(colors, id);
    final inheritedSheet = id == 'scriptList' || id == 'consoleOutput';
    return OrionGlassSurface(
      key: ValueKey('workspace-glass-$id'),
      enabled:
          glass &&
          !inheritedSheet &&
          !(id == 'editor' && _monaco?.ready == true),
      radius: _studioStyle(id)?.radius ?? radius,
      tint: Colors.transparent,
      blur: id == 'editor' ? 2 : 3,
      showRim: false,
      edgeRefraction: false,
      interactive: interactive,
      // Lists and output inherit the window's material. Their faint tone
      // separates content without stacking more lenses or border boxes.
      child: inheritedSheet
          ? ColoredBox(
              color: glass
                  ? colors.ink.withValues(
                      alpha: id == 'scriptList' ? .012 : .008,
                    )
                  : Colors.transparent,
              child: child,
            )
          : child,
    );
  }

  Widget _studioLayer(String id, Widget Function(OrionColors) builder) {
    Widget content(OrionColors colors) {
      final child = builder(colors);
      return switch (id) {
        // WebKit paints the matching optical substrate itself. A second
        // Flutter sheet underneath would compound its translucent backdrop;
        // frozen native previews already contain the same sheet and rim.
        'editor' => _glassSurface(id, colors, child, radius: 20),
        'scriptList' => _glassSurface(id, colors, child, radius: 18),
        'consoleOutput' => _glassSurface(id, colors, child, radius: 14),
        _ => child,
      };
    }

    return !_orionStudio
        ? content(OrionColors.of(context))
        : OrionStudioLayer(
            controller: c,
            elementId: id,
            child: Builder(
              builder: (context) {
                if (id == 'editor') _editorLayerContext = context;
                return content(OrionColors.of(context));
              },
            ),
          );
  }

  @override
  void initState() {
    super.initState();
    _editor = LuaEditingController();
    final savedHeight = c.getInterfacePreferences(
      InterfacePreset.orion,
    )['consoleHeight'];
    if (savedHeight is num && savedHeight.isFinite) {
      _consoleHeight = savedHeight.toDouble().clamp(48, 2000);
    }
    if (widget.editorService != null) {
      _monaco = widget.editorService!..addListener(_nativeChanged);
    } else if (widget.nativeEditor) {
      _ownsMonaco = true;
      _monaco = MonacoEditorService(
        onChange: (id, content) => c.updateDocumentContent(id, content),
        onShortcut: (name) => widget.onShortcut?.call(name),
      )..addListener(_nativeChanged);
    }
    _sync();
    _editor.addListener(_edited);
    c.addListener(_controllerChanged);
  }

  @override
  void dispose() {
    c.removeListener(_controllerChanged);
    _editor.removeListener(_edited);
    _editor.dispose();
    _monaco?.removeListener(_nativeChanged);
    if (_ownsMonaco) _monaco?.dispose();
    _tabMotion.dispose();
    _editorFocus.dispose();
    _findFocus.dispose();
    _find.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    _consoleScroll.dispose();
    super.dispose();
  }

  void _sync() {
    final latest = c.latestExecutionId;
    if (latest != null && latest != _lastExecution) {
      final followOutput =
          !_consoleScroll.hasClients ||
          _consoleScroll.position.extentAfter < 24;
      _showConsole = true;
      if (followOutput) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _consoleScroll.hasClients) {
            _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
          }
        });
      }
    }
    _lastExecution = latest;
    final doc = c.activeDocument;
    _lineCountByDocument[doc.id] = doc.lineCount;
    if (doc.id != _documentId || doc.content != _editor.text) {
      _syncing = true;
      final changing = doc.id != _documentId;
      if (changing && _documentId.isNotEmpty) {
        if (c.reducedMotion) {
          _tabMotion.value = 1;
        } else {
          _tabMotion.forward(from: 0);
        }
      }
      _documentId = doc.id;
      _editor.value = TextEditingValue(
        text: doc.content,
        selection: TextSelection.collapsed(
          offset: changing
              ? 0
              : math.min(
                  _editor.selection.baseOffset.clamp(0, doc.content.length),
                  doc.content.length,
                ),
        ),
      );
      _lastSyncedContentByDocument[doc.id] = doc.content;
      _syncing = false;
    }
  }

  int get _activeLineCount => _lineCountByDocument[_documentId] ?? 1;

  void _controllerChanged() {
    _sync();
    if (mounted && widget.active) setState(() {});
  }

  void _edited() {
    if (_syncing) return;
    final content = _editor.text;
    _lastSyncedContentByDocument[_documentId] = content;
    c.updateDocumentContent(_documentId, content);
    if (mounted) setState(() {});
  }

  void _nativeChanged() {
    final next = (
      _monaco?.ready,
      _monaco?.initializing,
      _monaco?.error,
      _monaco?.visible,
      _monaco?.visualMirror,
      _monaco?.frozenPreview,
    );
    if (next != _nativePresentation) {
      _nativePresentation = next;
      if (mounted) setState(() {});
    }
  }

  Future<void> flushEditor() async => _monaco?.flush();
  Future<void> _selectDocument(String id) async {
    await flushEditor();
    if (mounted && c.documents.any((doc) => doc.id == id)) c.selectDocument(id);
  }

  Future<void> _newDocument() async {
    await flushEditor();
    if (mounted) c.newDocument();
  }

  void setEditorObscured(bool value, {String owner = 'route'}) =>
      _monaco?.setObscured(value, owner: owner);
  void setEditorTransitioning(bool value) {
    _monaco?.setTransitioning(value);
    if (mounted) setState(() {});
  }

  void _synchronizeMonaco(OrionColors colors) {
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final studio = _orionStudio ? _studio : null;
    final editor = studio?.elements['editor'];
    SynapseStudioImage? visibleImage(SynapseStudioImage? image) =>
        image?.isValid == true && image!.opacity > 0 ? image : null;
    final localImage = visibleImage(editor?.image);
    final workspaceImage = visibleImage(studio?.elements['workspace']?.image);
    final contentImage = visibleImage(studio?.elements['content']?.image);
    bool opaque(int? fill) => fill != null && Color(fill).a == 1;
    final inheritedImage = opaque(editor?.fill)
        ? null
        : workspaceImage ??
              (opaque(studio?.elements['workspace']?.fill)
                  ? null
                  : contentImage ??
                        (opaque(studio?.elements['content']?.fill)
                            ? null
                            : visibleImage(studio?.background)));
    final image = localImage ?? inheritedImage;
    final overlay = visibleImage(studio?.overlay);
    final glassEditor = _glassEnabled(colors, 'editor');
    final transparentEditor =
        glassEditor ||
        image != null ||
        (colors.transparentSurfaces &&
            !colors.opaqueSurfaceRoles.contains('editor'));
    final windowColors = _windowColors ?? colors;
    final backdrop = windowColors.backgroundGradient;
    final glassGradient = OrionGlassBackdrop.gradientFor(
      windowColors.background,
      authoredGradient: windowColors.backgroundGradient,
      useAuthoredBackground: true,
    );
    final glassLights = OrionGlassBackdrop.lightsFor(windowColors.background);
    final opacity =
        (editor?.opacity ?? 1) *
        (studio?.elements['workspace']?.opacity ?? 1) *
        (studio?.elements['content']?.opacity ?? 1);
    final imageLayerOpacity = image == null
        ? 1.0
        : identical(image, localImage)
        ? opacity
        : identical(image, workspaceImage)
        ? (studio?.elements['workspace']?.opacity ?? 1) *
              (studio?.elements['content']?.opacity ?? 1)
        : identical(image, contentImage)
        ? (studio?.elements['content']?.opacity ?? 1)
        : 1.0;
    final imageFill = identical(image, localImage)
        ? editor?.fill
        : identical(image, workspaceImage)
        ? studio?.elements['workspace']?.fill
        : identical(image, contentImage)
        ? studio?.elements['content']?.fill
        : null;
    final imageRegion =
        identical(image, workspaceImage) && workspaceImage != null
        ? _studioImageRegion('workspace')
        : identical(image, contentImage) && contentImage != null
        ? _studioImageRegion('content')
        : null;
    String editorHex(Color color) => color.a == 1
        ? hex(color)
        : '${hex(color)}${(color.a * 255).round().toRadixString(16).padLeft(2, '0')}';
    final direction = Directionality.of(context);
    unawaited(
      _monaco?.synchronize({
            'documents': [
              for (final doc in c.documents)
                {'id': doc.id, 'name': doc.name, 'content': doc.content},
            ],
            'activeId': c.activeDocumentId,
            'options': {
              'fontSize': c.editorFontSize,
              // The managed bridge script cannot be modified while its guard
              // is enabled; the native editor mirrors that lock.
              'readOnly': c.activeDocumentIsBridgeScriptLocked,
              'uiScale': c.uiScale,
              'wordWrap': c.wordWrap,
              'lineNumbers': c.showLineNumbers,
              'minimap': c.showMinimap,
              'autocomplete': c.autocomplete,
              'bracketPairColorization': c.bracketPairColorization,
              'renderWhitespace': c.renderWhitespace,
              'reducedMotion':
                  c.reducedMotion || MediaQuery.disableAnimationsOf(context),
              // Orion already animates page changes in Flutter. Replaying the
              // GTK WebKit reveal on each map/unmap made Monaco flash in normal
              // themes when a transient layout transition hid the native view.
              'animateReveal': false,
              'brightness': colors.isLight ? 'light' : 'dark',
              'shell': c.selectedInterface == InterfacePreset.orion
                  ? 'orion'
                  : '',
              'background': editorHex(colors.editorColor),
              'transparentBackground': transparentEditor,
              'glassEnabled': glassEditor,
              'compositorGlass':
                  glassEditor && NativeDesktopGlassScope.isActiveOf(context),
              if (glassEditor) ...{
                'glassEditorRadius': editor?.radius ?? 20,
                'glassTint': '#00000000',
                'glassMaterialOpacity':
                    OrionGlassSurface.defaultMaterialOpacity,
              },
              if (transparentEditor || studio != null)
                'windowBackdrop': {
                  // An opaque owned canvas prevents retained software-WebKit
                  // pixels; the native window supplies desktop transparency.
                  'color': hex(windowColors.background),
                  if (glassEditor) ...{
                    'opacity': OrionGlassSurface.defaultMaterialOpacity,
                    'radials': [
                      for (final light in glassLights)
                        {
                          'colors': light.colors.map(editorHex).toList(),
                          'stops': light.stops,
                          'center': [
                            light.center.resolve(direction).x,
                            light.center.resolve(direction).y,
                          ],
                          'radius': light.radius,
                        },
                    ],
                  },
                  if (glassEditor || backdrop != null)
                    'gradient': {
                      'colors': glassEditor
                          ? glassGradient.colors.map(editorHex).toList()
                          : backdrop!.colors.map(hex).toList(),
                      'stops': glassEditor
                          ? glassGradient.stops
                          : backdrop!.stops,
                      'begin': [
                        (glassEditor ? glassGradient : backdrop!).begin
                            .resolve(direction)
                            .x,
                        (glassEditor ? glassGradient : backdrop!).begin
                            .resolve(direction)
                            .y,
                      ],
                      'end': [
                        (glassEditor ? glassGradient : backdrop!).end
                            .resolve(direction)
                            .x,
                        (glassEditor ? glassGradient : backdrop!).end
                            .resolve(direction)
                            .y,
                      ],
                    },
                },
              'surface': hex(colors.elevated),
              if (!glassEditor &&
                  colors.backgroundGradient != null &&
                  !colors.transparentSurfaces &&
                  !c.orionTheme.overrides.containsKey('editor'))
                'backgroundGradient': {
                  'colors':
                      orionSurfaceGradient(
                            colors,
                            base: colors.editorColor,
                            blend: .75,
                          )!.colors
                          .map(
                            (color) => hex(
                              Color.alphaBlend(color, colors.editorColor),
                            ),
                          )
                          .toList(),
                  'stops': colors.backgroundGradient!.stops,
                  'angle': c.orionTheme.gradientAngle + 90,
                },
              'foreground': hex(colors.ink),
              'accent': hex(colors.accent),
              'muted': hex(colors.muted),
              'border': hex(colors.border),
              'studioEditorEnabled': studio != null,
              if (studio != null) ...{
                'studioWindowBackground': hex(windowColors.background),
                'studioBackgroundImage': image?.data,
                'studioBackgroundLocal': localImage != null,
                'studioBackgroundOpacity': image?.opacity,
                'studioBackgroundLayerOpacity': imageLayerOpacity,
                'studioBackgroundRegion': imageRegion,
                'studioBackgroundFill': imageFill == null
                    ? null
                    : editorHex(Color(imageFill)),
                'studioBackgroundFit': image?.fit,
                'studioOverlayImage': overlay?.data,
                'studioOverlayOpacity': overlay?.opacity,
                'studioOverlayFit': overlay?.fit,
                'studioEditorTransparent': transparentEditor,
                'studioEditorOpacity': opacity,
                'studioEditorRadius': editor?.radius,
              },
            },
          }) ??
          Future<void>.value(),
    );
    // Ancestor image bounds become available after layout. Update the same
    // document snapshot once then; the editor service suppresses equal sends.
    if (_monaco != null &&
        (workspaceImage != null || contentImage != null) &&
        !_studioGeometryQueued &&
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.postFrameCallbacks) {
      _studioGeometryQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _studioGeometryQueued = false;
        if (mounted && _orionStudio) _synchronizeMonaco(colors);
      });
    }
  }

  Map<String, double>? _studioImageRegion(String id) {
    final context = _editorLayerContext;
    if (context == null || !context.mounted) return null;
    Rect? bounds;
    context.visitAncestorElements((element) {
      if (element.widget case OrionStudioLayer(
        elementId: final elementId,
      ) when elementId == id) {
        final object = element.findRenderObject();
        if (object is RenderBox && object.attached && object.hasSize) {
          RenderBox target = object is RenderTransform && object.child != null
              ? object.child!
              : object;
          final edit = _studioStyle(id);
          if (edit?.width != null || edit?.height != null) {
            RenderBox candidate = target;
            for (var i = 0; i < 10; i++) {
              if (candidate is RenderPositionedBox && candidate.child != null) {
                target = candidate.child!;
                break;
              }
              RenderObject? first;
              candidate.visitChildren((child) => first ??= child);
              if (first is! RenderBox) break;
              candidate = first as RenderBox;
            }
          }
          bounds = MatrixUtils.transformRect(
            target.getTransformTo(null),
            Offset.zero & target.size,
          );
        }
        return false;
      }
      return true;
    });
    final rect = bounds;
    // GTK divides editor/window bounds by this zoom before sending them to
    // WebKit. Ancestor bounds include UiScaleViewport's transform, so convert
    // them to the same CSS coordinate space for correctly aligned images.
    final scale = c.uiScale;
    return rect != null && rect.isFinite && rect.width > 0 && rect.height > 0
        ? {
            'x': rect.left / scale,
            'y': rect.top / scale,
            'width': rect.width / scale,
            'height': rect.height / scale,
          }
        : null;
  }

  Future<void> _editorAction(String name) async {
    try {
      if (_monaco != null) {
        final clipboard = name == 'paste'
            ? await Clipboard.getData(Clipboard.kTextPlain)
            : null;
        await _monaco!.action(name, text: clipboard?.text);
      } else if (name == 'find' || name == 'replace') {
        requestFind();
      } else if (name == 'selectAll') {
        _editor.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _editor.text.length,
        );
      } else if (name == 'paste') {
        final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
        if (clipboard?.text != null) {
          final selection = _editor.selection;
          final start = selection.isValid
              ? selection.start
              : _editor.text.length;
          final end = selection.isValid ? selection.end : start;
          _editor.value = TextEditingValue(
            text: _editor.text.replaceRange(start, end, clipboard!.text!),
            selection: TextSelection.collapsed(
              offset: start + clipboard.text!.length,
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) toast(context, 'Editor command failed: $error');
    }
  }

  void requestFind() {
    if (_monaco != null) {
      unawaited(_editorAction('find'));
      return;
    }
    setState(() => _showFind = true);
    _findFocus.requestFocus();
  }

  void _nextMatch() {
    final q = _find.text;
    if (q.isEmpty) return;
    final source = _editor.text.toLowerCase();
    final term = q.toLowerCase();
    final start = _editor.selection.end.clamp(0, source.length);
    var pos = source.indexOf(term, start);
    if (pos < 0) pos = source.indexOf(term);
    setState(() => _findMessage = pos < 0 ? 'No matches' : 'Match found');
    if (pos >= 0) {
      _editor.selection = TextSelection(
        baseOffset: pos,
        extentOffset: pos + q.length,
      );
      final line = source.substring(0, pos).split('\n').length - 1;
      if (_vertical.hasClients) {
        _vertical.animateTo(
          (line * c.editorFontSize * 1.8).clamp(
            0,
            _vertical.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _indent() {
    final value = _editor.value;
    final sel = value.selection;
    if (!sel.isValid) return;
    _editor.value = value.copyWith(
      text: value.text.replaceRange(sel.start, sel.end, '  '),
      selection: TextSelection.collapsed(offset: sel.start + 2),
      composing: TextRange.empty,
    );
  }

  Future<void> _close(EditorDocument original) async {
    await flushEditor();
    if (!mounted) return;
    final doc = c.documents.where((doc) => doc.id == original.id).firstOrNull;
    if (doc == null) return;
    if (doc.isDirty) {
      final result = await showOrionDialog<String>(
        context,
        controller: c,
        editorService: _monaco,
        builder: (ctx) => OrionAlertDialog(
          title: const Text('Save changes?'),
          content: Text('${doc.name} has unsaved changes.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save file'),
            ),
          ],
        ),
      );
      if (result == 'save') {
        setEditorObscured(true, owner: 'native-dialog');
        try {
          if (!await c.saveDocument(doc.id)) return;
        } finally {
          setEditorObscured(false, owner: 'native-dialog');
        }
      } else if (result != 'discard') {
        return;
      }
    }
    c.closeDocument(doc.id);
  }

  Future<void> _rename(EditorDocument doc) async {
    final input = TextEditingController(text: doc.name);
    final extension = doc.name.lastIndexOf('.');
    input.selection = TextSelection(
      baseOffset: 0,
      extentOffset: extension > 0 ? extension : doc.name.length,
    );
    final name = await showOrionDialog<String>(
      context,
      controller: c,
      editorService: _monaco,
      builder: (ctx) => OrionAlertDialog(
        title: const Text('Rename script'),
        content: TextField(
          controller: input,
          autofocus: true,
          onSubmitted: (s) {
            if (s.trim().isNotEmpty) Navigator.pop(ctx, s);
          },
          decoration: const InputDecoration(labelText: 'File name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: input,
            builder: (_, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, input.text),
              child: const Text('Rename'),
            ),
          ),
        ],
      ),
    );
    if (name != null) c.renameDocument(doc.id, name);
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
  }

  Future<void> _clear() async {
    await flushEditor();
    if (!mounted) return;
    if (_editor.text.isEmpty) return;
    final clear = await showOrionDialog<bool>(
      context,
      controller: c,
      editorService: _monaco,
      builder: (ctx) => OrionAlertDialog(
        title: const Text('Clear script?'),
        content: Text('Remove all text from ${c.activeDocument.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear == true) {
      if (_monaco != null) {
        await _monaco!.action('clear');
        await flushEditor();
      } else {
        _editor.clear();
        _editorFocus.requestFocus();
      }
    }
  }

  ({
    bool explorerRight,
    bool showExplorer,
    bool actionsBottom,
    double tabHeight,
    double explorerWidth,
  })
  get _layout => switch (c.selectedInterface) {
    InterfacePreset.orion => (
      explorerRight: false,
      showExplorer: true,
      actionsBottom: false,
      tabHeight: _space(42, 36),
      explorerWidth: _space(166, 148),
    ),
    InterfacePreset.synapseV3 => (
      explorerRight: true,
      showExplorer: true,
      actionsBottom: false,
      tabHeight: 42,
      explorerWidth: 172,
    ),
    InterfacePreset.synapse2017 => (
      explorerRight: true,
      showExplorer: true,
      actionsBottom: true,
      tabHeight: 38,
      explorerWidth: 158,
    ),
    InterfacePreset.synapseBlue => (
      explorerRight: false,
      showExplorer: true,
      actionsBottom: true,
      tabHeight: 40,
      explorerWidth: 160,
    ),
    InterfacePreset.synapseX => (
      explorerRight: true,
      showExplorer: true,
      actionsBottom: true,
      tabHeight: 40,
      explorerWidth: 166,
    ),
    InterfacePreset.rc7 => (
      explorerRight: true,
      showExplorer: true,
      actionsBottom: true,
      tabHeight: 36,
      explorerWidth: 156,
    ),
    InterfacePreset.krnl => (
      explorerRight: true,
      showExplorer: true,
      actionsBottom: true,
      tabHeight: 38,
      explorerWidth: 160,
    ),
    InterfacePreset.calamari => (
      explorerRight: false,
      showExplorer: true,
      actionsBottom: true,
      tabHeight: 38,
      explorerWidth: 158,
    ),
    InterfacePreset.awp => (
      explorerRight: true,
      showExplorer: true,
      actionsBottom: false,
      tabHeight: 40,
      explorerWidth: 168,
    ),
    InterfacePreset.xeno => (
      explorerRight: false,
      showExplorer: false,
      actionsBottom: true,
      tabHeight: 38,
      explorerWidth: 0,
    ),
    InterfacePreset.zenithV2 => (
      explorerRight: false,
      showExplorer: true,
      actionsBottom: false,
      tabHeight: 42,
      explorerWidth: 172,
    ),
  };

  @override
  Widget build(BuildContext context) {
    _windowColors = OrionColors.of(context);
    return _studioLayer(
      'workspace',
      (colors) => LayoutBuilder(
        builder: (context, constraints) {
          final layout = _layout;
          final showExplorer = layout.showExplorer;
          final adaptiveExplorer = c.selectedInterface == InterfacePreset.orion
              ? math.min(
                  layout.explorerWidth,
                  (constraints.maxWidth * .28).clamp(120.0, 168.0),
                )
              : layout.explorerWidth;
          final explorer = SizedBox(
            key: const ValueKey('script-explorer'),
            width: adaptiveExplorer,
            child: _studioLayer('scriptList', _explorer),
          );
          final editor = Expanded(
            key: const ValueKey('workspace-editor-panel'),
            child: _editorPanel(colors),
          );
          final divider = SizedBox(
            width: _space(8, 6),
            child: const ColoredBox(color: Colors.transparent),
          );
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _glassEnabled(colors)
                  ? Colors.transparent
                  : colors.chrome(colors.panel, role: 'panel'),
              gradient: _glassEnabled(colors)
                  ? null
                  : orionSurfaceGradient(colors),
              borderRadius: _studioStyle('workspace')?.radius != null
                  ? BorderRadius.circular(_studioStyle('workspace')!.radius!)
                  : _glassEnabled(colors)
                  ? BorderRadius.circular(_space(22, 18))
                  : BorderRadius.only(
                      topLeft: const Radius.circular(4),
                      topRight: Radius.circular(_space(22, 18)),
                      bottomLeft: Radius.circular(_space(22, 18)),
                      bottomRight: Radius.circular(_space(22, 18)),
                    ),
              border: null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showExplorer && !layout.explorerRight) ...[
                  explorer,
                  divider,
                ],
                editor,
                if (showExplorer && layout.explorerRight) ...[
                  divider,
                  explorer,
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _explorer(OrionColors colors) {
    final library = c.scriptLibrary;
    if (library == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Scripts',
          style: OrionType.sectionTitle.copyWith(color: colors.ink),
        ),
      );
    }
    return ScriptExplorer(
      controller: c,
      library: library,
      editorService: _monaco,
      onLibrary: widget.onLibrary,
      onOpenScript: (path) async {
        await flushEditor();
        if (!mounted) return;
        final opened = await c.openFileAtPath(path);
        if (opened == null && mounted) {
          toast(
            context,
            'Could not open the script. Check that the file is readable.',
          );
        }
      },
    );
  }

  List<Widget> _fileControls(
    OrionColors colors, {
    int count = 3,
    bool compactLabels = false,
    bool iconClear = false,
    bool iconOnly = false,
  }) => [
    _fileAction(
      colors,
      Icons.folder_open_rounded,
      iconOnly
          ? ''
          : _compact || compactLabels
          ? 'Open'
          : 'Open file',
      'Open file · Ctrl O',
      widget.onOpen,
      index: 0,
      count: count,
      compact: compactLabels,
    ),
    _fileAction(
      colors,
      Icons.save_outlined,
      iconOnly
          ? ''
          : _compact || compactLabels
          ? 'Save'
          : 'Save file',
      'Save file · Ctrl S',
      widget.onSave,
      index: 1,
      count: count,
      compact: compactLabels,
    ),
    _fileAction(
      colors,
      Icons.delete_outline_rounded,
      iconClear ? '' : 'Clear',
      'Clear script',
      _editor.text.isEmpty ? null : _clear,
      index: 2,
      count: count,
      compact: compactLabels,
    ),
  ];

  List<Widget> _executorControls(
    OrionColors colors, {
    int offset = 0,
    int count = 2,
    bool iconClients = false,
  }) => [
    _studioLayer(
      'clientsButton',
      (colors) => SpringPressFeedback(
        reducedMotion: c.reducedMotion,
        child: Tooltip(
          message: 'Clients',
          child: FilledButton.tonalIcon(
            onPressed: () => showBridgeClientManager(
              context,
              controller: c,
              editorService: _monaco,
            ),
            style: _connectedStyle(
              colors,
              index: offset,
              studioId: 'clientsButton',
              count: count,
              foreground: colors.readableAccent,
              background: Color.alphaBlend(
                colors.accent.withValues(alpha: .08),
                colors.panel,
              ),
              padding: iconClients ? 6 : _space(10, 8),
            ),
            icon: const Icon(Icons.devices_rounded, size: 16),
            label: iconClients
                ? const SizedBox.shrink()
                : const Text('Clients'),
          ),
        ),
      ),
    ),
    _studioLayer(
      'executeButton',
      (colors) => SpringPressFeedback(
        reducedMotion: c.reducedMotion,
        child: FilledButton.icon(
          onPressed: () async {
            await flushEditor();
            c.execute();
          },
          style: _connectedStyle(
            colors,
            index: offset + 1,
            studioId: 'executeButton',
            count: count,
            foreground: colors.transparentSurfaces
                ? colors.readableAccent
                : colors.onAccent,
            background: colors.accent,
            padding: _space(16, 12),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Execute'),
        ),
      ),
    ),
  ];

  Widget _actions(OrionColors _) => _studioLayer(
    'actions',
    (colors) => LayoutBuilder(
      builder: (context, constraints) {
        final compactLabels = constraints.maxWidth < 520;
        final tight = constraints.maxWidth < 380;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _space(12, 8),
            vertical: _space(8, 6),
          ),
          child: OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            spacing: _space(16, 10),
            overflowAlignment: OverflowBarAlignment.start,
            overflowSpacing: 6,
            children: [
              ConnectedActionGroup(
                children: _fileControls(
                  colors,
                  compactLabels: compactLabels,
                  iconClear: tight,
                  iconOnly: tight,
                ),
              ),
              ConnectedActionGroup(
                children: _executorControls(colors, iconClients: tight),
              ),
            ],
          ),
        );
      },
    ),
  );

  ButtonStyle _connectedStyle(
    OrionColors colors, {
    required int index,
    required int count,
    Color? foreground,
    Color? background,
    double? height,
    double padding = 8,
    String? studioId,
  }) {
    final element = studioId == null ? null : _studioStyle(studioId);
    final hasImage =
        element?.image?.isValid == true && element!.image!.opacity > 0;
    foreground = element?.foreground == null
        ? foreground
        : Color(element!.foreground!);
    background = hasImage
        ? Colors.transparent
        : element?.fill == null
        ? background
        : Color(element!.fill!);
    final controlHeight = height ?? _space(36, 32);
    return ButtonStyle(
      // Joined controls share one sheet instead of stacking the global
      // button glass underneath another lens for every segment.
      backgroundBuilder: colors.glassEnabled
          ? (_, _, child) => child ?? const SizedBox.shrink()
          : null,
      minimumSize: WidgetStatePropertyAll(Size(0, controlHeight)),
      maximumSize: WidgetStatePropertyAll(Size(double.infinity, controlHeight)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: padding),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.muted.withValues(alpha: .5)
            : foreground ?? colors.ink,
      ),
      backgroundColor: WidgetStatePropertyAll(
        _glassEnabled(colors, studioId) && element?.fill == null && !hasImage
            ? background == Colors.transparent
                  ? Colors.transparent
                  : (background ?? colors.elevated).withValues(
                      alpha: background == colors.accent ? .30 : .025,
                    )
            : colors.chrome(background ?? colors.elevated, role: 'elevated'),
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        final tint = !colors.transparentSurfaces && background == colors.accent
            ? colors.onAccent
            : colors.accent;
        if (states.contains(WidgetState.pressed)) {
          return tint.withValues(alpha: .14);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return tint.withValues(alpha: .08);
        }
        return Colors.transparent;
      }),
      side: WidgetStatePropertyAll(
        element?.border != null
            ? BorderSide(color: Color(element!.border!))
            : colors.outlineStrength > 1 && background != Colors.transparent
            ? BorderSide(
                color: colors.outline((colors.outlineStrength - 1) * 1.4),
                width: .67,
              )
            : BorderSide.none,
      ),
      textStyle: WidgetStatePropertyAll(
        OrionType.label.copyWith(
          fontSize: _space(12, 11.5),
          fontFamily: _studioFont,
        ),
      ),
      shape: element?.radius != null
          ? WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(element!.radius!),
              ),
            )
          : connectedActionShape(
              index: index,
              count: count,
              reducedMotion: c.reducedMotion,
              radius: height == null ? _space(12, 10) : 8,
              asymmetric: height == null,
            ),
      animationDuration: c.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 170),
    );
  }

  Widget _fileAction(
    OrionColors colors,
    IconData icon,
    String label,
    String tooltip,
    VoidCallback? onPressed, {
    required int index,
    int count = 3,
    bool compact = false,
  }) => _studioLayer(
    ['openButton', 'saveButton', 'clearButton'][index],
    (colors) => Tooltip(
      message: tooltip,
      child: SpringPressFeedback(
        reducedMotion: c.reducedMotion,
        enabled: onPressed != null,
        child: TextButton.icon(
          onPressed: onPressed,
          style: _connectedStyle(
            colors,
            index: index,
            count: count,
            studioId: ['openButton', 'saveButton', 'clearButton'][index],
            background: colors.elevated.withValues(alpha: .5),
            padding: compact ? 6 : 8,
          ),
          icon: Icon(icon, size: _space(16, 15)),
          label: label.isEmpty ? const SizedBox.shrink() : Text(label),
        ),
      ),
    ),
  );

  Widget _editorTools(OrionColors _) => _studioLayer(
    'editorTools',
    (colors) => Container(
      padding: EdgeInsets.fromLTRB(
        _space(12, 8),
        0,
        _space(12, 8),
        _space(6, 4),
      ),
      decoration: BoxDecoration(
        border: _glassEnabled(colors, 'editorTools')
            ? null
            : Border(bottom: BorderSide(color: colors.outline(.18))),
      ),
      child: Row(
        children: [
          ConnectedActionGroup(
            children: [
              IconButton(
                tooltip: 'Undo · Ctrl Z',
                onPressed: _monaco == null ? null : () => _editorAction('undo'),
                style: _utilityStyle(colors, index: 0),
                icon: const Icon(Icons.undo_rounded, size: 18),
              ),
              IconButton(
                tooltip: 'Redo · Ctrl Shift Z',
                onPressed: _monaco == null ? null : () => _editorAction('redo'),
                style: _utilityStyle(colors, index: 1),
                icon: const Icon(Icons.redo_rounded, size: 18),
              ),
              TextButton.icon(
                onPressed: () => _editorAction('paste'),
                style:
                    _connectedStyle(
                      colors,
                      index: 2,
                      count: 3,
                      height: _space(30, 28),
                      foreground: colors.muted,
                      background: Colors.transparent,
                    ).copyWith(
                      textStyle: WidgetStatePropertyAll(
                        OrionType.label.copyWith(fontFamily: _studioFont),
                      ),
                    ),
                icon: const Icon(Icons.content_paste_rounded, size: 16),
                label: const Text('Paste'),
              ),
            ],
          ),
          const Spacer(),
          ConnectedActionGroup(
            children: [
              IconButton(
                tooltip: 'Find · Ctrl F',
                onPressed: requestFind,
                style: _utilityStyle(colors, index: 0),
                icon: const Icon(Icons.search_rounded, size: 18),
              ),
              IconButton(
                tooltip: 'Replace · Ctrl H',
                onPressed: () => _editorAction('replace'),
                style: _utilityStyle(colors, index: 1),
                icon: const Icon(Icons.find_replace_rounded, size: 18),
              ),
              Builder(
                builder: (anchor) => IconButton(
                  tooltip: 'Editor actions',
                  style: _utilityStyle(colors, index: 2),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: colors.muted,
                  ),
                  onPressed: () => unawaited(_editorMenu(anchor)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _editorMenu(BuildContext anchor) async {
    final value = await showOrionPopupMenu<String>(
      anchor,
      controller: c,
      editorService: _monaco,
      entries: [
        const OrionMenuEntry(value: 'save-as', label: 'Save as…'),
        const OrionMenuEntry(value: 'rename', label: 'Rename script'),
        const OrionMenuEntry(value: 'close', label: 'Close tab'),
        const OrionMenuEntry.divider(),
        const OrionMenuEntry(value: 'selectAll', label: 'Select all'),
        OrionMenuEntry(
          value: 'format',
          label: 'Reindent',
          enabled: _monaco != null,
        ),
        OrionMenuEntry(
          value: 'suggest',
          label: 'Autocomplete',
          enabled: _monaco != null,
        ),
      ],
    );
    if (value == null || !mounted) return;
    switch (value) {
      case 'save-as':
        await flushEditor();
        setEditorObscured(true, owner: 'native-dialog');
        try {
          await c.saveAs();
        } finally {
          setEditorObscured(false, owner: 'native-dialog');
        }
      case 'rename':
        await _rename(c.activeDocument);
      case 'close':
        await _close(c.activeDocument);
      default:
        await _editorAction(value);
    }
  }

  Future<void> _tabMenu(
    BuildContext anchor,
    String documentId,
    Offset position,
  ) async {
    final action = await showOrionPopupMenu<String>(
      anchor,
      controller: c,
      editorService: _monaco,
      globalPosition: position,
      entries: const [
        OrionMenuEntry(value: 'rename', label: 'Rename tab'),
        OrionMenuEntry(value: 'save', label: 'Save'),
        OrionMenuEntry(value: 'save-as', label: 'Save as…'),
        OrionMenuEntry.divider(),
        OrionMenuEntry(value: 'close', label: 'Close tab'),
      ],
    );
    if (action == null || !mounted) return;
    final document = c.documents
        .where((doc) => doc.id == documentId)
        .firstOrNull;
    if (document == null) return;
    switch (action) {
      case 'rename':
        await _rename(document);
      case 'close':
        await _close(document);
      case 'save':
      case 'save-as':
        await flushEditor();
        if (!mounted) return;
        final needsDialog = action == 'save-as' || document.filePath == null;
        if (needsDialog) setEditorObscured(true, owner: 'native-dialog');
        try {
          final saved = action == 'save-as'
              ? await c.saveAs(documentId)
              : await c.saveDocument(documentId);
          if (mounted && saved) toast(context, 'Script saved');
        } catch (error) {
          if (mounted) toast(context, 'Could not save file: $error');
        } finally {
          if (needsDialog) setEditorObscured(false, owner: 'native-dialog');
        }
    }
  }

  ButtonStyle _utilityStyle(OrionColors colors, {required int index}) =>
      _connectedStyle(
        colors,
        index: index,
        count: 3,
        height: _space(30, 28),
        padding: 6,
        foreground: colors.muted,
        background: Colors.transparent,
      ).copyWith(
        minimumSize: WidgetStatePropertyAll(Size.square(_space(30, 28))),
        maximumSize: WidgetStatePropertyAll(Size.square(_space(30, 28))),
      );

  Widget _editorChrome(OrionColors colors) {
    // The controller intentionally returns an immutable snapshot. Keep one for
    // the strip so rebuilding N tabs never creates N copies of the full list.
    final documents = c.documents;
    return _glassSurface(
      'editorChrome',
      colors,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _studioLayer(
            'tabs',
            (colors) => Container(
              height: _layout.tabHeight,
              padding: EdgeInsets.symmetric(horizontal: _space(12, 8)),
              decoration: BoxDecoration(
                color: _glassEnabled(colors, 'tabs')
                    ? Colors.transparent
                    : colors.chrome(colors.panel, role: 'panel'),
                gradient: _glassEnabled(colors, 'tabs')
                    ? null
                    : orionSurfaceGradient(colors),
                border: _glassEnabled(colors, 'tabs')
                    ? null
                    : Border(bottom: BorderSide(color: colors.outline(.15))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: EditorTabStrip(
                      tabIds: [for (final doc in documents) doc.id],
                      activeId: c.activeDocumentId,
                      colors: colors,
                      reducedMotion: c.reducedMotion,
                      compact: _compact,
                      tabBuilder: (_, index) => _tab(
                        documents[index],
                        colors,
                        index: index,
                        count: documents.length,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'New script',
                    style: IconButton.styleFrom(
                      minimumSize: Size.square(_space(28, 26)),
                      maximumSize: Size.square(_space(28, 26)),
                      padding: EdgeInsets.all(_space(6, 5)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _newDocument,
                    icon: Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_layout.actionsBottom) _actions(colors),
          _editorTools(colors),
        ],
      ),
      radius: 20,
    );
  }

  Widget _editorPanel(OrionColors colors) => Column(
    children: [
      _editorChrome(colors),
      if (_showFind)
        Padding(
          padding: EdgeInsets.fromLTRB(
            _space(18, 12),
            0,
            _space(18, 12),
            _space(10, 7),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _find,
                  focusNode: _findFocus,
                  onSubmitted: (_) => _nextMatch(),
                  style: OrionType.body.copyWith(color: colors.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: _space(12, 10),
                      vertical: _space(11, 8),
                    ),
                    hintText: 'Find in script…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                  ),
                ),
              ),
              SizedBox(width: _space(10, 6)),
              Text(
                _findMessage,
                style: OrionType.metadata.copyWith(color: colors.muted),
              ),
              IconButton(
                tooltip: 'Next match',
                onPressed: _nextMatch,
                icon: const Icon(Icons.arrow_downward_rounded, size: 17),
              ),
              IconButton(
                tooltip: 'Close find',
                onPressed: () {
                  setState(() => _showFind = false);
                  _editorFocus.requestFocus();
                },
                icon: const Icon(Icons.close_rounded, size: 17),
              ),
            ],
          ),
        ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // These bounds exclude the actual toolbar, Find row and status
            // bar. Keep code visible even when the console is dragged fully up.
            final maxConsoleHeight = math.max(
              0.0,
              constraints.maxHeight -
                  80 -
                  _space(40, 34) -
                  (_layout.actionsBottom ? _space(64, 56) : 0),
            );
            return Column(
              children: [
                Expanded(
                  key: const ValueKey('editor-body'),
                  child: _studioLayer(
                    'editor',
                    (colors) => FadeTransition(
                      opacity: _tabOpacity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _glassEnabled(colors, 'editor')
                              ? Colors.transparent
                              : colors.chrome(
                                  colors.editorColor,
                                  role: 'editor',
                                ),
                          gradient:
                              _glassEnabled(colors, 'editor') ||
                                  c.orionTheme.overrides.containsKey('editor')
                              ? null
                              : orionSurfaceGradient(
                                  colors,
                                  base: colors.editorColor,
                                  blend: .75,
                                ),
                        ),
                        child: _codeArea(colors),
                      ),
                    ),
                  ),
                ),
                if (_layout.actionsBottom)
                  _glassSurface(
                    'bottomActions',
                    colors,
                    _actions(colors),
                    radius: 14,
                  ),
                _console(colors, maxHeight: maxConsoleHeight),
              ],
            );
          },
        ),
      ),
      if (_monaco case final service?)
        AnimatedBuilder(
          animation: service,
          builder: (context, _) => _statusBar(colors),
        )
      else
        _statusBar(colors),
    ],
  );
  Widget _tab(
    EditorDocument doc,
    OrionColors colors, {
    required int index,
    required int count,
  }) {
    final active = doc.id == c.activeDocumentId;
    final radius = active
        ? const BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
            bottomRight: Radius.circular(10),
          )
        : BorderRadius.horizontal(
            left: Radius.circular(index == 0 ? 10 : 4),
            right: Radius.circular(index == count - 1 ? 10 : 4),
          );
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: SpringPressFeedback(
        reducedMotion: c.reducedMotion,
        child: AnimatedContainer(
          duration: c.reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: OrionMotion.effects,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: active && _glassEnabled(colors, 'tabs')
                ? colors.ink.withValues(alpha: .10)
                : active
                ? colors.transparentSurfaces
                      ? colors.stateFill(.045)
                      : colors.elevated.withValues(alpha: .85)
                : Colors.transparent,
            borderRadius: radius,
          ),
          child: Material(
            color: Colors.transparent,
            child: Builder(
              builder: (anchor) => InkWell(
                key: ValueKey('workspace-tab:${doc.id}'),
                onTap: () => _selectDocument(doc.id),
                onSecondaryTapUp: (details) =>
                    unawaited(_tabMenu(anchor, doc.id, details.globalPosition)),
                borderRadius: radius,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: _space(11, 9),
                    right: 2,
                    top: _space(3, 2),
                    bottom: _space(3, 2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.code_rounded,
                        size: 14,
                        color: active ? colors.readableAccent : colors.muted,
                      ),
                      SizedBox(width: _space(7, 5)),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: _space(145, 125)),
                        child: Text(
                          doc.name,
                          overflow: TextOverflow.ellipsis,
                          style: OrionType.label.copyWith(
                            fontWeight: active
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: active ? colors.ink : colors.muted,
                          ),
                        ),
                      ),
                      if (doc.isDirty) ...[
                        const SizedBox(width: 7),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.readablePeach,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      const SizedBox(width: 3),
                      IconButton(
                        tooltip: 'Close ${doc.name}',
                        constraints: BoxConstraints.tightFor(
                          width: _space(26, 22),
                          height: _space(26, 22),
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => _close(doc),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: colors.muted,
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

  Widget _codeArea(OrionColors colors) {
    _synchronizeMonaco(colors);
    if (_monaco != null) {
      return MonacoEditor(
        key: const ValueKey('monaco-editor'),
        service: _monaco!,
        active: widget.active,
        backgroundColor: _glassEnabled(colors, 'editor')
            ? Colors.transparent
            : colors.chrome(colors.editorColor, role: 'editor'),
        // The native surface must stay hidden while Flutter paints covers,
        // page transitions and dialogs. Paint the same preserved source below
        // those layers until WebKit can safely return above Flutter again.
        fallback: ExcludeFocus(
          child: IgnorePointer(
            child: Builder(
              builder: (_) => _flutterCodeArea(colors, readOnly: true),
            ),
          ),
        ),
      );
    }
    return _flutterCodeArea(
      colors,
      readOnly: c.activeDocumentIsBridgeScriptLocked,
    );
  }

  Widget _flutterCodeArea(OrionColors colors, {bool readOnly = false}) {
    final size = c.editorFontSize;
    final lineHeight = size * 1.8;
    _editor.colors = colors;
    final lines = _editor.text.split('\n');
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = c.showLineNumbers ? _space(52, 46) : _space(18, 12);
        final available = math.max(
          100.0,
          constraints.maxWidth - gutter - _space(24, 16),
        );
        final width = c.wordWrap
            ? available
            : math.max(
                available,
                lines.fold<int>(0, (n, s) => math.max(n, s.length)) *
                        size *
                        .62 +
                    30,
              );
        final wrapWidth = math.max(1.0, width - 24);
        final lineHeights = _measureLineHeights(
          lines,
          size: size,
          lineHeight: lineHeight,
          wrapWidth: wrapWidth,
          wordWrap: c.wordWrap,
        );
        return Scrollbar(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _vertical,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: gutter,
                  child: c.showLineNumbers
                      ? Padding(
                          padding: EdgeInsets.only(
                            top: _space(9, 7),
                            right: _space(16, 12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(
                              math.max(lines.length, 1),
                              (i) => SizedBox(
                                height: lineHeights[i],
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontFamily: 'JetBrainsMono',
                                    fontSize: size,
                                    color: colors.muted.withValues(alpha: .7),
                                    height: 1.8,
                                  ),
                                ),
                              ),
                            ),
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
                          const SingleActivator(
                            LogicalKeyboardKey.keyF,
                            control: true,
                          ): requestFind,
                          const SingleActivator(
                            LogicalKeyboardKey.keyH,
                            control: true,
                          ): requestFind,
                        },
                        child: TextField(
                          key: const ValueKey('code-editor'),
                          controller: _editor,
                          focusNode: _editorFocus,
                          readOnly: readOnly,
                          keyboardType: TextInputType.multiline,
                          maxLines: null,
                          minLines: c.wordWrap
                              ? null
                              : math.max(
                                  1,
                                  (constraints.maxHeight / lineHeight).floor(),
                                ),
                          autocorrect: false,
                          enableSuggestions: false,
                          spellCheckConfiguration:
                              const SpellCheckConfiguration.disabled(),
                          cursorColor: colors.accent,
                          cursorWidth: 1.6,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: size,
                            height: 1.8,
                            color: colors.ink,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            contentPadding: EdgeInsets.only(
                              top: _space(9, 7),
                              bottom: _space(18, 12),
                              right: _space(24, 16),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onTapOutside: (_) => _editorFocus.unfocus(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<double> _measureLineHeights(
    List<String> lines, {
    required double size,
    required double lineHeight,
    required double wrapWidth,
    required bool wordWrap,
  }) {
    if (!wordWrap) return List<double>.filled(lines.length, lineHeight);
    final layout = (size, lineHeight, wrapWidth);
    if (_lineHeightCacheLayout != layout) {
      _lineHeightCacheLayout = layout;
      _lineHeightCache.clear();
    }
    final heights = List<double>.filled(lines.length, lineHeight);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final cached = _lineHeightCache[index];
      if (cached != null && cached.$1 == line) {
        heights[index] = cached.$2;
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(
          text: line.isEmpty ? ' ' : line,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: size,
            height: 1.8,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: wrapWidth);
      final height =
          math.max(1, (painter.height / lineHeight - .001).ceil()) * lineHeight;
      painter.dispose();
      heights[index] = height;
      _lineHeightCache[index] = (line, height);
    }
    _lineHeightCache.removeWhere((index, _) => index >= lines.length);
    return heights;
  }

  Widget _console(OrionColors _, {required double maxHeight}) => _studioLayer(
    'consoleOutput',
    (colors) => _consoleBody(colors, maxHeight),
  );

  Widget _consoleBody(OrionColors colors, double maxHeight) {
    final minHeight = math.min(48.0, maxHeight);
    final height = _consoleHeight.clamp(minHeight, maxHeight);
    final entries = _showConsole
        ? c.activities.where((a) => a.kind == ActivityKind.execution).toList()
        : const <ActivityEntry>[];
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            border: _glassEnabled(colors, 'consoleOutput')
                ? null
                : Border(top: BorderSide(color: colors.outline(.22))),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => _showConsole = !_showConsole),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _space(12, 8),
                    vertical: _space(7, 5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.terminal_rounded,
                        size: _space(18, 16),
                        color: colors.muted,
                      ),
                      SizedBox(width: _space(8, 6)),
                      Text(
                        'Console',
                        style: OrionType.label.copyWith(color: colors.muted),
                      ),
                      const Spacer(),
                      if (_showConsole && entries.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear console',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(22, 18),
                            maximumSize: const Size(22, 18),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: c.clearActivities,
                          constraints: const BoxConstraints.tightFor(
                            width: 22,
                            height: 18,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 15,
                            color: colors.muted,
                          ),
                        ),
                      Icon(
                        _showConsole
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        size: 18,
                        color: colors.muted,
                      ),
                    ],
                  ),
                ),
              ),
              _ConsoleExpansion(
                reducedMotion: c.reducedMotion || _resizingConsole,
                child: _showConsole
                    ? SizedBox(
                        key: const ValueKey('orion-console-output'),
                        height: height,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            _space(12, 8),
                            0,
                            _space(12, 8),
                            _space(8, 6),
                          ),
                          child: entries.isEmpty
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Client output appears here.',
                                    style: OrionType.metadata.copyWith(
                                      color: colors.muted,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _consoleScroll,
                                  itemCount: entries.length,
                                  itemBuilder: (context, index) {
                                    final entry =
                                        entries[entries.length - 1 - index];
                                    return Padding(
                                      key: ValueKey(
                                        'console-entry-${entry.id}',
                                      ),
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Tooltip(
                                        message: entry.title,
                                        child: SelectableText(
                                          entry.detail,
                                          style: OrionType.metadata.copyWith(
                                            fontFamily: 'JetBrainsMono',
                                            fontSize: 11,
                                            color: switch (entry.severity) {
                                              ActivitySeverity.error =>
                                                colors.readablePeach,
                                              ActivitySeverity.warning =>
                                                colors.readableForeground(
                                                  Colors.amber.shade300,
                                                ),
                                              _ => colors.ink,
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        if (_showConsole)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 7,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Tooltip(
                message: 'Drag to resize console',
                child: GestureDetector(
                  key: const ValueKey('orion-console-resize'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => setState(() {
                    _resizingConsole = true;
                    _consoleHeight = height;
                  }),
                  onVerticalDragUpdate: (details) => setState(() {
                    _consoleHeight = (_consoleHeight - details.delta.dy).clamp(
                      minHeight,
                      maxHeight,
                    );
                  }),
                  onVerticalDragEnd: (_) {
                    setState(() => _resizingConsole = false);
                    c.setInterfacePreference(
                      InterfacePreset.orion,
                      'consoleHeight',
                      _consoleHeight,
                    );
                  },
                  onVerticalDragCancel: () =>
                      setState(() => _resizingConsole = false),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 2,
                      decoration: BoxDecoration(
                        color: colors.muted.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusBar(OrionColors colors) {
    final offset = _editor.selection.baseOffset.clamp(0, _editor.text.length);
    final before = _monaco == null ? _editor.text.substring(0, offset) : '';
    final line = _monaco?.line ?? before.split('\n').length;
    final col = _monaco?.column ?? before.length - before.lastIndexOf('\n');
    return Container(
      height: _space(28, 24),
      padding: EdgeInsets.symmetric(horizontal: _space(12, 8)),
      color: colors.chrome(colors.elevated.withValues(alpha: .22)),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(Icons.circle, size: 5, color: colors.accent),
                const SizedBox(width: 7),
                Flexible(
                  flex: 2,
                  child: Text(
                    c.bridgeError != null
                        ? 'Bridge unavailable'
                        : c.bridgeConnected
                        ? '${c.bridgeTargetCount} / ${c.bridgeClients.length} clients'
                        : c.bridgeListening
                        ? 'Waiting for clients'
                        : 'Bridge offline',
                    overflow: TextOverflow.ellipsis,
                    style: OrionType.metadata.copyWith(color: colors.muted),
                  ),
                ),
                SizedBox(width: _space(12, 8)),
                Flexible(
                  child: Text(
                    'Orion Bridge',
                    overflow: TextOverflow.ellipsis,
                    style: OrionType.metadata.copyWith(color: colors.muted),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: _space(16, 10)),
          Text(
            'Ln $line, Col $col',
            style: OrionType.metadata.copyWith(color: colors.muted),
          ),
          SizedBox(width: _space(16, 10)),
          Text(
            'UTF-8',
            style: OrionType.metadata.copyWith(color: colors.muted),
          ),
          SizedBox(width: _space(16, 10)),
          Text('Luau', style: OrionType.metadata.copyWith(color: colors.muted)),
          SizedBox(width: _space(16, 10)),
          Text(
            '$_activeLineCount ${_activeLineCount == 1 ? 'line' : 'lines'}',
            style: OrionType.metadata.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

class _ConsoleExpansion extends StatelessWidget {
  final bool reducedMotion;
  final Widget child;
  const _ConsoleExpansion({required this.reducedMotion, required this.child});
  @override
  Widget build(BuildContext context) => reducedMotion
      ? child
      : AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: child,
        );
}

class LuaEditingController extends TextEditingController {
  OrionColors? colors;
  static const _keywords = {
    'local',
    'function',
    'end',
    'return',
    'if',
    'then',
    'else',
    'elseif',
    'for',
    'while',
    'do',
    'in',
    'and',
    'or',
    'not',
    'true',
    'false',
    'nil',
    'repeat',
    'until',
  };
  static final _numberStart = RegExp(r'^\d');
  static final _tokens = RegExp(
    r'''--[^\n]*|"[^"\n]*"|'[^'\n]*'|\b(?:local|function|end|return|if|then|else|elseif|for|while|do|in|and|or|not|true|false|nil|repeat|until)\b|\b\d+(?:\.\d+)?\b|\b[a-zA-Z_]\w*(?=\s*\()''',
  );
  String? _spanText;
  int? _spanTextLength;
  TextStyle? _spanStyle;
  OrionColors? _spanColors;
  TextRange? _spanComposing;
  bool _spanWithComposing = false;
  TextSpan? _span;

  @override
  void notifyListeners() {
    _span = null;
    super.notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final c = colors ?? OrionColors.of(context);
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    if (_span != null &&
        _spanTextLength == text.length &&
        identical(_spanText, text) &&
        _spanStyle == style &&
        _spanColors == c &&
        _spanComposing == composing &&
        _spanWithComposing == withComposing) {
      return _span!;
    }
    final spans = <TextSpan>[];
    int last = 0;
    for (final m in _tokens.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final token = m.group(0)!;
      final color = token.startsWith('--')
          ? c.muted
          : token.startsWith('"') || token.startsWith("'")
          ? c.readableAccent
          : _numberStart.hasMatch(token)
          ? c.readablePeach
          : _keywords.contains(token)
          ? c.readableLavender
          : c.readableAccent;
      spans.add(
        TextSpan(
          text: token,
          style: TextStyle(color: color),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    final result = TextSpan(style: style, children: spans);
    _spanText = text;
    _spanTextLength = text.length;
    _spanStyle = style;
    _spanColors = c;
    _spanComposing = composing;
    _spanWithComposing = withComposing;
    return _span = result;
  }
}
