/// 错误码与异常。与 CLI 版 `src/core/errors.ts` 语义一致。
library;

import 'dart:async';
import 'dart:io';

enum AppErrorCode {
  network('NETWORK_ERROR'),
  timeout('TIMEOUT'),
  server('SERVER_ERROR'),
  client('CLIENT_ERROR'),
  authExpired('AUTH_EXPIRED'),
  contractChanged('CONTRACT_CHANGED'),
  noTemplate('NO_TEMPLATE'),
  heartbeatFailed('HEARTBEAT_FAILED'),
  interrupted('INTERRUPTED'),
  config('CONFIG_ERROR'),
  badCredentials('BAD_CREDENTIALS'),
  platformRejected('PLATFORM_REJECTED'),
  parseWarning('PARSE_WARNING'),
  unknown('UNKNOWN');

  const AppErrorCode(this.code);
  final String code;

  bool get retryable =>
      this == AppErrorCode.network || this == AppErrorCode.timeout || this == AppErrorCode.server;
}

class AppException implements Exception {
  AppException(this.code, this.message, {this.status, this.cause});
  final AppErrorCode code;
  final String message;
  final int? status;
  final Object? cause;

  bool get isInterrupted => code == AppErrorCode.interrupted;
  bool get isAuthExpired => code == AppErrorCode.authExpired;

  @override
  String toString() => '${code.code}: $message';
}

/// 把任意异常归一化，便于统一判定
AppException toAppException(Object error, [AppErrorCode fallback = AppErrorCode.unknown]) {
  if (error is AppException) return error;
  if (error is TimeoutException) {
    return AppException(AppErrorCode.timeout, '请求超时（超过设定的单请求时长）');
  }
  if (error is SocketException) {
    return AppException(AppErrorCode.network, '网络连接失败：${error.message}', cause: error);
  }
  return AppException(fallback, error.toString(), cause: error);
}
