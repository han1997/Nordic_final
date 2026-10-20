import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'download_store.dart';
import 'iterables.dart';
import 'models.dart';
import 'music_source.dart';
import 'network_status.dart';

/// 一次下载请求 —— 界面发起,管理器接手。
///
/// [id] 是**幂等键**:同一张专辑点两次不会排出两条任务,重试也是同一个 id
/// (续传要按 id 找上次落下的文件)。id 同时是磁盘上的目录名。
@immutable
class DownloadRequest {
  const DownloadRequest({
    required this.id,
    required this.name,
    required this.detail,
    required this.songs,
    this.coverArtId,
  });

  /// 整张专辑。
  factory DownloadRequest.album(Album album, List<Song> songs) =>
      DownloadRequest(
        id: DownloadStore.albumTaskId(album.id),
        name: album.name,
        detail: '${songs.length} 首 · 整张',
        songs: songs,
        coverArtId: album.coverArtId,
      );

  /// 一位艺人的全部歌曲(调用方负责把曲子找齐)。
  factory DownloadRequest.artist(Artist artist, List<Song> songs) =>
      DownloadRequest(
        id: DownloadStore.artistTaskId(artist.id),
        name: artist.name,
        detail: '${songs.length} 首 · 这位艺人',
        songs: songs,
        coverArtId: artist.coverArtId,
      );

  /// 单曲。
  factory DownloadRequest.song(Song song) => DownloadRequest(
        id: DownloadStore.songTaskId(song.id),
        name: song.title,
        detail: '${song.artist} · 单曲',
        songs: [song],
        coverArtId: song.coverArtId,
      );

  final String id;
  final String name;
  final String detail;
  final List<Song> songs;
  final String? coverArtId;
}

/// 下载任务的状态。
enum DownloadState {
  queued('排队中'),
  waitingWifi('等待 Wi-Fi'),
  waitingNetwork('等待网络'),
  active('下载中'),
  done('已完成'),
  failed('失败');

  const DownloadState(this.label);

  final String label;

  /// 卡在等条件,不是卡在等用户。
  bool get isWaiting => this == waitingWifi || this == waitingNetwork;
}

/// 下载失败。
///
/// [network] 区分「这条线路不通」与「服务器就是不给」(文件不存在、
/// 权限不够)。只有前者值得换线路重试 —— 换条线也解不开的错误重试
/// 只是白等一轮。
class DownloadFailure implements Exception {
  const DownloadFailure(this.message, {this.network = false});

  final String message;
  final bool network;

  @override
  String toString() => message;
}

/// 下载一层能拿回的东西。
@immutable
class TransferResult {
  const TransferResult({
    required this.bytes,
    this.statusCode = 200,
    this.contentType,
  });

  final int bytes;
  final int statusCode;
  final String? contentType;
}

/// 真正把字节搬到磁盘的那一层。
///
/// 抽成可注入的函数,是为了让排队 / 门控 / 续传 / 状态这些**管理器自己的
/// 逻辑**能脱离网络单测 —— 那些才是容易写错的部分。
///
/// [resumeFrom] 是「这首歌的半截 `.part` 里已经有几个字节」。实现要么从那个
/// 偏移接着写,要么在服务器不认 `Range` 时**截断重来** —— 但绝不能把整段接在
/// 半截后面,那会让文件前段重复、整首损坏(而它不响:播放器照放)。
///
/// [onProgress] 是**累计口径**:`received` 含 `resumeFrom`,`total` 是这一首的
/// 全长(不知道时为 -1)。调用方直接拿它算进度,不必自己再加偏移 —— 加了会在
/// 「服务器不认 Range、从头重来」那一步多算一次。
typedef TransferFn = Future<TransferResult> Function({
  required Uri uri,
  required String savePath,
  required int resumeFrom,
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
});

/// 一条下载任务。
class DownloadJob {
  DownloadJob({
    required this.request,
    this.state = DownloadState.queued,
    this.pct = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.doneSongs = 0,
    this.error,
    this.record,
  });

  DownloadJob.fromRecord(DownloadRecord record)
      : this(
          request: DownloadRequest(
            id: record.id,
            name: record.name,
            detail: record.detail,
            songs: const [],
            coverArtId: null,
          ),
          state: DownloadState.done,
          pct: 100,
          receivedBytes: record.bytes,
          totalBytes: record.bytes,
          doneSongs: record.files.length,
          record: record,
        );

