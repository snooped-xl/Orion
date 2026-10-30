import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:socks_socket/socks_connection.dart';

/// Rotates through SOCKS5 proxies, cooling down endpoints that fail to connect.
class ApiProxyPool {
  ApiProxyPool({
    Iterable<String>? endpoints,
    Future<String> Function(Uri source)? endpointLoader,
    DateTime Function()? clock,
    this.cooldown = const Duration(minutes: 2),
    this.connectTimeout = const Duration(seconds: 8),
    this.refreshInterval = const Duration(minutes: 5),
    this.maxAttempts = 5,
    SecurityContext? securityContext,
    bool Function(X509Certificate certificate)? onBadCertificate,
    Future<bool> Function(String endpoint)? healthProbe,
  }) : _configuredEndpoints = endpoints == null
           ? null
           : List.unmodifiable(endpoints),
       _endpointLoader =
           endpointLoader ?? (endpoints == null ? _downloadEndpointList : null),
       _clock = clock ?? DateTime.now,
       _securityContext = securityContext,
       _onBadCertificate = onBadCertificate,
       _healthProbe = healthProbe {
    final configuredEndpoints = _configuredEndpoints;
    if (configuredEndpoints != null) _validateEndpoints(configuredEndpoints);
    if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts');
  }

  static final Uri defaultListUri = Uri.parse(
    'https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/all/data.txt',
  );

  final List<String>? _configuredEndpoints;
  final Future<String> Function(Uri source)? _endpointLoader;
  final Duration cooldown;
  final Duration connectTimeout;
  final Duration refreshInterval;
  final int maxAttempts;
  final DateTime Function() _clock;
  final SecurityContext? _securityContext;
  final bool Function(X509Certificate certificate)? _onBadCertificate;
  final Future<bool> Function(String endpoint)? _healthProbe;
  List<String> _endpoints = const [];
  Future<List<String>>? _loadInFlight;
  DateTime? _loadedAt;
  final Map<String, DateTime> _unhealthyUntil = {};
  int _nextIndex = 0;
  bool _closed = false;

  /// Returns health for every configured proxy and updates its cooldown state.
  Future<Map<String, bool>> checkHealth() async {
    _ensureOpen();
    final endpoints = await _ensureEndpoints();
    final results = <String, bool>{};
    for (final endpoint in endpoints) {
      bool healthy;
      if (_healthProbe != null) {
        healthy = await _healthProbe(
          endpoint,
        ).timeout(connectTimeout, onTimeout: () => false);
      } else {
        healthy = await _probe(endpoint);
      }
      _recordHealth(endpoint, healthy);
      results[endpoint] = healthy;
    }
    return Map.unmodifiable(results);
  }

  /// Opens a tunnel to [destination], trying available proxies in rotating order.
  Future<ConnectionTask<Socket>> connect(
    Uri destination, {
    Duration? timeout,
  }) async {
    _ensureOpen();
    final endpoints = await _ensureEndpoints();
    final deadline = timeout ?? connectTimeout;
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    final candidates = _orderedCandidates(endpoints).take(maxAttempts);
    for (final endpoint in candidates) {
      final remaining = deadline - stopwatch.elapsed;
      if (remaining <= Duration.zero) break;
      final attemptTimeout = remaining < connectTimeout
          ? remaining
          : connectTimeout;
      ConnectionTask<Socket>? connection;
      try {
        final proxy = Uri.parse(endpoint);
        connection = SocksConnection.start(
          proxyHost: InternetAddress.tryParse(proxy.host)!,
          proxyPort: proxy.port,
          targetHost: destination.host,
          targetPort: destination.hasPort
              ? destination.port
              : destination.scheme == 'https'
              ? 443
              : 80,
          tlsHost: destination.scheme == 'https' ? destination.host : null,
          securityContext: _securityContext,
          onBadCertificate: _onBadCertificate,
          timeout: attemptTimeout,
        );
        // Establish TLS inside the SOCKS connection for HTTPS. HttpClient's
        // custom connectionFactory receives a socket that it treats as already
        // connected, so it will not add TLS itself.
        await connection.socket.timeout(attemptTimeout);
        _recordHealth(endpoint, true);
        return connection;
      } catch (error) {
        lastError = error;
        connection?.cancel();
        _recordHealth(endpoint, false);
      }
    }
    throw SocketException(
      'All ${endpoints.length} SOCKS5 proxies failed for ${destination.host}: $lastError',
    );
  }

