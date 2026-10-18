import 'package:flutter_test/flutter_test.dart';

/// 让**真实的事件循环**把点下去那一串异步工作跑完。
///
/// `testWidgets` 里用的是假时钟,而 `AppState.connect` / `loadLibrary` 会真去删
/// 缓存文件、真写一次库快照 —— 那些 await 停在真实 IO 上永远不回来
/// (`home_screen_test.dart` 里对 `loadLibrary` 已经写过一遍,那里是把整件事塞进
/// `runAsync`;但**由点击触发的**那一串塞不进去:回调是建在假时钟里的,
/// 它的每一段后续也都在假时钟里排队)。
///
/// 所以这里是**一个回合一次让步**:`runAsync` 把控制权交给真实事件循环(那一步 IO
/// 走完),紧接着 `pump` 清掉假时钟的微任务队列(下一段 IO 才发得出去)。这一串是
/// 一步接一步的,一个回合只够推进一步。
///
/// 末尾再推一次把定时器也走掉:`connect` 收尾时那次线路测速**故意等 600ms**
/// (见 `AppState.refreshRouteLatency`),不推过去测试收场时会撞上
/// 「还有定时器没跑完」。
Future<void> pumpRealIo(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 700));
  // **收尾用有界的 pump,不用 `pumpAndSettle`**:这一串跑着的时候界面上可能挂着
  // 一个转圈的加载态(`_busy`),而它永远有下一帧 —— `pumpAndSettle` 会一路推到
  // 假的十分钟然后报「pumpAndSettle timed out」,读起来像是这里出了问题。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}