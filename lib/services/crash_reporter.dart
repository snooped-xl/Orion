import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CrashReporter {
  static const repository = 'https://github.com/snooped-xl/Orion';
  static const _fileName = 'orion-crash-report.txt';
  static const _consentFileName = 'crash-reports-enabled';

  bool get supported => Platform.isLinux || Platform.isWindows;

  Future<File> _file(String name) async => File(
    '${(await getApplicationSupportDirectory()).path}/$name',
  );

  Future<bool> get isEnabled async {
    if (!supported) return false;
    try {
      return await (await _file(_consentFileName)).readAsString() == 'yes';
    } on Object {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!supported) return;
    final report = await _file(_fileName);
    final consent = await _file(_consentFileName);
    await consent.parent.create(recursive: true);
    if (enabled) {
      await consent.writeAsString('yes', flush: true);
    } else {
      if (await consent.exists()) await consent.delete();
      if (await report.exists()) await report.delete();
    }
  }

  Future<void> capture(Object error, StackTrace stack) async {
    if (!await isEnabled) return;
    try {
      final file = await _file(_fileName);
      await file.parent.create(recursive: true);
      await file.writeAsString(sanitize('$error\n\n$stack'), flush: true);
    } on Object catch (failure) {
      debugPrint('Could not save local crash report: $failure');
    }
  }

  Future<String?> readPending() async {
    if (!supported) return null;
    try {
      final file = await _file(_fileName);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } on Object {
      return null;
    }
  }

  Uri issueUri(String report, {bool mentionAttachment = false}) {
    final body = StringBuffer()
      ..writeln('Orion crashed unexpectedly.')
      ..writeln()
      ..writeln('Crash details (sanitized; review before submitting):')
      ..writeln('```text')
      ..writeln(report)
      ..writeln('```')
      ..writeln()
      ..writeln('Platform: ${Platform.operatingSystem}');
    if (mentionAttachment) {
      body
        ..writeln()
        ..writeln('I will manually attach a screenshot or screen recording after reviewing it for private information.');
    }
    final content = body.toString();
    final encodedBody = Uri.encodeQueryComponent(content);
    return Uri.parse(
      '$repository/issues/new?title=${Uri.encodeQueryComponent('Crash report: Orion on ${Platform.operatingSystem}')}&labels=bug&body=$encodedBody',
    );
  }

  static String sanitize(String input) {
    var text = input
        .replaceAll(
          RegExp(r'(?:[A-Z]:\\|/Users/|/home/)[^\s:]*', caseSensitive: false),
          '<local-path>',
        )
        .replaceAll(
          RegExp(
            r'((?:token|password|secret|authorization)\s*[:=]\s*)[^\s,;]+',
            caseSensitive: false,
          ),
          r'$1<redacted>',
        );
    if (text.length > 12000) {
      text = '${text.substring(0, 12000)}\n… (truncated)';
    }
    return text;
  }

  Future<bool> openIssue(Uri uri) async {
    try {
      if (Platform.isWindows) {
        await Process.start('rundll32', [
          'url.dll,FileProtocolHandler',
          uri.toString(),
        ]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [uri.toString()]);
      } else {
        return false;
      }
      return true;
    } on Object catch (error) {
      debugPrint('Could not open GitHub issue in browser: $error');
      return false;
    }
  }
}
