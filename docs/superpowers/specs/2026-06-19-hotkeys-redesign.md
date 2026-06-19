# 快捷键系统重构设计

- **日期**：2026-06-19
- **范围**：rusterm 全局快捷键系统（配置、分发、录制 UI）

## 1. 背景与现状

当前快捷键实现存在三方面局限：

1. **只支持 `Ctrl + 单字符`**，无法表达 `Ctrl+Shift+X`、`Ctrl+Tab`、`F11`、`Ctrl+Enter` 等组合。
2. **新增快捷键需改 4 处**：`config.rs`（字段+默认值）、`app.slint`（属性）、`app.slint` 分发（`if`）、设置页录制列表（手写一项）。易漏、易不一致。
3. **分发是写死的 `if` 链**，两个快捷键绑同一组合会**同时触发**，无冲突检测。

### 现有快捷键（5 个）

| 功能 | 默认键 | 分发位置 |
|---|---|---|
| 新建标签页 | `Ctrl+T` | `app.slint:414` |
| 关闭标签 | `Ctrl+W` | `app.slint:418` |
| 切换侧边栏 | `Ctrl+B` | `app.slint:422` |
| 新建会话 | `Ctrl+N` | `app.slint:426` |
| 打开设置 | `Ctrl+,` | `app.slint:430` |

### 现有实现要点

- 配置：`config.rs` 的 `HotkeyConfig`（5 个 `String` 字段，serde 持久化）。
- 录制：设置页点按键 → `recording-hotkey` 属性 → `set-hotkey(action, key)` 回调。
- 分发：`app.slint:412-435` 的 `FocusScope.key-pressed` 内硬编码 5 个 `if`。

## 2. 目标

将快捷键系统重构为**表驱动单一数据源**，同时：

- **G1 组合键支持（标准档）**：支持 `Ctrl` / `Alt` / `Shift` 修饰键（含多修饰键组合）、字母数字符号、功能键 `F1`–`F12`、命名键 `Enter`/`Esc`/`Tab`/`Backspace`/方向键。不支持纯单键无修饰（避免与终端输入冲突）。
- **G2 功能扩展**：从 5 个扩展到 17 个功能。
- **G3 架构重构**：配置、分发、录制 UI 全部由一张定义表驱动；新增功能只需在表中加一行。
- **G4 终端聚焦规则**：全局快捷键即使终端聚焦也生效，但保留的终端控制字符永远放行、永不绑定。

## 3. 需求与约束

### 3.1 终端聚焦规则（已确认）

- 全局快捷键**始终生效**，不论焦点是否在终端。
- **保留字符集**（`Ctrl+C` / `Ctrl+D` / `Ctrl+Z`）**永远放行**、录制时禁止绑定 —— 被占用会导致 SSH 中断/EOF/挂起功能失效。
- 其他终端控制字符（`Ctrl+A/E/U/K/R/L` 等）允许自定义绑定，默认不绑。
- **`Ctrl+W` 维持现状** = "关闭标签"（不交给终端的"删词"，用户已习惯）。

### 3.2 不在本次范围（YAGNI）

- 系统级全局热键（应用未聚焦/最小化时触发）—— 用不上，不引入 `global-hotkey` 类库。
- 纯单键无修饰的快捷键（如单独 `Esc`、`F1`）—— 与终端输入冲突，不做。
- 按 action 单独配置"终端聚焦时是否生效"—— 过度灵活，统一规则即可。

## 4. 架构设计

### 4.1 数据结构

**Slint 端**（[widgets.slint](../../../ui/widgets.slint) 或 [app.slint](../../../ui/app.slint)）：

```slint
struct HotkeyBinding {
    action: string,     // "new-tab" / "next-tab" / "copy" / "fullscreen" ...
    key: string,         // "Ctrl+T" / "Ctrl+Shift+D" / "F11" / "Ctrl+Tab"
    label-zh: string,    // "新建标签页"
    label-en: string,
    group: string,       // "标签页" / "终端" / "界面"
}

in property <[HotkeyBinding]> hotkey-bindings;   // 由 Rust 生成并传入
callback trigger-action(string);                   // 分发入口
callback set-hotkey-binding(string, string);     // 录制 (action, key)
in-out property <string> hotkey-message: "";     // 录制冲突/提示文字
```

**Rust 端**（[config.rs](../../../src/config.rs)）—— 单一数据源：

