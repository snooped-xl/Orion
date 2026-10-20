import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/remote_script.dart';
import 'package:orion/services/companion_commands.dart';
import 'package:orion/services/companion_controller.dart';
import 'package:orion/state/orion_controller.dart';

/// Exercise the same loss of nested map key types as the native window codec.
Map<String, Object?> _nativeRoundTrip(Map<String, Object?> value) {
  const codec = StandardMessageCodec();
  return Map<String, Object?>.from(
    codec.decodeMessage(codec.encodeMessage(value)) as Map,
  );
}

CompanionController _mirror(OrionController owner, {String? documentId}) {
  final gateway = CompanionCommands(owner);
  var revision = 0;
  return CompanionController(
    initialState: _nativeRoundTrip(owner.exportWindowState()),
    documentId: documentId,
    sendCommand: (operation, payload, sequence) async {
      final result = await gateway.apply(operation, _nativeRoundTrip(payload));
      return _nativeRoundTrip({
        'envelope': {
          'state': owner.exportWindowState(),
          'ack': sequence,
          'revision': ++revision,
        },
        'result': result,
      });
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Orion Studio commits palette, document and recovery atomically over IPC',
    () async {
      final owner = OrionController(persistChanges: false, useMacSploit: false);
      final child = _mirror(owner);
      addTearDown(() {
        child.dispose();
        owner.dispose();
      });
      final changes = <Map<String, Object?>>[];
      owner.addListener(() => changes.add(owner.exportWindowState()));
      final palette = OrionThemePreferences.builtInPresets
          .singleWhere((p) => p.id == 'material-rain')
          .preferences
          .copyWith(accent: const Color(0xff3344aa));
      final document = {
        'name': 'Atomic theme',
        'windows': {
          'main': {'width': 1000},
        },
      };
      child.applyThemeStudioState(
        InterfacePreset.orion,
        document: document,
        draft: null,
        orionTheme: palette,
      );
      await child.flushCommands();
      expect(changes, hasLength(1));
      expect(owner.orionTheme, palette);
      expect(
        owner.getInterfacePreferences(InterfacePreset.orion)['themeStudio'],
        document,
      );
      expect(child.orionTheme, palette);
      expect(child.pendingCommandCount, 0);
    },
  );
  test(
    'native Apply waits for owner disk writes and mirrors recoverable storage errors',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orion-studio-disk-',
      );
      final owner = OrionController(storageDirectory: directory);
      await owner.initialize();
      await owner.flushPersistence();
      final child = _mirror(owner);
      addTearDown(() async {
        child.dispose();
        owner.dispose();
        await owner.flushPersistence();
        await directory.delete(recursive: true);
      });
      final blocker = Directory('${directory.path}/orion-workspace.json.tmp');
      await blocker.create();
      child.setInterfacePreference(InterfacePreset.synapseBlue, 'themeStudio', {
        'colors': {'shellBg': 0xff102030},
      });
      await child.flushPersistence();
      expect(owner.persistenceError, isNotNull);
      expect(child.persistenceError, owner.persistenceError);
      expect(child.pendingCommandCount, 0);
      await blocker.delete();
      child.setInterfacePreference(
        InterfacePreset.synapseBlue,
        'themeStudio',
        null,
      );
      await child.flushPersistence();
      expect(owner.persistenceError, isNull);
      expect(child.persistenceError, isNull);
      final state =
          jsonDecode(
                await File(
                  '${directory.path}/orion-workspace.json',
                ).readAsString(),
              )
              as Map;
      expect(
        ((state['interfacePreferences']
                as Map)[InterfacePreset.synapseBlue.name]
            as Map)['themeStudio'],
        isNull,
      );
    },
  );

  test(
    'native codec preserves optimistic IDs across insert reorder close and last replacement',
    () async {
      final owner = OrionController(persistChanges: false, useMacSploit: false);
      final child = _mirror(owner);
      addTearDown(() {
        child.dispose();
        owner.dispose();
      });
      final original = child.activeDocumentId;
      final next = child.newDocument(name: 'source.lua', content: 'original');
      child.renameDocument(next.id, 'renamed.lua');
      child.updateDocumentContent(next.id, 'print("kept draft")');
      child.reorderDocuments([next.id, original]);
      await child.flushCommands();
      expect(owner.documents.map((d) => d.id), [next.id, original]);
      expect(owner.activeDocument.name, 'renamed.lua');
      expect(owner.activeDocument.content, 'print("kept draft")');
      expect(owner.activeDocument.isDirty, true);
      child.closeDocument(original);
      child.closeDocument(next.id);
      final replacement = child.activeDocumentId;
      child.renameDocument(replacement, 'replacement.lua');
      await child.flushCommands();
      expect(owner.documents.length, 1);
      expect(owner.activeDocumentId, replacement);
      expect(owner.activeDocument.name, 'replacement.lua');
      expect(owner.activeDocument.content, '');
      expect(owner.activeDocument.isDirty, false);
    },
  );

  test(
    'native file import replaces the undocked document and save returns real metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orion-companion-gateway-files-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/imported.lua');
      await source.writeAsString('print("from disk")\n');
      final owner = OrionController(persistChanges: false, useMacSploit: false);
      final fixed = owner.activeDocumentId;
      owner.newDocument(name: 'other.lua', content: 'leave this intact');
      final primaryActive = owner.activeDocumentId;
      owner.setDocumentDetached(fixed, true);
      final child = _mirror(owner, documentId: fixed);
      addTearDown(() {
        child.dispose();
        owner.dispose();
      });
      final imported = await child.importDocumentFromPath(
        source.path,
        replaceId: fixed,
      );
      expect(imported!.id, fixed);
      expect(imported.filePath, source.path);
      expect(child.activeDocumentId, fixed);
      expect(child.activeDocument.content, 'print("from disk")\n');
      expect(owner.activeDocumentId, primaryActive);
      expect(owner.detachedDocumentIds, {fixed});
      child.updateDocumentContent(fixed, 'print("saved through owner")');
      expect(await child.saveDocument(), true);
      await child.flushCommands();
      expect(await source.readAsString(), 'print("saved through owner")');
      expect(child.activeDocument.savedContent, 'print("saved through owner")');
      expect(child.activeDocument.isDirty, false);
      expect(owner.activeDocumentId, primaryActive);
      expect(
        owner.documents.singleWhere((d) => d.id == fixed).filePath,
        source.path,
      );
      expect(
        owner.documents.singleWhere((d) => d.name == 'other.lua').content,
        'leave this intact',
      );
    },
  );

  test(
    'native settings patch merges source theme colors and persists on the owner',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orion-companion-gateway-prefs-',
      );
      final owner = OrionController(storageDirectory: directory);
      await owner.initialize();
      owner.updateSynapsePreferences(
        themeColors: {'editor.background': 0xff112233},
      );
      final child = _mirror(owner);
      addTearDown(() async {
        child.dispose();
        owner.dispose();
        await owner.flushPersistence();
        await directory.delete(recursive: true);
      });
      child.updateSynapsePreferences(
        themeAccent: const Color(0xff4488cc),
        themeBackground: const Color(0xff202124),
        compactTabs: true,
        themeColors: {'editor.foreground': 0xffeeeeee},
      );
      child.setInterfacePreference(InterfacePreset.krnl, 'alwaysOnTop', true);
      child.setInterfacePreference(InterfacePreset.synapseX, 'theme', {
        'name': 'custom',
        'colors': [0xff102030, 0xff405060],
      });
      child.setUiScale(1.2);
      await child.flushPersistence();
      await owner.flushPersistence();
      final state =
          jsonDecode(
                await File(
                  '${directory.path}/orion-workspace.json',
                ).readAsString(),
              )
              as Map;
      final colors = (state['synapsePreferences'] as Map)['themeColors'] as Map;
      expect(colors['editor.background'], 0xff112233);
      expect(colors['editor.foreground'], 0xffeeeeee);
      expect(colors['accent.primary'], 0xff4488cc);
      expect(colors['shell.pageBg'], 0xff202124);
      expect(colors['shell.contentBg'], 0xff202124);
      expect((state['synapsePreferences'] as Map)['compactTabs'], true);
      expect(state['uiScale'], 1.2);
      expect(
        owner.getInterfacePreferences(InterfacePreset.krnl)['alwaysOnTop'],
        true,
      );
      expect(child.getInterfacePreferences(InterfacePreset.synapseX)['theme'], {
        'name': 'custom',
        'colors': [0xff102030, 0xff405060],
      });
    },
  );

  test(
    'native remote script maps retain source and share favorites and honest execution status',
    () async {
      final owner = OrionController(persistChanges: false, useMacSploit: false);
      final child = _mirror(owner);
      addTearDown(() {
        child.dispose();
        owner.dispose();
      });
      const script = RemoteScript(
        id: 'bundled-source',
        provider: ScriptProvider.scriptBlox,
        title: 'Source script',
        game: 'Test',
        description: 'An offline payload used to verify the native codec.',
        externalUrl: 'https://scriptblox.com/script/bundled-source',
        body: 'print("exact source")\n-- preserve bytes',
      );
      child.toggleRemoteFavorite(script);
      await child.flushCommands();
      expect(owner.isRemoteFavorite(script.key), true);
      expect(child.isRemoteFavorite(script.key), true);
      expect(owner.remoteFavorites.single.body, isNull);
      expect(await child.loadRemoteScript(script), script.body);
      final document = await child.openRemoteScript(script);
      await child.flushCommands();
      expect(owner.activeDocumentId, document!.id);
      expect(owner.activeDocument.content, script.body);
      await child.executeRemoteScript(script);
      await child.flushCommands();
      expect(owner.activities.first.title, 'No clients connected');
      expect(child.activities.first.title, 'No clients connected');
      child.clearActivities();
      await child.flushCommands();
      expect(owner.activities, isEmpty);
      expect(child.activities, isEmpty);
    },
  );
}
