import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/screens/workspace_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

const _capture = ValueKey('workspace-tab-performance-capture');
const _captureDirectory = String.fromEnvironment('ORION_TAB_CAPTURE_DIR');
const _measureOnly = bool.fromEnvironment('ORION_TAB_MEASURE_ONLY');

class _CountedController extends OrionController {
  _CountedController() : super(persistChanges: false);

  int documentReads = 0;
  int activityReads = 0;

  @override
  List<EditorDocument> get documents {
    documentReads++;
    return super.documents;
  }

  @override
  List<ActivityEntry> get activities {
    activityReads++;
    return super.activities;
  }
}

void main() {
  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  Future<_CountedController> mount(
    WidgetTester tester, {
    required int count,
    OrionThemePreferences? preferences,
    bool compact = false,
  }) async {
    final size = compact ? const Size(720, 480) : const Size(900, 600);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _CountedController()..setReducedMotion(true);
    c.renameDocument(c.activeDocumentId, 'script-01.lua');
    c.updateDocumentContent(c.activeDocumentId, 'print("Hello world")');
    for (var index = 1; index < count; index++) {
      c.newDocument(
        name: 'script-${(index + 1).toString().padLeft(2, '0')}.lua',
        content: 'print("Hello world")',
      );
    }
    c.selectDocument(c.documents.first.id);
    if (preferences != null) c.setOrionTheme(preferences);
    final theme = orionTheme(
      Brightness.dark,
      c.orionTheme.accent,
      preferences: c.orionTheme,
      reducedMotion: true,
      compactMode: compact,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: WorkspaceScreen(
              key: ValueKey(c),
              controller: c,
              onLibrary: () {},
              onSave: () {},
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
    return c;
  }

  testWidgets('tab document snapshots stay constant as the tab count grows', (
    tester,
  ) async {
    final results = <String, int>{};
    for (final count in [2, 12, 60]) {
      final c = await mount(tester, count: count);
      c.documentReads = 0;
      c.updateDocumentContent(c.activeDocumentId, 'print("edited")');
      await tester.pumpAndSettle();
      results['$count tabs'] = c.documentReads;
      if (!_measureOnly) {
        expect(c.documentReads, lessThanOrEqualTo(2), reason: '$count tabs');
      }
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('code-editor')))
            .controller!
            .text,
        'print("edited")',
      );
      expect(tester.takeException(), isNull);
    }
    if (_captureDirectory.isNotEmpty) {
      await tester.runAsync(() async {
        final directory = Directory(_captureDirectory)
          ..createSync(recursive: true);
        File('${directory.path}/document-reads.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(results),
        );
      });
    }
  });

  testWidgets(
    'collapsed console skips history copies and still opens on output',
    (tester) async {
      final c = await mount(tester, count: 12);
      c.activityReads = 0;
      c.updateDocumentContent(c.activeDocumentId, 'print("edited")');
      await tester.pumpAndSettle();
      expect(c.activityReads, 0);
      expect(find.text('Client output appears here.'), findsNothing);

      c.execute();
      await tester.pumpAndSettle();
      expect(find.text('No clients connected'), findsOneWidget);
      expect(c.activityReads, 1);

      await tester.tap(find.text('Console'));
      await tester.pumpAndSettle();
      c.activityReads = 0;
      c.updateDocumentContent(c.activeDocumentId, 'print("more edits")');
      c.newDocument(name: 'another.lua', content: 'print("new")');
      await tester.pumpAndSettle();
      expect(c.activityReads, 0);
      expect(find.text('No clients connected'), findsNothing);

      c.execute();
      await tester.pumpAndSettle();
      expect(find.text('No clients connected'), findsWidgets);
      c.clearActivities();
      await tester.pumpAndSettle();
      expect(find.text('Client output appears here.'), findsOneWidget);
      expect(find.text('No clients connected'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  if (_captureDirectory.isNotEmpty) {
    for (final preset in OrionThemePreferences.builtInPresets.take(5)) {
      for (final compact in [false, true]) {
        for (final count in [2, 12]) {
          final name = '${preset.id}-${compact ? 'compact' : 'normal'}-$count';
          testWidgets('workspace tab pixel fixture $name', (tester) async {
            await mount(
              tester,
              count: count,
              preferences: preset.preferences,
              compact: compact,
            );
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_capture),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory(_captureDirectory)
                ..createSync(recursive: true);
              File(
                '${directory.path}/$name.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
              image.dispose();
            });
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
