import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'iterables.dart';
import 'media_files.dart';
import 'models.dart';

/// 歌曲缓存的上限档位。**界面与存储层共用这一份定义** ——
/// 面板上列什么、允许哪些值,只有一处说法。
///
/// 「不缓存」是真的不写盘,而不是给一个小额度:开关说关就得关。
@immutable
class CacheLimit {
  const CacheLimit({
    required this.id,
    required this.name,
    required this.description,
    required this.megabytes,
  });

  final String id;
  final String name;
  final String description;

  /// 0 = 不缓存。
  final int megabytes;

  bool get isOff => megabytes <= 0;

  int get bytes => megabytes * 1024 * 1024;

  /// 面板上的顺序 = 这里的顺序,从小到大。
  static const off = CacheLimit(
    id: 'off',
    name: '不缓存',
    description: '听过的歌每次都从服务器拉，本机不留音频',
    megabytes: 0,
  );

  static const mb256 = CacheLimit(
    id: '256',
    name: '256 MB',
    description: '约 25 首',
    megabytes: 256,
  );

  static const mb512 = CacheLimit(
    id: '512',
    name: '512 MB',
    description: '约 50 首',
    megabytes: 512,
  );

  static const gb1 = CacheLimit(
    id: '1g',
    name: '1 GB',
    description: '约 100 首 · 默认',
    megabytes: 1024,
  );

  static const gb2 = CacheLimit(
    id: '2g',
    name: '2 GB',
    description: '约 200 首',
    megabytes: 2048,
  );

  static const gb4 = CacheLimit(
    id: '4g',
    name: '4 GB',
    description: '约 400 首',
    megabytes: 4096,
  );

  static const all = [off, mb256, mb512, gb1, gb2, gb4];

  /// 没得选的时候用哪一档。1 GB:按 320 kbps 算约一百首,
  /// 手机上一个既听得出来又不会把存储吃掉的量。
  static const fallback = gb1;

  /// 后缀是给界面看的:「1 GB」比「1024 MB」好读。0 不是「0 MB」——
  /// 那读起来像额度用完了,而它说的是「压根不写盘」。
  String get label => isOff ? '不缓存' : name;

  static CacheLimit byId(String? id) =>
      all.where((l) => l.id == id).firstOrNull ?? fallback;
}

/// 听过的歌在本机留的那一份。
///
/// **与下载的区别**(两处都往磁盘写音频,它们是两件事):
///   - 下载是用户点名要的:不会被自动删掉,放在 `Nordic/Music` 里看得见;
///   - 缓存是播放时顺手留的:上限一到就按「最久没听」淘汰,放在应用私有目录。
///
/// 所以两边目录、索引、生命周期全部分开,谁也删不到谁的文件 —— 上限只管缓存。
///
/// **没有索引文件**,这一点是刻意的:缓存文件的名字由(曲目 id + 转码档位)
/// 算出来,写与读都能现算,于是不存在「索引说有一份、盘上却没有」这类
/// 两处对不上的状态。占用与「最久没听」直接读目录(文件 mtime 就是 LRU 的
/// 时间戳),代价是一次目录扫描 —— 它只发生在启动与淘汰的时候。
class MediaCache extends ChangeNotifier {
  MediaCache._(this._root, this._limitBytes);

  /// 缓存目录。null 表示这块存储用不了 —— 见 [isAvailable]。
  final Directory? _root;

  int _limitBytes;
  int _usedBytes = 0;
  int _fileCount = 0;

  /// 正在听的那一份的**完整路径**。淘汰时跳过它 ——
  /// 删掉正在放的文件的字节流,音就断了。
  String? _playingPath;

  /// 正在跑的那一轮淘汰。同一时刻只留一轮:两轮撞在一起会重复删同一个文件,
  /// 占用数字也会来回跳。
  Future<int>? _pruning;

