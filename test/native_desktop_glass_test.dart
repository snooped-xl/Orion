import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/widgets/native_desktop_glass.dart';

const channel = MethodChannel('orion/window');
String reply(bool active) => jsonEncode({'ok': true, 'active': active});

Widget viewport({
  bool supported = true,
  bool enabled = true,
  double opacity = .9,
  double radius = 20,
  FutureOr<void> Function(bool)? changed,
  Widget Function(BuildContext, bool)? builder,
}) => MaterialApp(
  home: NativeDesktopGlassViewport(
    supported: supported,
    enabled: enabled,
    opacity: opacity,
    cornerRadius: radius,
    onActiveChanged: changed,
    builder:
        builder ??
        (context, active) => Text(
          '$active/${NativeDesktopGlassScope.isActiveOf(context)}/'
          '${NativeDesktopGlassScope.opacityOf(context)}',
        ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call.arguments['enabled'] == true);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('unsupported never calls native or polls and scope is safe', (
    tester,
  ) async {
    await tester.pumpWidget(viewport(supported: false));
    expect(find.text('false/false/0.9'), findsOneWidget);
    await tester.pump(const Duration(seconds: 20));
    expect(calls, isEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Text(
            '${NativeDesktopGlassScope.isActiveOf(context)}/'
            '${NativeDesktopGlassScope.opacityOf(context)}',
          ),
        ),
      ),
    );
    expect(find.text('false/1.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled sends false once and opacity never writes native', (
    tester,
  ) async {
    await tester.pumpWidget(viewport(enabled: false));
    await tester.pump();
    await tester.pumpWidget(viewport(enabled: false, opacity: .7, radius: 24));
    await tester.pump(const Duration(seconds: 15));
    expect(calls, hasLength(1));
    expect(calls.single.method, 'configureDesktopGlass');
    expect(calls.single.arguments, {
      'enabled': false,
      'cornerRadius': 20.0,
      'opacity': .9,
    });
    expect(find.text('false/false/0.7'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(calls, hasLength(1));
  });

  testWidgets(
    'poll detects availability and loss without duplicate rebuild calls',
    (tester) async {
      var available = false;
      final changes = <bool>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply(available && call.arguments['enabled'] == true);
      });
      await tester.pumpWidget(viewport(changed: changes.add));
      await tester.pump();
      expect(find.text('false/false/0.9'), findsOneWidget);
      await tester.pumpWidget(viewport(changed: changes.add));
      await tester.pump();
      expect(calls, hasLength(1));
      available = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('true/true/0.9'), findsOneWidget);
      expect(changes, [true]);
      available = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('false/false/0.9'), findsOneWidget);
      expect(changes, [true, false]);
      await tester.pumpWidget(viewport(enabled: false));
      await tester.pump();
      final count = calls.length;
      await tester.pump(const Duration(seconds: 15));
      expect(calls, hasLength(count));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('active transitions retain editor controller focus and text', (
    tester,
  ) async {
    final activation = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.arguments['enabled'] == true
          ? activation.future
          : reply(false);
    });
    final controller = TextEditingController(text: 'unsaved script');
    final focus = FocusNode();
    final key = GlobalKey();
    Widget editor(BuildContext context, bool active) => Material(
      child: TextField(key: key, controller: controller, focusNode: focus),
    );
    await tester.pumpWidget(viewport(builder: editor));
    final originalElement = key.currentContext;
    focus.requestFocus();
    await tester.pump();
    activation.complete(reply(true));
    await tester.pump();
    await tester.pump();
    expect(key.currentContext, same(originalElement));
    expect(focus.hasFocus, true);
    expect(controller.text, 'unsaved script');
    await tester.pumpWidget(viewport(enabled: false, builder: editor));
    await tester.pump();
    expect(key.currentContext, same(originalElement));
    expect(focus.hasFocus, true);
    expect(controller.text, 'unsaved script');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
  });

  testWidgets(
    'late activation serializes disable and cannot reactivate scope',
    (tester) async {
      final activation = Completer<String>();
      final changes = <bool>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.arguments['enabled'] == true
            ? activation.future
            : reply(false);
      });
      await tester.pumpWidget(viewport(changed: changes.add));
      await tester.pumpWidget(viewport(enabled: false, changed: changes.add));
      expect(calls, hasLength(1));
      activation.complete(reply(true));
      await tester.pump();
      await tester.pump();
      expect(calls.map((call) => call.arguments['enabled']), [true, false]);
      expect(changes, isEmpty);
      expect(find.text('false/false/0.9'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(calls, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('support loss retains pending cleanup across radius changes', (
    tester,
  ) async {
    final activation = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.arguments['enabled'] == true
          ? activation.future
          : reply(false);
    });
    await tester.pumpWidget(viewport());
    await tester.pumpWidget(viewport(supported: false));
    await tester.pumpWidget(viewport(supported: false, radius: 30));
    activation.complete(reply(true));
    await tester.pump();
    await tester.pump();
    expect(calls.map((call) => call.arguments['enabled']), [true, false]);
    expect(find.text('false/false/0.9'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('radius changes coalesce behind the in-flight request', (
    tester,
  ) async {
    final first = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return calls.length == 1
          ? first.future
          : reply(call.arguments['enabled'] == true);
    });
    await tester.pumpWidget(viewport(radius: 20));
    await tester.pumpWidget(viewport(radius: 22));
    await tester.pumpWidget(viewport(radius: 24));
    first.complete(reply(true));
    await tester.pump();
    await tester.pump();
    expect(calls.map((call) => call.arguments['cornerRadius']), [20.0, 24.0]);
    expect(find.text('true/true/0.9'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('timed-out native requests recover and ignore their late reply', (
    tester,
  ) async {
    final first = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return calls.length == 1
          ? first.future
          : reply(call.arguments['enabled'] == true);
    });
    await tester.pumpWidget(viewport());
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('false/false/0.9'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('true/true/0.9'), findsOneWidget);
    first.complete(reply(false));
    await tester.pump();
    expect(find.text('true/true/0.9'), findsOneWidget);
    expect(calls, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(calls.last.arguments['enabled'], false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unmapped windows get three bounded retries then normal polling',
    (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return jsonEncode({
          'ok': true,
          'active': false,
          'reason': 'waiting-window',
        });
      });
      await tester.pumpWidget(viewport());
      await tester.pump();
      expect(calls, hasLength(1));
      for (final delay in [250, 750, 1500]) {
        final count = calls.length;
        await tester.pump(Duration(milliseconds: delay - 1));
        expect(calls, hasLength(count));
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        expect(calls, hasLength(count + 1));
      }
      expect(calls, hasLength(4));
      await tester.pump(const Duration(milliseconds: 2499));
      expect(calls, hasLength(4));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(calls, hasLength(5));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('disabling cancels the early unmapped-window retry', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return jsonEncode({
        'ok': true,
        'active': false,
        'reason': 'waiting-window',
      });
    });
    await tester.pumpWidget(viewport());
    await tester.pump();
    await tester.pumpWidget(viewport(enabled: false));
    await tester.pump();
    expect(calls.map((call) => call.arguments['enabled']), [true, false]);
    await tester.pump(const Duration(seconds: 15));
    expect(calls, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing pending activation restores native state once', (
    tester,
  ) async {
    final activation = Completer<String>();
    final changes = <bool>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.arguments['enabled'] == true
          ? activation.future
          : reply(false);
    });
    await tester.pumpWidget(viewport(changed: changes.add));
    await tester.pumpWidget(const SizedBox.shrink());
    activation.complete(reply(true));
    await tester.pump();
    await tester.pump();
    expect(calls.map((call) => call.arguments['enabled']), [true, false]);
    expect(changes, isEmpty);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing plugins malformed replies and platform errors recover', (
    tester,
  ) async {
    var response = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.arguments['enabled'] == false) return reply(false);
      switch (response++) {
        case 0:
          throw MissingPluginException();
        case 1:
          return '{broken';
        case 2:
          throw PlatformException(code: 'extension_unavailable');
        case 3:
          return jsonEncode({'ok': false, 'active': true});
        default:
          return reply(true);
      }
    });
    await tester.pumpWidget(viewport(opacity: double.nan, radius: double.nan));
    await tester.pump();
    expect(find.text('false/false/1.0'), findsOneWidget);
    expect(calls.single.arguments['cornerRadius'], 16);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('false/false/1.0'), findsOneWidget);
    }
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('true/true/1.0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('async host callbacks stay ordered and failures do not escape', (
    tester,
  ) async {
    final pending = Completer<void>();
    final changes = <String>[];
    Future<void> changed(bool active) async {
      changes.add('$active:start');
      if (active) await pending.future;
      changes.add('$active:end');
      if (!active) throw StateError('native window already closing');
    }

    await tester.pumpWidget(viewport(changed: changed));
    await tester.pump();
    await tester.pump();
    expect(changes, ['true:start']);
    await tester.pumpWidget(viewport(enabled: false, changed: changed));
    await tester.pump();
    expect(changes, ['true:start']);
    pending.complete();
    await tester.pump();
    expect(changes, ['true:start', 'true:end', 'false:start', 'false:end']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
