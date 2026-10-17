import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/editor_tab_strip.dart';

const _scrollKey = ValueKey('editor-tab-scroll');
const _backKey = ValueKey('editor-tabs-back');
const _forwardKey = ValueKey('editor-tabs-forward');

void main() {
  testWidgets(
    'fitting tabs keep their geometry and need no overflow controls',
    (tester) async {
      final fixture = await _mount(tester, count: 3);
      final position = _position(tester);
      expect(position.maxScrollExtent, 0);
      expect(find.byKey(_backKey), findsNothing);
      expect(find.byKey(_forwardKey), findsNothing);
      for (final id in fixture.ids) {
        expect(
          tester.getSize(find.byKey(ValueKey('fixture-tab:$id'))),
          const Size(120, 36),
        );
      }
      expect(await _wheel(tester, const Offset(0, 100)), isTrue);
      expect(position.pixels, 0);
      expect(fixture.activeId, 'tab-0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary wheel scrolls overflowing tabs without selecting them',
    (tester) async {
      final fixture = await _mount(tester);
      final position = _position(tester);
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);
      expect(find.byKey(_forwardKey), findsOneWidget);
      expect(await _wheel(tester, const Offset(0, 100)), isFalse);
      expect(position.pixels, closeTo(100, .01));
      expect(fixture.activeId, 'tab-0');
      expect(find.byKey(_backKey), findsOneWidget);
      expect(await _wheel(tester, const Offset(0, -35)), isFalse);
      expect(position.pixels, closeTo(65, .01));
      expect(fixture.activeId, 'tab-0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('horizontal and Shift-wheel input each move once', (
    tester,
  ) async {
    await _mount(tester);
    final position = _position(tester);
    expect(await _wheel(tester, const Offset(55, 0)), isFalse);
    expect(position.pixels, closeTo(55, .01));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      expect(await _wheel(tester, const Offset(0, 40)), isFalse);
      expect(position.pixels, closeTo(95, .01));
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nested page scrolling waits until the tab strip reaches its edge',
    (tester) async {
      final theme = orionTheme(Brightness.dark, const Color(0xFF88B5FF));
      final ids = List.generate(10, (index) => 'tab-$index');
      const outerKey = ValueKey('fixture-outer-scroll');
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 420,
                height: 200,
                child: SingleChildScrollView(
                  key: outerKey,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 40,
                        child: EditorTabStrip(
                          tabIds: ids,
                          activeId: ids.first,
                          colors: theme.extension<OrionColors>()!,
                          reducedMotion: true,
                          tabBuilder: (context, index) => SizedBox(
                            width: 120,
                            height: 36,
                            child: Text(ids[index]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 1160),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inner = _position(tester);
      final outer = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(outerKey),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      await _wheel(tester, const Offset(0, 80));
      expect(inner.pixels, closeTo(80, .01));
      expect(outer.pixels, 0);
      inner.jumpTo(inner.maxScrollExtent);
      await tester.pump();
      await _wheel(tester, const Offset(0, 35));
      expect(outer.pixels, closeTo(35, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid wheels accumulate, clamp, reverse, and release at edges', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final position = _position(tester);
    for (var i = 0; i < 4; i++) {
      await _wheel(tester, const Offset(0, 35), pump: false);
    }
    await tester.pump();
    expect(position.pixels, closeTo(140, .01));
    await _wheel(tester, const Offset(0, 100000));
    expect(position.pixels, position.maxScrollExtent);
    expect(await _wheel(tester, const Offset(0, 50)), isTrue);
    await _wheel(tester, const Offset(0, -25));
    expect(position.pixels, closeTo(position.maxScrollExtent - 25, .01));
    await _wheel(tester, const Offset(0, -100000));
    expect(position.pixels, 0);
    expect(await _wheel(tester, const Offset(0, -50)), isTrue);
    expect(fixture.activeId, 'tab-0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('chevrons scroll immediately with reduced motion', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final position = _position(tester);
    await tester.tap(find.byKey(_forwardKey));
    await tester.pump();
    expect(position.pixels, greaterThan(0));
    final afterForward = position.pixels;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_backKey));
    await tester.pump();
    expect(position.pixels, lessThan(afterForward));
    expect(fixture.activeId, 'tab-0');
    expect(find.byTooltip('Scroll tabs left'), findsOneWidget);
    expect(find.byTooltip('Scroll tabs right'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'normal-motion chevrons finish their scroll and retain selection',
    (tester) async {
      final fixture = await _mount(tester);
      fixture.change(reducedMotion: false);
      await tester.pumpAndSettle();
      final position = _position(tester);
      await tester.tap(find.byKey(_forwardKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(position.pixels, greaterThan(0));
      final midpoint = position.pixels;
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThanOrEqualTo(midpoint));
      expect(fixture.activeId, 'tab-0');
      fixture.change(activeId: fixture.ids.last);
      await tester.pumpAndSettle();
      expect(_fullyVisible(tester, fixture.activeId), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selecting, adding, and closing tabs keep the active tab visible',
    (tester) async {
      final fixture = await _mount(tester);
      fixture.change(activeId: fixture.ids.last);
      await tester.pumpAndSettle();
      expect(_fullyVisible(tester, fixture.activeId), isTrue);
      fixture.change(ids: [...fixture.ids, 'tab-new'], activeId: 'tab-new');
      await tester.pumpAndSettle();
      expect(_fullyVisible(tester, 'tab-new'), isTrue);
      final position = _position(tester);
      expect(position.pixels, greaterThan(0));
      fixture.change(ids: fixture.ids.take(2).toList(), activeId: 'tab-0');
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      expect(position.maxScrollExtent, 0);
      expect(find.byKey(_backKey), findsNothing);
      expect(find.byKey(_forwardKey), findsNothing);
      expect(_fullyVisible(tester, 'tab-0'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resizing remeasures overflow and reveals the selected tab', (
    tester,
  ) async {
    final fixture = await _mount(tester, count: 3);
    fixture.change(activeId: fixture.ids.last);
    await tester.pumpAndSettle();
    fixture.change(width: 240);
    await tester.pumpAndSettle();
    expect(_position(tester).maxScrollExtent, greaterThan(0));
    expect(_fullyVisible(tester, fixture.activeId), isTrue);
    fixture.change(width: 600);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);
    expect(find.byKey(_backKey), findsNothing);
    expect(find.byKey(_forwardKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unrelated rebuilds preserve the manually scrolled viewport', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await _wheel(tester, const Offset(0, 220));
    final position = _position(tester);
    final offset = position.pixels;
    fixture.change();
    await tester.pumpAndSettle();
    expect(position.pixels, offset);
    expect(fixture.activeId, 'tab-0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wider renamed active tab is revealed after content reflow', (
    tester,
  ) async {
    final fixture = await _mount(tester, count: 3);
    fixture.change(activeId: fixture.ids.last);
    await tester.pumpAndSettle();
    expect(_position(tester).maxScrollExtent, 0);
    fixture.change(widths: {fixture.ids.last: 220});
    await tester.pumpAndSettle();
    expect(_position(tester).maxScrollExtent, greaterThan(0));
    expect(_fullyVisible(tester, fixture.activeId), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing another tab preserves a manually browsed viewport', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await _wheel(tester, const Offset(0, 220));
    final position = _position(tester);
    final offset = position.pixels;
    expect(_fullyVisible(tester, fixture.activeId), isFalse);
    fixture.change(ids: fixture.ids.where((id) => id != 'tab-8').toList());
    await tester.pumpAndSettle();
    expect(position.pixels, offset);
    expect(fixture.activeId, 'tab-0');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overflow controls follow every Orion palette and compact layout',
    (tester) async {
      final fixture = await _mount(tester);
      final themes = [
        ...OrionThemePreferences.builtInPresets
            .take(OrionThemePreferences.primaryPresetCount)
            .map((preset) => preset.preferences),
        OrionThemePreferences(
          themeMode: ThemeMode.light,
          accent: const Color(0xFF8A4787),
          overrides: const {
            'panel': Color(0xFFFAF5F8),
            'muted': Color(0xFF62525C),
            'ink': Color(0xFF241923),
          },
        ),
      ];
      for (final theme in themes) {
        fixture.change(preferences: theme, compact: true);
        await tester.pumpAndSettle();
        await _wheel(tester, const Offset(0, 80));
        expect(find.byKey(_backKey), findsOneWidget);
        expect(find.byKey(_forwardKey), findsOneWidget);
        expect(_position(tester).pixels, greaterThan(0));
        final colors = fixture.colors;
        for (final key in [_backKey, _forwardKey]) {
          final button = tester.widget<IconButton>(find.byKey(key));
          expect(
            button.style!.foregroundColor!.resolve({}),
            colors.readableAccent,
          );
        }
        final icons = tester.widgetList<Icon>(
          find.descendant(
            of: find.byType(EditorTabStrip),
            matching: find.byType(Icon),
          ),
        );
        expect(icons, isNotEmpty);
        for (final icon in icons) {
          expect(
            icon.color,
            anyOf(isNull, colors.muted, colors.readableAccent, colors.ink),
          );
        }
        expect(tester.takeException(), isNull, reason: theme.presetId);
      }
    },
  );
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(_scrollKey),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

bool _fullyVisible(WidgetTester tester, String id) {
  final viewport = tester.getRect(find.byKey(_scrollKey));
  final tab = tester.getRect(find.byKey(ValueKey('fixture-tab:$id')));
  return tab.left >= viewport.left - .5 && tab.right <= viewport.right + .5;
}

Future<bool?> _wheel(
  WidgetTester tester,
  Offset delta, {
  bool pump = true,
}) async {
  bool? response;
  tester.binding.handlePointerEvent(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(find.byKey(_scrollKey)),
      scrollDelta: delta,
      onRespond: ({required bool allowPlatformDefault}) {
        response = allowPlatformDefault;
      },
    ),
  );
  if (pump) await tester.pump();
  return response;
}

Future<_HarnessState> _mount(WidgetTester tester, {int count = 10}) async {
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(_Harness(key: key, count: count));
  await tester.pumpAndSettle();
  return key.currentState!;
}

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.count});
  final int count;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<String> ids = List.generate(widget.count, (index) => 'tab-$index');
  String activeId = 'tab-0';
  double width = 420;
  bool compact = false;
  bool reducedMotion = true;
  Map<String, double> widths = {};
  OrionThemePreferences preferences = OrionThemePreferences.defaults;

  ThemeData get theme => orionTheme(
    preferences.themeMode == ThemeMode.light
        ? Brightness.light
        : Brightness.dark,
    preferences.accent,
    preferences: preferences,
    reducedMotion: reducedMotion,
    compactMode: compact,
  );
  OrionColors get colors => theme.extension<OrionColors>()!;

  void change({
    List<String>? ids,
    String? activeId,
    double? width,
    OrionThemePreferences? preferences,
    bool? compact,
    bool? reducedMotion,
    Map<String, double>? widths,
  }) => setState(() {
    if (ids != null) this.ids = ids;
    if (activeId != null) this.activeId = activeId;
    if (width != null) this.width = width;
    if (preferences != null) this.preferences = preferences;
    if (compact != null) this.compact = compact;
    if (reducedMotion != null) this.reducedMotion = reducedMotion;
    if (widths != null) this.widths = widths;
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 40,
          child: EditorTabStrip(
            tabIds: ids,
            activeId: activeId,
            colors: colors,
            reducedMotion: reducedMotion,
            compact: compact,
            tabBuilder: (context, index) => SizedBox(
              key: ValueKey('fixture-tab:${ids[index]}'),
              width: widths[ids[index]] ?? 120,
              height: 36,
              child: TextButton(
                onPressed: () => change(activeId: ids[index]),
                child: Text(ids[index]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