  /// 上一次把目录数完的时刻。换歌那一下的淘汰据此决定「要不要真的扫一遍」
  /// (见 [_pruneAfterTrackChange])。初值是纪元 —— 还没数过,所以一定会扫。
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 「数完目录之后又有文件可能落盘了」。播放层每拼一个走网络的播放源就会
  /// 置一次([fileFor] 拿到空位就说明 just_audio 接下来会往那儿写),
  /// 数目录那一趟负责清掉它。
  ///
  /// 删掉几份低档缓存之后也会置起来:那一笔是**相对**减账,而刚写下的文件
  /// 本来就没进过账([_delete] 减到底会被夹在 0),于是数字要靠下一趟重数
  /// 才对得回来。
  bool _needsRescan = true;

  /// 「盘上一份缓存都没有」这条快路能不能走。
  ///
  /// **光看 `_usedBytes == 0` 不够**:它是**上一次数目录**的结果,而
  /// [fileFor] 刚一发出缓存位、或者刚删掉几份,它就已经旧了(前者还没进账,
  /// 后者把账减穿了)。这类窗口里按「没有缓存」判,会放过一份真在盘上的文件,
  /// 于是同一首又从网络拉一遍 —— 正是这一轮要治的那件事。
  /// `_needsRescan` 正是「数完之后又可能有新文件落盘」那笔账,一起看。
  bool get _maybeEmpty => _usedBytes == 0 && !_needsRescan;

  /// 换歌那一下的淘汰,两次真扫之间至少隔这么久。
  /// 每换一首歌就把整个缓存目录 stat 一遍,在几百份文件上是可观的同步 I/O ——
  /// 而绝大多数换歌压根不会让占用越过上限。测试可以调小它。
  static Duration rescanInterval = const Duration(seconds: 15);

  /// 半截文件的尾巴。just_audio 的 LockCachingAudioSource 就是这么写的:
  /// 下完才改名成正式文件。
  static const _partialSuffix = '.part';

  /// just_audio 记原始 MIME 的小文件(`<缓存文件>.mime`),和它同生共死。
  static const _mimeSuffix = '.mime';

  /// 半截的下载超过这段时间就当它没主了(进程被杀 / 中途换了线路):
  /// 既不参与续传,也不该一直占着额度。
  static const stalePartialAge = Duration(minutes: 30);

  /// 打开缓存。[root] 只给测试用 —— 生产路径由平台目录决定。
  ///
  /// 缓存**不可用不该让应用起不来**:目录建不出来就退化成「不缓存」,
  /// 播放照旧走网络。
  ///
  /// [scan] 决定要不要**当场**数一遍目录(见 [prime])。生产路径传 `false`
  /// 并把它挪到首帧之后 —— 那是整个缓存目录的 stat 遍历,几百份文件压在
  /// `runApp` 之前就是白等一截,而它要产出的三件东西(占用数字、清半截文件、
  /// 按上限淘汰)**没有一件急着在首帧之前知道**。
  static Future<MediaCache> open({
    required int limitBytes,
    Directory? root,
    bool scan = true,
  }) async {
    try {
      final dir = root ?? await _defaultRoot();
      if (!dir.existsSync()) await dir.create(recursive: true);
      final cache = MediaCache._(dir, limitBytes < 0 ? 0 : limitBytes);
      if (scan) await cache.prime();
      return cache;
    } catch (_) {
      return MediaCache._(null, 0);
    }
  }

  /// 把目录数一遍:数出占用(设置页要显示)、清掉没主的半截文件、
  /// 超出上限就先淘汰 —— 于是「上限调小了」在下次启动也能落地。
  ///
  /// 冷启动时由 `main.dart` 在**首帧之后**调一次(见 [open] 的 [scan])。
  Future<void> prime() => prune();

  static Future<Directory> _defaultRoot() async {
    Directory base;
    try {
      base = await getApplicationSupportDirectory();
    } on MissingPluginException {
      // 桌面 / 测试环境没有这个插件。
      base = Directory.systemTemp;
    }
    return Directory('${base.path}${Platform.pathSeparator}cache'
        '${Platform.pathSeparator}audio');
  }

  bool get isAvailable => _root != null;

  /// 缓存开着没有。关掉时一切退化成「直接走网络」——
  /// 包括 [fileFor] 返回 null(不给缓存位)。
  bool get enabled => isAvailable && _limitBytes > 0;

  int get limitBytes => _limitBytes;

  /// 缓存目录眼下占了多少字节。**不含**半截文件与 `.mime` 小文件。
  int get usedBytes => _usedBytes;

