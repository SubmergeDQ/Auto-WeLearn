import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WeLearnApp());
}

class WeLearnApp extends StatefulWidget {
  const WeLearnApp({super.key});

  @override
  State<WeLearnApp> createState() => _WeLearnAppState();
}

class _WeLearnAppState extends State<WeLearnApp> {
  final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'WeLearn 助手',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const WorkbenchShell(),
      ),
    );
  }
}
