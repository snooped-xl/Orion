import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/original_ports/zenith_pages.dart';

void main() {
  setUpAll(() async {
    await rootBundle.loadString(
      'assets/original_zenith/Data/function-documentation.json',
    );
    await rootBundle.loadString(
      'assets/original_zenith/Data/help-articles.json',
    );
    for (final font in const [
      (
        'OriginalNunito',
        'assets/original_zenith/Fonts/Nunito-Source-Regular.ttf',
      ),
      ('OriginalConsolas', 'assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(968, 582),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(backgroundColor: const Color(0xff0a0a0a), body: page),
      ),
    );
    await tester.runAsync(() async {
      await rootBundle.loadString(
        'assets/original_zenith/Data/function-documentation.json',
      );
      await rootBundle.loadString(
        'assets/original_zenith/Data/help-articles.json',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Documentation General preserves source copy, fixed sidebar and no search',
    (tester) async {
      String? linked;
      await mount(
        tester,
        ZenithDocumentation(
          animation: const AlwaysStoppedAnimation(1),
          onVisitHelp: (title) => linked = title,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('zenith-doc-sidebar'))).width,
        224,
      );
      expect(
        find.text("Welcome to Zenith's In-App Function Documentation"),
        findsOneWidget,
      );
      expect(find.text('Zenith has it all (and more)!'), findsOneWidget);
      expect(find.byKey(const ValueKey('zenith-doc-search')), findsNothing);
      final guide = find.text('Help Center guide');
      await tester.ensureVisible(guide);
      await tester.pumpAndSettle();
      await tester.tap(guide);
      expect(linked, 'Can I contribute or suggest features?');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Function alias search expands full source details and copies exact syntax',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(
        tester,
        const ZenithDocumentation(animation: AlwaysStoppedAnimation(1)),
      );
      await tester.tap(find.byKey(const ValueKey('zenith-doc-category-All')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('zenith-doc-search')),
        'getscriptfunction',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('zenith-function-getscriptclosure')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Syntax'), findsOneWidget);
      expect(find.text('Parameters'), findsOneWidget);
      expect(find.text('Returns'), findsOneWidget);
      expect(find.text('Examples'), findsOneWidget);
      const syntax = 'getscriptclosure(script: Instance)';
      expect(find.text(syntax), findsOneWidget);
      await tester.tap(find.text('Copy').first);
      await tester.pump();
      expect(copied, syntax);
      expect(find.text('Copied'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Help source sidebar searches article content and renders bundled guide images',
    (tester) async {
      await mount(
        tester,
        const ZenithHelp(animation: AlwaysStoppedAnimation(1)),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('zenith-help-sidebar'))).width,
        256,
      );
      expect(find.text('Help & Guides'), findsOneWidget);
      expect(find.text('Welcome to Zenith Help Center'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('zenith-help-search')),
        'palette',
      );
      await tester.pumpAndSettle();
      final article = find.byKey(
        const ValueKey('zenith-help-article-Using the Command Palette'),
      );
      await tester.ensureVisible(article);
      await tester.pumpAndSettle();
      await tester.tap(article);
      await tester.pumpAndSettle();
      expect(find.text('Help Center'), findsOneWidget);
      expect(find.text('Related Articles'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('Using the Command Palette'), findsWidgets);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('zenith-help-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Help initial article and settings links keep source navigation usable',
    (tester) async {
      var settings = false;
      await mount(
        tester,
        ZenithHelp(
          animation: const AlwaysStoppedAnimation(1),
          initialArticle: 'Custom Themes',
          onOpenSettings: () => settings = true,
        ),
        size: const Size(692, 432),
      );
      final setting = find.text('Settings → Interface Settings → Theme');
      await tester.ensureVisible(setting);
      await tester.pumpAndSettle();
      await tester.tap(setting);
      expect(settings, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Zenith Help Center'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
