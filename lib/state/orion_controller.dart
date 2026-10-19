import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/orion_models.dart';
import '../models/bridge_models.dart';
import '../services/orion_bridge_service.dart';
import '../models/interface_preset.dart';
import '../models/companion_window.dart';
import '../models/interface_preferences.dart';
import '../models/remote_script.dart';
import '../models/orion_theme_preferences.dart';
import '../services/script_hub_service.dart';
import '../services/script_library_service.dart';
import '../services/desktop_launcher.dart';
import '../services/workspace_paths.dart';
import '../services/file_paths.dart';
import '../synapse_v3/synapse_v3_preferences.dart';

/// Shared workspace state and the application-owned, local Orion Bridge.
class OrionController extends ChangeNotifier {
  OrionController({
    Directory? storageDirectory,
    ScriptHubService? scriptHubService,
    OrionBridgeService? bridgeService,
    bool? useMacSploit,
    String nativeExecutorPreference = 'auto',
    int? nativePortPreference,
    bool persistChanges = true,
  }) : _storageDirectory = storageDirectory,
       _persistChanges = persistChanges,
       _scriptHub = scriptHubService ?? ScriptHubService(),
       _bridge =
           bridgeService ??
           OrionBridgeService(
             // The Rojo macOS fork talks directly to MacSploit's local TCP
             // API; keep the HTTP Bridge backend on other platforms.
             macSploitMode: useMacSploit ?? Platform.isMacOS,
             nativeExecutorPreference: nativeExecutorPreference,
             nativePortPreference: nativePortPreference,
           ) {
    _documents.add(
      const EditorDocument(
        id: 'welcome-constellation',
        name: 'constellation.lua',
        content: constellationSource,
        savedContent: constellationSource,
      ),
    );
    _activeDocumentId = _documents.first.id;
    _addActivity(
      'Workspace ready',
      'Local scripts and preferences are loaded.',
      ActivityKind.workspace,
      ActivitySeverity.success,
      persist: false,
    );
  }

  final ScriptHubService _scriptHub;
  final OrionBridgeService _bridge;
  StreamSubscription<BridgeLogEntry>? _bridgeLogSubscription;
  bool _bridgeInitialized = false;
  final List<BridgeClient> _bridgeClients = [];
  final Set<String> _selectedBridgeClients = {};
  bool _bridgeTargetAll = true;
  bool _bridgeListening = false;
  String? _bridgeError;
  int _bridgePort = 31337;
  bool get usesNativeExecutor => _bridge.usesNativeExecutor;
  bool get usesMacSploit =>
      _bridge.usesNativeExecutor &&
      (_bridge.nativeExecutorPreference != 'opiumware');
  String get nativeExecutorPreference => _bridge.nativeExecutorPreference;
  String? get detectedNativeExecutor => _bridge.nativeExecutorName;
  int? get nativePortPreference => _bridge.nativePortPreference;
  List<int> get availableNativePorts => _bridge.availableNativePorts;
  void setNativeExecutorPreference(String value) {
    _bridge.setNativeExecutorPreference(value);
    _changed(persist: false);
  }

  void setNativePortPreference(int? value) {
    _bridge.setNativePortPreference(value);
    _changed(persist: false);
  }

  List<BridgeClient> get bridgeClients => List.unmodifiable(_bridgeClients);
  bool get bridgeListening => _bridgeListening;
  bool get bridgeConnected => _bridgeClients.isNotEmpty;
  String? get bridgeError => _bridgeError;
  int get bridgePort => _bridgePort;
  Set<String> get selectedBridgeClients =>
      Set.unmodifiable(_selectedBridgeClients);
  bool get bridgeTargetAll => _bridgeTargetAll;
  int get bridgeTargetCount => _bridgeTargetAll
      ? _bridgeClients.length
      : _bridgeClients
            .where((c) => _selectedBridgeClients.contains(c.identifier))
            .length;
  Stream<BridgeClient> get bridgeClientConnected => _bridge.clientConnected;

  /// Only the primary engine starts the server. Companion windows mirror it.
  Future<bool> initializeBridge({int port = 31337}) async {
    if (_disposed) return false;
    if (!_bridgeInitialized) {
      _bridgeInitialized = true;
      _bridge.addListener(_bridgeChanged);
      _bridgeLogSubscription = _bridge.logReceived.listen(_bridgeLogReceived);
    }
    final started = await _bridge.start(port: port);
    if (!_disposed) _bridgeChanged();
    return started;
  }

  FutureOr<void> Function()? bridgeShutdownHook;
  Future<void> closeBridge() async {
    final shutdown = bridgeShutdownHook;
    bridgeShutdownHook = null;
    await shutdown?.call();
    await _bridge.close();
  }

  void _bridgeChanged() {
    if (_disposed) return;
    final previous = {for (final c in _bridgeClients) c.identifier: c};
    _bridgeClients
      ..clear()
      ..addAll(_bridge.clients);
    // A newly allocated UserN must never inherit a departed player's selection.
    _selectedBridgeClients.removeWhere(
      (id) => !_bridgeClients.any(
        (c) => c.identifier == id && previous[id]?.sessionId == c.sessionId,
      ),
    );
    _bridgeListening = _bridge.listening;
    _bridgeError = _bridge.error;
    _bridgePort = _bridge.port;
    _changed(persist: false);
  }

  void _bridgeLogReceived(BridgeLogEntry entry) {
    if (_disposed) return;
    final severity = switch (entry.level.toLowerCase()) {
      'error' => ActivitySeverity.error,
      'warn' || 'warning' => ActivitySeverity.warning,
      'success' => ActivitySeverity.success,
      _ => ActivitySeverity.info,
    };
    final client = _bridgeClients
        .where((c) => c.identifier == entry.identifier)
        .firstOrNull;
    final label = client == null
        ? entry.identifier ?? ''
        : '${client.username} · ${client.identifier}';
    _addActivity(
      label.isEmpty ? 'Orion Bridge' : label,
      entry.message,
      ActivityKind.execution,
      severity,
    );
    _changed(persist: false);
  }

  void setBridgeTargetAll(bool value) {
    if (_bridgeTargetAll == value) return;
    _bridgeTargetAll = value;
    _changed(persist: false);
  }

  void setBridgeClientSelected(String identifier, bool value) {
    if (!_bridgeClients.any((c) => c.identifier == identifier)) return;
    if (_bridgeTargetAll) {
      _selectedBridgeClients.addAll(_bridgeClients.map((c) => c.identifier));
    }
    _bridgeTargetAll = false;
    if (value) {
      _selectedBridgeClients.add(identifier);
    } else {
      _selectedBridgeClients.remove(identifier);
    }
    _changed(persist: false);
  }

  void disconnectBridgeClient(String identifier) =>
      _bridge.disconnectClient(identifier);
  void disconnectAllBridgeClients() => _bridge.disconnectAll();

  Future<String> loadBridgeScript() {
    if (usesMacSploit) {
      throw UnsupportedError(
        'Orion Bridge Lua is only used on Windows and Linux.',
      );
    }
    return rootBundle.loadString('assets/bridge/Orion Bridge.lua');
  }

