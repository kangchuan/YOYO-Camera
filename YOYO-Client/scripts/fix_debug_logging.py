#!/usr/bin/env python3
"""P4：把项目里的 print( 批量替换为 debugLog(。

安全措施：
  * 用「掩码」区分真实代码与注释/字符串，字符串字面量内的 print 不会被误改；
  * 跳过 DebugLog.swift 自身（它内部的 Swift.print 是唯一合法保留）；
  * 只替换标识符本身，保留原有空白与换行（含 6 处跨行调用）；
  * 默认 dry-run，加 --apply 才真正落盘。
"""

import os
import re
import sys

ROOT = 'Yoyo'
SKIP_FILES = {'Yoyo/Utils/DebugLog.swift'}
PATTERN = re.compile(r'(?<![A-Za-z0-9_$.])print(?![A-Za-z0-9_])(\s*\()')


def mask(src):
    """把注释与字符串字面量的内容替换为等长空格，仅保留真实代码可见。"""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if src[k] != '\n':
                    out[k] = ' '
            i = j
        elif c == '"':
            if src.startswith('"""', i):
                j = src.find('"""', i + 3)
                j = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n:
                    if src[j] == '\\':
                        j += 2
                        continue
                    if src[j] == '"':
                        j += 1
                        break
                    if src[j] == '\n':
                        break
                    j += 1
            for k in range(i, j):
                if src[k] != '\n':
                    out[k] = ' '
            i = j
        else:
            i += 1
    return ''.join(out)


def main():
    apply = '--apply' in sys.argv
    files = sorted(
        os.path.join(dp, f)
        for dp, _, fn in os.walk(ROOT)
        for f in fn
        if f.endswith('.swift')
    )

    total = 0
    touched = 0
    per_file = []
    interpolation_nested = []

    for path in files:
        if path in SKIP_FILES:
            continue
        src = open(path, encoding='utf-8').read()

        # 边界检查：字符串插值内部内嵌 print( —— 掩码会看不到，需要单独告警
        for m in re.finditer(r'\\\([^)]*\bprint\s*\(', src):
            interpolation_nested.append((path, src[m.start():m.start() + 60]))

        m = mask(src)
        matches = list(PATTERN.finditer(m))
        if not matches:
            continue

        total += len(matches)
        touched += 1
        per_file.append((len(matches), path))

        if apply:
            chars = list(src)
            # 倒序替换，避免下标漂移
            for mt in reversed(matches):
                chars[mt.start():mt.start() + 5] = list('debugLog')
            open(path, 'w', encoding='utf-8').write(''.join(chars))

    per_file.sort(reverse=True)
    print(f"{'[已写入]' if apply else '[预览]'} 命中 {total} 处，涉及 {touched} 个文件")
    print()
    print("数量最多的 10 个文件：")
    for c, p in per_file[:10]:
        print(f"  {c:>4}  {p[len(ROOT) + 1:]}")
    print()
    if interpolation_nested:
        print(f"⚠️  字符串插值内嵌 print( ：{len(interpolation_nested)} 处（掩码覆盖不到，需人工确认）")
        for p, s in interpolation_nested[:10]:
            print(f"    {p}: {s}")
    else:
        print("✅ 无字符串插值内嵌 print( 的漏网情况")


if __name__ == '__main__':
    main()
