import 'dart:async';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';

import '../models/interface_preset.dart';
import '../models/interface_preferences.dart';
import '../models/orion_models.dart';
import '../models/orion_theme_preferences.dart';
import '../models/remote_script.dart';
import '../state/orion_controller.dart';

typedef CompanionCommandSender =
    Future<Map<String, Object?>> Function(
      String operation,
      Map<String, Object?> payload,
      int sequence,
    );

/// A companion never owns recovery files or a second copy of workspace state.
/// Edits appear immediately, then ordered RPCs commit them on the primary
/// controller. An older primary snapshot is rebased over unacknowledged edits.
class CompanionController extends OrionController {
  CompanionController({
    required Map<String, Object?> initialState,
    required CompanionCommandSender sendCommand,
    this.documentId,
  }) : _sendCommand = sendCommand,
       super(persistChanges: false) {
    super.applyWindowState(initialState);
  }

  final CompanionCommandSender _sendCommand;
  final String? documentId;
  final _pending = <_CompanionCommand>[];
  int _sequence = 0, _acknowledged = 0, _revision = -1;
  bool _applying = false, _disposed = false;
  Future<void>? _draining;
  Object? _commandError;

  int get pendingCommandCount => _pending.length;
  Object? get commandError => _commandError;

  @override
  String get activeDocumentId {
    final fixed = documentId;
    return fixed != null && documents.any((d) => d.id == fixed)
        ? fixed
        : super.activeDocumentId;
  }

  @override
  EditorDocument get activeDocument =>
      documents.firstWhere((document) => document.id == activeDocumentId);

  /// Ack numbers belong to this child engine's ordered command stream.
  void acceptEnvelope(Map<String, Object?> envelope) {
    if (_disposed) return;
    final ack = envelope['ack'];
    final revision = envelope['revision'];
    final state = envelope['state'];
    if (ack is! int || state is! Map) {
      throw const FormatException('Invalid companion state envelope.');
    }
    // A reply may arrive after a newer state broadcast from the same owner.
    if (ack > _acknowledged) _acknowledged = ack;
    _pending.removeWhere((command) => command.sequence <= ack);
    if ((revision is int && revision < _revision) ||
        (revision == null && ack < _acknowledged)) {
      return;
    }
    if (revision is int) _revision = revision;
    _applying = true;
    try {
      runWindowUpdate(() {
        super.applyWindowState(Map<String, Object?>.from(state));
        for (final command in _pending) {
          command.replay?.call();
        }
      });
    } finally {
      _applying = false;
    }
  }

  Future<Object?> _enqueue(
    String operation,
    Map<String, Object?> payload, {
    VoidCallback? replay,
  }) {
    if (_disposed) return Future<Object?>.value();
    final command = _CompanionCommand(++_sequence, operation, payload, replay);
    _pending.add(command);
    if (replay != null) {
      _applying = true;
      try {
        runWindowUpdate(replay);
      } finally {
        _applying = false;
      }
    }
    // Most mutations are void API calls. Observe transport failures here while
    // retaining the pending edit for flushCommands() to retry explicitly.
    unawaited(command.result.future.then<void>((_) {}, onError: (Object _) {}));
    unawaited(_drain().then<void>((_) {}, onError: (Object _) {}));
    return command.result.future;
  }

  Future<void> _drain() {
    if (_draining != null) return _draining!;
    if (_disposed || _pending.isEmpty) return Future<void>.value();
    final done = Completer<void>();
    _draining = done.future;
    scheduleMicrotask(() async {
      _CompanionCommand? current;
      try {
        while (!_disposed && _pending.isNotEmpty) {
          current = _pending.first;
          final response = await _sendCommand(
            current.operation,
            current.payload,
            current.sequence,
          );
          if (_disposed) break;
          final envelope = response['envelope'];
          if (envelope is! Map) {
            throw const FormatException('Missing companion command reply.');
          }
          acceptEnvelope(Map<String, Object?>.from(envelope));
          if (_acknowledged < current.sequence) {
            throw StateError('The primary did not acknowledge the command.');
          }
          if (!current.result.isCompleted) {
            current.result.complete(response['result']);
          }
        }
        _commandError = null;
        done.complete();
      } catch (error, stack) {
        _commandError = error;
        if (current != null && !current.result.isCompleted) {
          current.result.completeError(error, stack);
        }
        done.completeError(error, stack);
      } finally {
        _draining = null;
      }
    });
    return done.future;
  }

