import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/script_thumbnail.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGPs2Pr/PwMDAwMTAxQAADFxAz/NK9FFAAAAAElFTkSuQmCC',
);

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDown(() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Future<void> pumpThumbnail(
    WidgetTester tester,
    String? address, {
    bool reducedMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: orionTheme(Brightness.dark, const Color(0xFF88B5FF)),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: ScriptThumbnail(
              imageUrl: address,
              title: 'Provider artwork',
              reducedMotion: reducedMotion,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> waitFor(WidgetTester tester, bool Function() completed) async {
    for (var attempt = 0; attempt < 30 && !completed(); attempt++) {
      // The actual image codec works outside Flutter's fake async event loop.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(
      completed(),
      isTrue,
      reason: 'The controlled image request completed',
    );
  }

  Finder decodedImages() => find.byWidgetPredicate(
    (widget) => widget is RawImage && widget.image != null,
  );

  Future<void> withClient(
    _ImageClient client,
    Future<void> Function() body,
  ) async {
    debugNetworkImageHttpClientProvider = () => client;
    try {
      await body();
    } finally {
      // Reset inside the callback, before Flutter checks painting invariants.
      debugNetworkImageHttpClientProvider = null;
    }
  }

  testWidgets('decodes provider PNG and opens a larger zoomable image viewer', (
    tester,
  ) async {
    final client = _ImageClient((_) async => _ImageResponse(_png));
    await withClient(client, () async {
      await pumpThumbnail(tester, 'https://images.example.com/artwork.png');
      await waitFor(tester, () => decodedImages().evaluate().isNotEmpty);
      expect(client.requests.single.path, '/artwork.png');
      expect(
        tester.widget<RawImage>(decodedImages()).image!.width,
        greaterThan(0),
      );
      final cardRect = tester.getRect(find.byType(ScriptThumbnail));

      await tester.tap(find.byTooltip('View image'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(Dialog), findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.maxScale, 4);
      expect(viewer.minScale, 1);
      expect(
        tester.getSize(find.byType(InteractiveViewer)).width,
        greaterThan(cardRect.width),
      );
      final fullImage = find.descendant(
        of: find.byType(Dialog),
        matching: decodedImages(),
      );
      await waitFor(tester, () => fullImage.evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Provider artwork'), findsOneWidget);
      await tester.tap(find.byTooltip('Close image'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a failed image retries a new request and recovers the artwork', (
    tester,
  ) async {
    final client = _ImageClient(
      (request) async => _ImageResponse(_png, status: request == 1 ? 503 : 200),
    );
    await withClient(client, () async {
      await pumpThumbnail(tester, 'https://images.example.com/retry.png');
      await waitFor(
        tester,
        () => find.text('Image unavailable').evaluate().isNotEmpty,
      );
      expect(client.requests, hasLength(1));
      expect(decodedImages(), findsNothing);
      await tester.tap(find.text('Retry image'));
      await waitFor(tester, () => decodedImages().evaluate().isNotEmpty);
      expect(client.requests, hasLength(2));
      expect(client.requests[0], client.requests[1]);
      expect(find.text('Image unavailable'), findsNothing);
      expect(find.text('Retry image'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'missing art has no viewer and reduced motion has a static loader',
    (tester) async {
      final pending = Completer<HttpClientResponse>();
      final client = _ImageClient((_) => pending.future);
      await withClient(client, () async {
        for (final address in <String?>[
          null,
          'https://[',
          'data:image/png;base64,AA',
        ]) {
          await pumpThumbnail(tester, address, reducedMotion: true);
          expect(find.text('No image'), findsOneWidget);
          expect(find.byTooltip('View image'), findsNothing);
          await tester.tap(find.text('No image'));
          await tester.pump();
          expect(find.byType(Dialog), findsNothing);
        }
        expect(client.requests, isEmpty);
        await pumpThumbnail(
          tester,
          'https://images.example.com/pending.png',
          reducedMotion: true,
        );
        await tester.pumpAndSettle();
        expect(client.requests, hasLength(1));
        expect(find.text('Loading image…'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.binding.hasScheduledFrame, isFalse);
        pending.complete(_ImageResponse(_png));
        await waitFor(tester, () => decodedImages().evaluate().isNotEmpty);
        expect(tester.takeException(), isNull);
      });
    },
  );
}

class _ImageClient extends Fake implements HttpClient {
  _ImageClient(this.respond);
  final Future<HttpClientResponse> Function(int request) respond;
  final List<Uri> requests = [];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return _ImageRequest(() => respond(requests.length));
  }
}

class _ImageRequest extends Fake implements HttpClientRequest {
  _ImageRequest(this.respond);
  final Future<HttpClientResponse> Function() respond;

  @override
  Future<HttpClientResponse> close() => respond();
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.bytes, {this.status = 200});
  final List<int> bytes;
  final int status;

  @override
  int get statusCode => status;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
