import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/bridge_notification_app.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/theme/orion_surfaces.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    required VoidCallback onClose,
    String username = 'OrionPlayer',
    String? executorName,
    Map<String, Object?> extraDefinition = const {},
    bool reducedMotion = false,
    String brightness = 'dark',
    OrionThemePreferences? preferences,
    Size size = const Size(396, 120),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      BridgeNotificationApp(
        definition: {
          ...extraDefinition,
          'username': username,
          'executorName': ?executorName,
          'brightness': brightness,
          'reducedMotion': reducedMotion,
          'theme': (preferences ?? OrionThemePreferences.defaults).toJson(),
          'durationMs': 4000,
        },
        onClose: onClose,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  BoxDecoration surface(WidgetTester tester) {
    final widget = tester.widget(
      find.byKey(const ValueKey('bridge-notification-surface')),
    );
    return switch (widget) {
      DecoratedBox() => widget.decoration as BoxDecoration,
      Container() => widget.decoration as BoxDecoration,
      _ => throw StateError(
        'Notification surface must expose its painted decoration.',
      ),
    };
  }

  OrionColors colorsOf(WidgetTester tester) =>
      OrionColors.of(tester.element(find.byType(BridgeConnectionToast)));

  BorderSide stroke(WidgetTester tester) {
    final border = surface(tester).border;
    if (border != null) return (border as Border).top;
    final material = tester
        .widgetList<Material>(find.byType(Material))
        .firstWhere((m) => m.elevation == 5);
    return (material.shape! as OutlinedBorder).side;
  }

  testWidgets(
    'passive card identifies bridge and player with dismiss control',
    (tester) async {
      var closes = 0;
      await mount(tester, onClose: () => closes++);
      expect(find.text('Orion Bridge'), findsOneWidget);
      expect(find.text('OrionPlayer'), findsOneWidget);
      expect(find.byTooltip('Dismiss'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(closes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'title identifies Orion Bridge and the subject identifies the live executor',
    (tester) async {
      await mount(tester, onClose: () {}, executorName: 'Madium');
      expect(find.text('Executor Connected! (Madium)'), findsOneWidget);
      expect(find.text('OrionPlayer'), findsOneWidget);
      expect(find.text('Orion Bridge'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Orion Bridge')).dy,
        lessThan(
          tester.getTopLeft(find.text('Executor Connected! (Madium)')).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('Executor Connected! (Madium)')).dy,
        lessThan(tester.getTopLeft(find.text('OrionPlayer')).dy),
      );
      final liveRegion = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .firstWhere((widget) => widget.properties.liveRegion == true);
      expect(
        liveRegion.properties.label,
        'Orion Bridge. Executor Connected! (Madium). OrionPlayer',
      );
      await mount(tester, onClose: () {}, executorName: 'AnotherExecutor');
      expect(
        find.text('Executor Connected! (AnotherExecutor)'),
        findsOneWidget,
      );
      expect(find.text('Executor Connected! (Madium)'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'display name takes precedence over the legacy account-name field',
    (tester) async {
      await mount(
        tester,
        onClose: () {},
        username: 'private_account_name',
        executorName: 'LiveExecutor',
        extraDefinition: const {'displayName': 'Galactic Friend'},
      );
      expect(find.text('Galactic Friend'), findsOneWidget);
      expect(find.text('private_account_name'), findsNothing);
      expect(find.text('Orion Bridge'), findsOneWidget);
      expect(find.text('Executor Connected! (LiveExecutor)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing empty and unknown executor retain title with a generic connected subject',
    (tester) async {
      for (final executorName in <String?>[
        null,
        '',
        '   ',
        'Unknown',
        'unknown',
      ]) {
        await mount(tester, onClose: () {}, executorName: executorName);
        expect(find.text('Orion Bridge'), findsOneWidget);
        expect(find.text('Executor Connected!'), findsOneWidget);
        expect(find.text('OrionPlayer'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'executor notification never consumes or displays version fields',
    (tester) async {
      await mount(
        tester,
        onClose: () {},
        executorName: 'Madium',
        extraDefinition: const {
          'executorVersion': '99.42.7-version-must-not-appear',
          'version': '99.42.7-version-must-not-appear',
        },
      );
      expect(find.text('Executor Connected! (Madium)'), findsOneWidget);
      expect(find.textContaining('99.42.7'), findsNothing);
      expect(find.textContaining('version-must-not-appear'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'long executor and player names fit narrow notification without overflow',
    (tester) async {
      const executor = 'AReallyLongCustomExecutorNameThatStillMustFitTheCard';
      const username = 'AnExceptionallyLongUsernameThatMustNotOverflow';
      await mount(
        tester,
        onClose: () {},
        executorName: executor,
        username: username,
        size: const Size(240, 120),
      );
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(
        find.text('Executor Connected! ($executor)'),
      );
      final player = tester.widget<Text>(find.text(username));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(player.maxLines, 1);
      expect(player.overflow, TextOverflow.ellipsis);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('stays four seconds then exits with reverse animation', (
    tester,
  ) async {
    var closes = 0;
    await mount(tester, onClose: () => closes++);
    await tester.pump(const Duration(milliseconds: 3800));
    expect(closes, 0);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 240));
    expect(closes, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(closes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dismiss reverses immediately and fires once', (tester) async {
    var closes = 0;
    await mount(tester, onClose: () => closes++);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(closes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hover pauses lifetime and resumes remaining time on exit', (
    tester,
  ) async {
    var closes = 0;
    await mount(tester, onClose: () => closes++);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 50));
    await mouse.moveTo(const Offset(101, 50));
    await tester.pump(const Duration(seconds: 7));
    expect(closes, 0);
    await mouse.moveTo(const Offset(-20, -20));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(closes, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reduced motion removes spatial movement and honors light scheme',
    (tester) async {
      var closes = 0;
      await mount(
        tester,
        onClose: () => closes++,
        reducedMotion: true,
        brightness: 'light',
      );
      final toast = tester.element(find.byType(BridgeConnectionToast));
      expect(Theme.of(toast).brightness, Brightness.light);
      final transforms = tester.widgetList<Transform>(find.byType(Transform));
      expect(transforms.any((t) => t.transform.storage[12] != 0), false);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(closes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'classic palette stays neutral and opaque for desktop legibility',
    (tester) async {
      await mount(
        tester,
        onClose: () {},
        preferences: OrionThemePreferences.builtInPresets
            .firstWhere((p) => p.id == 'original-orion')
            .preferences,
      );
      final toast = tester.element(find.byType(BridgeConnectionToast));
      final colors = OrionColors.of(toast);
      expect(colors.accent, OrionThemePreferences.originalAccent);
      final decoration = surface(tester);
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors.every((color) => color.a == 1), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Easy theme gradient retains custom colors, angle and stops on the toast',
    (tester) async {
      final preferences = OrionThemePreferences(
        accent: const Color(0xFFB1F0D3),
        gradientEnabled: true,
        gradientColors: const [
          Color(0xFF07151B),
          Color(0xFF132D22),
          Color(0xFF1F112B),
        ],
        gradientStops: const [0, .28, 1],
        gradientAngle: 90,
        surfaceTint: .6,
      );
      await mount(tester, onClose: () {}, preferences: preferences);
      final colors = colorsOf(tester);
      final gradient = surface(tester).gradient! as LinearGradient;
      expect(gradient.stops, [0, .28, 1]);
      final begin = gradient.begin as Alignment;
      final end = gradient.end as Alignment;
      expect(begin.x, closeTo(0, .000001));
      expect(begin.y, -1);
      expect(end.x, closeTo(0, .000001));
      expect(end.y, 1);
      expect(
        gradient.colors,
        orionSurfaceGradient(colors, base: colors.elevated, blend: .75)!.colors,
      );
      expect(gradient.colors.toSet().length, 3);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.color, preferences.accent.withValues(alpha: .65));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.person_rounded)).color,
        preferences.accent,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Original Orion notification has its standalone graphite gradient and thin outline',
    (tester) async {
      final preferences = OrionThemePreferences.builtInPresets
          .firstWhere((preset) => preset.id == 'original-orion')
          .preferences;
      await mount(tester, onClose: () {}, preferences: preferences);
      final colors = colorsOf(tester);
      final gradient = surface(tester).gradient! as LinearGradient;
      expect(gradient.colors, const [Color(0xFF181A1B), Color(0xFF08090A)]);
      expect(gradient.stops, [0, .37019]);
      final begin = gradient.begin as Alignment;
      final end = gradient.end as Alignment;
      expect(begin.x, closeTo(-1, .000001));
      expect(begin.y, closeTo(-1, .000001));
      expect(end.x, closeTo(1, .000001));
      expect(end.y, closeTo(1, .000001));
      expect(stroke(tester).color, colors.outline(.45));
      expect(stroke(tester).width, 1);
      expect(gradient.colors, colors.backgroundGradient!.colors);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Fine theme role overrides reach the actual card, border, labels and icons',
    (tester) async {
      const elevated = Color(0xFF152638);
      const ink = Color(0xFFFCF0D8);
      const muted = Color(0xFFCEDCE8);
      const border = Color(0xFFC261E4);
      final preferences = OrionThemePreferences(
        accent: const Color(0xFFB1F0D3),
        outlineStrength: 2,
        surfaceTint: .65,
        overrides: const {
          'background': Color(0xFF080C12),
          'elevated': elevated,
          'border': border,
          'ink': ink,
          'muted': muted,
        },
      );
      await mount(tester, onClose: () {}, preferences: preferences);
      expect(surface(tester).gradient, isNull);
      expect(surface(tester).color, elevated);
      expect(stroke(tester).color, border.withValues(alpha: .9));
      expect(tester.widget<Text>(find.text('Orion Bridge')).style!.color, ink);
      expect(tester.widget<Text>(find.text('OrionPlayer')).style!.color, muted);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.close_rounded)).color,
        muted,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'explicit elevated override takes priority over an enabled Easy gradient',
    (tester) async {
      const customSurface = Color(0xFF23182B);
      final preferences = OrionThemePreferences(
        gradientEnabled: true,
        gradientColors: const [Color(0xFF07151B), Color(0xFF132D22)],
        gradientAngle: 30,
        overrides: const {'elevated': customSurface},
      );
      await mount(tester, onClose: () {}, preferences: preferences);
      // The global scheme still has a gradient. The deliberately chosen card
      // color wins here, matching the fine-controls override hierarchy.
      expect(colorsOf(tester).backgroundGradient, isNotNull);
      expect(surface(tester).gradient, isNull);
      expect(surface(tester).color, customSurface);
      expect(surface(tester).color!.a, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Background control visibly changes a notification without a gradient',
    (tester) async {
      await mount(tester, onClose: () {});
      final original = surface(tester).color;
      await mount(
        tester,
        onClose: () {},
        preferences: OrionThemePreferences(
          overrides: const {'background': Color(0xFF321020)},
        ),
      );
      expect(surface(tester).gradient, isNull);
      expect(surface(tester).color, isNot(original));
      expect(surface(tester).color!.a, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Outline strength controls notification stroke visibility and weight',
    (tester) async {
      await mount(
        tester,
        onClose: () {},
        preferences: OrionThemePreferences(outlineStrength: 0),
      );
      final absent = stroke(tester);
      expect(absent.color.a, 0);
      await mount(
        tester,
        onClose: () {},
        preferences: OrionThemePreferences(outlineStrength: 2),
      );
      final strong = stroke(tester);
      expect(strong.color, colorsOf(tester).border.withValues(alpha: .9));
      expect(strong.width, greaterThan(absent.width));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('long usernames fit narrow monitor without layout overflow', (
    tester,
  ) async {
    await mount(
      tester,
      onClose: () {},
      username:
          'AnExceptionallyLongUsernameThatMustFitTheCardWithoutOverflowing',
      size: const Size(240, 120),
    );
    expect(tester.takeException(), isNull);
    final name = tester.widget<Text>(
      find.text(
        'AnExceptionallyLongUsernameThatMustFitTheCardWithoutOverflowing',
      ),
    );
    expect(name.overflow, TextOverflow.ellipsis);
    await tester.pumpWidget(const SizedBox());
  });
}
