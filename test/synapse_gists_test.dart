import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/synapse_v3/v3_gists.dart';

void main() {
  test('raw Gist URLs validate and names match the source title rule', () {
    for (final value in [
      '',
      'not a URL',
      'file:///tmp/script.lua',
      'javascript:alert(1)',
      'https:///missing-host',
      'https://user:password@example.com/test.lua',
    ]) {
      expect(V3Gists.parse(value), isNull, reason: value);
    }
    final uri = V3Gists.parse(
      ' https://gist.githubusercontent.com/raw/my_script.lua ',
    );
    expect(uri, isNotNull);
    expect(V3Gists.title(uri!), 'My Script');
  });
  test(
    'explicit Gist loads preserve each exact body and propagate server/empty errors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      final subscription = server.listen((request) async {
        requests++;
        expect(request.uri.queryParameters['_'], isNotNull);
        switch (request.uri.path) {
          case '/one.lua':
            request.response.write('-- exact one\nprint("one")\n');
          case '/two.lua':
            request.response.write('local value = 2\n');
          case '/empty.lua':
            request.response.write('   ');
          default:
            request.response.statusCode = 503;
        }
        await request.response.close();
      });
      Uri address(String name) =>
          Uri.parse('http://127.0.0.1:${server.port}/$name');
      try {
        expect(requests, 0);
        expect(
          await V3Gists.load(address('one.lua')),
          '-- exact one\nprint("one")\n',
        );
        expect(await V3Gists.load(address('two.lua')), 'local value = 2\n');
      await expectLater(
          V3Gists.load(address('empty.lua')),
          throwsA(isA<FormatException>()),
        );
      await expectLater(
          V3Gists.load(address('failure.lua')),
          throwsA(isA<HttpException>()),
        );
        expect(requests, 4);
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