  final DownloadRequest request;

  DownloadState state;

  /// 0–100。
  double pct;

  /// 本次任务已经落盘的字节数(含正在下那一首的部分)。
  int receivedBytes;

  /// 服务器报的总字节数。**为 0 表示不知道** —— 界面这时改按曲目数显示,
  /// 不要拿一个猜出来的体积冒充。
  int totalBytes;

  /// 已完成的曲目数。
  int doneSongs;

  /// 失败原因。非空时界面要显示它,而不是空态。
  String? error;

  /// 完成后登记的记录。重启后从索引恢复的任务也有它。
  DownloadRecord? record;

  /// 管理器内部用:取消正在下的一首。
  CancelToken? cancelToken;

  /// 上一次把进度播报出去的时刻 —— 用来限流(`_report`)。
  DateTime lastReportedAt = DateTime.fromMillisecondsSinceEpoch(0);

  int get songCount =>
      request.songs.isNotEmpty ? request.songs.length : doneSongs;

  bool get isDone => state == DownloadState.done;

  bool get isActive => state == DownloadState.active;

  /// 体积文案。不知道体积时为空串 —— 由界面改讲「3/12 首」。
  String get sizeLabel => totalBytes > 0
      ? '${(totalBytes / (1024 * 1024)).round()} MB'
      : '';

  /// 行里的第二行。**状态在这里落成文案**,界面只管排版。
  String get statusLine {
    switch (state) {
      case DownloadState.done:
        final type = record?.format.isNotEmpty == true
            ? record!.format
            : _formatOf(request.songs);
        final bytes = record?.bytes ?? receivedBytes;
        return '已完成 · $type · ${(bytes / (1024 * 1024)).round()} MB';
      case DownloadState.failed:
        return '失败 · ${error ?? '原因不明'}';
      case DownloadState.queued:
        return sizeLabel.isEmpty ? '排队中 · $songCount 首' : '排队中 · $sizeLabel';
      case DownloadState.waitingWifi:
      case DownloadState.waitingNetwork:
        return '${state.label}后开始 · $songCount 首';
      case DownloadState.active:
        // 知道体积就报体积(用户关心的是还剩多少流量),
        // 不知道才退回进度百分比 —— 后者不带单位,不如前者的信息量大。
        return sizeLabel.isEmpty
            ? '$doneSongs/$songCount 首 · ${pct.round()}%'
            : '$sizeLabel · ${pct.round()}%';
    }
  }

  static String _formatOf(List<Song> songs) =>
      songs.isEmpty ? '音频' : (songs.first.suffix?.toUpperCase() ?? '音频');

  /// 刚点完下载按钮时该说的话。
  ///
  /// 放在这里而不是各调用点:专辑页、艺人页、歌曲菜单三个入口做的是同一件事,
  /// 措辞不该因为入口不同而不同(尤其是「等待 Wi-Fi」这种状态,
  /// 用户得知道按钮没失灵)。
  String get queuedNotice => switch (state) {
        DownloadState.done => '这项已经在本机了',
        DownloadState.waitingWifi => '等待 Wi-Fi 后开始下载',
        DownloadState.waitingNetwork => '等网络恢复后开始下载',
        DownloadState.failed => '下载失败：${error ?? '原因不明'}',
        _ => '已加入下载队列',
      };
}

