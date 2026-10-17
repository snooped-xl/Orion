import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/local_script.dart';
import 'package:orion/services/script_library_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/script_code_text.dart';
import 'package:orion/widgets/script_explorer.dart';

class _Library extends ScriptLibraryService {
  _Library(Directory directory, this.items) : super(directory: directory);

  List<LocalScriptEntry> items;
  int reads = 0;

  @override
  List<LocalScriptEntry> get entries {
    reads++;
    return items;
  }

  void refreshView() => notifyListeners();
}

LocalScriptEntry _file(
  Directory directory,
  String name, {
  ScriptColorCode code = ScriptColorCode.none,
  bool folder = false,
}) => LocalScriptEntry(
  relativePath: name,
  name: name.split('/').last,
  path: '${directory.path}/$name',
  isDirectory: folder,
  code: code,
);

void main() {
  late Directory directory;
  late OrionController controller;
  late _Library library;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('orion-explorer-perf-');
    controller = OrionController(persistChanges: false)..setReducedMotion(true);
    library = _Library(directory, [_file(directory, 'example.lua')]);
  });

  tearDown(() {
    controller.dispose();
    library.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    ThemeData? theme,
    Future<void> Function(String)? onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? orionTheme(Brightness.dark, Colors.blue),
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 400,
            child: ScriptExplorer(
              controller: controller,
              library: library,
              onOpenScript: onOpen ?? (_) async {},
              onLibrary: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing and unrelated editor changes never reread the library', (
    tester,
  ) async {
    library.items = List.generate(
      3000,
      (index) => _file(directory, 'script-$index.lua'),
    );
    await mount(tester);
    final reads = library.reads;
    for (var index = 0; index < 30; index++) {
      controller.updateDocumentContent(
        controller.activeDocumentId,
        'print($index)',
      );
      controller.setWordWrap(index.isEven);
      await tester.pump();
    }
    expect(library.reads, reads);
    expect(find.text('Scripts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('library events refresh even a list mutated in place', (
    tester,
  ) async {
    library.items = [
      _file(directory, 'Folder', folder: true),
      _file(directory, 'Folder/first.lua'),
    ];
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('script-folder:Folder')));
    await tester.pumpAndSettle();
    expect(find.text('first.lua'), findsOneWidget);
    library.items.add(_file(directory, 'Folder/second.lua'));
    library.refreshView();
    await tester.pumpAndSettle();
    expect(find.text('second.lua'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('script-filter')),
      'second',
    );
    await tester.pumpAndSettle();
    expect(find.text('first.lua'), findsNothing);
    library.items.removeWhere((entry) => entry.name == 'second.lua');
    library.refreshView();
    await tester.pumpAndSettle();
    expect(find.text('No matching files'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('script-filter')), '');
    await tester.pumpAndSettle();
    expect(find.text('first.lua'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('active file highlighting follows native document selection', (
    tester,
  ) async {
    final first = File('${directory.path}/example.lua')..writeAsStringSync('');
    final second = File('${directory.path}/second.lua')..writeAsStringSync('');
    library.items.add(_file(directory, 'second.lua'));
    await mount(tester);
    await tester.runAsync(() => controller.openFileAtPath(first.path));
    await tester.pumpAndSettle();

    Color color(String name) => tester
        .widget<Material>(
          find
              .ancestor(of: find.text(name), matching: find.byType(Material))
              .first,
        )
        .color!;
    expect(color('example.lua'), isNot(Colors.transparent));
    expect(color('second.lua'), Colors.transparent);
    await tester.runAsync(() => controller.openFileAtPath(second.path));
    await tester.pumpAndSettle();
    expect(color('example.lua'), Colors.transparent);
    expect(color('second.lua'), isNot(Colors.transparent));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('theme updates and Special animation remain live', (
    tester,
  ) async {
    library.items = [
      _file(directory, 'Special', folder: true),
      _file(directory, 'blue.lua', code: ScriptColorCode.blue),
    ];
    await mount(tester);
    expect(
      tester.widget<Text>(find.text('blue.lua')).style!.color,
      const Color(0xff87b8ff),
    );
    await mount(tester, theme: orionTheme(Brightness.light, Colors.purple));
    expect(
      tester.widget<Text>(find.text('blue.lua')).style!.color,
      const Color(0xff245fa5),
    );
    controller.setReducedMotion(false);
    await tester.pump(const Duration(milliseconds: 10));
    final before = tester.widget<ShaderMask>(find.byType(ShaderMask));
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<ShaderMask>(find.byType(ShaderMask)),
      isNot(same(before)),
    );
    expect(tester.binding.hasScheduledFrame, true);
    controller.setReducedMotion(true);
    await tester.pumpAndSettle();
    expect(find.byType(ScriptCodeText), findsNWidgets(2));
    expect(tester.binding.hasScheduledFrame, false);
    await tester.pumpWidget(const SizedBox());
  });
}
