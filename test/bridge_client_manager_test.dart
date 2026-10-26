import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/bridge_models.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_overlay.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/widgets/bridge_client_manager.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

const _alex = BridgeClient(
  identifier: 'User1',
  username: 'Alex',
  transport: 'port',
  sessionId: 'alex',
);
const _sam = BridgeClient(
  identifier: 'User2',
  username: 'Sam',
  transport: 'websocket',
  sessionId: 'sam',
);

class _Controller extends OrionController {
  _Controller({bool useMacSploit = false, super.nativeExecutorPreference})
    : super(persistChanges: false, useMacSploit: useMacSploit) {
    setReducedMotion(true);
  }
  final disconnected = <String>[];
  int saved = 0, retried = 0;
  bool failScript = false;
  void clients(
    List<BridgeClient> clients, {
    bool listening = true,
    String? error,
  }) {
    applyWindowState({
      ...exportWindowState(),
      'bridgeClients': clients.map((v) => v.toJson()).toList(),
      'bridgeListening': listening,
      'bridgeError': error,
    });
  }

  @override
  void disconnectBridgeClient(String identifier) {
    disconnected.add(identifier);
    clients(bridgeClients.where((c) => c.identifier != identifier).toList());
  }

  @override
  void disconnectAllBridgeClients() {
    disconnected.addAll(bridgeClients.map((c) => c.identifier));
    clients([]);
  }

  @override
  Future<bool> initializeBridge({int port = 31337}) async {
    retried++;
    clients(bridgeClients);
    return true;
  }

  @override
  Future<String> loadBridgeScript() async {
    if (failScript) throw const FormatException('fixture unavailable');
    return 'print("bridge fixture")';
  }

  @override
  Future<bool> saveBridgeScript({bool rethrowErrors = false}) async {
    saved++;
    return true;
  }
}

class _Editor extends MonacoEditorService {
  _Editor() : super(onChange: (_, _) {}, onShortcut: (_) {});
  final hidden = <bool>[];
  @override
  Future<void> freezeForOverlay({String owner = 'route'}) async {
    hidden.add(true);
  }

