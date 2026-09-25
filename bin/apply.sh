#!/system/bin/sh
# 通用字体应用脚本
# 用法: apply.sh [字体路径] [--no-restart]
#
# 流程: 校验字体 -> 生成各目标文件(按 ColorOS 要求改写 PostScript 名) -> bind mount -> 重启 SystemUI

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

# ===== 需要替换的目标文件 与 对应的 PostScript 名类型 =====
# NONE = 无需改写; EN/SC/TC/EXT = 改写成 ColorOS 期望的名字
TARGETS="Roboto-Regular.ttf RobotoStatic-Regular.ttf SysSans-En-Regular.ttf SysSans-Hans-Regular.ttf SysSans-Hant-Regular.ttf OSans-Ext-Regular.otf"

kind_of() {
    case "$1" in
        Roboto-Regular.ttf)       echo NONE ;;
        RobotoStatic-Regular.ttf) echo NONE ;;
        SysSans-En-Regular.ttf)   echo EN ;;
        SysSans-Hans-Regular.ttf) echo SC ;;
        SysSans-Hant-Regular.ttf) echo TC ;;
        OSans-Ext-Regular.otf)    echo EXT ;;
        *)                        echo NONE ;;
    esac
}

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
[ -z "$FONTFILE" ] && [ -f "$FONTDIR/font.ttf" ] && FONTFILE="$FONTDIR/font.ttf"
if [ -z "$FONTFILE" ]; then
    for f in "$FONTDIR"/*.ttf "$FONTDIR"/*.otf "$FONTDIR"/*.TTF "$FONTDIR"/*.OTF; do
        [ -f "$f" ] && { FONTFILE="$f"; break; }
    done
fi
[ -z "$FONTFILE" ] && [ -f "$SAVED" ] && FONTFILE="$SAVED"

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

# ---------- 生成目标文件 ----------
log "生成字体副本……"
$BB rm -f "$WORK"/*.ttf "$WORK"/*.otf 2>/dev/null
for f in $TARGETS; do
    K=$(kind_of "$f")
    if sh "$MODDIR/bin/fontpatch.sh" "$FONTFILE" "$WORK/$f" "$K" >>"$LOG" 2>&1; then
        log "  ✓ 生成 $f ($K)"
    else
        log "  ✗ 生成失败 $f ($K)"
    fi
done

# 关键: 修正权限与属主 (从 /sdcard 复制来的字体权限可能是 600/660, 应用进程读不到)
$BB chmod 0644 "$WORK"/* 2>/dev/null
$BB chown root:root "$WORK"/* 2>/dev/null

# 保存一份供开机自动应用
$BB cp -f "$FONTFILE" "$SAVED" 2>/dev/null

# ---------- 挂载 ----------
clean_mount() {
    n=0
    while [ "$n" -lt 8 ] && $BB grep -q " $1 " /proc/mounts 2>/dev/null; do
        $BB umount -l "$1" 2>/dev/null || $BB umount "$1" 2>/dev/null || break
        n=$((n+1))
    done
}

log "挂载到 /system/fonts ……"
for f in $TARGETS; do
    T="/system/fonts/$f"
    [ -e "$T" ] || { log "  跳过(不存在): $f"; continue; }
    [ -f "$WORK/$f" ] || { log "  跳过(未生成): $f"; continue; }
    clean_mount "$T"
    if $BB mount --bind "$WORK/$f" "$T" 2>/dev/null; then
        log "  ✓ $f"
    else
        log "  ✗ $f 挂载失败"
    fi
done

# ---------- 重启 SystemUI 立即生效 ----------
if [ "$NORESTART" = "0" ]; then
    log "重启 SystemUI 使界面立即生效……"
    $BB killall com.android.systemui 2>/dev/null || pkill -f com.android.systemui 2>/dev/null
fi

log "完成 ✅"
exit 0
