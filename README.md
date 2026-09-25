# ColorOS 通用字体安装器

**刷一次模块，之后换字体只需丢个 TTF 文件 —— 无需重新打包、无需刷机、无需重启。**

适用于 ColorOS 16（Android 16，OPPO / OnePlus / realme），基于 **KernelSU / Magisk**。

---

## ✨ 特性

| 特性 | 说明 |
|---|---|
| **任意字体** | 支持 TTF / OTF，中英文均自动处理 |
| **即时生效** | 应用后自动重启 SystemUI，界面**立刻**变字体，不用重启手机 |
| **自动适配** | 自动解析字体 `name` 表并改写 ColorOS 要求的 PostScript 名，任意字体都能装上 |
| **开机保持** | 重启后自动重新应用，不怕系统还原 |
| **systemless** | 靠 `mount --bind` 运行时挂载，**不修改 /system 分区** |
| **一键回滚** | 删除模块 + 重启即恢复原厂字体 |

---

## 📦 安装

1. 下载 Release 里的 `coloros_font_switcher.zip`
2. **KernelSU Manager / Magisk → 模块 → 从本地安装** → 选择 zip
3. 重启

---

## 🚀 使用（重点）

### 方式一：KernelSU Manager 一键切换（推荐）

1. 把任意字体文件放到手机：

   ```
   /sdcard/Fonts/font.ttf
   ```

   （或把任意 `.ttf` / `.otf` 放进 `/sdcard/Fonts/` 目录，会自动识别第一个）

2. 打开 **KernelSU Manager → 模块 → 「ColorOS 通用字体安装器」→ 点「执行」按钮**

3. 界面**立即**变成新字体 ✅

结果日志在 `/sdcard/Fonts/apply_result.log`。

### 方式二：命令行

```bash
su -c "sh /data/adb/modules/coloros_font_switcher/bin/apply.sh /sdcard/Fonts/你的字体.ttf"
```

也可以直接指定路径，不局限于 `/sdcard/Fonts/`。

### 重新应用 / 换回

- 换新字体：替换 `/sdcard/Fonts/font.ttf`，再点一次「执行」
- 用上次的字体：直接点「执行」（会读取上次保存的字体）

---

## 🔍 原理

### ColorOS 的字体结构

```
/system/etc/fonts.xml          ← 字体族定义（含 postScriptName 校验）
    ↓ 引用
/system/fonts/
├── Roboto-Regular.ttf         默认字体族（无 postScriptName 要求）
├── SysFont-Regular.ttf        符号链接 → Roboto-Regular.ttf
├── SysSans-En-Regular.ttf     英文      （要求 PostScript 名 OPlusSansEn）
├── SysSans-Hans-Regular.ttf   简体中文  （要求 PostScript 名 OPPO_Sans_4.0_SC）
└── SysSans-Hant-Regular.ttf   繁体中文  （要求 PostScript 名 OPPO_Sans_4.0_TC）
```

**关键点**：如果字体文件内部的 **PostScript 名（name 表 nameID=6）** 与 `fonts.xml` 中声明的
`postScriptName` 不匹配，该字体族会加载失败，**中文会回落到系统自带的 Noto CJK** ——
这正是"换了字体但中文没变"的原因。

### 本模块怎么解决

1. **解析字体的 sfnt 结构**（纯 busybox 实现，不需要 Python）：
   读取表目录 → 定位 `name` 表 → 遍历记录 → 找到 `nameID=6` 的记录

2. **重建 `name` 表**：把新的 PostScript 名追加到字符串区，改写记录的 `length` / `offset`，
   然后把整张表**追加到文件末尾**，并更新表目录项（offset / length）。

   > 这样做的好处：**其它表的数据一个字节都不动**，也不受新名字长度限制。

3. **`mount --bind`** 把生成好的 4 个文件覆盖到 `/system/fonts/` 对应路径

4. **重启 SystemUI** 让界面立即重新加载字体

---

## 🗂 生成的文件

```
/data/adb/font-switcher/
├── source.ttf          上次应用的字体（开机自动重应用）
├── work/               生成的 4 个可挂载文件
│   ├── Roboto-Regular.ttf
│   ├── SysSans-En-Regular.ttf
│   ├── SysSans-Hans-Regular.ttf
│   └── SysSans-Hant-Regular.ttf
├── apply.log           应用日志
└── boot.log            开机应用日志
```

---

## 🔄 回滚

```bash
# 1) 卸载挂载（立即恢复原厂字体）
for f in Roboto-Regular.ttf SysSans-En-Regular.ttf SysSans-Hans-Regular.ttf SysSans-Hant-Regular.ttf; do
    umount -l /system/fonts/$f
done
killall com.android.systemui

# 2) 永久移除
rm -rf /data/adb/modules/coloros_font_switcher
# 然后重启
```

或者直接在 KernelSU Manager 里卸载模块 + 重启。
开机时按住「音量下」可进入安全模式（禁用所有模块）。

---

## ⚠️ 注意事项

1. **不要与其它"系统字体替换"模块同时使用**（会互相覆盖，后启动的生效）。
2. **符号链接型字体**：`/system/fonts` 下很多文件名是符号链接（如 `DroidSans.ttf` → `Roboto-Regular.ttf`），
   所以覆盖 `Roboto-Regular.ttf` 会连带影响一大批字体名 —— 这是预期行为。
3. **TTC / 字体集合**暂不支持（脚本会明确报错）。
4. **字体建议带中文覆盖**，否则中文会回落到系统 Noto 字体（这是正常现象）。
5. 有些字体的 `name` 表没有 `nameID=6` 记录，脚本会给出警告并退化为原样使用。

---

## 📄 许可

模块脚本：MIT

---

## 🙏 相关项目

- [coloros-sarasa-font](https://github.com/DerekHemcis/coloros-sarasa-font) — 固定字体版本（Sarasa Mono SC）
- [KernelSU](https://kernelsu.org/)
