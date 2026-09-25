#!/system/bin/sh
# 通用字体应用脚本
# 用法: apply.sh [字体路径] [--no-restart]
#
# 流程: 校验字体 -> 生成 4 份(按 ColorOS 要求改写 PostScript 名) -> bind mount -> 重启 SystemUI

SELF="${0%/*}"
MODDIR="${SELF%/*}"

umask 022

BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=busybox

DATA=/data/adb/font-switcher
WORK="$DATA/work"
LOG="$DATA/apply.log"
SAVED="$DATA/source.ttf"
FONTDIR=/sdcard/Fonts

mkdir -p "$DATA" "$WORK" 2>/dev/null
: > "$LOG"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG" >&2; echo "$*"; }

# ---------- 参数解析 ----------
FONTFILE=""; NORESTART=0
for a in "$@"; do
    case "$a" in
        --no-restart) NORESTART=1 ;;
        --*)          : ;;
        *)            [ -f "$a" ] && FONTFILE="$a" ;;
    esac
done

# ---------- 查找字体 ----------
if [ -z "$FONTFILE" ]; then
    # 1) /sdcard/Fonts/font.ttf
    [ -f "$FONTDIR/font.ttf" ] && FONTFILE="$FONTDIR/font.ttf"
fi
if [ -z "$FONTFILE" ]; then
    # 2) /sdcard/Fonts/ 下任意 ttf/otf
    for f in "$FONTDIR"/*.ttf "$FONTDIR"/*.otf "$FONTDIR"/*.TTF "$FONTDIR"/*.OTF; do
        [ -f "$f" ] && { FONTFILE="$f"; break; }
    done
fi
if [ -z "$FONTFILE" ]; then
    # 3) 上次保存的
    [ -f "$SAVED" ] && FONTFILE="$SAVED"
fi

if [ -z "$FONTFILE" ] || [ ! -f "$FONTFILE" ]; then
    log "错误: 未找到字体文件。请把 ttf/otf 放到 $FONTDIR/ 或直接传入路径"
    exit 1
fi

log "使用字体: $FONTFILE"

# ---------- 校验 ----------
MAGIC=$($BB od -An -tx1 -N 4 "$FONTFILE" 2>/dev/null | $BB tr -d ' \n')
case "$MAGIC" in
    00010000|4f54544f|74727565) : ;;
    74746366) log "错误: 不支持 TTC 集合字体"; exit 2 ;;
    *) log "错误: 不是有效的 ttf/otf (magic=$MAGIC)"; exit 2 ;;
esac

# ---------- 生成 4 份 ----------
log "生成字体副本……"
$BB rm -f "$WORK"/*.ttf
sh "$MODDIR/bin/fontpatch.sh" "$FONTFILE" "$WORK/Roboto-Regular.ttf"  NONE || { log "错误: 生成失败"; exit 3; }
sh "$MODDIR/bin/fontpatch.sh" "$FONTFILE" "$WORK/SysSans-En-Regular.ttf"   EN  || { log "错误: 生成失败(EN)"; exit 3; }
sh "$MODDIR/bin/fontpatch.sh" "$FONTFILE" "$WORK/SysSans-Hans-Regular.ttf" SC  || { log "错误: 生成失败(SC)"; exit 3; }
sh "$MODDIR/bin/fontpatch.sh" "$FONTFILE" "$WORK/SysSans-Hant-Regular.ttf" TC  || { log "错误: 生成失败(TC)"; exit 3; }

# 保存一份供开机自动应用
$BB cp -f "$FONTFILE" "$SAVED" 2>/dev/null

# 关键: 修正权限与属主 (从 /sdcard 复制来的字体权限可能是 600/660, 应用进程读不到)
$BB chmod 0644 "$WORK"/*.ttf 2>/dev/null
$BB chown root:root "$WORK"/*.ttf 2>/dev/null

# 清理已有挂载(避免多层堆叠; 被占用的用 lazy 卸载)
clean_mount() {
    n=0
    while [ "$n" -lt 8 ] && $BB grep -q " $1 " /proc/mounts 2>/dev/null; do
        $BB umount -l "$1" 2>/dev/null || $BB umount "$1" 2>/dev/null || break
        n=$((n+1))
    done
}

# ---------- 挂载 ----------
log "挂载到 /system/fonts ……"
for f in Roboto-Regular.ttf SysSans-En-Regular.ttf SysSans-Hans-Regular.ttf SysSans-Hant-Regular.ttf; do
    T="/system/fonts/$f"
    [ -f "$T" ] || { log "  跳过(不存在): $f"; continue; }
    clean_mount "$T"
    if $BB mount --bind "$WORK/$f" "$T" 2>/dev/null; then
        $BB chcon u:object_r:system_file:s0 "$T" 2>/dev/null
        log "  ✓ $f"
    else
        log "  ✗ $f 挂载失败"
    fi
done

# SysFont-Regular.ttf 是符号链接, 若指向别处则一并覆盖
REAL=$($BB readlink -f /system/fonts/SysFont-Regular.ttf 2>/dev/null)
if [ -n "$REAL" ] && [ "$REAL" != "/system/fonts/Roboto-Regular.ttf" ] && [ -f "$REAL" ]; then
    clean_mount "$REAL"
    $BB mount --bind "$WORK/Roboto-Regular.ttf" "$REAL" 2>/dev/null && log "  ✓ (符号链接目标) $REAL"
fi

# ---------- 重启 SystemUI 立即生效 ----------
if [ "$NORESTART" = "0" ]; then
    log "重启 SystemUI 使界面立即生效……"
    $BB killall com.android.systemui 2>/dev/null || pkill -f com.android.systemui 2>/dev/null
fi

log "完成 ✅"
exit 0
