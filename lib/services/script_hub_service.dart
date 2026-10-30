import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/remote_script.dart';
import 'api_proxy_pool.dart';

typedef ScriptHttpTransport =
    Future<ScriptHttpResponse> Function(Uri uri, Map<String, String> headers);

class ScriptHttpResponse {
  const ScriptHttpResponse({
    required this.statusCode,
    required this.body,
    this.contentType,
  });

  final int statusCode;
  final List<int> body;
  final String? contentType;
}

class ScriptHubException implements Exception {
  const ScriptHubException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Fetches public script listings and source text. It never executes source or
/// follows addresses embedded in source text.
class ScriptHubService {
  ScriptHubService({
    ScriptHttpTransport? transport,
    HttpClient? client,
    Iterable<String>? proxyEndpoints,
    Future<String> Function(Uri source)? proxyListLoader,
    this.timeout = const Duration(seconds: 18),
    this.maximumResponseBytes = 4 * 1024 * 1024,
  }) : _transport = transport,
       _proxyPool = ApiProxyPool(
         endpoints: proxyEndpoints,
         endpointLoader: proxyListLoader,
       ),
       _useProxyPool = proxyEndpoints != null || proxyListLoader != null,
       _client = transport == null ? (client ?? HttpClient()) : null {
    if (maximumResponseBytes < 1) {
      throw ArgumentError.value(maximumResponseBytes, 'maximumResponseBytes');
    }
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    _client?.connectionTimeout = timeout;
    final httpClient = _client;
    if (httpClient != null && _useProxyPool) {
      httpClient.findProxy = (_) => 'DIRECT';
      httpClient.connectionFactory = (uri, _, _) => _openProxyConnection(uri);
    }
  }

  final Duration timeout;
  final int maximumResponseBytes;
  final ScriptHttpTransport? _transport;
  final ApiProxyPool _proxyPool;
  final bool _useProxyPool;
  final HttpClient? _client;
  final Set<_RequestContext> _requests = {};
  bool _closed = false;

  Future<ScriptPage> fetch(
    ScriptProvider provider,
    String query,
    int page,
  ) async {
    _ensureOpen();
    if (page < 1) throw ArgumentError.value(page, 'page', 'Must be positive');
    final term = String.fromCharCodes(query.trim().runes.take(100));
    final uri = switch (provider) {
      ScriptProvider.robloxScripts =>
        Uri.https(provider.domain, '/api/v1/scripts', {
          'page': '$page',
          'limit': '12',
          'sort': 'newest',
          if (term.isNotEmpty) 'q': term,
        }),
      ScriptProvider.scriptBlox => Uri.https(
        provider.domain,
        term.isEmpty ? '/api/script/fetch' : '/api/script/search',
        {if (term.isNotEmpty) 'q': term, 'page': '$page'},
      ),
      ScriptProvider.haxHell => Uri.https(
        provider.domain,
        term.isEmpty ? '/api/v1/scripts' : '/api/v1/search/scripts',
        {'page': '$page', 'limit': '12', if (term.isNotEmpty) 'q': term},
      ),
      ScriptProvider.rscripts => Uri.https(provider.domain, '/api/v2/scripts', {
        'page': '$page',
        'orderBy': 'date',
        'sort': 'desc',
        if (term.isNotEmpty) 'q': term,
      }),
    };
    final json = await _json(uri, provider);
    final result = _map(json['result']);
    final rawItems = switch (provider) {
      ScriptProvider.robloxScripts || ScriptProvider.haxHell => json['data'],
      ScriptProvider.scriptBlox => result['scripts'],
      ScriptProvider.rscripts => json['scripts'],
    };
    if (rawItems is! List || rawItems.any((item) => item is! Map)) {
      throw ScriptHubException(
        '${provider.label} returned an unexpected response.',
      );
    }
    final items = rawItems
        .map((item) => _parseScript(provider, _map(item)))
        .toList(growable: false);
    final pagination = _map(json['pagination']);
    final info = _map(json['info']);
    final hasMore = switch (provider) {
      ScriptProvider.robloxScripts || ScriptProvider.haxHell =>
        pagination['hasMore'] is bool
            ? pagination['hasMore'] as bool
            : _hasAnotherPage(pagination, page, items.isNotEmpty),
      ScriptProvider.scriptBlox =>
        result.containsKey('nextPage')
            ? (_number(result['nextPage']) ?? 0) > page
            : _hasAnotherPage(result, page, items.isNotEmpty),
      ScriptProvider.rscripts => _hasAnotherPage(info, page, items.isNotEmpty),
    };
    return ScriptPage(items: List.unmodifiable(items), hasMore: hasMore);
  }