  /// 缓存里有几个文件。
  int get fileCount => _fileCount;

  /// 本机缓存放哪儿(绝对路径),给界面显示用。
  String get rootPath => _root?.path ?? '';

  /// 换上限。调小到低于当前占用时**当场淘汰**到上限之下,
  /// 而不是等下一次听歌 —— 用户改完数字就该看见占用跟着降。
  ///
  /// 改成 0(不缓存)会把已经留着的全清掉:关掉之后那些文件再也不会被用到,
  /// 留着只是白占地方。
  Future<void> setLimitBytes(int bytes) async {
    _limitBytes = bytes < 0 ? 0 : bytes;
    // 占用那本是「上次数完目录」时的账,调额度要**按现在的盘上情况**算,
    // 所以这里点名要重扫一遍(否则「调小上限当场淘汰」会漏掉刚写下的那几份)。
    _needsRescan = true;
    // 调额度会造成成片删除 / 保留,这一格一格的账不值得记 —— 直接整表重来。
    _forgetAll();
    notifyListeners();
    await prune();
  }

  // ---------------- 播放层要的两件事 ----------------

  /// 这一首该往哪儿写缓存。返回 null 表示**这次不要缓存**:
  /// 缓存关着、存储用不了,或者已经有一个播放源正在写这个位置
  /// (同一个文件两个写入句柄会把这份缓存写坏,那不如这次不缓存)。
  File? fileFor(Song song, {required String qualityId, String? format}) {
    if (!enabled) return null;
    final file = _slotFor(song, qualityId: qualityId, format: format);
    if (File('${file.path}$_partialSuffix').existsSync()) return null;
    // 拿到空位就说明**接下来会有字节往这儿写**(just_audio 边听边写)。
    // 记一笔,换歌那一下的淘汰就知道该重新数一遍目录了。
    _needsRescan = true;
    // 马上会有字节往这儿写(而且先写 `.part`)—— 这一格的事实已经旧了。
    _forget(file);
    return file;
  }

  /// 这一首在本机的缓存文件(存在才算数)。没缓存过就是 null。
  String? cachedPathFor(
    Song song, {
    required String qualityId,
    String? format,
  }) {
    // 一个文件都没有就不必碰盘 —— 冷启动时绝大多数曲目都落在这一支上
    // (判据见 [_maybeEmpty]:不是「账上是 0」,而是「账是 0 而且没欠着重数」)。
    if (!enabled || _maybeEmpty) return null;
    final file = _slotFor(song, qualityId: qualityId, format: format);
    return _existsAt(file) ? file.path : null;
  }

  /// 这一份**完整**落到本机了吗(不是半截的)。
  ///
  /// 与 [cachedPathFor] 的差别:那个是「能不能直接当本机文件播」的快路,
  /// 这个多问一句 `<文件>.part` 还在不在 —— 边听边缓存的那一份在播到一半时
  /// 就已经有文件了,但那是半截的,**不能拿去 seek**。播放层就是这么用的:
  /// 拖动进度条要等一份完整的,见 `audio_handler` 的 `_waitForLocalCopy`。
  ///
  /// 不看 [_usedBytes]:那个数要等下一轮数目录才刷新,刚下完的那一份还不在里头。
  /// **永远真查**,连「在不在」也不走 [_existsMemo] —— 见那份备忘录上的
  /// 第三条硬规矩:这条路是「半截写完了没有」的轮询,记忆会让它永远等不到
  /// 刚冒出来的那一份。
  bool isComplete(Song song, {required String qualityId, String? format}) {
    if (!enabled) return false;
    final file = _slotFor(song, qualityId: qualityId, format: format);
    if (!existsProbe(file.path)) return false;
    return !existsProbe('${file.path}$_partialSuffix');
  }

