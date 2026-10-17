import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_blue/synapse_blue_shell.dart';
import 'package:orion/synapse_og/synapse_og_shell.dart';
import 'package:orion/synapse_v3/synapse_v3_shell.dart';
import 'package:orion/synapse_v3/v3_undocked_editor.dart';
import 'package:orion/synapse_x/synapse_x_shell.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/luau_syntax.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

List<TextSpan> leaves(TextSpan root) => [
  if (root.text != null) root,
  for (final child in root.children ?? const []) ...leaves(child as TextSpan),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await SynapseSyntaxThemes.ensureLoaded();
    for (final family in ['Inter', 'Rubik']) {
      await (FontLoader('Synapse$family')..addFont(
            rootBundle.load('assets/synapse_v3/fonts/$family-Regular.ttf'),
          ))
          .load();
    }
  });
  testWidgets(
    'packaged non-default palette loads from rootBundle and reaches syntax spans',
    (tester) async {
      const themeId = 'magicwb--amiga-';
      final source = await tester.runAsync(
        () => rootBundle.loadString('assets/editor/synapse-syntax-themes.json'),
      );
      final bundled = jsonDecode(source!) as Map;
      expect(bundled[themeId]['styles']['keyword'], {
        'foreground': '0000FF',
        'fontStyle': 'bold',
      });
      expect(bundled[themeId]['styles']['comment'], {
        'foreground': '8d2e75',
        'fontStyle': 'italic',
      });
      await tester.runAsync(SynapseSyntaxThemes.ensureLoaded);
      final controller = LuauSyntaxController(
        text: 'local value = 1 -- comment',
        themeId: themeId,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
            ),
          ),
        ),
      );
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
        withComposing: false,
      );
      final rendered = leaves(span);
      final keyword = rendered.firstWhere((span) => span.text == 'local');
      final comment = rendered.firstWhere((span) => span.text == '-- comment');
      expect(keyword.style!.color, const Color(0xff0000ff));
      expect(keyword.style!.fontWeight, FontWeight.bold);
      expect(comment.style!.color, const Color(0xff8d2e75));
      expect(comment.style!.fontStyle, FontStyle.italic);
      expect(span.toPlainText(), controller.text);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'stateful Luau lexing preserves comments, long strings, escapes and types',
    () {
      const source =
          '--[=[ local fake = "42"\n ]=]\n'
          'local value: string = "hello \\"world"\n'
          'local long = [==[ -- not a comment\n42 ]==]\n'
          'local number = 0xAF + 0b101 + 12_345 + .5 + 1.25e-3\n'
          'print(`hello {value}`) -- 🌌 comment';
      final tokens = LuauSyntax.tokenize(source);
      expect(
        tokens.map((t) => source.substring(t.start, t.end)).join(),
        source,
      );
      expect(tokens.first.kind, 'comment');
      expect(
        source.substring(tokens.first.start, tokens.first.end),
        contains('local fake'),
      );
      expect(tokens.where((t) => t.kind == 'type'), isNotEmpty);
      expect(tokens.where((t) => t.kind == 'escape'), isNotEmpty);
      expect(tokens.where((t) => t.kind == 'interpolation'), isNotEmpty);
      expect(
        tokens
            .where((t) => t.kind == 'string')
            .any(
              (t) =>
                  source.substring(t.start, t.end).contains('-- not a comment'),
            ),
        true,
      );
      expect(
        tokens
            .where((t) => t.kind == 'number')
            .map((t) => source.substring(t.start, t.end)),
        containsAll(['0xAF', '0b101', '12_345', '.5', '1.25e-3']),
      );
      for (final incomplete in [
        '--[=[ unfinished',
        '[==[ unfinished',
        '"unfinished\\',
        '`hello {unfinished',
      ]) {
        final tokens = LuauSyntax.tokenize(incomplete);
        expect(
          tokens.map((t) => incomplete.substring(t.start, t.end)).join(),
          incomplete,
        );
      }
    },
  );

  testWidgets(
    'syntax spans preserve IME composition, code font and user foreground',
    (tester) async {
      final controller = LuauSyntaxController(text: 'local value = "hello"');
      addTearDown(controller.dispose);
      controller.useTheme('synapse-v3', foreground: Colors.cyan);
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 3),
        selection: const TextSelection.collapsed(offset: 3),
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final span = controller.buildTextSpan(
        context: context,
        style: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 13,
          height: 18 / 13,
        ),
        withComposing: true,
      );
      expect(span.toPlainText(), controller.text);
      expect(span.style!.fontFamily, 'JetBrainsMono');
      expect(span.style!.height, 18 / 13);
      expect(span.style!.color, Colors.cyan);
      expect(
        leaves(span)
            .where((span) => span.style?.decoration == TextDecoration.underline)
            .map((span) => span.text)
            .join(),
        'loc',
      );
      expect(controller.selection.extentOffset, 3);
    },
  );

  testWidgets(
    'preview gutter and code share the native font scale under OS and GUI scaling',
    (tester) async {
      final controller = LuauSyntaxController(text: 'local x = 1\nprint(x)');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.1)),
            child: UiScaleViewport(scale: 1.25, child: child!),
          ),
          home: Material(
            child: LuauCodePreview(
              controller: controller,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 18 / 13,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraphs = tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byType(LuauCodePreview),
              matching: find.byType(RichText),
            ),
          )
          .toList();
      expect(paragraphs, hasLength(2));
      expect(paragraphs.every((text) => text.textScaler.scale(13) == 13), true);
      final sizes = [
        for (final paragraph in paragraphs)
          tester.getRect(find.byWidget(paragraph)).height,
      ];
      expect(sizes.first, closeTo(sizes.last, .001));
      expect(sizes.last, closeTo(45, .001));
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, theme, keyword, string, make)
      in <(String, String, Color, Color, Widget Function(OrionController))>[
        (
          'V3',
          'synapse-v3',
          const Color(0xff569cd6),
          const Color(0xffce9178),
          (c) => SynapseV3Shell(
            controller: c,
            nativeWindow: false,
            onBackToOrion: () {},
          ),
        ),
        (
          'Blue',
          'tomorrow-night-eighties',
          const Color(0xffcc99cc),
          const Color(0xff99cc99),
          (c) => SynapseBlueShell(
            controller: c,
            nativeWindow: false,
            playIntro: false,
            onBackToOrion: () {},
          ),
        ),
        (
          'X',
          'net-theme-dark',
          const Color(0xffff6a00),
          const Color(0xff468dd4),
          (c) => SynapseXShell(
            controller: c,
            nativeWindow: false,
            playIntro: false,
            onBackToOrion: () {},
          ),
        ),
        (
          'OG',
          'og-2017-custom',
          const Color(0xff569cd6),
          const Color(0xffce9178),
          (c) => SynapseOgShell(
            controller: c,
            nativeWindow: false,
            playIntro: false,
            onBackToOrion: () {},
          ),
        ),
        (
          'undocked V3',
          'synapse-v3',
          const Color(0xff569cd6),
          const Color(0xffce9178),
          (c) => V3UndockedEditor(controller: c, nativeWindow: false),
        ),
      ]) {
    testWidgets(
      '$name actual source preview uses its native token palette and remains editable',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = OrionController(persistChanges: false)
          ..setReducedMotion(true);
        const source = 'local value: string = "hello" -- comment\nprint(value)';
        c.updateDocumentContent(c.activeDocumentId, source);
        await tester.pumpWidget(
          MaterialApp(
            theme: orionTheme(Brightness.dark, Colors.blue),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.1)),
              child: UiScaleViewport(scale: 1.25, child: child!),
            ),
            home: Material(child: make(c)),
          ),
        );
        await tester.pumpAndSettle();
        final key = name == 'undocked V3'
            ? 'v3-undocked-editor'
            : 'code-editor';
        final field = tester.widget<TextField>(find.byKey(ValueKey(key)));
        expect(field.controller, isA<LuauSyntaxController>());
        final editable = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(EditableText),
          ),
        );
        expect(
          (editable.textScaler ??
                  MediaQuery.textScalerOf(
                    tester.element(find.byWidget(editable)),
                  ))
              .scale(13),
          13,
        );
        final syntax = field.controller! as LuauSyntaxController;
        final spans = leaves(
          syntax.buildTextSpan(
            context: tester.element(find.byKey(ValueKey(key))),
            style: field.style,
            withComposing: false,
          ),
        );
        expect(
          spans.firstWhere((span) => span.text == 'local').style!.color,
          keyword,
        );
        expect(
          spans
              .where((span) => span.text?.contains('hello') ?? false)
              .first
              .style!
              .color,
          string,
        );
        expect(SynapseSyntaxThemes.style(theme, 'keyword').color, keyword);
        await tester.enterText(find.byKey(ValueKey(key)), 'print("edited")');
        await tester.pump();
        expect(c.activeDocument.content, 'print("edited")');
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
