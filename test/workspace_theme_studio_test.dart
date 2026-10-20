import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/screens/workspace_screen.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/synapse_theme_surface.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';
import 'package:orion/widgets/orion_glass.dart';
import 'package:orion/widgets/native_desktop_glass.dart';

final _inactiveCompositor = ValueNotifier(false);

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGOs2PLhPwMDAwMTAxQAAC9wAx8nztMDAAAAAElFTkSuQmCC';

class _Assets extends EditorAssetServer {
  @override
  Future<Uri> start() async =>
      Uri.parse('http://127.0.0.1:9999/editor/index.html');
  @override
  Future<void> close() async {}
}

class _Channel extends MethodChannel {
  _Channel() : super('orion/workspace-studio-test');
  Future<dynamic> Function(MethodCall)? handler;
  final commands = <Map<String, dynamic>>[];
  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) =>
      handler = callback;
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    if (method == 'create') {
      await handler?.call(MethodCall('message', jsonEncode({'type': 'ready'})));
    } else if (method == 'send') {
      commands.add(jsonDecode(arguments as String) as Map<String, dynamic>);
    }
    return null;
  }

  Map<String, dynamic> get options =>
      commands.lastWhere((c) => c['type'] == 'sync')['options']
          as Map<String, dynamic>;
}

