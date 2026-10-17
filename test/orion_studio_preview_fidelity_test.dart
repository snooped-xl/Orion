import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/interface_window_profile.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_density.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/desktop_frame.dart';
import 'package:orion/widgets/synapse_theme_surface.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

// Geometry/Flutter chrome are compared with the actual native-mode shell.
// The separate WebKit editor is kept inert in this widget-only fixture.
class _InertEditor extends MonacoEditorService {
  _InertEditor() : super(onChange: (_, _) {}, onShortcut: (_) {}) {
    ready = true;
  }
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
}

class _CanvasController extends OrionController {
  _CanvasController() : super(persistChanges: false);
  @override
  Future<void> searchRemoteScripts([String? query]) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const nativeChannel = MethodChannel('orion/window');
  const editorChannel = MethodChannel('orion/monaco');
  final nativeCalls = <String>[];
  late OrionController controller;
  late _InertEditor editor;
  final frame = GlobalKey();

  setUpAll(() async {
    for (final font in <String, List<String>>{
      'RobotoFlex': [
        'assets/fonts/RobotoFlex-Regular.ttf',
        'assets/fonts/RobotoFlex-Medium.ttf',
        'assets/fonts/RobotoFlex-Semibold.ttf',
      ],
      'JetBrainsMono': ['assets/fonts/JetBrainsMono.ttf'],
      'SynapseRubik': ['assets/synapse_v3/fonts/Rubik-Regular.ttf'],
    }.entries) {
      final loader = FontLoader(font.key);
      for (final asset in font.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  });

  setUp(() {
    controller = _CanvasController()
      ..completeIntro()
      ..setReducedMotion(true);
    editor = _InertEditor();
    nativeCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [windowChannel, nativeChannel, editorChannel]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add('${channel.name}:${call.method}');
        return switch (call.method) {
          'isMaximized' || 'isFullScreen' => false,
          _ => null,
        };
      });
    }
  });
  tearDown(() {
    controller.dispose();
    editor.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [windowChannel, nativeChannel, editorChannel]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    required bool preview,
    double textScale = 1,
    String page = 'editor',
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final size = InterfaceWindowProfile.forInterface(
      controller,
      InterfacePreset.orion,
    ).size;
    final theme = orionTheme(
      controller.themeMode == ThemeMode.light
          ? Brightness.light
          : Brightness.dark,
      controller.accentColor,
      preferences: controller.orionTheme,
      compactMode: controller.orionCompactMode,
      reducedMotion: true,
      fontFamily: SynapseThemeCatalog.current(
        controller,
        InterfacePreset.orion,
      ).fontFamily,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MediaQuery(
          // Deliberately unlike the source window: a Studio can be much larger
          // and can itself sit underneath keyboard/dialog insets.
          data: MediaQueryData(
            size: preview ? const Size(1200, 900) : size,
            padding: preview ? const EdgeInsets.all(19) : EdgeInsets.zero,
            viewPadding: preview ? const EdgeInsets.all(23) : EdgeInsets.zero,
            viewInsets: preview
                ? const EdgeInsets.only(bottom: 90)
                : EdgeInsets.zero,
            textScaler: TextScaler.linear(textScale),
            platformBrightness: Brightness.dark,
          ),
          child: Center(
            child: SizedBox.fromSize(
              size: size,
              child: RepaintBoundary(
                key: frame,
                child: preview
                    ? OrionStudioPreview(
                        controller: controller,
                        previewPage: page,
                      )
                    : DesktopFrame(
                        enabled: true,
                        reducedMotion: true,
                        cornerRadius: controller.orionCompactMode ? 14 : 16,
                        child: UiScaleViewport(
                          scale: controller.uiScale,
                          child: Material(
                            type: MaterialType.transparency,
                            child: OrionShell(
                              controller: controller,
                              nativeWindow: true,
                              previewPage: page,
                              editorService: editor,
                              onSwitchInterface: (_) async {},
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/orion-wordmark.png'),
        tester.element(find.byType(OrionShell)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder layer(String id) => find.byWidgetPredicate(
    (widget) =>
        widget is SynapseThemeElement &&
        widget.elementId == id &&
        widget.preset == InterfacePreset.orion,
  );
  Map<String, Rect> rectangles(WidgetTester tester) {
    final origin = tester.getTopLeft(find.byKey(frame));
    return {
      for (final id in [
        'titleBar',
        'logo',
        'sidebar',
        'content',
        'workspace',
        'editor',
        'executeButton',
      ])
        id: tester.getRect(layer(id)).shift(-origin),
      'quickActions': tester
          .getRect(find.byTooltip('Quick actions · Ctrl K'))
          .shift(-origin),
      'close': tester.getRect(find.byTooltip('Close Orion')).shift(-origin),
    };
  }

  Future<Uint8List> pixels(WidgetTester tester) async {
    late Uint8List bytes;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(frame),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        bytes = data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    });
    return bytes;
  }

  for (final settings in [
    (false, 1.0, 1.0, 'expressive'),
    (true, 1.25, 1.1, 'expressive'),
    (false, .8, 1.0, 'classic'),
    (false, 1.0, 1.0, 'light'),
  ]) {
    testWidgets(
      'Orion preview matches desktop frame and viewport: ${settings.$4}, compact ${settings.$1}, GUI ${settings.$2}',
      (tester) async {
        controller
          ..setOrionCompactMode(settings.$1)
          ..setUiScale(settings.$2);
        if (settings.$4 == 'classic') {
          controller.setOrionTheme(
            OrionThemePreferences.builtInPresets
                .singleWhere((preset) => preset.id == 'original-orion')
                .preferences,
          );
        } else if (settings.$4 == 'light') {
          controller.setOrionTheme(
            controller.orionTheme.copyWith(themeMode: ThemeMode.light),
          );
        }
        final document = SynapseThemeCatalog.defaults(
          InterfacePreset.orion,
        ).copyWith(fontFamily: 'SynapseRubik');
        controller.applyThemeStudioState(
          InterfacePreset.orion,
          document: document.toJson(),
        );
        await mount(tester, preview: false, textScale: settings.$3);
        final nativeRects = rectangles(tester);
        final nativeParagraph = tester.renderObject<RenderParagraph>(
          find.text('Execute'),
        );
        final nativeTextSize = nativeParagraph.size;
        final nativeMedia = MediaQuery.of(tester.element(layer('editor')));
        final nativeColors = OrionColors.of(tester.element(layer('editor')));
        final nativePixels = await pixels(tester);
        final window = InterfaceWindowProfile.forInterface(
          controller,
          InterfacePreset.orion,
        ).size;
        final rowLength = window.width.toInt() * 4;
        final titleHeight = (nativeRects['titleBar']!.height - 1).floor();
        final nativeTop = nativePixels.sublist(0, rowLength * titleHeight);
        await tester.pumpWidget(const SizedBox.shrink());
        nativeCalls.clear();
        await mount(tester, preview: true, textScale: settings.$3);
        final previewRects = rectangles(tester);
        expect(previewRects, nativeRects);
        expect(
          tester.renderObject<RenderParagraph>(find.text('Execute')).size,
          nativeTextSize,
        );
        final media = MediaQuery.of(tester.element(layer('editor')));
        expect(media.size, window / settings.$2);
        expect(media.size, nativeMedia.size);
        expect(media.padding, EdgeInsets.zero);
        expect(media.viewPadding, EdgeInsets.zero);
        expect(media.viewInsets, EdgeInsets.zero);
        expect(media.textScaler.scale(10), closeTo(settings.$3 * 10, .0001));
        expect(
          OrionDensity.of(tester.element(layer('editor'))).isCompact,
          settings.$1,
        );
        expect(
          OrionColors.of(tester.element(layer('editor'))).editorColor,
          nativeColors.editorColor,
        );
        final previewPixels = await pixels(tester);
        expect(previewPixels.sublist(0, rowLength * titleHeight), nativeTop);
        expect(
          previewPixels[3],
          0,
          reason: 'Rounded outer corner must be transparent.',
        );
        expect(previewPixels[(window.width.toInt() * 20 + 20) * 4 + 3], 255);
        expect(
          nativeCalls,
          isEmpty,
          reason:
              'A preview cannot create WebKit or query/mutate the Studio OS window.',
        );
        for (final tooltip in ['Minimize', 'Maximize', 'Close Orion']) {
          await tester.tap(find.byTooltip(tooltip));
        }
        await tester.pumpAndSettle();
        expect(nativeCalls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('all Orion page previews get the same isolated scaled window', (
    tester,
  ) async {
    controller.setUiScale(1.25);
    final document = SynapseThemeCatalog.defaults(InterfacePreset.orion);
    controller.applyThemeStudioState(
      InterfacePreset.orion,
      document: document.toJson(),
    );
    for (final page in [
      'editor',
      'scriptHub',
      'uiSelection',
      'themeControl',
      'settings',
    ]) {
      await mount(tester, preview: true, page: page);
      final shell = tester.element(find.byType(OrionShell));
      expect(MediaQuery.sizeOf(shell), const Size(822 / 1.25, 523 / 1.25));
      expect(MediaQuery.viewInsetsOf(shell), EdgeInsets.zero);
      expect(find.byTooltip('Close Orion'), findsOneWidget);
      expect(nativeCalls, isEmpty);
      expect(tester.takeException(), isNull, reason: page);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
