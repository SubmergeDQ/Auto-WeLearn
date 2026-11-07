import 'package:flutter/material.dart';

/// 设计变量。取值与 docs/GUI_DESIGN.md 一一对应。
class Tokens {
  static const canvas = Color(0xFFF5F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFFAFBFC);
  static const border = Color(0xFFE6E8EC);
  static const borderStrong = Color(0xFFD6DAE0);

  static const textPrimary = Color(0xFF1A1D21);
  static const textSecondary = Color(0xFF5B6470);
  static const textTertiary = Color(0xFF8A919C);

  static const accent = Color(0xFF0F766E);
  static const accentSoft = Color(0xFFE6F2F1);

  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFEAF5EE);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFDF3E7);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFBEDED);
  static const muted = Color(0xFF6B7280);
  static const mutedSoft = Color(0xFFF0F1F3);

  static const radiusControl = 6.0;
  static const radiusCard = 10.0;

  /// 顶栏/工具栏内所有控件（状态胶囊、图标按钮、按钮）的统一高度。
  /// 三者高度不一致时，即使 Row 居中也会显得参差。
  static const controlHeight = 32.0;

  // ── 移动端专用 ────────────────────────────────────────
  /// 手机最小触控高度（Material 建议 44–48）
  static const tapMin = 44.0;

  /// 两行文本的队列行高
  static const mobileRowHeight = 64.0;

  /// 运行卡展开高度（折叠态 44）
  static const runCardHeight = 108.0;

  static const gap4 = 4.0;
  static const gap8 = 8.0;
  static const gap12 = 12.0;
  static const gap16 = 16.0;
  static const gap24 = 24.0;

  static const fontFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans SC',
  ];

  static const mono = 'Consolas';
}

/// 等宽数字：倒计时、时长、计数都用它，避免数字跳动
const tabular = [FontFeature.tabularFigures()];

TextStyle monoStyle({
  double size = 12,
  FontWeight weight = FontWeight.w500,
  Color color = Tokens.textSecondary,
}) => TextStyle(
  fontFamily: Tokens.mono,
  fontFamilyFallback: const ['Roboto Mono', 'Menlo'],
  fontSize: size,
  fontWeight: weight,
  color: color,
  fontFeatures: tabular,
  letterSpacing: 0.2,
);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Tokens.canvas,
    splashFactory: InkSparkle.splashFactory,
    // 关键：桌面平台默认用 VisualDensity.compact，会把每个按钮压矮 8px
    // （32 的工具栏按钮变 24、输入框内文偏上），和固定高度的胶囊/图标按钮对不齐。
    // 这里统一成 standard，所有控件按代码写的尺寸渲染。
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: Tokens.accent,
      surface: Tokens.surface,
      onSurface: Tokens.textPrimary,
      outline: Tokens.border,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Segoe UI',
      fontFamilyFallback: Tokens.fontFallback,
      bodyColor: Tokens.textPrimary,
      displayColor: Tokens.textPrimary,
    ),
    dividerTheme: const DividerThemeData(
      color: Tokens.border,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF23272E),
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Tokens.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Tokens.textPrimary,
        side: const BorderSide(color: Tokens.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Tokens.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: const TextStyle(color: Tokens.textTertiary, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        borderSide: const BorderSide(color: Tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        borderSide: const BorderSide(color: Tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        borderSide: const BorderSide(color: Tokens.accent, width: 1.4),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.all(const Color(0xFFC9CED6)),
    ),
  );
}

/// 工具栏小型填充按钮：固定 32 高，与图标按钮、状态胶囊对齐。
ButtonStyle toolbarFilled() => FilledButton.styleFrom(
  minimumSize: const Size(0, Tokens.controlHeight),
  padding: const EdgeInsets.symmetric(horizontal: 14),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
);

/// 工具栏小型描边按钮，与 [toolbarFilled] 同高。
ButtonStyle toolbarOutlined() => OutlinedButton.styleFrom(
  minimumSize: const Size(0, Tokens.controlHeight),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
);
