# Nordic

多平台 NAS 音乐播放器。连接你自己的音乐服务器,在任意设备上听自己的库。

- **音源**:Navidrome、Subsonic / OpenSubsonic、飞牛音乐(fnOS)
- **多线路**:同一个音乐库可配多条地址,自动测速择优,线路故障自动切换
- **转码播放**:按网络情况选择原始音质或转码码率
- **平台**:Android、iOS、Windows、macOS、Linux、Web(单一 Flutter 代码库)

## 当前阶段:M2 — Android 客户端

原型已确认,开发已开始。`prototype/` 是**唯一的设计真相来源**,原样保留作对照基准;
应用是它的逐项实现,并接上了真实的 Subsonic 协议。

```
lib/
  theme/      设计 token(styles.css :root 的 Dart 翻译)、强调色取色、玻璃、氛围背景
  data/       Subsonic 协议:鉴权、客户端(多线路择优 + 故障切换)、映射、配置
  playback/   just_audio + audio_service:队列、四档转码、通知栏 / 锁屏控制
  state/      应用级状态:连接、音乐库、收藏、偏好
  ui/         shell(主壳 / 播放坞 / 标签栏)、screens(20 屏)、widgets(共享组件)

tool/build.sh 是构建入口 —— 它设好引擎产物镜像再调 flutter
```

界面已覆盖原型全部 20 屏:

> 服务器与线路 → 音乐库(专辑 / 艺人 / 歌曲 / 歌单)→ 专辑详情 → 艺人详情 →
> 播放页 → 转码质量 → 播放队列 → 线路切换 → 歌词 → 搜索 → 设置 →
> 下载管理 → 新建歌单 → 添加线路 → 上下文菜单

## 里程碑

| 阶段 | 内容 |
| --- | --- |
| M0 | HTML 原型 + 仓库初始化 |
| M1 | Flutter 工程骨架、分层架构、音源抽象层 |
| **M2** | Android MVP(浏览 / 搜索 / 播放 / 转码 / 收藏 / 歌单 / 歌词)← 当前 |
| M3 | iOS / 桌面 / Web 铺开,接入飞牛音乐 |

M2 尚未完成的部分:

- **下载**只做了界面与队列,**不做真实落盘与离线播放**(队列进度是模拟的)。
- **音频实际出声**只差在模拟器上验证 —— 开发机模拟器的网段配置有缺陷
  (见下),应用侧已由 `test/data/stream_probe_test.dart` 证明流地址可用。
- 收藏、歌单写操作已接协议,但尚未在真机上走查过全部路径。

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

### 已知环境问题

开发机上的 AVD `nordic-ui-api34` 网络配置有缺陷:`eth0` 是
`inet 10.0.2.15/8`,`/8` 掩码把 `192.168.10.4` 判成同网段,于是不走网关、
LAN 流量被错误路由(现象是 TCP 能握手但收不到任何字节)。无 root 改不了
路由表,**所以在这个模拟器上无法验证真实音频播放**。要验音频请用真机。

## 说明

仓库目前**未绑定远程**。