  /// 这一首在本机的**更高档**那一份(有才算数)。[candidates] 由播放层按
  /// 「从高到低」给出(见 `quality.dart` 的 `betterTiersThan`),取第一个命中的。
  ///
  /// 为什么值得做:同一首已经留着一份更好的音频时,照所选档再拉一遍等于
  /// **白花流量**,还会再写一份低档缓存 —— 于是同一首在磁盘上并存两份,
  /// 正是要治的那件事。拿更高的那份播之后,这一首压根不会再写缓存
  /// ([fileFor] 都轮不上)。
  ///
  /// 只要**完整**的那一份(半截的播到一半会断);[candidates] 最多三档,
  /// 路径纯算(有备忘录),不扫目录。
  ({String path, String qualityId})? completeCopyAmong(
    Song song,
    List<({String qualityId, String? format})> candidates,
  ) {
    // 一个文件都没有就不必碰盘(与 [cachedPathFor] 同一条快路,
    // 判据见 [_maybeEmpty])。
    if (!enabled || _maybeEmpty) return null;
    for (final candidate in candidates) {
      final file = _slotFor(
        song,
        qualityId: candidate.qualityId,
        format: candidate.format,
      );
      if (!_isCompleteFile(file)) continue;
      return (path: file.path, qualityId: candidate.qualityId);
    }
    return null;
  }

  /// 「盘上有这一份,而且不是半截」—— [isComplete] 与 [_dropLowerTiers]
  /// 共用这一条口径,免得两处对「完整」的理解不一样。
  /// 走「在不在」那一位的备忘录(没有缓存时直接短路,一次盘都不碰),
  /// 而 `.part` **每次真查** —— 那一半是 just_audio 自己的写入过程。
  bool _isCompleteFile(File file) {
    if (!_existsAt(file)) return false;
    return !existsProbe('${file.path}$_partialSuffix');
  }

  /// 开始放某一首时叫一声:记下「正在听的是哪一份」(淘汰时跳过它),
  /// 命中的话刷新它的「最近听过」,然后按上限淘汰一轮。
  ///
  /// 由**播放层的换歌**触发(见 `audio_handler` 的 `_noteCurrentTrack`),
  /// 不是「拼播放源」时触发 —— 一次 setQueue 会拼出整个队列的播放源,
  /// 在那一头打标记的话,最后被标记成「正在听」的会是队列的最后一首。
  ///
  /// 淘汰也放在这里,是因为它是**会话中途唯一的算账时刻**:一直放下去不会重建
  /// 播放源,不在这里淘汰的话,缓存能一路涨过上限(上限只在启动与调额度时才查)。
  /// 走的是 [_pruneAfterTrackChange] —— 不算账的那几下不白扫目录。
  /// [playingPath] 是**实际装载的那个文件**:播放层可能拿的是更高档那一份
  /// (见 [completeCopyAmong]),这时按 [qualityId] 现算路径会指到一个不存在的
  /// 文件 —— `_playingPath` 指错,淘汰时就可能把正在解码的那一份删掉。
  /// 所以让知道的那一头直接说,不去猜。
  ///
  /// [lowerTiers] 见 [_dropLowerTiers]。
  Future<void> markPlaying(
    Song song, {
    required String qualityId,
    String? format,
    String? playingPath,
    List<({String qualityId, String? format})> lowerTiers = const [],
  }) async {
    if (!enabled) return;
    final slot = _slotFor(song, qualityId: qualityId, format: format);
    final playing = File(playingPath ?? slot.path);
    _playingPath = playing.path;

    // **换一次歌就把存在性备忘录整表清掉**:那是「盘上有没有这一份」的记忆,
    // 而盘会被我们之外的东西改(用户在系统文件管理器里删、系统在存储吃紧时
    // 清掉应用缓存目录、just_audio 下完改名)。清在换歌这一下,窗口就**最多
    // 一首歌**;不清的话最坏情况是拿一条早就不在的路径去装载。
    _forgetAll();

    if (playing.existsSync() && _isInCache(playing)) {
      // 命中就刷新 mtime —— LRU 的「最近听过」就是文件时间,不刷的话
      // 一首天天听的歌会因为它当初落盘的时刻早而被先扔掉。
      //
      // **只对缓存目录里的文件做**:播放层会把下载来的那一份也报过来
      // (下过的直接播本机,不走缓存)。那份在 `Nordic/Music` 里,是用户
      // 看得见的东西 —— 文件管理器按日期排、他自己记的日子,拿缓存这套
      // 规则去动它等于悄悄改了别人的文件。
      try {
        await playing.setLastModified(DateTime.now());
      } catch (_) {
        // 刷不动只是这一份的 LRU 位置不准,不影响播放。
      }
    }

    await _dropLowerTiers(
      song,
      playingPath: playing.path,
      lowerTiers: lowerTiers,
    );
    await _pruneAfterTrackChange();
  }

