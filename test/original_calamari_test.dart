import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/original_ports/calamari_controls.dart';
import 'package:orion/original_ports/calamari_shell.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _Controller extends OrionController {
  int opened = 0;
  String? saved;
  String? executedBody;
  @override
  Future<void> flushPersistence() async {}
  @override
  Future<EditorDocument?> openFile() async {
    opened++;
    return newDocument(name: 'disk.lua', content: 'print("disk")');
  }

  @override
  Future<bool> saveDocument([String? id]) async {
    saved = activeDocument.content;
    return true;
  }

  @override
  void execute({String? source, String? name}) {
    executedBody = source ?? activeDocument.content;
    super.execute(source: source, name: name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('OriginalArial')..addFont(
          rootBundle.load('assets/original_fonts/LiberationSans-Regular.ttf'),
        ))
        .load();
    await rootBundle.loadString('assets/original_calamari/scripts/DexRaw.lua');
  });
  Future<void> mount(
    WidgetTester tester,
    _Controller c, {
    VoidCallback? back,
    GlobalKey<CalamariShellState>? key,
    bool bridge = false,
    Size size = const Size(521, 365),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (ctx, child) =>
            UiScaleViewport(scale: c.uiScale, child: child!),
        home: CalamariShell(
          key: key,
          controller: c,
          nativeWindow: false,
          onBackToOrion: back ?? () {},
          bridgeReady: bridge,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester, _Controller c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets(
    'original Calamari login preserves source imagery and accepts blank local login',
    (tester) async {
      final c = _Controller();
      await mount(tester, c);
      expect(find.text('Calamari-M is updated'), findsOneWidget);
      expect(find.text('© 2020 Inspect'), findsOneWidget);
      expect(find.text("Watch cutedoot's showcase"), findsOneWidget);
      expect(find.byKey(const ValueKey('code-editor')), findsNothing);
      final username = tester.getRect(
            find.byKey(const ValueKey('calamari-username')),
          ),
          password = tester.getRect(
            find.byKey(const ValueKey('calamari-password')),
          ),
          login = tester.getRect(find.byKey(const ValueKey('calamari-login')));
      expect(username.width, 236);
      expect(username.height, 32);
      expect(username, const Rect.fromLTWH(283, 200, 236, 32));
      expect(password.top - username.top, 27);
      expect(login.top - password.top, 28);
      expect(login.height, 23);
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(
        c.getInterfacePreferences(
          InterfacePreset.calamari,
        )['localLoginCompleted'],
        true,
      );
      expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
      expect(find.text('Executor'), findsOneWidget);
      expect(find.text('Tools & Tricks'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'executor and tools retain source button dimensions and source text font',
    (tester) async {
      final c = _Controller()
        ..setInterfacePreference(
          InterfacePreset.calamari,
          'localLoginCompleted',
          true,
        );
      await mount(tester, c);
      final editor = tester.getRect(
        find.byKey(const ValueKey('calamari-editor-viewport')),
      );
      expect(editor.width, 353);
      expect(editor.height, 207);
      final textfield = tester.widget<TextField>(
        find.byKey(const ValueKey('code-editor')),
      );
      expect(textfield.style!.fontFamily, 'OriginalArial');
      expect(textfield.style!.fontSize, 13);
      expect(editor, const Rect.fromLTWH(5, 63, 353, 207));
      expect(
        tester.getRect(find.widgetWithText(CalamariButton, 'Dex by Moon')),
        const Rect.fromLTWH(376, 85, 85, 23),
      );
      final play = tester.getRect(
            find.byKey(const ValueKey('calamari-execute')),
          ),
          paste = tester.getRect(find.byKey(const ValueKey('calamari-paste')));
      expect(play.size, const Size(25, 28));
      expect(paste.top - play.top, 31);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('calamari-executor-tab')))
            .size,
        const Size(78, 23),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('calamari-tools-tab'))).size,
        const Size(110, 23),
      );
      expect(
        tester
            .widget<CalamariButton>(
              find.byKey(const ValueKey('calamari-executor-tab')),
            )
            .selected,
        true,
      );
      await tester.tap(find.text('Tools & Tricks'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CalamariButton>(
              find.byKey(const ValueKey('calamari-tools-tab')),
            )
            .selected,
        true,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('calamari-number'))).size,
        const Size(105, 32),
      );
      expect(find.text('Back to Orion'), findsOneWidget);
      expect(
        tester.getRect(find.widgetWithText(CalamariButton, 'Set WalkSpeed')),
        const Rect.fromLTWH(14, 124, 98, 23),
      );
      expect(
        tester.getRect(find.widgetWithText(CalamariButton, 'Reset').first),
        const Rect.fromLTWH(157, 124, 39, 23),
      );
      for (final label in [
        'Set WalkSpeed',
        'Set JumpPower',
        'Set HipHeight',
        'Set Gravity (Local)',
        'Enable Fly',
        'Enable Noclip',
        'Give Btools',
        'Click to TP',
        'c00lgui',
        'RoXploit 6.0',
        'TopK3k',
        'FE Animation GUI',
        'Headspin',
        'Dex v4',
        'Lustris Sword',
        'True Hero Ultima',
        'Double Tails Music',
        'God Claws',
        'Starglitcher',
        'Wings Script',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'native workspace edits persist across tools and back without backend simulation',
    (tester) async {
      final c = _Controller()
        ..setInterfacePreference(
          InterfacePreset.calamari,
          'localLoginCompleted',
          true,
        );
      var backs = 0;
      await mount(tester, c, back: () => backs++);
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'print("carry")',
      );
      expect(c.activeDocument.content, 'print("carry")');
      await tester.tap(find.byKey(const ValueKey('calamari-execute')));
      await tester.pumpAndSettle();
      expect(c.activities.any((a) => a.kind == ActivityKind.execution), false);
      expect(
        find.text('please execute the Orion Bridge in your executor.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tools & Tricks'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('calamari-number')),
          matching: find.byType(TextField),
        ),
        '175',
      );
      await tester.tap(find.text('Set WalkSpeed'));
      await tester.pumpAndSettle();
      expect(
        c.getInterfacePreferences(InterfacePreset.calamari)['numberValue'],
        '175',
      );
      expect(c.activities.any((a) => a.kind == ActivityKind.execution), false);
      await tester.tap(find.text('Executor'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('code-editor')))
            .controller!
            .text,
        'print("carry")',
      );
      await tester.tap(find.text('Tools & Tricks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to Orion'));
      expect(backs, 1);
      expect(c.activeDocument.isDirty, true);
      await cleanup(tester, c);
    },
  );
  testWidgets('local login never stores username or password', (tester) async {
    final c = _Controller();
    await mount(tester, c);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('calamari-username')),
        matching: find.byType(TextField),
      ),
      'local-user',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('calamari-password')),
        matching: find.byType(TextField),
      ),
      'local-secret',
    );
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(
      c.getInterfacePreferences(InterfacePreset.calamari).keys,
      contains('localLoginCompleted'),
    );
    expect(
      c.getInterfacePreferences(InterfacePreset.calamari).values,
      isNot(contains('local-user')),
    );
    expect(
      c.getInterfacePreferences(InterfacePreset.calamari).values,
      isNot(contains('local-secret')),
    );
    await cleanup(tester, c);
  });
  testWidgets(
    'source plain editor scrolls long lines horizontally without wrapping',
    (tester) async {
      final c = _Controller()
        ..setInterfacePreference(
          InterfacePreset.calamari,
          'localLoginCompleted',
          true,
        );
      await mount(tester, c);
      final body =
          'local long_line = "${List.filled(200, 'wide').join()}"\nprint(long_line)';
      await tester.enterText(find.byKey(const ValueKey('code-editor')), body);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.byKey(const ValueKey('calamari-editor-viewport')),
      );
      final editable = tester.getRect(
        find.byKey(const ValueKey('code-editor')),
      );
      expect(viewport, const Rect.fromLTWH(5, 63, 353, 207));
      expect(editable.width, greaterThan(viewport.width));
      expect(c.activeDocument.content, body);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'source preset controls retain the exact bundled script for a future bridge',
    (tester) async {
      final c = _Controller()
        ..setInterfacePreference(
          InterfacePreset.calamari,
          'localLoginCompleted',
          true,
        );
      await mount(tester, c, bridge: true);
      final expected = (await tester.runAsync(
        () => rootBundle.loadString(
          'assets/original_calamari/scripts/DexRaw.lua',
        ),
      ))!;
      final id = c.activeDocumentId, before = c.activeDocument.content;
      await tester.runAsync(() async {
        await tester.tap(find.text('Dex by Moon'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.executedBody, expected);
      expect(c.activeDocumentId, id);
      expect(c.activeDocument.content, before);
      expect(c.activities.first.title, 'No clients connected');
      await cleanup(tester, c);
    },
  );
  testWidgets('clipboard and source shortcuts use actual local workspace', (
    tester,
  ) async {
    final clipboard = SystemChannels.platform;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      clipboard,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': 'print("clipboard")'}
          : call.method == 'Clipboard.hasStrings'
          ? {'value': true}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        clipboard,
        null,
      ),
    );
    final c = _Controller()
      ..setInterfacePreference(
        InterfacePreset.calamari,
        'localLoginCompleted',
        true,
      );
    final key = GlobalKey<CalamariShellState>();
    await mount(tester, c, key: key);
    await tester.tap(find.byKey(const ValueKey('calamari-paste')));
    await tester.pumpAndSettle();
    expect(c.activeDocument.content, 'print("clipboard")');
    key.currentState!.handleEditorShortcut('save');
    await tester.pumpAndSettle();
    expect(c.saved, 'print("clipboard")');
    key.currentState!.handleEditorShortcut('open');
    await tester.pumpAndSettle();
    expect(c.opened, 1);
    expect(c.activeDocument.content, 'print("disk")');
    await cleanup(tester, c);
  });
  testWidgets(
    'source status remains selectable while the client manager opens',
    (tester) async {
      final c = _Controller();
      await mount(tester, c);
      await tester.tap(find.text('Click here to buy this'));
      await tester.tap(find.text('Click to Join the Discord'));
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      final finder = find.byKey(const ValueKey('calamari-output'));
      final output = tester.widget<TextField>(finder);
      expect(output.readOnly, true);
      expect(
        output.controller!.text,
        'please execute the Orion Bridge in your executor.',
      );
      expect(tester.getRect(finder), const Rect.fromLTWH(40, 278, 322, 85));
      await tester.tap(find.byKey(const ValueKey('calamari-clients')));
      await tester.pumpAndSettle();
      expect(find.text('Client manager'), findsOneWidget);
      await tester.tap(find.byTooltip('Close client manager'));
      await tester.pumpAndSettle();
      expect(
        output.controller!.text,
        'please execute the Orion Bridge in your executor.',
      );
      expect(c.activities.any((a) => a.kind == ActivityKind.execution), false);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'source numeric actions use invariant literals and retain editor state',
    (tester) async {
      final c = _Controller()
        ..setInterfacePreference(
          InterfacePreset.calamari,
          'localLoginCompleted',
          true,
        );
      await mount(tester, c, bridge: true);
      final editor = find.byKey(const ValueKey('code-editor'));
      await tester.enterText(editor, 'print("retain selection")');
      final editable = tester.widget<TextField>(editor).controller!;
      editable.selection = const TextSelection(baseOffset: 7, extentOffset: 13);
      await tester.tap(find.text('Tools & Tricks'));
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(
        find.byKey(const ValueKey('code-editor'), skipOffstage: false),
        findsOneWidget,
      );
      final number = find.descendant(
        of: find.byKey(const ValueKey('calamari-number')),
        matching: find.byType(TextField),
      );
      await tester.enterText(number, '175');
      await tester.tap(find.text('Set WalkSpeed'));
      await tester.pumpAndSettle();
      expect(
        c.executedBody,
        "game:GetService('Players').LocalPlayer.Character.Humanoid.WalkSpeed=175",
      );
      await tester.enterText(number, '7.25');
      await tester.tap(find.text('Set JumpPower'));
      await tester.pumpAndSettle();
      expect(
        c.executedBody,
        "game:GetService('Players').LocalPlayer.Character.Humanoid.JumpHeight=7.25; game:GetService('Players').LocalPlayer.Character.Humanoid.JumpPower=7.25",
      );
      await tester.tap(find.text('Executor'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editor).controller, same(editable));
      expect(
        editable.selection,
        const TextSelection(baseOffset: 7, extentOffset: 13),
      );
      expect(c.activeDocument.content, 'print("retain selection")');
      await cleanup(tester, c);
    },
  );
  testWidgets('login executor tools and back fit the global GUI sizes', (
    tester,
  ) async {
    for (final scale in [.8, 1.25]) {
      final c = _Controller()..setUiScale(scale);
      await mount(tester, c);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Tools & Tricks'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final back = tester.getRect(
        find.byKey(const ValueKey('calamari-back-to-orion')),
      );
      expect(back.right, lessThanOrEqualTo(521));
      expect(back.bottom, lessThanOrEqualTo(365));
      await cleanup(tester, c);
    }
  });
}