  @override
  void setObscured(bool value, {String owner = 'route'}) {
    hidden.add(value);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Controller c, {
  Size size = const Size(822, 523),
  double scale = 1,
  _Editor? editor,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => UiScaleViewport(scale: scale, child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-manager'),
            onPressed: () => unawaited(
              showBridgeClientManager(
                context,
                controller: c,
                editorService: editor,
              ),
            ),
            child: const Text('Clients'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-manager')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('MacSploit manager explains first-responsive execution', (
    tester,
  ) async {
    final c = _Controller(useMacSploit: true)
      ..clients([
        const BridgeClient(
          identifier: 'User1',
          username: 'Roblox',
          transport: 'MacSploit',
          sessionId: 'macsploit:5553',
        ),
      ]);
    await _mount(tester, c);
    expect(
      find.textContaining('Available ports: 5553, 5554, 5555'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('bridge-target-mode')), findsNothing);
    expect(find.byKey(const ValueKey('bridge-copy-loader')), findsNothing);
    expect(find.byKey(const ValueKey('bridge-copy-script')), findsNothing);
    expect(find.byKey(const ValueKey('bridge-save-script')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('native manager offers executor and port selectors', (
    tester,
  ) async {
    final c = _Controller(
      useMacSploit: true,
      nativeExecutorPreference: 'opiumware',
    );
    await _mount(tester, c);
    expect(
      find.byKey(const ValueKey('native-executor-selector')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('native-port-selector')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('native-executor-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opiumware').last);
    await tester.pumpAndSettle();
    expect(c.nativeExecutorPreference, 'opiumware');
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('native-port-description-auto')),
              matching: find.byType(Text),
            ),
          )
          .data,
      'Available ports: 8392, 8393, 8394, 8395, 8396, 8397',
    );
    await tester.tap(find.byKey(const ValueKey('native-port-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8395').last);
    await tester.pumpAndSettle();
    expect(c.nativePortPreference, 8395);
    if (Platform.isMacOS) {
      await tester.tap(find.byKey(const ValueKey('native-executor-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Helios').last);
      await tester.pumpAndSettle();
      expect(c.nativeExecutorPreference, 'helios');
      expect(
        c.availableNativePorts,
        List.generate(10, (index) => 5553 + index),
      );
      await tester.tap(find.byKey(const ValueKey('native-port-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5558').last);
      await tester.pumpAndSettle();
      expect(c.nativePortPreference, 5558);
    }
    final expectedPort = Platform.isMacOS ? 5558 : 8395;
    final pinnedDescription = find.byKey(
      ValueKey('native-port-description-${c.nativePortPreference ?? 'auto'}'),
    );
    expect(pinnedDescription, findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: pinnedDescription, matching: find.byType(Text)),
          )
          .data,
      'Pinned to localhost:$expectedPort',
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'live clients share all and explicit targets and disconnect individually',
    (tester) async {
      final c = _Controller()..clients([_alex, _sam]);
      await _mount(tester, c);
      expect(find.text('2 connected'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('port · User1'), findsOneWidget);
      expect(find.text('websocket · User2'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(c.bridgeTargetAll, false);
      expect(c.selectedBridgeClients, {'User2'});
      expect(find.text('1 of 2 selected for Execute.'), findsOneWidget);
      await tester.tap(find.text('All clients'));
      await tester.pumpAndSettle();
      expect(c.bridgeTargetAll, true);
      await tester.tap(find.byTooltip('Disconnect Alex'));
      await tester.pumpAndSettle();
      expect(c.disconnected, ['User1']);
      expect(find.text('1 connected'), findsOneWidget);
      expect(find.text('Alex'), findsNothing);
      c.clients([
        _sam,
        const BridgeClient(
          identifier: 'User3',
          username: 'Jamie',
          transport: 'port',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Jamie'), findsOneWidget);
      await tester.tap(find.text('Disconnect all'));
      await tester.pumpAndSettle();
      expect(find.text('No clients connected'), findsOneWidget);
      expect(c.documents, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'setup copies loader or exact full script and saves via controller',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final c = _Controller()..clients([]);
      await _mount(tester, c);
      await tester.ensureVisible(
        find.byKey(const ValueKey('bridge-copy-loader')),
      );
      await tester.tap(find.byKey(const ValueKey('bridge-copy-loader')));
      await tester.pumpAndSettle();
      expect(clipboard, c.bridgeLoader);
      expect(find.text('Loader copied'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bridge-copy-script')));
      await tester.pumpAndSettle();
      expect(clipboard, 'print("bridge fixture")');
      await tester.tap(find.byKey(const ValueKey('bridge-save-script')));
      await tester.pumpAndSettle();
      expect(c.saved, 1);
      expect(find.text('Orion Bridge.lua saved'), findsOneWidget);
      c.failScript = true;
      await tester.tap(find.byKey(const ValueKey('bridge-copy-script')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not copy bridge'), findsOneWidget);
      expect(clipboard, 'print("bridge fixture")');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'offline errors allow retry and native editor stays hidden until modal closes',
    (tester) async {
      final c = _Controller()
        ..clients([], listening: false, error: 'Port is already in use');
      final editor = _Editor();
      await _mount(tester, c, editor: editor);
      expect(editor.hidden, [true]);
      expect(find.text('Port is already in use'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bridge-retry')));
      await tester.pumpAndSettle();
      expect(c.retried, 1);
      expect(find.text('Waiting for clients'), findsOneWidget);
      expect(find.byKey(const ValueKey('bridge-retry')), findsNothing);
      await tester.tap(find.byTooltip('Close client manager'));
      await tester.pumpAndSettle();
      expect(editor.hidden, [true, false]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      editor.dispose();
    },
  );

  testWidgets(
    'open manager follows Theme Control while preserving client selection',
    (tester) async {
      final c = _Controller()..clients([_alex, _sam]);
      await _mount(tester, c);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      c.setOrionTheme(
        OrionThemePreferences(
          accent: const Color(0xffe6ad79),
          gradientEnabled: true,
          gradientColors: const [Color(0xff191c15), Color(0xff2b1a23)],
        ),
      );
      await tester.pumpAndSettle();
      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('orion-overlay-decoration')),
      );
      var colors = OrionColors.of(
        tester.element(find.byType(OrionOverlaySurface)),
      );
      expect(colors.accent, const Color(0xffe6ad79));
      expect(
        (surface.decoration! as BoxDecoration).gradient,
        orionOverlayGradient(colors),
      );
      expect(
        tester
            .widget<Dialog>(find.byKey(const ValueKey('bridge-client-manager')))
            .backgroundColor,
        Colors.transparent,
      );
      expect(c.selectedBridgeClients, {'User2'});
      c.setOrionTheme(
        OrionThemePreferences.builtInPresets
            .singleWhere((p) => p.id == 'original-orion')
            .preferences,
      );
      await tester.pumpAndSettle();
      colors = OrionColors.of(tester.element(find.byType(OrionOverlaySurface)));
      expect(colors.accent, OrionThemePreferences.originalAccent);
      final row = find
          .ancestor(of: find.text('Sam'), matching: find.byType(Container))
          .first;
      final rowDecoration =
          tester.widget<Container>(row).decoration! as BoxDecoration;
      expect(rowDecoration.color, colors.stateFill(.09, base: colors.elevated));
      expect(rowDecoration.border!.top.width, .67);
      expect(c.selectedBridgeClients, {'User2'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final layout in [
    (const Size(822, 523), 1.0),
    (const Size(740, 470), 1.25),
    (const Size(521, 365), 1.25),
    (const Size(300, 200), 1.0),
  ]) {
    testWidgets(
      'manager fits ${layout.$1} at ${layout.$2} GUI scale with many clients',
      (tester) async {
        final c = _Controller()
          ..clients([
            _alex,
            _sam,
            for (var n = 3; n < 10; n++)
              BridgeClient(
                identifier: 'User$n',
                username: 'Player $n',
                transport: 'port',
              ),
          ]);
        await _mount(tester, c, size: layout.$1, scale: layout.$2);
        expect(
          find.byKey(const ValueKey('bridge-client-manager')),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Close client manager').hitTestable(),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Connect a client'));
        await tester.pumpAndSettle();
        expect(find.text('Connect a client').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close client manager'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
