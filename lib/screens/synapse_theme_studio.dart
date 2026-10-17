import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/interface_preset.dart';
import '../models/orion_theme_preferences.dart';
import '../models/synapse_studio_theme.dart';
import '../services/synapse_theme_catalog.dart';
import '../services/theme_studio_library.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import '../theme/expressive_motion.dart';
import '../widgets/orion_overlay.dart';
import '../widgets/orion_glass.dart';
import '../widgets/orion_popup_menu.dart';
import '../widgets/synapse_studio_preview.dart';
import '../widgets/theme_color_picker.dart';

// Studio chrome stays in Orion's Material typography while the canvas uses the
// draft's selected typeface. Explicit control styles do not merge font families.
abstract final class _StudioType {
  static final label = OrionType.label.copyWith(fontFamily: OrionType.family);
  static final metadata = OrionType.metadata.copyWith(
    fontFamily: OrionType.family,
  );
  static final sectionTitle = OrionType.sectionTitle.copyWith(
    fontFamily: OrionType.family,
  );
}

class SynapseThemeStudioScreen extends StatefulWidget {
  const SynapseThemeStudioScreen({
    super.key,
    required this.controller,
    required this.preset,
    this.onClose,
    this.nativeWindow = false,
  });
  final OrionController controller;
  final InterfacePreset preset;
  final VoidCallback? onClose;
  final bool nativeWindow;
  @override
  SynapseThemeStudioScreenState createState() =>
      SynapseThemeStudioScreenState();
}

class SynapseThemeStudioScreenState extends State<SynapseThemeStudioScreen> {
  late InterfacePreset _preset;
  late SynapseStudioTheme _draft, _saved;
  final _undo = <SynapseStudioTheme>[];
  final _redo = <SynapseStudioTheme>[];
  Map<String, Rect> _elementBounds = const {};
  String _window = 'main', _query = '', _panel = 'Inspector';
  String? _selected, _status, _selectedSavedId;
  String _previewPage = 'editor';
  bool _busy = false, _error = false, _changed = false;
  double _zoom = 1;
  final _scaffold = GlobalKey<ScaffoldState>();
  final _layerSearch = TextEditingController();
  final _layerScroll = ScrollController();
  final _layerKeys = <String?, GlobalKey>{};
  static const _historyLimit = 50;
  static const _orionPages = {
    'editor': 'Editor',
    'scriptHub': 'Script hub',
    'uiSelection': 'UI selection',
    'themeControl': 'Theme Control',
    'settings': 'Settings',
  };

  OrionController get c => widget.controller;
  ThemeStudioLibrary get _library => ThemeStudioLibrary(c, _preset);
  bool get _dirty => _changed;
  SynapseStudioWindow get _windowTheme => _draft.window(_window);
  String get _windowLabel =>
      _windowDescriptor.label.toLowerCase().endsWith('window')
      ? _windowDescriptor.label
      : '${_windowDescriptor.label} window';
  SynapseStudioWindowDescriptor get _windowDescriptor =>
      SynapseThemeCatalog.windows(_preset).firstWhere((w) => w.id == _window);
  SynapseStudioElementDescriptor? get _element => SynapseThemeCatalog.elements(
    _preset,
    _window,
  ).where((e) => e.id == _selected).firstOrNull;
  SynapseStudioElement get _elementTheme =>
      _windowTheme.elements[_selected] ?? SynapseStudioElement();
  Map<String, int> get _colors => {
    ...SynapseThemeCatalog.defaults(_preset).colors,
    ..._draft.colors,
    ..._windowTheme.colors,
  };

  @override
  void initState() {
    super.initState();
    _load(widget.preset);
  }

  void _load(InterfacePreset preset) {
    _preset = preset;
    _query = '';
    _layerSearch.clear();
    _draft = SynapseThemeCatalog.current(c, preset);
    _saved = _draft;
    final recovered = c.getInterfacePreferences(preset)['themeStudioDraft'];
    if (recovered is Map) {
      _draft = SynapseThemeCatalog.normalizeForPreset(
        SynapseStudioTheme.fromJson(recovered),
        preset,
      );
    }
    _changed = !_sameTheme(_draft, _saved);
    _window = SynapseThemeCatalog.windows(preset).first.id;
    _selected = null;
    _selectedSavedId = null;
    _previewPage = 'editor';
    _elementBounds = const {};
    _undo.clear();
    _redo.clear();
    _status = _changed ? 'Recovered unapplied draft' : null;
  }

  Future<void> preserveDraft() async {
    c.setInterfacePreference(
      _preset,
      'themeStudioDraft',
      _dirty ? _draft.toJson() : null,
    );
    await c.flushPersistence();
    if (c.persistenceError != null) throw FormatException(c.persistenceError!);
  }