- `HotkeyDef` 元数据表（`const`：`action` / 默认键 / `label-zh`/`label-en` / `group`）—— 所有功能的真相之源。
- `HotkeyConfig` 从现有 5 个具名字段改为 `HashMap<String, String>`（`action → key`）。
- 启动时遍历 `HotkeyDef`，用配置覆盖默认值，生成 `[HotkeyBinding]` 传给 Slint。
- **保留字符集**：一个 `const` 集合 `RESERVED = {"Ctrl+C", "Ctrl+D", "Ctrl+Z"}`，录制时拒绝。

### 4.2 组合键序列化格式

字符串格式：`[修饰键前缀]* + 主键`。

- 修饰键前缀顺序固定：`Ctrl+` → `Alt+` → `Shift+`（例：`Ctrl+Alt+Shift+X`）。
- 主键：
  - 字母：小写（`t`、`d`）。
  - 数字 / 符号：原样（`0`、`,`、`=`、`-`）。
  - 功能键：`F1`–`F12`。
  - 命名键：`Enter` / `Esc` / `Tab` / `Backspace` / `Left` / `Right` / `Up` / `Down`。
- 例：`Ctrl+T`、`Ctrl+Shift+D`、`Ctrl+Shift+Tab`、`F11`、`Ctrl+=`、`Ctrl+,`。

### 4.3 分发逻辑

