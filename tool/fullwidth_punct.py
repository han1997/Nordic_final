"""把 Dart 字符串字面量里**紧贴中文**的半角标点换成全角。

口径与原型那边的 punctcheck.js 一致(用户可见文案用全角标点):
  ,  ;  !  ?  :  (  )  →  ,;!?:()

不碰的东西:
  - 注释里的标点(那是给人看的代码注释,不是文案);
  - `${...}` 插值里面的内容(那是代码);
  - 另外报告 `.`(句号)紧贴中文的可疑处,但**不自动改** —— URL、小数、版本号
    都可能长这样,得一条条看。

用法:  python tool/fullwidth_punct.py --dry   # 只看
       python tool/fullwidth_punct.py         # 改
"""
import re
import sys
from pathlib import Path

HAN = re.compile(r'[㐀-䶿一-鿿豈-﫿]')
MAP = {
    ',': '，',
    ';': '；',
    '!': '！',
    '?': '？',
    ':': '：',
    '(': '（',
    ')': '）',
}
IDENT = re.compile(r'[A-Za-z_$0-9]')


def scan_literals(src):
    """产出 (字面量起点, 正文起点, 正文终点) —— 正文不含两侧引号。"""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            nl = src.find('\n', i)
            if nl < 0:
                return
            i = nl
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        raw = c == 'r' and i + 1 < n and src[i + 1] in '\'"'
        if c in '\'"' or raw:
            quote_at = i + 1 if raw else i
            q = src[quote_at]
            triple = src[quote_at:quote_at + 3] == q * 3
            open_len = 3 if triple else 1
            j = quote_at + open_len
            body_start = j
            while j < n:
                ch = src[j]
                if not raw and ch == '\\':
                    j += 2
                    continue
                if triple:
                    if src[j:j + 3] == q * 3:
                        yield (i, body_start, j)
                        j += 3
                        break
                else:
                    if ch == q:
                        yield (i, body_start, j)
                        j += 1
                        break
                    if ch == '\n':
                        yield (i, body_start, j)
                        break
                j += 1
            i = j
            continue
        i += 1


def interpolations(body):
    """`${...}`(含嵌套)与 `$ident` 在正文里的区间 —— 这些区段里的标点不动。"""
    regions = []
    i = 0
    while i < len(body):
        if body[i] != '$':
            i += 1
            continue
        if i + 1 < len(body) and body[i + 1] == '{':
            depth = 0
            j = i + 1
            while j < len(body):
                ch = body[j]
                if ch in '\'"':
                    k = j + 1
                    while k < len(body) and body[k] != ch:
                        if body[k] == '\\':
                            k += 1
                        k += 1
                    j = k + 1
                    continue
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            regions.append((i, min(j + 1, len(body))))
            i = j + 1
            continue
        m = IDENT.match(body[i + 1:]) if i + 1 < len(body) else None
        if m:
            regions.append((i, i + 1 + m.end()))
            i += 1 + m.end()
            continue
        i += 1
    return regions


def convert(path, dry):
    src = path.read_text(encoding='utf-8')
    hits, periods, out = [], [], []
    for (_, body_start, body_end) in scan_literals(src):
        body = src[body_start:body_end]
        if not HAN.search(body):
            continue
        guarded = interpolations(body)
        changed = list(body)
        for k, ch in enumerate(body):
            if any(a <= k < b for a, b in guarded):
                continue
            prev = body[k - 1] if k > 0 else ''
            nxt = body[k + 1] if k + 1 < len(body) else ''
            if not (HAN.search(prev) or HAN.search(nxt)):
                continue
            if ch in MAP:
                changed[k] = MAP[ch]
                hits.append((body, k, ch))
            elif ch == '.':
                periods.append((body, k))
        new_body = ''.join(changed)
        if new_body != body:
            out.append((body_start, body_end, new_body))

    if out and not dry:
        result = src
        for (a, b, new) in reversed(out):
            result = result[:a] + new + result[b:]
        path.write_text(result, encoding='utf-8')

    for (body, k, ch) in hits:
        print(f"{path}:  {ch!r} -> {MAP[ch]!r}   ...{body[max(0,k-16):k+16]}...")
    for (body, k) in periods:
        print(f"{path}:  可疑句号 '.'   ...{body[max(0,k-16):k+16]}...")
    return len(hits), len(periods)


def main():
    dry = '--dry' in sys.argv
    total = periods = 0
    for path in sorted(Path('lib').rglob('*.dart')) + sorted(Path('test').rglob('*.dart')):
        h, p = convert(path, dry)
        total += h
        periods += p
    print(f"\n{'待改' if dry else '已改'} {total} 处;句号可疑 {periods} 处")


main()