  void _remember() {
    _undo.add(_draft);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _edit(SynapseStudioTheme next, {bool record = true}) {
    if (_sameTheme(next, _draft)) return;
    setState(() {
      if (record) _remember();
      _draft = next;
      _changed = !_sameTheme(_draft, _saved);
      _status = null;
    });
  }

  void _editWindow(SynapseStudioWindow next, {bool record = true}) =>
      _edit(_draft.withWindow(_window, next), record: record);
  void _editElement(SynapseStudioElement next, {bool record = true}) {
    if (_selected != null) {
      _edit(_draft.withElement(_window, _selected!, next), record: record);
    }
  }

  void _history(bool redo) {
    final from = redo ? _redo : _undo, to = redo ? _undo : _redo;
    if (from.isEmpty) return;
    setState(() {
      to.add(_draft);
      _draft = from.removeLast();
      _changed = !_sameTheme(_draft, _saved);
      _status = null;
    });
  }

  Future<bool> _apply() async {
    if (_busy) return false;
    final applying = _draft;
    final previous = c.getInterfacePreferences(_preset)['themeStudio'];
    final recovery = c.getInterfacePreferences(_preset)['themeStudioDraft'];
    final previousOrion = c.orionTheme;
    setState(() => _busy = true);
    try {
      c.applyThemeStudioState(
        _preset,
        document: applying.toJson(),
        draft: null,
        orionTheme: _preset == InterfacePreset.orion
            ? SynapseThemeCatalog.orionPreferencesForTheme(applying)
            : null,
      );
      await c.flushPersistence();
      if (c.persistenceError != null) {
        throw FormatException(c.persistenceError!);
      }
      if (!mounted) return true;
      setState(() {
        _saved = applying;
        _changed = !_sameTheme(_draft, _saved);
        _status = 'Applied to ${_preset.label}';
        _error = false;
      });
      return true;
    } on Object catch (failure) {
      c.applyThemeStudioState(
        _preset,
        document: previous,
        draft: recovery,
        orionTheme: _preset == InterfacePreset.orion ? previousOrion : null,
      );
      if (mounted) {
        setState(() {
          _status = 'Could not apply theme. ${_readableError(failure)}';
          _error = true;
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Used by the native host for window-manager close requests as well as ×.
  Future<bool> confirmClose() async {
    if (_busy) return false;
    if (!_dirty) return true;
    final choice = await showOrionDialog<String>(
      context,
      controller: c,
      builder: (_) => OrionAlertDialog(
        title: const Text('Save your theme changes?'),
        content: Text(
          'Your ${_preset.label} draft has changes that have not been applied.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'apply'),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (choice == 'apply') return _apply();
    if (choice == 'discard') {
      final recovery = c.getInterfacePreferences(_preset)['themeStudioDraft'];
      try {
        c.setInterfacePreference(_preset, 'themeStudioDraft', null);
        await c.flushPersistence();
        if (c.persistenceError != null) {
          throw FormatException(c.persistenceError!);
        }
        if (!mounted) return true;
        setState(() {
          _draft = _saved;
          _changed = false;
        });
        return true;
      } on Object catch (failure) {
        c.setInterfacePreference(_preset, 'themeStudioDraft', recovery);
        if (mounted) {
          setState(() {
            _status =
                'Could not discard the saved draft. ${_readableError(failure)}';
            _error = true;
          });
        }
        return false;
      }
    }
    return false;
  }

  Future<void> _close() async {
    if (await confirmClose() && mounted) widget.onClose?.call();
  }

  Future<void> _variant(InterfacePreset preset) async {
    if (_preset == preset || !await confirmClose() || !mounted) return;
    setState(() => _load(preset));
  }

  void _selectWindow(String window) => setState(() {
    _window = window;
    _selected = null;
    _elementBounds = const {};
    _zoom = 1;
  });

  void _usePreset(String id) {
    final palette = SynapseThemeCatalog.preset(_preset, id);
    _selectedSavedId = null;
    _edit(
      _draft.copyWith(
        name: palette.name,
        colors: palette.colors,
        orionTheme: palette.orionTheme,
        windows: {
          for (final window in _draft.windows.entries)
            window.key: window.value.copyWith(
              colors: const {},
              elements: {
                for (final element in window.value.elements.entries)
                  element.key: element.value.copyWith(clearPaint: true),
              },
            ),
        },
      ),
    );
  }

  void _select(String? id) {
    setState(() {
      _selected = id;
      _panel = 'Inspector';
      if (id != null && _query.isNotEmpty) {
        final descriptor = SynapseThemeCatalog.elements(
          _preset,
          _window,
        ).where((e) => e.id == id).firstOrNull;
        if (descriptor != null &&
            !descriptor.label.toLowerCase().contains(_query) &&
            !id.toLowerCase().contains(_query)) {
          _query = '';
          _layerSearch.clear();
        }
      }
    });
    _scaffold.currentState?.closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_layerScroll.hasClients) return;
      final context = _layerKeys[id]?.currentContext;
      if (context != null) {
        unawaited(
          Scrollable.ensureVisible(context, duration: _motion, alignment: .5),
        );
      }
    });
  }

  @override
  void dispose() {
    _layerSearch.dispose();
    _layerScroll.dispose();
    super.dispose();
  }

  Future<void> _pickColor(
    String label,
    Color initial,
    ValueChanged<Color> apply,
  ) async {
    final selected = await showThemeColorPicker(
      context,
      color: initial,
      title: label,
      controller: c,
    );
    if (selected != null && mounted) apply(selected);
  }

  Future<void> _import() async {
    final json = await showOrionDialog<String>(
      context,
      controller: c,
      builder: (_) => const _StudioImportDialog(),
    );
    if (json == null || !mounted) return;
    try {
      _selectedSavedId = null;
      final imported = SynapseThemeCatalog.normalizeForPreset(
        SynapseStudioTheme.decode(json),
        _preset,
      );
      _edit(imported);
      setState(() {
        _status = 'Imported into draft';
        _error = false;
      });
    } on Object catch (failure) {
      setState(() {
        _status = 'Could not import theme. ${_readableError(failure)}';
        _error = true;
      });
    }
  }

  Future<void> _export([SynapseStudioTheme? document, String? name]) async {
    try {
      final location = await files.getSaveLocation(
        suggestedName: '${name ?? _preset.sourceTag}-theme.json',
        initialDirectory: '${widget.controller.workspaceDirectory.path}/themes',
        acceptedTypeGroups: [
          const files.XTypeGroup(label: 'Theme JSON', extensions: ['json']),
        ],
      );
      if (location == null) return;
      final data = Uint8List.fromList(
        utf8.encode((document ?? _draft).encode()),
      );
      await files.XFile.fromData(
        data,
        mimeType: 'application/json',
      ).saveTo(location.path);
      if (mounted) {
        setState(() {
          _status = 'Theme exported';
          _error = false;
        });
      }
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _status = 'Could not export theme. ${_readableError(failure)}';
          _error = true;
        });
      }
    }
  }

  Future<String?> _themeName(String title, String name, {String? exceptId}) =>
      showOrionDialog<String>(
        context,
        controller: c,
        builder: (_) => _StudioThemeNameDialog(
          title: title,
          name: name,
          unavailableNames: {
            for (final item in _library.themes)
              if (item.id != exceptId) item.name.toLowerCase(),
          },
        ),
      );

  Future<void> _saveTheme({bool updateSelected = false}) async {
    if (_busy) return;
    final themes = _library.themes;
    final selected = themes
        .where((item) => item.id == _selectedSavedId)
        .firstOrNull;
    if (updateSelected && selected == null) {
      setState(() {
        _status = 'Load a saved theme before updating it.';
        _error = true;
      });
      return;
    }
    final baseName =
        selected?.name ??
        (_draft.name == 'Current' || _draft.name == 'Original'
            ? '${_preset.label} theme'
            : _draft.name);
    String withSuffix(String suffix) =>
        '${baseName.substring(0, math.min(baseName.length, 60 - suffix.length)).trimRight()}$suffix';
    var initialName = updateSelected
        ? selected!.name
        : withSuffix(selected == null ? '' : ' copy');
    if (!updateSelected) {
      final unavailable = {
        for (final theme in themes) theme.name.toLowerCase(),
      };
      var number = 2;
      while (unavailable.contains(initialName.toLowerCase())) {
        initialName = withSuffix(
          selected == null ? ' $number' : ' copy $number',
        );
        number++;
      }
    }
    final name = await _themeName(
      updateSelected
          ? 'Update theme'
          : selected == null
          ? 'Save theme'
          : 'Save a copy',
      initialName,
      exceptId: updateSelected ? selected!.id : null,
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final saved = await _library.save(
        name,
        _draft,
        replaceId: updateSelected ? selected!.id : null,
      );
      if (!mounted) return;
      _edit(_draft.copyWith(name: saved.name));
      setState(() {
        _selectedSavedId = saved.id;
        _status = updateSelected ? 'Saved theme updated' : 'Saved to library';
        _error = false;
      });
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _status = 'Could not save theme. ${_readableError(failure)}';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loadSaved(SavedStudioTheme saved) {
    try {
      final document = SynapseThemeCatalog.normalizeForPreset(
        saved.theme,
        _preset,
      );
      _edit(document);
      setState(() {
        _selectedSavedId = saved.id;
        _status = 'Loaded into draft';
        _error = false;
      });
    } on Object catch (failure) {
      setState(() {
        _status = 'Could not load theme. ${_readableError(failure)}';
        _error = true;
      });
    }
  }

  Future<void> _savedMenu(BuildContext anchor, SavedStudioTheme saved) async {
    final action = await showOrionPopupMenu<String>(
      anchor,
      controller: c,
      entries: [
        if (_selectedSavedId == saved.id) ...[
          const OrionMenuEntry(value: 'update', label: 'Update selected'),
          const OrionMenuEntry(value: 'copy', label: 'Save a copy'),
        ],
        const OrionMenuEntry(value: 'rename', label: 'Rename'),
        const OrionMenuEntry(value: 'export', label: 'Export'),
        const OrionMenuEntry(value: 'delete', label: 'Delete'),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'update' || action == 'copy') {
      await _saveTheme(updateSelected: action == 'update');
      return;
    }
    if (action == 'export') {
      try {
        await _export(saved.theme, saved.name);
      } on Object catch (failure) {
        if (mounted) {
          setState(() {
            _status =
                'Could not export saved theme. ${_readableError(failure)}';
            _error = true;
          });
        }
      }
      return;
    }
    if (action == 'rename') {
      final name = await _themeName(
        'Rename theme',
        saved.name,
        exceptId: saved.id,
      );
      if (!mounted || name == null) return;
      setState(() => _busy = true);
      try {
        final renamed = await _library.rename(saved.id, name);
        if (!mounted) return;
        if (_selectedSavedId == saved.id) {
          _edit(_draft.copyWith(name: renamed.name));
        }
        setState(() {
          _status = 'Saved theme renamed';
          _error = false;
        });
      } on Object catch (failure) {
        if (mounted) {
          setState(() {
            _status = 'Could not rename theme. ${_readableError(failure)}';
            _error = true;
          });
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final remove = await showOrionDialog<bool>(
      context,
      controller: c,
      builder: (context) => OrionAlertDialog(
        title: const Text('Delete saved theme?'),
        content: Text(saved.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || remove != true) return;
    setState(() => _busy = true);
    try {
      await _library.delete(saved.id);
      if (mounted) {
        setState(() {
          if (_selectedSavedId == saved.id) _selectedSavedId = null;
          _status = 'Saved theme deleted';
          _error = false;
        });
      }
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _status = 'Could not delete theme. ${_readableError(failure)}';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage(String slot) async {
    try {
      final file = await files.openFile(
        acceptedTypeGroups: [
          const files.XTypeGroup(
            label: 'PNG, JPEG or WebP',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 4 * 1024 * 1024) {
        throw const FormatException('Choose an image smaller than 4 MB.');
      }
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 8192 || descriptor.height > 8192) {
          throw const FormatException(
            'Images can be at most 8192 × 8192 pixels.',
          );
        }
      } finally {
        descriptor?.dispose();
        buffer.dispose();
      }
      final mime = bytes.length > 12 && bytes[0] == 0x89 && bytes[1] == 0x50
          ? 'png'
          : bytes.length > 12 &&
                ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
          ? 'webp'
          : 'jpeg';
      final image = SynapseStudioImage(
        data: 'data:image/$mime;base64,${base64Encode(bytes)}',
        fit: slot == 'logo' ? 'contain' : 'cover',
      );
      if (!image.isValid) {
        throw const FormatException('Choose a PNG, JPEG or WebP image.');
      }
      if (!mounted) return;
      _setImage(slot, image);
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _status = 'Could not add image. ${_readableError(failure)}';
          _error = true;
        });
      }
    }
  }

  SynapseStudioImage? _image(String slot) => switch (slot) {
    'background' => _windowTheme.background,
    'overlay' => _windowTheme.overlay,
    'logo' => _windowTheme.logo,
    _ => _elementTheme.image,
  };
  void _setImage(
    String slot,
    SynapseStudioImage? image, {
    bool record = true,
  }) => switch (slot) {
    'background' => _editWindow(
      _windowTheme.copyWith(background: image, clearBackground: image == null),
      record: record,
    ),
    'overlay' => _editWindow(
      _windowTheme.copyWith(overlay: image, clearOverlay: image == null),
      record: record,
    ),
    'logo' => _editWindow(
      _windowTheme.copyWith(logo: image, clearLogo: image == null),
      record: record,
    ),
    _ => _editElement(
      _elementTheme.copyWith(image: image, clearImage: image == null),
      record: record,
    ),
  };

  Duration get _motion =>
      c.reducedMotion || MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final theme = Theme.of(context);
    final buttonText = WidgetStatePropertyAll<TextStyle>(_StudioType.label);
    final fieldShape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colors.glassEnabled
              ? colors.elevated.withValues(alpha: .06)
              : colors.elevated,
          border: fieldShape,
          enabledBorder: fieldShape,
          focusedBorder: fieldShape.copyWith(
            borderSide: BorderSide(
              color: colors.accent.withValues(alpha: .65),
              width: 1.3,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          labelStyle: _StudioType.metadata.copyWith(color: colors.muted),
          hintStyle: _StudioType.label.copyWith(color: colors.muted),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            textStyle: buttonText,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle())
              .copyWith(textStyle: buttonText),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(textStyle: buttonText),
        ),
        dividerTheme: DividerThemeData(
          color: colors.outline(.14),
          thickness: 1,
          space: 1,
        ),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
              _history(false),
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): () =>
              _history(true),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_apply()),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () =>
              unawaited(_saveTheme()),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_scaffold.currentState?.isDrawerOpen ?? false) {
              _scaffold.currentState?.closeDrawer();
            } else {
              unawaited(_close());
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 1000;
              final rightWidth = box.maxWidth < 740 ? 244.0 : 300.0;
              final screen = Scaffold(
                key: _scaffold,
                backgroundColor: colors.glassEnabled
                    ? Colors.transparent
                    : colors.background,
                drawerEnableOpenDragGesture: false,
                drawer: wide
                    ? null
                    : Drawer(
                        width: 248,
                        backgroundColor: colors.glassEnabled
                            ? Colors.transparent
                            : colors.panel,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(24),
                          ),
                        ),
                        child: _glassChrome(
                          SafeArea(child: _layers(drawer: true)),
                        ),
                      ),
                body: Column(
                  children: [
                    _titlebar(),
                    _toolbar(compact: !wide, narrow: box.maxWidth < 740),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _surface(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (wide) ...[
                                SizedBox(width: 196, child: _layers()),
                                const VerticalDivider(width: 1),
                              ],
                              Expanded(child: _canvas()),
                              const VerticalDivider(width: 1),
                              SizedBox(
                                width: rightWidth,
                                child: _inspectorDock(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _footer(),
                  ],
                ),
              );
              return KeyedSubtree(
                key: const ValueKey('synapse-theme-studio'),
                child: widget.nativeWindow
                    ? screen
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: screen,
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _titlebar() {
    final colors = OrionColors.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.nativeWindow
                  ? (_) => unawaited(windowManager.startDragging())
                  : null,
              onDoubleTap: widget.nativeWindow
                  ? () => unawaited(_maximize())
                  : null,
              child: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.stateFill(.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.design_services_rounded,
                        size: 18,
                        color: colors.readableAccent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Theme Studio',
                        overflow: TextOverflow.ellipsis,
                        style: _StudioType.sectionTitle.copyWith(fontSize: 17),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _glassChrome(
            Container(
              width: 150,
              height: 36,
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: BoxDecoration(
                color: colors.glassEnabled ? Colors.transparent : colors.panel,
                borderRadius: BorderRadius.circular(18),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<InterfacePreset>(
                  key: const ValueKey('studio-variant'),
                  value: _preset,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(18),
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                  style: _StudioType.label.copyWith(color: colors.ink),
                  items: [
                    for (final preset in SynapseThemeCatalog.supported)
                      DropdownMenuItem(
                        value: preset,
                        child: Text(preset.label),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) unawaited(_variant(value));
                        },
                ),
              ),
            ),
            radius: 18,
          ),
          const SizedBox(width: 8),
          if (widget.nativeWindow) ...[
            IconButton(
              tooltip: 'Minimize studio',
              onPressed: () => unawaited(windowManager.minimize()),
              icon: const Icon(Icons.remove_rounded, size: 17),
            ),
            IconButton(
              tooltip: 'Maximize studio',
              onPressed: () => unawaited(_maximize()),
              icon: const Icon(Icons.crop_square_rounded, size: 15),
            ),
          ],
          IconButton(
            key: const ValueKey('studio-close'),
            tooltip: 'Close studio',
            onPressed: _busy ? null : () => unawaited(_close()),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Future<void> _maximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Widget _toolbar({required bool compact, required bool narrow}) {
    final colors = OrionColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Row(
        children: [
          if (compact) ...[
            IconButton.filledTonal(
              key: const ValueKey('studio-show-layers'),
              tooltip: 'Layers',
              onPressed: () => _scaffold.currentState?.openDrawer(),
              icon: const Icon(Icons.layers_outlined, size: 19),
            ),
            const SizedBox(width: 6),
          ],
          _glassChrome(
            Container(
              width: narrow ? 144 : 182,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.glassEnabled ? Colors.transparent : colors.panel,
                borderRadius: BorderRadius.circular(20),
              ),
              child: DropdownButtonHideUnderline(child: _targetMenu()),
            ),
            radius: 20,
          ),
          const SizedBox(width: 8),
          _toolGroup(
            children: [
              _toolIcon(
                'Undo (Ctrl+Z)',
                Icons.undo_rounded,
                _undo.isEmpty ? null : () => _history(false),
                key: const ValueKey('studio-undo'),
              ),
              _toolIcon(
                'Redo (Ctrl+Shift+Z)',
                Icons.redo_rounded,
                _redo.isEmpty ? null : () => _history(true),
                key: const ValueKey('studio-redo'),
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            key: const ValueKey('studio-save-theme'),
            onPressed: _busy ? null : _saveTheme,
            style: TextButton.styleFrom(
              backgroundColor: colors.stateFill(.10),
              minimumSize: const Size(40, 40),
              padding: EdgeInsets.symmetric(horizontal: narrow ? 10 : 14),
            ),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(narrow ? 'Save' : 'Save theme'),
          ),
          const SizedBox(width: 8),
          _toolGroup(
            children: [
              _toolIcon(
                'Import theme',
                Icons.file_open_outlined,
                _busy ? null : _import,
                key: const ValueKey('studio-import'),
              ),
              _toolIcon(
                'Export draft',
                Icons.file_download_outlined,
                _busy ? null : _export,
                key: const ValueKey('studio-export'),
              ),
            ],
          ),
          const SizedBox(width: 6),
          _toolIcon(
            'Reset theme',
            Icons.restart_alt_rounded,
            _busy
                ? null
                : () {
                    _selectedSavedId = null;
                    _edit(SynapseThemeCatalog.defaults(_preset));
                  },
            key: const ValueKey('studio-reset'),
          ),
        ],
      ),
    );
  }

  Widget _targetMenu() {
    final colors = OrionColors.of(context);
    return DropdownButton<String>(
      key: ValueKey(
        _preset == InterfacePreset.orion
            ? 'studio-orion-page'
            : 'studio-window',
      ),
      value: _preset == InterfacePreset.orion ? _previewPage : _window,
      isExpanded: true,
      borderRadius: BorderRadius.circular(18),
      icon: const Icon(Icons.expand_more_rounded, size: 18),
      style: _StudioType.label.copyWith(color: colors.ink),
      items: [
        for (final entry
            in _preset == InterfacePreset.orion
                ? _orionPages.entries
                : SynapseThemeCatalog.windows(
                    _preset,
                  ).map((w) => MapEntry(w.id, w.label)))
          DropdownMenuItem(
            value: entry.key,
            child: Row(
              children: [
                Icon(Icons.web_asset_rounded, size: 16, color: colors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        if (_preset == InterfacePreset.orion) {
          setState(() {
            _previewPage = value;
            _selected = null;
            _elementBounds = const {};
          });
        } else {
          _selectWindow(value);
        }
      },
    );
  }

  Widget _glassChrome(Widget child, {double radius = 24}) => OrionGlassSurface(
    radius: radius,
    tint: OrionColors.of(context).panel.withValues(alpha: .055),
    child: child,
  );

  Widget _toolGroup({required List<Widget> children}) => _glassChrome(
    Container(
      decoration: BoxDecoration(
        color: OrionColors.of(context).glassEnabled
            ? Colors.transparent
            : OrionColors.of(context).panel,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
    radius: 20,
  );

  Widget _toolIcon(
    String tooltip,
    IconData icon,
    VoidCallback? action, {
    Key? key,
  }) => IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: action,
    constraints: const BoxConstraints.tightFor(width: 36, height: 40),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      minimumSize: const Size(36, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(icon, size: 18),
  );

  Widget _surface({required Widget child}) => _glassChrome(
    Material(
      key: const ValueKey('studio-workbench'),
      color: OrionColors.of(context).glassEnabled
          ? Colors.transparent
          : OrionColors.of(context).panel,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );

  Widget _inspectorDock() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            for (final entry in [
              ('Inspector', 'Edit'),
              ('Easy theme', 'Theme'),
              ('Images', 'Images'),
              ('Saved themes', 'Saved'),
            ]) ...[
              if (entry.$1 != 'Inspector') const SizedBox(width: 2),
              Expanded(child: _modeButton(entry.$1, entry.$2)),
            ],
          ],
        ),
      ),
      Expanded(
        child: AnimatedSwitcher(
          duration: _motion,
          switchInCurve: OrionMotion.effects,
          switchOutCurve: OrionMotion.effects,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: SingleChildScrollView(
            key: ValueKey('studio-content:$_panel'),
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
            child: switch (_panel) {
              'Easy theme' => _easy(),
              'Images' => _images(),
              'Saved themes' => _savedThemesPanel(),
              _ => _inspector(),
            },
          ),
        ),
      ),
    ],
  );

  Widget _modeButton(String mode, String label) {
    final colors = OrionColors.of(context);
    final selected = _panel == mode;
    final index = [
      'Inspector',
      'Easy theme',
      'Images',
      'Saved themes',
    ].indexOf(mode);
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: mode,
        child: TextButton(
          key: ValueKey('studio-mode:$mode'),
          onPressed: () => setState(() => _panel = mode),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            backgroundColor: selected
                ? colors.stateFill(.20)
                : colors.elevated.withValues(alpha: .42),
            foregroundColor: selected ? colors.readableAccent : colors.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(index == 0 ? 18 : 6),
                right: Radius.circular(index == 3 ? 18 : 6),
              ),
            ),
            textStyle: _StudioType.label.copyWith(fontSize: 11),
            animationDuration: _motion,
          ),
          child: Text(label, maxLines: 1),
        ),
      ),
    );
  }

  Widget _layers({bool drawer = false}) {
    final elements = SynapseThemeCatalog.elements(_preset, _window).where(
      (e) =>
          (_elementBounds.isEmpty || _elementBounds.containsKey(e.id)) &&
          (e.label.toLowerCase().contains(_query) ||
              e.id.toLowerCase().contains(_query)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Layers',
                    style: _StudioType.label.copyWith(fontSize: 13),
                  ),
                ),
                if (drawer)
                  IconButton(
                    tooltip: 'Close layers',
                    onPressed: () => _scaffold.currentState?.closeDrawer(),
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: TextField(
            controller: _layerSearch,
            key: const ValueKey('studio-layer-search'),
            onChanged: (text) =>
                setState(() => _query = text.toLowerCase().trim()),
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Find a layer',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('studio-clear-search'),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _layerSearch.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 15),
                    ),
              prefixIcon: const Icon(Icons.search_rounded, size: 17),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: _layerScroll,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            children: [
              _layerTile(null, _windowLabel, Icons.web_asset_rounded),
              for (final element in elements)
                _layerTile(element.id, element.label, switch (element.kind) {
                  'editor' => Icons.code_rounded,
                  'logo' => Icons.image_outlined,
                  'button' => Icons.smart_button_outlined,
                  'text' || 'label' => Icons.title_rounded,
                  _ => Icons.layers_outlined,
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _layerTile(String? id, String label, IconData icon) => Padding(
    key: _layerKeys.putIfAbsent(id, () => GlobalKey()),
    padding: const EdgeInsets.only(bottom: 2),
    child: ListTile(
      key: ValueKey('studio-layer:${id ?? 'window'}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      minLeadingWidth: 17,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: _selected == id,
      selectedTileColor: OrionColors.of(context).stateFill(.18),
      leading: Icon(icon, size: 17),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      onTap: () => _select(id),
    ),
  );

  Widget _canvas() => ColoredBox(
    color: OrionColors.of(context).glassEnabled
        ? Colors.transparent
        : Color.lerp(
            OrionColors.of(context).background,
            OrionColors.of(context).panel,
            .25,
          )!,
    child: Column(
      children: [
        SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Preview',
                    style: _StudioType.label.copyWith(fontSize: 13),
                  ),
                ),
                _toolIcon(
                  'Zoom out',
                  Icons.remove_rounded,
                  _zoom <= .5
                      ? null
                      : () => setState(() => _zoom = math.max(.5, _zoom - .25)),
                ),
                TextButton(
                  key: const ValueKey('studio-fit'),
                  onPressed: () => setState(() => _zoom = 1),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(40, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    _zoom == 1 ? 'Fit' : '${(_zoom * 100).round()}%',
                    style: _StudioType.metadata,
                  ),
                ),
                _toolIcon(
                  'Zoom in',
                  Icons.add_rounded,
                  _zoom >= 2
                      ? null
                      : () => setState(() => _zoom = math.min(2, _zoom + .25)),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SynapseStudioPreview(
            controller: c,
            preset: _preset,
            theme: _draft,
            window: _windowDescriptor,
            selected: _selected,
            zoom: _zoom,
            previewPage: _previewPage,
            onSelect: _select,
            onMoveStart: _remember,
            onGeometryChanged: (bounds) =>
                setState(() => _elementBounds = bounds),
            onMove: (id, delta) {
              final current =
                  _windowTheme.elements[id] ?? SynapseStudioElement();
              _edit(
                _draft.withElement(
                  _window,
                  id,
                  current.copyWith(
                    x: current.x + delta.dx,
                    y: current.y + delta.dy,
                  ),
                ),
                record: false,
              );
            },
            onResize: (id, size) {
              final current =
                  _windowTheme.elements[id] ?? SynapseStudioElement();
              _edit(
                _draft.withElement(
                  _window,
                  id,
                  current.copyWith(width: size.width, height: size.height),
                ),
                record: false,
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _panelTitle(String title, {String? subtitle}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _StudioType.sectionTitle.copyWith(fontSize: 17)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: _StudioType.metadata.copyWith(
              color: OrionColors.of(context).muted,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _propertySection(
    String title, {
    required Widget child,
    Widget? trailing,
  }) {
    final colors = OrionColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.glassEnabled
            ? colors.elevated.withValues(alpha: .035)
            : Color.lerp(colors.panel, colors.elevated, .42),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: _StudioType.label.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) SizedBox(height: 28, child: trailing),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _inspector() {
    final element = _element;
    final measuredSize = _elementBounds[_selected]?.size;
    final inheritedSize = measuredSize == null
        ? element?.bounds.size ?? Size.zero
        : measuredSize / c.uiScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (element != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('studio-inspect-window'),
              onPressed: () => _select(null),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.chevron_left_rounded, size: 16),
              label: Text(
                _windowDescriptor.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _StudioType.metadata,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _panelTitle(element.label),
          _propertySection(
            'Layout',
            trailing: _toolIcon(
              'Reset layout',
              Icons.restart_alt_rounded,
              () => _editElement(
                _elementTheme.copyWith(x: 0, y: 0, clearSize: true),
              ),
            ),
            child: Column(
              children: [
                _numberRow(
                  'X',
                  _elementTheme.x,
                  'Y',
                  _elementTheme.y,
                  (value) => _editElement(_elementTheme.copyWith(x: value)),
                  (value) => _editElement(_elementTheme.copyWith(y: value)),
                  minA: -4096,
                  minB: -4096,
                  max: 4096,
                ),
                const SizedBox(height: 4),
                _numberRow(
                  'Width',
                  _elementTheme.width ?? inheritedSize.width,
                  'Height',
                  _elementTheme.height ?? inheritedSize.height,
                  (value) => _editElement(_elementTheme.copyWith(width: value)),
                  (value) =>
                      _editElement(_elementTheme.copyWith(height: value)),
                  minA: 8,
                  minB: 8,
                  max: 4096,
                ),
              ],
            ),
          ),
          _propertySection(
            'Appearance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _number(
                  'Corner radius',
                  _elementTheme.radius ?? 0,
                  (value) =>
                      _editElement(_elementTheme.copyWith(radius: value)),
                  min: 0,
                  max: 256,
                  inherited: _elementTheme.radius == null,
                ),
                const SizedBox(height: 8),
                _slider(
                  'Opacity',
                  _elementTheme.opacity,
                  (value) => _editElement(
                    _elementTheme.copyWith(opacity: value),
                    record: false,
                  ),
                ),
                const SizedBox(height: 6),
                for (final paint in ['fill', 'foreground', 'border'])
                  _elementColor(element, paint),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _panel = 'Images'),
            icon: const Icon(Icons.image_outlined, size: 17),
            label: const Text('Element image'),
          ),
          TextButton.icon(
            key: const ValueKey('studio-reset-element'),
            onPressed: () => _editElement(SynapseStudioElement()),
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('Reset element'),
          ),
        ] else ...[
          _panelTitle('Window settings', subtitle: _windowLabel),
          _propertySection(
            'Theme',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StudioTextField(
                  key: ValueKey('studio-theme-name:$_preset'),
                  value: _draft.name,
                  onChanged: (value) => _edit(_draft.copyWith(name: value)),
                  label: 'Name',
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('studio-font:${_draft.fontFamily}'),
                  initialValue:
                      [
                        'SynapseInter',
                        'RobotoFlex',
                        'OriginalSegoeUI',
                        'JetBrainsMono',
                      ].contains(_draft.fontFamily)
                      ? _draft.fontFamily
                      : 'SynapseInter',
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(18),
                  decoration: const InputDecoration(
                    labelText: 'Typeface',
                    isDense: true,
                  ),
                  items: [
                    for (final font in [
                      'SynapseInter',
                      'RobotoFlex',
                      'OriginalSegoeUI',
                      'JetBrainsMono',
                    ])
                      DropdownMenuItem(
                        value: font,
                        child: Text(switch (font) {
                          'SynapseInter' => 'Inter',
                          'RobotoFlex' => 'Roboto Flex',
                          'OriginalSegoeUI' => 'Segoe / Cantarell',
                          _ => 'JetBrains Mono',
                        }, style: _StudioType.label),
                      ),
                  ],
                  onChanged: (font) {
                    if (font != null) _edit(_draft.copyWith(fontFamily: font));
                  },
                ),
              ],
            ),
          ),
          if (_windowDescriptor.hasOwnWindow)
            _propertySection(
              'Window size',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _numberRow(
                    'Width',
                    _windowTheme.width ?? _windowDescriptor.defaultSize.width,
                    'Height',
                    _windowTheme.height ?? _windowDescriptor.defaultSize.height,
                    (value) => _editWindow(_windowTheme.copyWith(width: value)),
                    (value) =>
                        _editWindow(_windowTheme.copyWith(height: value)),
                    minA: _windowDescriptor.minimumSize.width,
                    minB: _windowDescriptor.minimumSize.height,
                    max: 4096,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          _editWindow(_windowTheme.copyWith(clearSize: true)),
                      icon: const Icon(Icons.restart_alt_rounded, size: 15),
                      label: const Text('Original size'),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Shares the main window size.',
                style: _StudioType.metadata.copyWith(
                  color: OrionColors.of(context).muted,
                ),
              ),
            ),
          _propertySection(
            'Window colors',
            child: Column(
              children: [
                for (final group in SynapseThemeCatalog.roles(
                  _preset,
                ).map((r) => r.group).toSet())
                  ExpansionTile(
                    key: ValueKey('studio-role-group:$group'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    dense: true,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(group, style: _StudioType.label),
                    children: [
                      for (final role in SynapseThemeCatalog.roles(
                        _preset,
                      ).where((r) => r.group == group))
                        _colorRow(
                          role.label,
                          Color(_colors[role.key] ?? 0xffffffff),
                          () => _pickColor(
                            role.label,
                            Color(_colors[role.key] ?? 0xffffffff),
                            (color) => _editWindow(
                              _windowTheme.copyWith(
                                colors: {
                                  ..._windowTheme.colors,
                                  role.key: color.toARGB32(),
                                },
                              ),
                            ),
                          ),
                          key: ValueKey('studio-role:${role.key}'),
                          inherited: !_windowTheme.colors.containsKey(role.key),
                          onReset: _windowTheme.colors.containsKey(role.key)
                              ? () => _editWindow(
                                  _windowTheme.copyWith(
                                    colors: {..._windowTheme.colors}
                                      ..remove(role.key),
                                  ),
                                )
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _panel = 'Images'),
            icon: const Icon(Icons.image_outlined, size: 17),
            label: const Text('Background & logo'),
          ),
        ],
      ],
    );
  }

  Widget _elementColor(SynapseStudioElementDescriptor element, String paint) {
    final role = switch (paint) {
      'fill' => element.fillRole,
      'foreground' => element.foregroundRole,
      _ => element.borderRole,
    };
    final override = switch (paint) {
      'fill' => _elementTheme.fill,
      'foreground' => _elementTheme.foreground,
      _ => _elementTheme.border,
    };
    final value = Color(
      override ?? _colors[role] ?? (paint == 'foreground' ? 0xffdedede : 0),
    );
    return _colorRow(
      switch (paint) {
        'fill' => 'Fill',
        'foreground' => 'Text / icon',
        _ => 'Border',
      },
      value,
      () => _pickColor(
        'Element $paint',
        value,
        (color) => _editElement(switch (paint) {
          'fill' => _elementTheme.copyWith(fill: color.toARGB32()),
          'foreground' => _elementTheme.copyWith(foreground: color.toARGB32()),
          _ => _elementTheme.copyWith(border: color.toARGB32()),
        }),
      ),
      key: ValueKey('studio-element-color:$paint'),
      inherited: override == null,
      onReset: override == null
          ? null
          : () => _editElement(switch (paint) {
              'fill' => _elementTheme.copyWith(clearFill: true),
              'foreground' => _elementTheme.copyWith(clearForeground: true),
              _ => _elementTheme.copyWith(clearBorder: true),
            }),
    );
  }

  Widget _easy() {
    int findColor(List<String> roles, int fallback) {
      for (final role in roles) {
        if (_draft.colors[role] != null) return _draft.colors[role]!;
      }
      return fallback;
    }

    final base = findColor([
          'background',
          'windowBg',
          'shell.windowBg',
          'shellBg',
        ], 0xff202329),
        accent = findColor([
          'accent',
          'accent.primary',
          'topBarFrom',
          'buttonBg',
        ], 0xff5988db),
        text = findColor([
          'ink',
          'text',
          'topBar.text',
          'logoTextColor',
        ], 0xffeeeeee);
    void recolor({int? newBase, int? newAccent, int? newText}) => _edit(
      SynapseThemeCatalog.easy(
        _preset,
        base: newBase ?? base,
        accent: newAccent ?? accent,
        text: newText ?? text,
        current: _draft,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('Easy theme'),
        _propertySection(
          'Palette',
          child: Column(
            children: [
              _colorRow(
                'Background',
                Color(base),
                () => _pickColor(
                  'Background',
                  Color(base),
                  (color) => recolor(newBase: color.toARGB32()),
                ),
                key: const ValueKey('studio-easy-base'),
              ),
              _colorRow(
                'Accent',
                Color(accent),
                () => _pickColor(
                  'Accent',
                  Color(accent),
                  (color) => recolor(newAccent: color.toARGB32()),
                ),
                key: const ValueKey('studio-easy-accent'),
              ),
              _colorRow(
                'Text',
                Color(text),
                () => _pickColor(
                  'Text',
                  Color(text),
                  (color) => recolor(newText: color.toARGB32()),
                ),
                key: const ValueKey('studio-easy-text'),
              ),
            ],
          ),
        ),
        if (_preset == InterfacePreset.orion) ...[
          _propertySection('Appearance', child: _orionEasyControls()),
          _heading('Orion themes'),
          _presetGrid([
            for (final preset in OrionThemePreferences.builtInPresets)
              _presetTile(
                preset.name,
                (preset.preferences.gradientEnabled
                    ? preset.preferences.gradientColors
                    : SynapseThemeCatalog.orionPalette(
                        preset.preferences,
                      ).values.take(3).map((value) => Color(value)).toList()),
                () {
                  _selectedSavedId = null;
                  _setOrionPreferences(preset.preferences);
                  _edit(_draft.copyWith(name: preset.name), record: false);
                },
                key: ValueKey('studio-orion-preset:${preset.id}'),
                selected: _draft.name == preset.name,
              ),
          ]),
          const SizedBox(height: 16),
        ],
        _heading('Starting points'),
        _presetGrid([
          for (final preset in [
            ('original', 'Original'),
            ('midnight', 'Midnight'),
            ('ocean', 'Ocean'),
            ('ember', 'Ember'),
          ])
            _presetTile(
              preset.$2,
              SynapseThemeCatalog.preset(
                _preset,
                preset.$1,
              ).colors.values.take(3).map((value) => Color(value)).toList(),
              () => _usePreset(preset.$1),
              key: ValueKey('studio-preset:${preset.$1}'),
              selected:
                  _draft.name ==
                  SynapseThemeCatalog.preset(_preset, preset.$1).name,
            ),
        ]),
      ],
    );
  }

  Widget _presetGrid(List<Widget> children) => Column(
    children: [
      for (var index = 0; index < children.length; index += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(child: children[index]),
              const SizedBox(width: 6),
              Expanded(
                child: index + 1 < children.length
                    ? children[index + 1]
                    : const SizedBox(),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _presetTile(
    String name,
    List<Color> colors,
    VoidCallback onPressed, {
    Key? key,
    bool selected = false,
  }) {
    final palette = OrionColors.of(context);
    return TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 72),
        padding: const EdgeInsets.all(10),
        backgroundColor: selected
            ? palette.stateFill(.15)
            : palette.elevated.withValues(alpha: .38),
        foregroundColor: selected ? palette.readableAccent : palette.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 18,
              child: Row(
                children: [
                  for (final color in colors)
                    Expanded(
                      child: ColoredBox(
                        color: color,
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _StudioType.label.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  void _setOrionPreferences(
    OrionThemePreferences preferences, {
    bool record = true,
  }) => _edit(
    _draft.copyWith(
      orionTheme: preferences,
      colors: SynapseThemeCatalog.orionPalette(preferences),
      windows: {
        ..._draft.windows,
        'main': _draft.window('main').copyWith(colors: const {}),
      },
    ),
    record: record,
  );

  Widget _orionEasyControls() {
    final preferences = SynapseThemeCatalog.orionPreferencesForTheme(_draft);
    void gradientColors(List<Color> colors) => _setOrionPreferences(
      preferences.copyWith(
        presetId: 'custom',
        gradientColors: colors,
        clearGradientStops: true,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ThemeMode>(
          key: ValueKey('studio-orion-mode:${preferences.themeMode}'),
          initialValue: preferences.themeMode,
          decoration: const InputDecoration(labelText: 'Mode', isDense: true),
          items: [
            for (final mode in ThemeMode.values)
              DropdownMenuItem(
                value: mode,
                child: Text(switch (mode) {
                  ThemeMode.dark => 'Dark',
                  ThemeMode.light => 'Light',
                  ThemeMode.system => 'System',
                }, style: const TextStyle(fontSize: 12)),
              ),
          ],
          onChanged: (mode) {
            if (mode != null) {
              _setOrionPreferences(preferences.copyWith(themeMode: mode));
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('studio-orion-gradient'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Gradient', style: TextStyle(fontSize: 12)),
          value: preferences.gradientEnabled,
          onChanged: (value) => _setOrionPreferences(
            preferences.copyWith(gradientEnabled: value, presetId: 'custom'),
          ),
        ),
        if (preferences.gradientEnabled) ...[
          for (
            var index = 0;
            index < preferences.gradientColors.length;
            index++
          )
            Row(
              children: [
                Expanded(
                  child: _colorRow(
                    'Color ${index + 1}',
                    preferences.gradientColors[index],
                    () => _pickColor(
                      'Gradient color ${index + 1}',
                      preferences.gradientColors[index],
                      (color) => gradientColors(
                        [...preferences.gradientColors]..[index] = color,
                      ),
                    ),
                    key: ValueKey('studio-orion-gradient-color:$index'),
                  ),
                ),
                if (preferences.gradientColors.length > 2)
                  IconButton(
                    tooltip: 'Remove gradient color ${index + 1}',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => gradientColors(
                      [...preferences.gradientColors]..removeAt(index),
                    ),
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 16,
                    ),
                  ),
              ],
            ),
          if (preferences.gradientColors.length < 4)
            TextButton.icon(
              onPressed: () => gradientColors([
                ...preferences.gradientColors,
                preferences.gradientColors.last,
              ]),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add color'),
            ),
          _number(
            'Gradient angle',
            preferences.gradientAngle,
            (angle) => _setOrionPreferences(
              preferences.copyWith(gradientAngle: angle, presetId: 'custom'),
            ),
            min: 0,
            max: 359,
          ),
        ],
        SwitchListTile(
          key: const ValueKey('studio-orion-rain'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Rain glass', style: TextStyle(fontSize: 12)),
          value: preferences.rainEnabled,
          onChanged: (value) => _setOrionPreferences(
            preferences.copyWith(rainEnabled: value, presetId: 'custom'),
          ),
        ),
        if (preferences.rainEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Desktop rain runs in the live Orion window after Apply.',
              style: _StudioType.metadata.copyWith(
                color: OrionColors.of(context).muted,
                fontSize: 11,
              ),
            ),
          ),
        _boundedSlider(
          'Window opacity',
          preferences.windowOpacity,
          .5,
          1,
          (value) => _setOrionPreferences(
            preferences.copyWith(windowOpacity: value),
            record: false,
          ),
        ),
        _boundedSlider(
          'Surface tint',
          preferences.surfaceTint,
          0,
          1,
          (value) => _setOrionPreferences(
            preferences.copyWith(surfaceTint: value, presetId: 'custom'),
            record: false,
          ),
        ),
        _boundedSlider(
          'Outline strength',
          preferences.outlineStrength,
          0,
          2,
          (value) => _setOrionPreferences(
            preferences.copyWith(outlineStrength: value),
            record: false,
          ),
        ),
      ],
    );
  }

  Widget _boundedSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text('${(value * 100).round()}%', style: _StudioType.metadata),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChangeStart: (_) => _remember(),
        onChanged: change,
      ),
    ],
  );

  Widget _images() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _panelTitle('Images', subtitle: _windowLabel),
      for (final slot in [
        'background',
        'overlay',
        'logo',
        if (_selected != null) 'element',
      ])
        _imageSection(slot),
    ],
  );

  Widget _savedThemesPanel() {
    final themes = _library.themes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Saved themes', style: _StudioType.sectionTitle),
            ),
            Text(
              '${themes.length}/${ThemeStudioLibrary.maximumThemes}',
              style: _StudioType.metadata.copyWith(
                color: OrionColors.of(context).muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _preset.label,
          style: _StudioType.metadata.copyWith(
            color: OrionColors.of(context).muted,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          key: const ValueKey('studio-library-save'),
          onPressed: _busy ? null : _saveTheme,
          icon: const Icon(Icons.bookmark_add_outlined, size: 17),
          label: Text(_selectedSavedId == null ? 'Save theme' : 'Save a copy'),
        ),
        if (_selectedSavedId != null &&
            themes.any((entry) => entry.id == _selectedSavedId)) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            key: const ValueKey('studio-library-update'),
            onPressed: _busy ? null : () => _saveTheme(updateSelected: true),
            icon: const Icon(Icons.save_outlined, size: 17),
            label: const Text('Update selected'),
          ),
        ],
        const SizedBox(height: 12),
        if (themes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No saved themes yet.',
              textAlign: TextAlign.center,
              style: _StudioType.metadata.copyWith(
                color: OrionColors.of(context).muted,
              ),
            ),
          ),
        for (final saved in themes.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Material(
              key: ValueKey('studio-saved:${saved.id}'),
              color: _selectedSavedId == saved.id
                  ? OrionColors.of(context).stateFill(.12)
                  : OrionColors.of(context).chrome(
                      OrionColors.of(context).elevated,
                      role: 'elevated',
                    ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                child: Row(
                  children: [
                    Icon(
                      _selectedSavedId == saved.id
                          ? Icons.bookmark_rounded
                          : Icons.palette_outlined,
                      size: 17,
                      color: _selectedSavedId == saved.id
                          ? OrionColors.of(context).readableAccent
                          : OrionColors.of(context).muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        saved.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _StudioType.label.copyWith(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      key: ValueKey('studio-saved-load:${saved.id}'),
                      onPressed: _busy ? null : () => _loadSaved(saved),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Load', style: TextStyle(fontSize: 11)),
                    ),
                    Builder(
                      builder: (anchor) => IconButton(
                        key: ValueKey('studio-saved-menu:${saved.id}'),
                        tooltip: 'More for ${saved.name}',
                        onPressed: _busy
                            ? null
                            : () => unawaited(_savedMenu(anchor, saved)),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_vert_rounded, size: 17),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _imageSection(String slot) {
    final image = _image(slot);
    final title = switch (slot) {
      'background' => 'Background',
      'overlay' => 'Overlay',
      'logo' => 'Logo',
      _ => 'Element image',
    };
    return _propertySection(
      title,
      trailing: image == null
          ? null
          : IconButton(
              tooltip: 'Remove $title',
              onPressed: () => _setImage(slot, null),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (image?.bytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 76,
                  child: Image.memory(
                    image!.bytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            key: ValueKey('studio-image:$slot'),
            onPressed: () => _pickImage(slot),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
            label: Text(image == null ? 'Choose image' : 'Replace image'),
          ),
          if (image != null) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('studio-image-fit:$slot:${image.fit}'),
              initialValue: image.fit,
              decoration: const InputDecoration(
                labelText: 'Fit',
                isDense: true,
              ),
              items: [
                for (final fit in SynapseStudioImage.fits)
                  DropdownMenuItem(
                    value: fit,
                    child: Text(switch (fit) {
                      'cover' => 'Cover',
                      'contain' => 'Contain',
                      'fill' => 'Stretch',
                      'fitWidth' => 'Fit width',
                      'fitHeight' => 'Fit height',
                      'none' => 'Original size',
                      _ => 'Scale down',
                    }, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: (fit) {
                if (fit != null) _setImage(slot, image.copyWith(fit: fit));
              },
            ),
            _slider(
              'Opacity',
              image.opacity,
              (value) => _setImage(
                slot,
                image.copyWith(opacity: value),
                record: false,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: _StudioType.label.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget _colorRow(
    String label,
    Color value,
    VoidCallback onTap, {
    Key? key,
    bool inherited = false,
    VoidCallback? onReset,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        Expanded(
          child: TextButton(
            key: key,
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              foregroundColor: OrionColors.of(context).ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerLeft,
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: value,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: OrionColors.of(context).outline(.35),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: _StudioType.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  inherited ? 'Default' : themeColorHex(value),
                  style: _StudioType.metadata.copyWith(
                    fontSize: 10,
                    color: OrionColors.of(context).muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onReset != null)
          IconButton(
            tooltip: 'Reset $label',
            onPressed: onReset,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.restart_alt_rounded, size: 15),
          ),
      ],
    ),
  );

  Widget _numberRow(
    String a,
    double valueA,
    String b,
    double valueB,
    ValueChanged<double> editA,
    ValueChanged<double> editB, {
    double minA = 0,
    double minB = 0,
    double max = 4096,
  }) => Row(
    children: [
      Expanded(
        child: _number(a, valueA, editA, min: minA, max: max),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _number(
          b,
          valueB,
          editB,
          min: math.max(-2160, minB),
          max: math.min(2160, max),
        ),
      ),
    ],
  );
  Widget _number(
    String label,
    double value,
    ValueChanged<double> edit, {
    required double min,
    required double max,
    bool inherited = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: _StudioNumberField(
      key: ValueKey('studio-number:$_window:${_selected ?? 'window'}:$label'),
      label: label,
      value: value,
      min: min,
      max: max,
      onChanged: edit,
      inherited: inherited,
    ),
  );
  Widget _slider(String label, double value, ValueChanged<double> edit) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
              Text('${(value * 100).round()}%', style: _StudioType.metadata),
            ],
          ),
          SizedBox(
            height: 36,
            child: Slider(
              value: value.clamp(0, 1),
              onChangeStart: (_) => _remember(),
              onChanged: edit,
            ),
          ),
        ],
      );

  Widget _footer() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 14, 12),
    child: Row(
      children: [
        Icon(
          _error
              ? Icons.error_outline_rounded
              : _dirty
              ? Icons.circle
              : Icons.check_circle_outline_rounded,
          size: _dirty && !_error ? 7 : 15,
          color: _error
              ? Theme.of(context).colorScheme.error
              : _dirty
              ? OrionColors.of(context).readableAccent
              : OrionColors.of(context).muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _status ?? (_dirty ? 'Unapplied changes' : 'All changes applied'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _StudioType.metadata.copyWith(
              color: _error
                  ? Theme.of(context).colorScheme.error
                  : OrionColors.of(context).muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          key: const ValueKey('studio-cancel'),
          onPressed: _busy ? null : () => unawaited(_close()),
          child: const Text('Close'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('studio-apply'),
          onPressed: _busy || !_dirty ? null : () => unawaited(_apply()),
          style: FilledButton.styleFrom(
            minimumSize: const Size(112, 40),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          icon: _busy
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : const Icon(Icons.check_rounded, size: 17),
          label: const Text('Apply'),
        ),
      ],
    ),
  );
}

String _readableError(Object error) => error is FormatException
    ? error.message
    : error is PlatformException
    ? (error.message ?? 'The desktop service was unavailable.')
    : 'Try again.';

// Compare immutable fields directly: pointer edits never serialize image data.
bool _sameTheme(SynapseStudioTheme a, SynapseStudioTheme b) =>
    identical(a, b) ||
    (a.name == b.name &&
        a.orionTheme == b.orionTheme &&
        a.fontFamily == b.fontFamily &&
        mapEquals(a.colors, b.colors) &&
        _sameMap(a.windows, b.windows, _sameWindow));
bool _sameWindow(SynapseStudioWindow a, SynapseStudioWindow b) =>
    identical(a, b) ||
    (a.width == b.width &&
        a.height == b.height &&
        mapEquals(a.colors, b.colors) &&
        _sameMap(a.elements, b.elements, _sameElement) &&
        _sameImage(a.background, b.background) &&
        _sameImage(a.overlay, b.overlay) &&
        _sameImage(a.logo, b.logo));
bool _sameElement(SynapseStudioElement a, SynapseStudioElement b) =>
    identical(a, b) ||
    (a.x == b.x &&
        a.y == b.y &&
        a.width == b.width &&
        a.height == b.height &&
        a.radius == b.radius &&
        a.opacity == b.opacity &&
        a.fill == b.fill &&
        a.foreground == b.foreground &&
        a.border == b.border &&
        _sameImage(a.image, b.image));
bool _sameImage(SynapseStudioImage? a, SynapseStudioImage? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.data == b.data &&
        a.fit == b.fit &&
        a.opacity == b.opacity);
bool _sameMap<T>(
  Map<String, T> a,
  Map<String, T> b,
  bool Function(T, T) equal,
) =>
    identical(a, b) ||
    (a.length == b.length &&
        a.entries.every(
          (entry) =>
              b.containsKey(entry.key) && equal(entry.value, b[entry.key] as T),
        ));

class _StudioNumberField extends StatefulWidget {
  const _StudioNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.inherited = false,
  });
  final String label;
  final bool inherited;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  @override
  State<_StudioNumberField> createState() => _StudioNumberFieldState();
}

class _StudioNumberFieldState extends State<_StudioNumberField> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.inherited ? '' : _format(widget.value),
    );
  }

  String _format(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);
  @override
  void didUpdateWidget(covariant _StudioNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus &&
        (oldWidget.value != widget.value ||
            oldWidget.inherited != widget.inherited)) {
      _text.text = widget.inherited ? '' : _format(widget.value);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final value = double.tryParse(_text.text);
    if (value == null || !value.isFinite) {
      _text.text = widget.inherited ? '' : _format(widget.value);
      return;
    }
    final bounded = value.clamp(widget.min, widget.max).toDouble();
    widget.onChanged(bounded);
    _text.text = _format(bounded);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    focusNode: _focus,
    style: const TextStyle(fontSize: 12),
    keyboardType: const TextInputType.numberWithOptions(
      signed: true,
      decimal: true,
    ),
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.inherited ? 'Default' : null,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelStyle: _StudioType.label.copyWith(
        fontSize: 14,
        color: OrionColors.of(context).muted,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    ),
    onSubmitted: (_) => _commit(),
    onEditingComplete: () {
      _commit();
      _focus.unfocus();
    },
    onTapOutside: (_) {
      if (_focus.hasFocus) {
        _commit();
        _focus.unfocus();
      }
    },
  );
}

class _StudioTextField extends StatefulWidget {
  const _StudioTextField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final String value, label;
  final ValueChanged<String> onChanged;
  @override
  State<_StudioTextField> createState() => _StudioTextFieldState();
}

class _StudioTextFieldState extends State<_StudioTextField> {
  late final TextEditingController _text;
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _StudioTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    onChanged: widget.onChanged,
    style: const TextStyle(fontSize: 12),
    maxLength: 80,
    decoration: InputDecoration(
      labelText: widget.label,
      isDense: true,
      counterText: '',
    ),
  );
}

class _StudioThemeNameDialog extends StatefulWidget {
  const _StudioThemeNameDialog({
    required this.title,
    required this.name,
    required this.unavailableNames,
  });
  final String title, name;
  final Set<String> unavailableNames;
  @override
  State<_StudioThemeNameDialog> createState() => _StudioThemeNameDialogState();
}

class _StudioThemeNameDialogState extends State<_StudioThemeNameDialog> {
  late final TextEditingController _name;
  String? get _error => _name.text.trim().isEmpty
      ? 'Enter a theme name.'
      : widget.unavailableNames.contains(_name.text.trim().toLowerCase())
      ? 'A saved theme already uses this name.'
      : null;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.name.length,
      );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_error == null) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => OrionAlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('studio-theme-name-input'),
      controller: _name,
      autofocus: true,
      maxLength: 60,
      decoration: InputDecoration(
        labelText: 'Theme name',
        errorText: _error,
        counterText: '',
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('studio-theme-name-confirm'),
        onPressed: _error == null ? _submit : null,
        child: const Text('Save'),
      ),
    ],
  );
}

class _StudioImportDialog extends StatefulWidget {
  const _StudioImportDialog();
  @override
  State<_StudioImportDialog> createState() => _StudioImportDialogState();
}

class _StudioImportDialogState extends State<_StudioImportDialog> {
  final _text = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    setState(() => _busy = true);
    try {
      final file = await files.openFile(
        acceptedTypeGroups: [
          const files.XTypeGroup(label: 'Theme JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;
      if (await file.length() > 64 * 1024 * 1024) {
        throw const FormatException('Theme files must be smaller than 64 MB.');
      }
      final source = await file.readAsString();
      SynapseStudioTheme.decode(source);
      if (mounted) Navigator.pop(context, source);
    } on Object catch (failure) {
      if (mounted) setState(() => _error = _readableError(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _import() {
    try {
      SynapseStudioTheme.decode(_text.text);
      Navigator.pop(context, _text.text);
    } on Object catch (failure) {
      setState(() => _error = _readableError(failure));
    }
  }

  @override
  Widget build(BuildContext context) => OrionAlertDialog(
    title: const Text('Import theme'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('studio-import-json'),
          controller: _text,
          minLines: 5,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
          decoration: InputDecoration(
            hintText: 'Paste theme JSON',
            errorText: _error,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _choose,
          icon: const Icon(Icons.folder_open_outlined, size: 17),
          label: const Text('Choose JSON file'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('studio-import-confirm'),
        onPressed: _busy || _text.text.trim().isEmpty ? null : _import,
        child: const Text('Import'),
      ),
    ],
  );
}
