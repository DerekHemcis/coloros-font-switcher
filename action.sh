#!/system/bin/sh
# KernelSU / Magisk 模块「执行」按钮
# 从 /sdcard/Fonts/ 取字体并即时应用
MODDIR="${0%/*}"
OUT="/sdcard/Fonts/apply_result.log"

mkdir -p /sdcard/Fonts 2>/dev/null

sh "$MODDIR/bin/apply.sh" 2>&1 | tee "$OUT"

# 同时在通知栏提示(部分系统会拦截,失败也无妨)
cmd notification post -t "字体安装器" -c reminder font_apply "字体已应用: $(grep -m1 '使用字体' "$OUT" 2>/dev/null | sed 's/.*: //')" >/dev/null 2>&1
exit 0
