"""扫描 Dart 源码中的 GBK/UTF-8 误解码乱码（mojibake）。

用法：python tool/scan_mojibake.py [lib 目录]
原理：UTF-8 字节被按 GBK 解码时，会产生大量集中出现的生僻汉字。
     按行统计「生僻字占比」比逐字黑名单更稳。
"""
import pathlib
import sys
import unicodedata

# GBK 误解码 UTF-8 时的典型产物字符（高频出现）
MOJIBAKE_MARKERS = set(
    '鍦鐨涓鏄鎵璇杩鍚浣鏃鍙闇绛濡澶澧鐜鍒鍏鐞鐢鎴鎬鎻鎺鏂鏉鏋鏌鏍鏖鏗鏘鏙鏚鏛鏜'
    '鏝鏞鏟鏠鏡鏢鏣鏤鏥鏦鏧鏨鏩鏪鏫鏬鏭鏮鏯鏰鏱鏲鏳鏴鏵鏶鏷鏸鏹鏺鏻鏼鏽鏾鏿'
    '鐀鐁鐂鐃鐄鐅鐆鐇鐈鐉鐊鐋鐌鐍鐎鐏鐐鐑鐒鐓鐔鐕鐖鐗鐘鐙鐚鐛鐜鐝鐞鐟鐠鐡'
    '囧锛娆犲铏绋绾鐢ㄦ埛'
)


def is_mojibake(line: str) -> tuple[bool, int]:
    hits = sum(1 for ch in line if ch in MOJIBAKE_MARKERS)
    return hits >= 3, hits


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'lib')
    findings = []
    for path in sorted(root.rglob('*.dart')):
        try:
            text = path.read_text(encoding='utf-8')
        except UnicodeDecodeError as error:
            findings.append((path, 0, f'文件不是合法 UTF-8：{error}'))
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            flagged, hits = is_mojibake(line)
            if flagged:
                findings.append((path, lineno, f'hits={hits}  {line.strip()[:80]}'))
    for path, lineno, detail in findings:
        print(f'{path}:{lineno}  {detail}')
    print(f'\n共 {len(findings)} 处可疑乱码')
    return 1 if findings else 0


if __name__ == '__main__':
    raise SystemExit(main())
