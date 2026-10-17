import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/bridge_client_manager.dart';

import '../models/interface_preset.dart';
import '../models/companion_window.dart';
import '../services/file_paths.dart';
import 'awp_workspace.dart';
import 'xeno_controls.dart';

/// Original Orion Xeno with independent native settings, scripts and client windows.
class XenoShell extends AwpWorkspaceHost {
  const XenoShell({
    super.key,
    required super.controller,
    required super.nativeWindow,
    required super.onBackToOrion,
    super.editorService,
    super.bridgeReady,
    super.onSelectInterface,
    super.pickScriptPath,
    super.pickSavePath,
  });
  @override
  State<XenoShell> createState() => XenoShellState();
}

class XenoShellState extends AwpWorkspaceState<XenoShell> {
  late String _page;
  CompanionWindowHost? get _windows => c.companionWindows;

  @override
  void initState() {
    _page = switch (widget.controller.companionWindows?.kind) {
      CompanionWindowKind.xenoSettings => 'settings',
      CompanionWindowKind.xenoScripts => 'scripts',
      CompanionWindowKind.xenoClients => 'clients',
      _ => 'editor',
    };
    super.initState();
  }

  @override
  bool get replaceActiveOnOpen => true;
  @override
  bool get renameOnSave => false;
  @override
  bool get showLuauSaveType => false;
  @override
  List<String> get scriptExtensions => const ['lua', 'luau', 'txt', 'md'];
  @override
  InterfacePreset get preset => InterfacePreset.xeno;
  @override
  String get shellName => 'originalXeno';
  @override
  Color get canvasColor => const Color(0xff050505);
  @override
  bool get editorVisible => _page == 'editor';
  @override
  Size get mainSize => const Size(700, 400);
  @override
  Size get mainMinimum => const Size(560, 320);

  @override
  Future<void> showEditor() async => _navigate('editor');
  // Source settings/scripts/clients close independently; the main Xeno returns
  // to its hidden Orion owner and closes every companion first.
  @override
  Future<void> closeWindow() async {
    if (isCompanionWindow) {
      await _windows?.close();
    } else {
      await backToOrion();
    }
  }

  @override
  void onWindowClose() => unawaited(closeWindow());

  @override
  Future<void> backToOrion() async {
    await flushEditor();
    final windows = _windows;
    if (windows != null) {
      await windows.returnToOrion();
    } else if (mounted) {
      widget.onBackToOrion();
    }
  }

  @override
  Future<void> maximize() async {
    if (option('resizable') && !isCompanionWindow) await super.maximize();
  }

  Future<void> _navigate(String page) async {
    await flushEditor();
    if (!mounted) return;
    final windows = _windows;
    if (windows == null) {
      // Embedded previews and widget fixtures have no native window host.
      if (page == 'scripts') await refreshLocalFiles();
      if (!mounted) return;
      setState(() => _page = page);
      monaco?.setActive(editorVisible);
      return;
    }
    if (page == 'editor') {
      if (isCompanionWindow) await windows.close();
      return;
    }
    await windows.open(switch (page) {
      'settings' => CompanionWindowKind.xenoSettings,
      'scripts' => CompanionWindowKind.xenoScripts,
      _ => CompanionWindowKind.xenoClients,
    });
  }

