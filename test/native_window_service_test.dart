import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/native_window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <(String, MethodCall)>[];
  const plugin = MethodChannel('window_manager'),
      native = MethodChannel('orion/window');
  setUp(() {
    calls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(('plugin', call));
      return null;
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(('native', call));
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(native, null);
  });
  test(
    'startup preparation and placement stay independent of sizing and flags',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add(('native', call));
        return '{"ok":true,"mode":"gnome-window-policy","monitor":1,"reason":"waiting-window"}';
      });
      final prepared = await NativeWindowService.prepareStartupPlacement();
      final applied = await NativeWindowService.applyStartupPlacement();
      if (!Platform.isLinux && !Platform.isWindows) {
        expect(prepared['reason'], 'unsupported-platform');
        expect(applied['reason'], 'unsupported-platform');
        expect(calls, isEmpty);
        return;
      }
      expect(calls.map((call) => call.$1), ['native', 'native']);
      expect(calls.map((call) => call.$2.method), [
        'prepareStartupPlacement',
        'applyStartupPlacement',
      ]);
      expect(calls.first.$2.arguments, isNull);
      expect(calls.last.$2.arguments, {'followInitialResize': false});
      expect(prepared['monitor'], 1);
      expect(applied['mode'], 'gnome-window-policy');
    },
  );

  test(
    'source loader tracking completes once without moving later windows',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add(('native', call));
        return '{"ok":true}';
      });
      if (!Platform.isLinux && !Platform.isWindows) {
        expect(
          await NativeWindowService.applyStartupPlacement(
            followInitialResize: true,
          ),
          {'ok': false, 'reason': 'unsupported-platform'},
        );
        expect(await NativeWindowService.completeStartupPlacement(), {
          'ok': true,
          'reason': 'completed',
        });
        expect(calls, isEmpty);
        return;
      }
      await NativeWindowService.applyStartupPlacement(
        followInitialResize: true,
      );
      await NativeWindowService.completeStartupPlacement();
      await NativeWindowService.completeStartupPlacement();
      expect(calls.map((call) => call.$2.method), [
        'applyStartupPlacement',
        'completeStartupPlacement',
      ]);
      expect(calls.first.$2.arguments, {'followInitialResize': true});
      expect(calls.last.$2.arguments, isNull);
    },
  );

  test(
    'startup placement cannot prevent launch when the compositor is unavailable',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      if (!Platform.isLinux && !Platform.isWindows) {
        expect(await NativeWindowService.prepareStartupPlacement(), {
          'ok': false,
          'reason': 'unsupported-platform',
        });
        expect(calls, isEmpty);
        return;
      }
      for (final response in ['not-json', '[]', 'true', null]) {
        messenger.setMockMethodCallHandler(native, (call) async => response);
        expect(
          (await NativeWindowService.prepareStartupPlacement())['ok'],
          false,
        );
        expect(
          (await NativeWindowService.applyStartupPlacement())['ok'],
          false,
        );
      }
      messenger.setMockMethodCallHandler(native, (call) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(
        (await NativeWindowService.prepareStartupPlacement())['reason'],
        'native-placement-unavailable',
      );
      messenger.setMockMethodCallHandler(native, null);
      expect(
        (await NativeWindowService.applyStartupPlacement())['reason'],
        'native-placement-unavailable',
      );
    },
  );

  test(
    'topmost updates requested plugin hint then requests actual native state',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add(('native', call));
        return '{"ok":true,"requested":true,"above":true,"active":true,"mode":"gnome-window-policy"}';
      });
      final result = await NativeWindowService.setAlwaysOnTop(true);
      if (!Platform.isLinux) {
        expect(calls.map((call) => call.$1), ['plugin']);
        expect(calls.single.$2.method, 'setAlwaysOnTop');
        expect(calls.single.$2.arguments, {'isAlwaysOnTop': true});
        expect(result, {
          'ok': true,
          'requested': true,
          'mode': 'platform-hint',
        });
        return;
      }
      expect(calls.map((call) => call.$1), ['plugin', 'native']);
      expect(calls.map((call) => call.$2.method), [
        'setAlwaysOnTop',
        'setAlwaysOnTop',
      ]);
      expect(calls[0].$2.arguments, {'isAlwaysOnTop': true});
      expect(calls[1].$2.arguments, {'enabled': true});
      expect(result['above'], true);
      expect(result['mode'], 'gnome-window-policy');
    },
  );
  test('unavailable compositor never becomes cached topmost success', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      native,
      (call) async => '{"ok":false,"active":false,"reason":"unavailable"}',
    );
    final result = await NativeWindowService.setAlwaysOnTop(true);
    expect(result['ok'], false);
    expect(result['active'], false);
    expect(result['reason'], 'unavailable');
  }, skip: !Platform.isLinux);
  test('disabling topmost sends only the window-policy switch', () async {
    final result = await NativeWindowService.setAlwaysOnTop(false);
    if (!Platform.isLinux) {
      expect(calls.map((call) => call.$2.method), ['setAlwaysOnTop']);
      expect(calls.single.$2.arguments, {'isAlwaysOnTop': false});
      expect(result['ok'], true);
      return;
    }
    expect(calls.map((call) => call.$2.method), [
      'setAlwaysOnTop',
      'setAlwaysOnTop',
    ]);
    expect(calls.last.$2.arguments, {'enabled': false});
    expect(result['ok'], false); // A null mock is not compositor confirmation.
  });
  test('malformed and missing native policy responses are handled', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final response in ['not-json', '[]', 'true', null]) {
      messenger.setMockMethodCallHandler(native, (call) async => response);
      final result = await NativeWindowService.setAlwaysOnTop(true);
      expect(result['ok'], false);
      expect(result['requested'], true);
    }
    messenger.setMockMethodCallHandler(native, null);
    final result = await NativeWindowService.setAlwaysOnTop(false);
    expect(result['ok'], false);
    expect(result['reason'], 'native-window-policy-unavailable');
  }, skip: !Platform.isLinux);

  test(
    'minimum size reaches plugin then internal GTK channel for each source profile',
    () async {
      for (final size in [
        const Size(418, 117),
        const Size(265, 171),
        const Size(720, 480),
        const Size(600, 300),
      ]) {
        calls.clear();
        await NativeWindowService.setMinimumSize(size);
        expect(calls.map((c) => c.$1), [
          'plugin',
          if (Platform.isLinux) 'native',
        ]);
        expect(calls.every((c) => c.$2.method == 'setMinimumSize'), true);
        for (final call in calls) {
          expect((call.$2.arguments as Map)['width'], size.width);
          expect((call.$2.arguments as Map)['height'], size.height);
        }
      }
    },
  );
  test('invalid minima fail before changing either native API', () async {
    for (final size in [
      const Size(0, 117),
      const Size(418, -1),
      const Size(double.nan, 117),
      const Size(418, double.infinity),
      const Size(16385, 117),
    ]) {
      await expectLater(
        NativeWindowService.setMinimumSize(size),
        throwsArgumentError,
      );
    }
    expect(calls, isEmpty);
  });
  test(
    'corner radius opts into the native input region without resizing',
    () async {
      await NativeWindowService.setCornerRadius(20);
      await NativeWindowService.setCornerRadius(0);
      if (!Platform.isLinux && !Platform.isWindows) {
        expect(calls, isEmpty);
        return;
      }
      expect(calls.map((call) => call.$1), ['native', 'native']);
      expect(calls.map((call) => call.$2.method), [
        'setCornerRadius',
        'setCornerRadius',
      ]);
      expect(calls.map((call) => call.$2.arguments), [
        {'radius': 20.0},
        {'radius': 0.0},
      ]);
    },
  );
  test('invalid corner radii leave the native shape unchanged', () async {
    for (final radius in [-1.0, 65.0, double.nan, double.infinity]) {
      await expectLater(
        NativeWindowService.setCornerRadius(radius),
        throwsArgumentError,
      );
    }
    expect(calls, isEmpty);
  });
}
