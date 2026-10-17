import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/bridge_client_manager.dart';
import 'package:flutter/services.dart';

import '../models/interface_preset.dart';
import '../models/orion_models.dart';
import '../services/native_window_service.dart';
import 'awp_controls.dart';
import 'awp_workspace.dart';

/// AWP.GG's original Orion/Avalonia chrome, fake login, menus, workspace and output.
class AwpShell extends AwpWorkspaceHost {
  const AwpShell({
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
  State<AwpShell> createState() => AwpShellState();
}

class AwpShellState extends AwpWorkspaceState<AwpShell> {
  final _username = TextEditingController(),
      _password = TextEditingController(),
      _search = TextEditingController(),
      _renameInput = TextEditingController();
  final _renameFocus = FocusNode();
  final Set<String> _clearedOutput = {};
  final _scriptingRoot = GlobalKey();
  final _pageAnchor = GlobalKey();
  final _root = GlobalKey();
  String _page = 'scripting';
  bool _login = true,
      _menu = false,
      _clients = false,
      _editorSettings = false,
      _workspaceExpanded = true;
  String? _renaming, _toast;
  Timer? _toastTimer;
  double _consoleHeight = 130;
  int _popupSequence = 0;
  @override
  InterfacePreset get preset => InterfacePreset.awp;
  @override
  bool get excludeHiddenScripts => false;
  @override
  bool get createScriptsDirectory => true;
  @override
  String get shellName => 'originalAwp';
  @override
  Color get canvasColor => awpEditorBackground;
  @override
  bool get editorVisible =>
      !_login && _page == 'scripting' && !_menu && !_clients;
  @override
  Size get mainSize => const Size(820, 560);
  @override
  Size get mainMinimum => const Size(620, 420);

  @override
  void initState() {
    super.initState();
    _renameFocus.addListener(_renameFocusChanged);
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    _consoleHeight =
        (preferences['consoleHeight'] as num?)?.toDouble().clamp(
          72,
          double.infinity,
        ) ??
        130;
  }

  @override
  void dispose() {
    ++_popupSequence;
    monaco?.setObscured(false, owner: 'awp-popup');
    _toastTimer?.cancel();
    _username.dispose();
    _password.dispose();
    _search.dispose();
    _renameFocus.removeListener(_renameFocusChanged);
    _renameFocus.dispose();
    _renameInput.dispose();
    super.dispose();
  }

  @override
  Future<void> showEditor() async => _navigate('scripting');
  @override
  void handleEditorShortcut(String name) {
    if (name == 'console') {
      preference('consoleVisible', true);
      preference('consoleOpen', !option('consoleOpen', true));
      return;
    }
    super.handleEditorShortcut(name);
  }

  Future<void> _navigate(String page) async {
    await flushEditor();
    if (!mounted) return;
    ++_popupSequence;
    monaco?.setObscured(false, owner: 'awp-popup');
    setState(() {
      _page = page;
      _menu = false;
      _clients = false;
    });
    monaco?.setActive(editorVisible);
  }

  Future<void> _toggleMenu() => _togglePopup(clients: false);

  Future<void> _togglePopup({required bool clients}) async {
    if (clients ? _clients : _menu) {
      _dismiss();
      return;
    }
    final sequence = ++_popupSequence;
    await monaco?.freezeForOverlay(owner: 'awp-popup');
    if (!mounted || sequence != _popupSequence) return;
    setState(() {
      _clients = clients;
      _menu = !clients;
    });
    monaco?.setActive(editorVisible);
  }

  void _dismiss() {
    ++_popupSequence;
    monaco?.setObscured(false, owner: 'awp-popup');
    if (!_menu && !_clients) return;
    setState(() {
      _menu = false;
      _clients = false;
    });
    monaco?.setActive(editorVisible);
  }

  void _loginNow() {
    setState(() => _login = false);
    _password.clear();
    monaco?.setActive(editorVisible);
  }

  void _logout() {
    ++_popupSequence;
    monaco?.setObscured(false, owner: 'awp-popup');
    setState(() {
      _login = true;
      _menu = false;
      _clients = false;
    });
    _username.clear();
    _password.clear();
    monaco?.setActive(false);
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _closeTab(EditorDocument d) async {
    await flushEditor();
    if (!mounted) return;
    if (c.documents.length == 1) {
      _showToast('Cannot close last tab');
      return;
    }
    final index = c.documents.indexOf(d);
    final previous = c.documents[(index - 1).clamp(0, c.documents.length - 1)];
    final active = c.activeDocumentId == d.id;
    c.closeDocument(d.id);
    if (active && previous.id != d.id) c.selectDocument(previous.id);
  }

  void _reset() {
    for (final d in c.documents.skip(1).toList()) {
      final index = c.documents.indexOf(d);
      final previous =
          c.documents[(index - 1).clamp(0, c.documents.length - 1)];
      final active = c.activeDocumentId == d.id;
      c.closeDocument(d.id);
      if (active && previous.id != d.id) c.selectDocument(previous.id);
    }
    c.renameDocument(c.activeDocumentId, 'Untitled Tab');
    c.updateDocumentContent(c.activeDocumentId, '');
    _clearOutput();
    _showToast('State reset');
  }

  void _clearOutput() {
    setState(() => _clearedOutput.addAll(c.activities.map((a) => a.id)));
  }

  void _renameFocusChanged() {
    if (!_renameFocus.hasFocus) _commitRename();
  }

  String _tabTitle(EditorDocument document) {
    if (document.filePath != null &&
        document.name == document.filePath!.split('/').last) {
      return document.name.replaceFirst(RegExp(r'\.[^.]*$'), '');
    }
    return document.name;
  }

  void _beginRename(EditorDocument document) {
    _renameInput.value = TextEditingValue(
      text: document.name,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: document.name.length,
      ),
    );
    setState(() => _renaming = document.id);
  }

  void _commitRename() {
    final id = _renaming;
    if (id == null || !mounted) return;
    final name = _renameInput.text.trim();
    setState(() => _renaming = null);
    c.renameDocument(id, name.isEmpty ? 'Untitled Tab' : name);
  }

  @override
  Future<void> refreshLocalFiles() async {
    await super.refreshLocalFiles();
    if (!mounted) return;
    setState(
      () => localFiles = localFiles.where((file) {
        final extension = file.path.split('.').last.toLowerCase();
        return scriptExtensions.contains(extension);
      }).toList(),
    );
  }

  @override
  Future<void> save({bool saveAs = false}) async {
    if (await savePickedScript() && mounted) {
      _showToast('Saved ${c.activeDocument.name}');
    }
  }

  Future<void> _executeFile() async {
    if (!widget.bridgeReady) return;
    await open();
    if (mounted) await execute();
  }

  @override
  Widget build(BuildContext context) {
    synchronizeNative();
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: awpType(12),
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              if (_renaming != null) {
                setState(() => _renaming = null);
              } else {
                _dismiss();
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(maximized ? 0 : 4),
            child: Container(
              key: _root,
              decoration: BoxDecoration(
                color: awpBackground,
                borderRadius: BorderRadius.circular(maximized ? 0 : 4),
                border: maximized
                    ? null
                    : Border.all(color: const Color(0xff424040)),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      _titleBar(),
                      Expanded(
                        child: _page == 'settings' ? _settings() : _scripting(),
                      ),
                    ],
                  ),
                  if (_menu || _clients)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _dismiss,
                      ),
                    ),
                  if (_menu) _pageMenu(),
                  if (_clients)
                    Positioned(
                      right: 3,
                      bottom: 42,
                      width: 194,
                      child: _clientsPopup(),
                    ),
                  if (_login) Positioned.fill(child: _loginPage()),
                  if (_toast != null)
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: awpPanel,
                          border: Border.all(color: awpBorder),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x99000000),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(_toast!, style: awpType(12)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wordmark(double size, double spacing) => RichText(
    text: TextSpan(
      style: awpType(
        size,
        color: Colors.white,
        weight: FontWeight.w800,
        spacing: spacing,
      ),
      children: const [
        TextSpan(text: 'AWP'),
        TextSpan(
          text: '.',
          style: TextStyle(color: Color(0xff6a6a6a)),
        ),
        TextSpan(text: 'GG'),
      ],
    ),
  );
  Widget _titleBar() => GestureDetector(
    onPanStart: (_) => drag(),
    onDoubleTap: option('resizable') ? () => unawaited(maximize()) : null,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 12),
          _wordmark(16, .8),
          const SizedBox(width: 10),
          Container(
            width: 2,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xff6a6a6a),
              borderRadius: BorderRadius.circular(60),
            ),
          ),
          const SizedBox(width: 10),
          AwpButton(
            key: _pageAnchor,
            height: 24,
            flat: true,
            padding: EdgeInsets.zero,
            onPressed: () => unawaited(_toggleMenu()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                awpIcon(_page == 'settings' ? 'tool' : 'file', color: awpText),
                const SizedBox(width: 6),
                Text(
                  _page == 'settings' ? 'Settings' : 'Scripting',
                  style: awpType(12, weight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                awpIcon(_menu ? 'chevron-up' : 'chevron-down', color: awpText),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AwpButton(
            tooltip: 'Logout',
            icon: 'logout',
            iconSize: 15,
            width: 22,
            height: 22,
            flat: true,
            padding: EdgeInsets.zero,
            onPressed: _logout,
          ),
          const Spacer(),
          AwpButton(
            tooltip: 'Minimize',
            width: 24,
            height: 24,
            flat: true,
            padding: EdgeInsets.zero,
            onPressed: () => unawaited(minimize()),
            child: Container(
              width: 11,
              height: 1.4,
              decoration: BoxDecoration(
                color: awpMuted,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AwpButton(
            tooltip: 'Maximize',
            icon: 'maximize',
            iconSize: 11,
            width: 24,
            height: 24,
            flat: true,
            padding: EdgeInsets.zero,
            onPressed: () => option('resizable') ? unawaited(maximize()) : null,
          ),
          const SizedBox(width: 12),
          AwpButton(
            tooltip: 'Close',
            icon: 'close',
            iconSize: 11,
            width: 24,
            height: 24,
            flat: true,
            close: true,
            padding: EdgeInsets.zero,
            onPressed: () => unawaited(closeWindow()),
          ),
          const SizedBox(width: 12),
        ],
      ),
    ),
  );

  Widget _pageMenu() {
    final anchor = _pageAnchor.currentContext?.findRenderObject() as RenderBox?;
    final root = _root.currentContext?.findRenderObject() as RenderBox?;
    final pos = anchor != null && root != null
        ? anchor.localToGlobal(Offset.zero, ancestor: root)
        : const Offset(120, 6);
    return Positioned(
      left: pos.dx,
      top: pos.dy + 27,
      width: 130,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: awpBackground,
          border: Border.all(color: awpBorder),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            for (final p in ['scripting', 'settings']) ...[
              if (p == 'settings') const SizedBox(height: 2),
              AwpButton(
                key: ValueKey('awp-menu-$p'),
                height: 27,
                flat: true,
                radius: 3,
                background: _page == p ? awpPanel : Colors.transparent,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () => unawaited(_navigate(p)),
                child: Row(
                  children: [
                    awpIcon(
                      p == 'settings' ? 'tool' : 'file',
                      size: 13,
                      color: _page == p ? awpText : awpMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      p == 'settings' ? 'Settings' : 'Scripting',
                      style: awpType(
                        12,
                        color: _page == p ? awpText : awpMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loginPage() => ColoredBox(
    color: awpBackground,
    child: Center(
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _wordmark(22, 1)),
            const SizedBox(height: 4),
            Text(
              'Enter any credentials, this is a fake login page',
              textAlign: TextAlign.center,
              style: awpType(11, color: const Color(0xff6a6a6a)),
            ),
            const SizedBox(height: 20),
            Text(
              'Username:',
              style: awpType(
                11,
                color: const Color(0xff6a6a6a),
                weight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            AwpInput(
              key: const ValueKey('awp-login-username'),
              controller: _username,
              hint: 'Username',
              autofocus: true,
              onSubmitted: (_) => _loginNow(),
            ),
            const SizedBox(height: 12),
            Text(
              'Password:',
              style: awpType(
                11,
                color: const Color(0xff6a6a6a),
                weight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            AwpInput(
              key: const ValueKey('awp-login-password'),
              controller: _password,
              hint: 'Password',
              password: true,
              onSubmitted: (_) => _loginNow(),
            ),
            const SizedBox(height: 28),
            AwpButton(
              key: const ValueKey('awp-login'),
              label: 'Login',
              height: 34,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              onPressed: _loginNow,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _scripting() => Row(
    key: _scriptingRoot,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 32,
              padding: const EdgeInsets.fromLTRB(3, 0, 0, 3),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: awpBorder)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final d in c.documents) ...[
                      _tab(d),
                      const SizedBox(width: 3),
                    ],
                    AwpButton(
                      key: const ValueKey('awp-new-tab'),
                      label: '+',
                      width: 25,
                      height: 25,
                      flat: true,
                      fontSize: 18,
                      padding: const EdgeInsets.all(4),
                      color: const Color(0xff6a6a6a),
                      onPressed: () => unawaited(newTab()),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: codeEditor()),
            _toolbar(),
            if (option('consoleVisible', true)) _console(),
          ],
        ),
      ),
      _workspace(),
    ],
  );

  Widget _tab(EditorDocument d) => AwpButton(
    key: ValueKey('awp-tab-${d.id}'),
    width: 150,
    height: 28,
    flat: true,
    padding: const EdgeInsets.all(5),
    background: d.id == c.activeDocumentId ? awpPanel : Colors.transparent,
    border: d.id == c.activeDocumentId ? awpBorder : Colors.transparent,
    onPressed: () => unawaited(select(d.id)),
    child: Row(
      children: [
        awpIcon('file'),
        const SizedBox(width: 8),
        Expanded(
          child: _renaming == d.id
              ? TextFormField(
                  controller: _renameInput,
                  focusNode: _renameFocus,
                  autofocus: true,
                  style: awpType(13),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    visualDensity: VisualDensity.standard,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.only(left: 6),
                  ),
                  onFieldSubmitted: (_) => _commitRename(),
                  onTapOutside: (_) => _commitRename(),
                )
              : GestureDetector(
                  onDoubleTap: () => _beginRename(d),
                  child: Text(
                    _tabTitle(d),
                    overflow: TextOverflow.ellipsis,
                    style: awpType(
                      13,
                      color: d.id == c.activeDocumentId ? awpText : awpMuted,
                    ),
                  ),
                ),
        ),
        AwpButton(
          label: '×',
          tooltip: 'Close tab',
          width: 16,
          height: 16,
          fontSize: 13,
          flat: true,
          padding: const EdgeInsets.all(2),
          onPressed: () => unawaited(_closeTab(d)),
        ),
      ],
    ),
  );
  Widget _toolbar() => SizedBox(
    height: 40,
    child: LayoutBuilder(
      builder: (ctx, box) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: box.maxWidth.clamp(580, double.infinity),
          height: 40,
          child: Row(
            children: [
              for (final (label, icon, callback, disabled)
                  in <(String, String, VoidCallback?, bool)>[
                    (
                      'Execute',
                      'execute',
                      widget.bridgeReady ? () => unawaited(execute()) : null,
                      true,
                    ),
                    ('Clear', 'clear', () => unawaited(clear()), false),
                    ('Open', 'open', () => unawaited(open()), false),
                    (
                      'Execute',
                      'execute-file',
                      widget.bridgeReady
                          ? () => unawaited(_executeFile())
                          : null,
                      true,
                    ),
                    ('Save', 'save', () => unawaited(save()), false),
                  ])
                Padding(
                  padding: const EdgeInsets.fromLTRB(3, 6, 0, 6),
                  child: AwpButton(
                    label: label,
                    icon: icon,
                    height: 28,
                    execute: disabled,
                    tooltip: icon == 'execute-file' ? 'Execute file' : label,
                    onPressed: callback,
                  ),
                ),
              const Spacer(),
              AwpButton(
                tooltip: 'Attach',
                icon: 'plug',
                iconSize: 24,
                width: 32,
                height: 32,
                flat: true,
                padding: EdgeInsets.zero,
                onPressed: () => unawaited(_manageClients()),
              ),
              const SizedBox(width: 8),
              AwpButton(
                tooltip: 'Launch Roblox',
                icon: 'launch',
                iconSize: 24,
                width: 32,
                height: 32,
                flat: true,
                padding: EdgeInsets.zero,
                onPressed: () =>
                    _showToast('Start Roblox using your installed executor.'),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _console() {
    final expanded = option('consoleOpen', true);
    final height = expanded ? _consoleHeight : 33.0;
    return SizedBox(
      key: const ValueKey('awp-console'),
      height: height,
      child: Stack(
        children: [
          Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => preference('consoleOpen', !expanded),
                child: Container(
                  height: 33,
                  color: awpPanel,
                  padding: const EdgeInsets.fromLTRB(9, 0, 7, 0),
                  child: Row(
                    children: [
                      Text(
                        'Output',
                        style: awpType(
                          11,
                          weight: FontWeight.w600,
                          spacing: .66,
                        ),
                      ),
                      const Spacer(),
                      AwpButton(
                        tooltip: 'Clear console',
                        icon: 'clear',
                        iconSize: 13,
                        width: 20,
                        height: 20,
                        flat: true,
                        padding: EdgeInsets.zero,
                        onPressed: _clearOutput,
                      ),
                      const SizedBox(width: 4),
                      AwpButton(
                        tooltip: expanded
                            ? 'Collapse console'
                            : 'Expand console',
                        icon: expanded ? 'chevron-up' : 'chevron-down',
                        width: 20,
                        height: 20,
                        flat: true,
                        padding: EdgeInsets.zero,
                        onPressed: () => preference('consoleOpen', !expanded),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Expanded(
                  child: ColoredBox(
                    color: awpEditorBackground,
                    child: SizedBox.expand(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: SelectableText(
                          c.activities
                              .where(
                                (a) =>
                                    a.kind == ActivityKind.execution &&
                                    !_clearedOutput.contains(a.id),
                              )
                              .map(
                                (a) =>
                                    '[${a.timestamp.hour.toString().padLeft(2, '0')}:${a.timestamp.minute.toString().padLeft(2, '0')}:${a.timestamp.second.toString().padLeft(2, '0')}] ${a.message}',
                              )
                              .join('\n'),
                          style: awpType(10.2, mono: true, height: 14.2 / 10.2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (expanded)
            Positioned(
              key: const ValueKey('awp-console-resize'),
              top: 0,
              left: 0,
              right: 0,
              height: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) {
                    final max =
                        (_scriptingRoot.currentContext?.size?.height ?? 522) -
                        130;
                    setState(
                      () => _consoleHeight = (_consoleHeight - d.delta.dy)
                          .clamp(72, max.clamp(72, double.infinity)),
                    );
                  },
                  onVerticalDragEnd: (_) =>
                      preference('consoleHeight', _consoleHeight),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xff343434))),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _workspace() => Container(
    width: 200,
    decoration: const BoxDecoration(
      color: awpBackground,
      border: Border(left: BorderSide(color: awpBorder)),
      boxShadow: [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 12,
          offset: Offset(-4, 0),
        ),
      ],
    ),
    child: Column(
      children: [
        Container(
          height: 35,
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: awpBorder)),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: awpPanel,
              border: Border.all(color: awpBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                SizedBox(width: 25, child: awpIcon('search', size: 13)),
                Expanded(
                  child: TextField(
                    key: const ValueKey('awp-script-search'),
                    controller: _search,
                    style: awpType(12),
                    cursorColor: awpText,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      visualDensity: VisualDensity.standard,
                      hintText: 'Search...',
                      hintStyle: awpType(12, color: const Color(0xff606060)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AwpButton(
          height: 33,
          flat: true,
          background: awpPanel,
          radius: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: () =>
              setState(() => _workspaceExpanded = !_workspaceExpanded),
          child: Row(
            children: [
              awpIcon('workspace', size: 16, color: awpText),
              const SizedBox(width: 4),
              Text(
                'Workspace',
                style: awpType(14, color: awpMuted, weight: FontWeight.w600),
              ),
              const Spacer(),
              awpIcon(
                _workspaceExpanded ? 'chevron-up' : 'chevron-down',
                size: 12,
              ),
            ],
          ),
        ),
        Expanded(child: !_workspaceExpanded ? const SizedBox() : _scriptList()),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: awpBorder)),
          ),
          child: AwpButton(
            key: const ValueKey('awp-clients'),
            height: 33,
            flat: true,
            background: awpPanel,
            border: awpBorder,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onPressed: () => unawaited(_togglePopup(clients: true)),
            child: Row(
              children: [
                awpIcon('clients', size: 16),
                const SizedBox(width: 6),
                Text(
                  _clientSummary,
                  style: awpType(14, color: awpMuted, weight: FontWeight.w600),
                ),
                const Spacer(),
                awpIcon(_clients ? 'chevron-down' : 'chevron-up', size: 10),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget _scriptList() {
    final files = localFiles
        .where(
          (f) => f.path
              .split('/')
              .last
              .toLowerCase()
              .contains(_search.text.toLowerCase()),
        )
        .toList();
    if (files.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'No scripts found',
            style: awpType(
              12,
              color: const Color(0xff555555),
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final f in files)
          AwpButton(
            height: 27,
            flat: true,
            radius: 0,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            onPressed: () => unawaited(openLocal(f)),
            child: Row(
              children: [
                awpIcon('file'),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    f.path.split('/').last,
                    overflow: TextOverflow.ellipsis,
                    style: awpType(13, color: awpMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String get _clientSummary {
    final selected = c.bridgeClients
        .where(
          (client) =>
              c.bridgeTargetAll ||
              c.selectedBridgeClients.contains(client.identifier),
        )
        .toList();
    return switch (selected.length) {
      0 => 'None',
      1 => selected.single.username,
      _ => '${selected.length} Clients',
    };
  }

  Future<void> _manageClients() async {
    _dismiss();
    await showBridgeClientManager(
      context,
      controller: c,
      editorService: monaco,
    );
  }

  Widget _clientsPopup() => Container(
    padding: const EdgeInsets.all(3),
    constraints: BoxConstraints(
      maxHeight: (MediaQuery.sizeOf(context).height - 92).clamp(120, 300),
    ),
    decoration: BoxDecoration(
      color: awpBackground,
      border: Border.all(color: awpBorder),
      borderRadius: BorderRadius.circular(4),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 12,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 31,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: awpBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'CLIENTS',
                  style: awpType(
                    10,
                    color: awpMuted,
                    weight: FontWeight.w700,
                    spacing: .6,
                  ),
                ),
              ),
              AwpButton(
                label: c.bridgeTargetAll ? 'All ✓' : 'All',
                height: 23,
                width: 42,
                flat: true,
                padding: EdgeInsets.zero,
                onPressed: () => c.setBridgeTargetAll(!c.bridgeTargetAll),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.bridgeClients.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                    child: Text(
                      'No clients connected',
                      textAlign: TextAlign.center,
                      style: awpType(
                        11,
                        color: const Color(0xff606060),
                      ).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                for (final client in c.bridgeClients)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AwpButton(
                      key: ValueKey('awp-client-${client.identifier}'),
                      height: 45,
                      flat: true,
                      border:
                          c.bridgeTargetAll ||
                              c.selectedBridgeClients.contains(
                                client.identifier,
                              )
                          ? const Color(0xff343434)
                          : const Color(0xff252525),
                      background:
                          c.bridgeTargetAll ||
                              c.selectedBridgeClients.contains(
                                client.identifier,
                              )
                          ? const Color(0xff282828)
                          : awpBackground,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      onPressed: () => c.setBridgeClientSelected(
                        client.identifier,
                        !(c.bridgeTargetAll ||
                            c.selectedBridgeClients.contains(
                              client.identifier,
                            )),
                      ),
                      child: Row(
                        children: [
                          awpIcon('clients', size: 15),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  client.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: awpType(
                                    12,
                                    color: awpText,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  client.identifier,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: awpType(
                                    9.5,
                                    color: const Color(0xff606060),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            c.bridgeTargetAll ||
                                    c.selectedBridgeClients.contains(
                                      client.identifier,
                                    )
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            color: awpMuted,
                            size: 15,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 3),
        AwpButton(
          key: const ValueKey('awp-manage-clients'),
          label: 'Manage clients',
          height: 28,
          flat: true,
          border: awpBorder,
          onPressed: () => unawaited(_manageClients()),
        ),
      ],
    ),
  );

  Widget _section(String label, String icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: awpPanel,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        awpIcon(icon, size: 16, color: awpText),
        const SizedBox(width: 8),
        Text(label, style: awpType(11, weight: FontWeight.w700, spacing: .5)),
      ],
    ),
  );
  Widget _setting(
    String title,
    String subtitle,
    String action,
    VoidCallback callback, {
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: awpType(12, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: awpType(10, color: awpMuted)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        AwpButton(
          key: key,
          label: action,
          height: 26,
          fontSize: 11,
          onPressed: callback,
        ),
      ],
    ),
  );
  Widget _settings() => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 58,
          padding: const EdgeInsets.only(top: 2),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: awpBorder)),
          ),
          child: Column(
            children: [
              AwpButton(
                tooltip: 'General settings',
                icon: 'tool',
                iconSize: 16,
                width: 42,
                height: 34,
                flat: true,
                selected: !_editorSettings,
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _editorSettings = false),
              ),
              const SizedBox(height: 6),
              AwpButton(
                tooltip: 'Editor settings',
                icon: 'code',
                iconSize: 16,
                width: 42,
                height: 34,
                flat: true,
                selected: _editorSettings,
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _editorSettings = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: awpBorder)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _editorSettings
                    ? [
                        _section('EDITOR', 'code'),
                        _setting(
                          'Reset State',
                          'Clear all UI state.',
                          'Reset',
                          _reset,
                        ),
                      ]
                    : [
                        _section('GENERAL', 'tool'),
                        _setting(
                          'Always on Top: ${option('alwaysOnTop') ? 'On' : 'Off'}',
                          'Toggle UI always being on top.',
                          option('alwaysOnTop') ? 'Disable' : 'Enable',
                          () {
                            final value = !option('alwaysOnTop');
                            preference('alwaysOnTop', value);
                            if (widget.nativeWindow) {
                              unawaited(
                                NativeWindowService.setAlwaysOnTop(value),
                              );
                            }
                          },
                        ),
                        _setting(
                          'Console: ${option('consoleVisible', true) ? 'Visible' : 'Hidden'}',
                          'Show or hide the output console.',
                          option('consoleVisible', true) ? 'Hide' : 'Show',
                          () => preference(
                            'consoleVisible',
                            !option('consoleVisible', true),
                          ),
                        ),
                        _setting(
                          'Scripts Folder',
                          'Open the workspace folder.',
                          'Open',
                          () => unawaited(openScriptsFolder()),
                        ),
                        _setting(
                          'Reset State',
                          'Clear all UI state.',
                          'Reset',
                          _reset,
                        ),
                        const SizedBox(height: 8),
                        _section('ORION', 'back'),
                        _setting(
                          'Back to Orion',
                          'Return to the Orion interface.',
                          'Back to Orion',
                          () => unawaited(backToOrion()),
                          key: const ValueKey('awp-back-to-orion'),
                        ),
                      ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
