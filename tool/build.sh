#!/usr/bin/env bash
# Nordic 构建入口 —— 把本机网络环境需要的那几项配置收在一处。
#
# 背景:这台机器直连 Google 系主机不通(services.gradle.org 超时、
# maven.google.com 无响应、download.flutter.io 连上但零吞吐)。
# Gradle 发行包与 Maven 仓库的镜像已经写进 android/ 下的 Gradle 配置,
# 只剩 Flutter engine 的 aar 下载走环境变量,所以统一从这个脚本出入。
#
# 用法:
#   tool/build.sh                  # 打 debug APK
#   tool/build.sh release         # 打 release APK(并落成标准化名字,见下)
#   tool/build.sh windows         # 打 Windows release(整目录打成标准名的 zip)
#   tool/build.sh web             # 打 Web release(整目录打成标准名的 zip)
#   tool/build.sh run -d windows  # 在桌面跑
#   tool/build.sh run -d chrome   # 在浏览器里跑(会自动补 --no-web-resources-cdn)
#   tool/build.sh <任意 flutter 参数...>
set -euo pipefail

cd "$(dirname "$0")/.."

# Flutter engine 的 aar / 字体等产物托管在 storage.googleapis.com,
# 本机不通;上海交大镜像 source 镜像同构,换掉基址即可。
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

# 标准化产物名:`Nordic-<版本>-release.apk`,如 `Nordic-1.0.17+18-release.apk`。
#
# 默认产物叫 `app-release.apk` —— 侧载到手机上、发给别人、丢进下载目录之后,
# 几版攒在一起分不清谁是谁,连「是哪个应用」都得点开才知道。
#
# **为什么放在脚本里而不是 Gradle 里**:AGP 9 把 `VariantOutput.outputFileName`
# 从公开 API 里拿掉了(只剩 versionCode / versionName),要用得伸进内部实现。
# 而本仓库的约定本来就是「统一从这个脚本出入」(见 README),落在这里更稳。
#
# 版本号取自 `pubspec.yaml`,不另存一份 —— 唯一的真值在那一行。
# 抽成一个函数是因为产物不止一个了(APK 与 Windows 的 zip 都从这儿取名),
# 别让第二个产物把「从哪儿读版本」抄第二遍。
read_version() {
  sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1
}

standardize_apk() {
  local built="$1"
  local version apk_name out
  version="$(read_version)"
  if [ -z "$version" ]; then
    echo "读不出 pubspec.yaml 里的 version,产物名没法标准化" >&2
    return 1
  fi

  apk_name="Nordic-${version}-release.apk"
  out="build/dist/${apk_name}"
  mkdir -p build/dist
  cp "$built" "$out"

  # 校验一遍再报成。**名字是从 pubspec 拼的,包里的版本必须真是它** ——
  # 改了版本忘了重建,否则会得到一个「名字是新版、内容是旧版」的包,
  # 那种包装上手机才被发现,比没有名字还糟。
  local sdk bt apksigner aapt badging
  sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$LOCALAPPDATA/Android/Sdk}}"
  bt="$(ls -d "$sdk"/build-tools/*/ 2>/dev/null | tail -1)" || true
  if [ -z "${bt:-}" ]; then
    echo "找不到 Android build-tools,跳过签名 / 版本校验" >&2
    echo "$out"
    return 0
  fi

  apksigner="${bt}apksigner"; [ -f "${apksigner}.bat" ] && apksigner="${apksigner}.bat"
  aapt="${bt}aapt";           [ -f "${aapt}.exe" ]      && aapt="${aapt}.exe"

  "$apksigner" verify "$out" >/dev/null
  badging="$("$aapt" dump badging "$out" | head -1)"
  case "$badging" in
    *"package: name='fun.han1997.nordic'"*) ;;
    *) echo "包名不对:$badging" >&2; return 1 ;;
  esac
  case "$badging" in
    *"versionName='${version%%+*}'"*) ;;
    *) echo "包里的 versionName 与 pubspec 的 $version 对不上:$badging" >&2; return 1 ;;
  esac

  echo "✓ $out"
  echo "  签名有效 · 包名 fun.han1997.nordic · 版本 ${version}"
  echo "  (flutter 默认那个 build/app/outputs/flutter-apk/app-release.apk 照旧保留,"
  echo "   flutter install / run --release 认的是它)"
}

