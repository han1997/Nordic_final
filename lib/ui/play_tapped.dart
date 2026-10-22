import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../playback/playback_controller.dart';

/// 点了一首歌 / 一行歌 —— **把它播起来,播不起来就说一句**。
///
/// 为什么值得单独一个文件:全应用有十八处 `playAll`,而它们原先都是一句裸调用。
/// 而 `playAll` 的失败只写进 `PlaybackState.error`,那个字段**没有任何界面读它**
/// —— 于是「点了一首播不出来的歌」在屏幕上什么都不发生:坞不出现、播放页还是
/// 「还没有在播的歌」。用户分不清是自己没点中、还是这一首坏了。
///
/// 原型里这一句是 `.toast`(见 `prototype/app.js` 的 `toastMarkup` 与设计板上那格
/// 「音乐库 · 播放失败」):一条 1.6 秒的气泡,不占位、不打断。这里照它来 ——
/// 用 SnackBar 而不是自己画一个 overlay,是因为全应用的提示都是它(见
/// `docs/performance.md` 里「别为一句话再造一套」那一条);1.6 秒太短,
/// 按应用里既有的一档取 2 秒(与「已加入下载队列」那些同长)。
///
/// **为什么不用 protoype 里那个 168px 的底部位置**:那一格是浮在播放坞上方的;
/// SnackBar 由框架摆在坞的更上面,两者说的是同一件事,不必自己对齐。
///
/// [label] 是「这一下点的是什么」,拼进那句提示里 —— 用户刚点的那一行就在眼前,
/// 说「这一首」比说「播放失败」更具体。
Future<void> playTapped(
  BuildContext context,
  List<Song> songs, {
  int index = 0,
  String? label,
}) async {
  final playable = context.read<PlaybackController>();
  // 先取出提示通道:**await 之后 context 可能已经不能用了**(比如从下载面板
  // 点开的那一条会 pop),而这句话必须说得出口。
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failure = await playable.playAll(songs, index: index);
  if (failure == null) return;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        label == null
            ? '这一首播不了 —— $failure'
            : '「$label」播不了 —— $failure',
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}
