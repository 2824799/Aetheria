import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SyncProvider provider;
  late HttpClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = SyncProvider();
    await provider.start(LibraryProvider());
    client = HttpClient();
  });

  tearDown(() {
    client.close(force: true);
    provider.dispose();
  });

  Future<({int status, String body})> send(
    String method,
    String path, {
    String? body,
    String? token,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${provider.localPort}$path'),
    );
    if (token != null) {
      request.headers.set('X-Aetheria-Sync-Token', token);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  Future<IncomingSyncRequest> nextPrompt({String? from}) {
    bool matches() {
      final request = provider.incomingRequest;
      return request != null && (from == null || request.deviceName == from);
    }

    if (matches()) {
      return Future.value(provider.incomingRequest);
    }
    final completer = Completer<IncomingSyncRequest>();
    late void Function() listener;
    listener = () {
      if (matches()) {
        provider.removeListener(listener);
        completer.complete(provider.incomingRequest);
      }
    };
    provider.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 5));
  }

  String approvalBody(String deviceName) =>
      jsonEncode({'deviceId': 'id-$deviceName', 'deviceName': deviceName});

  test(
    'a malformed approval request is rejected and the server survives',
    () async {
      expect(provider.localPort, isNotNull);

      final malformed = await send('POST', '/sync/request', body: 'not json');
      expect(malformed.status, HttpStatus.badRequest);
      expect(provider.incomingRequest, isNull);

      final notAnObject = await send('POST', '/sync/request', body: '[1, 2]');
      expect(notAnObject.status, HttpStatus.badRequest);

      final unauthorized = await send('GET', '/sync/manifest');
      expect(unauthorized.status, HttpStatus.unauthorized);
    },
  );

  test('a pending approval prompt does not block other requests', () async {
    final pending = send('POST', '/sync/request', body: approvalBody('Phone'));
    final prompt = await nextPrompt();
    expect(prompt.deviceName, 'Phone');

    final other = await send(
      'GET',
      '/nope',
    ).timeout(const Duration(seconds: 5));
    expect(other.status, HttpStatus.notFound);

    await provider.approveIncomingRequest(prompt.id);
    final approved = jsonDecode((await pending).body) as Map<String, dynamic>;
    expect(approved['approved'], isTrue);
    expect(provider.incomingRequest, isNull);

    final token = approved['token'] as String;
    final withToken = await send('GET', '/sync/manifest', token: token);
    expect(withToken.status, isNot(HttpStatus.unauthorized));
  });

  test('approval prompts are shown one at a time', () async {
    final first = send('POST', '/sync/request', body: approvalBody('First'));
    final firstPrompt = await nextPrompt(from: 'First');

    final second = send('POST', '/sync/request', body: approvalBody('Second'));
    // Give the second request time to arrive; it must not replace the prompt.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(provider.incomingRequest?.id, firstPrompt.id);

    await provider.denyIncomingRequest(firstPrompt.id);
    expect(jsonDecode((await first).body), {'approved': false});

    final secondPrompt = await nextPrompt(from: 'Second');
    expect(secondPrompt.id, isNot(firstPrompt.id));
    await provider.approveIncomingRequest(secondPrompt.id);
    final approved = jsonDecode((await second).body) as Map<String, dynamic>;
    expect(approved['approved'], isTrue);
  });
}
