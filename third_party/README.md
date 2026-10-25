# third_party

两个**按固定版本放进仓库**的依赖。它们都不是「我们的代码」,是为了把上游
还没发布的两个 Windows 缺陷修掉才搬进来的 —— 理由、补丁、什么时候该搬回去,
都记在下面,别只留着目录。

两个都走 `pubspec.yaml` 里的 `path:` 依赖,所以 `flutter pub get` 读的就是
这里的源码;改了这里就是改了应用实际跑的东西。

## just_audio_windows

- 来源:`https://github.com/bdlukaa/just_audio_windows`
- 取的是 `501f2ddddf2cdd9241213bcdaf05227a6c6a7c10`(2026-09-06),pub 上最新
  仍是 `0.2.3`(2026-04-04),**没有这些修复**
- 搬进来的原因(每一条都在真机日志里见过,见 `docs/CHANGELOG.md` 第三十四轮):
  - **#63** WinRT 回调线程直接往平台通道写事件 —— Flutter 引擎逐条报
    `... channel sent a message from native to Flutter on a non-platform thread`,
    按引擎自己的说法会「丢消息或崩溃」。上游改成消息窗口派发到平台线程。
  - **#65** 换源过程中 MediaPlaybackState 会短暂回到 `None`,上游据此报 `idle`;
    `just_audio` 把 `idle` 理解成「平台没了」,于是 `_setPlatformActive(false)`
    把**还在装载的那一次**打断(`PlayerInterruptedException: Loading
    interrupted`)—— 表现就是「点了没反应 / 放着放着没声了」。
  - **#66** 时长还没报出来就报 `completed`。
  - **#62** `load` 抛的 C++ 异常直接终结进程,现在变成一个 Dart 错误。
  - **#61** 默认接管系统媒体键 / SMTC 弹层,系统侧的操作会绕过 Dart 改原生状态。
  - **#64** 只在 debug 构建里逐条打方法名,`BufferingProgress` 只警告一次。
- **没有改上游一个字节**(只删了 `.git` / `.metadata` / `.gitignore`)。要改就在
  这里改,并在这一节记一笔。

## just_audio

- 来源:`https://pub.dev/packages/just_audio` 的 `0.10.6`(2026-06-29),
  目录里是那个包的 `lib/`、`android/`、`darwin/` 与元数据(没有 `example/`)
- 搬进来的原因只有一条:**`LockCachingAudioSource` 在 Windows 上从来没成功过**。
  它一边把流喂给解码器一边写 `<缓存文件>.part`,下完再改名成正式的那一份;
  但那个写句柄从来没人关(上游 0.10.6 里还留着
  `// TODO: Should close sink after done, but it throws an error`)。POSIX 上
  「对打开着的文件改名」是合法的,所以 Android / iOS / Linux 一直没事;
  Windows 上这是 `ERROR_SHARING_VIOLATION`(errno 32),于是**每一首**放完都抛
  `PathAccessException`,`.part` 永远变不成正式文件 —— 真机缓存目录里
  97 个文件里 45 个 `.part`、**0 个完整文件**,「听过的歌留一份」在 Windows 上
  从未生效,顺带远端 seek 也永远等不到「完整那一份」。
- 补丁两处(都在 `lib/just_audio.dart`,都用 `**Nordic 补丁**` 起头标出来):
  1. `_fetch` 的 `onDone`:先 `flush + close` 再改名,并重试三次(中间可能被
     杀软短暂占住);`onError` 里也先放句柄再删 `.part`(Windows 上留着句柄
     连删除都失败)。
  2. `_proxyHandlerForSource`:长度未知的响应设 `persistentConnection = false`。
     上游 PR #1602(未发布)—— `headers.clear()` 把 chunked 也清了,于是
     `contentLength = -1` 的响应既无长度也无分帧,客户端只能等到连接关闭;
     Media Foundation 等不到,就是「放到一半不动 / Item error」。
- 升级时要做的事:拿新版本覆盖,重放上面两处补丁,再跑
  `test/playback/lock_caching_rename_test.dart` 与全量测试;上游若已修
  (0.10.6 之后没有),把这里整个删掉、pubspec 换回 `^` 约束。

## 许可

两个都是 MIT。`LICENSE` 随包带着,没有改动。
