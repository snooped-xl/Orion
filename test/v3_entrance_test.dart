import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/synapse_v3/v3_entrance.dart';

class _EditorVisibility extends MonacoEditorService {
  _EditorVisibility() : super(onChange: (_, _) {}, onShortcut: (_) {});
  final changes = <(String, bool)>[];

  @override
  void setObscured(bool obscured, {String owner = 'route'}) {
    changes.add((owner, obscured));
  }
}

void main() {
  testWidgets('holds for two seconds, fades, and restores editor interaction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(961, 461);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final editor = _EditorVisibility();
    addTearDown(editor.dispose);
    var completed = 0;
    var taps = 0;
    Widget host({bool play = true}) => _host(
      editor,
      play: play,
      onCompleted: () => completed++,
      onTap: () => taps++,
    );
    await tester.pumpWidget(host());
    expect(editor.changes, [('v3-loading', true)]);
    final logo = find.byKey(const ValueKey('v3-loading-logo'));
    expect(tester.getRect(logo), const Rect.fromLTWH(390, 188, 181, 38));
    expect(
      tester.getSize(find.byKey(const ValueKey('v3-loading-spinner'))),
      const Size(29, 29),
    );
    expect(find.byKey(const ValueKey('mounted-page')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    expect(taps, 0);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(completed, 0);
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.tapAt(const Offset(20, 20));
    expect(taps, 0);
    expect(editor.changes, [('v3-loading', true)]);
    await tester.pump(const Duration(milliseconds: 316));
    await tester.pump();
    expect(completed, 1);
    expect(editor.changes, [('v3-loading', true), ('v3-loading', false)]);
    expect(logo, findsNothing);
    await tester.tapAt(const Offset(20, 20));
    expect(taps, 1);
    await tester.pumpWidget(host(play: false));
    await tester.pump(const Duration(seconds: 3));
    expect(completed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps hold and has no spinner or reveal ticker', (
    tester,
  ) async {
    final editor = _EditorVisibility();
    addTearDown(editor.dispose);
    var completed = 0;
    await tester.pumpWidget(
      _host(editor, reducedMotion: true, onCompleted: () => completed++),
    );
    expect(find.byKey(const ValueKey('v3-loading-spinner')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(completed, 0);
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(completed, 1);
    expect(find.byKey(const ValueKey('v3-loading-opacity')), findsNothing);
    expect(editor.changes, [('v3-loading', true), ('v3-loading', false)]);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during hold or fade releases only loading ownership', (
    tester,
  ) async {
    for (final elapsed in [
      const Duration(seconds: 1),
      const Duration(milliseconds: 2100),
    ]) {
      final editor = _EditorVisibility();
      var completed = 0;
      await tester.pumpWidget(_host(editor, onCompleted: () => completed++));
      await tester.pump(elapsed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(completed, 0);
      expect(editor.changes, [('v3-loading', true), ('v3-loading', false)]);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      editor.dispose();
    }
  });
}

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(find.byKey(const ValueKey('v3-loading-opacity')))
    .opacity;

Widget _host(
  MonacoEditorService editor, {
  bool play = true,
  bool reducedMotion = false,
  required VoidCallback onCompleted,
  VoidCallback? onTap,
}) => MaterialApp(
  home: Material(
    child: V3Entrance(
      play: play,
      reducedMotion: reducedMotion,
      editorService: editor,
      onCompleted: onCompleted,
      cornerRadius: 7,
      child: GestureDetector(
        key: const ValueKey('mounted-page'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const Center(child: Text('Ready')),
      ),
    ),
  ),
);