  Future<String> loadScript(RemoteScript script) async {
    _ensureOpen();
    if (script.body != null && script.body!.trim().isNotEmpty) {
      _checkSize(utf8.encode(script.body!).length);
      return script.body!;
    }
    if (script.provider == ScriptProvider.scriptBlox) {
      final detailUri = Uri(
        scheme: 'https',
        host: script.provider.domain,
        pathSegments: ['api', 'script', script.id],
      );
      final details = await _json(detailUri, script.provider);
      final nestedScript = _map(details['script']);
      final body = _source(nestedScript, 'script');
      if (body != null) return body;
      return _raw(
        Uri(
          scheme: 'https',
          host: script.provider.domain,
          pathSegments: ['api', 'script', 'raw', script.id],
        ),
        script.provider,
      );
    }
    final rawUrl = script.rawUrl;
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      throw const ScriptHubException('This script has no source available.');
    }
    return _raw(Uri.parse(rawUrl), script.provider);
  }

  RemoteScript _parseScript(
    ScriptProvider provider,
    Map<String, dynamic> script,
  ) {
    var game = _map(script['game']);
    final games = script['games'];
    if (game.isEmpty && games is List && games.isNotEmpty) {
      game = _map(games.first);
    }
    final links = _map(script['links']);
    final stats = _map(script['stats']);
    final flags = _map(script['flags']);
    final id = _scalar(script, ['id', '_id', 'slug']);
    final title = _text(script, ['title']) ?? 'Untitled';
    final slug = _text(script, ['slug']) ?? id;
    final origin = Uri.https(provider.domain);
    final external = provider == ScriptProvider.haxHell
        ? _url(origin, _text(links, ['webpage']))
        : _url(origin, _text(script, ['scriptPageUrl'])) ??
              (slug.isEmpty
                  ? null
                  : Uri(
                      scheme: 'https',
                      host: provider.domain,
                      pathSegments: ['script', slug],
                    ).toString());
    final raw = switch (provider) {
      ScriptProvider.robloxScripts => _text(script, ['rawScriptUrl']),
      ScriptProvider.scriptBlox => null,
      ScriptProvider.haxHell => _text(links, ['raw']),
      ScriptProvider.rscripts => _text(script, ['rawScript']),
    };
    final gameName =
        _text(game, [
          if (provider == ScriptProvider.rscripts) 'title',
          'name',
          'title',
        ]) ??
        'Universal Script';
    return RemoteScript(
      id: id.isNotEmpty ? id : (external ?? title),
      provider: provider,
      title: title,
      game: gameName,
      description: _text(script, ['description', 'features']) ?? gameName,
      body: _source(script, 'script'),
      rawUrl: _url(origin, raw),
      imageUrl: _imageUrl(origin, script, game),
      externalUrl: external ?? origin.toString(),
      views:
          _count(script, ['views', 'viewCount', 'viewsCount', 'totalViews']) ??
          _count(stats, ['views']) ??
          0,
      updatedAt: _date(script, [
        'updatedAt',
        'updated_at',
        'dateUpdated',
        'lastUpdated',
        'publishedAt',
        'createdAt',
        'created_at',
        'date',
      ]),
      isPaid: _paid(script) || _paid(flags),
      hasKey:
          _boolean(script, ['key', 'hasKey', 'requiresKey', 'keySystem']) ||
          _boolean(flags, ['key', 'hasKey', 'requiresKey', 'keySystem']),
      isVerified:
          _boolean(script, ['verified', 'isVerified']) ||
          _boolean(flags, ['verified', 'isVerified']),
    );
  }

  Future<Map<String, dynamic>> _json(Uri uri, ScriptProvider provider) async {
    final response = await _request(uri, provider);
    try {
      final value = jsonDecode(utf8.decode(response.body));
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      throw ScriptHubException('${provider.label} returned invalid data.');
    }
    throw ScriptHubException(
      '${provider.label} returned an unexpected response.',
    );
  }

