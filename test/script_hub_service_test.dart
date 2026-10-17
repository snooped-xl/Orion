import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/remote_script.dart';
import 'package:orion/services/script_hub_service.dart';

ScriptHttpResponse _json(Object value, {int status = 200}) =>
    ScriptHttpResponse(
      statusCode: status,
      body: utf8.encode(jsonEncode(value)),
      contentType: 'application/json',
    );

ScriptHttpResponse _source(String body) => ScriptHttpResponse(
  statusCode: 200,
  body: utf8.encode(body),
  contentType: 'text/plain',
);

RemoteScript _script(
  ScriptProvider provider, {
  String? body,
  String? rawUrl,
  String? imageUrl,
}) => RemoteScript(
  id: 'script-id',
  provider: provider,
  title: 'Example',
  game: 'Studio',
  description: 'Fixture',
  externalUrl: 'https://${provider.domain}/script/example',
  body: body,
  rawUrl: rawUrl,
  imageUrl: imageUrl,
);

void main() {
  test(
    'RobloxScripts parses games, access flags, URLs and exact source text',
    () async {
      final service = ScriptHubService(
        transport: (uri, headers) async => _json({
          'data': [
            {
              'id': 'roblox-id',
              'slug': 'sample orbit',
              'title': 'Orbit',
              'image': 'https://robloxscripts.com/images/scripts/orbit.webp',
              'game': null,
              'games': [
                {'name': 'Studio'},
              ],
              'script': '  print("hello")\n',
              'rawScriptUrl': '/raw/sample',
              'description': 'A geometry example',
              'accessType': 'paid',
              'key': true,
              'verified': 'yes',
              'views': '125',
              'updatedAt': '2026-10-12T12:00:00Z',
            },
          ],
          'pagination': {'hasMore': false},
        }),
      );
      addTearDown(service.close);
      final page = await service.fetch(ScriptProvider.robloxScripts, '', 1);
      final item = page.items.single;
      expect(item.id, 'roblox-id');
      expect(item.game, 'Studio');
      expect(
        item.imageUrl,
        'https://robloxscripts.com/images/scripts/orbit.webp',
      );
      expect(item.body, '  print("hello")\n');
      expect(item.rawUrl, 'https://robloxscripts.com/raw/sample');
      expect(
        item.externalUrl,
        'https://robloxscripts.com/script/sample%20orbit',
      );
      expect(item.views, 125);
      expect(item.isPaid && item.hasKey && item.isVerified, isTrue);
      expect(item.updatedAt, DateTime.utc(2026, 10, 12, 12));
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'ScriptBlox retains every API result and follows nextPage metadata',
    () async {
      final service = ScriptHubService(
        transport: (uri, headers) async => _json({
          'result': {
            'totalPages': 6,
            'nextPage': 3,
            'scripts': List.generate(
              20,
              (index) => {
                '_id': '$index',
                'slug': 'blox-$index',
                'title': 'Blox $index',
                'image': '/images/sb/blox-$index.png',
                'game': {'name': 'Studio'},
                'scriptType': 'paid',
                'keySystem': 'required',
                'verified': true,
                'views': index,
                'script': 'print("$index")',
              },
            ),
          },
        }),
      );
      addTearDown(service.close);
      final page = await service.fetch(ScriptProvider.scriptBlox, 'studio', 2);
      expect(page.items, hasLength(20));
      expect(page.items.last.id, '19');
      expect(
        page.items.first.imageUrl,
        'https://scriptblox.com/images/sb/blox-0.png',
      );
      expect(page.items.first.isPaid, isTrue);
      expect(page.items.first.hasKey, isTrue);
      expect(page.hasMore, isTrue);
    },
  );

  test(
    'HaxHell reads nested stats and flags and resolves actual raw endpoints',
    () async {
      final service = ScriptHubService(
        transport: (uri, headers) async => _json({
          'data': [
            {
              'id': 'hax-id',
              'title': 'Example',
              'game': {
                'name': 'Studio',
                'thumbnailUrl': 'https://tr.rbxcdn.com/game.webp',
              },
              'media': {
                'thumbnailUrl':
                    'https://cdn.haxhell.com/thumbnails/example.webp',
              },
              'stats': {'views': 987},
              'flags': {'isPaid': true, 'keySystem': true, 'verified': true},
              'links': {
                'webpage': '/scripts/example',
                'raw': '/api/raw/example',
              },
              'updatedAt': 1791806400000,
            },
          ],
          'pagination': {'hasMore': true, 'totalPages': null},
        }),
      );
      addTearDown(service.close);
      final page = await service.fetch(ScriptProvider.haxHell, '', 1);
      final item = page.items.single;
      expect(item.views, 987);
      expect(item.imageUrl, 'https://cdn.haxhell.com/thumbnails/example.webp');
      expect(item.isPaid && item.hasKey && item.isVerified, isTrue);
      expect(item.body, isNull);
      expect(item.rawUrl, 'https://haxhell.com/api/raw/example');
      expect(item.externalUrl, 'https://haxhell.com/scripts/example');
      expect(item.updatedAt?.isUtc, isTrue);
      expect(page.hasMore, isTrue);
    },
  );

  test(
    'Rscripts retains16results and parses lastUpdated plus maxPages',
    () async {
      final service = ScriptHubService(
        transport: (uri, headers) async => _json({
          'scripts': List.generate(
            16,
            (index) => {
              '_id': 'r-$index',
              'slug': 'rscript-$index',
              'title': 'Script $index',
              'image': 'https://tr.rbxcdn.com/script-$index.webp',
              'game': {'title': 'Studio'},
              'paid': false,
              'keySystem': true,
              'lastUpdated': '2026-10-11T08:03:00Z',
              'views': -1,
              'rawScript': '/raw/script-$index.txt',
            },
          ),
          'info': {'currentPage': 4, 'maxPages': 4},
        }),
      );
      addTearDown(service.close);
      final page = await service.fetch(ScriptProvider.rscripts, 'studio', 4);
      expect(page.items, hasLength(16));
      expect(page.items.first.game, 'Studio');
      expect(page.items.first.imageUrl, 'https://tr.rbxcdn.com/script-0.webp');
      expect(page.items.first.updatedAt, DateTime.utc(2026, 10, 11, 8, 3));
      expect(page.items.first.views, 0);
      expect(page.items.first.hasKey, isTrue);
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'all request URLs, query encoding, and original headers are preserved',
    () async {
      final calls = <(Uri, Map<String, String>)>[];
      final service = ScriptHubService(
        transport: (uri, headers) async {
          calls.add((uri, headers));
          return _json(switch (uri.host) {
            'scriptblox.com' => {
              'result': {'scripts': [], 'nextPage': null},
            },
            'rscripts.net' => {
              'scripts': [],
              'info': {'maxPages': 0},
            },
            _ => {
              'data': [],
              'pagination': {'hasMore': false},
            },
          });
        },
      );
      addTearDown(service.close);
      for (final provider in ScriptProvider.values) {
        await service.fetch(provider, '  a&b / café  ', 7);
      }
      expect(calls.map((call) => call.$1.path), [
        '/api/v1/scripts',
        '/api/script/search',
        '/api/v1/search/scripts',
        '/api/v2/scripts',
      ]);
      for (var index = 0; index < calls.length; index++) {
        expect(calls[index].$1.queryParameters['q'], 'a&b / café');
        expect(calls[index].$1.queryParameters['page'], '7');
        expect(calls[index].$2['User-Agent'], 'Orbit/1.0 ScriptHub');
        expect(calls[index].$2['Accept'], 'application/json');
        expect(
          calls[index].$2['Referer'],
          'https://${ScriptProvider.values[index].domain}/',
        );
      }
      await service.fetch(ScriptProvider.scriptBlox, '', 1);
      expect(calls.last.$1.path, '/api/script/fetch');
      await service.fetch(ScriptProvider.haxHell, '', 1);
      expect(calls.last.$1.path, '/api/v1/scripts');
      await service.fetch(ScriptProvider.rscripts, 'x' * 130, 1);
      expect(calls.last.$1.queryParameters['q']!.length, 100);
    },
  );

  test(
    'missing or invalid script artwork falls back to normalized game art',
    () async {
      for (final provider in ScriptProvider.values) {
        var requests = 0;
        final service = ScriptHubService(
          transport: (uri, headers) async {
            requests++;
            final item = {
              'id': 'image-fallback',
              'title': 'Image fallback',
              'image': 'javascript:alert(1)',
              'media': {'thumbnailUrl': 'https://['},
              'game': {
                'name': 'Studio',
                'thumbnailUrl': 'file:///tmp/thumb.png',
                'imageUrl': '//cdn.example.com/game.webp',
                'iconUrl': '/images/icon.webp',
              },
              'script': ' print("preserved")\n',
            };
            return _json(switch (provider) {
              ScriptProvider.scriptBlox => {
                'result': {
                  'scripts': [item],
                  'nextPage': null,
                },
              },
              ScriptProvider.rscripts => {
                'scripts': [item],
                'info': {'maxPages': 1},
              },
              _ => {
                'data': [item],
                'pagination': {'hasMore': false},
              },
            });
          },
        );
        final result = await service.fetch(provider, '', 1);
        expect(
          result.items.single.imageUrl,
          'https://cdn.example.com/game.webp',
          reason: provider.label,
        );
        expect(
          await service.loadScript(result.items.single),
          ' print("preserved")\n',
        );
        expect(
          requests,
          1,
          reason: 'Thumbnail parsing must not download image bytes',
        );
        service.close();
      }
    },
  );

  test(
    'game arrays and relative image paths retain the provider origin',
    () async {
      final service = ScriptHubService(
        transport: (uri, headers) async => _json({
          'data': [
            {
              'id': 'game-array',
              'title': 'Array game',
              'game': null,
              'games': [
                {'name': 'Studio', 'iconUrl': 'images/game icon.webp'},
              ],
            },
          ],
          'pagination': {'hasMore': false},
        }),
      );
      addTearDown(service.close);
      final page = await service.fetch(ScriptProvider.robloxScripts, '', 1);
      expect(page.items.single.game, 'Studio');
      expect(
        page.items.single.imageUrl,
        'https://robloxscripts.com/images/game%20icon.webp',
      );
    },
  );

  test(
    'invalid thumbnail metadata is ignored without losing script listings',
    () async {
      final service = ScriptHubService(
        transport: (uri, headers) async => _json({
          'data': [
            for (final image in [
              null,
              42,
              <String, Object?>{},
              '',
              '  ',
              'data:image/png;base64,AA',
              'https://user:password@example.com/a.webp',
              'http://127.0.0.1/a.webp',
              'https://[',
              'https://example.com/a\nb.webp',
            ])
              {
                'id': 'invalid-${image.hashCode}',
                'title': 'Still listed',
                'image': image,
              },
          ],
          'pagination': {'hasMore': false},
        }),
      );
      addTearDown(service.close);
      final page = await service.fetch(ScriptProvider.haxHell, '', 1);
      expect(page.items, hasLength(10));
      expect(page.items.every((item) => item.imageUrl == null), isTrue);
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'HTTP failures expose their actual status without fabricated results',
    () async {
      final service = ScriptHubService(
        transport: (uri, headers) async =>
            _json({'message': 'Blocked'}, status: 403),
      );
      addTearDown(service.close);
      await expectLater(
        service.fetch(ScriptProvider.haxHell, '', 1),
        throwsA(
          isA<ScriptHubException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having(
                (error) => error.message,
                'message',
                contains('HTTP 403'),
              ),
        ),
      );
    },
  );

  test(
    'malformed provider data is an error rather than an empty success',
    () async {
      final service = ScriptHubService(
        transport: (uri, headers) async => _json({
          'result': {'message': 'Unexpected schema'},
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.fetch(ScriptProvider.scriptBlox, '', 1),
        throwsA(isA<ScriptHubException>()),
      );
    },
  );

  test(
    'bounded responses reject oversized JSON and source before opening them',
    () async {
      final service = ScriptHubService(
        maximumResponseBytes: 20,
        transport: (uri, headers) async => _source('x' * 21),
      );
      addTearDown(service.close);
      await expectLater(
        service.fetch(ScriptProvider.rscripts, '', 1),
        throwsA(
          isA<ScriptHubException>().having(
            (error) => error.message,
            'message',
            contains('too large'),
          ),
        ),
      );
      await expectLater(
        service.loadScript(
          _script(
            ScriptProvider.rscripts,
            rawUrl: 'https://rscripts.net/raw/test.txt',
          ),
        ),
        throwsA(isA<ScriptHubException>()),
      );
    },
  );

  test(
    'raw source is downloaded exactly and URLs inside source are never followed',
    () async {
      final calls = <Uri>[];
      const source =
          'loadstring(game:HttpGet("https://example.com/other.lua"))()\n';
      final service = ScriptHubService(
        transport: (uri, headers) async {
          calls.add(uri);
          return _source(source);
        },
      );
      addTearDown(service.close);
      for (final provider in [
        ScriptProvider.haxHell,
        ScriptProvider.rscripts,
      ]) {
        final uri = 'https://${provider.domain}/raw/example';
        expect(
          await service.loadScript(_script(provider, rawUrl: uri)),
          source,
        );
      }
      expect(calls, hasLength(2));
      expect(calls.any((uri) => uri.host == 'example.com'), isFalse);
      expect(
        await service.loadScript(
          _script(ScriptProvider.robloxScripts, body: '  print("inline")\n'),
        ),
        '  print("inline")\n',
      );
      expect(calls, hasLength(2));
    },
  );

  test('missing ScriptBlox body loads its documented detail API', () async {
    final calls = <Uri>[];
    final service = ScriptHubService(
      transport: (uri, headers) async {
        calls.add(uri);
        return _json({
          'script': {'script': 'print("detail")\n'},
        });
      },
    );
    addTearDown(service.close);
    expect(
      await service.loadScript(_script(ScriptProvider.scriptBlox)),
      'print("detail")\n',
    );
    expect(
      calls.single.toString(),
      'https://scriptblox.com/api/script/script-id',
    );
  });

  test(
    'ScriptBlox missing detail source falls back to its documented raw API',
    () async {
      final calls = <Uri>[];
      final service = ScriptHubService(
        transport: (uri, headers) async {
          calls.add(uri);
          return calls.length == 1
              ? _json({'script': {}})
              : _source('print("raw")');
        },
      );
      addTearDown(service.close);
      expect(
        await service.loadScript(_script(ScriptProvider.scriptBlox)),
        'print("raw")',
      );
      expect(
        calls.last.toString(),
        'https://scriptblox.com/api/script/raw/script-id',
      );
    },
  );

  test('raw HTML responses are errors instead of imported source', () async {
    final service = ScriptHubService(
      transport: (uri, headers) async =>
          _source('<!DOCTYPE html><html>Access denied</html>'),
    );
    addTearDown(service.close);
    await expectLater(
      service.loadScript(
        _script(
          ScriptProvider.haxHell,
          rawUrl: 'https://haxhell.com/api/raw/fixture',
        ),
      ),
      throwsA(
        isA<ScriptHubException>().having(
          (error) => error.message,
          'message',
          contains('webpage'),
        ),
      ),
    );
  });

  test('unsafe URLs are rejected before the transport runs', () async {
    var requests = 0;
    final service = ScriptHubService(
      transport: (uri, headers) async {
        requests++;
        return _source('print("no")');
      },
    );
    addTearDown(service.close);
    for (final address in [
      'file:///etc/passwd',
      'http://localhost/script',
      'http://127.0.0.1/script',
      'http://10.1.2.3/script',
      'https://[::1]/script',
      'http://[::ffff:192.168.1.2]/script',
      'https://user:password@example.com/a',
    ]) {
      await expectLater(
        service.loadScript(_script(ScriptProvider.rscripts, rawUrl: address)),
        throwsA(isA<ScriptHubException>()),
      );
    }
    expect(requests, 0);
  });

  test(
    'the request has a total timeout and close prevents further requests',
    () async {
      final service = ScriptHubService(
        timeout: const Duration(milliseconds: 20),
        transport: (uri, headers) => Completer<ScriptHttpResponse>().future,
      );
      await expectLater(
        service.fetch(ScriptProvider.scriptBlox, '', 1),
        throwsA(
          isA<ScriptHubException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      service.close();
      await expectLater(
        service.fetch(ScriptProvider.scriptBlox, '', 1),
        throwsStateError,
      );
    },
  );

  test('favorite metadata round trips without requiring cached source', () {
    final original = _script(
      ScriptProvider.rscripts,
      body: 'print("not persisted")',
      rawUrl: 'https://rscripts.net/raw/example',
      imageUrl: 'https://tr.rbxcdn.com/image.webp',
    );
    final restored = RemoteScript.fromJson({
      ...original.toJson(),
      'body': null,
    });
    expect(restored?.key, original.key);
    expect(restored?.rawUrl, original.rawUrl);
    expect(restored?.imageUrl, original.imageUrl);
    expect(restored?.body, isNull);
    expect(
      RemoteScript.fromJson({'id': 'broken', 'provider': 'unknown'}),
      isNull,
    );
  });

  test(
    'thumbnail metadata restores old favorites and rejects invalid saved URLs',
    () {
      final item = _script(ScriptProvider.scriptBlox);
      final legacy = {...item.toJson()}..remove('imageUrl');
      expect(RemoteScript.fromJson(legacy)?.imageUrl, isNull);
      expect(
        RemoteScript.fromJson({
          ...legacy,
          'imageUrl': '/images/sb/fixture.png',
        })?.imageUrl,
        'https://scriptblox.com/images/sb/fixture.png',
      );
      expect(
        RemoteScript.fromJson({
          ...legacy,
          'imageUrl': '//cdn.example.com/fixture.webp',
        })?.imageUrl,
        'https://cdn.example.com/fixture.webp',
      );
      for (final image in [
        42,
        'data:image/png;base64,AA',
        'file:///tmp/image.png',
        'https://[',
        'https://user:password@example.com/a.webp',
        'https://example.com/a\nb.webp',
      ]) {
        final restored = RemoteScript.fromJson({...legacy, 'imageUrl': image});
        expect(restored?.imageUrl, isNull);
        expect(restored?.key, item.key);
      }
    },
  );
}
