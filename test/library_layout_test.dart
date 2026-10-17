import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/remote_script.dart';
import 'package:orion/screens/library_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

const _short = RemoteScript(
  id: 'short',
  provider: ScriptProvider.scriptBlox,
  title: 'Quiet example',
  game: 'Test place',
  description: 'A short description.',
  body: 'print("quiet")',
  externalUrl: 'https://scriptblox.com/script/short',
  views: 1,
);
const _long = RemoteScript(
  id: 'long',
  provider: ScriptProvider.robloxScripts,
  title:
      'A much longer script title that spans more than one line without moving the card actions',
  game: 'A place with a considerably longer name',
  description:
      'A longer description stays available without adding uneven rows to cards.',
  body: 'print("long")',
  externalUrl: 'https://robloxscripts.com/script/long',
  views: 2000,
  hasKey: true,
  isVerified: true,
  isPaid: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final ui = FontLoader('RobotoFlex');
    for (final asset in [
      'assets/fonts/RobotoFlex-Regular.ttf',
      'assets/fonts/RobotoFlex-Medium.ttf',
      'assets/fonts/RobotoFlex-Semibold.ttf',
    ]) {
      ui.addFont(rootBundle.load(asset));
    }
    await ui.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final size in [const Size(1080, 720), const Size(860, 600)]) {
    testWidgets(
      'hub cards align titles and actions at ${size.width.toInt()} pixels',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _LayoutController()..setReducedMotion(true);
        addTearDown(controller.dispose);
        await controller.flushPersistence();
        await tester.pumpWidget(
          MaterialApp(
            theme: orionTheme(Brightness.dark, controller.accentColor),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.fromLTRB(92, 60, 12, 12),
                child: LibraryScreen(
                  controller: controller,
                  onOpenWorkspace: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final firstImage = tester.getRect(
          find.byKey(ValueKey('image/${_short.key}')),
        );
        final secondImage = tester.getRect(
          find.byKey(ValueKey('image/${_long.key}')),
        );
        expect(firstImage.top, closeTo(secondImage.top, .1));
        expect(firstImage.width, closeTo(secondImage.width, .1));
        expect(firstImage.right, lessThan(secondImage.left));
        final firstAction = find.byKey(ValueKey('execute/${_short.key}'));
        final secondAction = find.byKey(ValueKey('execute/${_long.key}'));
        expect(
          tester.getRect(firstAction).top,
          closeTo(tester.getRect(secondAction).top, .1),
        );
        expect(find.text('View code'), findsNWidgets(2));
        expect(find.text('On source'), findsNWidgets(2));
        expect(find.text('Open'), findsNWidgets(2));
        expect(find.byType(TextField), findsOneWidget);
        expect(find.byType(FilterChip), findsNWidgets(6));

        await tester.ensureVisible(firstAction);
        await tester.tap(firstAction);
        await tester.pumpAndSettle();
        expect(controller.executed, _short.key);
        await tester.ensureVisible(find.byTooltip('Add to favorites').first);
        await tester.tap(find.byTooltip('Add to favorites').first);
        await tester.pumpAndSettle();
        expect(controller.isRemoteFavorite(_short.key), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.flushPersistence();
      },
    );
  }
}

class _LayoutController extends OrionController {
  String? executed;

  @override
  List<RemoteScript> get remoteScripts => const [_short, _long];

  @override
  Future<void> executeRemoteScript(RemoteScript script) async {
    executed = script.key;
  }
}
