import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// 用保存的账号密码在后台完成登录，不打开任何界面。
///
/// 平台是 ASP.NET + IdentityServer：先 GET 登录入口（会重定向到 SSO 登录页），
/// 解析表单里的隐藏字段与账号 / 密码输入框，再按 action POST，跟随跳转并收集
/// Cookie。成功时返回完整的 Cookie 头，交给 [AppState.login] 复用现有会话逻辑。
///
/// 页面若由纯 JS 驱动（找不到表单）或需要验证码，返回 null，由用户手动登录。
class AutoLoginService {
  AutoLoginService({HttpClient? client})
    : _client =
          client ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 12));

  final HttpClient _client;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  Future<String?> login(String username, String password) async {
    if (username.isEmpty || password.isEmpty) return null;
    final cookies = <String, String>{};

    try {
      final first = await _request(
        Uri.parse('https://welearn.sflep.com/student/index.aspx'),
        cookies: cookies,
      );
      final form = findLoginForm(first.body);
      if (form == null) {
        // 没有登录表单：如果已有会话票据，说明入口本身还是登录态
        return _hasSession(cookies) ? _cookieHeader(cookies) : null;
      }

      final action = first.uri.resolve(
        form.action.isEmpty ? first.uri.toString() : form.action,
      );
      final fields = <String, String>{
        ...form.fields,
        form.userField: username,
        form.passField: password,
      };
      final posted = await _request(
        action,
        cookies: cookies,
        method: 'POST',
        body: fields,
      );

      if (_hasSession(cookies)) {
        final studentPage = _isStudentUrl(posted.uri);
        if (studentPage || posted.response.statusCode == 200) {
          return _cookieHeader(cookies);
        }
      }

      // 少数流程 POST 后先跳回入口，再跳学生主页：补一次 GET
      final follow = await _request(posted.uri, cookies: cookies);
      if (_hasSession(cookies) && _isStudentUrl(follow.uri)) {
        return _cookieHeader(cookies);
      }
      return null;
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
  }) async {
    var current = uri;
    var currentMethod = method;
    var currentBody = body;

    for (var hop = 0; hop < 6; hop++) {
      final request = await _client.openUrl(currentMethod, current);
      request.headers
        ..set(HttpHeaders.userAgentHeader, _ua)
        ..set(
          HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,application/xml;q=0.9',
        );
      if (cookies.isNotEmpty) {
        request.headers.set(
          HttpHeaders.cookieHeader,
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        );
      }
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

  bool _isStudentUrl(Uri uri) {
    if (uri.host != 'welearn.sflep.com') return false;
    final path = uri.path.toLowerCase();
    return path.startsWith('/student/') && !path.contains('prelogin');
  }

  String _cookieHeader(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// 从登录页 HTML 中找出可提交的表单：含密码框，且能找到账号输入框。
///
/// 登录页的字段名由服务端决定（`UserName`、`txtUser`、`loginName` 等都可能），
/// 因此不写死字段名，而是按 input 的 name/id 特征推断；隐藏字段（防伪 token）
/// 原样带回。找不到表单（纯 JS 登录或验证码）时返回 null。
LoginForm? findLoginForm(String html) {
  if (html.trim().isEmpty) return null;
  final doc = html_parser.parse(html);
  for (final form in doc.querySelectorAll('form')) {
    final password = form.querySelector('input[type=password]');
    if (password == null) continue;
    final passName = password.attributes['name'];
    if (passName == null || passName.isEmpty) continue;

    final inputs = form.querySelectorAll('input');
    Element? user;
    for (final input in inputs) {
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (type == 'password' ||
          type == 'hidden' ||
          type == 'submit' ||
          type == 'button' ||
          type == 'checkbox' ||
          type == 'radio') {
        continue;
      }
      final name = (input.attributes['name'] ?? input.attributes['id'] ?? '')
          .toLowerCase();
      if (type == 'email' ||
          name.contains('user') ||
          name.contains('account') ||
          name.contains('login') ||
          name.contains('mail')) {
        user = input;
        break;
      }
    }
    if (user == null) continue;
    final userName = user.attributes['name'] ?? user.attributes['id'];
    if (userName == null || userName.isEmpty) continue;

    final fields = <String, String>{};
    for (final input in inputs) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      if (name == passName || name == userName) continue;
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (type == 'submit' ||
          type == 'button' ||
          type == 'image' ||
          type == 'file') {
        continue;
      }
      fields[name] = input.attributes['value'] ?? '';
    }

    return LoginForm(
      action: form.attributes['action'] ?? '',
      userField: userName,
      passField: passName,
      fields: fields,
    );
  }
  return null;
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

class LoginForm {
  const LoginForm({
    required this.action,
    required this.userField,
    required this.passField,
    required this.fields,
  });

  final String action;
  final String userField;
  final String passField;
  final Map<String, String> fields;
}