  String get bridgeLoader => usesMacSploit
      ? 'MacSploit API · localhost ports 5553–5563'
      : 'loadstring(game:HttpGet("http://127.0.0.1:$_bridgePort/bridge.lua"))()';
  Future<bool> saveBridgeScript({bool rethrowErrors = false}) async {
    try {
      final source = await loadBridgeScript();
      final location = await getSaveLocation(
        suggestedName: 'Orion Bridge.lua',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Lua script', extensions: ['lua']),
        ],
      );
      if (location == null || _disposed) return false;
      await File(location.path).writeAsString(source, flush: true);
      return true;
    } on Object catch (error) {
      // The first-run guide presents its own inline feedback. Cancellation
      // still returns false, while a failed write must not look like a cancel.
      if (rethrowErrors) rethrow;
      if (!_disposed) _fileError('Could not save Orion Bridge.lua', error);
      return false;
    }
  }

  final bool _persistChanges;
  CompanionWindowHost? companionWindows;
  final Set<String> _detachedDocumentIds = {};
  int _windowUpdateDepth = 0;
  bool _windowUpdatePending = false;
  Set<String> get detachedDocumentIds => Set.unmodifiable(_detachedDocumentIds);

  void runWindowUpdate(void Function() update) {
    _windowUpdateDepth++;
    try {
      update();
    } finally {
      _windowUpdateDepth--;
      if (_windowUpdateDepth == 0 && _windowUpdatePending) {
        _windowUpdatePending = false;
        _notify();
      }
    }
  }

  void insertSharedDocument(EditorDocument document, {bool select = true}) {
    if (_documents.any((d) => d.id == document.id)) return;
    _documents.add(document);
    if (select) _activeDocumentId = document.id;
    _changed();
  }

  void setDocumentDetached(String id, bool detached) {
    if (!_documents.any((document) => document.id == id)) return;
    final changed = detached
        ? _detachedDocumentIds.add(id)
        : _detachedDocumentIds.remove(id);
    if (changed) _changed(persist: false);
  }

  void reorderDocuments(List<String> ids) {
    if (ids.length != _documents.length ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !_documents.any((document) => document.id == id))) {
      throw ArgumentError.value(
        ids,
        'ids',
        'Expected every open tab exactly once.',
      );
    }
    final byId = {for (final document in _documents) document.id: document};
    _documents
      ..clear()
      ..addAll(ids.map((id) => byId[id]!));
    _changed();
  }

  InterfacePreset _selectedInterface = InterfacePreset.orion;
  ScriptProvider? _selectedProvider;
  final List<RemoteScript> _remoteScripts = [];
  final Map<String, RemoteScript> _remoteFavorites = {};
  final Map<ScriptProvider, String> _providerErrors = {};
  final Map<ScriptProvider, int> _providerPages = {};
  final Set<ScriptProvider> _remoteHasMoreProviders = {};
  final Set<ScriptProvider> _remoteBusyProviders = {};
  final Map<String, Future<String>> _remoteCodeCache = {};
  bool _remoteLoading = false;
  bool _remoteLoadingMore = false;
  String _remoteQuery = '';
  int _remoteGeneration = 0;
  Timer? _remoteSearchDebounce;
  Directory? _storageDirectory;
  Directory? _ownerWorkspaceDirectory;
  ScriptLibraryService? _scriptLibrary;
  final List<EditorDocument> _documents = [];
  final List<ActivityEntry> _activities = [];
  final Set<String> _favoriteIds = {'orbit-canvas', 'easing-curves'};
  String _activeDocumentId = '';
  String _searchQuery = '';
  String _selectedCollection = 'All scripts';
  ThemeMode _themeMode = ThemeMode.dark;
  OrionAccent _accent = OrionAccent.blue;
  OrionThemePreferences _orionTheme = OrionThemePreferences.defaults;
  final List<SavedOrionTheme> _savedOrionThemes = [];
  Uint8List? _customLogoBytes;
  String? _customLogoBase64;
  bool _reducedMotion = false;
  double _editorFontSize = 14;
  double _uiScale = 1.0;
  SynapsePreferences _synapsePreferences = const SynapsePreferences();
  final Map<InterfacePreset, Map<String, Object?>> _interfacePreferences = {};
  bool _wordWrap = false;
  bool _showLineNumbers = true;
  bool _autosave = true;
  bool _introCompleted = false;
  bool _initialized = false;
  bool _disposed = false;
  int _idCounter = 0;
  Timer? _saveDebounce;
  Future<void> _writeQueue = Future<void>.value();
  String? _persistenceError;

  static const _collections = <String>[
    'All scripts',
    'Favorites',
    'Templates',
    'Interface',
    'Utilities',
  ];

  List<EditorDocument> get documents => List.unmodifiable(_documents);
  ScriptLibraryService? get scriptLibrary => _scriptLibrary;
  Directory get workspaceDirectory =>
      _storageDirectory ??
      _ownerWorkspaceDirectory ??
      WorkspacePaths.unresolvedDirectory;
  Directory get scriptsDirectory =>
      _scriptLibrary?.directory ??
      Directory('${workspaceDirectory.path}/scripts');
  Directory get autoexecuteDirectory =>
      Directory('${workspaceDirectory.path}/autoexec');
  List<String> get collections => _collections;
  String get activeDocumentId => _activeDocumentId;
  EditorDocument get activeDocument =>
      _documents.firstWhere((document) => document.id == _activeDocumentId);
  List<LibraryItem> get libraryItems => sampleLibraryItems;
  List<ActivityEntry> get activities => List.unmodifiable(_activities);
  String? get latestExecutionId {
    for (final entry in _activities) {
      if (entry.kind == ActivityKind.execution) return entry.id;
    }
    return null;
  }

  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);
  String get searchQuery => _searchQuery;
  String get selectedCollection => _selectedCollection;
  ThemeMode get themeMode => _themeMode;
  OrionAccent get accent => _accent;
  Color get accentColor => _accent.color;
  OrionThemePreferences get orionTheme => _orionTheme;
  List<SavedOrionTheme> get savedOrionThemes =>
      List.unmodifiable(_savedOrionThemes);
  Uint8List? get customLogoBytes => _customLogoBytes;
  static const maxCustomLogoBytes = 8 * 1024 * 1024;
  bool get reducedMotion => _reducedMotion;
  double get editorFontSize => _editorFontSize;
  double get uiScale => _uiScale;
  bool get orionCompactMode =>
      getInterfacePreferences(InterfacePreset.orion)['compactMode'] == true;
  bool get orionEnlargedMode =>
      !orionCompactMode &&
      getInterfacePreferences(InterfacePreset.orion)['enlargedMode'] == true;
  bool get alwaysOnTop =>
      getInterfacePreferences(InterfacePreset.orion)['alwaysOnTop'] == true;
  bool get showMinimap =>
      getInterfacePreferences(InterfacePreset.orion)['minimap'] == true;
  bool get autocomplete =>
      getInterfacePreferences(InterfacePreset.orion)['autocomplete'] != false;
  bool get bracketPairColorization =>
      getInterfacePreferences(
        InterfacePreset.orion,
      )['bracketPairColorization'] !=
      false;
  bool get renderWhitespace =>
      getInterfacePreferences(InterfacePreset.orion)['renderWhitespace'] ==
      true;
  SynapsePreferences get synapsePreferences => _synapsePreferences;

  void setOrionCompactMode(bool value) {
    if (orionCompactMode == value) return;
    setInterfacePreference(InterfacePreset.orion, 'compactMode', value);
  }

  void setOrionEnlargedMode(bool value) {
    if (orionEnlargedMode == value) return;
    setInterfacePreference(InterfacePreset.orion, 'enlargedMode', value);
  }

  void setAlwaysOnTop(bool value) {
    if (alwaysOnTop == value) return;
    setInterfacePreference(InterfacePreset.orion, 'alwaysOnTop', value);
  }

  void setShowMinimap(bool value) {
    if (showMinimap == value) return;
    setInterfacePreference(InterfacePreset.orion, 'minimap', value);
  }

  void setAutocomplete(bool value) {
    if (autocomplete == value) return;
    setInterfacePreference(InterfacePreset.orion, 'autocomplete', value);
  }

  void setBracketPairColorization(bool value) {
    if (bracketPairColorization == value) return;
    setInterfacePreference(
      InterfacePreset.orion,
      'bracketPairColorization',
      value,
    );
  }

  void setRenderWhitespace(bool value) {
    if (renderWhitespace == value) return;
    setInterfacePreference(InterfacePreset.orion, 'renderWhitespace', value);
  }

  Map<String, Object?> getInterfacePreferences(InterfacePreset preset) =>
      _interfacePreferences[preset] ?? const {};

  void setInterfacePreference(
    InterfacePreset preset,
    String key,
    Object? value,
  ) {
    final preferences = Map<String, Object?>.of(
      getInterfacePreferences(preset),
    );
    if (value == null) {
      preferences.remove(key);
    } else {
      preferences[key] = copyInterfacePreference(value);
    }
    // A size-mode switch is one persisted mutation, including changes from
    // companion windows. Never expose an intermediate mode to resize listeners.
    if (preset == InterfacePreset.orion && value == true) {
      if (key == 'compactMode') preferences['enlargedMode'] = false;
      if (key == 'enlargedMode') preferences['compactMode'] = false;
    }
    _interfacePreferences[preset] = Map.unmodifiable(preferences);
    _changed();
  }

  void resetInterfacePreferences(InterfacePreset preset) {
    _interfacePreferences.remove(preset);
    _changed();
  }

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
    _synapsePreferences = _synapsePreferences.copyWith(
      alwaysOnTop: alwaysOnTop,
      resizable: resizable,
      showScriptList: showScriptList,
      minimap: minimap,
      errorLogging: errorLogging,
      compactButtons: compactButtons,
      compactTabs: compactTabs,
      consoleTimestamp: consoleTimestamp,
      defaultTabContent: defaultTabContent,
      themePreset: themePreset,
      uiFontFamily: uiFontFamily,
      consoleHeight: consoleHeight,
      consoleFontSize: consoleFontSize,
      cornerRadius: cornerRadius,
      themeBackground: themeBackground,
      themeAccent: themeAccent,
      themeColors: themeColors,
      gistUrls: gistUrls,
      bookmarkedDocumentIds: bookmarkedDocumentIds,
      gistDocumentUrls: gistDocumentUrls,
    );
    _changed();
  }

  void resetSynapsePreferences() {
    _synapsePreferences = const SynapsePreferences();
    _editorFontSize = 14;
    _uiScale = 1;
    _wordWrap = false;
    _showLineNumbers = true;
    _autosave = true;
    _changed();
  }

  void resetSynapseTheme({
    String preset = 'framework',
    Map<String, int> colors = const {},
  }) {
    final data = _synapsePreferences.toJson();
    data['themePreset'] = preset;
    data['themeColors'] = colors;
    data['uiFontFamily'] = 'SynapseInter';
    data['cornerRadius'] = 7;
    _synapsePreferences = SynapsePreferences.fromJson(data);
    _changed();
  }

  void executeSource(String source, {String? name}) =>
      execute(source: source, name: name);
  bool get wordWrap => _wordWrap;
  bool get showLineNumbers => _showLineNumbers;
  bool get autosave => _autosave;
  bool get introCompleted => _introCompleted;
  bool get initialized => _initialized;
  String? get persistenceError => _persistenceError;

  List<LibraryItem> get filteredLibraryItems {
    final query = _searchQuery.trim().toLowerCase();
    return libraryItems
        .where((item) {
          final inCollection =
              _selectedCollection == 'All scripts' ||
              (_selectedCollection == 'Favorites'
                  ? isFavorite(item.id)
                  : item.collection == _selectedCollection);
          final matchesQuery =
              query.isEmpty ||
              '${item.title} ${item.description} ${item.tags.join(' ')} ${item.collection}'
                  .toLowerCase()
                  .contains(query);
          return inCollection && matchesQuery;
        })
        .toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    try {
      _storageDirectory ??= await WorkspacePaths.prepare();
      final stateFile = File('${_storageDirectory!.path}/orion-workspace.json');
      if (await stateFile.exists()) {
        final json = jsonDecode(await stateFile.readAsString());
        if (json is Map<String, dynamic>) _restore(json);
      }
    } on Object catch (error) {
      _persistenceError = 'Could not restore the local workspace: $error';
      _addActivity(
        'Started a fresh workspace',
        'The saved workspace could not be read. Your files are unaffected.',
        ActivityKind.workspace,
        ActivitySeverity.warning,
        persist: false,
      );
    }
    if (_disposed) return;
    final storage = _storageDirectory;
    if (storage != null) {
      final library = ScriptLibraryService(directory: scriptsDirectory);
      _scriptLibrary = library;
      await library.initialize();
    }
    if (_disposed) return;
    _initialized = true;
    _notify();
  }

  void selectDocument(String id) {
    if (_activeDocumentId == id || !_documents.any((doc) => doc.id == id)) {
      return;
    }
    _activeDocumentId = id;
    _changed();
  }

  EditorDocument newDocument({String? name, String content = ''}) {
    final document = EditorDocument(
      id: _newId('document'),
      name: name ?? _nextUntitledName(),
      content: content,
      savedContent: content,
    );
    _documents.add(document);
    _activeDocumentId = document.id;
    _addActivity(
      'Script created',
      document.name,
      ActivityKind.workspace,
      ActivitySeverity.info,
    );
    _changed();
    return document;
  }

  void updateDocumentContent(String id, String content) {
    final index = _documents.indexWhere((document) => document.id == id);
    if (index < 0 || _documents[index].content == content) return;
    _documents[index] = _documents[index].copyWith(content: content);
    // Autosave means local recovery; external files are written only on Save.
    _changed(persist: _autosave);
  }

  void renameDocument(String id, String name) {
    final trimmedName = name.trim();
    final index = _documents.indexWhere((document) => document.id == id);
    if (index < 0 || trimmedName.isEmpty) return;
    _documents[index] = _documents[index].copyWith(name: trimmedName);
    _changed();
  }

  /// The UI confirms discarding unsaved changes before calling this method.
  void closeDocument(String id) {
    final index = _documents.indexWhere((document) => document.id == id);
    if (index < 0) return;
    final wasActive = _activeDocumentId == id;
    _documents.removeAt(index);
    if (_documents.isEmpty) {
      final document = EditorDocument(
        id: _newId('document'),
        name: 'untitled.lua',
        content: '',
        savedContent: '',
      );
      _documents.add(document);
    }
    if (wasActive) {
      _activeDocumentId = _documents[index.clamp(0, _documents.length - 1)].id;
    }
    _changed();
  }

  Future<EditorDocument?> openFile() async {
    try {
      final file = await openFileDialog();
      if (file == null || _disposed) return null;
      return await openFileAtPath(file.path);
    } on Object catch (error) {
      _fileError('Could not open the file', error);
      return null;
    }
  }

  /// Kept separate from [openFile] for local integrations and tests.
  Future<EditorDocument?> openFileAtPath(String path) async {
    try {
      final existingIndex = _documents.indexWhere(
        (doc) => doc.filePath != null && FilePaths.same(doc.filePath!, path),
      );
      if (existingIndex >= 0) {
        selectDocument(_documents[existingIndex].id);
        return _documents[existingIndex];
      }
      final content = await File(path).readAsString();
      if (_disposed) return null;
      final document = EditorDocument(
        id: _newId('document'),
        name: _fileName(path),
        content: content,
        savedContent: content,
        filePath: path,
      );
      _documents.add(document);
      _activeDocumentId = document.id;
      _addActivity(
        'File opened',
        document.name,
        ActivityKind.file,
        ActivitySeverity.success,
      );
      _changed();
      return document;
    } on Object catch (error) {
      _fileError('Could not open the file', error);
      return null;
    }
  }

  /// Source ports either create a fresh tab or replace one existing editor.
  Future<EditorDocument?> importDocumentFromPath(
    String path, {
    String? replaceId,
  }) async {
    try {
      final content = await File(path).readAsString();
      if (_disposed) return null;
      final index = replaceId == null
          ? -1
          : _documents.indexWhere((document) => document.id == replaceId);
      if (replaceId != null && index < 0) return null;
      final document = EditorDocument(
        id: replaceId ?? _newId('document'),
        name: _fileName(path),
        content: content,
        savedContent: content,
        filePath: path,
      );
      if (index < 0) {
        _documents.add(document);
      } else {
        _documents[index] = document;
      }
      if (!_detachedDocumentIds.contains(document.id)) {
        _activeDocumentId = document.id;
      }
      _addActivity(
        'File opened',
        document.name,
        ActivityKind.file,
        ActivitySeverity.success,
      );
      _changed();
      return document;
    } on Object catch (error) {
      _fileError('Could not open the file', error);
      return null;
    }
  }

  Future<bool> saveDocument([String? id]) async {
    final document = _documentById(id ?? _activeDocumentId);
    if (document == null) return false;
    if (document.filePath == null) return saveAs(document.id);
    return _writeDocument(document.id, document.filePath!);
  }

  Future<bool> saveAs([String? id]) async {
    final document = _documentById(id ?? _activeDocumentId);
    if (document == null) return false;
    try {
      final location = await getSaveLocation(
        suggestedName: document.name,
        initialDirectory: scriptsDirectory.path,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Luau, Lua and text files',
            extensions: ['luau', 'lua', 'txt'],
          ),
        ],
      );
      if (location == null || _disposed) return false;
      return await _writeDocument(document.id, location.path);
    } on Object catch (error) {
      _fileError('Could not save the file', error);
      return false;
    }
  }

  Future<bool> saveDocumentToPath(String id, String path) =>
      _writeDocument(id, path);

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _notify();
  }

  void setCollection(String collection) {
    if (!collections.contains(collection) ||
        _selectedCollection == collection) {
      return;
    }
    _selectedCollection = collection;
    _notify();
  }

  bool isFavorite(String id) => _favoriteIds.contains(id);

  void toggleFavorite(String id) {
    if (!libraryItems.any((item) => item.id == id)) return;
    if (!_favoriteIds.remove(id)) _favoriteIds.add(id);
    _changed();
  }

  EditorDocument openLibraryItem(String id) {
    final item = libraryItems.firstWhere((item) => item.id == id);
    final document = newDocument(name: item.fileName, content: item.source);
    _addActivity(
      'Library script opened',
      item.fileName,
      ActivityKind.library,
      ActivitySeverity.success,
    );
    _changed();
    return document;
  }

  InterfacePreset get selectedInterface => _selectedInterface;
  void setInterface(InterfacePreset preset) {
    if (_selectedInterface == preset) return;
    _selectedInterface = preset;
    _changed();
  }

  List<RemoteScript> get remoteScripts => List.unmodifiable(_remoteScripts);
  List<RemoteScript> get remoteFavorites =>
      List.unmodifiable(_remoteFavorites.values);
  ScriptProvider? get selectedProvider => _selectedProvider;
  bool get remoteLoading => _remoteLoading;
  bool get remoteLoadingMore => _remoteLoadingMore;
  bool get remoteHasMore => _remoteHasMoreProviders.isNotEmpty;
  Map<ScriptProvider, String> get providerErrors =>
      Map.unmodifiable(_providerErrors);

  void setRemoteSearchQuery(String query) {
    _searchQuery = query;
    _remoteSearchDebounce?.cancel();
    _remoteSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(searchRemoteScripts());
    });
    _notify();
  }

  void setScriptProvider(ScriptProvider? provider) {
    if (_selectedProvider == provider) return;
    _selectedProvider = provider;
    _scheduleSave();
    unawaited(searchRemoteScripts());
  }

  Future<void> searchRemoteScripts([String? query]) async {
    if (_disposed) return;
    _remoteSearchDebounce?.cancel();
    if (query != null) _searchQuery = query;
    _remoteQuery = _searchQuery.trim();
    final generation = ++_remoteGeneration;
    _remoteScripts.clear();
    _providerErrors.clear();
    _providerPages.clear();
    _remoteHasMoreProviders.clear();
    _remoteBusyProviders.clear();
    _remoteLoading = true;
    _remoteLoadingMore = false;
    _notify();
    final providers = _selectedProvider == null
        ? ScriptProvider.values
        : [_selectedProvider!];
    await Future.wait(
      providers.map(
        (provider) => _fetchRemotePage(provider, 1, generation, _remoteQuery),
      ),
    );
    if (_disposed || generation != _remoteGeneration) return;
    _remoteLoading = false;
    _notify();
  }

  Future<void> _fetchRemotePage(
    ScriptProvider provider,
    int page,
    int generation,
    String query,
  ) async {
    _remoteBusyProviders.add(provider);
    try {
      final response = await _scriptHub.fetch(provider, query, page);
      if (_disposed || generation != _remoteGeneration) return;
      _providerErrors.remove(provider);
      _providerPages[provider] = page;
      if (response.hasMore) {
        _remoteHasMoreProviders.add(provider);
      } else {
        _remoteHasMoreProviders.remove(provider);
      }
      final seen = _remoteScripts.map((item) => item.key).toSet();
      _remoteScripts.addAll(response.items.where((item) => seen.add(item.key)));
      _remoteScripts.sort((a, b) {
        final latest = (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
        return latest != 0
            ? latest
            : a.provider.index.compareTo(b.provider.index);
      });
    } on Object catch (error) {
      if (_disposed || generation != _remoteGeneration) return;
      _providerErrors[provider] = error is ScriptHubException
          ? error.message
          : error.toString();
    } finally {
      if (!_disposed && generation == _remoteGeneration) {
        _remoteBusyProviders.remove(provider);
        _notify();
      }
    }
  }

  Future<void> loadMoreRemoteScripts() async {
    if (_disposed || _remoteLoading || _remoteLoadingMore || !remoteHasMore) {
      return;
    }
    final generation = _remoteGeneration;
    final query = _remoteQuery;
    final providers = List<ScriptProvider>.of(_remoteHasMoreProviders);
    _remoteLoadingMore = true;
    _notify();
    await Future.wait(
      providers.map(
        (provider) => _fetchRemotePage(
          provider,
          (_providerPages[provider] ?? 0) + 1,
          generation,
          query,
        ),
      ),
    );
    if (_disposed || generation != _remoteGeneration) return;
    _remoteLoadingMore = false;
    _notify();
  }

  Future<void> retryRemoteSource(ScriptProvider provider) async {
    if (_disposed ||
        _remoteLoading ||
        _remoteLoadingMore ||
        _remoteBusyProviders.contains(provider)) {
      return;
    }
    if (_selectedProvider != null && _selectedProvider != provider) return;
    _remoteLoadingMore = true;
    _notify();
    final generation = _remoteGeneration;
    await _fetchRemotePage(
      provider,
      (_providerPages[provider] ?? 0) + 1,
      generation,
      _remoteQuery,
    );
    if (_disposed || generation != _remoteGeneration) return;
    _remoteLoadingMore = false;
    _notify();
  }

  bool isRemoteFavorite(String key) => _remoteFavorites.containsKey(key);
  void toggleRemoteFavorite(RemoteScript script) {
    if (_remoteFavorites.remove(script.key) == null) {
      // Persist metadata, never megabytes of downloaded source.
      final metadata = RemoteScript.fromJson({
        ...script.toJson(),
        'body': null,
      });
      if (metadata != null) _remoteFavorites[script.key] = metadata;
    }
    _changed();
  }

  Future<String> loadRemoteScript(RemoteScript script) {
    final existing = _remoteCodeCache[script.key];
    if (existing != null) return existing;
    if (_remoteCodeCache.length >= 24) {
      _remoteCodeCache.remove(_remoteCodeCache.keys.first);
    }
    final pending = _scriptHub.loadScript(script);
    _remoteCodeCache[script.key] = pending;
    // A failed load is retryable; observing its error here prevents stale caching.
    unawaited(
      pending.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_remoteCodeCache[script.key], pending)) {
            _remoteCodeCache.remove(script.key);
          }
        },
      ),
    );
    return pending;
  }

  Future<EditorDocument?> openRemoteScript(RemoteScript script) async {
    final body = await loadRemoteScript(script);
    if (_disposed) return null;
    final base = script.title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final trimmed = base.isEmpty
        ? 'script'
        : base.substring(0, base.length.clamp(0, 100));
    final name = trimmed.toLowerCase().endsWith('.lua')
        ? trimmed
        : '$trimmed.lua';
    return newDocument(name: name, content: body);
  }

  Future<void> executeRemoteScript(RemoteScript script) async {
    final body = await loadRemoteScript(script);
    if (_disposed) return;
    execute(source: body, name: script.title);
  }

  Future<void> openScriptPage(RemoteScript script) =>
      _openScriptUrl(script.externalUrl);
  Future<void> openScriptProvider(ScriptProvider provider) =>
      _openScriptUrl('https://${provider.domain}/');
  Future<void> _openScriptUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('The source link is not available.');
    }
    await DesktopLauncher.openUrl(uri);
  }

  void execute({String? source, String? name}) {
    if (_disposed) return;
    final body = source ?? activeDocument.content;
    final scriptName = name ?? activeDocument.name;
    if (body.trim().isEmpty) {
      _addActivity(
        'Script is empty',
        'Add code before running $scriptName.',
        ActivityKind.execution,
        ActivitySeverity.error,
      );
      _changed();
      return;
    }
    if (usesNativeExecutor) {
      unawaited(_executeViaNativeExecutor(body, scriptName));
      return;
    }
    if (!bridgeConnected) {
      _addActivity(
        'No clients connected',
        usesMacSploit
            ? 'Start MacSploit and open a Roblox client to run $scriptName.'
            : 'Connect Orion Bridge to run $scriptName. Open Clients to copy Orion Bridge.lua.',
        ActivityKind.execution,
        ActivitySeverity.warning,
      );
      _changed();
      return;
    }
    final targetCount = bridgeTargetCount;
    late final BridgeExecutionReceipt receipt;
    try {
      receipt = _bridge.enqueueExecute(
        body,
        targetIdentifiers: _bridgeTargetAll ? null : _selectedBridgeClients,
      );
    } on ArgumentError catch (error) {
      _addActivity(
        'Script could not be queued',
        error.message.toString(),
        ActivityKind.execution,
        ActivitySeverity.error,
      );
      _changed();
      return;
    }
    if (receipt.deliveredCount == 0) {
      _addActivity(
        targetCount == 0 ? 'No clients selected' : 'Clients unavailable',
        targetCount == 0
            ? 'Choose a client in the client manager before executing.'
            : 'The target clients disconnected or their execution queues are full.',
        ActivityKind.execution,
        ActivitySeverity.warning,
      );
    } else {
      final count = receipt.deliveredCount;
      _addActivity(
        'Script queued',
        '$scriptName → $count ${count == 1 ? 'client' : 'clients'} · ${receipt.targetIdentifiers.join(', ')}',
        ActivityKind.execution,
        ActivitySeverity.info,
      );
    }
    _changed();
  }

  Future<void> _executeViaNativeExecutor(
    String source,
    String scriptName,
  ) async {
    try {
      final receipt = await _bridge.executeNativeExecutor(
        source,
        targetIdentifiers: _bridgeTargetAll ? null : _selectedBridgeClients,
      );
      final target = receipt.targetIdentifiers.single;
      final executor = _bridge.nativeExecutorName ?? 'executor';
      final client = _bridgeClients
          .where((item) => item.identifier == target)
          .firstOrNull;
      _addActivity(
        'Script sent',
        '$scriptName → $executor on $target${client == null ? '' : ' (${client.username})'}',
        ActivityKind.execution,
        ActivitySeverity.success,
      );
    } on Object catch (error) {
      _addActivity(
        'Script could not be executed',
        error.toString(),
        ActivityKind.execution,
        ActivitySeverity.error,
      );
    }
    if (!_disposed) _changed();
  }

  void attach() {
    if (_disposed) return;
    _addActivity(
      bridgeConnected
          ? (usesNativeExecutor
                ? '${detectedNativeExecutor ?? 'Executor'} connected'
                : 'Orion Bridge connected')
          : (usesNativeExecutor
                ? 'Waiting for executor'
                : 'Waiting for Orion Bridge'),
      bridgeConnected
          ? '${_bridgeClients.length} clients connected. Choose execution targets in Clients.'
          : (usesNativeExecutor
                ? 'Select MacSploit or Opiumware, or leave Auto to detect an available executor.'
                : 'Run Orion Bridge.lua in your client. Open Clients to copy the script or loader.'),
      ActivityKind.execution,
      bridgeConnected ? ActivitySeverity.success : ActivitySeverity.info,
    );
    _changed();
  }

  void clearActivities() {
    _activities.clear();
    _changed();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _orionTheme = _orionTheme.copyWith(themeMode: mode);
    _changed();
  }

  void setAccent(OrionAccent accent) {
    if (_accent == accent && _orionTheme.accent == accent.color) return;
    _accent = accent;
    _orionTheme = _orionTheme.copyWith(accent: accent.color);
    _changed();
  }

  void setOrionTheme(OrionThemePreferences preferences) {
    if (_orionTheme == preferences && _themeMode == preferences.themeMode) {
      return;
    }
    _orionTheme = preferences;
    _themeMode = preferences.themeMode;
    _changed();
  }

  /// Commit a Studio document, recovery draft and Orion palette as one update.
  /// The same operation is forwarded atomically by native companion engines.
  void applyThemeStudioState(
    InterfacePreset preset, {
    required Object? document,
    Object? draft,
    OrionThemePreferences? orionTheme,
  }) {
    runWindowUpdate(() {
      if (preset == InterfacePreset.orion && orionTheme != null) {
        setOrionTheme(orionTheme);
      }
      setInterfacePreference(preset, 'themeStudio', document);
      setInterfacePreference(preset, 'themeStudioDraft', draft);
    });
  }

  void resetOrionTheme() {
    _orionTheme = OrionThemePreferences.defaults;
    _themeMode = ThemeMode.dark;
    _accent = OrionAccent.blue;
    _changed();
  }

  SavedOrionTheme saveOrionTheme(String name) {
    final trimmed = name.trim();
    final saved = SavedOrionTheme(
      id: 'theme-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
      name: trimmed.isEmpty
          ? 'Untitled theme'
          : trimmed.substring(0, trimmed.length.clamp(0, 80)),
      preferences: _orionTheme,
    );
    if (_savedOrionThemes.length >= 32) _savedOrionThemes.removeAt(0);
    _savedOrionThemes.add(saved);
    _changed();
    return saved;
  }

  void applySavedOrionTheme(String id) {
    final saved = _savedOrionThemes
        .where((theme) => theme.id == id)
        .firstOrNull;
    if (saved != null) setOrionTheme(saved.preferences);
  }

  void deleteSavedOrionTheme(String id) {
    final count = _savedOrionThemes.length;
    _savedOrionThemes.removeWhere((theme) => theme.id == id);
    if (_savedOrionThemes.length != count) _changed();
  }

  String exportOrionTheme() =>
      const JsonEncoder.withIndent('  ').convert(_orionTheme.toJson());

  bool importOrionTheme(String source) {
    if (source.length > 65536) return false;
    try {
      final value = jsonDecode(source);
      if (value is! Map ||
          !value.keys.any(
            (key) => const {
              'presetId',
              'accent',
              'gradientColors',
              'overrides',
            }.contains(key),
          )) {
        return false;
      }
      setOrionTheme(OrionThemePreferences.fromJson(value));
      return true;
    } on FormatException {
      return false;
    }
  }

  void setCustomLogo(Uint8List? bytes) {
    if (bytes != null && !_isSupportedLogo(bytes)) {
      throw ArgumentError(
        'Use a PNG, JPEG, WebP or GIF logo of at most 8 MiB and 8192 pixels per side.',
      );
    }
    _customLogoBytes = bytes == null
        ? null
        : Uint8List.fromList(bytes).asUnmodifiableView();
    _customLogoBase64 = _customLogoBytes == null
        ? null
        : base64Encode(_customLogoBytes!);
    // The familiar Logo control remains authoritative after an advanced edit.
    // Keep the Studio layer's geometry while replacing only its image.
    final preferences = getInterfacePreferences(InterfacePreset.orion);
    final stored = preferences['themeStudio'];
    if (stored is Map && stored['windows'] is Map) {
      final document = Map<String, Object?>.from(stored);
      final windows = Map<String, Object?>.from(stored['windows'] as Map);
      if (windows['main'] is Map) {
        final main = Map<String, Object?>.from(windows['main'] as Map);
        main.remove('logo');
        if (main['elements'] is Map) {
          final elements = Map<String, Object?>.from(main['elements'] as Map);
          if (elements['logo'] is Map) {
            final logo = Map<String, Object?>.from(elements['logo'] as Map);
            logo.remove('image');
            elements['logo'] = logo;
          }
          main['elements'] = elements;
        }
        windows['main'] = main;
        document['windows'] = windows;
        runWindowUpdate(() {
          setInterfacePreference(
            InterfacePreset.orion,
            'themeStudio',
            document,
          );
          _changed();
        });
        return;
      }
    }
    _changed();
  }

  static bool _isSupportedLogo(Uint8List bytes) {
    if (bytes.length < 12 || bytes.length > maxCustomLogoBytes) return false;
    bool starts(List<int> signature) => List.generate(
      signature.length,
      (i) => i,
    ).every((i) => bytes[i] == signature[i]);
    bool validSize(int width, int height) =>
        width > 0 && height > 0 && width <= 8192 && height <= 8192;
    if (starts(const [137, 80, 78, 71, 13, 10, 26, 10])) {
      if (bytes.length < 33 ||
          String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
        return false;
      }
      final data = ByteData.sublistView(bytes);
      final width = data.getUint32(16), height = data.getUint32(20);
      return validSize(width, height) &&
          bytes.length >= 45 &&
          String.fromCharCodes(
                bytes.sublist(bytes.length - 8, bytes.length - 4),
              ) ==
              'IEND';
    }
    if (starts(const [255, 216, 255])) {
      if (bytes[bytes.length - 2] != 255 || bytes.last != 217) return false;
      var offset = 2;
      while (offset + 4 <= bytes.length) {
        if (bytes[offset++] != 255) return false;
        while (offset < bytes.length && bytes[offset] == 255) {
          offset++;
        }
        if (offset >= bytes.length) return false;
        final marker = bytes[offset++];
        if (marker == 1 || (marker >= 0xD0 && marker <= 0xD9)) continue;
        if (offset + 2 > bytes.length) return false;
        final length = (bytes[offset] << 8) | bytes[offset + 1];
        if (length < 2 || offset + length > bytes.length) return false;
        if (const {
          0xC0,
          0xC1,
          0xC2,
          0xC3,
          0xC5,
          0xC6,
          0xC7,
          0xC9,
          0xCA,
          0xCB,
          0xCD,
          0xCE,
          0xCF,
        }.contains(marker)) {
          if (length < 7) return false;
          return validSize(
            (bytes[offset + 5] << 8) | bytes[offset + 6],
            (bytes[offset + 3] << 8) | bytes[offset + 4],
          );
        }
        offset += length;
      }
      return false;
    }
    if (starts(const [71, 73, 70, 56, 55, 97]) ||
        starts(const [71, 73, 70, 56, 57, 97])) {
      final data = ByteData.sublistView(bytes);
      final width = data.getUint16(6, Endian.little),
          height = data.getUint16(8, Endian.little);
      return validSize(width, height) && bytes.last == 0x3B;
    }
    if (!starts(const [82, 73, 70, 70]) ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WEBP' ||
        bytes.length < 25) {
      return false;
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(4, Endian.little) + 8 != bytes.length) return false;
    final type = String.fromCharCodes(bytes.sublist(12, 16));
    if (type == 'VP8X' && bytes.length >= 30) {
      int uint24(int offset) =>
          bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
      return validSize(uint24(24) + 1, uint24(27) + 1);
    }
    if (type == 'VP8L' && bytes[20] == 0x2F) {
      return validSize(
        1 + (bytes[21] | ((bytes[22] & 0x3F) << 8)),
        1 + ((bytes[22] >> 6) | (bytes[23] << 2) | ((bytes[24] & 0xF) << 10)),
      );
    }
    if (type == 'VP8 ' &&
        bytes.length >= 30 &&
        bytes[23] == 0x9D &&
        bytes[24] == 1 &&
        bytes[25] == 0x2A) {
      return validSize(
        data.getUint16(26, Endian.little) & 0x3FFF,
        data.getUint16(28, Endian.little) & 0x3FFF,
      );
    }
    return false;
  }

  static Uint8List? _readCustomLogo(Object? value) {
    if (value is! String ||
        value.length > ((maxCustomLogoBytes + 2) ~/ 3) * 4) {
      return null;
    }
    try {
      final bytes = base64Decode(value);
      return _isSupportedLogo(bytes) ? bytes.asUnmodifiableView() : null;
    } on FormatException {
      return null;
    }
  }

  void setReducedMotion(bool value) {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    _changed();
  }

  void setUiScale(double value) {
    final scale = _normalizeUiScale(value);
    if (_uiScale == scale) return;
    _uiScale = scale;
    _changed();
  }

  static double _normalizeUiScale(double value) {
    if (!value.isFinite) return 1.0;
    return (value.clamp(.8, 1.25) * 20).round() / 20;
  }

  void setEditorFontSize(double value) {
    final size = value.clamp(11, 22).toDouble();
    if (_editorFontSize == size) return;
    _editorFontSize = size;
    _changed();
  }

  void setWordWrap(bool value) {
    if (_wordWrap == value) return;
    _wordWrap = value;
    _changed();
  }

  void setShowLineNumbers(bool value) {
    if (_showLineNumbers == value) return;
    _showLineNumbers = value;
    _changed();
  }

  void setAutosave(bool value) {
    if (_autosave == value) return;
    _autosave = value;
    _changed();
  }

  void completeIntro() {
    if (_introCompleted) return;
    _introCompleted = true;
    _changed();
  }

  void replayIntro() {
    _introCompleted = false;
    _changed();
  }

  Future<void> flushPersistence() {
    if (!_persistChanges) return Future<void>.value();
    _saveDebounce?.cancel();
    final directory = _storageDirectory;
    if (directory == null) return Future<void>.value();
    final snapshot = jsonEncode(_toJson());
    _writeQueue = _writeQueue.then((_) async {
      try {
        await directory.create(recursive: true);
        final target = File('${directory.path}/orion-workspace.json');
        final temporary = File('${target.path}.tmp');
        await temporary.writeAsString(snapshot, flush: true);
        await temporary.rename(target.path);
        _persistenceError = null;
      } on Object catch (error) {
        _persistenceError = 'Could not save the local workspace: $error';
        _notify();
      }
    });
    return _writeQueue;
  }

  Future<bool> _writeDocument(String id, String path) async {
    final document = _documentById(id);
    if (document == null || _disposed) return false;
    final savedContent = document.content;
    try {
      await File(path).writeAsString(savedContent, flush: true);
      if (_disposed) return true;
      final index = _documents.indexWhere((doc) => doc.id == id);
      if (index < 0) return true;
      // Keep edits made during the disk write and compare them with its snapshot.
      final latest = _documents[index];
      _documents[index] = latest.copyWith(
        // Saving an existing file keeps its chosen workspace tab name. A new
        // destination still takes the filename selected in Save as.
        name: latest.filePath != null && FilePaths.same(latest.filePath!, path)
            ? latest.name
            : _fileName(path),
        savedContent: savedContent,
        filePath: path,
      );
      _addActivity(
        'Saved to disk',
        '${_fileName(path)} is up to date.',
        ActivityKind.file,
        ActivitySeverity.success,
      );
      _changed();
      return true;
    } on Object catch (error) {
      _fileError('Could not save the file', error);
      return false;
    }
  }

  void _fileError(String title, Object error) {
    _addActivity(
      title,
      error.toString(),
      ActivityKind.file,
      ActivitySeverity.error,
    );
    _changed();
  }

  EditorDocument? _documentById(String id) {
    for (final document in _documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  void _addActivity(
    String title,
    String detail,
    ActivityKind kind,
    ActivitySeverity severity, {
    bool persist = true,
  }) {
    _activities.insert(
      0,
      ActivityEntry(
        id: _newId('activity'),
        title: title,
        detail: detail,
        kind: kind,
        severity: severity,
        timestamp: DateTime.now(),
      ),
    );
    if (_activities.length > 150) {
      _activities.removeRange(150, _activities.length);
    }
    if (persist) _scheduleSave();
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  String _nextUntitledName() {
    var index = 1;
    var name = 'untitled.lua';
    while (_documents.any((document) => document.name == name)) {
      name = 'untitled-${++index}.lua';
    }
    return name;
  }

  static String _fileName(String path) => FilePaths.basename(path);

  void _changed({bool persist = true}) {
    if (persist) _scheduleSave();
    _notify();
  }

  void _notify() {
    if (_windowUpdateDepth > 0) {
      _windowUpdatePending = true;
      return;
    }
    if (!_disposed) notifyListeners();
  }

  void _scheduleSave() {
    if (_disposed || !_persistChanges) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(flushPersistence());
    });
  }

  Map<String, Object?> _toJson({bool includeBranding = true}) => {
    'version': 2,
    'appearanceVersion': 1,
    'bridgeConsoleVersion': 1,
    'selectedInterface': _selectedInterface.name,
    'selectedProvider': _selectedProvider?.name,
    'remoteFavorites': _remoteFavorites.values
        .map((item) => item.toJson())
        .toList(),
    'documents': _documents.map((document) => document.toJson()).toList(),
    'activeDocumentId': _activeDocumentId,
    'favoriteIds': _favoriteIds.toList(),
    'activities': _activities.map((activity) => activity.toJson()).toList(),
    'themeMode': _themeMode.name,
    'accent': _accent.name,
    'orionTheme': _orionTheme.toJson(),
    'savedOrionThemes': _savedOrionThemes
        .map((theme) => theme.toJson())
        .toList(),
    if (includeBranding) 'customLogo': _customLogoBase64,
    'reducedMotion': _reducedMotion,
    'editorFontSize': _editorFontSize,
    'uiScale': _uiScale,
    'synapsePreferences': _synapsePreferences.toJson(),
    'interfacePreferences': {
      for (final entry in _interfacePreferences.entries)
        entry.key.name: entry.value,
    },
    'wordWrap': _wordWrap,
    'showLineNumbers': _showLineNumbers,
    'autosave': _autosave,
    'introCompleted': _introCompleted,
  };

  /// Engine-to-engine state; only the primary controller writes recovery data.
  Map<String, Object?> exportWindowState() => {
    ..._toJson(includeBranding: false),
    'workspaceDirectory': workspaceDirectory.path,
    'bridgeClients': _bridgeClients.map((c) => c.toJson()).toList(),
    'bridgeTargetAll': _bridgeTargetAll,
    'selectedBridgeClients': _selectedBridgeClients.toList(),
    'bridgeListening': _bridgeListening,
    'bridgeError': _bridgeError,
    'bridgePort': _bridgePort,
    'detachedDocumentIds': _detachedDocumentIds.toList(),
    'searchQuery': _searchQuery,
    'remoteQuery': _remoteQuery,
    'remoteScripts': _remoteScripts.map((item) => item.toJson()).toList(),
    'providerErrors': {
      for (final e in _providerErrors.entries) e.key.name: e.value,
    },
    'providerPages': {
      for (final e in _providerPages.entries) e.key.name: e.value,
    },
    'busyProviders': _remoteBusyProviders.map((p) => p.name).toList(),
    'hasMoreProviders': _remoteHasMoreProviders.map((p) => p.name).toList(),
    'remoteLoading': _remoteLoading,
    'remoteLoadingMore': _remoteLoadingMore,
    'persistenceError': _persistenceError,
  };

  void applyWindowState(Map<String, Object?> state) {
    final json = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    final workspace = json['workspaceDirectory'];
    if (workspace is String && workspace.isNotEmpty) {
      _ownerWorkspaceDirectory = Directory(workspace);
    }
    _remoteFavorites.clear();
    _restore(json, restoreBranding: json.containsKey('customLogo'));
    _detachedDocumentIds
      ..clear()
      ..addAll(
        (json['detachedDocumentIds'] as List? ?? const []).whereType<String>(),
      );
    // Runtime connections are mirrored between engines, never restored from disk.
    if (!_bridgeInitialized) {
      _bridgeClients
        ..clear()
        ..addAll(
          (json['bridgeClients'] as List? ?? const []).whereType<Map>().map(
            (v) => BridgeClient.fromJson(Map<String, dynamic>.from(v)),
          ),
        );
      _bridgeListening = json['bridgeListening'] == true;
      _bridgeError = json['bridgeError'] as String?;
      _bridgePort = json['bridgePort'] as int? ?? 31337;
    }
    _bridgeTargetAll = json['bridgeTargetAll'] != false;
    _selectedBridgeClients
      ..clear()
      ..addAll(
        (json['selectedBridgeClients'] as List? ?? const [])
            .whereType<String>(),
      );
    _searchQuery = json['searchQuery'] as String? ?? '';
    _remoteQuery = json['remoteQuery'] as String? ?? '';
    _remoteScripts
      ..clear()
      ..addAll(
        (json['remoteScripts'] as List? ?? const [])
            .map(RemoteScript.fromJson)
            .whereType<RemoteScript>(),
      );
    _providerErrors.clear();
    _providerPages.clear();
    _remoteBusyProviders.clear();
    _remoteHasMoreProviders.clear();
    for (final provider in ScriptProvider.values) {
      final error = (json['providerErrors'] as Map?)?[provider.name];
      final page = (json['providerPages'] as Map?)?[provider.name];
      if (error is String) _providerErrors[provider] = error;
      if (page is int) _providerPages[provider] = page;
      if ((json['busyProviders'] as List? ?? const []).contains(
        provider.name,
      )) {
        _remoteBusyProviders.add(provider);
      }
      if ((json['hasMoreProviders'] as List? ?? const []).contains(
        provider.name,
      )) {
        _remoteHasMoreProviders.add(provider);
      }
    }
    _remoteLoading = json['remoteLoading'] == true;
    _remoteLoadingMore = json['remoteLoadingMore'] == true;
    _persistenceError = json['persistenceError'] as String?;
    _initialized = true;
    _notify();
  }

  void _restore(Map<String, dynamic> json, {bool restoreBranding = true}) {
    final interfacePreferences = json['interfacePreferences'];
    _interfacePreferences.clear();
    if (interfacePreferences is Map) {
      for (final preset in InterfacePreset.values) {
        final preferences = readInterfacePreferences(
          interfacePreferences[preset.name],
        );
        if (preferences.isNotEmpty) _interfacePreferences[preset] = preferences;
      }
    }
    _synapsePreferences = SynapsePreferences.fromJson(
      json['synapsePreferences'],
    );
    _selectedInterface = InterfacePreset.values.firstWhere(
      (preset) =>
          preset.name == json['selectedInterface'] ||
          preset.sourceTag == json['selectedInterface'],
      orElse: () => InterfacePreset.orion,
    );
    _selectedProvider = null;
    for (final provider in ScriptProvider.values) {
      if (provider.name == json['selectedProvider']) {
        _selectedProvider = provider;
      }
    }
    final remoteFavorites = json['remoteFavorites'];
    if (remoteFavorites is List) {
      for (final value in remoteFavorites.take(200)) {
        final item = RemoteScript.fromJson(value);
        if (item != null) _remoteFavorites[item.key] = item;
      }
    }
    final rawDocuments = json['documents'];
    if (rawDocuments is List) {
      final seenIds = <String>{};
      final documents = rawDocuments
          .map(EditorDocument.fromJson)
          .whereType<EditorDocument>()
          .where((document) => seenIds.add(document.id))
          .toList();
      if (documents.isNotEmpty) {
        _documents
          ..clear()
          ..addAll(documents);
      }
    }
    final activeId = json['activeDocumentId'];
    _activeDocumentId =
        activeId is String &&
            _documents.any((document) => document.id == activeId)
        ? activeId
        : _documents.first.id;
    final rawFavorites = json['favoriteIds'];
    if (rawFavorites is List) {
      _favoriteIds
        ..clear()
        ..addAll(
          rawFavorites.whereType<String>().where(
            (id) => libraryItems.any((item) => item.id == id),
          ),
        );
    }
    final rawActivities = json['activities'];
    if (rawActivities is List) {
      final consoleVersion = json['bridgeConsoleVersion'];
      // Retire the old bridge's synthetic success lines once. Versioned state
      // keeps future genuine client prints intact, even with identical text.
      final legacyCompletion = consoleVersion is num && consoleVersion >= 1
          ? null
          : RegExp(
              r'^Execution exec_(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}) completed\.$',
            );
      _activities
        ..clear()
        ..addAll(
          rawActivities
              .map(ActivityEntry.fromJson)
              .whereType<ActivityEntry>()
              .where(
                (entry) =>
                    legacyCompletion == null ||
                    entry.kind != ActivityKind.execution ||
                    entry.severity != ActivitySeverity.info ||
                    legacyCompletion.stringMatch(entry.detail) != entry.detail,
              )
              .take(150),
        );
    }
    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == json['themeMode'],
      orElse: () => ThemeMode.dark,
    );
    _accent = OrionAccent.values.firstWhere(
      (accent) => accent.name == json['accent'],
      orElse: () => OrionAccent.blue,
    );
    // Upgrade the former default once; later explicit choices stay intact.
    final appearanceVersion = json['appearanceVersion'];
    if ((appearanceVersion is! num || appearanceVersion < 1) &&
        _accent == OrionAccent.lime) {
      _accent = OrionAccent.blue;
    }
    _orionTheme = json['orionTheme'] is Map
        ? OrionThemePreferences.fromJson(json['orionTheme'])
        : OrionThemePreferences.defaults.copyWith(
            themeMode: _themeMode,
            accent: _accent.color,
          );
    _themeMode = _orionTheme.themeMode;
    final saved = json['savedOrionThemes'];
    _savedOrionThemes.clear();
    if (saved is List) {
      final ids = <String>{};
      _savedOrionThemes.addAll(
        saved
            .take(32)
            .map(SavedOrionTheme.fromJson)
            .whereType<SavedOrionTheme>()
            .where((theme) => ids.add(theme.id)),
      );
    }
    if (restoreBranding) {
      _customLogoBytes = _readCustomLogo(json['customLogo']);
      _customLogoBase64 = _customLogoBytes == null
          ? null
          : base64Encode(_customLogoBytes!);
    }
    _reducedMotion = _readBool(json, 'reducedMotion', false);
    _wordWrap = _readBool(json, 'wordWrap', false);
    _showLineNumbers = _readBool(json, 'showLineNumbers', true);
    _autosave = _readBool(json, 'autosave', true);
    _introCompleted = _readBool(json, 'introCompleted', false);
    final uiScale = json['uiScale'];
    _uiScale = uiScale is num ? _normalizeUiScale(uiScale.toDouble()) : 1.0;
    final fontSize = json['editorFontSize'];
    if (fontSize is num) {
      _editorFontSize = fontSize.toDouble().clamp(11, 22).toDouble();
    }
  }

  static bool _readBool(Map<String, dynamic> json, String key, bool fallback) =>
      json[key] is bool ? json[key] as bool : fallback;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _remoteSearchDebounce?.cancel();
    _remoteGeneration++;
    _scriptHub.close();
    _scriptLibrary?.dispose();
    _bridge.removeListener(_bridgeChanged);
    unawaited(_bridgeLogSubscription?.cancel());
    final shutdown = bridgeShutdownHook;
    bridgeShutdownHook = null;
    if (shutdown != null) unawaited(Future<void>.sync(shutdown));
    _bridge.dispose();
    unawaited(flushPersistence());
    _disposed = true;
    super.dispose();
  }
}

// The alias avoids shadowing file_selector's openFile with the controller API.
Future<XFile?> openFileDialog() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'Luau, Lua and text files',
      extensions: ['luau', 'lua', 'txt'],
    ),
    XTypeGroup(label: 'All files'),
  ],
);
