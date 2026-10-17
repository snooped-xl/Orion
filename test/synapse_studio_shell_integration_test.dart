import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_blue/blue_controls.dart';
import 'package:orion/synapse_blue/synapse_blue_shell.dart';
import 'package:orion/synapse_og/synapse_og_shell.dart';
import 'package:orion/synapse_v3/synapse_v3_shell.dart';
import 'package:orion/synapse_x/synapse_x_shell.dart';
import 'package:orion/widgets/synapse_theme_surface.dart';

import 'original_awp_test.dart' show OriginalPortAssets, OriginalPortChannel;

Widget _shell(
  InterfacePreset preset,
  OrionController c,
  MonacoEditorService service,
) => switch (preset) {
  InterfacePreset.synapseBlue => SynapseBlueShell(
    controller: c,
    nativeWindow: false,
    onBackToOrion: () {},
    playIntro: false,
    bridgeReady: true,
    editorService: service,
  ),
  InterfacePreset.synapseX => SynapseXShell(
    controller: c,
    nativeWindow: false,
    onBackToOrion: () {},
    playIntro: false,
    bridgeReady: true,
    editorService: service,
  ),
  InterfacePreset.synapse2017 => SynapseOgShell(
    controller: c,
    nativeWindow: false,
    onBackToOrion: () {},
    playIntro: false,
    bridgeReady: true,
    editorService: service,
  ),
  _ => SynapseV3Shell(
    controller: c,
    nativeWindow: false,
    onBackToOrion: () {},
    bridgeReady: true,
    editorService: service,
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Inter', 'Rubik']) {
      await (FontLoader('Synapse$family')..addFont(
            rootBundle.load('assets/synapse_v3/fonts/$family-Regular.ttf'),
          ))
          .load();
    }
  });
  for (final preset in SynapseThemeCatalog.synapsePresets) {
    testWidgets(
      '${preset.name} applies individual action and native editor styles while diagnostics remain disabled',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = OrionController(persistChanges: false)
          ..setReducedMotion(true);
        final channel = OriginalPortChannel();
        final service = MonacoEditorService(
          channel: channel,
          server: OriginalPortAssets(),
          onChange: c.updateDocumentContent,
          onShortcut: (_) {},
        );
        await service.initialize();
        c.setInterfacePreference(preset, 'errorLogging', true);
        c.setInterfacePreference(preset, 'errorLoggingEnabled', true);
        c.updateSynapsePreferences(errorLogging: true);
        await tester.pumpWidget(MaterialApp(home: _shell(preset, c, service)));
        await tester.pumpAndSettle();
        expect(channel.snapshot!['options']['diagnosticEnabled'], isFalse);
        final target = find.byWidgetPredicate(
          (widget) =>
              widget is SynapseThemeElement &&
              widget.windowId == 'main' &&
              widget.elementId == 'executeButton',
        );
        expect(target, findsOneWidget);
        final actualButton = find
            .descendant(
              of: target,
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton || widget is BlueButton,
              ),
            )
            .first;
        final originalRect = tester.getRect(actualButton);
        final document = SynapseThemeCatalog.defaults(preset)
            .copyWith(fontFamily: 'SynapseRubik')
            .withElement(
              'main',
              'executeButton',
              SynapseStudioElement(
                x: 9,
                y: 5,
                fill: 0xff253c64,
                foreground: 0xffe3efff,
                border: 0xff536c98,
                radius: 11,
              ),
            )
            .withElement(
              'main',
              'editor',
              SynapseStudioElement(
                fill: 0xff123456,
                foreground: 0xffabcdef,
                opacity: .7,
                radius: 8,
              ),
            )
            .withElement('main', 'content', SynapseStudioElement(opacity: .8));
        c.setInterfacePreference(preset, 'themeStudio', document.toJson());
        await tester.pumpAndSettle();
        final moved = tester.getRect(actualButton);
        expect(moved.left - originalRect.left, closeTo(9, .01));
        expect(moved.top - originalRect.top, closeTo(5, .01));
        final buttons = find.descendant(
          of: target,
          matching: find.byType(TextButton),
        );
        if (preset == InterfacePreset.synapseBlue) {
          expect(
            find.descendant(
              of: target,
              matching: find.byWidgetPredicate(
                (widget) => widget is BlueButton,
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: target,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).color ==
                        const Color(0xff253c64),
              ),
            ),
            findsOneWidget,
          );
        } else {
          final button = tester.widget<TextButton>(buttons.first);
          expect(
            button.style!.backgroundColor!.resolve({}),
            const Color(0xff253c64),
          );
          expect(
            button.style!.foregroundColor!.resolve({}),
            const Color(0xffe3efff),
          );
          final shape =
              button.style!.shape!.resolve({})! as RoundedRectangleBorder;
          expect(shape.borderRadius, BorderRadius.circular(11));
        }
        final options = channel.snapshot!['options'] as Map;
        expect(options['background'], '#123456');
        expect(options['foreground'], '#abcdef');
        expect(options['studioEditorEnabled'], isTrue);
        expect(options['studioEditorOpacity'], closeTo(.56, .0001));
        expect(options['studioEditorRadius'], 8);
        expect(options['studioFontFamily'], isNull);
        expect(options['diagnosticEnabled'], isFalse);
        final image = SynapseStudioImage(
          data:
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
        );
        final imaged = document.withElement(
          'main',
          'executeButton',
          document
              .window('main')
              .elements['executeButton']!
              .copyWith(image: image),
        );
        c.setInterfacePreference(preset, 'themeStudio', imaged.toJson());
        await tester.pumpAndSettle();
        if (preset == InterfacePreset.synapseBlue) {
          expect(
            find.descendant(
              of: target,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).color ==
                        Colors.transparent,
              ),
            ),
            findsOneWidget,
          );
        } else {
          final style = tester.widget<TextButton>(buttons.first).style!;
          expect(style.backgroundColor!.resolve({}), Colors.transparent);
          expect(
            style.backgroundColor!.resolve({WidgetState.hovered}),
            Colors.transparent,
          );
        }
        expect(
          find.descendant(of: target, matching: find.byType(Image)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        service.dispose();
      },
    );
  }
}
