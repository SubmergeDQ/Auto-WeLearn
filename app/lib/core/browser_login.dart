/// 内置浏览器登录的纯逻辑部分：起始地址、登录成功的判定、Cookie 拼装。
///
/// 平台用 IdentityServer4 + PKCE，`state` 由服务端生成，脱离浏览器无法复现，
/// 所以这里不模拟登录流程，而是把真实登录页放进 WebView，让平台自己完成跳转，
/// 成功后只负责把 Cookie 取回来交给 [Api]。
library;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const welearnOrigin = 'https://welearn.sflep.com';

/// 直接进学生主页：已登录会停在主页，未登录会被平台跳到 prelogin → SSO。
const loginStartUrl = '$welearnOrigin/student/index.aspx';

/// 登录成功后才存在的路径。prelogin 与 SSO 的 /Account/Login 都要排除，
/// 否则在登录页上就会误判成功。
bool isLoggedInUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return false;
  if (uri.host != 'welearn.sflep.com') return false;

  final path = uri.path.toLowerCase();
  if (!path.startsWith('/student/')) return false;
  if (path.contains('prelogin')) return false;
  if (path.contains('/account/')) return false;
  return true;
}

/// 判断读到的 Cookie 是否够用。`.AspNet.Cookies` 是身份票据，
/// 只有 `acw_tc` 这类风控 Cookie 说明登录并未真正完成。
bool hasSessionCookie(Iterable<Cookie> cookies) {
  for (final c in cookies) {
    if (c.name == '.AspNet.Cookies' && c.value.trim().isNotEmpty) return true;
  }
  return false;
}

/// 拼成 `a=1; b=2` 形式，供 [parseCookieInput] 复用。
String buildCookieHeader(Iterable<Cookie> cookies) {
  final parts = <String>[];
  for (final c in cookies) {
    if (c.name.trim().isEmpty) continue;
    parts.add('${c.name}=${c.value}');
  }
  return parts.join('; ');
}

/// 只保留与本平台相关的 Cookie，避免把其它域的票据一起写进请求。
List<Cookie> relevantCookies(Iterable<Cookie> cookies) {
  return cookies.where((c) {
    final domain = (c.domain ?? '').toLowerCase();
    if (domain.isEmpty) return true;
    return domain.contains('sflep.com');
  }).toList();
}

/// 清空内置浏览器留下的 Cookie、缓存与本地存储。
///
/// 登录态失效后旧 Cookie 仍留在 WebView 里：打开登录页时平台会直接跳到
/// `/student/`，被误判成「已登录」并立刻关闭页面（表现为内置浏览器闪退）。
/// 打开登录页前和强制清除凭据时都调用这里。
Future<void> clearBrowserSession() async {
  try {
    await CookieManager.instance().deleteAllCookies();
  } catch (_) {
    // 桌面端 WebView2 的 Cookie 清理失败不影响账号 Cookie 已清空
  }
  try {
    await WebStorageManager.instance().deleteAllData();
  } catch (_) {
    // 仅 Android / iOS 支持；Windows 忽略
  }
  try {
    await InAppWebViewController.clearAllCache();
  } catch (_) {
    // 缓存清理失败不阻塞登录流程
  }
}
