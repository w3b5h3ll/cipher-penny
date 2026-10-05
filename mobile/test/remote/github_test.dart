import 'dart:convert';

import 'package:cipher_penny/remote/github.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const target = GitHubTarget(owner: 'paul', repo: 'data', path: 'dir/vault.cpenny.json', token: 'tok');

http.Response json(Object body, [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});

void main() {
  test('parseRepo and normalizePath', () {
    expect(parseRepo('https://github.com/paul/data.git/'), (owner: 'paul', repo: 'data'));
    expect(parseRepo(' paul/data '), (owner: 'paul', repo: 'data'));
    expect(parseRepo('paul'), isNull);
    expect(parseRepo('paul/data/x'), isNull);
    expect(normalizePath('/a/b.json'), 'a/b.json');
    expect(normalizePath('a/../b'), isNull);
    expect(normalizePath('a//b'), isNull);
  });

  test('only talks to api.github.com with the token, and requires a private repo', () async {
    final seen = <http.Request>[];
    final client = GitHubClient(target, client: MockClient((req) async {
      seen.add(req);
      return json({'private': false});
    }));
    await expectLater(client.checkRepo(),
        throwsA(isA<RemoteException>().having((e) => e.kind, 'kind', RemoteErrorKind.publicRepo)));
    expect(seen.single.url.toString(), 'https://api.github.com/repos/paul/data');
    expect(seen.single.headers['Authorization'], 'Bearer tok');
    expect(seen.single.headers['X-GitHub-Api-Version'], '2022-11-28');
  });

  test('reads inline content, falls back to the blob API, and maps 404 to null', () async {
    final text = '{"中文": 1}\n';
    final b64 = base64Encode(utf8.encode(text));
    final inline = GitHubClient(target, client: MockClient((req) async {
      expect(req.url.path, '/repos/paul/data/contents/dir/vault.cpenny.json');
      return json({'type': 'file', 'sha': 's1', 'encoding': 'base64', 'content': '${b64.substring(0, 4)}\n${b64.substring(4)}'});
    }));
    final file = await inline.readFile();
    expect(file!.sha, 's1');
    expect(file.text, text);

    final large = GitHubClient(target, client: MockClient((req) async {
      if (req.url.path.endsWith('/git/blobs/s2')) return json({'content': b64});
      return json({'type': 'file', 'sha': 's2', 'encoding': 'none', 'content': ''});
    }));
    expect((await large.readFile())!.text, text);

    final missing = GitHubClient(target, client: MockClient((_) async => json({'message': 'Not Found'}, 404)));
    expect(await missing.readFile(), isNull);
  });

  test('writes with sha and maps errors', () async {
    late Map<String, Object?> body;
    final ok = GitHubClient(target, client: MockClient((req) async {
      expect(req.method, 'PUT');
      body = (jsonDecode(req.body) as Map).cast();
      return json({'content': {'sha': 'new'}}, 200);
    }));
    expect(await ok.writeFile('hello', 'old'), 'new');
    expect(body['sha'], 'old');
    expect(utf8.decode(base64Decode(body['content'] as String)), 'hello');

    Future<RemoteErrorKind> kindFor(http.Response res) async {
      final c = GitHubClient(target, client: MockClient((_) async => res));
      try {
        await c.writeFile('x', null);
      } on RemoteException catch (e) {
        return e.kind;
      }
      fail('expected RemoteException');
    }

    expect(await kindFor(json({}, 409)), RemoteErrorKind.conflict);
    expect(await kindFor(json({'message': 'Invalid request. "sha" wasn\'t supplied.'}, 422)), RemoteErrorKind.conflict);
    expect(await kindFor(json({}, 401)), RemoteErrorKind.auth);
    expect(await kindFor(json({}, 403)), RemoteErrorKind.forbidden);
    expect(await kindFor(json({}, 403, {'x-ratelimit-remaining': '0'})), RemoteErrorKind.rateLimited);

    final offline = GitHubClient(target, client: MockClient((_) async => throw http.ClientException('offline')));
    await expectLater(offline.readFile(),
        throwsA(isA<RemoteException>().having((e) => e.kind, 'kind', RemoteErrorKind.network)));
  });
}
