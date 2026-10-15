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
#   tool/build.sh release         # 打 release APK
#   tool/build.sh run             # 在模拟器上跑
#   tool/build.sh <任意 flutter 参数...>
set -euo pipefail

cd "$(dirname "$0")/.."

# Flutter engine 的 aar / 字体等产物托管在 storage.googleapis.com,
# 本机不通;上海交大镜像 source 镜像同构,换掉基址即可。
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

case "${1:-debug}" in
  run)
    shift
    exec flutter run "$@"
    ;;
  release)
    shift
    exec flutter build apk --release "$@"
    ;;
  debug|apk)
    shift
    exec flutter build apk --debug "$@"
    ;;
  *)
    exec flutter "$@"
    ;;
esac