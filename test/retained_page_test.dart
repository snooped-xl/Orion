import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/widgets/retained_page.dart';

void main() {
  testWidgets('invisible pages retain theme, viewport and layout until shown', (
    tester,
  ) async {
    var visible = true;
    var width = 300.0;
    var color = Colors.blue;
    var builds = 0;
    var layouts = 0;
    var version = 0;
    late StateSetter update;
    final values = <(Color, Size, BoxConstraints, int)>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: ThemeData(colorSchemeSeed: color),
            home: Center(
              child: SizedBox(
                width: width,
                height: 180,
                child: MediaQuery(
                  data: MediaQueryData(size: Size(width, 180)),
                  child: Offstage(
                    offstage: !visible,
                    child: RetainedPage(
                      visible: visible,
                      child: _LayoutCounter(
                        onLayout: () => layouts++,
                        child: Builder(
                          builder: (context) {
                            builds++;
                            final themeColor = Theme.of(
                              context,
                            ).colorScheme.primary;
                            final size = MediaQuery.sizeOf(context);
                            final currentVersion = version;
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                values.add((
                                  themeColor,
                                  size,
                                  constraints,
                                  currentVersion,
                                ));
                                return const SizedBox.expand();
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pump();
    final hidden = values.last;
    builds = 0;
    layouts = 0;
    values.clear();
    for (var index = 0; index < 20; index++) {
      update(() {
        width += 4;
        color = Colors.primaries[index % Colors.primaries.length];
        version++;
      });
      await tester.pump();
    }
    expect(builds, 0);
    expect(layouts, 0);
    expect(values, isEmpty);

    update(() => visible = true);
    await tester.pumpAndSettle();
    final shown = values.last;
    expect(shown.$1, isNot(hidden.$1));
    expect(shown.$2, const Size(380, 180));
    expect(shown.$3, BoxConstraints.tight(const Size(380, 180)));
    expect(shown.$4, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'identical visible pages follow theme, text and icons at fixed bounds',
    (tester) async {
      final frame = ValueNotifier(0);
      addTearDown(frame.dispose);
      final seen = <(Color, Color?, double?, Color?, double?)>[];
      // Keep this exact widget instance throughout every inherited animation.
      final retained = RetainedPage(
        visible: true,
        child: Builder(
          builder: (context) {
            final text = DefaultTextStyle.of(context).style;
            final icon = IconTheme.of(context);
            seen.add((
              Theme.of(context).colorScheme.primary,
              text.color,
              text.fontSize,
              icon.color,
              icon.size,
            ));
            return const Row(children: [Text('Preview'), Icon(Icons.code)]);
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: frame,
            builder: (context, frame, child) => Theme(
              data: ThemeData(colorSchemeSeed: Colors.primaries[frame]),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: Colors.accents[frame],
                  fontSize: 14 + frame.toDouble(),
                ),
                child: IconTheme(
                  data: IconThemeData(
                    color: Colors.primaries[frame + 1],
                    size: 20 + frame.toDouble(),
                  ),
                  child: child!,
                ),
              ),
            ),
            child: retained,
          ),
        ),
      );
      for (var index = 1; index < 8; index++) {
        frame.value = index;
        await tester.pump();
        expect(seen.last, (
          ThemeData(
            colorSchemeSeed: Colors.primaries[index],
          ).colorScheme.primary,
          Colors.accents[index],
          14 + index.toDouble(),
          Colors.primaries[index + 1],
          20 + index.toDouble(),
        ));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mounted hidden content keeps its own live subscriptions', (
    tester,
  ) async {
    final value = ValueNotifier(0);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Offstage(
          child: RetainedPage(
            visible: false,
            child: ValueListenableBuilder<int>(
              valueListenable: value,
              builder: (context, value, child) => Text('$value'),
            ),
          ),
        ),
      ),
    );
    value.value = 42;
    await tester.pump();
    expect(find.text('42', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible and departing pages inherit each animation frame', (
    tester,
  ) async {
    final inherited = ValueNotifier(0);
    addTearDown(inherited.dispose);
    final seen = <(Size, Color)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: inherited,
          builder: (context, frame, child) => MediaQuery(
            data: MediaQueryData(size: Size(300 + frame.toDouble(), 180)),
            child: Theme(
              data: ThemeData(colorSchemeSeed: Colors.primaries[frame]),
              child: RetainedPage(
                // An outgoing page remains visible until its fade completes.
                visible: true,
                child: Builder(
                  builder: (context) {
                    seen.add((
                      MediaQuery.sizeOf(context),
                      Theme.of(context).colorScheme.primary,
                    ));
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var frame = 1; frame < 8; frame++) {
      inherited.value = frame;
      await tester.pump();
      expect(seen.last.$1, Size(300 + frame.toDouble(), 180));
      expect(
        seen.last.$2,
        ThemeData(colorSchemeSeed: Colors.primaries[frame]).colorScheme.primary,
      );
    }
    expect(tester.takeException(), isNull);
  });
}

class _LayoutCounter extends SingleChildRenderObjectWidget {
  const _LayoutCounter({required this.onLayout, required super.child});
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutCounter(onLayout);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLayoutCounter renderObject,
  ) => renderObject.onLayout = onLayout;
}

class _RenderLayoutCounter extends RenderProxyBox {
  _RenderLayoutCounter(this.onLayout);
  VoidCallback onLayout;
  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}
