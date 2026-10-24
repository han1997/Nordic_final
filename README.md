# Nordic

多平台 NAS 音乐播放器。连接你自己的音乐服务器,在任意设备上听自己的库。

- **音源**:Navidrome、Subsonic / OpenSubsonic、飞牛音乐(fnOS)
- **多线路**:同一个音乐库可配多条地址,自动测速择优,线路故障自动切换
- **转码播放**:按网络情况选择原始音质或转码码率
- **离线下载**:整张专辑 / 单曲 / 一位艺人的歌拉到本机(原文件,不转码),
  进度与失败原因都是真的;已下好的曲子播放时走本机文件,**封面也用本机那张**,
  断网也能听、也能看。断网时库刷不出来,但「设置 → 下载管理」里点开已下好的
  条目就能直接播 —— 曲目清单随下载记录一起存在本机
- **歌单管理**:新建 / 重命名 / 删除,把歌加进歌单,从歌单里按位置移除
- **排序**:专辑与歌曲两栏各一套口径 —— 专辑走服务器(Navidrome 的「最近添加 /
  最近播放 / 常听」本地算不出来),歌曲在本地排(标题 / 艺人 / 专辑 / 添加时间)
- **缓存**:音乐库列表落盘一份,启动先铺出来再静默刷新(不必空等一次全量拉取);
  刷新失败时留在屏幕上并说明一句是什么时候同步的 —— 断网也还有东西可看。
  封面走磁盘缓存(按封面 id + 尺寸作键,不按 URL —— Subsonic 每次请求换 salt)。
  **听过的歌也留一份**(边听边写,不多花一份流量),再听直接读本机、断网也能放;
  上限在设置里选(不缓存 / 256 MB … 4 GB,默认 1 GB),满了按「最久没听」淘汰。
  缓存**只管缓存**:点名下载的那些在另一个目录里,永远不会被淘汰掉
- **平台**:Android、Windows、Web(单一 Flutter 代码库;iOS / macOS / Linux 的工程
  目录尚未生成)。**宽屏 / 平板**(桌面窗口、平板横屏)自第二十六轮起有完整形态:
  >= 840 换左竖栏 + 底部播放横条 + 多列网格 + 两栏播放页,窄屏形态不变

## 当前阶段:M3 — 平台铺开(先做 Windows 桌面)

原型已确认,开发已开始。`prototype/` 是**唯一的设计真相来源**,原样保留作对照基准;
应用是它的逐项实现,并接上了真实的 Subsonic 协议。

```
lib/
  theme/      设计 token(styles.css :root 的 Dart 翻译)、强调色取色、玻璃、氛围背景
  data/       音源抽象层(music_source):界面只认 MusicSource 这个接口,不认协议
              Subsonic 协议:鉴权、客户端(多线路择优 + 故障切换)、映射、配置
              以及下载:落盘索引(download_store)、下载器(download_manager)、网络探针
              缓存:音乐库快照(library_cache)、听过的歌(media_cache)与文件命名规则
              (media_files)、排序口径(sorting)
  playback/   just_audio + audio_service:队列、四档转码、通知栏 / 锁屏控制、
              播放源选取(本机有下载 / 缓存就走本机文件)、边听边缓存
  state/      应用级状态:连接、音乐库、收藏、偏好、下载、缓存
  ui/         shell(主壳 / 播放坞 / 标签栏)、screens(21 屏)、widgets(共享组件)

tool/build.sh 是构建入口 —— 它设好引擎产物镜像再调 flutter
```

界面已覆盖原型全部 21 屏:

> 服务器与线路 → 首页(正在播放 / 最近添加 / 最近播放 / 最常播放)→
> 音乐库(专辑 / 艺人 / 歌曲 / 歌单)→ 专辑详情 → 艺人详情 →
> 播放页 → 转码质量 → 播放队列 → 线路切换 → 歌词 → 搜索 → 设置 →
> 下载管理 → 新建歌单 → 添加线路 → 上下文菜单 → 歌单详情(含增删改)

