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
  封面走磁盘缓存(按封面 id + 尺寸作键,不按 URL —— Subsonic 每次请求换 salt)
- **平台**:Android、iOS、Windows、macOS、Linux、Web(单一 Flutter 代码库)

## 当前阶段:M2 — Android 客户端

原型已确认,开发已开始。`prototype/` 是**唯一的设计真相来源**,原样保留作对照基准;
应用是它的逐项实现,并接上了真实的 Subsonic 协议。

```
lib/
  theme/      设计 token(styles.css :root 的 Dart 翻译)、强调色取色、玻璃、氛围背景
  data/       Subsonic 协议:鉴权、客户端(多线路择优 + 故障切换)、映射、配置
              以及下载:落盘索引(download_store)、下载器(download_manager)、网络探针
              缓存:音乐库快照(library_cache)、排序口径(sorting)
  playback/   just_audio + audio_service:队列、四档转码、通知栏 / 锁屏控制、
              播放源选取(本机有下载就走本机文件)
  state/      应用级状态:连接、音乐库、收藏、偏好、下载
  ui/         shell(主壳 / 播放坞 / 标签栏)、screens(20 屏)、widgets(共享组件)

tool/build.sh 是构建入口 —— 它设好引擎产物镜像再调 flutter
```

界面已覆盖原型全部 20 屏:

> 服务器与线路 → 音乐库(专辑 / 艺人 / 歌曲 / 歌单)→ 专辑详情 → 艺人详情 →
> 播放页 → 转码质量 → 播放队列 → 线路切换 → 歌词 → 搜索 → 设置 →
> 下载管理 → 新建歌单 → 添加线路 → 上下文菜单 → 歌单详情(含增删改)

## 里程碑

| 阶段 | 内容 |
| --- | --- |
| M0 | HTML 原型 + 仓库初始化 |
| M1 | Flutter 工程骨架、分层架构、音源抽象层 |
| **M2** | Android MVP(浏览 / 搜索 / 播放 / 转码 / 收藏 / 歌单读写 / 歌词 / 下载 / 离线播放)← 当前 |
| M3 | iOS / 桌面 / Web 铺开,接入飞牛音乐 |

M2 尚未完成的部分:

- 歌单写操作(建 / 改名 / 删 / 加歌 / 按位置移除)已由
  `test/data/playlist_writes_live_test.dart` 打到真服务器上验过一遍;
  **收藏**的写路径同样接了协议,但只有线上形态的用例(`write_operations_test.dart`),
  还没在真机 / 真服务器上走查过。
- 下载已真实落盘,但「下载一位艺人的全部歌曲」要翻页把曲目找齐
  (`getArtist` 只给几首热门),大库上这一段的手感还没在真机上验过。
- 断点续传是**按曲目**的:同一首没下完的半截不接着下,重试从这首开头来
  (整张专辑不会重下已完成的曲子)。要按字节续传得先确认服务器支持 Range。
- 离线只覆盖「已下载的内容」:浏览整个库仍然要连得上服务器(下载管理是
  断网时唯一进得去的门)。

## 开发环境

- Flutter 3.44.1 stable / Dart 3.12.1
- JDK 17、Android SDK 37(或更新)

### 构建

**统一走 `tool/build.sh`**,不要直接跑 `flutter build`:

```bash
tool/build.sh            # debug APK
tool/build.sh release    # release APK
tool/build.sh run        # 在设备上跑
```

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

下载那部分分两层:`download_store_test.dart` 与 `download_manager_test.dart`
走临时目录 + 假传输,不碰网络 —— 验的是排队、门控、续传、失败这些逻辑;
`download_live_test.dart` 则拿真服务器上的一首小歌走完
「拉流 → 落盘 → 索引 → 删除」,验协议那一半。
**但目录归属、存储权限、后台存活只有真机算数**,这几项请在真机上走一遍。

缓存那部分:`library_cache_test.dart` 钉住存读往返、换服务器不认旧缓存、文件坏了
不炸;`app_state_test.dart` 里那几条钉住「铺完缓存就是 ready」「刷新失败但手上有
缓存时不切错误态」「刷新成功之后『来自缓存』归位」。

排序那部分:口径换算与排序本身是纯函数(`sorting_test.dart`),状态层那几条
(`app_state_test.dart`)钉住「专辑换口径要按新 `type` 重拉、歌曲换口径不再打
服务器、失败时本地那份保持原样」。

写操作同理:`write_operations_test.dart` 钉住线上形态(端点与参数名),
`playlist_writes_live_test.dart` 在真服务器上建一条**自检用**的歌单,
加歌 → 改名 → 按位置移除 → 删掉(只碰它自己建的那一条)。

### 已知环境问题

开发机上的 AVD `nordic-ui-api34` 网络配置有缺陷:`eth0` 是
`inet 10.0.2.15/8`,`/8` 掩码把 `192.168.10.4` 判成同网段,于是不走网关、
LAN 流量被错误路由(现象是 TCP 能握手但收不到任何字节)。无 root 改不了
路由表,**所以在这个模拟器上无法验证真实音频播放**。要验音频请用真机。

## 说明

仓库目前**未绑定远程**。