  List<String> _orderedCandidates(List<String> endpoints) {
    final now = _clock();
    final start = _nextIndex++ % endpoints.length;
    final ordered = [
      for (var offset = 0; offset < endpoints.length; offset++)
        endpoints[(start + offset) % endpoints.length],
    ];
    final available = ordered
        .where(
          (endpoint) => !(_unhealthyUntil[endpoint]?.isAfter(now) ?? false),
        )
        .toList();
    // If every endpoint is cooling down, probe all of them once rather than
    // leaving API calls unavailable until the cooldown expires.
    return available.isEmpty ? ordered : available;
  }

  Future<List<String>> _ensureEndpoints() {
    if (_closed) {
      return Future.error(StateError('The API proxy pool is closed.'));
    }
    final loadedAt = _loadedAt;
    if (_endpoints.isNotEmpty &&
        (_configuredEndpoints != null ||
            (loadedAt != null &&
                _clock().difference(loadedAt) < refreshInterval))) {
      return Future.value(_endpoints);
    }
    return _loadInFlight ??= _loadEndpoints().whenComplete(() {
      _loadInFlight = null;
    });
  }

  Future<List<String>> _loadEndpoints() async {
    final endpoints =
        _configuredEndpoints ??
        _parseEndpoints(await _endpointLoader!(defaultListUri));
    _validateEndpoints(endpoints);
    if (_configuredEndpoints == null &&
        endpoints.any((endpoint) => !_isPublicProxy(endpoint))) {
      throw const FormatException('Proxy list contains a non-public endpoint');
    }
    if (endpoints.isEmpty) {
      throw const FormatException('Proxy list contains no SOCKS5 endpoints');
    }
    _endpoints = List.unmodifiable(endpoints.toSet());
    _loadedAt = _clock();
    return _endpoints;
  }

  static List<String> parseEndpoints(String contents) =>
      _parseEndpoints(contents);

  static List<String> _parseEndpoints(String contents) => contents
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.startsWith('socks5://'))
      .where((line) => _validEndpoint(line))
      .toSet()
      .toList(growable: false);

  static bool _validEndpoint(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    return uri != null &&
        uri.scheme == 'socks5' &&
        uri.userInfo.isEmpty &&
        uri.host.isNotEmpty &&
        uri.port >= 1 &&
        uri.port <= 65535 &&
        InternetAddress.tryParse(uri.host) != null;
  }

  static bool _isPublicProxy(String endpoint) {
    final address = InternetAddress.tryParse(Uri.parse(endpoint).host);
    if (address == null ||
        address.isLoopback ||
        address.isLinkLocal ||
        address.isMulticast) {
      return false;
    }
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return !(bytes[0] == 0 ||
          bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 169 && bytes[1] == 254) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
          bytes[0] >= 224);
    }
    return (bytes[0] & 0xFE) != 0xFC && (bytes[0] & 0xE0) == 0x20;
  }

  static void _validateEndpoints(Iterable<String> endpoints) {
    if (endpoints.isEmpty ||
        endpoints.any((endpoint) => !_validEndpoint(endpoint))) {
      throw ArgumentError.value(
        endpoints,
        'endpoints',
        'Must contain valid SOCKS5 proxy URIs',
      );
    }
  }

  static Future<String> _downloadEndpointList(Uri source) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(source);
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Proxy-list server returned HTTP ${response.statusCode}',
        );
      }
      final contents = await response.transform(utf8.decoder).join();
      if (contents.length > 4 * 1024 * 1024) {
        throw const FormatException('Proxy list is larger than 4 MiB');
      }
      return contents;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _probe(String endpoint) async {
    final proxy = Uri.parse(endpoint);
    try {
      final connection = SocksConnection.start(
        proxyHost: InternetAddress.tryParse(proxy.host)!,
        proxyPort: proxy.port,
        targetHost: 'example.com',
        targetPort: 443,
        timeout: connectTimeout,
      );
      final socket = await connection.socket.timeout(connectTimeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _recordHealth(String endpoint, bool healthy) {
    if (healthy) {
      _unhealthyUntil.remove(endpoint);
    } else {
      _unhealthyUntil[endpoint] = _clock().add(cooldown);
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('The API proxy pool is closed.');
  }

  void close() {
    _closed = true;
    _unhealthyUntil.clear();
  }
}