设计板上还有第 22 格 —— **应用图标**:它不对应应用里的任何一屏,是「这个应用在启动器里
长什么样」的设计交付物,候选、定稿的三档尺寸(48px 是判据)、启动器四种遮罩各摆一份。
图形来自 `tool/app_icon.py`,和落到 Android 资源里的 PNG 是同一次生成的同一份矢量 ——
所以要改几何改那个脚本,别改 `prototype/icon.js`。

**底栏是「首页 / 音乐库 / 设置」**(2026-10-17 起,原型与应用同步):搜索是
「知道要找什么」时的动作,用完就退,占一个常驻位置不划算 —— 它挪进首页与音乐库
顶栏那颗放大镜,变成**推入的页面**;空出来的位置给首页,「不知道听什么」时才需要
一个一直能回的地方。首页铺的是**服务器口径**的三条货架(正在播放 / 最近添加 /
最近播放 / 最常播放),音乐库只管「库里有什么」—— 两屏的分工就这一条线。

## 界面改动一律**先改原型**

`prototype/` 是唯一的设计真相来源,这不是修辞:**任何界面 / 交互的增删改,先改
`prototype/`**(`app.js` 的屏幕函数 + `styles.css`、新屏幕要进 `VIEWS` 与 `BOARD`),
定下来之后应用再去实现。**不要在应用里「顺手」做一个原型里没有的东西** ——
设计板不再能对照、别人无从知道那个东西本来该长什么样,而用户是真的会去看原型的。

> 这一条是 2026-10-17 立的:当时加首页 tab 直接改了应用、没动原型,被指出来了。
> 补做时连带修掉一个漏网的重复:那次只把「继续收听」与「最近添加」加到了首页,
> **没从音乐库撤掉**,于是两屏各铺了一份。同一天还补了首页那屏漏掉的**底部托盘** ——
> 它是从音乐库那两栏搬过来的,搬的时候没带上 `bottom()`,于是首页没有路去别的地方。」

顺带记一条自检习惯:改完原型跑一遍 `.tmp-shots/*.cjs` 里的 playwright 脚本
(见那儿已有的模板),顺手看控制台 —— 那次改动里漏掉的 `pct` 引用,
就是靠它报的 `Uncaught ReferenceError` 抓到的。

## 里程碑

| 阶段 | 内容 |
| --- | --- |
| M0 | HTML 原型 + 仓库初始化 |
| M1 | Flutter 工程骨架、分层架构 |
| M2 | Android MVP(浏览 / 搜索 / 播放 / 转码 / 收藏 / 歌单读写 / 歌词 / 下载 / 离线播放) |
| **M3** | iOS / 桌面 / Web 铺开,接入飞牛音乐 ← 当前(Windows 桌面已通 · Web 第一版 · **宽屏 / 平板已适配** · 音源接缝已立 · 飞牛音乐未接) |

M2 收口时留下的、**只剩真机走查**的几条:

- 歌单写操作(建 / 改名 / 删 / 加歌 / 按位置移除)与**收藏**(曲 / 专辑 / 艺人)
  都已由 live 用例打到真服务器上验过(`playlist_writes_live_test.dart`、
  `star_writes_live_test.dart`);这两样在**真机**上还没走查过。
- 下载已真实落盘。「下载一位艺人的全部歌曲」会一页页翻到**空页**为止把曲目
  找齐(`getArtist` 只给几首热门,见 `songsByArtist`);这一段**大库上还没在真机
  上验过**。
- 断点续传**按字节**:同一首没下完的半截 `.part` 留着,下次从那个偏移接着下
  (服务器不认 `Range` 时自动截断重来);整张专辑不会重下已完成的曲子。
  只有「下到一半杀进程再续」那一条只在单测里验过,真机上没走查。
