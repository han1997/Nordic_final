import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **原型 ↔ 应用的对账:有没有「应用做了、原型没跟上」的屏 / 面板**
/// (第三十八轮立)。
///
/// `test/ui/proto_sync_test.dart` 对的是**几何**(某个选择器的数与应用渲染出的数),
/// 它假定两边都有那件东西。这一条对的是**存在性**,专抓另一种漂移:
///
///   > 应用新增了一屏或一张纸,原型里压根没有 —— 于是「唯一的设计真相来源」
///   > 少了一块,而没有任何人会发现。
///
/// 这不是假设出来的风险。第三十八轮开工时实测到的就是 4 处:
///
/// | 应用 | 原型当时 |
/// |---|---|
/// | `playlist_screen.dart`(歌单详情) | **完全没有** |
/// | `playlist_picker_sheet.dart`(加入歌单) | **完全没有** |
/// | `sort_sheet.dart` / `cache_sheet.dart` / `song_info_sheet.dart` | 函数写了,`BOARD` 里**一格都没有** |
///
/// 后三处比「没写」更糟:stage 里点得到、设计板上看不见,下次改的时候没有对照基准。
///
/// 判据只看**名字**与**调用关系**,不看长相 —— 长相归 `proto_sync_test` 管。
void main() {
  final js = File('prototype/app.js').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  /// `lib/ui/screens/*.dart` 的文件名,去掉 `_screen` / `_sheet` / `_picker_sheet`。
  List<String> stems({required bool sheets}) {
    final files = Directory('lib/ui/screens')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.dart'));
    return [
      for (final name in files)
        if (_isSheet(name) == sheets)
          // **只剥自己那一层后缀**:`playlist_picker_sheet.dart` 要剩下
          // `playlist_picker`(→ sheetPlaylistPicker),连 `_picker` 一起剥掉
          // 会与 `playlist_screen.dart` 撞成同一个名字。
          name.replaceAll(sheets ? '_sheet.dart' : '_screen.dart', ''),
    ]..sort();
  }

  /// `snake_case` → `CamelCase`(目录里只有小写与下划线)。
  String camel(String snake) => snake
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();

  /// **例外表:文件名对不上函数名的那几个。**
  ///
  /// 每条都得写清为什么 —— 加一条新例外就是给漂移开了个口子,要么改名,
  /// 要么在这里说明这一处为什么不能改。
  const exceptions = {
    // 原型里那张纸叫「队列接续」,函数名从一开始就是 sheetResume ——
    // 它的标题是「接着上次听?」,叫 resume 比叫 queueRestore 更贴。
    'queue_restore': 'sheetResume',
    // 导出配置 —— 原型把一个单词写成 camelCase(sheetExportConfig),
    // 文件名是两个词。
    'config_export': 'sheetExportConfig',
    // 歌曲的「⋯」菜单:原型里它要服务歌曲 / 专辑 / 艺人 / 歌单四种来源
    // (见 sheetMenu 的 forWhat),所以不叫 sheetSongMenu。
    'song_menu': 'sheetMenu',
  };

  /// 原型里那个函数该叫什么。
  String protoName(String stem, {required bool sheet}) {
    final hit = exceptions[stem];
    if (hit != null) return hit;
    return (sheet ? 'sheet' : 'screen') + camel(stem);
  }

  bool definedInPrototype(String fn) =>
      RegExp('function $fn\\(').hasMatch(js);

  /// `BOARD` 那一段(设计板的格表)。
  final board = js.substring(
    js.indexOf('const BOARD = ['),
    js.indexOf('function boardFrames'),
  );

  /// `VIEWS` 那一段(可点击原型的路由表)—— 从表头到设计板那一段之前。
  /// 边界用 `BOARD` 的表头而不是注释:**这个文件是 CRLF**,写 `\n` 会找不到。
  final views = js.substring(
    js.indexOf('const VIEWS = {'),
    js.indexOf('const BOARD = ['),
  );

  group('每一屏 / 每一张纸，原型里都有', () {
    test('应用里的页面在原型里都有同名函数', () {
      final missing = <String>[];
      for (final stem in stems(sheets: false)) {
        final fn = protoName(stem, sheet: false);
        if (!definedInPrototype(fn)) missing.add('$stem.dart → $fn()');
      }
      expect(missing, isEmpty,
          reason: '这些页面应用里有、原型里没有 —— 先补原型（README「界面改动一律先改原型」):\n'
              '${missing.join('\n')}');
    });

    test('应用里的面板在原型里都有同名函数', () {
      final missing = <String>[];
      for (final stem in stems(sheets: true)) {
        final fn = protoName(stem, sheet: true);
        if (!definedInPrototype(fn)) missing.add('$stem.dart → $fn()');
      }
      expect(missing, isEmpty,
          reason: '这些面板应用里有、原型里没有：\n${missing.join('\n')}');
    });
  });

  group('设计板铺得出它们', () {
    test('每张面板在设计板上都有一格', () {
      final missing = [
        for (final stem in stems(sheets: true))
          if (!board.contains('${protoName(stem, sheet: true)}()')) stem,
      ];
      expect(missing, isEmpty,
          reason: '这些面板写了函数却没进 BOARD —— '
              'stage 里点得到、设计板上看不见，等于没人能对照：\n${missing.join('\n')}');
    });

    test('每个页面在设计板上都至少有一格', () {
      // 设计板不必逐屏对应(它铺的是状态与形态组合),但一屏都不铺的那一屏
      // 就是「只在交互里活着」—— 深 / 浅两套并排看材质时它永远缺席。
      final missing = [
        for (final stem in stems(sheets: false))
          if (!board.contains('${protoName(stem, sheet: false)}(')) stem,
      ];
      expect(missing, isEmpty,
          reason: '这些页面在设计板上没有一格：\n${missing.join('\n')}');
    });
  });

  group('可点击原型走得进去', () {
    test('每个页面都在 VIEWS 里有一个入口', () {
      final missing = [
        for (final stem in stems(sheets: false))
          if (!views.contains('${protoName(stem, sheet: false)}(')) stem,
      ];
      expect(missing, isEmpty,
          reason: '这些页面没有路由 —— 设计板上有、点不进去，或者压根到不了：\n'
              '${missing.join('\n')}');
    });

    test('歌单详情：路由在、行也点得着', () {
      // 这一条单独钉,因为第三十八轮之前它就是那个样子:库里列着四张歌单,
      // 每一行都是死行(没有 data-*),视图表里也没有 playlist。
      expect(views, contains('screenPlaylist('));
      expect(js, contains('data-playlist="\${p.id}"'),
          reason: '歌单行要挂 data-playlist，不然点不动');
      expect(js, contains('if (d.playlist)'),
          reason: '点击分发里要有 data-playlist 这一支');
    });

    test('「加入歌单」从歌曲菜单进得去', () {
      expect(js, contains("'sheet:playlistPicker'"),
          reason: '歌曲「⋯」菜单里那条要指向这张纸');
      expect(js, contains('playlistPicker: sheetPlaylistPicker'),
          reason: 'sheets 注册表里要有它，否则 withOverlay 铺不出来');
    });
  });

  group('菜单项逐条对得上', () {
    /// 从一段源码里抠出「菜单项文案」。
    ///
    /// **三元要两条都收**:`starred ? '取消收藏' : '收藏这首歌'` 是同一个位置的
    /// 两种状态,不是两条菜单项。只认 `label: '...'` 那种写法会把两边同时漏掉
    /// ——漏掉之后差集是空的,**用例会假装通过**。所以这里抓的是「含中文的引号串」,
    /// 一条菜单项里的每一支都进来。
    Set<String> textsIn(String src, {required Pattern itemStart}) {
      final out = <String>{};
      // `itemStart` 可以是字符串,也可以是正则 —— 原型那边的条目以 `[faved ? ...`
      // 开头(图标跟着状态换),按 `['` 切会把它们整条丢掉。
      final chunks = src.split(itemStart).skip(1);
      for (final chunk in chunks) {
        // 一条菜单项截到 `onTap:`(应用)/ `','目标'`(原型)—— 只取文案那一段。
        final body = chunk.length > 400 ? chunk.substring(0, 400) : chunk;
        for (final m in RegExp(r"[`']([^`'\n]*[\u4e00-\u9fa5][^`'\n]*)[`']")
            .allMatches(body)) {
          out.add(m.group(1)!.replaceAll(RegExp(r"\$\{[^}]*\}"), '*'));
        }
      }
      return out;
    }

    /// 应用侧:`NordicMenuRow(...)`。
    Set<String> appLabels(String file, {String? inBlock}) {
      var src = File('lib/ui/screens/$file').readAsStringSync();
      if (inBlock != null) {
        final at = src.indexOf(inBlock);
        expect(at, greaterThanOrEqualTo(0), reason: '找不到 `$inBlock`');
        src = src.substring(at);
      }
      return textsIn(src, itemStart: 'NordicMenuRow(');
    }

    /// 原型侧:`items = [['icon', '文案', '目标'], ...]`。
    ///
    /// [only] 给 `sheetMenu` 这种**一个函数服务多种来源**的地方:
    /// 它按 `forWhat` 分四支(歌曲 / 专辑 / 艺人 / 歌单),四支的条目完全不同。
    Set<String> protoLabels(String functionName, {String? only}) {
      final at = js.indexOf('function $functionName(');
      expect(at, greaterThanOrEqualTo(0), reason: '原型里没有 $functionName');
      final rest = js.substring(at);
      final end = rest.indexOf('\nfunction ', 1);
      var body = end > 0 ? rest.substring(0, end) : rest;
      if (only != null) {
        final from = body.indexOf(only);
        expect(from, greaterThanOrEqualTo(0),
            reason: '$functionName 里找不到分支 `$only`');
        final tail = body.substring(from);
        final next = tail.indexOf('} else if (forWhat');
        body = next > 0 ? tail.substring(0, next) : tail;
      }
      final items = body.indexOf('items = [');
      if (items > 0) body = body.substring(items);
      // 条目缩进六格:`      ['icon', '文案', '目标'],`。
      return textsIn(body, itemStart: RegExp(r'\n\s{6}\['));
    }

    test('歌曲「⋯」菜单', () {
      final app = appLabels('song_menu_sheet.dart');
      final proto = protoLabels('sheetMenu', only: "forWhat === 'song'");

      // **只在这一屏出现的那一条**,两边天然对不上:
      // 「从这个歌单移除」由 `onRemoveFromPlaylist` 传不传决定,而它是歌单页
      // (playlist_screen)才给的上下文项。原型的设计板上没有「歌单里按位置移除」
      // 那一格,所以不在这一条的比较范围 —— 记在这儿,不是悄悄放过。
      app.remove('从这个歌单移除');

      expect(app.difference(proto), isEmpty,
          reason: '这些菜单项应用里有、原型没有 —— 补进 sheetMenu 的 items');
      expect(proto.difference(app), isEmpty,
          reason: '这些菜单项原型里有、应用没有 —— 要么实现，要么从原型撤掉');
    });

    test('歌曲信息底部的两条去路', () {
      final app = appLabels('song_info_sheet.dart', inBlock: '两处去路');
      final proto = {
        for (final m in RegExp(r'<span>([^<]+)</span>')
            .allMatches(js.substring(
              js.indexOf('function sheetSongInfo('),
              js.indexOf('function scanLine('),
            )))
          m.group(1)!,
      };
      expect(app, {'查看专辑', '查看艺人'});
      expect(proto.containsAll(app), isTrue,
          reason: '歌曲信息底部那两条去路，原型要摆出同样的两条');
    });
  });

  group('两个入口除了该差的那几行，逐行相同', () {
    /// `player.html` 与 `index.html` 共用同一份 `app.js` / `styles.css`,
    /// 差别只有三处:**标题**、**`data-mode`**、以及各自那句注释。
    ///
    /// 这一条挡的是「改了一个入口、忘了另一个」—— 比它看起来常见:引一个新
    /// script、加一个 meta、改一次 favicon 的插法,都只会在其中一页上做。
    /// 两份 head 一旦分叉,`index.html` 打开时能看见的东西就和交互流不一样了,
    /// 而**没有任何人会发现**(它们长得都像「那个只差一个 mode 的文件」)。
    List<String> normalized(String file) => File('prototype/$file')
        .readAsStringSync()
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .map((line) => line
            // 标题:设计板 / 可点击原型,各自的名字。
            .replaceAll(RegExp(r'<title>[^<]*</title>'), '<title>')
            // mode:board / stage,这是两个文件存在的唯一理由。
            .replaceAll(RegExp(r'data-mode="[^"]*"'), 'data-mode=""'))
        // 两边各有一句说明「这是什么」的注释,内容本就该不同 —— 整行去掉。
        .where((line) => !line.startsWith('<!--'))
        .toList();

    test('player.html 与 index.html 除标题 / mode / 注释外逐行一致', () {
      final stage = normalized('player.html');
      final board = normalized('index.html');

      final onlyStage = stage.where((l) => !board.contains(l)).toList();
      final onlyBoard = board.where((l) => !stage.contains(l)).toList();

      expect(onlyStage, isEmpty,
          reason: '这几行只在 player.html 里有 —— 原型改动要包括 index.html:\n'
              '${onlyStage.join('\n')}');
      expect(onlyBoard, isEmpty,
          reason: '这几行只在 index.html 里有 —— 另一页也要跟上：\n'
              '${onlyBoard.join('\n')}');
      expect(stage.length, board.length, reason: '两页行数该一样');
    });

    test('index.html 确实是板模式，player.html 是舞台模式', () {
      // 上面那条把 mode 抹平了才比较,所以这里补一句「谁该是哪个」。
      expect(File('prototype/index.html').readAsStringSync(),
          contains('data-mode="board"'));
      expect(File('prototype/player.html').readAsStringSync(),
          contains('data-mode="stage"'));
    });
  });

  group('动效候选：表、样式、两个入口三处对得上', () {
    /// `FX_ITEMS` 里那六个 id —— 侧栏开关、`<html data-fx>` 上的词、样式里的
    /// `[data-fx~="…"]` 都用它。**表里加一条而样式里没人认**,开关就成了
    /// 「点了没反应」,而它长得跟正常那条一模一样。
    final itemsBlock =
        js.substring(js.indexOf('const FX_ITEMS = ['), js.indexOf('const FX_ALL_ON'));
    final ids = [
      for (final m in RegExp(r"\{ id: '([a-z]+)',\s+name:").allMatches(itemsBlock)) m.group(1)!,
    ];
    final css = File('prototype/styles.css').readAsStringSync();

    test('FX_ITEMS 列了六条候选', () {
      expect(ids.length, 6, reason: '候选表是唯一口径，少了 / 多了都要在这里对齐');
      expect(ids.toSet().length, ids.length, reason: 'id 不能重 —— 重了样式与状态会互相覆盖');
    });

    test('每一条都在样式里有对应的 [data-fx~] 选择器', () {
      final orphan = [for (final id in ids) if (!css.contains('data-fx~="$id"')) id];
      expect(orphan, isEmpty,
          reason: '这些候选在 FX_ITEMS 里、样式里却没人认 —— 开关会「点了没反应」:\n'
              '${orphan.join('\n')}');
    });

    test('推荐组合对每一条都明写了取舍', () {
      // `all` / `none` 是按 FX_ITEMS 派生的,不可能漏;`rec` 是逐个手写的 ——
      // 新加一条候选而没在推荐组合里表态,这一条就会红。
      final rec = js.substring(js.indexOf('rec:  {'), js.indexOf('none: FX_ALL_OFF'));
      final missing = [for (final id in ids) if (!rec.contains('$id:')) id];
      expect(missing, isEmpty,
          reason: '这些候选没在「推荐组合」里写明留或不留 —— '
              '默认值随便落一个，取舍就没人真的做过：\n${missing.join('\n')}');
    });

    test('由 app.js 决定「这一次演不演」的三条真的被读', () {
      // 其余几条装在样式里就够了;这三条由 app.js 决定「这一次要不要演」,
      // 所以它们必须在 renderStage 里被读一次 —— 只写在表里等于没接上。
      for (final id in ['stagger', 'dock', 'tabx']) {
        expect(js, contains('STATE.fx.$id'), reason: '$id 要在 app.js 里真的被读');
      }
    });

    test('设计交付物在两个入口里都有入口', () {
      // 与图标那一格同一类:不是应用里的一屏,所以走不到「应用有没有」那条守卫,
      // 但它同样必须**同时进 VIEWS 与 BOARD** —— 否则侧栏那颗按钮点不动,
      // 或者设计板上看不见。
      final views = js.substring(js.indexOf('const VIEWS = {'), js.indexOf('const BOARD = ['));
      final board = js.substring(js.indexOf('const BOARD = ['), js.indexOf('function boardFrames'));
      expect(views, contains('screenMotion()'),
          reason: 'VIEWS 里要有 motion 这一支，不然侧栏那颗「看动效说明」走不进去');
      expect(board, contains('screenMotion()'), reason: 'BOARD 里要有「动效研究」那一格');
    });
  });

  group('两处硬编码的值不许漂', () {
    test('关于页的版本号 == pubspec.yaml', () {
      final proto = RegExp(r"ABOUT_VERSION = '([^']+)'").firstMatch(js)?.group(1);
      final pub = RegExp(r'^version: *([^ \r\n]+)', multiLine: true)
          .firstMatch(pubspec)
          ?.group(1);
      expect(pub, isNotNull);
      expect(proto, pub,
          reason: '原型那一行只能手写（静态页读不到 pubspec)，所以由这条用例跟住它 —— '
              '改版本号时把 prototype/app.js 的 ABOUT_VERSION 一起改');
    });

    test('设置页的副标题与关于页的产品名一致', () {
      // 原型写「Nordic 原型 v1」、应用写「Nordic」—— 那一处漂了很久没人发现,
      // 因为它既不是几何也不是结构,两条对账都照不到。
      expect(js, isNot(contains('Nordic 原型 v1')),
          reason: '副标题要写产品名，不是「原型 v1」—— 那一行会被当成版本');
      expect(js, contains('<div class="h1">设置</div><div class="sub">Nordic</div>'));
    });
  });
}

/// `*_sheet.dart` / `*_picker_sheet.dart` 归面板,其余归页面。
bool _isSheet(String fileName) =>
    fileName.endsWith('_sheet.dart') || fileName.endsWith('_picker_sheet.dart');
