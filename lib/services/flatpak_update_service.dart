import 'dart:io';

/// Run through flatpak-spawn so installation happens outside the app sandbox.
typedef UpdateProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class FlatpakUpdateInstallation {
  const FlatpakUpdateInstallation({
    required this.scope,
    required this.ref,
    required this.instanceId,
  });

  final String scope, ref, instanceId;
}

class FlatpakUpdateService {
  FlatpakUpdateService({UpdateProcessRunner? run, File? infoFile})
    : _run = run ?? ((exe, args) => Process.run(exe, args)),
      _infoFile = infoFile ?? File('/.flatpak-info');

  final UpdateProcessRunner _run;
  final File _infoFile;
  static const appId = 'dev.snooped.orion';

  // The launcher uses /app/orion, which exists only in the sandbox. A host
  // command must start in a directory present in the host namespace.
  Future<ProcessResult> _host(List<String> arguments) => _run('flatpak-spawn', [
    '--host',
    '--directory=/',
    '--env=LC_ALL=C',
    ...arguments,
  ]);

  Future<ProcessResult> _checked(List<String> arguments) async {
    final result = await _host(arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        arguments.first,
        arguments.skip(1).toList(),
        '${result.stderr}\n${result.stdout}'.trim(),
        result.exitCode,
      );
    }
    return result;
  }

  Future<FlatpakUpdateInstallation> install(File bundle) async {
    // Match the running deployment, including user/system duplicates and named
    // installations. Only fall back to a user copy for a denied system install.
    final info = await _infoFile.readAsLines();
    String value(String key) => info
        .firstWhere((line) => line.startsWith('$key='), orElse: () => '$key=')
        .substring(key.length + 1);
    final appPath = value('original-app-path').isNotEmpty
        ? value('original-app-path')
        : value('app-path');
    final arch = value('arch');
    final branch = value('branch');
    final instanceId = value('instance-id');
    if (arch.isEmpty ||
        branch.isEmpty ||
        instanceId.isEmpty ||
        appPath.isEmpty) {
      throw StateError('Unable to identify the running Flatpak installation.');
    }
    final ref = '$appId/$arch/$branch';
    final installations = await _checked([
      'flatpak',
      'list',
      '--app',
      '--columns=installation',
    ]);
    String? scope;
    for (final name
        in installations.stdout
            .toString()
            .split('\n')
            .map((s) => s.trim())
            .toSet()) {
      if (name.isEmpty) continue;
      final candidate = switch (name) {
        'user' => '--user',
        'system' => '--system',
        _ => '--installation=$name',
      };
      final location = await _host([
        'flatpak',
        'info',
        candidate,
        '--show-location',
        ref,
      ]);
      final path = location.stdout.toString().trim();
      if (location.exitCode == 0 &&
          path.isNotEmpty &&
          appPath.startsWith('${Directory(path).parent.path}/')) {
        scope = candidate;
        break;
      }
    }
    if (scope == null) {
      throw StateError(
        'The running Flatpak deployment was not found on the host.',
      );
    }
    Future<ProcessResult> installIn(String installation) => _host([
      'flatpak',
      'install',
      installation,
      '--or-update',
      '--bundle',
      '--assumeyes',
      bundle.path,
    ]);
    var effectiveScope = scope;
    var result = await installIn(effectiveScope);
    // System bundle installs can be denied by PolicyKit. Do not mask corrupt
    // bundles, missing runtimes, disk errors, or other installer failures.
    if (result.exitCode != 0 &&
        scope != '--user' &&
        result.stderr.toString().contains(
          'Flatpak system operation InstallBundle not allowed for user',
        )) {
      effectiveScope = '--user';
      result = await installIn(effectiveScope);
    }
    // Flatpak returns 1 for the exact same bundle, even with --or-update. This
    // is a successful no-op: the requested version is already deployed. Keep
    // the selected scope so restart uses that copy, not an older system copy.
    final alreadyInstalled =
        result.exitCode == 1 &&
        result.stderr.toString().trim() ==
            'error: Failed to install bundle $appId: '
                'This version of $appId is already installed';
    if (result.exitCode != 0 && !alreadyInstalled) {
      throw ProcessException(
        'flatpak',
        [
          'install',
          effectiveScope,
          '--or-update',
          '--bundle',
          '--assumeyes',
          bundle.path,
        ],
        '${result.stderr}\n${result.stdout}'.trim(),
        result.exitCode,
      );
    }
    return FlatpakUpdateInstallation(
      scope: effectiveScope,
      ref: ref,
      instanceId: instanceId,
    );
  }

  Future<void> scheduleRestart(
    FlatpakUpdateInstallation installation,
    Directory cache,
  ) async {
    final script = File('${cache.path}/restart_flatpak.sh');
    final workspace = Platform.environment['ORION_WORKSPACE'];
    await script.writeAsString(
      buildRestartScript(installation, workspace: workspace),
      flush: true,
    );
    // The host helper is detached BEFORE Orion exits. --watch-bus would kill it
    // with the old sandbox. The marker confirms the helper actually started.
    await _checked([
      '/bin/sh',
      '-c',
      r'nohup /bin/sh "$1" >"$1.log" 2>&1 </dev/null & '
          r'for i in 1 2 3 4 5 6 7 8 9 10; do '
          r'if test -f "$1.started"; then exit 0; fi; sleep 0.1; done; exit 1',
      'orion-restart',
      script.path,
    ]);
  }

  static String buildRestartScript(
    FlatpakUpdateInstallation installation, {
    String? workspace,
  }) {
    String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
    final run = [
      'flatpak',
      'run',
      installation.scope,
      if (workspace != null) '--env=ORION_WORKSPACE=$workspace',
      installation.ref,
    ].map(quote).join(' ');
    return '''#!/bin/sh
set -eu
: > "\$0.started"
# Sandbox PIDs are not host PIDs. Wait for this exact Flatpak instance instead.
instance=${quote(installation.instanceId)}
attempt=0
while :; do
    instances=\$(flatpak ps --columns=instance)
    if ! printf '%s\\n' "\$instances" | grep -Fxq -- "\$instance"; then break; fi
    attempt=\$((attempt + 1))
    if [ "\$attempt" -ge 240 ]; then echo 'Orion did not exit in time.' >&2; exit 1; fi
    sleep 0.5
done
rm -f "\$0.started" "\$0"
exec $run
''';
  }
}
