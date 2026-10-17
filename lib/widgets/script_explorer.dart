import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/local_script.dart';
import '../services/monaco_editor_service.dart';
import '../services/desktop_launcher.dart';
import '../services/script_library_service.dart';
import '../state/orion_controller.dart';
import '../theme/orion_density.dart';
import '../theme/orion_surfaces.dart';
import '../theme/orion_theme.dart';
import 'orion_overlay.dart';
import 'orion_popup_menu.dart';
import 'script_code_text.dart';
import 'selected_builder.dart';

/// A view of the dedicated on-disk library, independent of open editor tabs.
class ScriptExplorer extends StatefulWidget {
  const ScriptExplorer({
    super.key,
    required this.controller,
    required this.library,
    required this.onOpenScript,
    required this.onLibrary,
    this.editorService,
  });

  final OrionController controller;
  final ScriptLibraryService library;
  final Future<void> Function(String path) onOpenScript;
  final VoidCallback onLibrary;
  final MonacoEditorService? editorService;

  @override
  State<ScriptExplorer> createState() => _ScriptExplorerState();
}

class _ScriptExplorerState extends State<ScriptExplorer> {
  final _search = TextEditingController();
  final _expanded = <String>{'Special'};
  final _scroll = ScrollController();
  String _query = '';
  String? _operationError, _opening;
  bool _creating = false;
  List<LocalScriptEntry>? _rowEntries;
  List<({LocalScriptEntry entry, int depth})>? _rows;
  String? _rowQuery;
  int _expansionRevision = 0, _rowExpansionRevision = -1;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_invalidateRows);
  }

  @override
  void didUpdateWidget(covariant ScriptExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.library, widget.library)) {
      oldWidget.library.removeListener(_invalidateRows);
      widget.library.addListener(_invalidateRows);
      _invalidateRows();
    }
  }

  void _invalidateRows() {
    // A library may notify after changing an existing list in place. Invalidate
    // on every event as well as checking list identity when the view rebuilds.
    _rowEntries = null;
    _rows = null;
  }

  @override
  void dispose() {
    widget.library.removeListener(_invalidateRows);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String query) =>
      setState(() => _query = query.trim().toLowerCase());

  List<({LocalScriptEntry entry, int depth})> _visibleEntries() {
    final entries = widget.library.entries;
    if (identical(entries, _rowEntries) &&
        _rows != null &&
        _rowQuery == _query &&
        _rowExpansionRevision == _expansionRevision) {
      return _rows!;
    }
    final byParent = <String, List<LocalScriptEntry>>{};
    final included = <String>{};
    for (final entry in entries) {
      final separator = entry.relativePath.lastIndexOf('/');
      final parent = separator < 0
          ? ''
          : entry.relativePath.substring(0, separator);
      byParent.putIfAbsent(parent, () => []).add(entry);
      if (_query.isNotEmpty &&
          (entry.relativePath.toLowerCase().contains(_query) ||
              entry.name.toLowerCase().contains(_query))) {
        var path = entry.relativePath;
        included.add(path);
        while (path.contains('/')) {
          path = path.substring(0, path.lastIndexOf('/'));
          included.add(path);
        }
      }
    }
    final result = <({LocalScriptEntry entry, int depth})>[];
    void visit(String parent, int depth) {
      final children = byParent[parent] ?? <LocalScriptEntry>[];
      children.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      for (final entry in children) {
        if (_query.isNotEmpty && !included.contains(entry.relativePath)) {
          continue;
        }
        result.add((entry: entry, depth: depth));
        if (entry.isDirectory &&
            (_query.isNotEmpty || _expanded.contains(entry.relativePath))) {
          visit(entry.relativePath, depth + 1);
        }
      }
    }

    visit('', 0);
    _rowEntries = entries;
    _rowQuery = _query;
    _rowExpansionRevision = _expansionRevision;
    return _rows = result;
  }

  Future<void> _open(LocalScriptEntry entry) async {
    if (_opening == entry.path) return;
    setState(() {
      _opening = entry.path;
      _operationError = null;
    });
    try {
      await widget.onOpenScript(entry.path);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _operationError = _errorText(error, 'Could not open script.'),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final entry = await showOrionDialog<LocalScriptEntry>(
        context,
        controller: widget.controller,
        editorService: widget.editorService,
        builder: (_) => _CreateScriptDialog(library: widget.library),
      );
      if (entry == null || !mounted) return;
      var path = entry.relativePath;
      setState(() {
        _query = '';
        _search.clear();
        while (path.contains('/')) {
          path = path.substring(0, path.lastIndexOf('/'));
          _expanded.add(path);
        }
        _expansionRevision++;
      });
      await _open(entry);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _fileMenu(BuildContext anchor, LocalScriptEntry entry) async {
    final selected = await showOrionPopupMenu<String>(
      anchor,
      controller: widget.controller,
      editorService: widget.editorService,
      entries: const [OrionMenuEntry(value: 'code', label: 'Code')],
    );
    if (selected != 'code' || !mounted) return;
    final current = widget.library.entries
        .where((file) => file.relativePath == entry.relativePath)
        .firstOrNull;
    if (current == null) return;
    await showOrionDialog<void>(
      context,
      controller: widget.controller,
      editorService: widget.editorService,
      builder: (_) => _CodePalette(
        library: widget.library,
        entry: current,
        reducedMotion: widget.controller.reducedMotion,
      ),
    );
  }

  Future<void> _openFolder() async {
    try {
      await DesktopLauncher.openDirectory(widget.library.directory);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _operationError = _errorText(
            error,
            'Could not open scripts folder.',
          ),
        );
      }
    }
  }

  Future<void> _retry() async {
    setState(() => _operationError = null);
    try {
      await widget.library.refresh();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () =>
              _operationError = _errorText(error, 'Could not refresh scripts.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SelectedBuilder(
    listenable: widget.controller,
    select: () => (
      widget.controller.activeDocument.filePath,
      widget.controller.reducedMotion,
    ),
    builder: (context, _) => AnimatedBuilder(
      animation: widget.library,
      builder: (context, _) {
        final colors = OrionColors.of(context),
            density = OrionDensity.of(context);
        final rows = _visibleEntries();
        final error = _operationError ?? widget.library.error;
        final compact = density.isCompact;
        final iconStyle = IconButton.styleFrom(
          minimumSize: Size.square(density.mix(28, 26)),
          maximumSize: Size.square(density.mix(28, 26)),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
        return Container(
          decoration: BoxDecoration(
            color: colors.chrome(colors.panel, role: 'panel'),
            gradient: orionSurfaceGradient(colors, blend: .16),
          ),
          padding: EdgeInsets.all(density.mix(8, 6)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scripts',
                      style: OrionType.sectionTitle.copyWith(
                        color: colors.ink,
                        fontSize: density.mix(15, 14),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('script-new-file'),
                    tooltip: 'New script file',
                    style: iconStyle,
                    onPressed: _creating ? null : () => unawaited(_create()),
                    icon: const Icon(Icons.add_rounded, size: 17),
                  ),
                ],
              ),
              SizedBox(height: density.mix(6, 4)),
              TextField(
                key: const ValueKey('script-filter'),
                controller: _search,
                onChanged: _filter,
                style: OrionType.body.copyWith(color: colors.ink, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Filter files',
                  hintStyle: OrionType.body.copyWith(
                    color: colors.muted,
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 15),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 27,
                    minHeight: 30,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 8,
                  ),
                  fillColor: colors.chrome(colors.elevated, role: 'elevated'),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: colors.transparentSurfaces
                        ? BorderSide(color: colors.outline(.3), width: .67)
                        : BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: colors.readableAccent),
                  ),
                ),
              ),
              SizedBox(
                height: 4,
                child: widget.library.loading
                    ? const Align(
                        alignment: Alignment.center,
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    : null,
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          widget.library.loading
                              ? 'Loading…'
                              : _query.isEmpty
                              ? 'No scripts yet'
                              : 'No matching files',
                          textAlign: TextAlign.center,
                          style: OrionType.metadata.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      )
                    : Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.zero,
                          itemCount: rows.length,
                          itemBuilder: (_, index) => _entry(
                            rows[index].entry,
                            rows[index].depth,
                            colors,
                            density,
                          ),
                        ),
                      ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: error,
                          child: Text(
                            error,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: OrionType.metadata.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('script-library-retry'),
                        tooltip: 'Retry scripts',
                        onPressed: () => unawaited(_retry()),
                        style: iconStyle,
                        icon: const Icon(Icons.refresh_rounded, size: 15),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message:
                          'Open scripts folder\n${widget.library.directory.path}',
                      constraints: const BoxConstraints(maxWidth: 124),
                      child: TextButton.icon(
                        key: const ValueKey('script-open-folder'),
                        onPressed: () => unawaited(_openFolder()),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size(0, compact ? 28 : 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: OrionType.label.copyWith(
                            fontSize: 11.5,
                            fontFamily: Theme.of(
                              context,
                            ).textTheme.labelLarge?.fontFamily,
                          ),
                        ),
                        icon: const Icon(Icons.folder_open_rounded, size: 15),
                        label: const Text('Folder'),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('script-hub'),
                    tooltip: 'Script hub',
                    style: iconStyle,
                    onPressed: widget.onLibrary,
                    icon: const Icon(Icons.widgets_outlined, size: 16),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _entry(
    LocalScriptEntry entry,
    int depth,
    OrionColors colors,
    OrionDensity density,
  ) {
    final expanded =
        _query.isNotEmpty || _expanded.contains(entry.relativePath);
    final active =
        !entry.isDirectory &&
        widget.controller.activeDocument.filePath == entry.path;
    final code = entry.relativePath == 'Special' && entry.isDirectory
        ? ScriptColorCode.special
        : entry.code;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(8),
      topRight: const Radius.circular(3),
      bottomLeft: const Radius.circular(8),
      bottomRight: const Radius.circular(8),
    );
    return Padding(
      key: ValueKey(
        '${entry.isDirectory ? 'script-folder' : 'script-file'}:${entry.relativePath}',
      ),
      padding: const EdgeInsets.only(bottom: 1),
      child: LayoutBuilder(
        builder: (context, constraints) => Tooltip(
          message: entry.path,
          constraints: BoxConstraints(
            maxWidth: math.max(60, constraints.maxWidth - 24),
          ),
          child: Material(
            color: active
                ? colors.stateFill(colors.transparentSurfaces ? .05 : .1)
                : Colors.transparent,
            borderRadius: radius,
            child: Builder(
              builder: (anchor) => InkWell(
                borderRadius: radius,
                onTap: entry.isDirectory
                    ? () => setState(() {
                        if (!_expanded.add(entry.relativePath)) {
                          _expanded.remove(entry.relativePath);
                        }
                        _expansionRevision++;
                      })
                    : () => unawaited(_open(entry)),
                onSecondaryTap: entry.isDirectory
                    ? null
                    : () => unawaited(_fileMenu(anchor, entry)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    4 + math.min(depth * 10, 28).toDouble(),
                    density.mix(8, 6),
                    4,
                    density.mix(8, 6),
                  ),
                  child: Row(
                    children: [
                      if (entry.isDirectory) ...[
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_right_rounded,
                          size: 12,
                          color: colors.muted,
                        ),
                        const SizedBox(width: 1),
                      ],
                      Icon(
                        entry.isDirectory
                            ? (expanded
                                  ? Icons.folder_open_rounded
                                  : Icons.folder_rounded)
                            : Icons.code_rounded,
                        size: entry.isDirectory ? 14 : 12,
                        color: active ? colors.readableAccent : colors.muted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: ScriptCodeText(
                          text: entry.name,
                          code: code,
                          reducedMotion: widget.controller.reducedMotion,
                          style: OrionType.label.copyWith(
                            fontSize: density.mix(12, 11.5),
                            fontWeight: entry.isDirectory
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (_opening == entry.path)
                        const Padding(
                          padding: EdgeInsets.only(left: 3),
                          child: SizedBox.square(
                            dimension: 9,
                            child: CircularProgressIndicator(strokeWidth: 1.2),
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
}

String _errorText(Object error, String fallback) {
  if (error is FileSystemException && error.message.isNotEmpty) {
    return error.message;
  }
  if (error is FormatException) return error.message;
  if (error is ArgumentError && error.message != null) {
    return error.message.toString();
  }
  return fallback;
}

class _CreateScriptDialog extends StatefulWidget {
  const _CreateScriptDialog({required this.library});
  final ScriptLibraryService library;
  @override
  State<_CreateScriptDialog> createState() => _CreateScriptDialogState();
}

class _CreateScriptDialogState extends State<_CreateScriptDialog> {
  final _name = TextEditingController(text: 'untitled.lua')
    ..selection = const TextSelection(baseOffset: 0, extentOffset: 8);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entry = await widget.library.createScript(_name.text.trim());
      if (mounted) Navigator.pop(context, entry);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errorText(error, 'Could not create script.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => OrionAlertDialog(
    title: const Text('New script file'),
    content: TextField(
      key: const ValueKey('script-create-name'),
      controller: _name,
      autofocus: true,
      enabled: !_busy,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'File name',
        hintText: 'untitled.lua',
        errorText: _error,
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => unawaited(_create()),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('script-create-confirm'),
        onPressed: _busy || _name.text.trim().isEmpty
            ? null
            : () => unawaited(_create()),
        child: _busy
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : const Text('Create'),
      ),
    ],
  );
}

class _CodePalette extends StatefulWidget {
  const _CodePalette({
    required this.library,
    required this.entry,
    required this.reducedMotion,
  });
  final ScriptLibraryService library;
  final LocalScriptEntry entry;
  final bool reducedMotion;
  @override
  State<_CodePalette> createState() => _CodePaletteState();
}

class _CodePaletteState extends State<_CodePalette> {
  ScriptColorCode? _busy;
  String? _error;
  Future<void> _select(ScriptColorCode code) async {
    if (_busy != null) return;
    setState(() {
      _busy = code;
      _error = null;
    });
    try {
      await widget.library.setCode(widget.entry.relativePath, code);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = _errorText(error, 'Could not change script code.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(16),
    child: OrionOverlaySurface(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(22),
        topRight: Radius.circular(6),
        bottomLeft: Radius.circular(22),
        bottomRight: Radius.circular(22),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 270,
          maxHeight: MediaQuery.sizeOf(context).height - 32,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Code',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close code palette',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy == null
                        ? () => Navigator.pop(context)
                        : null,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 5),
                child: Text(
                  widget.entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final code in ScriptColorCode.values)
                        TextButton(
                          key: ValueKey('script-code:${code.name}'),
                          onPressed: _busy == null
                              ? () => unawaited(_select(code))
                              : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            minimumSize: const Size(0, 38),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: Row(
                            children: [
                              ScriptCodeSwatch(code: code),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ScriptCodeText(
                                  text: scriptCodeLabel(code),
                                  code: code,
                                  reducedMotion: widget.reducedMotion,
                                  style: OrionType.label,
                                ),
                              ),
                              if (_busy == code)
                                const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                )
                              else if (widget.entry.code == code)
                                Icon(
                                  Icons.check_rounded,
                                  size: 17,
                                  color: OrionColors.of(context).readableAccent,
                                )
                              else
                                const SizedBox.square(dimension: 17),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