  /// 同一首的**更低档**那几份,在当前在放的这一份**已经完整落到本机**之后才丢。
  ///
  /// 两条判据缺一不可:
  /// - 高码率那份还在下(只有 `.part`)就把低码率的扔掉,网络一断就两头落空 ——
  ///   用户既没拿到好的那份,也没有回得去的差的那份。所以先看「好的那份完整吗」;
  /// - 候选路径**纯算**([_slotFor] 有备忘录),最多三下 stat、**不扫目录** ——
  ///   这一步挂在每次换歌上,不能变贵。
  ///
  /// 正在听的那一份永远先跳过(防御:它不该出现在 [lowerTiers] 里,
  /// 真出了这种事也不该删)。
  Future<void> _dropLowerTiers(
    Song song, {
    required String playingPath,
    required List<({String qualityId, String? format})> lowerTiers,
  }) async {
    if (lowerTiers.isEmpty) return;
    if (!_isCompleteFile(File(playingPath))) return;

    var dropped = false;
    for (final lower in lowerTiers) {
      final slot = _slotFor(
        song,
        qualityId: lower.qualityId,
        format: lower.format,
      );
      if (slot.path == playingPath) continue;
      if (!_isCompleteFile(slot)) continue;
      // 连同 `.mime` 旁注一起删。**不逐份播报**:一次切歌最多丢掉三档,
      // 每份各播报一次等于让全应用跟着重建两三遍(见 [_delete] 的 notify,
      // 与 [markPlaying] 排在后面的那一趟淘汰同一个道理 —— 那一趟会重新
      // 数一遍目录,数字对了才播报)。
      await _delete(slot, notify: false);
      dropped = true;
    }
    // 减账是**相对**的,而刚写下的那份本来就不在账上(见 [_needsRescan])——
    // 置起来,紧跟其后的那趟淘汰会把目录重新数一遍,占用与文件数就归位了。
    if (dropped) _needsRescan = true;
  }

  // ---------------- 占用与淘汰 ----------------

  /// 全量淘汰:重新数一遍目录,再按上限删到额度之下。返回这次释放的字节数。
  ///
  /// 用在**启动 / 调额度 / 清缓存**这几处,以及测试里 —— 也就是说「立刻如实
  /// 算一遍」的场景。换歌那一下走的是 [_pruneAfterTrackChange]。
  Future<int> prune() {
    final running = _pruning;
    if (running != null) return running;
    final run = _pruneOnce().whenComplete(() => _pruning = null);
    _pruning = run;
    return run;
  }

  /// 换歌那一下的淘汰。
  ///
  /// 与 [prune] 是同一件事(**淘汰仍然发生在换歌这一下**,这是原本的约定),
  /// 差别只在「要不要真的扫一遍目录」。绝大多数换歌不会让占用越过上限,
  /// 而每换一首都 stat 一遍整个缓存目录,在几百份文件上是能感觉到的同步 I/O。
  /// 所以只在下面四种情况真扫:
  ///
  ///   - 缓存关着(那就该清干净);
  ///   - **眼下已经超了上限**(账虽然是旧的,但旧账都超了,真账只会更超);
  ///   - 数完之后又有新文件可能落盘([_needsRescan]);
  ///   - 距上次数目录超过 [rescanInterval]。
  ///
  /// 代价说清楚:刚写下的那一份最多晚到「下一次真扫」才被算进占用与文件数 ——
  /// 而界面上那是 MB 级的数字,而且它还是被上限兜着的。
  Future<int> _pruneAfterTrackChange() {
    if (!enabled) return prune();
    if (_usedBytes > _limitBytes) return prune();
    if (_needsRescan) return prune();
    if (DateTime.now().difference(_lastScanAt) >= rescanInterval) return prune();
    return Future.value(0);
  }