void main() {
  late OrionController c;
  setUp(() {
    c = OrionController(persistChanges: false)..setReducedMotion(true);
  });
  tearDown(() => c.dispose());

  Future<void> pump(
    WidgetTester tester, {
    MonacoEditorService? service,
    VoidCallback? onOpen,
    ValueNotifier<bool>? compositorGlass,
  }) async {
    tester.view.physicalSize = const Size(1000, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: c,
        builder: (_, _) => MaterialApp(
          theme: orionTheme(
            Brightness.dark,
            c.accentColor,
            preferences: c.orionTheme,
          ),
          home: Scaffold(
            body: UiScaleViewport(
              scale: c.uiScale,
              child: ValueListenableBuilder<bool>(
                valueListenable: compositorGlass ?? _inactiveCompositor,
                builder: (_, active, child) => NativeDesktopGlassScope(
                  active: active,
                  opacity: .9,
                  child: child!,
                ),
                child: WorkspaceScreen(
                  controller: c,
                  editorService: service,
                  onOpen: onOpen ?? () {},
                  onSave: () {},
                  onLibrary: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void commit(SynapseStudioTheme? document) => c.setInterfacePreference(
    InterfacePreset.orion,
    'themeStudio',
    document?.toJson(),
  );

  testWidgets(
    'editor settings reach native Monaco without replacing the script',
    (tester) async {
      final channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      addTearDown(service.dispose);
      await service.initialize();
      await pump(tester, service: service);
      expect(channel.options['minimap'], isFalse);
      expect(channel.options['autocomplete'], isTrue);
      expect(channel.options['bracketPairColorization'], isTrue);
      expect(channel.options['renderWhitespace'], isFalse);
      expect(channel.options['animateReveal'], isFalse);
      final source = c.activeDocument.content;
      final id = c.activeDocumentId;
      c.setShowMinimap(true);
      c.setAutocomplete(false);
      c.setBracketPairColorization(false);
      c.setRenderWhitespace(true);
      await tester.pumpAndSettle();
      expect(channel.options['minimap'], isTrue);
      expect(channel.options['autocomplete'], isFalse);
      expect(channel.options['bracketPairColorization'], isFalse);
      expect(channel.options['renderWhitespace'], isTrue);
      expect(c.activeDocumentId, id);
      expect(c.activeDocument.content, source);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real workspace layers apply button paint and geometry without losing editor contents or callbacks',
    (tester) async {
      var opened = 0;
      await pump(tester, onOpen: () => opened++);
      final code = c.activeDocument.content;
      final execute = find.ancestor(
        of: find.text('Execute'),
        matching: find.byType(FilledButton),
      );
      final document = SynapseThemeCatalog.defaults(InterfacePreset.orion)
          .copyWith(fontFamily: 'SynapseRubik')
          .withElement(
            'main',
            'executeButton',
            SynapseStudioElement(
              y: 4,
              width: 95,
              height: 30,
              fill: 0xff663399,
              foreground: 0xffffeecc,
              border: 0xff00ff00,
              radius: 2,
              opacity: .75,
            ),
          );
      commit(
        document.withElement(
          'main',
          'executeButton',
          document.window('main').elements['executeButton']!.copyWith(y: 0),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(execute);
      commit(document);
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(execute);
      expect(
        button.style!.backgroundColor!.resolve({}),
        const Color(0xff663399),
      );
      expect(
        button.style!.foregroundColor!.resolve({}),
        const Color(0xffffeecc),
      );
      expect(button.style!.side!.resolve({})!.color, const Color(0xff00ff00));
      expect(
        (button.style!.shape!.resolve({})! as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.circular(2),
      );
      expect(button.style!.textStyle!.resolve({})!.fontFamily, 'SynapseRubik');
      final after = tester.getRect(execute);
      expect(after.width, 95);
      expect(after.height, 30);
      expect(after.top, closeTo(before.top + 4, .1));
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(of: execute, matching: find.byType(Opacity)),
            )
            .any((w) => w.opacity == .75),
        isTrue,
      );
      expect(c.activeDocument.content, code);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('code-editor')))
            .style!
            .fontFamily,
        'JetBrainsMono',
      );
      final ids = tester
          .widgetList<SynapseThemeElement>(find.byType(SynapseThemeElement))
          .map((w) => w.elementId)
          .toSet();
      expect(
        ids,
        containsAll([
          'workspace',
          'scriptList',
          'tabs',
          'editorTools',
          'editor',
          'actions',
          'consoleOutput',
          'executeButton',
          'openButton',
          'saveButton',
          'clearButton',
          'clientsButton',
        ]),
      );
      await tester.tap(find.text('Open file'));
      expect(opened, 1);
      commit(null);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(execute)
            .style!
            .backgroundColor!
            .resolve({}),
        c.accentColor,
      );
      expect(c.activeDocument.content, code);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native Orion editor receives image, fill, opacity and radius; resetting restores Classic options',
    (tester) async {
      final channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      addTearDown(service.dispose);
      c.setOrionTheme(
        OrionThemePreferences.builtInPresets
            .singleWhere((p) => p.id == 'original-orion')
            .preferences,
      );
      final doc = SynapseThemeCatalog.defaults(InterfacePreset.orion)
          .withWindow(
            'main',
            SynapseStudioWindow(
              background: SynapseStudioImage(data: _png, opacity: .4),
              overlay: SynapseStudioImage(data: _png, opacity: .2),
              elements: {
                'content': SynapseStudioElement(opacity: .8),
                'workspace': SynapseStudioElement(opacity: .5),
                'editor': SynapseStudioElement(
                  fill: 0xff223344,
                  foreground: 0xffffee99,
                  opacity: .25,
                  radius: 18,
                  image: SynapseStudioImage(
                    data: _png,
                    opacity: .6,
                    fit: 'contain',
                  ),
                ),
              },
            ),
          );
      commit(doc);
      await pump(tester, service: service);
      final options = channel.options;
      expect(options['shell'], 'orion');
      expect(options['studioEditorEnabled'], isTrue);
      expect(options['studioBackgroundLocal'], isTrue);
      expect(
        options['studioBackgroundImage'],
        startsWith('data:image/png;base64,'),
      );
      expect(options['studioBackgroundOpacity'], .6);
      expect(options['studioBackgroundLayerOpacity'], closeTo(.1, 1e-9));
      expect(options['studioBackgroundFill'], '#223344');
      expect(options['studioEditorOpacity'], closeTo(.1, 1e-9));
      expect(options['studioEditorRadius'], 18);
      expect(options['foreground'], '#ffee99');
      expect(options['studioOverlayOpacity'], .2);
      expect(options['studioEditorTransparent'], isTrue);
      commit(
        doc
            .withElement(
              'main',
              'editor',
              doc
                  .window('main')
                  .elements['editor']!
                  .copyWith(clearImage: true, clearFill: true),
            )
            .withElement(
              'main',
              'workspace',
              doc
                  .window('main')
                  .elements['workspace']!
                  .copyWith(image: SynapseStudioImage(data: _png), x: 8),
            ),
      );
      await tester.pumpAndSettle();
      final region = channel.options['studioBackgroundRegion'] as Map;
      final frame = tester.getRect(find.byType(WorkspaceScreen));
      expect(region['x'], closeTo(frame.left + 8, .01));
      expect(region['y'], closeTo(frame.top, .01));
      expect(region['width'], closeTo(frame.width, .01));
      expect(region['height'], closeTo(frame.height, .01));
      expect(channel.options['studioBackgroundLocal'], isFalse);
      c.setUiScale(1.25);
      await tester.pumpAndSettle();
      final zoomed = channel.options['studioBackgroundRegion'] as Map;
      final zoomedFrame = tester.getRect(find.byType(WorkspaceScreen));
      expect(zoomed['x'], closeTo(zoomedFrame.left / 1.25 + 8, .01));
      expect(zoomed['y'], closeTo(zoomedFrame.top / 1.25, .01));
      expect(zoomed['width'], closeTo(zoomedFrame.width / 1.25, .01));
      expect(zoomed['height'], closeTo(zoomedFrame.height / 1.25, .01));
      expect(channel.options['uiScale'], 1.25);
      commit(null);
      await tester.pumpAndSettle();
      expect(channel.options['studioEditorEnabled'], isFalse);
      expect(channel.options.containsKey('studioBackgroundImage'), isFalse);
      expect(channel.options['transparentBackground'], isTrue);
      expect(channel.options['windowBackdrop'], isNotNull);
      expect(channel.options['backgroundGradient'], isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'glass workspace uses one chrome sheet and an opaque native canvas with authored-fill precedence',
    (tester) async {
      final channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      addTearDown(service.dispose);
      c.setOrionTheme(
        OrionThemePreferences.builtInPresets
            .singleWhere((preset) => preset.id == 'liquid-glass')
            .preferences,
      );
      final originalCode = c.activeDocument.content;
      await pump(tester, service: service);
      for (final layer in ['scriptList', 'editorChrome']) {
        expect(find.byKey(ValueKey('workspace-glass-$layer')), findsOneWidget);
      }
      expect(
        tester
            .widget<OrionGlassSurface>(
              find.byKey(const ValueKey('workspace-glass-editorChrome')),
            )
            .enabled,
        isTrue,
      );
      for (final layer in ['scriptList', 'consoleOutput']) {
        expect(
          tester
              .widget<OrionGlassSurface>(
                find.byKey(ValueKey('workspace-glass-$layer')),
              )
              .enabled,
          isFalse,
          reason: '$layer inherits the window glass instead of another lens',
        );
      }
      expect(
        find.byKey(const ValueKey('workspace-glass-editor')),
        findsOneWidget,
        reason:
            'stable native slot retains its foreground across glass changes',
      );
      expect(
        tester
            .widget<OrionGlassSurface>(
              find.byKey(const ValueKey('workspace-glass-editor')),
            )
            .enabled,
        isFalse,
      );
      expect(channel.options['glassEnabled'], isTrue);
      expect(channel.options['transparentBackground'], isTrue);
      expect(channel.options['glassEditorRadius'], 20);
      final backdrop = channel.options['windowBackdrop'] as Map;
      expect((backdrop['color'] as String).length, 7);
      expect(backdrop['color'], isNot('#00000000'));
      expect(backdrop['opacity'], 1);
      expect(backdrop['opacity'], OrionGlassSurface.defaultMaterialOpacity);
      expect(backdrop['radials'], isEmpty);
      expect(channel.options['glassTint'], '#00000000');
      // Glassy's default backing is one neutral tint, with no blue gradient.
      final solidGlass = (backdrop['gradient'] as Map)['colors'] as List;
      expect(solidGlass, hasLength(2));
      expect(solidGlass.toSet(), {'#151719'});
      expect(
        ((backdrop['gradient'] as Map)['colors'] as List).every(
          (color) => (color as String).length == 7,
        ),
        isTrue,
      );
      expect(find.byType(OrionGlassSurface), findsWidgets);
      c.setOrionTheme(
        c.orionTheme.copyWith(
          gradientEnabled: false,
          overrides: {
            'background': const Color(0xfff2f6fc),
            'ink': const Color(0xff17212e),
          },
        ),
      );
      await tester.pumpAndSettle();
      final lightBackdrop = channel.options['windowBackdrop'] as Map;
      final lightColors = (lightBackdrop['gradient'] as Map)['colors'] as List;
      expect(
        int.parse((lightColors.first as String).substring(1, 3), radix: 16),
        greaterThan(200),
        reason: 'native glass follows the light scene substrate',
      );
      expect(lightBackdrop['radials'], isEmpty);
      c.setOrionTheme(
        OrionThemePreferences.builtInPresets
            .singleWhere((preset) => preset.id == 'liquid-glass')
            .preferences,
      );
      final doc = SynapseThemeCatalog.defaults(InterfacePreset.orion)
          .withElement(
            'main',
            'editor',
            SynapseStudioElement(fill: 0xff29394d, radius: 6),
          );
      commit(doc);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OrionGlassSurface>(
              find.byKey(const ValueKey('workspace-glass-editor')),
            )
            .enabled,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('workspace-glass-scriptList')),
        findsOneWidget,
      );
      expect(channel.options['glassEnabled'], isFalse);
      expect(channel.options['transparentBackground'], isFalse);
      expect(channel.options['background'], '#29394d');
      expect(channel.options['studioEditorRadius'], 6);
      expect(c.activeDocument.content, originalCode);
      commit(null);
      c.setOrionTheme(OrionThemePreferences.defaults);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<OrionGlassSurface>(find.byType(OrionGlassSurface))
            .every((surface) => !surface.enabled),
        isTrue,
      );
      expect(channel.options['glassEnabled'], isFalse);
      expect(channel.options['transparentBackground'], isFalse);
      expect(channel.options.containsKey('glassTint'), isFalse);
      // Authored Studio hierarchy is reset separately above; a plain Glass
      // toggle keeps the native editor State/selection/engine in its slot.
      final stableState = tester.state(
        find.byKey(const ValueKey('monaco-editor')),
      );
      c.setOrionTheme(c.orionTheme.copyWith(liquidGlassEnabled: true));
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byKey(const ValueKey('monaco-editor'))),
        same(stableState),
      );
      expect(c.activeDocument.content, originalCode);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Flutter editor fallback receives its own glass sheet', (
    tester,
  ) async {
    c.setOrionTheme(
      OrionThemePreferences.defaults.copyWith(liquidGlassEnabled: true),
    );
    await pump(tester);
    expect(
      find.byKey(const ValueKey('workspace-glass-editor')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native glass follows authored Easy gradients and solid backgrounds',
    (tester) async {
      final channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      addTearDown(service.dispose);
      final originalCode = c.activeDocument.content;
      c.setOrionTheme(
        OrionThemePreferences.defaults.copyWith(
          liquidGlassEnabled: true,
          gradientEnabled: true,
          gradientColors: const [
            Color(0xff80253b),
            Color(0xff224d78),
            Color(0xff255a34),
          ],
          gradientStops: const [0, .18, 1],
          gradientAngle: 72,
        ),
      );
      await pump(tester, service: service);
      final gradient =
          (channel.options['windowBackdrop'] as Map)['gradient'] as Map;
      expect(
        (gradient['colors'] as List).map(
          (color) => (color as String).substring(0, 7),
        ),
        ['#80253b', '#224d78', '#255a34'],
      );
      expect(gradient['stops'], [0.0, .18, 1.0]);
      expect(gradient['begin'], isNot([-1.0, -1.0]));
      expect(
        (channel.options['windowBackdrop'] as Map)['opacity'],
        OrionGlassSurface.defaultMaterialOpacity,
      );
      c.setOrionTheme(
        c.orionTheme.copyWith(
          gradientEnabled: false,
          overrides: const {'background': Color(0xff592a82)},
        ),
      );
      await tester.pumpAndSettle();
      final solid =
          (channel.options['windowBackdrop'] as Map)['gradient'] as Map;
      final solidColors = (solid['colors'] as List).cast<String>();
      expect(solidColors, hasLength(2));
      expect(solidColors.toSet(), hasLength(1));
      expect(solidColors.first.substring(0, 7), '#592a82');
      expect(channel.options['glassEnabled'], isTrue);
      c.setOrionTheme(c.orionTheme.copyWith(liquidGlassEnabled: false));
      await tester.pumpAndSettle();
      expect(channel.options['glassEnabled'], isFalse);
      expect(channel.options['transparentBackground'], isFalse);
      expect(channel.options['windowBackdrop'], isNull);
      expect(channel.options['backgroundGradient'], isNull);
      expect(c.activeDocument.content, originalCode);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'native compositor scope updates editor mode without replacing its model',
    (tester) async {
      final channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      final compositor = ValueNotifier(false);
      addTearDown(service.dispose);
      addTearDown(compositor.dispose);
      c.setOrionTheme(
        OrionThemePreferences.defaults.copyWith(liquidGlassEnabled: true),
      );
      final document = c.activeDocument;
      await pump(tester, service: service, compositorGlass: compositor);
      expect(channel.options['glassEnabled'], isTrue);
      expect(channel.options['compositorGlass'], isFalse);
      final originalEditor = tester.state(find.byType(WorkspaceScreen));
      compositor.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(channel.options['compositorGlass'], isTrue);
      expect(tester.state(find.byType(WorkspaceScreen)), same(originalEditor));
      expect(c.activeDocument, same(document));
      compositor.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(channel.options['compositorGlass'], isFalse);
      c.setOrionTheme(c.orionTheme.copyWith(liquidGlassEnabled: false));
      compositor.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        channel.options['compositorGlass'],
        isFalse,
        reason: 'the desktop helper must never change a non-Glass editor',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
