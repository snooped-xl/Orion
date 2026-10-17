import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/widgets/monaco_editor.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _GeometryService extends MonacoEditorService {
  _GeometryService(this.mirror, this.frame)
    : super(onChange: (_, _) {}, onShortcut: (_) {});
  final bool mirror;
  final ValueNotifier<ui.Image?> frame;
  int measurements = 0;

  @override
  bool get visualMirror => mirror;
  @override
  ValueListenable<ui.Image?> get visualMirrorFrame => frame;
  @override
  Future<void> initialize() async {
    ready = true;
    notifyListeners();
  }

  @override
  Future<void> setBounds({
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    measurements++;
  }

  @override
  void setActive(bool active) {}
  @override
  void setMirrorPresentationActive(bool active, {required Object owner}) {}
  @override
  void mirrorFramePresented(ui.Image image) {}
}

void main() {
  for (final mirror in [false, true]) {
    for (final scale in [1.0, 1.25]) {
      testWidgets(
        'resize updates native geometry once without rebuilding the editor, mirror=$mirror scale=$scale',
        (tester) async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 4, 2),
            Paint()..color = Colors.blue,
          );
          final picture = recorder.endRecording();
          final image = (await tester.runAsync(() => picture.toImage(4, 2)))!;
          picture.dispose();
          final frame = ValueNotifier<ui.Image?>(image);
          final service = _GeometryService(mirror, frame);
          final size = ValueNotifier<Size>(const Size(500.3, 320.7));
          final editor = MonacoEditor(
            service: service,
            active: true,
            backgroundColor: Colors.transparent,
          );
          final previousDebugCallback = debugOnRebuildDirtyWidget;
          try {
            await tester.pumpWidget(
              MaterialApp(
                builder: (_, child) =>
                    UiScaleViewport(scale: scale, child: child!),
                home: Center(
                  child: ValueListenableBuilder<Size>(
                    valueListenable: size,
                    child: editor,
                    builder: (_, value, child) =>
                        SizedBox.fromSize(size: value, child: child),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            var builds = 0;
            debugOnRebuildDirtyWidget = (element, _) {
              if (element.widget is MonacoEditor) builds++;
            };
            service.measurements = 0;
            for (var n = 1; n <= 24; n++) {
              size.value = Size(500.3 - n * 2.37, 320.7 - n * 1.43);
              await tester.pump();
              await tester.pump();
              if (mirror) {
                final editorRect = tester.getRect(find.byType(MonacoEditor));
                final imageRect = tester.getRect(
                  find.byKey(const ValueKey('monaco-visual-mirror')),
                );
                expect(
                  imageRect.left,
                  closeTo(editorRect.left.floorToDouble(), .001),
                );
                expect(
                  imageRect.top,
                  closeTo(editorRect.top.floorToDouble(), .001),
                );
                expect(
                  imageRect.width,
                  closeTo(editorRect.width.ceilToDouble(), .001),
                );
                expect(
                  imageRect.height,
                  closeTo(editorRect.height.ceilToDouble(), .001),
                );
              }
            }
            expect(builds, 0);
            expect(service.measurements, 24);
            expect(tester.takeException(), isNull);
          } finally {
            debugOnRebuildDirtyWidget = previousDebugCallback;
            await tester.pumpWidget(const SizedBox.shrink());
            service.dispose();
            size.dispose();
            frame.dispose();
            image.dispose();
          }
        },
      );
    }
  }
}
