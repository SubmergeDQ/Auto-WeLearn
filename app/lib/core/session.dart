import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'errors.dart';

/// 唯一的网络出口。业务层不直接使用 HttpClient。
///
/// 与 CLI 版一致：手动处理重定向（要拿 SSO 每跳的 Location），逐跳吸收 Set-Cookie。
class SessionResponse {
  SessionResponse({
    required this.status,
    required this.url,
    required this.text,
    required this.redirects,
  });
  final int status;
  final String url;
  final String text;
  final List<String> redirects;
}

class Session {
  Session({
    required this.baseUrl,
    required this.userAgent,
    this.timeout = const Duration(seconds: 15),
  }) : _base = Uri.parse(baseUrl) {
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  final String baseUrl;
  final String userAgent;
  final Duration timeout;

  final Uri _base;
  final HttpClient _client = HttpClient();
  final Map<String, String> _cookies = {};

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  void setCookies(Map<String, String> values) => _cookies.addAll(values);

  void clearCookies() => _cookies.clear();

  Uri resolve(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Uri.parse(pathOrUrl);
    }
    if (pathOrUrl.startsWith('//')) return Uri.parse('https:$pathOrUrl');
    return _base.resolve(pathOrUrl);
  }

  String _cookieHeader(Uri uri) {
    // 只给主站带 Cookie；内容页在 centercourseware 另一个域名，不需要
    if (uri.host != _base.host) return '';
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<SessionResponse> request(
    String pathOrUrl, {
    String method = 'GET',
    Map<String, String>? form,
    String? referer,
    bool withOrigin = true,
    bool followRedirects = true,
    String? accept,
    Duration? requestTimeout,
  }) async {
    var uri = resolve(pathOrUrl);
    var currentMethod = method;
    var body = form == null ? null : Uri(queryParameters: form).query;
    final redirects = <String>[];
    final maxHops = followRedirects ? 10 : 0;

    for (var hop = 0; hop <= maxHops; hop++) {
      final response = await _send(
        uri,
        currentMethod,
        body,
        referer,
        withOrigin,
        accept,
        requestTimeout,
      );

      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        for (final cookie in response.cookies) {
          _cookies[cookie.name] = cookie.value;
        }
        await response.drain<void>().catchError((_) {});
        if (location == null) {
          throw AppException(
            AppErrorCode.contractChanged,
            '${response.statusCode} 重定向缺少 Location',
          );
        }
        final next = uri.resolve(location);
        redirects.add(next.toString());
        // 浏览器语义：302/303 之后 POST 降级为 GET
        if (currentMethod == 'POST' &&
            (response.statusCode == 302 || response.statusCode == 303)) {
          currentMethod = 'GET';
          body = null;
        }
        uri = next;
        continue;
      }

      final text = await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(timeout);

      if (response.statusCode >= 400) {
        final code = response.statusCode >= 500
            ? AppErrorCode.server
            : AppErrorCode.client;
        throw AppException(
          code,
          'HTTP ${response.statusCode}：${text.replaceAll(RegExp(r'\s+'), ' ').substring(0, text.length.clamp(0, 120))}',
          status: response.statusCode,
        );
      }

      return SessionResponse(
        status: response.statusCode,
        url: uri.toString(),
        text: text,
        redirects: redirects,
      );
    }

    throw AppException(AppErrorCode.contractChanged, '重定向次数超过上限');
  }

  Future<HttpClientResponse> _send(
    Uri uri,
    String method,
    String? body,
    String? referer,
    bool withOrigin,
    String? accept,
    Duration? requestTimeout,
  ) async {
    try {
      final request = await _client
          .openUrl(method, uri)
          .timeout(requestTimeout ?? timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        accept ??
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'zh-CN,zh;q=0.9,en;q=0.8',
      );
      if (referer != null) {
        request.headers.set(HttpHeaders.refererHeader, referer);
      }
      if (withOrigin) request.headers.set('Origin', baseUrl);
      final cookie = _cookieHeader(uri);
      if (cookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }

      if (body != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        request.write(body);
      }

      final response = await request.close().timeout(requestTimeout ?? timeout);
      for (final cookie in response.cookies) {
        _cookies[cookie.name] = cookie.value;
      }
      return response;
    } on TimeoutException {
      throw AppException(AppErrorCode.timeout, '请求超时');
    } on SocketException catch (e) {
      throw AppException(AppErrorCode.network, '网络连接失败：${e.message}', cause: e);
    } on HandshakeException catch (e) {
      throw AppException(
        AppErrorCode.network,
        'TLS 握手失败：${e.message}',
        cause: e,
      );
    }
  }

  Future<SessionResponse> get(
    String pathOrUrl, {
    String? referer,
    String? accept,
    Duration? requestTimeout,
  }) => request(
    pathOrUrl,
    referer: referer,
    accept: accept,
    requestTimeout: requestTimeout,
    followRedirects: true,
  );

  Future<SessionResponse> postForm(
    String pathOrUrl,
    Map<String, String> form, {
    String? referer,
    String? accept,
    Duration? requestTimeout,
  }) => request(
    pathOrUrl,
    method: 'POST',
    form: form,
    referer: referer,
    accept: accept,
    requestTimeout: requestTimeout,
  );

  /// 二进制资源（目前只有头像）。走同一个 HttpClient，带上同样的 Cookie / Referer，
  /// 不用 `Image.network` 是因为平台头像常需要登录态。失败返回 null，由界面回退占位。
  Future<Uint8List?> getBytes(
    String pathOrUrl, {
    String? referer,
    Duration? requestTimeout,
  }) async {
    try {
      final response = await _send(
        resolve(pathOrUrl),
        'GET',
        null,
        referer,
        true,
        'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        requestTimeout,
      );
      if (response.statusCode != 200) {
        await response.drain<void>().catchError((_) {});
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close(force: true);
}
