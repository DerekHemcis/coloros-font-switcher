#!/system/bin/sh
# 开机自动挂载已应用过的字体
# 注意: 只做"挂载", 不做生成 —— 生成在用户点「执行」时已一次性完成
#       这样开机负担极小, 不会拖慢启动 / 触发 KernelSU 防变砖

MODDIR="${0%/*}"
DATA=/data/adb/font-switcher
WORK="$DATA/work"
LOG="$DATA/boot.log"

# 没应用过字体就直接退出
[ -f "$DATA/source.ttf" ] || exit 0
[ -d "$WORK" ] || exit 0

# 至少有生成好的文件才继续
ls "$WORK"/*.ttf "$WORK"/*.otf >/dev/null 2>&1 || exit 0

# 等 /system/fonts 就绪
i=0
while [ ! -f /system/fonts/Roboto-Regular.ttf ] && [ $i -lt 20 ]; do
    sleep 0.5
    i=$((i+1))
done

echo "[$(date '+%F %T')] 开机挂载字体" >> "$LOG"
sh "$MODDIR/bin/apply.sh" --mount-only >> "$LOG" 2>&1
exit 0