重写 [app.slint:412-435](../../../ui/app.slint#L412) 的 `key-pressed`：

```slint
key-pressed(e) => {
    // 1) 录制优先：正在录制则捕获按键（不进正常分发）
    if root.recording-action != "" {
        if e.text == "Escape" { root.recording-action = ""; accept }
        else { root.set-hotkey-binding(root.recording-action, normalize(e)); accept }
    }
    // 2) 保留字符 → 放行给终端
    if is-reserved(e) { reject }
    // 3) 归一化 → 遍历表匹配
    let key = normalize(e);
    for b in root.hotkey-bindings {
        if b.key == key { root.trigger-action(b.action); accept }
    }
    reject
}
```

- `normalize(e)`：由 `e.modifiers`（control/alt/shift）+ 主键（`e.text` 小写化 或 `e.key-code` 映射为命名）组合出绑定字符串。
- `is-reserved(e)`：`Ctrl` 单修饰 + `text ∈ {c,d,z}` → 保留。
- `trigger-action(action)`：集中一处 `if/else` 分发到各行为（Slint 无法按名字动态调用回调，集中一处而非散落）。

### 4.4 `trigger-action` 行为对接

| action | 行为 | 接口状态 |
|---|---|---|
| `new-tab` | 新建标签 | ✅ `new-tab-clicked` |
| `close-tab` | 关闭当前标签 | ✅ `tab-closed(active-tab-id)` |
| `next-tab` | 切换到下一个标签 | 🆕 遍历 `tabs` 数组找 `active` 的 +1（末尾回 0） |
| `prev-tab` | 切换到上一个标签 | 🆕 同上 -1（首回末） |
| `toggle-sidebar` | 切换侧边栏 | ✅ 翻转 `sidebar-collapsed` |
| `settings` | 开关设置面板 | ✅ 翻转 `settings-open` |
| `toggle-theme` | 切换深浅主题 | ✅ `toggle-theme` |
| `fullscreen` | 切换全屏 | 🆕 Rust `set-fullscreen(bool)` → `window.set_fullscreen` |
| `new-session` | 新建会话 | ✅ `new-session-clicked` |
| `disconnect` | 断开当前会话 | ✅ 复用 `tab-closed(active-tab-id)` |
| `copy` | 复制终端选区 | ✅ active 终端 `copy-terminal-text()` |
| `paste` | 粘贴 | ✅ active 终端 `paste-from-clipboard()` |
| `font-bigger` | 放大字体 | ✅ `set-term-font-size(cur + 1)` |
| `font-smaller` | 缩小字体 | ✅ `set-term-font-size(cur - 1)` |
| `font-reset` | 重置字体大小 | ✅ `set-term-font-size(13)` |

> `copy` / `paste` 操作**当前 active 终端**（不论焦点）。非终端聚焦时 `Ctrl+Shift+C/V` 也作用于 active 终端，不单独处理 UI 输入框（YAGNI）。

### 4.5 默认键位表（17 个）

| 分组 | 功能 | 默认键 |
|---|---|---|
| 标签页 | 新建 / 关闭 / 下一个 / 上一个 | `Ctrl+T` / `Ctrl+W` / `Ctrl+Tab` / `Ctrl+Shift+Tab` |
| 界面 | 侧边栏 / 设置 / 主题 / 全屏 | `Ctrl+B` / `Ctrl+,` / `Ctrl+Shift+L` / `F11` |
| 会话 | 新建 / 断开 | `Ctrl+N` / `Ctrl+Shift+D` |
| 终端 | 复制 / 粘贴 / 放大 / 缩小 / 重置 | `Ctrl+Shift+C` / `Ctrl+Shift+V` / `Ctrl+=` / `Ctrl+-` / `Ctrl+0` |

所有键位均为默认值，用户可在设置页录制修改。

### 4.6 录制 UI

设置页"快捷键"页，遍历 `hotkey-bindings` 按 `group` 分组渲染：

```
┌─ 标签页 ──────────────────────────┐
│ 新建标签页            [ Ctrl + T ] │
│ 关闭标签              [ Ctrl + W ] │
│ 下一个标签            [ Ctrl+Tab ] │
└─────────────────────────────────────┘
┌─ 终端 ────────────────────────────┐
│ 复制                 [Ctrl+Shift+C]│
└─────────────────────────────────────┘
```

- 每行一个按键按钮，点击 → `recording-action = action`，按钮高亮显示"按下按键…（Esc 取消）"。
- `key-pressed` 录制优先捕获（见 4.3）。
- 提示文字 `hotkey-message` 显示在录制行下方。

### 4.7 冲突检测

在 `set-hotkey-binding` 的 **Rust 端**完成，返回结果通过 `hotkey-message` 显示：

| 情况 | 处理 |
|---|---|
| key 被别的 action 占用 | ❌ 拒绝，提示"与「{冲突功能}」冲突" |
| key 在保留集（`Ctrl+C/D/Z`） | ❌ 拒绝，提示"该组合保留给终端" |
| 无冲突 | ✅ 保存、持久化、刷新 `hotkey-bindings` 该行 |

### 4.8 功能处快捷键提示（发现性）

让用户在**功能所在位置**直观看到快捷键存在，而不仅埋在设置页：

- 在**有可见按钮的主功能**旁显示淡色 badge（如 `Ctrl+T`），颜色用 `Theme.text-muted`，跟随 `hotkey-bindings` **实时更新**（用户改键后 badge 自动变）。
- 显示 badge 的功能（有固定按钮）：
  - 新建标签（TabBar 的 `+` 按钮）
  - 切换侧边栏（侧边栏折叠按钮）
  - 打开设置（设置按钮）
  - 切换主题（主题按钮）
- **无固定按钮的功能**（关闭标签的 ×、复制/粘贴/字体缩放/全屏/切标签等）：仅在设置页快捷键列表中可见，不强行加 badge。
- **交互**：badge 仅显示，不触发录制（避免与按钮自身点击冲突）。点击 badge 弹提示"在设置 → 快捷键中修改"或无响应。
- **修改入口**统一在设置页快捷键页（见 4.6）。

## 5. 向后兼容

- 旧配置 json 中的具名字段（`new_tab` / `close_tab` / `toggle_sidebar` / `new_session` / `settings`）在 deserialize 时**迁移**到 `HashMap`：读旧字段 → 填入对应 `action`。
- 迁移后写出新格式 json，旧字段不再写入。
- 默认值仍来自 `HotkeyDef` 表，缺失项自动补默认。

## 6. 改动清单（高层）

| 文件 | 改动 |
|---|---|
| [config.rs](../../../src/config.rs) | `HotkeyConfig` → `HashMap`；新增 `HotkeyDef` 表 + `RESERVED` 集 + 迁移逻辑 |
| [app.rs](../../../src/app.rs) | 启动构建 `[HotkeyBinding]`；`set_hotkey_binding` 含冲突检测；新增 `set_fullscreen` |
| [app.slint](../../../ui/app.slint) | `HotkeyBinding` struct + 属性 + 重写 `key-pressed` + `trigger-action` 分发 + 录制状态 + 录制 UI（设置页遍历表渲染 + 冲突提示） + 主功能按钮 badge 显示 |

> 录制 UI 留在现有快捷键设置页（[app.slint](../../../ui/app.slint) 的 `ifd-page == "hotkey"` 区块），不引入 `widgets.slint` 改动。

## 7. 验证标准

- 17 个默认快捷键全部生效（含 `Ctrl+Shift+` 组合、`F11`、`Ctrl+Tab`）。
- 录制修改后重启应用，自定义键位保持。
- 绑保留字符（`Ctrl+C/D/Z`）被拒绝并提示。
- 绑已被占用的组合被拒绝并提示冲突功能。
- 终端聚焦时 `Ctrl+C/D/Z` 仍正常中断/EOF/挂起。
- 旧配置 json 升级后快捷键不丢失。
- 新建标签/侧边栏/设置/主题按钮处显示快捷键 badge；改键后 badge 实时更新。
