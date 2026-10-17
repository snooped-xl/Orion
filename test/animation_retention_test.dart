import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/screens/onboarding_screen.dart';
import 'package:orion/screens/ui_selection_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_logo.dart';
import 'package:orion/widgets/orion_startup_reveal.dart';
import 'package:orion/widgets/orion_studio_layer.dart';

class _LocalController extends OrionController {
  _LocalController() : super(persistChanges: false);
  @override
  Future<void> searchRemoteScripts([String? query]) async {}
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    OrionController controller,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(822, 523);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(Brightness.dark, controller.accentColor),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  testWidgets('page animation retains static Studio decorators and content', (
    tester,
  ) async {
    final controller = _LocalController()..completeIntro();
    addTearDown(controller.dispose);
    await mount(
      tester,
      controller,
      OrionShell(
        controller: controller,
        nativeWindow: false,
        onSwitchInterface: (_) async {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('UI Selection'));
    await tester.pump();
    var decorators = 0;
    var headingBuilds = 0;
    final heading = tester.element(
      find.descendant(
        of: find.byType(UISelectionScreen),
        matching: find.text('UI Selection'),
      ),
    );
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is OrionStudioLayer) decorators++;
      if (element == heading) headingBuilds++;
    };
    try {
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    expect(decorators, 0);
    expect(headingBuilds, 0);
    // The actual title, controls and page remain mounted throughout the swap.
    expect(find.text('UI Selection'), findsWidgets);
    expect(find.byTooltip('Editor'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editor'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('onboarding moves its poses without rebuilding static copy', (
    tester,
  ) async {
    final controller = _LocalController();
    addTearDown(controller.dispose);
    await mount(
      tester,
      controller,
      OrionOnboardingScreen(
        controller: controller,
        onComplete: () {},
        onSaveBridge: () async => true,
        onCopyBridge: () async {},
        onOpenBridgeFolder: () async {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pump();
    var copyBuilds = 0;
    final before = tester.getTopLeft(find.text('Connect your executor'));
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is Text) copyBuilds++;
    };
    try {
      for (var frame = 0; frame < 16; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    expect(copyBuilds, 0);
    expect(
      tester.getTopLeft(find.text('Connect your executor')),
      isNot(before),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('startup retains its decoded wordmark during every pose', (
    tester,
  ) async {
    final controller = _LocalController();
    addTearDown(controller.dispose);
    var completions = 0;
    await mount(
      tester,
      controller,
      OrionStartupReveal(
        controller: controller,
        onComplete: () => completions++,
      ),
    );
    var logoBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is OrionWordmark) logoBuilds++;
    };
    try {
      for (var frame = 0; frame < 58; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    expect(logoBuilds, 0);
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 22));
    expect(completions, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
