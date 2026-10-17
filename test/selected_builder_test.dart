import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/widgets/selected_builder.dart';

class _State extends ChangeNotifier {
  int selected = 0;
  bool get listening => hasListeners;
  void update([int? value]) {
    if (value != null) selected = value;
    notifyListeners();
  }
}

class _Child extends StatelessWidget {
  const _Child(this.onBuild);
  final VoidCallback onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox(width: 20, height: 20);
  }
}

void main() {
  testWidgets('filters unrelated changes while preserving its shared child', (
    tester,
  ) async {
    final state = _State();
    var builds = 0;
    var childBuilds = 0;
    final child = _Child(() => childBuilds++);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SelectedBuilder(
          listenable: state,
          select: () => (state.selected, 'immutable record'),
          child: child,
          builder: (_, child) {
            builds++;
            return Column(children: [Text('${state.selected}'), child!]);
          },
        ),
      ),
    );
    expect(builds, 1);
    for (var index = 0; index < 100; index++) {
      state.update();
      await tester.pump();
    }
    expect(builds, 1);
    state.update(1);
    await tester.pump();
    expect(builds, 2);
    expect(find.text('1'), findsOneWidget);
    expect(childBuilds, 1);
    await tester.pumpWidget(const SizedBox());
    expect(state.listening, isFalse);
    state.dispose();
  });

  testWidgets('updates selectors and replaces or detaches listening sources', (
    tester,
  ) async {
    final first = _State();
    final second = _State();
    var builds = 0;
    Widget host(_State source, int offset) => Directionality(
      textDirection: TextDirection.ltr,
      child: SelectedBuilder(
        listenable: source,
        select: () => source.selected + offset,
        builder: (_, _) {
          builds++;
          return Text('${source.selected + offset}');
        },
      ),
    );
    await tester.pumpWidget(host(first, 0));
    await tester.pumpWidget(host(first, 10));
    expect(find.text('10'), findsOneWidget);
    first.update();
    await tester.pump();
    expect(builds, 2, reason: 'parent selector replaces cached selection');
    await tester.pumpWidget(host(second, 20));
    expect(first.listening, isFalse);
    expect(second.listening, isTrue);
    first.update(3);
    await tester.pump();
    expect(builds, 3);
    second.update(2);
    await tester.pump();
    expect(builds, 4);
    expect(find.text('22'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(second.listening, isFalse);
    first.dispose();
    second.dispose();
  });

  testWidgets('inherited theme and layout changes still rebuild normally', (
    tester,
  ) async {
    final state = _State();
    var builds = 0;
    final selected = SelectedBuilder(
      listenable: state,
      select: () => state.selected,
      builder: (context, _) {
        builds++;
        return ColoredBox(
          color: Theme.of(context).colorScheme.primary,
          child: SizedBox(width: MediaQuery.sizeOf(context).width),
        );
      },
    );
    Widget host(Color color, Size size) => Theme(
      data: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: color)),
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: selected,
      ),
    );
    await tester.pumpWidget(host(Colors.blue, const Size(700, 450)));
    await tester.pumpWidget(host(Colors.red, const Size(500, 400)));
    expect(builds, 2);
    expect(
      tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
      ColorScheme.fromSeed(seedColor: Colors.red).primary,
    );
    expect(tester.widget<SizedBox>(find.byType(SizedBox)).width, 500);
    state.update();
    await tester.pump();
    expect(builds, 2);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
