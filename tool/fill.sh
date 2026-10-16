#!/usr/bin/env bash
# 在模拟器上按字段标签精确填表 —— 每次点击前重新 dump,拿当帧的真实坐标。
#
# 为什么需要它:软键盘弹出 / 收起会把 Flutter 的布局整体推上推下,
# 硬编码的坐标在两次点击之间就失效了,表现成「文字输进了上一个框」。
# 每次操作前重新取坐标是唯一稳的做法。
set -uo pipefail

SERIAL="${SERIAL:-emulator-5554}"
A=(adb -s "$SERIAL")
TMP="$(cd "$(dirname "$0")/.." && pwd)/.tmp-shots"
mkdir -p "$TMP"

dump() {
  "${A[@]}" shell "uiautomator dump /data/local/tmp/ui.xml" >/dev/null 2>&1
  "${A[@]}" shell "cat /data/local/tmp/ui.xml" > "$TMP/ui.xml" 2>/dev/null
}

# 列出所有可选中的节点的中心坐标与文案
nodes() {
  dump
  python - "$TMP/ui.xml" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8', errors='replace').read()
for m in re.finditer(r'<node[^>]*?/?>', s):
    n = m.group(0)
    cls = re.search(r'class="([^"]*)"', n)
    bnd = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    txt = re.search(r'text="([^"]*)"', n)
    desc = re.search(r'content-desc="([^"]*)"', n)
    if not bnd:
        continue
    c = cls.group(1) if cls else ''
    # Flutter 把文案放进 content-desc(语义树),不是 text。
    t = (desc.group(1) if desc and desc.group(1) else (txt.group(1) if txt else ''))
    t = t.replace('&#10;', ' | ')
    if 'EditText' in c or 'Button' in c or t:
        x1, y1, x2, y2 = (int(v) for v in bnd.groups())
        print(f"{c.split('.')[-1]:10s} {(x1+x2)//2:5d},{(y1+y2)//2:5d}  h={y2-y1:4d}  {t[:40]}")
PY
}

case "${1:-nodes}" in
  nodes) nodes ;;
  tap)   dump; cx=$(python - "$TMP/ui.xml" "$2" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8', errors='replace').read()
want = sys.argv[2]
for m in re.finditer(r'<node[^>]*?/?>', s):
    n = m.group(0)
    bnd = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    txt = re.search(r'text="([^"]*)"', n)
    desc = re.search(r'content-desc="([^"]*)"', n)
    if not bnd:
        continue
    t = (desc.group(1) if desc and desc.group(1) else (txt.group(1) if txt else '')).replace('&#10;', ' ')
    if want in t:
        x1, y1, x2, y2 = (int(v) for v in bnd.groups())
        print(f"{(x1+x2)//2} {(y1+y2)//2}")
        break
PY
); if [ -z "$cx" ]; then echo "找不到: $2" >&2; exit 1; fi
         "${A[@]}" shell input tap $cx
         echo "点击 $2 → $cx" ;;
  type)  "${A[@]}" shell input text "$2" ;;
  esc)   "${A[@]}" shell input keyevent 111 ;;
  shot)  "${A[@]}" exec-out screencap -p > "$TMP/${2:-shot}.png"; echo "$TMP/${2:-shot}.png" ;;
  *) echo "用法: fill.sh {nodes|tap <文案>|type <文本>|esc|shot [名]}" >&2; exit 1 ;;
esac