  Future<int> _pruneOnce() async {
    final stamped = await _scan();

    // 关了缓存 = 已经留着的一份也不要。
    if (!enabled) return _usedBytes == 0 ? 0 : _deleteAll(stamped: stamped);

    if (_usedBytes <= _limitBytes) return 0;
    return _evict(stamped);
  }

  /// 清空缓存,返回释放的字节数(界面拿它说「释放了 138 MB」)。
  /// **正在读的那一份也删** —— 用户按的是「清除」,
  /// 留下一个不清不楚的几 MB 只会让人以为没清干净(Android 上删除一个
  /// 正开着的文件不会掐断声音:平台手上那个文件句柄还活着)。
  Future<int> clear() async {
    if (_root == null) return 0;
    _forgetAll();
    final freed = await _deleteAll(keepPlaying: false);
    notifyListeners();
    return freed;
  }

  // ---------------- 盘上那点事 ----------------

  /// 算出来的槽位路径按「曲目 + 档位」记一份。
  ///
  /// 路径是这几个输入决定**纯函数**,记下来永远是同一个答案。值得记的理由与
  /// 播放地址那一头同一套:一次 `setQueue` 会把整条队列的播放源都拼一遍,而每首歌
  /// 要算两次 SHA-1(一次看有没有缓存、一次看能不能写缓存位)。
  static const _slotMemoLimit = 4096;
  final Map<String, File> _slotMemo = {};

  /// 「盘上这一份在不在 / 完不完整」的备忘录,键是**绝对路径**。
  ///
  /// 为什么值得记:一次 `setQueue` / 重排 / 换档 / 换线路会把**整条队列**的播放源
  /// 都拼一遍,而每一首要在「所选档」与「至多三档更高档」上各问一遍盘 ——
  /// 一千首的队列就是几千次**同步** `existsSync`,全压在按下去那一帧的 UI 线程上。
  ///
  /// 三条硬规矩:
  ///  - **只对缓存目录里的路径记**([_isInCache])。点名下载的那一份在
  ///    `Nordic/Music` 里,可能被用户在系统文件管理器里删掉 —— 那条路必须每次
  ///    真查,它是 [playbackOriginFor]「下载 > 缓存 > 网络」那条优先级的前提。
  ///  - **记的只有「在不在」这一位,不记「完不完整」**:半截那个 `.part` 是
  ///    just_audio 边听边写时自己造、下完自己改名的,那条路我们插不上手(没有
  ///    失效钩子)。把它记下来,要么会把正在写的半截当完整的(拿它播会播到
  ///    一半没了),要么会把刚写完的那一份藏住。于是完整那一位**每次真查**。
  ///  - **`isComplete` 连「在不在」也绕开**(`useMemo: false`):那是「半截写完
  ///    了没有」的轮询路(见 `audio_handler` 的 `_waitForLocalCopy`),文件随时
  ///    可能冒出来,记忆会让它永远等不到。
  ///
  /// 正负都记:缓存槽位在常见情况下就是「没有」,只记正结果等于每次整队拼源都
  /// 重新 stat 一遍那些不存在的路径 —— 那条路比命中还多。
  static const _existsMemoLimit = 8192;
  final Map<String, bool> _existsMemo = {};

  /// 存在性探针。**测试换成计数的那个**,用来钉「少查了盘」这件事本身;
  /// 生产路径上它就是一句 [File.existsSync]。
  @visibleForTesting
  bool Function(String path) existsProbe = _statExists;

  static bool _statExists(String path) => File(path).existsSync();

  /// 「在不在」这一位 —— 记的就是它。缓存目录外一律真查。
  bool _existsAt(File file) {
    if (!_isInCache(file)) return existsProbe(file.path);
    final hit = _existsMemo[file.path];
    if (hit != null) return hit;
    final exists = existsProbe(file.path);
    // 满了整体清掉:多算一遍只是慢一点,记错才是问题(与 [_slotMemo] 同一条口径)。
    if (_existsMemo.length >= _existsMemoLimit) _existsMemo.clear();
    _existsMemo[file.path] = exists;
    return exists;
  }

