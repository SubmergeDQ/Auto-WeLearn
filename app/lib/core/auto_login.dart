import 'dart:convert';
import 'dart:io';

/// 用保存的账号密码在后台完成登录，不打开任何界面。
///
/// 平台的登录入口是 JS 驱动的 SSO 页面，纯表单解析拿不到可提交的地址；
/// 但页面本身调用的是服务端接口 `POST /idsvr/account/login`，请求体只有
/// 账号、密码（前端编码后）与回跳地址。这里复刻这个请求，成功后跟随
/// 回跳地址拿到 `.AspNet.Cookies`，交给 [AppState.login] 复用会话逻辑。
///
/// 需要图形验证码或短信二次验证时返回 null，由用户手动登录。
class AutoLoginService {
  AutoLoginService({HttpClient? client})
    : _client =
          client ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 12));

  final HttpClient _client;

  static const _loginEndpoint = 'https://sso.sflep.com/idsvr/account/login';
  static const _redirectUrl = 'http://welearn.sflep.com/user/loginredirect.aspx';

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// 登录成功返回 Cookie 头；需要验证码、账号密码错误或网络异常时返回 null。
  Future<String?> login(String username, String password) async {
    if (username.isEmpty || password.isEmpty) return null;
    final cookies = <String, String>{};

    try {
      final encoded = encodeLoginPassword(password);
      final posted = await _request(
        Uri.parse(_loginEndpoint),
        cookies: cookies,
        method: 'POST',
        body: {
          'account': username,
          'pwd': encoded.pwd,
          'ts': '${encoded.timestamp}',
          'rturl': _redirectUrl,
        },
        headers: const {
          'origin': 'https://sso.sflep.com',
          'referer': 'https://sso.sflep.com/idsvr/login.html',
        },
      );

      final decoded = jsonDecode(posted.body);
      if (decoded is! Map) return null;
      // code 100 = 触发图形验证码，其余非 0 也表示登录未通过
      if (decoded['code'] != 0) return null;

      // 风控账号会要求短信二次验证，无法在后台完成
      final extra = decoded['extraCheck'];
      if (extra is Map && extra['vcToken'] != null) return null;

      final target = decoded['data'];
      if (target is! String || target.isEmpty) return null;

      // data 通常是绝对回跳地址；相对路径按 SSO 站根解析
      final next = target.contains('://')
          ? Uri.parse(target)
          : Uri.parse('https://sso.sflep.com/idsvr/').resolve(target);
      await _request(next, cookies: cookies);

      if (!_hasSession(cookies)) return null;
      return _cookieHeader(cookies);
    } catch (_) {
      return null;
    } finally {
      _client.close(force: true);
    }
  }

  Future<_HttpResult> _request(
    Uri uri, {
    required Map<String, String> cookies,
    String method = 'GET',
    Map<String, String>? body,
    Map<String, String>? headers,
  }) async {
    var current = uri;
    var currentMethod = method;
    var currentBody = body;
    var currentHeaders = headers;

    for (var hop = 0; hop < 8; hop++) {
      final request = await _client.openUrl(currentMethod, current);
      request.headers
        ..set(HttpHeaders.userAgentHeader, _ua)
        ..set(
          HttpHeaders.acceptHeader,
          'text/html,application/json,application/xhtml+xml,'
          'application/xml;q=0.9',
        );
      if (cookies.isNotEmpty) {
        request.headers.set(
          HttpHeaders.cookieHeader,
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        );
      }
      currentHeaders?.forEach(request.headers.set);
      if (currentBody != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(
          currentBody.entries
              .map(
                (e) =>
                    '${Uri.encodeQueryComponent(e.key)}='
                    '${Uri.encodeQueryComponent(e.value)}',
              )
              .join('&'),
        );
      }

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      for (final cookie in response.cookies) {
        cookies[cookie.name] = cookie.value;
      }
      final text = await response.transform(utf8.decoder).join();

      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location != null && location.isNotEmpty) {
          current = current.resolve(location);
          currentMethod = 'GET';
          currentBody = null;
          // Origin / Referer 只对第一跳的接口请求有意义
          currentHeaders = null;
          continue;
        }
      }
      return _HttpResult(response: response, body: text, uri: current);
    }
    throw const SocketException('重定向次数过多');
  }

  bool _hasSession(Map<String, String> cookies) {
    for (final entry in cookies.entries) {
      if (entry.key.toLowerCase() == '.aspnet.cookies' &&
          entry.value.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String _cookieHeader(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// 平台登录接口需要的密码编码结果。
class LoginPassword {
  const LoginPassword({required this.pwd, required this.timestamp});

  /// 提交给服务端的 `pwd` 字段（base64）。
  final String pwd;

  /// 提交给服务端的 `ts` 字段（毫秒时间戳 + 密码校验位）。
  final int timestamp;
}

/// 复刻平台登录页的前端编码：`base64("<ts>*<密码 UTF-8 字节的 hex>")`。
///
/// 时间戳的低两位由密码字节异或算出，服务端据此判断请求未被篡改；
/// [now] 仅用于测试固定时间。
LoginPassword encodeLoginPassword(String password, {DateTime? now}) {
  final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
  // JS 的位移按 32 位有符号整数计算，这里做同样的截断
  var t32 = ms & 0xFFFFFFFF;
  if (t32 >= 0x80000000) t32 -= 0x100000000;
  var hash = (t32 >> 16) & 255;
  final bytes = utf8.encode(password);
  for (final b in bytes) {
    hash ^= b;
  }
  final check = hash % 100;
  final timestamp = (ms ~/ 100) * 100 + check;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return LoginPassword(
    pwd: base64Encode(utf8.encode('$timestamp*$hex')),
    timestamp: timestamp,
  );
}

class _HttpResult {
  const _HttpResult({
    required this.response,
    required this.body,
    required this.uri,
  });

  final HttpClientResponse response;
  final String body;
  final Uri uri;
}