- 离线覆盖「已下载的 + 听过的」:**浏览整库不用连服务器** —— 整库快照落在本机
  (`library_cache.dart`),断网冷启动照样铺得出首页与库(刷新失败时保留上次
  那份)。真正的边界只剩「断网**能听**哪几首」:已下载的,加上缓存里最近听过的
  那几首 —— 缓存按上限淘汰,要长期留着请用下载。

## 开发环境

- Flutter 3.44.1 stable / Dart 3.12.1
- JDK 17、Android SDK 37(或更新)

### 构建

**统一走 `tool/build.sh`**,不要直接跑 `flutter build`:

```bash
tool/build.sh            # debug APK
tool/build.sh release    # release APK(按 ABI 三个包)
tool/build.sh windows    # Windows release(整目录打成标准名的 zip)
tool/build.sh web        # Web release(整目录打成标准名的 zip)
tool/build.sh run        # 在设备上跑
```

侧载用的 release 包由这个脚本**按 ABI 分三份**、各落成标准名字:

```
build/dist/Nordic-1.0.47+48-arm64-v8a-release.apk
             └ 应用  └ pubspec 的版本  └ CPU 架构
```

**手机侧载装 `arm64-v8a` 那份,模拟器装 `x86_64` 那份,32 位老设备用 `armeabi-v7a`。**
为什么分三份:`flutter build apk` 默认把三套原生库塞进同一个包,而一台设备只用得到其中
一份 —— 另外两份引擎(每份 8.4~12.9 MB)与 Dart 快照(每份 7.5~8.2 MB)是白背的。
实测那个万能包 74.6 MB,按 ABI 分开之后手机该装的 `arm64-v8a` 约 26 MB。真要那个万能包
(比如分不出对方是什么设备)走脚本的透传分支:`tool/build.sh build apk --release` ——
出得来,只是不落 `build/dist`。

默认那个 `app-<abi>-release.apk` 装上手机、发给别人之后分不清是哪一版,连「是哪个应用」
都得点开看。版本号**只从 `pubspec.yaml` 读**,不另存一份;脚本还会顺手校验
签名、包名与包内 `versionName` 是否真与 pubspec 对得上(三个包逐个验,任一个不过就整批
失败)—— 改了版本忘了重建,否则会得到一个「名字是新版、内容是旧版」的包,
那种包装上手机才发现,比没有名字更糟。
(浮出来的产物 `build/app/outputs/flutter-apk/app-<abi>-release.apk` 照旧保留:
`flutter install` / `run --release` 认的是它。)

Windows 侧同理:`tool/build.sh windows` 落成
`build/dist/Nordic-<版本>-windows-x64.zip`。它的产物**不是一个文件,是一整个目录**
(`nordic.exe` + `flutter_windows.dll` + `data/` + 各插件的 dll),单拿 exe 跑不起来,
所以整目录打包、解压出来就能双击;脚本同样校验 exe 里的版本与 pubspec 一致
(Windows 没有签名那一套,不假装有)。

**Windows 构建有两条系统前置**(都不是仓库能替你解决的):

1. **开开发者模式** —— Flutter 给插件建符号链接要它,不然 `flutter build windows`
   会直接停在 `Building with plugins requires symlink support`
   (设置 → 隐私和安全性 → 开发者选项 → 开发人员模式)。
2. **装 ATL 组件** —— `flutter_secure_storage_windows`(存服务器密码用的那个)要
   `atlstr.h`,它属于 VS 安装器里的「C++ ATL for latest v143 Build Tools (x86 & x64)」。
   没装就在这里报 `error C1083: 无法打开包括文件: "atlstr.h"`。