# 标准化 Windows 产物:`Nordic-<版本>-windows-x64.zip`。
#
# **产物不是一个文件,是一整个目录**:`flutter build windows` 落的是 `nordic.exe`
# + `flutter_windows.dll` + `data/` + 各插件的 dll,单拿 exe 跑不起来。所以整目录
# 打包,解压出来就能双击。
#
# 为什么用 PowerShell 的 Compress-Archive:Git Bash 里的 tar 是 GNU tar,不按扩展名
# 打 zip。从目录**里面**打包,压缩包顶层就不会多套一层 `Release/`。
#
# 校验三样:exe 在、引擎 dll 与 data/ 都在、以及 **exe 里的版本与 pubspec 对得上**。
# 只校验 exe 的话,一个「看起来有产物」的残缺 zip 会被当成成功;版本那条与 apk
# 同一个理由 —— 名字是从 pubspec 拼的、内容不能是旧版。
# (Windows 没有签名那套东西,这里不假装有。)
standardize_windows() {
  local built="$1"
  local version zip_name out out_abs exe exe_win vinfo alt
  version="$(read_version)"
  if [ -z "$version" ]; then
    echo "读不出 pubspec.yaml 里的 version,产物名没法标准化" >&2
    return 1
  fi

  exe="$built/nordic.exe"
  if [ ! -f "$exe" ]; then
    echo "找不到 $exe —— 构建没产出可执行文件" >&2
    return 1
  fi
  if [ ! -f "$built/flutter_windows.dll" ] || [ ! -d "$built/data" ]; then
    echo "$built 不完整(缺 flutter_windows.dll 或 data/),这个 zip 解压出来跑不起来" >&2
    return 1
  fi

  # `Runner.rc` 把 CMake 注进来的 FLUTTER_VERSION 写成 FileVersion 字符串
  # (`1.0.34+35`),数字四段那份则是 `1.0.34.35`。两种呈现都认 —— 这里不挑
  # 系统怎么渲染版本串,只要求它**就是这个 pubspec 版本**,不是上一个。
  exe_win="$(cygpath -w "$exe")"
  vinfo="$(powershell -NoProfile -Command \
    "(Get-Item '${exe_win}').VersionInfo.FileVersion" | tr -d '\r')"
  alt="${version%%+*}.${version##*+}"
  if [ "$vinfo" != "$version" ] && [ "$vinfo" != "$alt" ]; then
    echo "exe 里的版本 '$vinfo' 与 pubspec 的 '$version' 对不上" >&2
    return 1
  fi

  zip_name="Nordic-${version}-windows-x64.zip"
  out="build/dist/${zip_name}"
  out_abs="$PWD/build/dist/${zip_name}"
  mkdir -p build/dist
  rm -f "$out"
  ( cd "$built" && powershell -NoProfile -Command \
      "Compress-Archive -Path '.\\*' -DestinationPath '$(cygpath -w "$out_abs")' -Force" ) \
    || return 1

  echo "✓ $out"
  echo "  版本 ${version} · 整目录打包(exe + flutter_windows.dll + data/)"
  echo "  (flutter 默认那个 $built 照旧保留,flutter run -d windows 认的是它)"
}