  Future<String> _raw(Uri uri, ScriptProvider provider) async {
    final response = await _request(uri, provider);
    String body;
    try {
      body = utf8.decode(response.body);
    } on FormatException {
      throw const ScriptHubException('The source is not valid text.');
    }
    final start = body.trimLeft().toLowerCase();
    if (response.contentType?.toLowerCase().contains('text/html') == true ||
        start.startsWith('<!doctype html') ||
        start.startsWith('<html')) {
      throw const ScriptHubException(
        'The provider returned a webpage instead of script source.',
      );
    }
    if (body.trim().isEmpty) {
      throw const ScriptHubException('This script has no source available.');
    }
    return body;
  }

  Future<ScriptHttpResponse> _request(Uri uri, ScriptProvider provider) async {
    _ensureOpen();
    _validateUri(uri);
    final headers = <String, String>{
      'User-Agent': 'Orbit/1.0 ScriptHub',
      'Accept': 'application/json',
      'Referer': 'https://${provider.domain}/',
    };
    final context = _RequestContext();
    _requests.add(context);
    try {
      final response =
          await (_transport != null
                  ? _transport(uri, Map.unmodifiable(headers))
                  : _nativeRequest(uri, headers, context))
              .timeout(
                timeout,
                onTimeout: () {
                  context.cancel();
                  throw ScriptHubException(
                    '${provider.label} timed out. Try again.',
                  );
                },
              );
      _checkSize(response.body.length);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ScriptHubException(
          '${provider.label} returned HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      return response;
    } on ScriptHubException {
      context.cancel();
      rethrow;
    } on SocketException {
      context.cancel();
      throw ScriptHubException(
        'Could not reach ${provider.label}. Check your connection and try again.',
      );
    } on HttpException {
      context.cancel();
      throw ScriptHubException(
        'Could not read the response from ${provider.label}.',
      );
    } finally {
      _requests.remove(context);
    }
  }

  Future<ConnectionTask<Socket>> _openProxyConnection(Uri uri) =>
      _proxyPool.connect(uri, timeout: timeout);

  Future<ScriptHttpResponse> _nativeRequest(
    Uri uri,
    Map<String, String> headers,
    _RequestContext context,
  ) async {
    var destination = uri;
    for (var redirects = 0; redirects <= 4; redirects++) {
      _validateUri(destination);
      final addresses = await InternetAddress.lookup(destination.host);
      if (addresses.isEmpty ||
          addresses.any((address) => !_isPublicAddress(address))) {
        throw const ScriptHubException(
          'Only public HTTP and HTTPS addresses are supported.',
        );
      }
      if (context.cancelled) {
        throw const ScriptHubException('The request was cancelled.');
      }
      final request = await _client!.getUrl(destination);
      context.request = request;
      if (context.cancelled) {
        request.abort();
        throw const ScriptHubException('The request was cancelled.');
      }
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      final response = await request.close();
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.listen((_) {}).cancel();
        if (location == null || redirects == 4) {
          throw const ScriptHubException(
            'The provider returned an invalid redirect.',
          );
        }
        destination = destination.resolve(location);
        continue;
      }
      if (response.contentLength > maximumResponseBytes) {
        request.abort();
        throw const ScriptHubException('The response is too large to open.');
      }
      final bytes = BytesBuilder(copy: false);
      final complete = Completer<void>();
      context.subscription = response.listen(
        (chunk) {
          if (bytes.length + chunk.length > maximumResponseBytes) {
            if (!complete.isCompleted) {
              complete.completeError(
                const ScriptHubException('The response is too large to open.'),
              );
            }
            context.cancel();
          } else {
            bytes.add(chunk);
          }
        },
        onDone: () {
          if (!complete.isCompleted) complete.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!complete.isCompleted) complete.completeError(error, stack);
        },
        cancelOnError: true,
      );
      await complete.future;
      context.subscription = null;
      return ScriptHttpResponse(
        statusCode: response.statusCode,
        body: bytes.takeBytes(),
        contentType: response.headers.value(HttpHeaders.contentTypeHeader),
      );
    }
    throw const ScriptHubException('The provider returned too many redirects.');
  }

  void _checkSize(int size) {
    if (size > maximumResponseBytes) {
      throw const ScriptHubException('The response is too large to open.');
    }
  }

  static void _validateUri(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    final literal = InternetAddress.tryParse(host);
    if (!['http', 'https'].contains(uri.scheme) ||
        host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        (literal != null && !_isPublicAddress(literal))) {
      throw const ScriptHubException(
        'Only public HTTP and HTTPS addresses are supported.',
      );
    }
  }

  static bool _isPublicAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return false;
    }
    if (address.type == InternetAddressType.IPv4) {
      return !(bytes[0] == 0 ||
          bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 169 && bytes[1] == 254) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
          bytes[0] >= 224 ||
          (bytes[0] == 192 && bytes[1] == 0) ||
          (bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 2) ||
          (bytes[0] == 198 &&
              (bytes[1] == 18 || bytes[1] == 19 || bytes[1] == 51)) ||
          (bytes[0] == 203 && bytes[1] == 0 && bytes[2] == 113));
    }
    if (bytes.every((byte) => byte == 0) || (bytes[0] & 0xFE) == 0xFC) {
      return false;
    }
    if (bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xFF &&
        bytes[11] == 0xFF) {
      return _isPublicAddress(
        InternetAddress.fromRawAddress(Uint8List.fromList(bytes.sublist(12))),
      );
    }
    return (bytes[0] & 0xE0) == 0x20 &&
        !(bytes[0] == 0x20 &&
            bytes[1] == 0x01 &&
            bytes[2] == 0x0D &&
            bytes[3] == 0xB8);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('The script search service is closed.');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final request in _requests) {
      request.cancel();
    }
    _client?.close(force: true);
    _proxyPool.close();
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};

  static String? _text(Map<String, dynamic> object, List<String> keys) {
    for (final key in keys) {
      final value = object[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static String? _source(Map<String, dynamic> object, String key) {
    final value = object[key];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  static String _scalar(Map<String, dynamic> object, List<String> keys) {
    for (final key in keys) {
      final value = object[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return '$value';
    }
    return '';
  }

  static num? _number(Object? value) => value is num
      ? value
      : value is String
      ? num.tryParse(value.trim())
      : null;

  static int? _count(Map<String, dynamic> object, List<String> keys) {
    for (final key in keys) {
      final value = _number(object[key]);
      if (value != null && value.isFinite) {
        return value.toInt().clamp(0, 0x7FFFFFFFFFFFFFFF);
      }
    }
    return null;
  }

  static bool _boolean(Map<String, dynamic> object, List<String> keys) {
    for (final key in keys) {
      if (!object.containsKey(key)) continue;
      final value = object[key];
      if (value is bool) return value;
      final number = _number(value);
      if (number != null) return number != 0;
      if (value is String) {
        return [
          'true',
          'yes',
          'required',
          'paid',
        ].contains(value.trim().toLowerCase());
      }
    }
    return false;
  }

  static bool _paid(Map<String, dynamic> object) =>
      _boolean(object, ['paid', 'isPaid']) ||
      ['paid'].contains(
        (_text(object, ['scriptType', 'type', 'accessType']) ?? '')
            .toLowerCase(),
      ) ||
      (_count(object, ['price', 'cost']) ?? 0) > 0;

  static DateTime? _date(Map<String, dynamic> object, List<String> keys) {
    for (final key in keys) {
      final value = object[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toUtc();
      }
      final numeric = _number(value);
      if (numeric == null || !numeric.isFinite) continue;
      final milliseconds = numeric > 10000000000
          ? numeric.toInt()
          : numeric.toInt() * 1000;
      try {
        return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
      } on RangeError {
        continue;
      }
    }
    return null;
  }

  static String? _url(Uri origin, String? value) {
    if (value == null ||
        value.trim().isEmpty ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      return null;
    }
    try {
      final url = origin.resolve(value.trim());
      _validateUri(url);
      return url.toString();
    } on ScriptHubException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static String? _imageUrl(
    Uri origin,
    Map<String, dynamic> script,
    Map<String, dynamic> game,
  ) {
    final media = _map(script['media']);
    // Prefer the script's own artwork; game art fills missing/invalid entries.
    for (final candidate in [
      media['thumbnailUrl'],
      script['image'],
      script['imageUrl'],
      script['thumbnailUrl'],
      game['thumbnailUrl'],
      game['imageUrl'],
      game['iconUrl'],
      game['image'],
    ]) {
      if (candidate is! String) continue;
      final address = _url(origin, candidate);
      if (address != null) return address;
    }
    return null;
  }

  static bool _hasAnotherPage(
    Map<String, dynamic> metadata,
    int page,
    bool fallback,
  ) {
    final maximum = _count(metadata, ['totalPages', 'pages', 'maxPages']);
    return maximum == null ? fallback : page < maximum;
  }
}

class _RequestContext {
  HttpClientRequest? request;
  StreamSubscription<List<int>>? subscription;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    request?.abort();
    final active = subscription;
    if (active != null) unawaited(active.cancel());
  }
}
