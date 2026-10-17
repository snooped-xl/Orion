import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_x/synapse_x_shell.dart';
import 'package:orion/synapse_x/synapse_x_pages.dart';
import 'package:orion/synapse_og/synapse_og_shell.dart';
import 'package:orion/synapse_og/og_pages.dart';

class _Host implements CompanionWindowHost {
  _Host({this.kind});
  @override
  final CompanionWindowKind? kind;
  @override
  bool get isChildWindow => kind != null;
  @override
  String? get documentId => null;
  final opened = <CompanionWindowKind>[];
  final flags = <({bool? alwaysOnTop, bool? resizable})>[];
  int closes = 0, closeAlls = 0, returns = 0, focuses = 0;
  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) async =>
      opened.add(kind);
  @override
  Future<void> close() async => closes++;
  @override
  Future<void> closeAll() async => closeAlls++;
  @override
  Future<void> focusMain() async => focuses++;
  @override
  Future<void> returnToOrion() async => returns++;
  @override
  Future<void> updateOwnerWindow({
    bool? alwaysOnTop,
    bool? resizable,
    double? opacity,
  }) async => flags.add((alwaysOnTop: alwaysOnTop, resizable: resizable));
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('SynapseInter');
    for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
      loader.addFont(
        rootBundle.load('assets/synapse_v3/fonts/Inter-$weight.ttf'),
      );
    }
    await loader.load();
    await (FontLoader('SynapseXMono')..addFont(
          rootBundle.load('assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
        ))
        .load();
  });

  Future<void> mount(
    WidgetTester tester,
    OrionController c, {
    required bool og,
    required Size size,
    MonacoEditorService? service,
    GlobalKey<SynapseXShellState>? xKey,
    GlobalKey<SynapseOgShellState>? ogKey,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => rootBundle.loadString('assets/synapse_og/scriptDumperLegacy.lua'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          type: MaterialType.transparency,
          child: og
              ? SynapseOgShell(
                  key: ogKey,
                  controller: c,
                  nativeWindow: false,
                  playIntro: c.companionWindows!.isChildWindow,
                  editorService: service,
                  onBackToOrion: () => fail('Use the companion host'),
                )
              : SynapseXShell(
                  key: xKey,
                  controller: c,
                  nativeWindow: false,
                  playIntro: c.companionWindows!.isChildWindow,
                  editorService: service,
                  onBackToOrion: () => fail('Use the companion host'),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final og in [false, true]) {
    testWidgets(
      '${og ? 'OG' : 'X'} opens native companions while its editor stays mounted',
      (tester) async {
        final c = OrionController(persistChanges: false)
          ..setReducedMotion(true);
        final host = _Host();
        c.companionWindows = host;
        final xKey = GlobalKey<SynapseXShellState>();
        final ogKey = GlobalKey<SynapseOgShellState>();
        const draft = 'print("unsaved native window draft")';
        c.updateDocumentContent(c.activeDocumentId, draft);
        try {
          await mount(
            tester,
            c,
            og: og,
            size: og ? OgGeometry.main : const Size(801, 355),
            xKey: xKey,
            ogKey: ogKey,
          );
          final editor = find.byKey(const ValueKey('code-editor'));
          final before = tester.getRect(editor);
          await tester.tap(find.text(og ? 'Settings & Clients' : 'Options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Script Hub'));
          await tester.pumpAndSettle();
          if (og) {
            ogKey.currentState!.handleEditorShortcut('console');
          } else {
            xKey.currentState!.handleEditorShortcut('console');
          }
          await tester.pumpAndSettle();
          expect(
            host.opened,
            og
                ? [
                    CompanionWindowKind.synapseOgSettings,
                    CompanionWindowKind.synapseOgHub,
                    CompanionWindowKind.synapseOgConsole,
                  ]
                : [
                    CompanionWindowKind.synapseXOptions,
                    CompanionWindowKind.synapseXHub,
                    CompanionWindowKind.synapseXConsole,
                  ],
          );
          expect(tester.getRect(editor), before);
          expect(c.activeDocument.content, draft);
          expect(c.activeDocument.isDirty, isTrue);
          if (og) {
            ogKey.currentState!.onWindowClose();
          } else {
            xKey.currentState!.onWindowClose();
          }
          await tester.pumpAndSettle();
          expect(host.closeAlls, 1);
          expect(host.closes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        }
      },
    );
  }

  for (final entry in [
    (
      CompanionWindowKind.synapseXOptions,
      false,
      const Size(528, 460),
      SynapseXOptions,
    ),
    (CompanionWindowKind.synapseXHub, false, const Size(612, 384), SynapseXHub),
    (
      CompanionWindowKind.synapseXConsole,
      false,
      const Size(520, 300),
      SynapseXConsole,
    ),
    (
      CompanionWindowKind.synapseOgSettings,
      true,
      const Size(649, 705),
      OgSettingsPage,
    ),
    (CompanionWindowKind.synapseOgHub, true, const Size(612, 384), OgHubPage),
    (
      CompanionWindowKind.synapseOgConsole,
      true,
      const Size(520, 300),
      OgConsolePage,
    ),
  ]) {
    testWidgets('${entry.$1.name} starts directly without a loader or Monaco', (
      tester,
    ) async {
      final c = OrionController(persistChanges: false)..setReducedMotion(true);
      final host = _Host(kind: entry.$1);
      c.companionWindows = host;
      final service = MonacoEditorService(
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      final xKey = GlobalKey<SynapseXShellState>();
      final ogKey = GlobalKey<SynapseOgShellState>();
      try {
        await mount(
          tester,
          c,
          og: entry.$2,
          size: entry.$3,
          service: service,
          xKey: xKey,
          ogKey: ogKey,
        );
        expect(find.byType(entry.$4), findsOneWidget);
        expect(find.byKey(const ValueKey('code-editor')), findsNothing);
        expect(service.ready, isFalse);
        expect(service.initializing, isFalse);
        expect(service.error, isNull);
        if (entry.$2) {
          ogKey.currentState!.onWindowClose();
        } else {
          xKey.currentState!.onWindowClose();
        }
        await tester.pumpAndSettle();
        expect(host.closes, 1);
        expect(host.closeAlls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        service.dispose();
      }
    });
  }

  for (final og in [false, true]) {
    testWidgets(
      '${og ? 'OG' : 'X'} settings mirror flags and Back to Orion to the owner',
      (tester) async {
        final c = OrionController(persistChanges: false)
          ..setReducedMotion(true);
        final host = _Host(
          kind: og
              ? CompanionWindowKind.synapseOgSettings
              : CompanionWindowKind.synapseXOptions,
        );
        c.companionWindows = host;
        try {
          await mount(
            tester,
            c,
            og: og,
            size: og ? OgGeometry.settings : const Size(528, 460),
          );
          for (final label in ['Top Most', 'Resizable']) {
            await tester.ensureVisible(find.text(label));
            await tester.tap(find.text(label));
            await tester.pumpAndSettle();
          }
          final prefs = c.getInterfacePreferences(
            og ? InterfacePreset.synapse2017 : InterfacePreset.synapseX,
          );
          expect(prefs['alwaysOnTop'], isTrue);
          expect(prefs['resizable'], isTrue);
          expect(host.flags.any((value) => value.alwaysOnTop == true), isTrue);
          expect(host.flags.any((value) => value.resizable == true), isTrue);
          final back = find.byKey(
            ValueKey(og ? 'og-back-to-orion' : 'x-back-to-orion'),
          );
          await tester.ensureVisible(back);
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(host.returns, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        }
      },
    );
  }
}