# 标准化 Web 产物:`Nordic-<版本>-web.zip`。
#
# 与 Windows 同构:产物**也是一整个目录**(`index.html` + `main.dart.js` +
# `flutter_bootstrap.js` + `canvaskit/` + assets),整目录打包,解压出来拿静态
# 服务器提供即可。
#
# 校验四条,每条都要能真查出东西:
#  1. 六个入口文件都在 —— 少一个,这个 zip 解出来就是跑不起来;
#  2. `useLocalCanvasKit` 出现在 `flutter_bootstrap.js` 里 —— 这是防「有人绕过这个
#     脚本手打 `flutter build web`」的守门。那种产物会在**运行时**去
#     www.gstatic.com 取 CanvasKit,而失败形态是**停在加载动画上、不报错也不超时**
#     (装载器卡在 main.dart.js 之前)—— 本轮最难查的一种,所以单独一条;
#  3. **版本对齐**:读 `build/web/version.json`。那份是**构建系统**在构建那一刻从
#     当次的 pubspec 写进去的(不是我们从手上这份抄的),所以「改了版本忘了重建」
#     必被抓,与 apk / windows 那两条同一个理由;
#  4. **没有签名那套** —— web 产物没有签名,也没有 Android 那种包名身份可校。
#     这里不假装有。
standardize_web() {
  local built="$1"
  local version zip_name out out_abs written written_num f
  version="$(read_version)"
  if [ -z "$version" ]; then
    echo "读不出 pubspec.yaml 里的 version,产物名没法标准化" >&2
    return 1
  fi

  for f in index.html main.dart.js flutter_bootstrap.js version.json \
           canvaskit/canvaskit.js canvaskit/canvaskit.wasm; do
    if [ ! -f "$built/$f" ]; then
      echo "$built 不完整(缺 $f),这个 zip 解出来跑不起来" >&2
      return 1
    fi
  done

  if ! grep -q useLocalCanvasKit "$built/flutter_bootstrap.js"; then
    echo "$built/flutter_bootstrap.js 里没有 useLocalCanvasKit" >&2
    echo "—— 这份产物运行时会去 www.gstatic.com 取 CanvasKit,打开页面会停在加载动画上。" >&2
    echo "   请走 tool/build.sh web(web) 分支带着 --no-web-resources-cdn)。" >&2
    return 1
  fi

  written="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$built/version.json")"
  written_num="$(sed -n 's/.*"build_number"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$built/version.json")"
  if [ "$written" != "${version%%+*}" ] || [ "$written_num" != "${version##*+}" ]; then
    echo "产物里的版本 ${written}+${written_num} 与 pubspec 的 $version 对不上" >&2
    return 1
  fi

  zip_name="Nordic-${version}-web.zip"
  out="build/dist/${zip_name}"
  out_abs="$PWD/build/dist/${zip_name}"
  mkdir -p build/dist
  rm -f "$out"
  ( cd "$built" && powershell -NoProfile -Command \
      "Compress-Archive -Path '.\\*' -DestinationPath '$(cygpath -w "$out_abs")' -Force" ) \
    || return 1

  echo "✓ $out"
  echo "  版本 ${version}(产物内 version.json 逐字核对过)· 整目录打包"
  echo "  入口 index.html · 本地 CanvasKit(未走 www.gstatic.com)· 无签名可校"
  echo "  必须从根提供(index.html 里是 base href=\"/\");"
  echo "  (flutter 默认那个 $built 照旧保留,flutter run -d chrome 认的是它)"
}

case "${1:-debug}" in
  run)
    shift
    # 跑在浏览器里时自动补上那个开关(理由见 `web)` 分支那段注释)。漏了它的症状是
    # 「页面停住、什么都不说」,人大概率会先怀疑代码而不是少了个开关 —— 与脚本顶部
    # 那句「本机网络环境需要的那几项配置收在一处」同一类。**只认 web 设备 id**,
    # 桌面 / 手机原样透传;用户自己传过就不叠。
    case " $* " in
      *web-resources-cdn*) ;;
      *" -d chrome"*|*" -d edge"*|*" -d web-server"*|*"--device-id chrome"*|*"--device-id edge"*|*"--device-id=chrome"*|*"--device-id=edge"*)
        set -- "$@" --no-web-resources-cdn ;;
    esac
    exec flutter run "$@"
    ;;
  release)
    shift
    flutter build apk --release "$@"
    standardize_apk build/app/outputs/flutter-apk/app-release.apk
    ;;
  windows|win)
    shift
    flutter build windows --release "$@"
    standardize_windows build/windows/x64/runner/Release
    ;;
  web)
    shift
    # **`--no-web-resources-cdn` 不是可选项。** web 目标的默认是让**页面在运行时**
    # 去 www.gstatic.com 取 CanvasKit(渲染器本体):`kWebResourcesCdnFlag` 的
    # `defaultsTo: true`,`flutter_web_sdk/flutter_js/src/utils.js` 的
    # `getCanvaskitBaseUrl()` 于是在 `engineRevision && !useLocalCanvasKit` 时
    # 返回那个 CDN 地址。取不到的表现是**页面停在加载动画上,不报错也不超时**
    # (装载器卡在 main.dart.js 之前)—— 最难查的一种。
    # 加了这个开关,CanvasKit 从产物自己的 `build/web/canvaskit/` 里取。
    # 注意 `FLUTTER_STORAGE_BASE_URL` **管不到这一跳**:它只管构建期的引擎产物下载,
    # 而那个 CDN 地址是运行时用的、且在工具里是硬编码的。
    flutter build web --release --no-web-resources-cdn "$@"
    standardize_web build/web
    ;;
  debug|apk)
    shift
    exec flutter build apk --debug "$@"
    ;;
  *)
    exec flutter "$@"
    ;;
esac
