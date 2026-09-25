#!/system/bin/sh
# 开机自动应用已保存的字体
MODDIR="${0%/*}"
DATA=/data/adb/font-switcher

[ -f "$DATA/source.ttf" ] || exit 0
mkdir -p "$DATA"

# 等 /system/fonts 就绪
i=0
while [ ! -d /system/fonts ] && [ $i -lt 20 ]; do
    sleep 0.5
    i=$((i+1))
done

sh "$MODDIR/bin/apply.sh" --no-restart >> "$DATA/boot.log" 2>&1
exit 0