  /// 盘上这一份的事实变了(刚发出写入位 / 刚删掉)—— 把那一格扔掉。
  /// 整表清的理由有两条:**换歌**([markPlaying],把窗口压到一首歌以内)、
  /// 以及 [_scan] 已经把整个目录数过一遍了(清完立刻回填)。
  void _forget(File file) {
    if (_existsMemo.isNotEmpty) _existsMemo.remove(file.path);
  }

  void _forgetAll() {
    if (_existsMemo.isNotEmpty) _existsMemo.clear();
  }

  /// 「这个路径上真有文件吗」—— 播放层的存在性判据接的就是这一条
  /// (见 `audio_handler` 的 `_sourceFor` 把 [playbackOriginFor] 的 `pathExists`
  /// 指过来)。缓存目录外的路径在这里**照旧真查**。
  bool existsAt(String path) => _existsAt(File(path));

  /// 这个路径是不是**缓存目录里的**文件。
  ///
  /// 播放层报过来的「正在听的那一份」有可能不是缓存:下过的曲子直接播
  /// `Nordic/Music` 里那份,不写缓存(见 [markPlaying] 的 [playingPath])。
  /// 那种文件不该按缓存这套规则去动(mtime 就是缓存自己的 LRU 记账)。
  bool _isInCache(File file) {
    final root = _root;
    if (root == null) return false;
    return file.path.startsWith(
      '${root.path}${Platform.pathSeparator}',
    );
  }

  /// 缓存文件的位置。**纯算**:曲目 id + 档位 → 路径,不必问索引。
  ///
  /// 名字里带 id 是为了排查时看得懂(哪一份是谁),后缀是哈希 ——
  /// 洗过的 id 可能撞车(`a/b` 与 `a_b` 洗完一样),而撞车等于两首歌
  /// 互相覆盖对方那份缓存。转码档位进哈希:换档位就是换一份音频。
  File _slotFor(Song song, {required String qualityId, String? format}) {
    final key = '$qualityId|${song.id}|$format';
    final hit = _slotMemo[key];
    if (hit != null) return hit;

    final id = sanitizeFileName(song.id, maxLength: 40, fallback: '曲目');
    final digest = sha1
        .convert(utf8.encode('$qualityId|${song.id}'))
        .toString()
        .substring(0, 8);
    // 原音档没有 format —— 那就跟服务器的原文件一个后缀。两种情况都算不出来
    // (服务器没报后缀)时索性不带后缀:交给解码器自己嗅探,别安一个错的。
    final ext = audioExtensionOf(format ?? song.suffix);
    final base = '$id-$digest';
    final file = File('${_root!.path}${Platform.pathSeparator}'
        '${ext.isEmpty ? base : '$base.$ext'}');

    // 满了整体清掉:备忘录多算一遍只是慢一点,记错才是问题。
    if (_slotMemo.length >= _slotMemoLimit) _slotMemo.clear();
    _slotMemo[key] = file;
    return file;
  }

  /// 扫一遍目录:清理没主的半截文件,数出占用与文件数,并把
  /// 「(最后一次动过的时间, 文件)」这一列**一并带回去**。
  ///
  /// 两件事一趟做完是有原因的:淘汰要按 mtime 从旧到新排,而那是**同一次 stat**
  /// 就能拿到的东西 —— 分两趟(先数占用、再按时间排)等于把整个目录 stat 两遍,
  /// 而这一趟原先只在「占用超了上限」时才会真的开始删。
  ///
  /// 目录读不动时当作空缓存(数字不该算错),`.part` 与 `.mime` 都不算进占用:
  /// 前者还没写完,后者只是几字节的旁注。
  Future<List<(DateTime, File)>> _scan() async {
    final root = _root;
    if (root == null) return const [];

    var used = 0;
    var count = 0;
    final staleBefore = DateTime.now().subtract(stalePartialAge);
    final stamped = <(DateTime, File)>[];

    try {
      await for (final item in root.list(followLinks: false)) {
        if (item is! File) continue;
        if (item.path.endsWith(_partialSuffix)) {
          await _deleteStalePartial(item, staleBefore);
          continue;
        }
        // `.mime` 是几字节的旁注文件,不算进占用 —— 用户看到的数字
        // 该是他能听的东西占了多少。
        if (item.path.endsWith(_mimeSuffix)) continue;
        try {
          final stat = item.statSync();
          used += stat.size;
          count++;
          stamped.add((stat.modified, item));
        } catch (_) {
          // 正好被删掉了(另一条线在淘汰),跳过就是了。
        }
      }
    } catch (_) {
      // 目录读不动:当作空缓存,别把数字算错。
    }

    _lastScanAt = DateTime.now();
    _needsRescan = false;
    // 这一趟把整个目录都 stat 过了:备忘录**整表清掉,再用这趟扫到的回填**
    // (进来的都是完整文件 —— `.part` 上面就跳过了)。于是淘汰之后那份账
    // 立刻是对的,不必等下一次查询重新问盘。
    _forgetAll();
    for (final (_, file) in stamped) {
      _existsMemo[file.path] = true;
    }
    // **只在数字真的变了的时候播报。** 这一趟挂在每次换歌的淘汰上
    // (见 [markPlaying]),而 `AppState` 把这个通知转发给了全应用
    // (`app_state.dart`)—— 无条件播报等于让每一屏跟着每一次切歌重建一遍,
    // 哪怕占用一个字节都没动。
    final changed = used != _usedBytes || count != _fileCount;
    _usedBytes = used;
    _fileCount = count;
    if (changed) notifyListeners();
    return stamped;
  }

