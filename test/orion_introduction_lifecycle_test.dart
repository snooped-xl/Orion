import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/screens/onboarding_screen.dart';
import 'package:orion/screens/synapse_theme_studio.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_startup_reveal.dart';

const _editor = ValueKey('code-editor');
const _next = ValueKey('onboarding-next');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.devicePixelRatio = 1;
    view.physicalSize = const Size(822, 523);
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'first launch waits for the user and survives a restart until finished',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('orion-introduction-'),
      );
      final controllers = <_CheckpointController>[];
      addTearDown(() {
        for (final controller in controllers) {
          controller.dispose();
        }
        directory!.deleteSync(recursive: true);
      });

      Future<_CheckpointController> restore() async {
        final controller = _CheckpointController(storageDirectory: directory)
          ..setReducedMotion(true);
        controllers.add(controller);
        await tester.runAsync(controller.initialize);
        return controller;
      }

      const source = 'print("kept through the introduction")';
      final first = await restore();
      first.updateDocumentContent(first.activeDocumentId, source);
      await tester.pumpWidget(OrionApp(controller: first, nativeWindow: false));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Orion'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      expect(first.introCompleted, isFalse);
      expect(find.text('Welcome to Orion'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyN);
      await _studioShortcut(tester);
      await _studioShortcut(tester, alternate: true);
      expect(first.documents, hasLength(1));
      expect(find.byType(SynapseThemeStudioScreen), findsNothing);
      await _advance(tester);
      expect(find.text('Connect your executor'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-save-bridge')),
        findsOneWidget,
      );

      // Closing in the middle of setup cannot turn it into a completed guide.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(first.checkpoint);
      first.dispose();
      controllers.remove(first);
      final second = await restore();
      expect(second.introCompleted, isFalse);
      await tester.pumpWidget(
        OrionApp(controller: second, nativeWindow: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Orion'), findsOneWidget);
      await _advance(tester);
      await _advance(tester);
      expect(find.text('Smoother starts'), findsOneWidget);
      await _advance(tester);
      expect(find.text('Executor Quick Launch'), findsOneWidget);
      expect(find.text('Open Orion'), findsOneWidget);
      expect(second.introCompleted, isFalse);
      await _advance(tester);
      expect(second.introCompleted, isTrue);
      expect(find.byType(OrionOnboardingScreen), findsNothing);
      expect(find.byKey(_editor), findsOneWidget);
      expect(second.activeDocument.content, source);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(second.checkpoint);
      second.dispose();
      controllers.remove(second);
      final third = await restore();
      expect(third.introCompleted, isTrue);
      expect(third.activeDocument.content, source);
      await tester.pumpWidget(OrionApp(controller: third, nativeWindow: false));
      await tester.pumpAndSettle();
      expect(find.byType(OrionOnboardingScreen), findsNothing);
      expect(find.byKey(_editor), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      third.dispose();
      await tester.runAsync(third.checkpoint);
      controllers.remove(third);
    },
  );

  testWidgets(
    'replaying setup preserves completion, edits and the Settings page',
    (tester) async {
      final controller = _memoryController()..completeIntro();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        OrionApp(controller: controller, nativeWindow: false),
      );
      await tester.pumpAndSettle();
      const source = '-- unsaved and still here\nprint("hello")';
      await tester.enterText(find.byKey(_editor), source);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final replay = find.text('Replay intro');
      await tester.ensureVisible(replay);
      await tester.tap(replay);
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Orion'), findsOneWidget);
      expect(controller.introCompleted, isTrue);
      await _shortcut(tester, LogicalKeyboardKey.keyN);
      await _shortcut(tester, LogicalKeyboardKey.keyK);
      expect(controller.documents, hasLength(1));
      expect(find.text('New script'), findsNothing);
      for (var step = 0; step < 4; step++) {
        await _advance(tester);
      }
      expect(controller.introCompleted, isTrue);
      expect(controller.activeDocument.content, source);
      expect(find.byKey(const ValueKey('settings')), findsOneWidget);
      expect(find.text('Replay intro'), findsOneWidget);
      expect(find.byType(OrionOnboardingScreen), findsNothing);
      await tester.tap(find.byTooltip('Editor'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(_editor)).controller!.text,
        source,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'startup shields shortcuts and native editor until its reveal ends',
    (tester) async {
      final controller = _memoryController(reducedMotion: false)
        ..completeIntro();
      final service = _RecordingEditorService();
      addTearDown(controller.dispose);
      addTearDown(service.dispose);
      var completions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: orionTheme(Brightness.dark, controller.accentColor),
          home: OrionShell(
            controller: controller,
            nativeWindow: false,
            playStartup: true,
            editorService: service,
            onStartupComplete: () => completions++,
            onSwitchInterface: (_) async {},
          ),
        ),
      );
      expect(find.byType(OrionStartupReveal), findsOneWidget);
      expect(service.obscuredBy, contains('orion-introduction'));
      expect(service.visible, isFalse);
      await _shortcut(tester, LogicalKeyboardKey.keyN);
      await _shortcut(tester, LogicalKeyboardKey.keyK);
      expect(controller.documents, hasLength(1));
      expect(find.text('New script'), findsNothing);
      await tester.pump(OrionStartupReveal.duration);
      await tester.pumpAndSettle();
      expect(completions, 1);
      expect(find.byType(OrionStartupReveal), findsNothing);
      expect(service.obscuredBy, isEmpty);
      expect(service.visible, isTrue);
      await _shortcut(tester, LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(controller.documents, hasLength(2));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editor'));
      await tester.pumpAndSettle();
      expect(find.byType(OrionStartupReveal), findsNothing);
      expect(completions, 1);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(service.obscuredBy, isEmpty);
    },
  );

  testWidgets(
    'the startup animation runs once even after changing interfaces',
    (tester) async {
      final controller = _memoryController(reducedMotion: false)
        ..completeIntro();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        OrionApp(controller: controller, nativeWindow: false),
      );
      expect(find.byType(OrionStartupReveal), findsOneWidget);
      await tester.pump(OrionStartupReveal.duration);
      await tester.pumpAndSettle();
      expect(find.byType(OrionStartupReveal), findsNothing);
      controller.setReducedMotion(true);
      controller.setInterface(InterfacePreset.xeno);
      await tester.pumpAndSettle();
      expect(find.byType(OrionStartupReveal), findsNothing);
      controller.setInterface(InterfacePreset.orion);
      await tester.pumpAndSettle();
      expect(find.byType(OrionStartupReveal), findsNothing);
      expect(find.byKey(_editor), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Theme Studio previews bypass both introductions without completing setup',
    (tester) async {
      final controller = _memoryController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: OrionStudioPreview(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(controller.introCompleted, isFalse);
      expect(find.byKey(_editor), findsOneWidget);
      expect(find.byType(OrionOnboardingScreen), findsNothing);
      expect(find.byType(OrionStartupReveal), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

OrionController _memoryController({bool reducedMotion = true}) =>
    OrionController(persistChanges: false)..setReducedMotion(reducedMotion);

Future<void> _advance(WidgetTester tester) async {
  await tester.tap(find.byKey(_next));
  await tester.pumpAndSettle();
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _studioShortcut(
  WidgetTester tester, {
  bool alternate = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (alternate) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
  if (alternate) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// A ready native surface without starting WebKit or using platform channels.
/// The shell still owns its real visibility flags throughout the introduction.
class _RecordingEditorService extends MonacoEditorService {
  _RecordingEditorService() : super(onChange: (_, _) {}, onShortcut: (_) {}) {
    ready = true;
  }

  final obscuredBy = <String>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> synchronize(Map<String, Object?> snapshot) async {}

  @override
  Future<void> flush() async {}

  @override
  void setObscured(bool obscured, {String owner = 'route'}) {
    if (obscured) {
      obscuredBy.add(owner);
    } else {
      obscuredBy.remove(owner);
    }
    super.setObscured(obscured, owner: owner);
  }
}

/// Keep file operations out of FakeAsync while exercising the real storage
/// format, restoration, and completion flag at explicit process checkpoints.
class _CheckpointController extends OrionController {
  _CheckpointController({required super.storageDirectory});

  @override
  Future<void> flushPersistence() async {}

  Future<void> checkpoint() => super.flushPersistence();
}
