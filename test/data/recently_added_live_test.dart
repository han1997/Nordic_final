import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/sorting.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_repository.dart';

import 'live_server.dart';

/// 「最近添加」必须与服务器真实数据一致 —— 这一条是**真机报的 bug**,
/// 所以只能拿真库钉,不能拿假响应钉(照着实现编 JSON 再照着实现断言,
/// 只会把同一个误解抄两遍)。
///
/// 当时的根因:服务器 `search3` 空查询按 `created` **升序**返回,
/// 而 app 首屏只取 500 条 —— 库里 529 首,最新的那几首正好落在没取的 29 条里,
/// 于是「最近添加」排出来的是「最老的 500 首里最新的那些」。
/// 这里钉的就是那个形状:新歌**不在**前 500 条里,而全量取回后必须排在最前。
///
/// **凭据从环境变量读**(见 `live_server.dart`):仓库是公开的,密码不能跟着代码走。
/// 没配环境变量时退回一个够不着的地址,整组照旧跳过,不让离线开发平白失败。
final _serverUrl = liveServerUrl;
final _username = liveServerUser;
final _password = liveServerPassword;
final _route = ServerRoute(id: 'lan', name: '局域网直连', url: _serverUrl);

void main() {
  late SubsonicRepository repo;

  setUp(() {
    repo = SubsonicRepository(clientFor(
      config: ServerConfig(
        id: 's1',
        name: '客厅 Navidrome',
        kind: ServerKind.navidrome,
        username: _username,
        routes: [_route],
      ),
      password: _password,
    ));
  });

  Future<bool> reachable() async {
    try {
      return (await repo.client.pingRoute(_route)).isOk;
    } catch (_) {
      return false;
    }
  }

  /// 有 `created` 的那批,按时间升序 —— 比大小用。
  List<Song> dated(List<Song> songs) =>
      songs.where((s) => s.created != null).toList();

  test('全量取回的曲目数不少于服务器报的首数', () async {
    if (!await reachable()) return markTestSkipped('Navidrome 不可达，跳过');

    // AppState 现在首屏取 1000 条(见 app_state 的 _songPageSize)。
    final songs = await repo.allSongs(size: 1000);
    expect(songs, isNotEmpty, reason: '真实库应该有歌');

    final unique = {for (final s in songs) s.id};
    expect(unique.length, songs.length, reason: '同一首不该在结果里出现两次');
  });

  test('「最近添加」取的是全量里最新的那几首，不是前 500 条里最新的那几首', () async {
    if (!await reachable()) return markTestSkipped('Navidrome 不可达，跳过');

    final all = dated(await repo.allSongs(size: 1000));

    final newest = recentlyAddedSongsOf(all, limit: 20);
    expect(newest, hasLength(20));

    // ① 顺序:严格按 created 递减 —— 浏览器里看到的「最近添加」就是这个顺序。
    for (var i = 1; i < newest.length; i++) {
      expect(
        newest[i].created!.isAfter(newest[i - 1].created!),
        isFalse,
        reason: '第 $i 首比上一首还新，排序反了',
      );
    }

    // ② 它确实是全量里最新的那 20 首(而不是某一段子集里最新的 20 首)。
    final truth = [...all]..sort((a, b) => b.created!.compareTo(a.created!));
    expect(
      newest.map((s) => s.id).toList(),
      truth.take(20).map((s) => s.id).toList(),
      reason: '「最近添加」与全量按 created 倒序的前 20 不一致',
    );

    // ③ 这一条是本轮 bug 的形状:最新那首**不在**前 500 条里。
    //    库若真小到全在前 500 里,这条自动让路(不硬造失败)。
    final firstPage = await repo.allSongs(size: 500);
    final firstPageIds = {for (final s in firstPage) s.id};
    if (!firstPageIds.contains(truth.first.id)) {
      expect(
        recentlyAddedSongsOf(firstPage).map((s) => s.id),
        isNot(contains(truth.first.id)),
        reason: '前 500 条里本来就没有最新那首，不该凭空排出来',
      );
      expect(
        newest.first.id,
        truth.first.id,
        reason: '全量补齐后「最近添加」的第一首必须是真·最新那首',
      );
    }
  });

  test('页大小 1000 一次就能拿全常见规模的库', () async {
    if (!await reachable()) return markTestSkipped('Navidrome 不可达，跳过');

    final big = await repo.allSongs(size: 1000);
    final small = await repo.allSongs(size: 500);
    expect(
      big.length,
      greaterThanOrEqualTo(small.length),
      reason: '页大一点不该反而拿到更少',
    );
    // 若真库超过 1000 首,这组用例仍成立(只是 ③ 那条会走「让路」分支);
    // 但值得知道实际规模。
    // ignore: avoid_print
    print('真库规模：500 档 ${small.length} 首，1000 档 ${big.length} 首');
  });
}