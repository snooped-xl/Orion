import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_blue/synapse_blue_shell.dart';
import 'package:orion/widgets/monaco_editor.dart';

class _PreviewMonaco extends MonacoEditorService {
  _PreviewMonaco() : super(onChange: (_, _) {}, onShortcut: (_) {}) {
    ready = true;
  }
  Completer<Uint8List?>? pending;
  bool obscured = false;
  int captures = 0;
  double opacity = 1;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> synchronize(Map<String, Object?> snapshot) async {}
  @override
  Future<void> setBounds({
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {}
  @override
  void setActive(bool active) {}
  @override
  void setOpacity(double value, {String owner = 'shell'}) {
    if (owner == 'synapse-blue') opacity = value;
  }

  @override
  void setObscured(bool value, {String owner = 'route'}) {
    if (owner == 'blue-nav-hover') obscured = value;
  }

  @override
  Future<Uint8List?> capturePreview() {
    captures++;
    return pending?.future ?? Future.value(_png);
  }

  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGPs2Pr/PwMDAwMTAxQAADFxAz/NK9FFAAAAAElFTkSuQmCC',
  );
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    OrionController controller,
    _PreviewMonaco service,
  ) async {
    tester.view.physicalSize = const Size(714, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SynapseBlueShell(
          controller: controller,
          nativeWindow: false,
          playIntro: false,
          editorService: service,
          onBackToOrion: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Blue captures the real editor and dims its page during hover', (
    tester,
  ) async {
    final c = OrionController(persistChanges: false);
    final service = _PreviewMonaco();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mount(tester, c, service);
      expect(find.byType(MonacoEditor), findsOneWidget);
      final original = c.activeDocument.content;
      await mouse.addPointer(location: const Offset(500, 380));
      await mouse.moveTo(const Offset(30, 153));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 190));
      expect(service.captures, 1);
      expect(service.obscured, isTrue);
      expect(service.opacity, inExclusiveRange(.36, 1));
      expect(
        find.byKey(const ValueKey('blue-editor-hover-preview')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('code-editor')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(service.opacity, closeTo(.36, .0001));
      expect(c.activeDocument.content, original);
      await mouse.moveTo(const Offset(500, 380));
      await tester.pumpAndSettle();
      expect(service.obscured, isFalse);
      expect(service.opacity, closeTo(1, .0001));
      expect(
        find.byKey(const ValueKey('blue-editor-hover-preview')),
        findsNothing,
      );
      expect(find.byType(MonacoEditor), findsOneWidget);
      expect(c.activeDocument.content, original);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      service.dispose();
    }
  });

  testWidgets('a late native preview cannot reopen an abandoned hover', (
    tester,
  ) async {
    final c = OrionController(persistChanges: false);
    final service = _PreviewMonaco()..pending = Completer<Uint8List?>();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mount(tester, c, service);
      await mouse.addPointer(location: const Offset(500, 380));
      await mouse.moveTo(const Offset(30, 153));
      await tester.pump();
      expect(service.captures, 1);
      expect(service.obscured, isFalse);
      await mouse.moveTo(const Offset(500, 380));
      await tester.pump();
      service.pending!.complete(_PreviewMonaco._png);
      await tester.pumpAndSettle();
      expect(service.obscured, isFalse);
      expect(
        find.byKey(const ValueKey('blue-editor-hover-preview')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('blue-nav-hint')), findsNothing);
      expect(find.byType(MonacoEditor), findsOneWidget);
      expect(service.opacity, closeTo(1, .0001));
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      service.dispose();
    }
  });
}
