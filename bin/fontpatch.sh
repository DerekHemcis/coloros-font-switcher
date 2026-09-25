#!/system/bin/sh
# fontpatch.sh <源字体> <输出字体> <NONE|EN|SC|TC>
# 作用: 把字体 name 表中的 PostScript 名(nameID=6) 改写为 ColorOS 期望的值
# 实现: 在文件末尾追加一张重建的 name 表, 并把目录项指向它 (不改动其它表)
# 依赖: busybox (od / dd / printf / base64 / tr / awk / wc)

BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=busybox

SRC="$1"; DST="$2"; KIND="$3"
T="${TMPDIR:-/data/local/tmp}/fontpatch.$$"
mkdir -p "$T" || exit 1
trap 'rm -rf "$T"' EXIT

r16() { $BB od -An -tu1 -j "$2" -N 2 "$1" 2>/dev/null | $BB awk '{print $1*256+$2}'; }
r32() { $BB od -An -tu1 -j "$2" -N 4 "$1" 2>/dev/null | $BB awk '{print $1*16777216+$2*65536+$3*256+$4}'; }
w16() { $BB printf "\\$(printf '%03o' $(( $3 / 256 )))\\$(printf '%03o' $(( $3 % 256 )))" | $BB dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null; }
w32() { $BB printf "\\$(printf '%03o' $(( ($3/16777216)%256 )))\\$(printf '%03o' $(( ($3/65536)%256 )))\\$(printf '%03o' $(( ($3/256)%256 )))\\$(printf '%03o' $(( $3%256 )))" | $BB dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null; }

# --- 选择目标 PostScript 名 (UTF-16BE 的 base64) ---
case "$KIND" in
  NONE) cp -f "$SRC" "$DST" && exit 0 ;;
  EN) B64='AE8AUABsAHUAcwBTAGEAbgBzAEUAbg==' ;;                         # OPlusSansEn
  SC) B64='AE8AUABQAE8AXwBTAGEAbgBzAF8ANAAuADAAXwBTAEM=' ;;           # OPPO_Sans_4.0_SC
  TC) B64='AE8AUABQAE8AXwBTAGEAbgBzAF8ANAAuADAAXwBUAEM=' ;;           # OPPO_Sans_4.0_TC
  *) echo "fontpatch: 未知类型 $KIND" >&2; exit 1 ;;
esac
echo "$B64" | $BB base64 -d > "$T/ps.bin" || exit 1
PSLEN=$($BB wc -c < "$T/ps.bin")

# --- 校验 sfnt 头 ---
MAGIC=$($BB od -An -tx1 -N 4 "$SRC" 2>/dev/null | $BB tr -d ' \n')
case "$MAGIC" in
  00010000|4f54544f|74727565) : ;;   # TTF / OTF(CFF) / true
  74746366) echo "fontpatch: 不支持 TTC 集合字体" >&2; exit 2 ;;
  *) echo "fontpatch: 不是有效的字体文件 (magic=$MAGIC)" >&2; exit 2 ;;
esac

NUM=$(r16 "$SRC" 4)
[ -z "$NUM" ] && { echo "fontpatch: 读取表数失败" >&2; exit 2; }

# --- 定位 name 表 ---
i=0; NOFF=""; NLEN=""; DENT=""
while [ "$i" -lt "$NUM" ]; do
  E=$((12 + i * 16))
  TAG=$($BB od -An -c -j "$E" -N 4 "$SRC" 2>/dev/null | $BB tr -d ' \n')
  if [ "$TAG" = "name" ]; then
    NOFF=$(r32 "$SRC" $((E + 8)))
    NLEN=$(r32 "$SRC" $((E + 12)))
    DENT=$E
    break
  fi
  i=$((i + 1))
done
[ -n "$NOFF" ] || { echo "fontpatch: 未找到 name 表" >&2; exit 3; }

# --- 复制 name 表并重建 ---
$BB dd if="$SRC" bs=1 skip="$NOFF" count="$NLEN" of="$T/nt.bin" 2>/dev/null
CNT=$(r16 "$T/nt.bin" 2)
[ -z "$CNT" ] && { echo "fontpatch: 解析 name 表失败" >&2; exit 3; }

STRLEN=$(( NLEN - (6 + CNT * 12) ))
[ "$STRLEN" -lt 0 ] && { echo "fontpatch: name 表结构异常" >&2; exit 3; }
NEWOFF=$STRLEN

$BB cat "$T/ps.bin" >> "$T/nt.bin"

j=0; PATCHED=0
while [ "$j" -lt "$CNT" ]; do
  R=$((6 + j * 12))
  PID=$(r16 "$T/nt.bin" "$R")
  NID=$(r16 "$T/nt.bin" $((R + 6)))
  if [ "$NID" = "6" ] && { [ "$PID" = "3" ] || [ "$PID" = "0" ]; }; then
    w16 "$T/nt.bin" $((R + 8))  "$PSLEN"
    w16 "$T/nt.bin" $((R + 10)) "$NEWOFF"
    PATCHED=$((PATCHED + 1))
  fi
  j=$((j + 1))
done

if [ "$PATCHED" -eq 0 ]; then
  # 没有 Unicode 平台的 PostScript 名记录: 退化为原样复制
  echo "fontpatch: 警告 - 未找到可改写的 PostScript 名记录, 使用原字体" >&2
  cp -f "$SRC" "$DST" && exit 0
fi

# --- 4 字节对齐 ---
SZ=$($BB wc -c < "$T/nt.bin")
PAD=$(( (4 - SZ % 4) % 4 ))
[ "$PAD" -gt 0 ] && $BB dd if=/dev/zero bs=1 count="$PAD" >> "$T/nt.bin" 2>/dev/null
NEWLEN=$($BB wc -c < "$T/nt.bin")

# --- 组装新文件: 原文件 + 对齐填充 + 新 name 表 ---
ORIGSZ=$($BB wc -c < "$SRC")
PADF=$(( (4 - ORIGSZ % 4) % 4 ))
OFFTAB=$(( ORIGSZ + PADF ))

$BB cat "$SRC" > "$DST"
[ "$PADF" -gt 0 ] && $BB dd if=/dev/zero bs=1 count="$PADF" >> "$DST" 2>/dev/null
$BB cat "$T/nt.bin" >> "$DST"

# --- 更新 name 表目录项 (checksum/offset/length) ---
w32 "$DST" $((DENT + 4))  0
w32 "$DST" $((DENT + 8))  "$OFFTAB"
w32 "$DST" $((DENT + 12)) "$NEWLEN"

echo "fontpatch: OK ($KIND, $PATCHED 个记录, 表长 $NEWLEN)"
exit 0
