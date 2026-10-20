import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/state/orion_controller.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('orion-test-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'restores unsaved documents, active tab, favorites, and preferences',
    () async {
      final first = OrionController(storageDirectory: temporaryDirectory);
      await first.initialize();
      final document = first.newDocument(
        name: 'my-orbit.lua',
        content: '-- start',
      );
      first.updateDocumentContent(document.id, '-- a new idea\nprint("hello")');
      first.toggleFavorite('glass-panel');
      first.setThemeMode(ThemeMode.light);
      first.setAccent(OrionAccent.lavender);
      first.setEditorFontSize(17);
      first.setWordWrap(true);
      first.setReducedMotion(true);
      first.completeIntro();
      await first.flushPersistence();
      first.dispose();
      await first.flushPersistence();

      final restored = OrionController(storageDirectory: temporaryDirectory);
      await restored.initialize();
      expect(restored.documents, hasLength(2));
      expect(restored.activeDocument.id, document.id);
      expect(restored.activeDocument.content, '-- a new idea\nprint("hello")');
      expect(restored.activeDocument.isDirty, isTrue);
      expect(restored.isFavorite('glass-panel'), isTrue);
      expect(restored.themeMode, ThemeMode.light);
      expect(restored.accent, OrionAccent.lavender);
      expect(restored.editorFontSize, 17);
      expect(restored.wordWrap, isTrue);
      expect(restored.reducedMotion, isTrue);
      expect(restored.introCompleted, isTrue);
      restored.dispose();
      await restored.flushPersistence();
    },
  );

  test('persists the Linux-only Relapse support preference', () async {
    if (!Platform.isLinux) return;
    final first = OrionController(storageDirectory: temporaryDirectory);
    await first.initialize();
    first.setRelapseSupportEnabled(true);
    await first.flushPersistence();
    first.dispose();
    await first.flushPersistence();

    final restored = OrionController(storageDirectory: temporaryDirectory);
    await restored.initialize();
    expect(restored.relapseSupportAvailable, isTrue);
    expect(restored.relapseSupportEnabled, isTrue);
    restored.dispose();
    await restored.flushPersistence();
  });

  test(
    'saving writes real files and reopening selects the existing tab',
    () async {
      final controller = OrionController(
        storageDirectory: temporaryDirectory,
        useMacSploit: false,
      );
      await controller.initialize();
      final document = controller.newDocument(content: 'print("first")');
      controller.updateDocumentContent(document.id, 'print("saved")');
      final path = '${temporaryDirectory.path}/saved.lua';

      expect(await controller.saveDocumentToPath(document.id, path), isTrue);
      expect(await File(path).readAsString(), 'print("saved")');
      expect(controller.activeDocument.name, 'saved.lua');
      expect(controller.activeDocument.isDirty, isFalse);

      controller.newDocument();
      final count = controller.documents.length;
      final opened = await controller.openFileAtPath(path);
      expect(opened?.id, document.id);
      expect(controller.documents, hasLength(count));
      expect(controller.activeDocument.id, document.id);
      controller.dispose();
      await controller.flushPersistence();
    },
  );

  test(
    'renamed file tabs keep their label through Save and recovery',
    () async {
      final controller = OrionController(
        storageDirectory: temporaryDirectory,
        useMacSploit: false,
      );
      await controller.initialize();
      final document = controller.newDocument(content: 'print("original")');
      final path = '${temporaryDirectory.path}/disk-name.lua';
      await controller.saveDocumentToPath(document.id, path);
      controller.renameDocument(document.id, 'workspace-name.lua');
      controller.updateDocumentContent(document.id, 'print("updated")');
      expect(await controller.saveDocument(document.id), isTrue);
      expect(controller.activeDocument.name, 'workspace-name.lua');
      expect(controller.activeDocument.filePath, path);
      expect(await File(path).readAsString(), 'print("updated")');
      expect(controller.activeDocument.isDirty, isFalse);
      await controller.flushPersistence();
      controller.dispose();
      await controller.flushPersistence();

      final restored = OrionController(storageDirectory: temporaryDirectory);
      await restored.initialize();
      expect(restored.activeDocument.name, 'workspace-name.lua');
      expect(restored.activeDocument.filePath, path);
      final newPath = '${temporaryDirectory.path}/new-destination.lua';
      await restored.saveDocumentToPath(document.id, newPath);
      expect(restored.activeDocument.name, 'new-destination.lua');
      restored.dispose();
      await restored.flushPersistence();
    },
  );

  test('library collection and text search compose correctly', () async {
    final controller = OrionController(
      storageDirectory: temporaryDirectory,
      useMacSploit: false,
    );
    await controller.initialize();
    controller.setCollection('Utilities');
    controller.setSearchQuery('motion');
    expect(controller.filteredLibraryItems.map((item) => item.id), [
      'easing-curves',
    ]);
    controller.setCollection('Favorites');
    expect(controller.filteredLibraryItems.map((item) => item.id), [
      'easing-curves',
    ]);
    controller.toggleFavorite('easing-curves');
    expect(controller.filteredLibraryItems, isEmpty);
    controller.dispose();
    await controller.flushPersistence();
  });

  test('closing the final tab leaves an editable empty document', () async {
    final controller = OrionController(
      storageDirectory: temporaryDirectory,
      useMacSploit: false,
    );
    await controller.initialize();
    controller.closeDocument(controller.activeDocument.id);
    expect(controller.documents, hasLength(1));
    expect(controller.activeDocument.name, 'untitled.lua');
    expect(controller.activeDocument.content, isEmpty);
    controller.updateDocumentContent(controller.activeDocument.id, '-- new');
    expect(controller.activeDocument.isDirty, isTrue);
    controller.dispose();
    await controller.flushPersistence();
  });

  test(
    'invalid stored state recovers and clamps persisted preferences',
    () async {
      final stateFile = File('${temporaryDirectory.path}/orion-workspace.json');
      await stateFile.writeAsString('{invalid JSON');
      final recovered = OrionController(storageDirectory: temporaryDirectory);
      await recovered.initialize();
      expect(recovered.documents, isNotEmpty);
      expect(recovered.persistenceError, isNotNull);
      expect(recovered.activities.first.severity, ActivitySeverity.warning);
      recovered.dispose();
      await recovered.flushPersistence();

      await stateFile.writeAsString(
        jsonEncode({
          'documents': [],
          'activeDocumentId': 'missing',
          'favoriteIds': ['missing', 'glass-panel'],
          'editorFontSize': 400,
          'themeMode': 'invalid',
        }),
      );
      final validated = OrionController(storageDirectory: temporaryDirectory);
      await validated.initialize();
      expect(validated.activeDocument.name, 'constellation.lua');
      expect(validated.editorFontSize, 22);
      expect(validated.themeMode, ThemeMode.dark);
      expect(validated.favoriteIds, {'glass-panel'});
      validated.dispose();
      await validated.flushPersistence();
    },
  );

  test(
    'execute and attach report missing bridge clients without pretending to execute',
    () async {
      final controller = OrionController(
        storageDirectory: temporaryDirectory,
        useMacSploit: false,
      );
      await controller.initialize();
      controller.updateDocumentContent(
        controller.activeDocument.id,
        'error("source must never be executed without an engine")',
      );
      controller.execute();
      expect(controller.activities.first.title, 'No clients connected');
      expect(controller.activities.first.kind, ActivityKind.execution);
      expect(controller.activities.first.severity, ActivitySeverity.warning);
      controller.attach();
      expect(controller.activities.first.title, 'Waiting for Orion Bridge');
      expect(controller.activities.first.severity, ActivitySeverity.info);
      final executionEntries = controller.activities.where(
        (entry) => entry.kind == ActivityKind.execution,
      );
      expect(executionEntries, hasLength(2));
      expect(
        executionEntries.any(
          (entry) => entry.severity == ActivitySeverity.success,
        ),
        isFalse,
      );
      controller.dispose();
      await controller.flushPersistence();
    },
  );

  test(
    'legacy simulated activity is removed when restoring the workspace',
    () async {
      final stateFile = File('${temporaryDirectory.path}/orion-workspace.json');
      await stateFile.writeAsString(
        jsonEncode({
          'activities': [
            {
              'id': 'legacy',
              'title': 'Preview complete',
              'detail': 'Demo finished successfully.',
              'kind': 'demo',
              'severity': 'success',
              'timestamp': DateTime.now().toIso8601String(),
            },
            ActivityEntry(
              id: 'current',
              title: 'No executor attached',
              detail: 'Executor attachment is not configured.',
              kind: ActivityKind.execution,
              severity: ActivitySeverity.warning,
              timestamp: DateTime.now(),
            ).toJson(),
          ],
        }),
      );
      final controller = OrionController(
        storageDirectory: temporaryDirectory,
        useMacSploit: false,
      );
      await controller.initialize();
      expect(controller.activities, hasLength(1));
      expect(controller.activities.first.id, 'current');
      controller.dispose();
      await controller.flushPersistence();
    },
  );

  test(
    'legacy bridge completion cleanup preserves all other history and persists its version',
    () async {
      const hex = 'Execution exec_a40bf9e87ef249f5b041d7d1e3d5d2cb completed.';
      const uuid =
          'Execution exec_a40bf9e8-7ef2-49f5-b041-d7d1e3d5d2cb completed.';
      Map<String, Object> activity(
        String id,
        String detail, {
        ActivityKind kind = ActivityKind.execution,
        ActivitySeverity severity = ActivitySeverity.info,
      }) => ActivityEntry(
        id: id,
        title: 'Player · User1',
        detail: detail,
        kind: kind,
        severity: severity,
        timestamp: DateTime.utc(2026),
      ).toJson();
      final stateFile = File('${temporaryDirectory.path}/orion-workspace.json');
      await stateFile.writeAsString(
        jsonEncode({
          'version': 2,
          'activities': [
            activity('old-hex', hex),
            activity('old-uuid', uuid),
            activity('print', 'hello world'),
            activity('warning', hex, severity: ActivitySeverity.warning),
            activity(
              'error',
              'Execution failed: syntax error',
              severity: ActivitySeverity.error,
            ),
            activity('workspace', hex, kind: ActivityKind.workspace),
            activity('not-an-id', 'Execution exec_user-text completed.'),
            activity('extra-text', '$hex extra user text'),
            activity('newline', '$hex\n'),
          ],
        }),
      );
      final controller = OrionController(
        storageDirectory: temporaryDirectory,
        useMacSploit: false,
      );
      await controller.initialize();
      expect(controller.activities.map((entry) => entry.id), [
        'print',
        'warning',
        'error',
        'workspace',
        'not-an-id',
        'extra-text',
        'newline',
      ]);
      await controller.flushPersistence();
      final saved = jsonDecode(await stateFile.readAsString()) as Map;
      expect(saved['bridgeConsoleVersion'], 1);
      expect(
        (saved['activities'] as List).map((entry) => (entry as Map)['id']),
        controller.activities.map((entry) => entry.id),
      );
      controller.dispose();
      await controller.flushPersistence();
    },
  );

  test(
    'versioned history keeps genuine completion-shaped prints across recovery and companion snapshots',
    () async {
      const printedText =
          'Execution exec_a40bf9e87ef249f5b041d7d1e3d5d2cb completed.';
      final printed = ActivityEntry(
        id: 'genuine-print',
        title: 'Player · User1',
        detail: printedText,
        kind: ActivityKind.execution,
        severity: ActivitySeverity.info,
        timestamp: DateTime.utc(2026),
      );
      final stateFile = File('${temporaryDirectory.path}/orion-workspace.json');
      await stateFile.writeAsString(
        jsonEncode({
          'version': 2,
          'bridgeConsoleVersion': 1,
          'activities': [printed.toJson()],
        }),
      );
      final controller = OrionController(
        storageDirectory: temporaryDirectory,
        useMacSploit: false,
      );
      await controller.initialize();
      expect(controller.activities.single.id, 'genuine-print');
      expect(controller.activities.single.detail, printedText);
      final companion = OrionController(persistChanges: false);
      companion.applyWindowState(controller.exportWindowState());
      expect(companion.activities.single.id, 'genuine-print');
      expect(companion.activities.single.detail, printedText);
      expect(companion.exportWindowState()['bridgeConsoleVersion'], 1);
      companion.dispose();
      controller.dispose();
      await controller.flushPersistence();
      final restored = OrionController(storageDirectory: temporaryDirectory);
      await restored.initialize();
      expect(restored.activities.single.detail, printedText);
      restored.dispose();
      await restored.flushPersistence();
    },
  );
}