  Future<void> flushCommands() async {
    while (!_disposed && (_draining != null || _pending.isNotEmpty)) {
      await _drain();
    }
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> flushPersistence() async {
    await flushCommands();
    // Acknowledged preferences may still be waiting in the owner's debounce.
    // The reply includes its current disk-error state, so Apply cannot claim
    // success before the authoritative recovery file has been written.
    await _enqueue('flushPersistence', const {});
  }

  @override
  void applyThemeStudioState(
    InterfacePreset preset, {
    required Object? document,
    Object? draft,
    OrionThemePreferences? orionTheme,
  }) {
    if (_applying) {
      super.applyThemeStudioState(
        preset,
        document: document,
        draft: draft,
        orionTheme: orionTheme,
      );
      return;
    }
    final copiedDocument = document == null
        ? null
        : copyInterfacePreference(document);
    final copiedDraft = draft == null ? null : copyInterfacePreference(draft);
    unawaited(
      _enqueue(
        'applyThemeStudioState',
        {
          'preset': preset.name,
          'document': copiedDocument,
          'draft': copiedDraft,
          if (orionTheme != null) 'orionTheme': orionTheme.toJson(),
        },
        replay: () => super.applyThemeStudioState(
          preset,
          document: copiedDocument,
          draft: copiedDraft,
          orionTheme: orionTheme,
        ),
      ),
    );
  }

  @override
  void setInterfacePreference(
    InterfacePreset preset,
    String key,
    Object? value,
  ) {
    if (_applying) {
      super.setInterfacePreference(preset, key, value);
      return;
    }
    final copied = value == null ? null : copyInterfacePreference(value);
    unawaited(
      _enqueue('setInterfacePreference', {
        'preset': preset.name,
        'key': key,
        'value': copied,
      }, replay: () => super.setInterfacePreference(preset, key, copied)),
    );
  }

  @override
  void resetInterfacePreferences(InterfacePreset preset) {
    unawaited(
      _enqueue('resetInterfacePreferences', {
        'preset': preset.name,
      }, replay: () => super.resetInterfacePreferences(preset)),
    );
  }

  void _applySynapsePatch(Map<String, Object?> patch) {
    super.applyWindowState({
      ...super.exportWindowState(),
      'synapsePreferences': {
        ...synapsePreferences.toJson(),
        ...patch,
        if (patch['themeColors'] is Map)
          'themeColors': {
            ...synapsePreferences.themeColors,
            ...Map<String, int>.from(patch['themeColors'] as Map),
          },
      },
    });
  }

  @override
  void updateSynapsePreferences({
    bool? alwaysOnTop,
    bool? resizable,
    bool? showScriptList,
    bool? minimap,
    bool? errorLogging,
    bool? compactButtons,
    bool? compactTabs,
    bool? consoleTimestamp,
    String? defaultTabContent,
    String? themePreset,
    String? uiFontFamily,
    double? consoleHeight,
    double? consoleFontSize,
    double? cornerRadius,
    Color? themeBackground,
    Color? themeAccent,
    Map<String, int>? themeColors,
    List<String>? gistUrls,
    List<String>? bookmarkedDocumentIds,
    Map<String, String>? gistDocumentUrls,
  }) {
    final patch = <String, Object?>{
      'alwaysOnTop': ?alwaysOnTop,
      'resizable': ?resizable,
      'showScriptList': ?showScriptList,
      'minimap': ?minimap,
      'errorLogging': ?errorLogging,
      'compactButtons': ?compactButtons,
      'compactTabs': ?compactTabs,
      'consoleTimestamp': ?consoleTimestamp,
      'defaultTabContent': ?defaultTabContent,
      'themePreset': ?themePreset,
      'uiFontFamily': ?uiFontFamily,
      'consoleHeight': ?consoleHeight,
      'consoleFontSize': ?consoleFontSize,
      'cornerRadius': ?cornerRadius,
      if (themeColors != null || themeBackground != null || themeAccent != null)
        'themeColors': {
          ...?themeColors,
          if (themeBackground != null)
            'shell.pageBg': themeBackground.toARGB32(),
          if (themeBackground != null)
            'shell.contentBg': themeBackground.toARGB32(),
          if (themeAccent != null) 'accent.primary': themeAccent.toARGB32(),
        },
      if (gistUrls != null) 'gistUrls': List<String>.of(gistUrls),
      if (bookmarkedDocumentIds != null)
        'bookmarkedDocumentIds': List<String>.of(bookmarkedDocumentIds),
      if (gistDocumentUrls != null)
        'gistDocumentUrls': Map<String, String>.of(gistDocumentUrls),
    };
    if (patch.isEmpty) return;
    unawaited(
      _enqueue('updateSynapsePreferences', {
        'patch': patch,
      }, replay: () => _applySynapsePatch(patch)),
    );
  }

  @override
  void resetSynapsePreferences() => unawaited(
    _enqueue(
      'resetSynapsePreferences',
      {},
      replay: super.resetSynapsePreferences,
    ),
  );

  @override
  void resetSynapseTheme({
    String preset = 'framework',
    Map<String, int> colors = const {},
  }) {
    unawaited(
      _enqueue('resetSynapseTheme', {
        'preset': preset,
        'colors': Map<String, int>.of(colors),
      }, replay: () => super.resetSynapseTheme(preset: preset, colors: colors)),
    );
  }

  @override
  void updateDocumentContent(String id, String content) {
    if (!documents.any((d) => d.id == id) ||
        documents.firstWhere((d) => d.id == id).content == content) {
      return;
    }
    unawaited(
      _enqueue('setDocumentContent', {
        'id': id,
        'content': content,
      }, replay: () => super.updateDocumentContent(id, content)),
    );
  }

  @override
  void selectDocument(String id) {
    if (super.activeDocumentId == id || !documents.any((d) => d.id == id)) {
      return;
    }
    unawaited(
      _enqueue('selectDocument', {
        'id': id,
      }, replay: () => super.selectDocument(id)),
    );
  }

  @override
  EditorDocument newDocument({String? name, String content = ''}) {
    final document = EditorDocument(
      id: 'companion-${DateTime.now().microsecondsSinceEpoch}-${_sequence + 1}',
      name: name ?? _nextName(),
      content: content,
      savedContent: content,
    );
    unawaited(
      _enqueue(
        'insertDocument',
        {'document': document.toJson()},
        replay: () {
          super.insertSharedDocument(document);
          super.selectDocument(document.id);
        },
      ),
    );
    return document;
  }

  String _nextName() {
    var index = 1;
    var name = 'untitled.lua';
    while (documents.any((d) => d.name == name)) {
      name = 'untitled-${++index}.lua';
    }
    return name;
  }

  @override
  void renameDocument(String id, String name) {
    unawaited(
      _enqueue('renameDocument', {
        'id': id,
        'name': name,
      }, replay: () => super.renameDocument(id, name)),
    );
  }

  @override
  void closeDocument(String id) {
    if (!documents.any((document) => document.id == id)) return;
    final replacement = documents.length == 1
        ? EditorDocument(
            id: 'companion-${DateTime.now().microsecondsSinceEpoch}-${_sequence + 1}',
            name: 'untitled.lua',
            content: '',
            savedContent: '',
          )
        : null;
    unawaited(
      _enqueue(
        'closeDocument',
        {
          'id': id,
          if (replacement != null) 'replacement': replacement.toJson(),
        },
        replay: () {
          if (replacement != null) super.insertSharedDocument(replacement);
          super.closeDocument(id);
        },
      ),
    );
  }

  @override
  void reorderDocuments(List<String> ids) {
    if (ids.length != documents.length ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !documents.any((d) => d.id == id))) {
      throw ArgumentError.value(
        ids,
        'ids',
        'Expected every open tab exactly once.',
      );
    }
    final order = List<String>.of(ids);
    unawaited(
      _enqueue(
        'reorderDocuments',
        {'ids': order},
        replay: () {
          final existing = super.documents.map((d) => d.id).toSet();
          super.reorderDocuments([
            ...order.where(existing.contains),
            ...existing.where((id) => !order.contains(id)),
          ]);
        },
      ),
    );
  }

