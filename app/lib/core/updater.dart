import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 当前应用版本。与 pubspec.yaml 的 version 保持一致。
const String appVersion = '1.2.0';

/// 默认更新源。用户可在设置里改成任意公开 GitHub 仓库链接。
const String defaultRepoUrl = 'https://github.com/SubmergeDQ/Auto-WeLearn';

enum UpdateTarget { windows, android }

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
    this.publishedAt,
  });

  /// 去掉前缀 v 的版本号，例如 `1.1.0`
  final String version;
  final String tagName;
  final String notes;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
  final DateTime? publishedAt;
}

final _slugPart = RegExp(r'^[A-Za-z0-9_.-]+$');

/// 把 GitHub 仓库链接解析成 `owner/repo`。
///
/// 支持 `https://github.com/owner/repo`、`github.com/owner/repo`、
/// `owner/repo`，以及带 `/releases`、`.git` 后缀的写法；非 GitHub 链接返回 null。
String? parseRepoSlug(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final direct = RegExp(r'^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$')
      .firstMatch(text);
  if (direct != null) return '${direct.group(1)}/${direct.group(2)}';

  final url = text.contains('://') ? text : 'https://$text';
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host != 'github.com' && host != 'www.github.com') return null;

  final segments = uri.pathSegments;
  if (segments.length < 2) return null;
  final owner = segments[0];
  var repo = segments[1];
  if (!_slugPart.hasMatch(owner)) return null;
  if (repo.endsWith('.git')) repo = repo.substring(0, repo.length - 4);
  if (!_slugPart.hasMatch(repo)) return null;
  return '$owner/$repo';
}