Web 侧:`tool/build.sh web` 落成 `build/dist/Nordic-<版本>-web.zip`(同样整目录打包),
脚本会校验入口文件齐不齐、**产物里的 `version.json` 与 pubspec 是否一致**,以及
「CanvasKit 是不是从 CDN 拿的」。最后那条不是洁癖 —— **web 目标的默认是让页面在运行时
去 `www.gstatic.com` 取 CanvasKit(渲染器本体)**,取不到的表现是**停在加载动画上、
不报错也不超时**。所以 `build web` 与 `run -d chrome` 都必须带
`--no-web-resources-cdn`(`run` 分支已经按设备 id 自动补),让 CanvasKit 从产物自己的
`build/web/canvaskit/` 取。注意 `FLUTTER_STORAGE_BASE_URL` 那个镜像**管不到这一跳** ——
它只管构建期的引擎产物下载,而这是个运行时的地址。

Web 产物还有两条部署约束:**必须从根提供**(`index.html` 里是 `<base href="/">`,
丢进子目录会 404);静态服务器要会用 `application/wasm` 发 `.wasm`
(Python 的 `http.server` 会发成 octet-stream,浏览器打一句 warning 后仍能用,
但正式部署该交给 nginx 这类)。

**改名为什么在脚本里而不是 Gradle 里**:AGP 9 把 `VariantOutput.outputFileName`
从公开 API 拿掉了(只剩 `versionCode` / `versionName`),照旧写法编译不过,
要用得伸进内部实现 —— 而本仓库的约定本来就是「统一从这个脚本出入」。

**每做一次代码工作,`pubspec.yaml` 的 patch 与 `versionCode` 各 +1**
(`1.0.17+18` → `1.0.18+19`),这样产物名与安装包的版本永远对得上,也方便回滚比对。

这台开发机**直连 Google 系主机不通**(`services.gradle.org` 超时、
`maven.google.com` 无响应、`download.flutter.io` 连上但零吞吐),
所以三项镜像配置已经写进仓库,新环境克隆下来即可构建:

| 目标 | 处置 |
| --- | --- |
| Gradle 发行包 | `android/gradle/wrapper/gradle-wrapper.properties` → 腾讯镜像 |
| Maven 仓库(AGP / AndroidX) | `android/settings.gradle.kts`、`android/build.gradle.kts` → 阿里云前置,上游兜底 |
| Flutter 引擎产物 | `tool/build.sh` 设 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` |

### 测试

```bash
flutter test
```

其中 `test/data/` 下有一组**打真实服务器**的用例(不可达时自动跳过),
覆盖鉴权、专辑 / 艺人 / 歌单 / 搜索 / 歌词、封面与流地址。
用假响应测「字段名对不对」容易自说自话,打到真服务器才能发现协议口径的偏差。

**凭据从环境变量读,不进仓库**(仓库是公开的,密码一旦提交就永远留在 git 历史里)。
不设就当作服务器不可达,那几组整组跳过:

```bash
NORDIC_LIVE_URL=http://<你的服务器>:4533 \
NORDIC_LIVE_USER=<账号> \
NORDIC_LIVE_PASSWORD=<密码> \
flutter test
```

(变量名与降级规则只有一处说法:`test/data/live_server.dart`。)

下载那部分分两层:`download_store_test.dart` 与 `download_manager_test.dart`
走临时目录 + 假传输,不碰网络 —— 验的是排队、门控、续传、失败这些逻辑;
`download_live_test.dart` 则拿真服务器上的一首小歌走完
「拉流 → 落盘 → 索引 → 删除」,验协议那一半。
**但目录归属、存储权限、后台存活只有真机算数**,这几项请在真机上走一遍。

缓存那部分:`library_cache_test.dart` 钉住存读往返、换服务器不认旧缓存、文件坏了
不炸;`app_state_test.dart` 里那几条钉住「铺完缓存就是 ready」「刷新失败但手上有
缓存时不切错误态」「刷新成功之后『来自缓存』归位」。

听过的歌那份缓存(`media_cache_test.dart`)盯的是两件最容易写错的事:**位置是算出
来的**(曲目 id + 档位 → 路径,没有索引文件,所以不存在「索引说有、盘上没有」),
以及**淘汰按最久没听、且绝不碰正在听的那一份**;顺手钉住「调小上限当场淘汰」
「关掉缓存真的不写盘」与「半截文件不算占用」。界面那半在 `settings_screen_test.dart`
(上限、占用、清除三者对得上,清缓存不动下载)。

排序那部分:口径换算与排序本身是纯函数(`sorting_test.dart`),状态层那几条
(`app_state_test.dart`)钉住「专辑换口径要按新 `type` 重拉、歌曲换口径不再打
服务器、失败时本地那份保持原样」。

写操作同理:`write_operations_test.dart` 钉住线上形态(端点与参数名),
`playlist_writes_live_test.dart` 在真服务器上建一条**自检用**的歌单,
加歌 → 改名 → 按位置移除 → 删掉(只碰它自己建的那一条)。

## 性能姿态(为什么这么写)

下面几处看着「绕」,但都是为了性能 —— 别顺手改回去。**完整的 130 行口径
(懒加载、独立通道、缓存门控、HeroMode、翻页判据、歌词滚动……)在
[`docs/performance.md`](docs/performance.md),判据以那份为准**;README 只留最容易被
「顺手优化」掉的几条:

- 大列表是真懒加载(sliver),别换成嵌在 `ListView` 里的 `GridView(shrinkWrap: true)`。
- 播放位置与缓冲各走**单独一条通道**,不进 `state` 的通知。
- 「全部歌曲」一页 1000 首,**「这一页不满」不等于「到底了」**(有服务器卡在 500)。
- 新缓存只在**不花流量**的时候写(`shouldWriteCache`),**别去掉这层门控**;
  已经在盘上的照旧读本机。
- `BackdropFilter` 只能收**裸** `ImageFilter.blur`(Impeller 上组合过滤器不生效)。
- 流媒体的**取数节拍带迟滞**(75 / 45):别把 `min` 与 `max` 改回相等 —— 相等就是
  「一直在小口小口地拉」,无线电没有安静的间隙,费电而屏幕上看不出来。
- 等网络的下载复查**带退避**(4 秒翻到 32 秒),别改回固定节拍。

## 更新历史

第三轮 ~ 第七轮的分轮记录已经移到
[`docs/CHANGELOG.md`](docs/CHANGELOG.md),本文件不再逐轮展开。**以后新的一轮接在
那个文件末尾**(从早到晚排),不要新开文件,也不要往 README 里加。

## 已知环境问题

开发机上的 AVD `nordic-ui-api34` 网络配置有缺陷:`eth0` 是
`inet 10.0.2.15/8`,`/8` 掩码把 `192.168.10.4` 判成同网段,于是不走网关、
LAN 流量被错误路由(现象是 TCP 能握手但收不到任何字节)。无 root 改不了
路由表,**所以在这个模拟器上无法验证真实音频播放**。要验音频请用真机。

## 说明

远程仓库:`git@github.com:han1997/Nordic_final.git`(origin)。**每次改完都提交并推送**,
别攒着 —— 本地一份、远程一份,才不会出现「改完没提交、之后谁也说不清哪一版是对的」。

改完东西顺手记一轮:分轮记录写在 [`docs/CHANGELOG.md`](docs/CHANGELOG.md) 的**末尾**
(从早到晚排),不要往本文件里加;改了代码就按 `### 构建` 那节把 `pubspec.yaml` 的
patch 与 `versionCode` 各 +1 —— **纯文档 / 纯注释的改动不动版本号**(版本号是为了让
侧载的包分得清哪一版,行为没变的包换号只是噪音)。版本号的真值只在 `pubspec.yaml`。

界面改动一律**先改 `prototype/`**(见「界面改动一律先改原型」一节);提交信息里也写清楚原型与应用各改了什么。