  @override
  Future<EditorDocument?> openFile() async {
    final file = await files.openFile(
      acceptedTypeGroups: const [
        files.XTypeGroup(
          label: 'Luau, Lua and text files',
          extensions: ['luau', 'lua', 'txt'],
        ),
      ],
    );
    if (file == null || _disposed) return null;
    return importDocumentFromPath(file.path, replaceId: documentId);
  }

  @override
  Future<EditorDocument?> openFileAtPath(String path) =>
      importDocumentFromPath(path, replaceId: documentId);

  @override
  Future<EditorDocument?> importDocumentFromPath(
    String path, {
    String? replaceId,
  }) async {
    final result = await _enqueue('importDocument', {
      'path': path,
      'replaceId': ?replaceId,
    });
    return result is Map
        ? EditorDocument.fromJson(Map<String, dynamic>.from(result))
        : null;
  }

  @override
  Future<bool> saveDocument([String? id]) async {
    final target = id ?? activeDocumentId;
    final document = documents.where((d) => d.id == target).firstOrNull;
    if (document == null) return false;
    return document.filePath == null
        ? saveAs(target)
        : saveDocumentToPath(target, document.filePath!);
  }

  @override
  Future<bool> saveAs([String? id]) async {
    final target = id ?? activeDocumentId;
    final document = documents.where((d) => d.id == target).firstOrNull;
    if (document == null) return false;
    final location = await files.getSaveLocation(
      suggestedName: document.name,
      initialDirectory: scriptsDirectory.path,
      acceptedTypeGroups: const [
        files.XTypeGroup(
          label: 'Luau, Lua and text files',
          extensions: ['luau', 'lua', 'txt'],
        ),
      ],
    );
    if (location == null || _disposed) return false;
    return saveDocumentToPath(target, location.path);
  }

