/// 更新说明的极简 Markdown 解析。
///
/// GitHub Release 正文是 Markdown，直接塞进 Text 会露出 `##`、`-`、`|`
/// 这类标记。这里只处理更新说明里实际出现的语法：标题、列表、
/// 简单表格与常见行内标记，解析成可排版的块，避免引入完整的
/// Markdown 依赖。
enum NoteBlockType { heading, bullet, paragraph }

class NoteBlock {
  const NoteBlock(this.type, this.text, {this.level = 1});

  final NoteBlockType type;
  final String text;

  /// 标题层级（`#` 的个数），非标题恒为 1。
  final int level;
}

/// 解析 Release 正文为依次排版的块。
List<NoteBlock> parseReleaseNotes(String source) {
  final lines = source.split('\n');
  final blocks = <NoteBlock>[];
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trim();
    if (raw.isEmpty || raw.startsWith('```')) continue;
    // 表格分隔行与 Markdown 分隔线没有内容，跳过
    if (RegExp(r'^[\s|:-]+$').hasMatch(raw) && raw.contains('-')) continue;

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(raw);
    if (heading != null) {
      blocks.add(
        NoteBlock(
          NoteBlockType.heading,
          _stripInline(heading.group(2)!),
          level: heading.group(1)!.length,
        ),
      );
      continue;
    }

    if (raw.startsWith('|')) {
      // 紧跟着分隔行的那一行是表头，不单独显示；
      // 数据行拼成 "列一 · 列二 · 列三"，窄屏上自然折行。
      if (i + 1 < lines.length &&
          RegExp(r'^[\s|:-]+$').hasMatch(lines[i + 1].trim())) {
        continue;
      }
      final cells = _tableCells(raw);
      if (cells.isNotEmpty) {
        blocks.add(
          NoteBlock(NoteBlockType.paragraph, cells.join(' · ')),
        );
      }
      continue;
    }

    final bullet = RegExp(r'^(?:[-*+]|\d+\.)\s+(.*)$').firstMatch(raw);
    if (bullet != null) {
      blocks.add(NoteBlock(NoteBlockType.bullet, _stripInline(bullet.group(1)!)));
      continue;
    }

    blocks.add(NoteBlock(NoteBlockType.paragraph, _stripInline(raw)));
  }
  return blocks;
}

/// 去掉行内的链接、粗体、反引号等标记，只保留可读文字。
String _stripInline(String text) {
  return text
      .replaceAllMapped(
        RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll('**', '')
      .replaceAll('`', '')
      .replaceAll('~~', '')
      .trim();
}

/// 拆分 `| a | b | c |` 形式的表格行。
List<String> _tableCells(String line) {
  final parts = line.split('|').map((cell) => _stripInline(cell.trim())).toList();
  // 首尾通常是空串，去掉
  if (parts.isNotEmpty && parts.first.isEmpty) parts.removeAt(0);
  if (parts.isNotEmpty && parts.last.isEmpty) parts.removeAt(parts.length - 1);
  return parts.where((cell) => cell.isNotEmpty).toList();
}
