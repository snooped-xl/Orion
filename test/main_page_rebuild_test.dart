import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/screens/ui_selection_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/interface_logo.dart';

void main() {
  testWidgets('typing does not rebuild background UI cards and settings', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false)
      ..completeIntro()
      ..setReducedMotion(true);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1045, 648);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      OrionApp(controller: controller, nativeWindow: false),
    );
    await tester.pumpAndSettle();
    final logo = tester.element(
      find.byType(InterfaceLogo, skipOffstage: false).first,
    );
    final switchElement = tester.element(
      find.byKey(const ValueKey('settings-minimap'), skipOffstage: false),
    );
    var logoBuilds = 0, settingsBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element == logo) logoBuilds++;
      if (element == switchElement) settingsBuilds++;
    };
    try {
      for (var index = 0; index < 30; index++) {
        controller.updateDocumentContent(
          controller.activeDocumentId,
          'print("edit $index")',
        );
        await tester.pump();
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    expect(logoBuilds, 0);
    expect(settingsBuilds, 0);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('code-editor')))
          .controller!
          .text,
      'print("edit 29")',
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    controller.setShowMinimap(true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('settings-minimap')))
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('UI selection stays live when its selected interface changes', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false)
      ..setReducedMotion(true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(Brightness.dark, controller.accentColor),
        home: Scaffold(body: UISelectionScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('select-interface-synapseX'));
    final before = tester.widget<FilledButton>(action).style!;
    controller.setInterface(InterfacePreset.synapseX);
    await tester.pumpAndSettle();
    final after = tester.widget<FilledButton>(action).style!;
    expect(
      after.backgroundColor!.resolve({}),
      isNot(before.backgroundColor!.resolve({})),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