  @override
  Future<bool> saveDocumentToPath(String id, String path) async =>
      await _enqueue('saveDocument', {'id': id, 'path': path}) == true;

  @override
  void execute({String? source, String? name}) {
    unawaited(
      _enqueue('execute', {
        'source': source ?? activeDocument.content,
        'name': name ?? activeDocument.name,
      }),
    );
  }

  @override
  void attach() => unawaited(_enqueue('attach', {}));

  @override
  Future<bool> initializeBridge({int port = 31337}) async =>
      await _enqueue('initializeBridge', {}) == true;

  @override
  Future<void> closeBridge() async {}

  @override
  void setBridgeTargetAll(bool value) => unawaited(
    _enqueue('setBridgeTargetAll', {
      'value': value,
    }, replay: () => super.setBridgeTargetAll(value)),
  );

  @override
  void setBridgeClientSelected(String identifier, bool value) {
    final session = bridgeClients
        .where((c) => c.identifier == identifier)
        .firstOrNull;
    if (session == null) return;
    unawaited(
      _enqueue(
        'setBridgeClientSelected',
        {
          'identifier': identifier,
          'sessionId': session.sessionId,
          'value': value,
        },
        replay: () {
          if (bridgeClients.any(
            (c) =>
                c.identifier == identifier && c.sessionId == session.sessionId,
          )) {
            super.setBridgeClientSelected(identifier, value);
          }
        },
      ),
    );
  }

