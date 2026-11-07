import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/browser_login.dart';
import '../theme.dart';

/// 内置浏览器登录页。
///
/// 打开真实的平台登录页，用户在页面内输入账号密码；平台自己完成 PKCE 跳转，
/// 这里只在 URL 落到 `/student/` 之后把 Cookie 读出来，作为结果返回。
/// 返回 `null` 表示用户取消。
class LoginWebPage extends StatefulWidget {
  const LoginWebPage({super.key});

  @override
  State<LoginWebPage> createState() => _LoginWebPageState();
}

class _LoginWebPageState extends State<LoginWebPage> {
  InAppWebViewController? _controller;
  Timer? _poll;

  bool _loading = true;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 有些平台的 URL 变化事件不保证触发（重定向链、SPA 路由），补一个轮询兜底。
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_finishing) return;
    final controller = _controller;
    if (controller == null) return;

    final url = await controller.getUrl();
    if (url == null) return;
    if (!isLoggedInUrl(url.toString())) return;

    _finishing = true;
    _poll?.cancel();
    if (mounted) setState(() => _loading = true);

    try {
      final all = await CookieManager.instance().getCookies(
        url: WebUri(welearnOrigin),
        webViewController: controller,
      );
      final cookies = relevantCookies(all);
      if (!hasSessionCookie(cookies)) {
        // 已跳到主页但票据还没落盘，退回等待，不要直接报错。
        _finishing = false;
        _poll = Timer.periodic(
          const Duration(milliseconds: 1200),
          (_) => _check(),
        );
        return;
      }
      final header = buildCookieHeader(cookies);
      if (mounted) Navigator.of(context).pop(header);
    } catch (e) {
      _finishing = false;
      if (mounted) {
        setState(() {
          _error = '读取登录信息失败：$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: Tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              compact: compact,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 24,
                  compact ? 8 : 12,
                  compact ? 12 : 24,
                  0,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radiusCard),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Tokens.surface,
                      border: Border.all(color: Tokens.border),
                      borderRadius: BorderRadius.circular(Tokens.radiusCard),
                    ),
                    child: Stack(
                      children: [
                        InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri(loginStartUrl),
                          ),
                          initialSettings: InAppWebViewSettings(
                            javaScriptEnabled: true,
                            supportZoom: true,
                            mediaPlaybackRequiresUserGesture: true,
                            useShouldOverrideUrlLoading: false,
                          ),
                          onWebViewCreated: (controller) {
                            _controller = controller;
                          },
                          onLoadStart: (_, _) {
                            if (!mounted) return;
                            setState(() => _loading = true);
                          },
                          onLoadStop: (_, _) {
                            if (!mounted) return;
                            setState(() => _loading = false);
                            _check();
                          },
                          onUpdateVisitedHistory: (_, _, _) => _check(),
                          onReceivedError: (_, _, error) {
                            if (!mounted) return;
                            setState(() {
                              _loading = false;
                              _error = '页面加载失败：${error.description}';
                            });
                          },
                        ),
                        if (_loading)
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              color: Tokens.accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _Footer(
              compact: compact,
              status: _statusText(),
              error: _error,
              onCancel: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText() {
    if (_error != null) return '没能自动读取登录状态';
    if (_finishing) return '已登录，正在读取登录信息…';
    if (_loading) return '正在加载登录页…';
    return '在页面里完成登录后会自动返回';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.compact, required this.onClose});

  final bool compact;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 56 : 64,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(bottom: BorderSide(color: Tokens.border)),
      ),
      child: Row(
        children: [
          _CloseButton(onTap: onClose),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '登录 WE Learn',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '使用平台账号登录，登录信息只保存在本机',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Tokens.textTertiary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '关闭',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: SizedBox(
          width: Tokens.controlHeight,
          height: Tokens.controlHeight,
          child: const Icon(
            Icons.close_rounded,
            size: 18,
            color: Tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.compact,
    required this.status,
    required this.error,
    required this.onCancel,
  });

  final bool compact;
  final String status;
  final String? error;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 24,
        12,
        compact ? 16 : 24,
        14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: error == null ? Tokens.textSecondary : Tokens.danger,
                    height: 1.4,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Tokens.textTertiary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: Tokens.tapMin,
            child: TextButton(onPressed: onCancel, child: const Text('取消')),
          ),
        ],
      ),
    );
  }
}
