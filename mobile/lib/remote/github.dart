import 'dart:convert';

import 'package:http/http.dart' as http;

// Talks to the GitHub REST API for sync (F-SYNC). Port of src/remote/github.ts.
// Only ciphertext envelopes are ever sent, and only to api.github.com (spec A-4).

const _api = 'https://api.github.com';

class GitHubTarget {
  const GitHubTarget({required this.owner, required this.repo, required this.path, required this.token});
  factory GitHubTarget.fromJson(Map<String, Object?> json) => GitHubTarget(
        owner: json['owner'] as String,
        repo: json['repo'] as String,
        path: json['path'] as String,
        token: json['token'] as String,
      );

  final String owner;
  final String repo;

  /// File path inside the repo, e.g. `vault.cpenny.json`.
  final String path;
  final String token;

  Map<String, Object?> toJson() => {'owner': owner, 'repo': repo, 'path': path, 'token': token};
}

class RemoteFile {
  const RemoteFile(this.sha, this.text);

  /// Git blob sha; required to update the file without clobbering other writers.
  final String sha;
  final String text;
}

enum RemoteErrorKind { network, auth, forbidden, notFound, publicRepo, conflict, rateLimited, unexpected }

class RemoteException implements Exception {
  const RemoteException(this.kind, this.message);
  final RemoteErrorKind kind;
  final String message;
  @override
  String toString() => message;
}

final _name = RegExp(r'^[A-Za-z0-9_.-]+$');

/// Accepts `owner/repo` or a github.com URL.
({String owner, String repo})? parseRepo(String input) {
  final trimmed = input
      .trim()
      .replaceFirst(RegExp(r'^https?://github\.com/', caseSensitive: false), '')
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'\.git$', caseSensitive: false), '');
  final parts = trimmed.split('/');
  if (parts.length != 2 || !_name.hasMatch(parts[0]) || !_name.hasMatch(parts[1])) return null;
  return (owner: parts[0], repo: parts[1]);
}

/// Normalises a file path; rejects empty segments and `..`.
String? normalizePath(String input) {
  final segments = input.trim().replaceFirst(RegExp(r'^/+'), '').split('/');
  if (segments.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
  return segments.join('/');
}

class GitHubClient {
  GitHubClient(this.target, {http.Client? client}) : _client = client ?? http.Client();

  final GitHubTarget target;
  final http.Client _client;

  Uri get _repoUrl => Uri.parse('$_api/repos/${Uri.encodeComponent(target.owner)}/${Uri.encodeComponent(target.repo)}');

  Uri get _contentsUrl =>
      Uri.parse('$_repoUrl/contents/${target.path.split('/').map(Uri.encodeComponent).join('/')}');

  Future<http.Response> _request(Uri url, {String method = 'GET', Object? body}) async {
    final request = http.Request(method, url)
      ..headers.addAll({
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ${target.token}',
        'X-GitHub-Api-Version': '2022-11-28',
        'Cache-Control': 'no-cache',
      });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on Exception {
      throw const RemoteException(RemoteErrorKind.network, '无法连接 GitHub，请检查网络');
    }
  }

  static String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      return body is Map && body['message'] is String ? body['message'] as String : '';
    } on FormatException {
      return '';
    }
  }

  static Never _fail(http.Response res, String notFound) {
    if (res.statusCode == 401) throw const RemoteException(RemoteErrorKind.auth, 'GitHub 令牌无效或已过期');
    if (res.statusCode == 429 || (res.statusCode == 403 && res.headers['x-ratelimit-remaining'] == '0')) {
      throw const RemoteException(RemoteErrorKind.rateLimited, 'GitHub 请求过于频繁，请稍后再试');
    }
    if (res.statusCode == 403) {
      throw const RemoteException(RemoteErrorKind.forbidden, '令牌没有这个仓库的读写权限（需要 Contents: Read and write）');
    }
    if (res.statusCode == 404) throw RemoteException(RemoteErrorKind.notFound, notFound);
    final detail = _errorMessage(res);
    throw RemoteException(RemoteErrorKind.unexpected, 'GitHub 返回错误 ${res.statusCode}${detail.isEmpty ? '' : '：$detail'}');
  }

  static bool _ok(http.Response res) => res.statusCode >= 200 && res.statusCode < 300;

  static Object? _json(http.Response res) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const RemoteException(RemoteErrorKind.unexpected, 'GitHub 返回的数据无法解析');
    }
  }

  static String _decodeText(String base64) => utf8.decode(base64Decode(base64.replaceAll(RegExp(r'\s'), '')));

  /// F-SYNC-1: the repo must exist, be reachable with the token, and be private.
  Future<void> checkRepo() async {
    final res = await _request(_repoUrl);
    if (!_ok(res)) _fail(res, '找不到这个仓库，或令牌无权访问它');
    final repo = _json(res);
    if (repo is! Map || repo['private'] != true) {
      throw const RemoteException(RemoteErrorKind.publicRepo, '这是公开仓库。为了安全，同步只能使用私有仓库');
    }
  }

  /// Returns null if the file does not exist yet.
  Future<RemoteFile?> readFile() async {
    final res = await _request(_contentsUrl);
    if (res.statusCode == 404) return null;
    if (!_ok(res)) _fail(res, '找不到同步文件');
    final file = _json(res);
    if (file is! Map || file['type'] != 'file' || file['sha'] is! String) {
      throw const RemoteException(RemoteErrorKind.unexpected, '同步路径不是一个文件');
    }
    final sha = file['sha'] as String;
    if (file['encoding'] == 'base64' && file['content'] is String) {
      return RemoteFile(sha, _decodeText(file['content'] as String));
    }
    // Files over 1 MB come back without inline content.
    final blobRes = await _request(Uri.parse('$_repoUrl/git/blobs/${Uri.encodeComponent(sha)}'));
    if (!_ok(blobRes)) _fail(blobRes, '找不到同步文件');
    final blob = _json(blobRes);
    if (blob is! Map || blob['content'] is! String) {
      throw const RemoteException(RemoteErrorKind.unexpected, '无法读取同步文件');
    }
    return RemoteFile(sha, _decodeText(blob['content'] as String));
  }

  /// Creates (`sha` == null) or updates the file. Throws a [RemoteErrorKind.conflict]
  /// error if someone else changed it since `sha` was read. Returns the new sha.
  Future<String> writeFile(String text, String? sha) async {
    final res = await _request(_contentsUrl, method: 'PUT', body: {
      'message': 'CipherPenny 同步 ${DateTime.now().toUtc().toIso8601String()}',
      'content': base64Encode(utf8.encode(text)),
      'sha': ?sha,
    });
    if (res.statusCode == 409) throw const RemoteException(RemoteErrorKind.conflict, '远端文件已被其他设备更新');
    if (res.statusCode == 422) {
      // Returned when the file appeared since we read it and no sha was sent.
      final detail = _errorMessage(res);
      if (RegExp('sha', caseSensitive: false).hasMatch(detail)) {
        throw const RemoteException(RemoteErrorKind.conflict, '远端文件已被其他设备更新');
      }
      throw RemoteException(RemoteErrorKind.unexpected, 'GitHub 拒绝了写入${detail.isEmpty ? '' : '：$detail'}');
    }
    if (!_ok(res)) _fail(res, '找不到这个仓库，或令牌无权写入');
    final body = _json(res);
    final content = body is Map ? body['content'] : null;
    if (content is! Map || content['sha'] is! String) {
      throw const RemoteException(RemoteErrorKind.unexpected, 'GitHub 返回的数据不完整');
    }
    return content['sha'] as String;
  }
}