  /// 按「最久没动过」从旧到新删,直到占用回到上限之下。
  ///
  /// 正在听的那一份永远跳过 —— 删掉正在放的文件的字节流,音就断了。
  Future<int> _evict(List<(DateTime, File)> stamped) async {
    stamped.sort((a, b) => a.$1.compareTo(b.$1));
    var freed = 0;
    for (final (_, file) in stamped) {
      if (_usedBytes <= _limitBytes) break;
      if (file.path == _playingPath) continue;
      freed += await _delete(file);
    }
    return freed;
  }

  /// 删一份缓存(连同它的 `.mime` 旁注),返回释放的字节数。
  ///
  /// [notify] 关掉是给批量删除用的:一次清空几百份,每份播报一次会让
  /// 界面重建几百次。批量那头删完自己播报一次。
  Future<int> _delete(File file, {bool notify = true}) async {
    var freed = 0;
    try {
      freed = await file.length();
    } catch (_) {
      // 量不到就算了,它反正要没了。
    }
    await _deleteQuietly(file);
    _forget(file);

    final mime = File('${file.path}$_mimeSuffix');
    if (mime.existsSync()) await _deleteQuietly(mime);

    _usedBytes -= freed;
    if (_usedBytes < 0) _usedBytes = 0;
    _fileCount--;
    if (_fileCount < 0) _fileCount = 0;
    if (freed > 0 && notify) notifyListeners();
    return freed;
  }

  /// 清掉所有完整的缓存文件,返回释放的字节数。
  ///
  /// 正在写的半截文件不动 —— 删它会让这次播放的收尾(下完改名)落到一个
  /// 不存在的路径上,而那一头是 just_audio 的内部逻辑,报错只在日志里。
  Future<int> _deleteAll({
    bool keepPlaying = true,
    List<(DateTime, File)>? stamped,
  }) async {
    final root = _root;
    if (root == null) return 0;

    var freed = 0;
    final playingPath = _playingPath;
    // 调用方刚数过就直接用那份,没数过就自己数一遍 —— 清空是用户点的动作,
    // 多一趟扫描无所谓,数字不准才是问题。
    final files = stamped ?? await _scan();
    files.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, file) in files) {
      if (keepPlaying && file.path == playingPath) continue;
      freed += await _delete(file, notify: false);
    }
    // 逐份播报过了,这里统一播一次;顺带把占用重新对一遍账
    // (删不掉的、刚冒出来的半截文件都在这一趟里归位)。
    await _scan();
    return freed;
  }

  Future<void> _deleteStalePartial(File file, DateTime before) async {
    try {
      final modified = file.statSync().modified;
      if (modified.isBefore(before)) await _deleteQuietly(file);
    } catch (_) {
      // 正在写的那一份量不到/删不掉都很正常,放它一马。
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // 删不掉(还有进程占着 / 权限诡异)也只是留着占地方,
      // 下一次淘汰还会再试。
    }
  }
}