/// 下载管理器:排队、门控、续传、落盘登记。
///
/// 与 [MusicSource] 的关系和播放器一样 —— 它每次现取仓库,
/// 因为服务器配置可以在运行中变(改地址、换账号、移除服务器)。
///
/// **顺序下**:同一时刻只有一条任务在跑。并行拉多条任务看着热闹,
/// 但在手机上只会让每条都慢,还让「预计剩余」这类信息彻底失真。
/// 排在后面的任务状态是「排队中」,不是「下载中」。
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this._repository,
    required DownloadStore store,
    required this._wifiOnly,
    NetworkProbe? probe,
    this._transfer,
    this._dio,
    this.checkInterval = const Duration(seconds: 4),
  })  : _store = store,
        _probe = probe ?? NetworkProbe() {
    // 上次运行下好的东西要在「下载管理」里还在,否则用户会以为丢了。
    for (final record in store.records) {
      _jobs.add(DownloadJob.fromRecord(record));
    }
  }

  final MusicSource? Function() _repository;
  final DownloadStore _store;
  final bool Function() _wifiOnly;
  final NetworkProbe _probe;
  final TransferFn? _transfer;

  /// 真下载用的客户端。测试可以塞一个假 Dio 进来 —— 传输层里
  /// 「服务器回 200 但内容是错误 JSON」那条判断值得单独验。
  Dio? _dio;

  /// 卡在等网络时的复查间隔。
  final Duration checkInterval;

  final List<DownloadJob> _jobs = [];
  String? _runningId;
  Timer? _retryTimer;

  List<DownloadJob> get jobs => UnmodifiableListView(_jobs);

  int get activeCount => _jobs.where((j) => j.isActive).length;

  /// 这首歌是不是已经在本机。播放层靠它决定走本地还是走网络。
  bool isDownloaded(String songId) => _store.localPathFor(songId) != null;

  /// 这张封面在本机的路径(下过才有)。界面上的封面优先用它。
  String? coverPathForArt(String? coverArtId) =>
      _store.coverPathForArt(coverArtId);

  DownloadStore get store => _store;

  /// 入队。[request] 已经入过队(或已在本地)就不重复排 —— 返回既有的那条,
  /// 界面据此说「已经在本地了」而不是「已加入队列」。
  Future<DownloadJob> enqueue(DownloadRequest request) async {
    if (!_store.isAvailable) {
      throw const DownloadFailure('本机找不到可写的目录，没法保存下载内容');
    }

    final existing = _jobs.where((j) => j.request.id == request.id).firstOrNull;
    if (existing != null) {
      if (existing.state == DownloadState.failed) await retry(request.id);
      return existing;
    }

    final job = DownloadJob(
      request: request,
      totalBytes: _knownTotal(request.songs),
    );
    _jobs.add(job);
    notifyListeners();
    unawaited(_pump());
    return job;
  }

  /// 删掉一条任务。**连同它在磁盘上的文件** —— 见 [DownloadStore.remove]。
  Future<void> remove(String id) async {
    final job = _jobs.where((j) => j.request.id == id).firstOrNull;
    if (job == null) return;

    job.cancelToken?.cancel('用户取消了这条下载');
    _jobs.remove(job);
    if (_runningId == id) _runningId = null;
    notifyListeners();

    await _store.remove(id);
    unawaited(_pump());
  }

  /// 重试失败的任务。已经下好的曲子会被跳过(见 [_run] 的续传)。
  Future<void> retry(String id) async {
    final job = _jobs.where((j) => j.request.id == id).firstOrNull;
    if (job == null || job.isActive || job.isDone) return;
    job
      ..state = DownloadState.queued
      ..error = null
      ..pct = 0
      ..doneSongs = 0
      ..receivedBytes = 0;
    notifyListeners();
    await _pump();
  }

  /// 用户在设置里动了「仅 Wi-Fi 下载」—— 门控条件变了,重新算一次。
  Future<void> onWifiOnlyChanged() => _pump();

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  // ---------------- 调度 ----------------

  /// 推进一步:没有任务在跑时,挑一条能跑的起来。
  Future<void> _pump() async {
    if (_runningId != null) return;

    final next = _jobs.where((j) => j.state == DownloadState.queued).firstOrNull ??
        _jobs.where((j) => j.state.isWaiting).firstOrNull;
    if (next == null) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }

    // **先占位再问网络**。问网络是异步的,而等待期间复查定时器可能再次
    // 触发 _pump;两次都通过上面那道「没有任务在跑」的检查,同一条任务
    // 就会被跑两遍(两个流写同一个文件)。
    _runningId = next.request.id;

    final blocked = _blockedBy(await _probe.status());
    if (blocked != null) {
      // 条件不满足就如实说在等什么,而不是假装在下载。
      _runningId = null;
      if (next.state != blocked) {
        next.state = blocked;
        notifyListeners();
      }
      _retryTimer ??= Timer.periodic(checkInterval, (_) => unawaited(_pump()));
      return;
    }

    await _run(next);
  }

  /// 现在能不能开始下载。返回非空表示要停在哪个等待态。
  DownloadState? _blockedBy(NetworkStatus status) {
    if (!status.canTransfer) return DownloadState.waitingNetwork;
    // 计费连接上不下 —— 这正是「仅 Wi-Fi 下载」这句话的意思。
    if (_wifiOnly() && status == NetworkStatus.metered) {
      return DownloadState.waitingWifi;
    }
    return null;
  }

  /// 跑一条任务。进来时 [_pump] 已经把「在跑的是谁」占好了。
  Future<void> _run(DownloadJob job) async {
    final repo = _repository();
    if (repo == null) {
      // 没服务器就没法下载。说清原因之外还要把占位让出来 ——
      // 不然队列会一直卡在这条上,后面排着的任务永远轮不到。
      _fail(job, '还没有连接服务器');
      _runningId = null;
      unawaited(_pump());
      return;
    }

    final cancel = CancelToken();
    job
      ..state = DownloadState.active
      ..error = null
      ..cancelToken = cancel;
    notifyListeners();

    try {
      final dir = await _store.directoryFor(job.request.id);
      // **半截的 .part 留着** —— 它是这首歌的续传起点,不是垃圾:下一次(乃至
      // 下一次启动)从它的长度接着下(见 [_resumableFrom])。这里以前会把它们
      // 全清掉,于是「按曲目续传」就成了能拿到的最好结果。现在不作数的半截
      // 由传输层那几条判据处理(服务器不认 Range / Content-Range 对不上 →
      // 截断重来;硬失败 → 当场删掉,免得错误体被当成起点)。

      var completedBytes = 0;
      final files = <String, String>{};

      for (var i = 0; i < job.request.songs.length; i++) {
        final song = job.request.songs[i];
        final name = DownloadStore.trackFileName(i, song);
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        final relative = '${job.request.id}/$name';

        // 续传:上一次中断前已经落盘的那几首不重下。
        // 半截的不走这条 —— 它们写的是 .part,由下面那一路按字节接着下。
        if (file.existsSync() && file.lengthSync() > 0) {
          final size = file.lengthSync();
          // 这首已经整首在盘上了,旁边不该再躺一份半截:留着会被当成这首的
          // 续传起点,而它其实已经下完了。
          _deleteQuietly('${file.path}.part');
          _deleteQuietly('${file.path}.part.restart');
          completedBytes += size;
          files[song.id] = relative;
          _report(job, completedBytes, i + 1, 1);
          continue;
        }

        final bytes = await _fetchWithFailover(
          repo: repo,
          song: song,
          file: file,
          job: job,
          cancel: cancel,
          baseBytes: completedBytes,
          index: i,
        );
        completedBytes += bytes;
        files[song.id] = relative;
        _report(job, completedBytes, i + 1, 1);
      }

      final cover = await _fetchCover(repo, job, dir);
      final record = DownloadRecord(
        id: job.request.id,
        name: job.request.name,
        detail: job.request.detail,
        format: DownloadJob._formatOf(job.request.songs),
        bytes: completedBytes,
        files: files,
        // 曲目信息随身带一份:断网时下载管理里要能列出来点着播(见 DownloadRecord.tracks)。
        tracks: job.request.songs,
        cover: cover,
        coverArtId: job.request.coverArtId,
        completedAt: DateTime.now(),
      );
      await _store.add(record);

      job
        ..record = record
        ..state = DownloadState.done
        ..pct = 100
        ..receivedBytes = completedBytes
        ..totalBytes = completedBytes
        ..doneSongs = job.request.songs.length;
    } catch (e) {
      // 用户撤掉这条任务时,状态已经不需要改了 —— 它已经从列表里出去。
      if (cancel.isCancelled) return;
      _fail(job, e is DownloadFailure ? e.message : '$e');
    } finally {
      _runningId = null;
      job.cancelToken = null;
      notifyListeners();
      unawaited(_pump());
    }
  }

  /// 下一首。线路不通时换一条再试一次 —— 与浏览时的故障切换同一套语义。
  Future<int> _fetchWithFailover({
    required MusicSource repo,
    required Song song,
    required File file,
    required DownloadJob job,
    required CancelToken cancel,
    required int baseBytes,
    required int index,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final uri = repo.downloadUri(song.id);
      // 这首的半截 `.part` 是本次续传的起点。**每次尝试都重读一遍** —— 上一次
      // 失败前可能已经又多落了一些字节,而那正是该接着下的地方。
      final resumeFrom = _resumableFrom(file, song.sizeBytes);
      try {
        final result = await _doTransfer(
          uri: uri,
          savePath: file.path,
          resumeFrom: resumeFrom,
          expectedBytes: song.sizeBytes,
          cancelToken: cancel,
          // received 已是**累计口径**(含 resumeFrom,由传输层补上),这里不加
          // 偏移 —— 加了会在「服务器不认 Range、从头重来」那一步多算一遍。
          onProgress: (received, total) => _report(
            job,
            baseBytes + received,
            index,
            total > 0 ? received / total : 0.5,
          ),
        );
        return result.bytes;
      } on DownloadFailure catch (e) {
        if (cancel.isCancelled) rethrow;
        if (e.network && attempt < 2) {
          // 重新测速会把当前最快的那条线顶上来,下次拿到的就是它的地址。
          await repo.connection.pingAll();
          continue;
        }
        throw DownloadFailure('『${song.title}』${e.message}', network: e.network);
      }
    }
  }

  /// 封面单独取一张,整项共用。**下不到不算失败** ——
  /// 封面是锦上添花,为它把一整张专辑判成失败不划算。
  Future<String?> _fetchCover(
    MusicSource repo,
    DownloadJob job,
    Directory dir,
  ) async {
    final artId = job.request.coverArtId;
    if (artId == null || artId.isEmpty) return null;

    final temp = '${dir.path}${Platform.pathSeparator}cover.tmp';
    try {
      final result = await _doTransfer(
        uri: repo.coverUri(artId, size: 1024),
        savePath: temp,
        // 封面不续传:一张图几百 KB,重下一遍比维护它的半截划算。
        resumeFrom: 0,
      );
      final ext = _imageExtension(result.contentType);
      final name = 'cover.$ext';
      final target = File('${dir.path}${Platform.pathSeparator}$name');
      if (target.existsSync()) target.deleteSync();
      await File(temp).rename(target.path);
      return '${job.request.id}/$name';
    } catch (_) {
      _deleteQuietly(temp);
      _deleteQuietly('$temp.part');
      _deleteQuietly('$temp.part.restart');
      return null;
    }
  }

  void _fail(DownloadJob job, String message) {
    job
      ..state = DownloadState.failed
      ..error = message;
    notifyListeners();
  }

  /// 进度上报。**节流**:每收到一块数据就重绘会让整个下载页一直在抖,
  /// 而进度条上 0.5% 的差别肉眼看不出来。
  void _report(
    DownloadJob job,
    int receivedBytes,
    int doneSongs,
    double fraction,
  ) {
    job.receivedBytes = receivedBytes;
    job.doneSongs = doneSongs;

    final count = job.request.songs.isEmpty ? 1 : job.request.songs.length;
    final raw = job.totalBytes > 0
        ? receivedBytes / job.totalBytes * 100
        : (doneSongs + fraction) / count * 100;
    final next = raw.clamp(0.0, 100.0);

    // 两道闸:进度差不到 0.5% 不重绘,而且**每秒最多四次**。
    // 只看百分比是不够的:局域网上下得飞快,一块 0.5% 就是十几毫秒一次,
    // 而每次通知都会让盯着下载状态的界面跟着重建。
    final now = DateTime.now();
    final tooSoon = next < 100 &&
        now.difference(job.lastReportedAt) < const Duration(milliseconds: 250);
    final tooSmall = next < 100 && (next - job.pct).abs() < 0.5;
    if (tooSoon || tooSmall) return;

    job.pct = next;
    job.lastReportedAt = now;
    notifyListeners();
  }

  /// 服务器报的总量。**有任何一首没报就不给总量** ——
  /// 拿部分之和当总量会让进度条冲到 100% 之后继续爬。
  int _knownTotal(List<Song> songs) {
    if (songs.isEmpty) return 0;
    var total = 0;
    for (final song in songs) {
      final size = song.sizeBytes;
      if (size == null || size <= 0) return 0;
      total += size;
    }
    return total;
  }

  /// 一首曲子可用的**续传起点**(字节)。返回 0 表示从头下。
  ///
  /// **半截为空、或比整首还长,都当 0** —— 前者没什么可续;后者多半是服务器上
  /// 那份已经换过了,接着写会把两段来源不同的内容拼成一个坏文件,而坏文件不响
  /// (播放器照放)。宁可重下一遍。
  static int _resumableFrom(File target, int? expectedBytes) {
    final part = File('${target.path}.part');
    if (!part.existsSync()) return 0;
    final length = part.lengthSync();
    if (length <= 0) return 0;
    if (expectedBytes != null && expectedBytes > 0 && length >= expectedBytes) {
      return 0;
    }
    return length;
  }

  // ---------------- 传输 ----------------

  Future<TransferResult> _doTransfer({
    required Uri uri,
    required String savePath,
    required int resumeFrom,
    int? expectedBytes,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    final transfer = _transfer;
    if (transfer != null) {
      // 注入的那一层只用得上 resumeFrom;`expectedBytes` 是给真 dio 那条路
      // 校验 `Content-Range` 用的(见 [_parseContentRange])。
      return transfer(
        uri: uri,
        savePath: savePath,
        resumeFrom: resumeFrom,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    return _dioTransfer(
      uri: uri,
      savePath: savePath,
      resumeFrom: resumeFrom,
      expectedBytes: expectedBytes,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 真下载。先写 `.part` 再改名 —— 文件管理器与播放器都只会看到完整的文件。
  ///
  /// **续传**:`resumeFrom > 0` 时发 `Range: bytes=<n>-`,往 `.part` 后面接。
  /// 服务器不认 Range(回 200 而不是 206)或 `Content-Range` 对不上时**当场
  /// 截断重来** —— 把整段接在半截后面会让文件前段重复、整首损坏,而那不响。
  Future<TransferResult> _dioTransfer({
    required Uri uri,
    required String savePath,
    required int resumeFrom,
    int? expectedBytes,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dio = _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      // 一首歌可能上百 MB,而 dio 的接收超时管的是「两次数据之间」的间隔;
      // 给足容忍度,免得慢线上下到一半被判成超时。
      receiveTimeout: const Duration(seconds: 60),
      validateStatus: (_) => true,
    ));

    final partPath = '$savePath.part';
    // 「服务器无视了 Range」时另起一个**干净**文件,不去动已经写下的半截。
    final restartPath = '$savePath.part.restart';
    final resuming = resumeFrom > 0;
    var writtenPath = partPath;
    var offset = resuming ? resumeFrom : 0;

    // dio 先按响应头定文件名、再决定怎么开它(`File(await savePath(headers))`
    // 之后才 `openSync(mode:)`,见 dio_for_native.dart),所以这里能在**写盘
    // 之前**看清服务器认没认 Range —— 这是「换个文件从头写」能成立的原因。
    FutureOr<String> choosePath(Headers headers) {
      writtenPath = partPath;
      offset = 0;
      if (!resuming) return partPath;

      final range = _parseContentRange(headers.value('content-range'));
      final trusted = range != null &&
          range.start == resumeFrom &&
          (expectedBytes == null ||
              expectedBytes <= 0 ||
              range.total == null ||
              range.total == expectedBytes);
      if (trusted) {
        writtenPath = partPath;
        offset = resumeFrom;
        return partPath;
      }

      // 半截不可信:连旧的那份一起扔掉,换一个不存在的空文件从头写。
      // (append 模式打开一个刚建出来的空文件,就等于从 0 写。)
      _deleteQuietly(partPath);
      _deleteQuietly(restartPath);
      writtenPath = restartPath;
      return restartPath;
    }

    Response<dynamic> response;
    try {
      response = await dio.downloadUri(
        uri,
        choosePath,
        onReceiveProgress: (received, total) {
          // 换成**累计口径**:dio 的 received 只是这一次调用收到的字节,续传时
          // 不含半截里已有的那部分 —— 原样上报会让进度条先退再爬。
          onProgress?.call(offset + received, total > 0 ? offset + total : total);
        },
        cancelToken: cancelToken,
        // 半截**留着** —— 下一次(乃至下次启动)从它接着下,那才是续传的意思。
        // 真正不该留的那些由下面几处显式删掉。
        deleteOnError: false,
        fileAccessMode: resuming ? FileAccessMode.append : FileAccessMode.write,
        options:
            resuming ? Options(headers: {'Range': 'bytes=$resumeFrom-'}) : null,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw DownloadFailure(_describe(e), network: _isNetworkFailure(e));
    }

    final status = response.statusCode ?? 0;
    // 200 = 整段;206 = 从 resumeFrom 起的剩余段。**两个都要认** ——
    // 只认 200 会把每一次续传都判成失败。
    if (status != 200 && status != 206) {
      _deleteQuietly(writtenPath);
      throw DownloadFailure('服务器返回 HTTP $status');
    }

    final contentType = response.headers.value(Headers.contentTypeHeader);
    if (_looksLikeErrorBody(contentType)) {
      // Subsonic 出错时**照样回 200**,错误在响应体里。若不当心,
      // 一个几百字节的 JSON 会被当成音频存下来 —— 「下载完成」就是假的。
      // 206 同理一起挡,而且这份错误体必须删掉:留着它,下一次的续传起点
      // 就成了「错误信息」。
      final message = await _readErrorMessage(writtenPath);
      _deleteQuietly(writtenPath);
      throw DownloadFailure(message);
    }

    final written = File(writtenPath);
    if (!written.existsSync()) {
      throw const DownloadFailure('服务器没有返回内容');
    }
    final target = File(savePath);
    if (target.existsSync()) target.deleteSync();
    await written.rename(savePath);
    return TransferResult(
      bytes: await target.length(),
      statusCode: status,
      contentType: contentType,
    );
  }

  static bool _isNetworkFailure(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.connectionError =>
          true,
        _ => e.error is SocketException,
      };

  static String _describe(DioException e) {
    if (_isNetworkFailure(e)) return '连接失败，检查网络或线路';
    return '下载中断：${e.message ?? e.type.name}';
  }

  /// 从 `Content-Range: bytes <起点>-<末>/<总量>` 里取两头。总量写成 `*` 时为
  /// null(那种响应里服务器自己也没说整段有多大)。解析不出来就返回 null ——
  /// 调用方按「半截不可信」处理,也就是从头重下,这是安全的那一侧。
  static ({int start, int? total})? _parseContentRange(String? value) {
    if (value == null) return null;
    final match =
        RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)').firstMatch(value.trim());
    if (match == null) return null;
    final total = match.group(3)!;
    return (
      start: int.parse(match.group(1)!),
      total: total == '*' ? null : int.tryParse(total),
    );
  }

  static bool _looksLikeErrorBody(String? contentType) {
    if (contentType == null) return false;
    final lower = contentType.toLowerCase();
    // 音频永远不是 text/*,也永远不是 json / xml。
    return lower.startsWith('text/') ||
        lower.contains('json') ||
        lower.contains('xml');
  }

  /// 从错误响应体里抠一句能给用户看的话。
  static Future<String> _readErrorMessage(String path) async {
    final file = File(path);
    if (!file.existsSync()) return '服务器拒绝了这次下载';
    try {
      final body = (await file.readAsString()).trim();
      final json = _tryJson(body);
      if (json != null) {
        final error = json['subsonic-response']?['error']?['message'];
        if (error is String && error.isNotEmpty) return error;
      }
      return body.isEmpty ? '服务器拒绝了这次下载' : _truncate(body);
    } catch (_) {
      return '服务器拒绝了这次下载';
    }
  }

  static Map<String, dynamic>? _tryJson(String body) {
    if (!body.startsWith('{')) return null;
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _truncate(String text) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ');
    return oneLine.length <= 80 ? oneLine : '${oneLine.substring(0, 80)}…';
  }

  static void _deleteQuietly(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  /// 封面文件名带正确的后缀 —— 有些加载器按扩展名判 MIME,
  /// 一张 png 存成 `.jpg` 会解不出来。
  static String _imageExtension(String? contentType) {
    final lower = contentType?.toLowerCase() ?? '';
    if (lower.contains('png')) return 'png';
    if (lower.contains('webp')) return 'webp';
    if (lower.contains('gif')) return 'gif';
    return 'jpg';
  }
}