  @override
  void disconnectBridgeClient(String identifier) {
    final session = bridgeClients
        .where((c) => c.identifier == identifier)
        .firstOrNull;
    if (session == null) return;
    unawaited(
      _enqueue('disconnectBridgeClient', {
        'identifier': identifier,
        'sessionId': session.sessionId,
      }),
    );
  }

  @override
  void disconnectAllBridgeClients() =>
      unawaited(_enqueue('disconnectAllBridgeClients', {}));

  @override
  void clearActivities() =>
      unawaited(_enqueue('clearActivities', {}, replay: super.clearActivities));

  void _preference(String key, Object? value, VoidCallback replay) {
    unawaited(
      _enqueue('setPreference', {'key': key, 'value': value}, replay: replay),
    );
  }

  @override
  void setThemeMode(ThemeMode mode) =>
      _preference('themeMode', mode.name, () => super.setThemeMode(mode));
  @override
  void setAccent(OrionAccent accent) =>
      _preference('accent', accent.name, () => super.setAccent(accent));
  @override
  void setReducedMotion(bool value) =>
      _preference('reducedMotion', value, () => super.setReducedMotion(value));
  @override
  void setUiScale(double value) =>
      _preference('uiScale', value, () => super.setUiScale(value));
  @override
  void setEditorFontSize(double value) => _preference(
    'editorFontSize',
    value,
    () => super.setEditorFontSize(value),
  );
  @override
  void setWordWrap(bool value) =>
      _preference('wordWrap', value, () => super.setWordWrap(value));
  @override
  void setShowLineNumbers(bool value) => _preference(
    'showLineNumbers',
    value,
    () => super.setShowLineNumbers(value),
  );
  @override
  void setAutosave(bool value) =>
      _preference('autosave', value, () => super.setAutosave(value));

  @override
  void setRemoteSearchQuery(String query) {
    unawaited(
      _enqueue('setRemoteSearchQuery', {
        'query': query,
      }, replay: () => super.setSearchQuery(query)),
    );
  }

  @override
  void setScriptProvider(ScriptProvider? provider) {
    // Applying the primary snapshot updates the selected provider/results;
    // the child must not start its own network search or debounce timer.
    unawaited(_enqueue('setScriptProvider', {'provider': provider?.name}));
  }

  @override
  Future<void> searchRemoteScripts([String? query]) async {
    await _enqueue('searchRemoteScripts', {'query': ?query});
  }

  @override
  Future<void> loadMoreRemoteScripts() async {
    await _enqueue('loadMoreRemoteScripts', {});
  }

  @override
  Future<void> retryRemoteSource(ScriptProvider provider) async {
    await _enqueue('retryRemoteSource', {'provider': provider.name});
  }

  @override
  void toggleRemoteFavorite(RemoteScript script) {
    final favorite = !isRemoteFavorite(script.key);
    unawaited(
      _enqueue(
        'toggleRemoteFavorite',
        {'script': script.toJson()},
        replay: () {
          if (isRemoteFavorite(script.key) != favorite) {
            super.toggleRemoteFavorite(script);
          }
        },
      ),
    );
  }

  @override
  Future<String> loadRemoteScript(RemoteScript script) async {
    final result = await _enqueue('loadRemoteScript', {
      'script': script.toJson(),
    });
    if (result is! String) {
      throw const FormatException('The primary returned no script source.');
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final command in _pending) {
      if (!command.result.isCompleted) command.result.complete();
    }
    _pending.clear();
    super.dispose();
  }
}

class _CompanionCommand {
  _CompanionCommand(this.sequence, this.operation, this.payload, this.replay);
  final int sequence;
  final String operation;
  final Map<String, Object?> payload;
  final VoidCallback? replay;
  final result = Completer<Object?>();
}
