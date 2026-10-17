import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/file_paths.dart';
import 'package:orion/models/local_script.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/services/script_library_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_overlay.dart';
import 'package:orion/widgets/script_code_text.dart';
import 'package:orion/widgets/script_explorer.dart';

void main() {
  testWidgets(
    'Special continuously moves while ordinary code text stays still',
    (tester) async {
      Future<void> mount(ScriptColorCode code) => tester.pumpWidget(
        MaterialApp(
          theme: orionTheme(Brightness.dark, Colors.blue),
          home: Scaffold(
            body: ScriptCodeText(text: 'Orion Bridge.lua', code: code),
          ),
        ),
      );
      await mount(ScriptColorCode.special);
      await tester.pump(const Duration(milliseconds: 10));
      final before = tester.widget<ShaderMask>(find.byType(ShaderMask));
      await tester.pump(const Duration(seconds: 1));
      final after = tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(identical(before, after), isFalse);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await mount(ScriptColorCode.blue);
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester.widget<Text>(find.text('Orion Bridge.lua')).style!.color,
        const Color(0xff87b8ff),
      );
    },
  );

  testWidgets('reduced motion freezes Special without removing its gradient', (
    tester,
  ) async {
    Future<void> mount({bool reduced = false, bool systemReduced = false}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: orionTheme(Brightness.dark, Colors.blue),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: systemReduced),
              child: ScriptCodeText(
                text: 'Special',
                code: ScriptColorCode.special,
                reducedMotion: reduced,
              ),
            ),
          ),
        );
    await mount();
    await tester.pump(const Duration(seconds: 1));
    await mount(reduced: true);
    await tester.pumpAndSettle();
    var still = tester.widget<ShaderMask>(find.byType(ShaderMask));
    await tester.pump(const Duration(seconds: 1));
    expect(identical(still, tester.widget(find.byType(ShaderMask))), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await mount(systemReduced: true);
    await tester.pumpAndSettle();
    still = tester.widget<ShaderMask>(find.byType(ShaderMask));
    await tester.pump(const Duration(seconds: 1));
    expect(identical(still, tester.widget(find.byType(ShaderMask))), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await mount();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  group('filesystem explorer', () {
    late Directory directory;
    late ScriptLibraryService library;
    late OrionController controller;
    late List<String> opened;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('orion-explorer-test-');
      library = ScriptLibraryService(
        directory: directory,
        bridgeSourceLoader: () async => 'print("bridge")',
      );
      await library.initialize();
      controller = OrionController(persistChanges: false)
        ..setReducedMotion(true);
      opened = [];
    });

    tearDown(() async {
      library.dispose();
      controller.dispose();
      await directory.delete(recursive: true);
    });

    Future<void> mount(WidgetTester tester, {double width = 166}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OrionOverlayTheme(
            controller: controller,
            builder: (context) => Scaffold(
              body: SizedBox(
                width: width,
                height: 350,
                child: ScriptExplorer(
                  controller: controller,
                  library: library,
                  onOpenScript: (path) async => opened.add(path),
                  onLibrary: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('filter opens matching ancestors without changing expansion', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await library.createScript('Folder/Nested/Match.lua');
        await Directory('${directory.path}/Empty').create();
        await library.refresh();
      });
      await mount(tester);
      expect(
        find.byKey(const ValueKey('script-file:Folder/Nested/Match.lua')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('script-folder:Empty')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('script-filter')),
        'MATCH',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('script-folder:Folder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-folder:Folder/Nested')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-file:Folder/Nested/Match.lua')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('script-folder:Special')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('script-filter')), '');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('script-file:Folder/Nested/Match.lua')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('script-file:Special/Orion Bridge.lua')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('right-click Code offers six swatches and persists a choice', (
      tester,
    ) async {
      await mount(tester);
      final row = find.byKey(
        const ValueKey('script-file:Special/Orion Bridge.lua'),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(row),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Code'), findsOneWidget);
      expect(find.byType(ScriptCodeSwatch), findsNothing);
      await tester.tap(find.text('Code'));
      await tester.pumpAndSettle();
      for (final code in ScriptColorCode.values) {
        expect(
          find.byKey(ValueKey('script-code:${code.name}')),
          findsOneWidget,
        );
      }
      expect(find.byType(ScriptCodeSwatch), findsNWidgets(6));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('script-code:special')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      controller.setOrionTheme(
        OrionThemePreferences(
          accent: const Color(0xfff1bd86),
          overrides: const {'ink': Color(0xffffe8d1)},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        OrionColors.of(tester.element(find.byType(Dialog))).accent,
        const Color(0xfff1bd86),
      );
      expect(
        tester.widget<Text>(find.text('None')).style!.color,
        const Color(0xffffe8d1),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('script-code:green')));
        // Native filesystem completion must run on the real clock before
        // advancing widget animations with pumpAndSettle's fake clock.
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (library.entries.singleWhere((e) => !e.isDirectory).code !=
                ScriptColorCode.green &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(
        library.entries.singleWhere((e) => !e.isDirectory).code,
        ScriptColorCode.green,
      );
      expect(opened, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('New script file creates a real nested file and opens it', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.byTooltip('New script file'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('script-create-name')),
        'Utilities/fresh.luau',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('script-create-confirm')));
      });
      // File I/O and directory watches use real time; the guarded dialog must
      // also finish its route transition before returning the created entry.
      for (
        var frame = 0;
        frame < 150 && (opened.isEmpty || library.loading);
        frame++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(opened, isNotEmpty, reason: 'The created script must open');
      await tester.pumpAndSettle();
      expect(
        FilePaths.same(opened.single, '${directory.path}/Utilities/fresh.luau'),
        isTrue,
      );
      expect(await tester.runAsync(() => File(opened.single).exists()), isTrue);
      expect(
        find.byKey(const ValueKey('script-file:Utilities/fresh.luau')),
        findsOneWidget,
      );
      expect(controller.documents, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('compact footer stays usable and tooltips fit the explorer', (
      tester,
    ) async {
      controller.setOrionCompactMode(true);
      await mount(tester, width: 148);
      expect(
        find.byKey(const ValueKey('script-open-folder')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-hub')).hitTestable(),
        findsOneWidget,
      );
      final row = find.byKey(
        const ValueKey('script-file:Special/Orion Bridge.lua'),
      );
      final pathTooltip = tester.widget<Tooltip>(
        find.descendant(of: row, matching: find.byType(Tooltip)),
      );
      expect(pathTooltip.constraints!.maxWidth, lessThanOrEqualTo(124));
      expect(
        FilePaths.same(
          pathTooltip.message!,
          '${directory.path}/Special/Orion Bridge.lua',
        ),
        isTrue,
      );
      final special = tester.widget<ScriptCodeText>(
        find.descendant(
          of: find.byKey(const ValueKey('script-folder:Special')),
          matching: find.byType(ScriptCodeText),
        ),
      );
      expect(special.code, ScriptColorCode.special);
      expect(tester.takeException(), isNull);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        FilePaths.same(
          opened.single,
          '${directory.path}/Special/Orion Bridge.lua',
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
