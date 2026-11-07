import 'package:flutter/material.dart';

import '../app_state.dart';

/// 通过 InheritedNotifier 分发状态，避免引入额外状态管理依赖
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未挂载');
    return scope!.notifier!;
  }
}
