import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 用户可见文案的标点:中文里**用全角**,别混半角。
///
/// 于是一条守卫:`lib/` 与 `test/` 里所有含中文的字符串字面量,凡紧贴中文的
/// `, ; ! ? : ( )` 都必须是全角。这条约定原先只在原型那边有个外部脚本
/// (`tool/fullwidth_punct.py` 的源头,`.tmp-shots/punctcheck.js`),应用这边
/// 漂了 70 处 —— 混用的样子在屏幕上很扎眼(「刷新音乐库后,全部歌曲…」)。
///
/// 不查的东西(它们长着同样的样子却不是文案):
///   - 代码注释;
///   - `${...}` 插值内部的标点(那是代码);
///   - 句号 `.` —— 文件名(`01 - 某艺人.flac`)、URL、小数都长这样。
void main() {
  const halfWidth = {',', ';', '!', '?', ':', '(', ')'};
  const fullWidth = {'，', '；', '！', '？', '：', '（', '）'};

  bool isHan(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.runes.first;
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }

  test('中文文案里不混半角标点', () {
    final offenders = <String>[];

    for (final dir in ['lib', 'test']) {
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in files) {
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].split('//').first;
          for (final body in stringLiterals(code)) {
            if (!body.runes.any((r) => isHan(String.fromCharCode(r)))) continue;
            final guarded = interpolationRanges(body);
            for (var k = 0; k < body.length; k++) {
              if (guarded.any((r) => k >= r.$1 && k < r.$2)) continue;
              final ch = body[k];
              if (!halfWidth.contains(ch)) continue;
              final prev = k > 0 ? body[k - 1] : '';
              final next = k + 1 < body.length ? body[k + 1] : '';
              if (!isHan(prev) && !isHan(next)) continue;
              offenders.add(
                '${file.path}:${i + 1}  '
                '"${ch}" → "${fullWidth.elementAt(halfWidth.toList().indexOf(ch))}"'
                '   …${body.substring(k < 16 ? 0 : k - 16, k + 16 > body.length ? body.length : k + 16)}…',
              );
            }
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '中文文案里的标点要用全角。批量改可以跑 '
          'tool/fullwidth_punct.py:\n${offenders.join('\n')}',
    );
  });
}

/// 一行代码里的字符串字面量正文(不含引号)。三引号、转义都认。
List<String> stringLiterals(String line) {
  final out = <String>[];
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    final raw = ch == 'r' && i + 1 < line.length && (line[i + 1] == "'" || line[i + 1] == '"');
    final quoteAt = raw ? i + 1 : i;
    if (line[quoteAt] != "'" && line[quoteAt] != '"') {
      i++;
      continue;
    }
    final q = line[quoteAt];
    final triple = line.length > quoteAt + 2 && line.substring(quoteAt, quoteAt + 3) == q * 3;
    final start = quoteAt + (triple ? 3 : 1);
    var j = start;
    while (j < line.length) {
      if (!raw && line[j] == r'\') {
        j += 2;
        continue;
      }
      if (triple) {
        if (line.length > j + 2 && line.substring(j, j + 3) == q * 3) break;
      } else if (line[j] == q) {
        break;
      }
      j++;
    }
    out.add(line.substring(start, j.clamp(start, line.length)));
    i = j + 1;
  }
  return out;
}

/// `$name` 与 `${…}`(含嵌套)在正文里的区间 —— 这些区段里的标点不是文案。
List<(int, int)> interpolationRanges(String body) {
  final ranges = <(int, int)>[];
  var i = 0;
  while (i < body.length) {
    if (body[i] != r'$') {
      i++;
      continue;
    }
    if (i + 1 < body.length && body[i + 1] == '{') {
      var depth = 0;
      var j = i + 1;
      while (j < body.length) {
        final ch = body[j];
        if (ch == "'" || ch == '"') {
          var k = j + 1;
          while (k < body.length && body[k] != ch) {
            if (body[k] == r'\') k++;
            k++;
          }
          j = k + 1;
          continue;
        }
        if (ch == '{') depth++;
        if (ch == '}') {
          depth--;
          if (depth == 0) break;
        }
        j++;
      }
      ranges.add((i, (j + 1).clamp(0, body.length)));
      i = j + 1;
      continue;
    }
    final m = RegExp(r'^[A-Za-z_0-9]+').firstMatch(body.substring(i + 1));
    if (m != null) {
      ranges.add((i, i + 1 + m.end));
      i += 1 + m.end;
      continue;
    }
    i++;
  }
  return ranges;
}