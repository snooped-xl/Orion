import 'dart:convert';
import 'dart:io';

/// Manual raw-script loading, matching V3's URL-based Gists section.
abstract final class V3Gists {
  static Uri? parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  static String title(Uri uri) {
    final base = uri.pathSegments.lastOrNull ?? 'Gist';
    final words = base
        .replaceFirst(RegExp(r'\.lua$', caseSensitive: false), '')
        .replaceAll(RegExp('[-_]'), ' ')
        .trim()
        .split(RegExp(r'\s+'));
    final result = words
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
    return result.isEmpty ? 'Gist' : result;
  }

  static Future<String> load(Uri uri) async {
    if (parse(uri.toString()) == null) {
      throw const FormatException('Invalid raw script URL.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final address = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          '_': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      final request = await client
          .getUrl(address)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Could not fetch script (${response.statusCode}).',
          uri: uri,
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 4 * 1024 * 1024) {
          throw const FormatException('Script exceeds 4 MiB.');
        }
      }
      final source = utf8.decode(bytes);
      if (source.trim().isEmpty) {
        throw const FormatException('Script was empty.');
      }
      return source;
    } finally {
      client.close(force: true);
    }
  }
}
