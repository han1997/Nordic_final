import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'download_store.dart';
import 'models.dart';
import 'network_status.dart';
import 'subsonic_repository.dart';

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
        id: 'dl-album-${album.id}',
        name: album.name,
        detail: '${songs.length} 首 · 整张',
        songs: songs,
        coverArtId: album.coverArtId,
      );

  /// 一位艺人的全部歌曲(调用方负责把曲子找齐)。
  factory DownloadRequest.artist(Artist artist, List<Song> songs) =>
      DownloadRequest(
        id: 'dl-artist-${artist.id}',
        name: artist.name,
        detail: '${songs.length} 首 · 这位艺人',
        songs: songs,
        coverArtId: artist.coverArtId,
      );

  /// 单曲。
  factory DownloadRequest.song(Song song) => DownloadRequest(
        id: 'dl-song-${song.id}',
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
typedef TransferFn = Future<TransferResult> Function({
  required Uri uri,
  required String savePath,
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
        DownloadState.failed => '下载失败:${error ?? '原因不明'}',
        _ => '已加入下载队列',
      };
}

/// 下载管理器:排队、门控、续传、落盘登记。
///
/// 与 [SubsonicRepository] 的关系和播放器一样 —— 它每次现取仓库,
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

  final SubsonicRepository? Function() _repository;
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

  List<DownloadJob> get jobs => List.unmodifiable(_jobs);

  int get activeCount => _jobs.where((j) => j.isActive).length;

  /// 这首歌是不是已经在本机。播放层靠它决定走本地还是走网络。
  bool isDownloaded(String songId) => _store.localPathFor(songId) != null;

  DownloadStore get store => _store;

  /// 入队。[request] 已经入过队(或已在本地)就不重复排 —— 返回既有的那条,
  /// 界面据此说「已经在本地了」而不是「已加入队列」。
  Future<DownloadJob> enqueue(DownloadRequest request) async {
    if (!_store.isAvailable) {
      throw const DownloadFailure('本机找不到可写的目录,没法保存下载内容');
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
      // 上一次可能被系统杀掉进程,留下半截的 .part。续传只认完整的文件,
      // 这些既不参与续传又占地方 —— 开工前先清掉。
      await for (final leftover in dir.list()) {
        if (leftover is File && leftover.path.endsWith('.part')) {
          await leftover.delete();
        }
      }

      var completedBytes = 0;
      final files = <String, String>{};

      for (var i = 0; i < job.request.songs.length; i++) {
        final song = job.request.songs[i];
        final name = DownloadStore.trackFileName(i, song);
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        final relative = '${job.request.id}/$name';

        // 续传:上一次中断前已经落盘的那几首不重下。
        // 半截的文件不在这里 —— 它们写的是 .part,失败时已被清掉。
        if (file.existsSync() && file.lengthSync() > 0) {
          final size = file.lengthSync();
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
        cover: cover,
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
    required SubsonicRepository repo,
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
      try {
        final result = await _doTransfer(
          uri: uri,
          savePath: file.path,
          cancelToken: cancel,
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
          await repo.client.pingAll();
          continue;
        }
        throw DownloadFailure('『${song.title}』${e.message}', network: e.network);
      }
    }
  }

  /// 封面单独取一张,整项共用。**下不到不算失败** ——
  /// 封面是锦上添花,为它把一整张专辑判成失败不划算。
  Future<String?> _fetchCover(
    SubsonicRepository repo,
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
      );
      final ext = _imageExtension(result.contentType);
      final name = 'cover.$ext';
      final target = File('${dir.path}${Platform.pathSeparator}$name');
      if (target.existsSync()) target.deleteSync();
      await File(temp).rename(target.path);
      return '${job.request.id}/$name';
    } catch (_) {
      final tempFile = File(temp);
      if (tempFile.existsSync()) tempFile.deleteSync();
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

    if (next < 100 && (next - job.pct).abs() < 0.5) return;
    job.pct = next;
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

  // ---------------- 传输 ----------------

  Future<TransferResult> _doTransfer({
    required Uri uri,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    final transfer = _transfer;
    if (transfer != null) {
      return transfer(
        uri: uri,
        savePath: savePath,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    return _dioTransfer(
      uri: uri,
      savePath: savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 真下载。先写 `.part` 再改名 —— 文件管理器与播放器都只会看到完整的文件。
  Future<TransferResult> _dioTransfer({
    required Uri uri,
    required String savePath,
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

    final tempPath = '$savePath.part';
    Response<dynamic> response;
    try {
      response = await dio.downloadUri(
        uri,
        tempPath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        // 失败时把半截文件删掉:留下的 .part 对任何一方都没有意义。
        deleteOnError: true,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw DownloadFailure(_describe(e), network: _isNetworkFailure(e));
    }

    final status = response.statusCode ?? 0;
    if (status != 200) {
      throw DownloadFailure('服务器返回 HTTP $status');
    }

    final contentType = response.headers.value(Headers.contentTypeHeader);
    if (_looksLikeErrorBody(contentType)) {
      // Subsonic 出错时**照样回 200**,错误在响应体里。若不当心,
      // 一个几百字节的 JSON 会被当成音频存下来 —— 「下载完成」就是假的。
      final message = await _readErrorMessage(tempPath);
      _deleteQuietly(tempPath);
      throw DownloadFailure(message);
    }

    final temp = File(tempPath);
    if (!temp.existsSync()) {
      throw const DownloadFailure('服务器没有返回内容');
    }
    final target = File(savePath);
    if (target.existsSync()) target.deleteSync();
    await temp.rename(savePath);
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
    if (_isNetworkFailure(e)) return '连接失败,检查网络或线路';
    return '下载中断:${e.message ?? e.type.name}';
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
