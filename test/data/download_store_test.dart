import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/models.dart';

/// 下载内容的落盘处。
///
/// 这里全用临时目录当根 —— [DownloadStore.open] 特意留了 `root` 参数,
/// 就是为了让「索引怎么存、路径怎么还原、删的时候删掉了什么」能直接验,
/// 不必去碰真实的平台目录。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nordic-dl-store');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Song song(String id, {String title = '曲目', String? suffix = 'flac'}) => Song(
        id: id,
        title: title,
        artist: '艺人',
        album: '专辑',
        albumId: 'al-1',
        suffix: suffix,
      );

  /// 造一个「已经下好」的现场:目录、文件、索引记录齐全。
  Future<(DownloadStore, File)> givenDownloaded() async {
    final store = await DownloadStore.open(root: root);
    final dir = await store.directoryFor('dl-album-al-1');
    final file = File('${dir.path}${Platform.pathSeparator}01 - 曲目.flac');
    await file.writeAsBytes([1, 2, 3, 4]);

    await store.add(DownloadRecord(
      id: 'dl-album-al-1',
      name: '专辑',
      detail: '1 首 · 整张',
      format: 'FLAC',
      bytes: 4,
      files: {'s1': 'dl-album-al-1/01 - 曲目.flac'},
      cover: 'dl-album-al-1/cover.jpg',
      completedAt: DateTime(2026, 10, 16),
    ));
    return (store, file);
  }

  test('登记一条下载后,播放层能按曲目 id 找到文件', () async {
    final (store, file) = await givenDownloaded();

    expect(store.isAvailable, isTrue);
    expect(store.localPathFor('s1'), file.path);
    expect(store.localPathFor('没下过的曲子'), isNull);
    expect(store.coverPathForSong('s1'),
        '${root.path}${Platform.pathSeparator}dl-album-al-1'
        '${Platform.pathSeparator}cover.jpg');
  });

  test('重开一次记录还在 —— 存的是相对路径,换根目录也还原得出来', () async {
    await givenDownloaded();

    // 另一块「根」,里面摆同样的相对结构 —— 模拟重装 / 换设备路径。
    final moved = await Directory.systemTemp.createTemp('nordic-dl-moved');
    addTearDown(() => moved.deleteSync(recursive: true));
    final dir = Directory('${moved.path}${Platform.pathSeparator}dl-album-al-1')
      ..createSync(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}01 - 曲目.flac')
        .writeAsBytes([1, 2, 3, 4]);
    File('${root.path}${Platform.pathSeparator}index.json')
        .copySync('${moved.path}${Platform.pathSeparator}index.json');

    final reopened = await DownloadStore.open(root: moved);
    expect(reopened.records.single.id, 'dl-album-al-1');
    expect(reopened.localPathFor('s1'),
        '${dir.path}${Platform.pathSeparator}01 - 曲目.flac');
  });

  test('删掉一条任务会把它在本机的文件一起删掉', () async {
    final (store, file) = await givenDownloaded();

    await store.remove('dl-album-al-1');

    expect(store.localPathFor('s1'), isNull);
    expect(store.records, isEmpty);
    // 留着一堆没主的音乐文件不是用户按「删掉」时想要的结果。
    expect(file.existsSync(), isFalse);
    expect(file.parent.existsSync(), isFalse);

    // 索引也要落盘 —— 重开一次仍然是空的。
    final reopened = await DownloadStore.open(root: root);
    expect(reopened.records, isEmpty);
  });

  test('索引坏了当作没下过,但不动磁盘上的文件', () async {
    final (_, file) = await givenDownloaded();
    await File('${root.path}${Platform.pathSeparator}index.json')
        .writeAsString('{ 这不是 json');

    final store = await DownloadStore.open(root: root);

    expect(store.records, isEmpty);
    // 记录可以重建,删错的文件回不来 —— 宁可让用户重下一次。
    expect(file.existsSync(), isTrue);
  });

  test('文件名挡掉路径分隔符 —— 一个斜杠就能把文件写到别的目录去', () {
    expect(
      DownloadStore.trackFileName(0, song('s1', title: 'A/B:C*D?')),
      '01 - A_B_C_D_.flac',
    );
    expect(
      DownloadStore.trackFileName(9, song('s2', title: ' 多  空格 ')),
      '10 - 多 空格.flac',
    );
  });

  test('标题为空时给个占位名,不拼出「01 - .flac」', () {
    expect(DownloadStore.trackFileName(0, song('s1', title: '   ')),
        '01 - 未命名.flac');
  });

  test('没有后缀的曲目不硬安一个扩展名', () {
    // 安错扩展名会让解码器按错格式去解;交给它自己嗅探更稳。
    expect(
      DownloadStore.trackFileName(0, song('s1', title: '曲目', suffix: null)),
      '01 - 曲目',
    );
  });

  test('根目录不可用时如实报「用不了」,而不是抛异常', () async {
    final blocked = File('${root.path}${Platform.pathSeparator}blocked');
    await blocked.writeAsString('占位');

    // 拿一个「不是目录」的路径当根 —— 建目录必然失败。
    final store = await DownloadStore.open(root: Directory(blocked.path));

    expect(store.isAvailable, isFalse);
    expect(store.records, isEmpty);
  });
}
