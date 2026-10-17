import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/synapse_blue/blue_intro.dart';
import 'package:orion/synapse_blue/blue_theme.dart';

class _Visibility extends MonacoEditorService {
  _Visibility() : super(onChange: (_, _) {}, onShortcut: (_) {});
  final changes = <(String, bool)>[];
  @override
  void setObscured(bool obscured, {String owner = 'route'}) =>
      changes.add((owner, obscured));
}

Widget _host(
  _Visibility service,
  VoidCallback completed, {
  bool reduced = false,
}) => MaterialApp(
  home: BlueEntrance(
    palette: const BluePalette(),
    play: true,
    reducedMotion: reduced,
    nativeWindow: false,
    resizable: false,
    editorService: service,
    onCompleted: completed,
    child: const Center(child: Text('Ready')),
  ),
);

double _opacity(WidgetTester tester, String text) => tester
    .widgetList<Opacity>(
      find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
    )
    .fold<double>(1, (opacity, widget) => opacity * widget.opacity);

void main() {
  setUpAll(() async {
    await (FontLoader('SynapseInter')..addFont(
          rootBundle.load('assets/synapse_v3/fonts/Inter-Regular.ttf'),
        ))
        .load();
  });
  testWidgets('source staggered fades, progress, morph and completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(714, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Visibility();
    addTearDown(service.dispose);
    var completed = 0;
    await tester.pumpWidget(_host(service, () => completed++));
    expect(
      tester.getSize(find.byKey(const ValueKey('blue-init-card'))),
      const Size(290, 355),
    );
    expect(_opacity(tester, "Let's get scripting."), 0);
    await tester.pump(const Duration(milliseconds: 680));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester, "Let's get scripting."), inExclusiveRange(0, 1));
    expect(_opacity(tester, 'Initializing...'), 0);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 210));
    expect(_opacity(tester, 'Initializing...'), inExclusiveRange(0, 1));
    expect(find.text('Checking Status'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 5790));
    expect(completed, 0);
    await tester.pump(const Duration(milliseconds: 520));
    await tester.pump(const Duration(milliseconds: 290));
    final expanding = tester.getSize(
      find.byKey(const ValueKey('blue-init-card')),
    );
    expect(expanding.width, inExclusiveRange(290, 714));
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump();
    expect(completed, 1);
    expect(find.text('Ready'), findsOneWidget);
    expect(service.changes, [('blue-loading', true), ('blue-loading', false)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion has discrete progress and disposing cancels completion',
    (tester) async {
      final service = _Visibility();
      addTearDown(service.dispose);
      var completed = 0;
      await tester.pumpWidget(_host(service, () => completed++, reduced: true));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_opacity(tester, 'Initializing...'), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(milliseconds: 1800));
      expect(find.text('Checking For Updates'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(completed, 0);
      expect(service.changes, [
        ('blue-loading', true),
        ('blue-loading', false),
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
