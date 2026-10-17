import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/models.dart';

/// 歌曲缓存的两件事最容易写错,这一组就盯这两件:
///   1. **缓存文件的位置是算出来的**(不是索引里记的)—— 同一首同一档必须
///      永远指向同一个路径,否则写了一份、读的时候找的是另一份;
///   2. **淘汰按「最久没听」,而且绝不碰正在听的那一份**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const song = Song(
    id: 'song-1',
    title: '可能',
    artist: '程响',
    album: '可能',
    albumId: 'al-1',
    suffix: 'flac',
  );

  const other = Song(
    id: 'song-2',
    title: '山丘',
    artist: '李宗盛',
    album: '山丘',
    albumId: 'al-2',
    suffix: 'flac',
  );

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nordic-media-cache');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// 开着缓存的一份。
  Future<MediaCache> open({int megabytes = 1}) => MediaCache.open(
        limitBytes: megabytes * 1024 * 1024,
        root: root,
      );

  /// 往缓存里塞一份「已经听过」的曲子,返回它的路径。
  ///
  /// 走的是**缓存自己算出来的位置**(`fileFor`),所以测的正是「写与读是不是
  /// 同一处」;手写文件名就测不到那件事了。
  Future<String> seed(
    MediaCache cache,
    Song song, {
    int bytes = 1024,
    required DateTime listenedAt,
    String qualityId = 'medium',
    String? format = 'mp3',
    bool withMime = true,
  }) async {
    final file = cache.fileFor(song, qualityId: qualityId, format: format)!;
    await file.writeAsBytes(List<int>.filled(bytes, 7));
    await file.setLastModified(listenedAt);
    if (withMime) {
      // just_audio 会写这么一份旁注 —— 它得跟着音频一起走。
      await File('${file.path}.mime').writeAsString('audio/mpeg');
      await File('${file.path}.mime').setLastModified(listenedAt);
    }
    // 重新扫一遍,让占用与文件数跟上(生产里由 prune / 下一次启动做这件事)。
    await cache.prune();
    return file.path;
  }

  group('缓存文件的位置', () {
    test('同一首、同一个档位 —— 每次算出来的都是同一个路径', () async {
      final cache = await open();

      final a = cache.fileFor(song, qualityId: 'medium', format: 'mp3')!.path;
      final b = cache.fileFor(song, qualityId: 'medium', format: 'mp3')!.path;

      expect(a, b);
      // 换了实例也还是它 —— 路径只由 id 与档位算出来,与内存状态无关。
      final again = await open();
      expect(again.fileFor(song, qualityId: 'medium', format: 'mp3')!.path, a);
      expect(again.isAvailable, isTrue);
    });

    test('换了转码档位就是另一份 —— 缓存里不能混着两种码率', () async {
      final cache = await open();

      final medium = cache.fileFor(song, qualityId: 'medium', format: 'mp3')!;
      final original = cache.fileFor(song, qualityId: 'original')!;

      expect(medium.path, isNot(original.path));
      // 原音档跟着服务器的原文件后缀走(这里没有 format)。
      expect(original.path, endsWith('.flac'));
      expect(medium.path, endsWith('.mp3'));
    });

    test('曲目 id 里的路径分隔符不会把文件指到别的目录去', () async {
      final cache = await open();
      const nasty = Song(
        id: '../../etc/passwd',
        title: 'x',
        artist: 'y',
        album: 'z',
        albumId: 'a',
      );

      final file = cache.fileFor(nasty, qualityId: 'medium', format: 'mp3')!;
      // 关键不是名字里没有点号,而是**父目录仍然是缓存根** ——
      // 一个没洗过的 `/` 就能把文件指到别的目录去。
      expect(file.parent.path, root.path);
    });

    test('没缓存过的曲目答「没有」,命中之后才答路径', () async {
      final cache = await open();
      expect(cache.cachedPathFor(song, qualityId: 'medium', format: 'mp3'), isNull);

      final path = await seed(
        cache,
        song,
        listenedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      expect(cache.cachedPathFor(song, qualityId: 'medium', format: 'mp3'), path);
      expect(cache.usedBytes, 1024);
      expect(cache.fileCount, 1);
    });

    test('另一首曲目不会误答成已有那一份', () async {
      final cache = await open();
      await seed(
        cache,
        song,
        listenedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      expect(cache.cachedPathFor(other, qualityId: 'medium', format: 'mp3'), isNull);
    });
  });

  group('上限与淘汰', () {
    test('超出上限就按「最久没听」先扔', () async {
      // 上限 1 MB,每份 400 KB —— 三份放不下,得扔一份。
      // 每写一份都会顺手淘汰一轮(生产里由播放触发),所以断言的是
      // 「最后剩下谁」,而不是某一轮释放了多少。
      final cache = await open();
      final now = DateTime.now();

      final oldest = await seed(
        cache,
        song,
        bytes: 400 * 1024,
        listenedAt: now.subtract(const Duration(days: 3)),
      );
      final middle = await seed(
        cache,
        other,
        bytes: 400 * 1024,
        listenedAt: now.subtract(const Duration(days: 1)),
      );
      const third = Song(
        id: 'song-3', title: 'c', artist: 'd', album: 'e', albumId: 'al-3',
      );
      final newest = await seed(
        cache,
        third,
        bytes: 400 * 1024,
        listenedAt: now,
      );

      expect(File(oldest).existsSync(), isFalse, reason: '最久没听的那一份该先走');
      expect(File(middle).existsSync(), isTrue);
      expect(File(newest).existsSync(), isTrue);
      expect(cache.usedBytes, lessThanOrEqualTo(1 * 1024 * 1024));
    });

    test('正在听的那一份不管多旧都不扔', () async {
      final cache = await open();
      final now = DateTime.now();

      final playing = await seed(
        cache,
        song,
        bytes: 400 * 1024,
        listenedAt: now.subtract(const Duration(days: 9)),
      );
      final newer = await seed(
        cache,
        other,
        bytes: 400 * 1024,
        listenedAt: now,
      );
      expect(cache.usedBytes, 800 * 1024, reason: '两份都还在,还没到上限');

      // 正在听的就是最旧那一份 —— 它反而被保护起来。
      await cache.markPlaying(song, qualityId: 'medium', format: 'mp3');

      const third = Song(
        id: 'song-3', title: 'c', artist: 'd', album: 'e', albumId: 'al-3',
      );
      await seed(cache, third, bytes: 400 * 1024, listenedAt: now);

      expect(File(playing).existsSync(), isTrue,
          reason: '删掉正在放的文件的字节流,音就断了');
      expect(File(newer).existsSync(), isFalse,
          reason: '要腾地方就得扔别的 —— 哪怕它比正在听的那份新');
      expect(cache.usedBytes, lessThanOrEqualTo(1 * 1024 * 1024));
    });

    test('命中会刷新「最近听过」—— 常听的不会被新歌挤掉', () async {
      final cache = await open();
      final now = DateTime.now();

      // 老歌:三天前落盘,但刚刚又听了一遍。
      final replayed = await seed(
        cache,
        song,
        bytes: 400 * 1024,
        listenedAt: now.subtract(const Duration(days: 3)),
      );
      await cache.markPlaying(song, qualityId: 'medium', format: 'mp3');

      await seed(cache, other, bytes: 400 * 1024, listenedAt: now.subtract(const Duration(days: 2)));
      const third = Song(
        id: 'song-3', title: 'c', artist: 'd', album: 'e', albumId: 'al-3',
      );
      await seed(cache, third, bytes: 400 * 1024, listenedAt: now.subtract(const Duration(days: 1)));
      await cache.prune();

      expect(File(replayed).existsSync(), isTrue, reason: '刚听过的那一份不该先走');
    });

    test('调小上限当场淘汰到额度之下', () async {
      final cache = await open(megabytes: 4);
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await seed(
          cache,
          Song(id: 'song-$i', title: 't$i', artist: 'a', album: 'b', albumId: 'al'),
          bytes: 1024 * 1024,
          listenedAt: now.subtract(Duration(days: 3 - i)),
        );
      }
      expect(cache.usedBytes, 3 * 1024 * 1024);

      await cache.setLimitBytes(1024 * 1024);

      expect(cache.usedBytes, lessThanOrEqualTo(1024 * 1024));
      expect(cache.fileCount, 1);
    });

    test('关掉缓存(上限 0)= 已经留着的全清掉,而且不再给缓存位', () async {
      final cache = await open();
      final path = await seed(
        cache,
        song,
        listenedAt: DateTime.now(),
      );

      await cache.setLimitBytes(0);

      expect(cache.enabled, isFalse);
      expect(File(path).existsSync(), isFalse);
      expect(cache.usedBytes, 0);
      expect(cache.fileFor(song, qualityId: 'medium', format: 'mp3'), isNull,
          reason: '不缓存就得真的不写盘');
    });

    test('已经在写的那一份不给第二个播放源 —— 两个写入句柄会写坏它', () async {
      final cache = await open();
      final file = cache.fileFor(song, qualityId: 'medium', format: 'mp3')!;
      expect(cache.fileFor(song, qualityId: 'medium', format: 'mp3'), isNotNull);

      // 模拟 just_audio 正在写:它先写 `.part`,下完才改名。
      await File('${file.path}.part').writeAsString('半截');

      expect(cache.fileFor(song, qualityId: 'medium', format: 'mp3'), isNull);
    });
  });

  group('清空与半截文件', () {
    test('清除:文件与旁注一起走,返回释放的体积', () async {
      final cache = await open();
      final path = await seed(cache, song, bytes: 2048, listenedAt: DateTime.now());

      final freed = await cache.clear();

      expect(freed, 2048);
      expect(File(path).existsSync(), isFalse);
      expect(File('$path.mime').existsSync(), isFalse);
      expect(cache.usedBytes, 0);
      expect(cache.fileCount, 0);
    });

    test('没主的半截文件不算占用,也不会一直被留着', () async {
      final cache = await open();
      final stale = File('${root.path}${Platform.pathSeparator}abc.part');
      await stale.writeAsBytes(List<int>.filled(4096, 1));
      await stale.setLastModified(
        DateTime.now().subtract(MediaCache.stalePartialAge * 2),
      );

      final fresh = File('${root.path}${Platform.pathSeparator}def.part');
      await fresh.writeAsBytes(List<int>.filled(4096, 1));

      await cache.prune();

      expect(File(stale.path).existsSync(), isFalse, reason: '上一次被杀掉留下的');
      expect(File(fresh.path).existsSync(), isTrue, reason: '可能正在写,别动');
      expect(cache.usedBytes, 0, reason: '半截的不该算进用户的「已用空间」');
    });
  });

  group('存储用不了时', () {
    test('目录建不出来就退化成「不缓存」,别的照旧', () async {
      // 拿一个**文件**当缓存根目录 —— create() 必然失败。
      final blocker = File('${root.path}${Platform.pathSeparator}not-a-dir');
      await blocker.writeAsString('x');

      final cache = await MediaCache.open(
        limitBytes: 1024,
        root: Directory(blocker.path),
      );

      expect(cache.isAvailable, isFalse);
      expect(cache.enabled, isFalse);
      expect(cache.fileFor(song, qualityId: 'medium', format: 'mp3'), isNull);
      expect(cache.cachedPathFor(song, qualityId: 'medium', format: 'mp3'), isNull);
      expect(await cache.prune(), 0);
      expect(await cache.clear(), 0);
    });
  });

  /// 播报的**次数**也是行为的一部分:`AppState` 把这个通知转发给了全应用
  /// (见 `app_state.dart`),所以「扫一遍、什么都没变、还是播报一次」等于
  /// 让每一次换歌(淘汰就搭在那上面)都把整个界面重建一遍。
  group('占用没变就不播报', () {
    test('第二次扫到同一份目录时,订阅者收不到通知', () async {
      final cache = await MediaCache.open(
        limitBytes: CacheLimit.gb1.bytes,
        root: Directory('${root.path}${Platform.pathSeparator}audio'),
      );
      final file = cache.fileFor(song, qualityId: 'medium', format: 'mp3')!;
      await file.writeAsBytes(List<int>.filled(1024, 7));

      var notified = 0;
      cache.addListener(() => notified++);

      await cache.prune();
      expect(cache.usedBytes, 1024);
      expect(notified, 1, reason: '占用从 0 变到 1 KB,该播报一次');

      await cache.prune();
      expect(notified, 1, reason: '一个字节都没变,不该再播报');

      // 数字真的变了就还得播报 —— 收窄不能收成「不再通知」。
      await file.writeAsBytes(List<int>.filled(2048, 7));
      await cache.prune();
      expect(cache.usedBytes, 2048);
      expect(notified, 2);
    });
  });

  /// 换歌那一下的淘汰:**该算的账一分不少,不该扫的目录一趟不多**。
  ///
  /// 它原先每换一首歌就把整个缓存目录 stat 一遍(几百份文件),是能感觉到的
  /// 同步 I/O,而绝大多数换歌根本不会让占用越过上限。所以账只在「有新文件
  /// 可能落盘」或「账面上已经超了」时才重新数 —— 两条都要钉住:漏了后者,
  /// 缓存就能一路涨过上限。
  group('换歌那一下的算账', () {
    test('没有新东西落盘时,换歌不重扫目录', () async {
      final cache = await open();
      final gone = await seed(
        cache,
        song,
        bytes: 400 * 1024,
        listenedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(cache.usedBytes, 400 * 1024);

      // 背地里把文件删掉 —— 只有真的重扫一遍目录才会发现。
      await File(gone).delete();
      await cache.markPlaying(other, qualityId: 'medium', format: 'mp3');

      expect(cache.usedBytes, 400 * 1024,
          reason: '这一次换歌不该重扫目录,账应当还是上一趟数出来的那份');
    });

    test('有新文件要落盘时,下一次换歌就把账对齐', () async {
      final cache = await open();
      final gone = await seed(
        cache,
        song,
        bytes: 400 * 1024,
        listenedAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      await File(gone).delete();
      // 拼一个走网络的播放源 = just_audio 接下来会往这个位置写字节。
      cache.fileFor(other, qualityId: 'medium', format: 'mp3');
      await cache.markPlaying(other, qualityId: 'medium', format: 'mp3');

      expect(cache.usedBytes, 0, reason: '有新文件要写,这一次就该重扫对齐');
    });

    test('账面上已经超了上限时,换歌那一下照样淘汰', () async {
      final cache = await open();
      final now = DateTime.now();
      final oldest = await seed(
        cache,
        song,
        bytes: 400 * 1024,
        listenedAt: now.subtract(const Duration(days: 2)),
      );
      await seed(cache, other, bytes: 400 * 1024, listenedAt: now);
      expect(cache.usedBytes, 800 * 1024);

      // 第三份直接写到盘上(账还停在 800 KB):帐面上没超、盘上超了。
      const third = Song(
        id: 'song-3', title: 'c', artist: 'd', album: 'e', albumId: 'al-3',
      );
      final file = cache.fileFor(third, qualityId: 'medium', format: 'mp3')!;
      await file.writeAsBytes(List<int>.filled(400 * 1024, 7));

      await cache.markPlaying(other, qualityId: 'medium', format: 'mp3');

      expect(cache.usedBytes, lessThanOrEqualTo(1024 * 1024),
          reason: '淘汰仍然发生在换歌这一下');
      expect(File(oldest).existsSync(), isFalse, reason: '最久没动过的那份该走');
      expect(file.existsSync(), isTrue);
    });
  });

  group('档位定义', () {
    test('认不出来的档位退回默认,而不是抛异常', () {
      expect(CacheLimit.byId('1g'), CacheLimit.gb1);
      expect(CacheLimit.byId(null), CacheLimit.fallback);
      expect(CacheLimit.byId('nope'), CacheLimit.fallback);
      expect(CacheLimit.byId('off').isOff, isTrue);
    });

    test('档位从「不缓存」起按体积从小到大排 —— 面板上的顺序就是它', () {
      final sizes = CacheLimit.all.map((l) => l.bytes).toList();
      expect(sizes, orderedEquals([...sizes]..sort()));
      expect(CacheLimit.all.first.isOff, isTrue);
    });

    test('0 说的是「不缓存」,不是「0 MB」', () {
      expect(CacheLimit.off.label, '不缓存');
      expect(CacheLimit.gb1.label, '1 GB');
    });
  });
}
