import 'models.dart';

/// 播放队列的**形状与指纹** —— 队列同步那条路上两个纯函数,单独放一处是因为
/// **两侧都要用**:播放层拿它们决定「写什么回服务器」,
/// 状态层拿它们判断「服务器上那一份是不是我们自己刚写的」
/// (见 `playback/play_queue_sync.dart` 与 `state/app_state.dart`)。
///
/// 放 data/ 而不是 playback/:状态层按约定不 import 播放层(那会成环)——
/// 这两个函数只认 [Song],与播放无关。

/// 只取当前曲目前后的一段。
///
/// 为什么必须截断:这是一条 **GET 查询串**,几千个 id 拼出来的 URL 会被反向
/// 代理挡下(nginx 默认请求头上限 8KB,超了就是 414)。「接着听」要的本来
/// 也只是当前这一首前后的那一段。
///
/// 默认往前 49、往后 150(总 ≤200),而 **`current` 一定落在名单里** ——
/// 服务器按 id 找它,不在名单里那一份就白存了。当前那一首不在队列里时
/// (理论上不该发生)取开头一段,并把 `current` 让给服务器自己定。
({List<Song> songs, String? currentId}) queueWindow(
  List<Song> songs,
  String? currentId, {
  int before = 49,
  int after = 150,
}) {
  final max = before + after + 1;
  if (songs.length <= max) return (songs: songs, currentId: currentId);

  final index =
      currentId == null ? -1 : songs.indexWhere((s) => s.id == currentId);
  if (index < 0) {
    return (songs: songs.sublist(0, max), currentId: null);
  }
  final start = (index - before).clamp(0, songs.length - max);
  return (songs: songs.sublist(start, start + max), currentId: currentId);
}

/// 队列的**指纹** —— 「服务器上这一份,是不是我们自己刚写的那一份」。
///
/// 用它而不是服务器的 `changed` 时间戳:保存的响应里拿不到那个时间戳
/// (Navidrome 只回一个 ok 外壳),而我们**自己写完**必须认得出下一趟看到的就是它
/// —— 否则每次启动都会问一遍「接着上次听?」,而那明明是我们自己的队列。
///
/// 取的是**身份**不是全部内容:条数 + 头一首 + 末一首 + 当前那一首。
/// 另一台设备留下的队列要在这四项上全撞上才会被误判成自己的,代价只是少问一次
/// (而那一次本来就是「同一份队列」);反过来问错的代价是每次启动都烦人。
String queueMark({required List<Song> songs, String? currentId}) {
  if (songs.isEmpty) return 'empty';
  return '${songs.length}:${songs.first.id}:${songs.last.id}:${currentId ?? '-'}';
}