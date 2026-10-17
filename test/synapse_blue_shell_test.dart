import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_blue/blue_controls.dart';
import 'package:orion/synapse_blue/synapse_blue_shell.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _Controller extends OrionController {
  int opened = 0, executed = 0;
  String? saved;
  @override
  Future<void> flushPersistence() async {}
  @override
  Future<EditorDocument?> openFile() async {
    opened++;
    return newDocument(name: 'opened.lua', content: 'print("opened")');
  }

  @override
  Future<bool> saveDocument([String? id]) async {
    saved = documents
        .firstWhere((d) => d.id == (id ?? activeDocumentId))
        .content;
    return true;
  }

  @override
  void execute({String? source, String? name}) => executed++;
}

Future<void> _mount(
  WidgetTester tester,
  _Controller c, {
  GlobalKey<SynapseBlueShellState>? key,
  VoidCallback? back,
}) async {
  tester.view.physicalSize = const Size(714, 393);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          UiScaleViewport(scale: c.uiScale, child: child!),
      home: SynapseBlueShell(
        key: key,
        controller: c,
        nativeWindow: false,
        playIntro: false,
        onBackToOrion: back ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is BlueButton && w.label == label);

void main() {
  setUpAll(() async {
    final inter = FontLoader('SynapseInter');
    for (final path in [
      'assets/synapse_blue/fonts/Inter-Light.ttf',
      'assets/synapse_v3/fonts/Inter-Regular.ttf',
      'assets/synapse_v3/fonts/Inter-Semibold.ttf',
      'assets/synapse_blue/fonts/Inter-Black.ttf',
    ]) {
      inter.addFont(rootBundle.load(path));
    }
    await inter.load();
    await (FontLoader(
      'JetBrainsMono',
    )..addFont(rootBundle.load('assets/fonts/JetBrainsMono.ttf'))).load();
  });
  tearDown(() {});

  testWidgets(
    'source-sized chrome and actions keep unavailable execution disabled',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _Controller()..setReducedMotion(true);
      var backed = false;
      try {
        await _mount(tester, c, back: () => backed = true);
        expect(
          tester.getRect(find.byKey(const ValueKey('blue-nav-0'))),
          const Rect.fromLTWH(0, 55, 60, 64),
        );
        final body = tester.getRect(
          find.byKey(const ValueKey('blue-editor-body')),
        );
        expect(body.left, 70);
        expect(body.top, closeTo(118.328125, .001));
        expect(body.width, 522);
        expect(body.bottom, closeTo(347, .1));
        expect(
          tester.getRect(_button('Clear')),
          const Rect.fromLTWH(165, 352, 91, 36),
        );
        expect(
          tester.getRect(_button('Attach')),
          const Rect.fromLTWH(600, 352, 109, 36),
        );
        expect(find.text('Add .lua files to scripts.'), findsOneWidget);
        for (final name in ['Execute', 'Execute File']) {
          expect(tester.widget<BlueButton>(_button(name)).onPressed, isNull);
          await tester.tap(_button(name));
        }
        expect(c.executed, 0);
        expect(find.text('Back to Orion'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('blue-nav-3')));
        await tester.pumpAndSettle();
        final back = find.byKey(const ValueKey('blue-back-to-orion'));
        await tester.ensureVisible(back);
        await tester.pumpAndSettle();
        expect(find.text('Back to Orion'), findsOneWidget);
        await tester.tap(back);
        expect(backed, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );

  testWidgets(
    'tabs align with editor and fit short labels while capping long ones',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _Controller()..setReducedMotion(true);
      c.renameDocument(c.activeDocumentId, 'Script');
      try {
        await _mount(tester, c);
        Finder tab(String id) => find
            .ancestor(
              of: find.byKey(ValueKey('blue-tab-$id')),
              matching: find.byType(Container),
            )
            .first;
        final short = tester.getRect(tab(c.activeDocumentId));
        expect(short.left, 70);
        expect(short.width, inInclusiveRange(53, 58));
        expect(short.height, 24);
        expect(short.top, closeTo(97.328125, .001));
        c.renameDocument(c.activeDocumentId, 'hello-world.luau');
        await tester.pumpAndSettle();
        final medium = tester.getRect(tab(c.activeDocumentId));
        expect(medium.left, 70);
        expect(medium.width, inExclusiveRange(short.width, 150));
        c.renameDocument(c.activeDocumentId, 'a very long file name ' * 6);
        await tester.pumpAndSettle();
        final long = tester.getRect(tab(c.activeDocumentId));
        expect(long.left, 70);
        expect(long.width, 280);
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('blue-tab-${c.activeDocumentId}')),
              )
              .maxLines,
          1,
        );
        final opened = c.newDocument(
          name: 'opened-script.luau',
          content: '-- retained',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('blue-tab-${opened.id}')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );

  testWidgets(
    'shared draft, open, save, new, rename and clear confirmation work',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _Controller()..setReducedMotion(true);
      final key = GlobalKey<SynapseBlueShellState>();
      try {
        await _mount(tester, c, key: key);
        await tester.enterText(
          find.byKey(const ValueKey('code-editor')),
          'print("draft")',
        );
        await tester.tap(_button('Save File'));
        await tester.pump();
        expect(c.saved, 'print("draft")');
        key.currentState!.handleEditorShortcut('new');
        await tester.pumpAndSettle();
        final added = c.activeDocumentId;
        expect(c.documents.length, 2);
        await tester.tap(_button('Open File'));
        await tester.pumpAndSettle();
        expect(c.opened, 1);
        expect(c.activeDocument.content, 'print("opened")');
        await tester.tap(find.text('opened.lua').first);
        await tester.pump(const Duration(milliseconds: 70));
        await tester.tap(find.text('opened.lua').first);
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('blue-tab-rename')),
          'renamed.lua',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(c.activeDocument.name, 'renamed.lua');
        await tester.tap(_button('Clear'));
        await tester.pumpAndSettle();
        expect(find.text('Synapse Warning'), findsOneWidget);
        await tester.tap(_button('No'));
        await tester.pumpAndSettle();
        expect(c.activeDocument.content, 'print("opened")');
        await tester.tap(_button('Clear'));
        await tester.pumpAndSettle();
        await tester.tap(_button('Yes'));
        await tester.pumpAndSettle();
        expect(c.activeDocument.content, '');
        expect(c.documents.any((d) => d.id == added), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );

  testWidgets(
    'all core pages and dialogs fit 80, 100 and 125 percent preserving tabs',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _Controller()..setReducedMotion(true);
      c.updateDocumentContent(c.activeDocumentId, '-- persistent draft');
      final key = GlobalKey<SynapseBlueShellState>();
      try {
        for (final scale in [.8, 1.0, 1.25]) {
          c.setUiScale(scale);
          await _mount(tester, c, key: key);
          for (final page in [3, 4, 1, 2, 0]) {
            await tester.ensureVisible(find.byKey(ValueKey('blue-nav-$page')));
            await tester.tap(find.byKey(ValueKey('blue-nav-$page')));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'page $page at $scale',
            );
            if (page == 4) {
              expect(
                find.byKey(const ValueKey('synapse-theme-studio')),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: find.byKey(const ValueKey('synapse-theme-studio')),
                  matching: find.text('Theme Studio'),
                ),
                findsOneWidget,
              );
              await tester.tap(find.byTooltip('Close studio'));
              await tester.pumpAndSettle();
            }
          }
          expect(c.activeDocument.content, '-- persistent draft');
          expect(_button('Clear').hitTestable(), findsOneWidget);
          await tester.tap(_button('Clear'));
          await tester.pumpAndSettle();
          expect(_button('No').hitTestable(), findsOneWidget);
          await tester.tap(_button('No'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );

  testWidgets(
    'Blue preferences remain isolated and navigation hint follows source fade',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _Controller();
      c.setInterfacePreference(
        InterfacePreset.synapseBlue,
        'enhancedScriptListDefault',
        true,
      );
      c.setInterfacePreference(
        InterfacePreset.synapseX,
        'enhancedScriptListDefault',
        false,
      );
      try {
        await _mount(tester, c);
        expect(find.byKey(const ValueKey('blue-list-search')), findsOneWidget);
        expect(find.text('Github Gists'), findsNothing);
        expect(find.textContaining('Github Gists'), findsOneWidget);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(500, 380));
        await mouse.moveTo(const Offset(30, 155));
        await tester.pump();
        expect(find.byKey(const ValueKey('blue-nav-hint')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 180));
        final hintOpacity = tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('blue-nav-hint')),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity;
        expect(hintOpacity, inExclusiveRange(0, 1));
        await mouse.moveTo(const Offset(500, 380));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(find.byKey(const ValueKey('blue-nav-hint')), findsNothing);
        await mouse.removePointer();
        expect(
          c.getInterfacePreferences(
            InterfacePreset.synapseX,
          )['enhancedScriptListDefault'],
          isFalse,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
}