  @override
  Widget build(BuildContext context) {
    synchronizeNative();
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: xenoType(13),
        child: _page == 'editor' ? _editorPage() : _supportPage(),
      ),
    );
  }

  Widget _editorPage() => ClipRRect(
    borderRadius: BorderRadius.circular(maximized ? 0 : 12),
    child: Container(
      key: const ValueKey('xeno-main'),
      decoration: BoxDecoration(
        color: const Color(0xff090909),
        borderRadius: BorderRadius.circular(maximized ? 0 : 12),
        border: maximized ? null : Border.all(color: const Color(0xff2e2e2e)),
      ),
      child: Column(
        children: [
          _titleBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: canvasColor,
                  border: Border.all(color: const Color(0xff202020)),
                ),
                child: ClipRect(child: codeEditor()),
              ),
            ),
          ),
          _toolbar(),
        ],
      ),
    ),
  );

  Widget _titleBar() => GestureDetector(
    onPanStart: (_) => drag(),
    behavior: HitTestBehavior.opaque,
    child: Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xff090909),
        border: Border(bottom: BorderSide(color: Color(0xff3a3a3a))),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Image.asset(
            'assets/original_xeno/xeno-icon.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 7),
          Text('Xeno', style: xenoType(18, weight: FontWeight.w900)),
          const SizedBox(width: 7),
          Text('v1.0.8', style: xenoType(12)),
          const Spacer(),
          XenoIconButton(
            tooltip: 'Minimize',
            asset: 'minimize',
            width: 38,
            height: 39,
            imageSize: 20,
            onPressed: () => unawaited(minimize()),
          ),
          XenoIconButton(
            tooltip: 'Maximize',
            asset: maximized ? 'normalize' : 'maximize',
            width: 38,
            height: 39,
            imageSize: 20,
            onPressed: () => unawaited(maximize()),
          ),
          XenoIconButton(
            tooltip: 'Close',
            asset: 'close',
            width: 38,
            height: 39,
            imageSize: 20,
            onPressed: () => unawaited(closeWindow()),
          ),
        ],
      ),
    ),
  );

  Widget _toolbar() => Container(
    height: 40,
    decoration: const BoxDecoration(
      color: Color(0xff090909),
      border: Border(top: BorderSide(color: Color(0xff202020))),
    ),
    child: Row(
      children: [
        const SizedBox(width: 8),
        XenoIconButton(
          tooltip: 'Open',
          asset: 'open',
          width: 32,
          imageSize: 25,
          onPressed: () => unawaited(open()),
        ),
        const SizedBox(width: 2),
        XenoIconButton(
          tooltip: 'Save',
          asset: 'save',
          width: 32,
          imageSize: 25,
          onPressed: () => unawaited(save()),
        ),
        const SizedBox(width: 2),
        XenoIconButton(
          tooltip: 'Clear',
          asset: 'clear',
          width: 32,
          imageSize: 28,
          onPressed: () => unawaited(clear()),
        ),
        const Spacer(),
        XenoIconButton(
          key: const ValueKey('xeno-settings'),
          tooltip: 'Settings',
          onPressed: () => unawaited(_navigate('settings')),
          child: Text(
            '⚙',
            style: xenoType(
              19,
              color: const Color(0xffe4e4e4),
              family: 'OriginalXenoUI',
            ),
          ),
        ),
        const SizedBox(width: 2),
        XenoIconButton(
          key: const ValueKey('xeno-scripts'),
          tooltip: 'Scripts',
          asset: 'scripts',
          imageSize: 28,
          onPressed: () => unawaited(_navigate('scripts')),
        ),
        const SizedBox(width: 2),
        XenoIconButton(
          key: const ValueKey('xeno-clients'),
          tooltip: 'Clients management',
          asset: 'multiple',
          imageSize: 27,
          onPressed: () => unawaited(_navigate('clients')),
        ),
        const SizedBox(width: 2),
        XenoIconButton(
          key: const ValueKey('xeno-execute'),
          tooltip: 'Execute',
          asset: 'execute',
          imageSize: 25,
          onPressed: widget.bridgeReady ? () => unawaited(execute()) : null,
        ),
        const SizedBox(width: 8),
      ],
    ),
  );

  Widget _supportPage() => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Container(
      key: ValueKey('xeno-$_page'),
      decoration: BoxDecoration(
        color: const Color(0xff090909),
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          GestureDetector(
            onPanStart: (_) => drag(),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 30,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Text(switch (_page) {
                    'settings' => 'Settings',
                    'scripts' => 'Scripts',
                    _ => 'Clients',
                  }, style: xenoType(18, mono: true)),
                  const Spacer(),
                  XenoTextButton(
                    key: const ValueKey('xeno-close-panel'),
                    label: '×',
                    width: 29,
                    height: 29,
                    fontSize: 22,
                    onPressed: () => unawaited(_navigate('editor')),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black,
                border: Border(top: BorderSide(color: Color(0xff303030))),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
                child: switch (_page) {
                  'settings' => _settingsBody(),
                  'scripts' => _scriptsBody(),
                  _ => _clientsBody(),
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _settingsBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(3, 5, 3, 0),
        child: Text(
          'XENO UI',
          style: xenoType(10, color: const Color(0xff777777)),
        ),
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.fromLTRB(3, 0, 3, 5),
        child: Text(
          'Interface settings',
          style: xenoType(17, weight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 6),
      _info('Editor', 'Monaco'),
      const SizedBox(height: 6),
      _info('Runtime', 'Orion Bridge'),
      const SizedBox(height: 6),
      _info('Theme', 'Xeno Dark'),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.fromLTRB(3, 10, 0, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: XenoTextButton(
            key: const ValueKey('xeno-back-to-orion'),
            label: 'Back to Orion',
            width: 150,
            height: 32,
            onPressed: () => unawaited(backToOrion()),
          ),
        ),
      ),
    ],
  );
  Widget _info(String label, String value) => Container(
    height: 31,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xff303030))),
    ),
    child: Row(
      children: [
        Text(label, style: xenoType(14, color: const Color(0xffb0b0b0))),
        const Spacer(),
        Text(value, style: xenoType(14, color: const Color(0xff737373))),
      ],
    ),
  );
  Widget _scriptsBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: localFiles.isEmpty
        ? [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'No scripts found',
                style: xenoType(13, color: const Color(0xff777777), mono: true),
              ),
            ),
          ]
        : [
            for (final file in localFiles) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        FilePaths.basename(
                          file.path,
                        ).replaceFirst(RegExp(r'\.[^.]*$'), ''),
                        style: xenoType(14, mono: true),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    XenoTextButton(
                      label: 'Execute',
                      width: 69,
                      height: 28,
                      onPressed: widget.bridgeReady
                          ? () async {
                              c.executeSource(
                                await file.readAsString(),
                                name: FilePaths.basename(file.path),
                              );
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              Container(
                height: 1,
                color: const Color(0xff555555),
                margin: const EdgeInsets.only(bottom: 8),
              ),
            ],
          ],
  );
  Widget _clientsBody() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${c.bridgeClients.length} connected',
                style: xenoType(12, color: const Color(0xff999999)),
              ),
            ),
            XenoTextButton(
              label: c.bridgeTargetAll ? 'All selected' : 'Select all',
              width: 95,
              height: 28,
              onPressed: () => c.setBridgeTargetAll(!c.bridgeTargetAll),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.bridgeClients.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No clients connected',
              textAlign: TextAlign.center,
              style: xenoType(13, color: const Color(0xff777777)),
            ),
          ),
        for (final client in c.bridgeClients)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0xff171717),
              border: Border.all(color: const Color(0xff303030)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => c.setBridgeClientSelected(
                      client.identifier,
                      !(c.bridgeTargetAll ||
                          c.selectedBridgeClients.contains(client.identifier)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            c.bridgeTargetAll ||
                                    c.selectedBridgeClients.contains(
                                      client.identifier,
                                    )
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            color: const Color(0xffcccccc),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  client.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: xenoType(13),
                                ),
                                Text(
                                  '${client.identifier} · ${client.transport}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: xenoType(
                                    10,
                                    color: const Color(0xff888888),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                XenoIconButton(
                  tooltip: 'Disconnect ${client.username}',
                  width: 30,
                  height: 30,
                  onPressed: () => c.disconnectBridgeClient(client.identifier),
                  child: const Icon(
                    Icons.link_off_rounded,
                    color: Color(0xff999999),
                    size: 17,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        XenoTextButton(
          label: 'Bridge setup & management',
          width: double.infinity,
          height: 31,
          onPressed: () =>
              unawaited(showBridgeClientManager(context, controller: c)),
        ),
      ],
    ),
  );
}
