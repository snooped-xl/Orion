import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/api_proxy_pool.dart';

void main() {
  test('parses only valid SOCKS5 records from the upstream list', () {
    expect(
      ApiProxyPool.parseEndpoints('''
# refreshed proxy list
socks5://192.0.2.10:1080
http://192.0.2.11:8080
socks4://192.0.2.12:1080
socks5://bad:port
socks5://192.0.2.10:1080
'''),
      ['socks5://192.0.2.10:1080'],
    );
  });

  test('loads endpoint list from the configured GitHub source', () async {
    Uri? requested;
    final pool = ApiProxyPool(
      endpointLoader: (uri) async {
        requested = uri;
        return 'socks5://8.8.8.8:1080\nhttp://8.8.4.4:8080';
      },
      healthProbe: (_) async => true,
    );
    expect(await pool.checkHealth(), {'socks5://8.8.8.8:1080': true});
    expect(requested, ApiProxyPool.defaultListUri);
    pool.close();
  });

  test('health checks update endpoint status and cooldown', () async {
    var now = DateTime.utc(2026, 1, 1);
    final pool = ApiProxyPool(
      endpoints: ['socks5://8.8.8.8:1080', 'socks5://1.1.1.1:1081'],
      clock: () => now,
      cooldown: const Duration(seconds: 10),
      healthProbe: (endpoint) async => endpoint.endsWith(':1081'),
    );
    expect(await pool.checkHealth(), {
      'socks5://8.8.8.8:1080': false,
      'socks5://1.1.1.1:1081': true,
    });
    now = now.add(const Duration(seconds: 11));
    expect(await pool.checkHealth(), {
      'socks5://8.8.8.8:1080': false,
      'socks5://1.1.1.1:1081': true,
    });
    pool.close();
  });

  test('connect fails over and completes SOCKS5 handshake', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<void>();
    final subscription = server.listen((socket) async {
      final reader = _SocketReader(socket);
      try {
        expect(await reader.read(3), [5, 1, 0]);
        socket.add([5, 0]);
        await socket.flush();
        expect(await reader.read(5), [5, 1, 0, 3, 11]);
        await reader.read(13);
        socket.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 80]);
        await socket.flush();
        if (!accepted.isCompleted) accepted.complete();
      } catch (error, stack) {
        if (!accepted.isCompleted) accepted.completeError(error, stack);
      }
    });
    final pool = ApiProxyPool(
      endpoints: [
        'socks5://127.0.0.1:$deadPort',
        'socks5://127.0.0.1:${server.port}',
      ],
      connectTimeout: const Duration(seconds: 1),
    );
    try {
      final task = await pool.connect(
        Uri.parse('http://example.com/'),
        timeout: const Duration(seconds: 2),
      );
      final socket = await task.socket;
      await accepted.future.timeout(const Duration(seconds: 2));
      socket.destroy();
    } finally {
      pool.close();
      await subscription.cancel();
      await server.close();
    }
  });

  test('HTTPS SOCKS connection returns a TLS-secured socket', () async {
    final certificate = await _createTestCertificate();
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<void>();
    final proxySubscription = proxy.listen((socket) async {
      final reader = _SocketReader(socket);
      try {
        expect(await reader.read(3), [5, 1, 0]);
        socket.add([5, 0]);
        await socket.flush();
        expect(await reader.read(5), [5, 1, 0, 3, 11]);
        await reader.read(13);
        socket.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 443]);
        await socket.flush();
        final secured = await SecureSocket.secureServer(
          socket,
          SecurityContext()
            ..useCertificateChainBytes(certificate.cert)
            ..usePrivateKeyBytes(certificate.key),
        );
        if (!accepted.isCompleted) accepted.complete();
        secured.destroy();
      } catch (error, stack) {
        if (!accepted.isCompleted) accepted.completeError(error, stack);
        socket.destroy();
      }
    });
    final pool = ApiProxyPool(
      endpoints: ['socks5://127.0.0.1:${proxy.port}'],
      connectTimeout: const Duration(seconds: 3),
      onBadCertificate: (_) => true,
    );
    try {
      final task = await pool.connect(
        Uri.parse('https://example.com/'),
        timeout: const Duration(seconds: 5),
      );
      final socket = await task.socket;
      expect(socket, isA<SecureSocket>());
      await accepted.future.timeout(const Duration(seconds: 3));
      socket.destroy();
    } finally {
      pool.close();
      await proxySubscription.cancel();
      await proxy.close();
    }
  });
}

Future<({List<int> cert, List<int> key})> _createTestCertificate() async {
  final directory = await Directory.systemTemp.createTemp('orion-tls-test');
  try {
    final key = File('${directory.path}/key.pem');
    final cert = File('${directory.path}/cert.pem');
    final process = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      key.path,
      '-out',
      cert.path,
      '-days',
      '1',
      '-subj',
      '/CN=example.com',
      '-addext',
      'subjectAltName=DNS:example.com',
    ]);
    if (process.exitCode != 0) {
      throw StateError('Could not create local TLS test certificate.');
    }
    return (cert: await cert.readAsBytes(), key: await key.readAsBytes());
  } finally {
    await directory.delete(recursive: true);
  }
}

class _SocketReader {
  _SocketReader(Socket socket) {
    socket.listen(
      (chunk) {
        _bytes.addAll(chunk);
        final pending = _pending;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onError: (Object error, StackTrace stack) {
        final pending = _pending;
        if (pending != null && !pending.isCompleted) {
          pending.completeError(error, stack);
        }
      },
      onDone: () {
        final pending = _pending;
        if (pending != null && !pending.isCompleted) {
          pending.completeError(const SocketException('closed'));
        }
      },
    );
  }

  final List<int> _bytes = [];
  Completer<void>? _pending;

  Future<List<int>> read(int count) async {
    while (_bytes.length < count) {
      final ready = _pending = Completer<void>();
      await ready.future;
    }
    final result = _bytes.take(count).toList();
    _bytes.removeRange(0, count);
    _pending = null;
    return result;
  }
}