/// 语义化版本比较：`v1.1.0` 与 `1.0.2` 都按数字段比较。
int compareVersions(String a, String b) {
  List<int> parts(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final core = cleaned.split(RegExp(r'[-+]')).first;
    return [
      for (final bit in core.split('.'))
        int.tryParse(RegExp(r'\d+').stringMatch(bit) ?? '') ?? 0,
    ];
  }

  final left = parts(a);
  final right = parts(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  return 0;
}

bool isNewerVersion(String candidate, String current) =>
    compareVersions(candidate, current) > 0;

/// 按平台挑选更新包。
///
/// Windows 优先 `Setup xxx.exe` 安装版（支持 /S 静默安装），其次任意 exe，
/// 最后退回便携版 zip；Android 取 apk，优先通用包而不是分 ABI 包。
ReleaseAsset? selectUpdateAsset(ReleaseInfo release, UpdateTarget target) {
  bool endsWith(ReleaseAsset asset, String suffix) =>
      asset.name.toLowerCase().endsWith(suffix);

  if (target == UpdateTarget.android) {
    final apks = release.assets.where((a) => endsWith(a, '.apk')).toList();
    if (apks.isEmpty) return null;
    final universal = apks.where(
      (a) => !RegExp(
        'arm64|armeabi|x86|universal',
        caseSensitive: false,
      ).hasMatch(a.name),
    );
    return universal.isNotEmpty ? universal.first : apks.first;
  }

  final exes = release.assets.where((a) => endsWith(a, '.exe')).toList();
  final setup = exes.where((a) => a.name.toLowerCase().contains('setup'));
  if (setup.isNotEmpty) return setup.first;
  if (exes.isNotEmpty) return exes.first;
  final zips = release.assets.where((a) => endsWith(a, '.zip')).toList();
  return zips.isEmpty ? null : zips.first;
}

/// GitHub Releases 客户端。只依赖 dart:io，桌面与安卓共用。
class UpdateService {
  UpdateService({HttpClient? client})
    : _client =
          client ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 12));

  final HttpClient _client;
  static const _apiHost = 'https://api.github.com';

  Future<ReleaseInfo> fetchLatest(String repoUrl) async {
    final slug = parseRepoSlug(repoUrl);
    if (slug == null) {
      throw UpdateException('GitHub 仓库链接格式不正确，示例：$defaultRepoUrl');
    }

    final uri = Uri.parse('$_apiHost/repos/$slug/releases/latest');
    final HttpClientResponse response;
    final String body;
    try {
      final result = await _requestWithRetry(uri);
      response = result.$1;
      body = result.$2;
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw UpdateException(_networkMessage(e));
    }

    if (response.statusCode == 404) {
      throw UpdateException('仓库还没有发布 Release（$slug）');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw UpdateException(_rateLimitMessage(response));
    }
    if (response.statusCode != 200) {
      throw UpdateException('GitHub 返回 HTTP ${response.statusCode}');
    }

    final json = jsonDecode(body);
    if (json is! Map) throw UpdateException('Release 数据格式不正确');

    final tag = json['tag_name'] as String? ?? '';
    final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
    if (version.isEmpty) throw UpdateException('Release 缺少版本号');

    final rawAssets = json['assets'];
    final assets = <ReleaseAsset>[];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) continue;
        final name = item['name'];
        final url = item['browser_download_url'];
        if (name is! String || url is! String) continue;
        assets.add(
          ReleaseAsset(
            name: name,
            downloadUrl: url,
            size: (item['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }

    return ReleaseInfo(
      version: version,
      tagName: tag,
      notes: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      assets: assets,
      publishedAt: DateTime.tryParse('${json['published_at']}'),
    );
  }

  /// 请求 GitHub API：TLS 握手中断、连接重置这类瞬时故障自动重试一次。
  Future<(HttpClientResponse, String)> _requestWithRetry(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request = await _client.getUrl(uri);
        request.headers
          ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
          ..set(HttpHeaders.userAgentHeader, 'WeLearn-Assistant/$appVersion');
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        final body = await response.transform(utf8.decoder).join();
        return (response, body);
      } catch (e) {
        lastError = e;
        if (attempt == 0 && _isTransient(e)) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          continue;
        }
        throw UpdateException(_networkMessage(e));
      }
    }
    throw UpdateException(_networkMessage(lastError ?? '未知网络错误'));
  }

  /// 握手失败、连接被重置、超时都属于网络抖动，值得再试一次。
  bool _isTransient(Object error) =>
      error is HandshakeException ||
      error is SocketException ||
      error is TimeoutException ||
      error is HttpException;

  String _networkMessage(Object error) {
    if (error is HandshakeException) {
      return '与 GitHub 建立安全连接失败（TLS 握手被中断），请检查网络或代理后重试';
    }
    if (error is SocketException) return '无法连接 GitHub，请检查网络后重试';
    if (error is TimeoutException) return '连接 GitHub 超时，请稍后重试';
    return '连接 GitHub 失败：$error';
  }

  /// 403 / 429 的统一文案；能读到配额重置时间就把重试时刻写清楚。
  String _rateLimitMessage(HttpClientResponse response) {
    final resetSeconds = int.tryParse(
      response.headers.value('x-ratelimit-reset') ?? '',
    );
    if (resetSeconds != null && resetSeconds > 0) {
      final at = DateTime.fromMillisecondsSinceEpoch(
        resetSeconds * 1000,
        isUtc: true,
      ).toLocal();
      final hh = at.hour.toString().padLeft(2, '0');
      final mm = at.minute.toString().padLeft(2, '0');
      return 'GitHub API 请求次数已达上限，$hh:$mm 后可重试';
    }
    return 'GitHub API 请求过于频繁，请稍后再试';
  }

  /// 下载更新包到系统临时目录，同名文件已完整下载时直接复用。
  Future<File> downloadAsset(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/welearn-updates',
    );
    await dir.create(recursive: true);
    final name = asset.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$name');

    if (asset.size > 0 &&
        await file.exists() &&
        await file.length() == asset.size) {
      return file;
    }

    final HttpClientResponse response;
    try {
      final request = await _client.getUrl(Uri.parse(asset.downloadUrl));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'WeLearn-Assistant/$appVersion',
      );
      response = await request.close().timeout(const Duration(seconds: 60));
    } catch (e) {
      throw UpdateException(_networkMessage(e));
    }
    if (response.statusCode != 200) {
      throw UpdateException('下载更新包失败（HTTP ${response.statusCode}）');
    }

    final total = response.contentLength > 0
        ? response.contentLength
        : asset.size;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    return file;
  }
}
