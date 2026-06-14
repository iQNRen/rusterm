# Rusterm 项目改造记录

> 基于 [meatshell](https://github.com/iQNRen/meatshell) 二次开发
> 分支：`rusterm`（main 保持同步上游）

---

## 一、项目改名：meatshell → rusterm

### 改动范围

| 类型 | 文件 | 改动 |
|------|------|------|
| 包名 | `Cargo.toml` | `name = "rusterm"` |
| 源码 | `src/*.rs` (13个) | 所有字符串/注释中的 meatshell → rusterm |
| UI | `ui/*.slint` (5个) | 界面文本中的 meatshell → rusterm |
| 翻译 | `lang/zh/LC_MESSAGES/rusterm.po` | 文件名 + 内容 |
| 翻译 | `lang/en/LC_MESSAGES/rusterm.po` | 文件名 + 内容 |
| 构建 | `build.rs` | 翻译文件路径引用 |
| 文档 | `README.md`, `README.en.md`, `CONTRIBUTING.md`, `CHANGELOG.md` | 全部替换 |

### 注意事项

- `EXPORT_KEY` 从 `meatshell.export.portable.key.01` (32字节) 改为 `rusterm.export.portable.key.01ab` (32字节)，保持长度一致
- `ProjectDirs::from("dev", "rusterm", "rusterm")` — 配置目录变为 `~/.config/rusterm/`
- XDG app id 改为 `rusterm`

---

## 二、WebDAV 同步功能

### 新增依赖

```toml
reqwest = { version = "0.12", features = ["json"] }
sha2 = "0.10"
```

### 新增文件：`src/webdav.rs`

核心模块，约 190 行，提供：

| 函数 | 说明 |
|------|------|
| `load_settings()` | 从 `webdav.json` 读取配置 |
| `save_settings()` | 保存配置到 `webdav.json` |
| `test_connection()` | PROPFIND 测试 WebDAV 连接 |
| `upload()` | PUT sessions.json 到 WebDAV 服务器 |
| `download()` | GET 远端 sessions.json 到本地（自动备份为 .bak） |
| `create_collection()` | MKCOL 创建远端目录 |

### 配置文件：`webdav.json`

与 `sessions.json` 同目录（`~/.config/rusterm/`）：

```json
{
  "enabled": false,
  "base_url": "https://dav.jianguoyun.com/dav/rusterm-sync/",
  "username": "",
  "password": "",
  "auto_sync": false
}
```

### 技术细节

- **认证**：HTTP Basic Auth
- **完整性**：SHA256 校验上传/下载内容
- **备份**：下载前自动将本地 sessions.json 备份为 sessions.json.bak
- **异步**：所有网络操作通过 `slint::spawn_local` 异步执行，不阻塞 UI
- **错误处理**：anyhow + tracing 日志

### UI 集成

#### 侧边栏按钮（`ui/sidebar.slint`）

底部新增 ☁ WebDAV 按钮，点击打开设置对话框。

#### 设置对话框（`ui/app.slint`）

```
┌─────────────────────────────────┐
│         WebDAV 同步              │
│                                 │
│  服务器地址                       │
│  [https://dav.jianguoyun.com/..]│
│                                 │
│  用户名                          │
│  [user@example.com            ] │
│                                 │
│  应用密码                        │
│  [••••••••••                  ] │
│                                 │
│  ☑ 启用    ☑ 自动同步            │
│                                 │
│  [状态消息区域]                   │
│                                 │
│  [测试] [保存] [上传] [下载] [关闭]│
└─────────────────────────────────┘
```

### 回调接入（`src/app.rs`）

| 回调 | 行为 |
|------|------|
| `on_webdav_open_dialog` | 打开设置对话框 |
| `on_webdav_save_settings` | 保存配置到 webdav.json |
| `on_webdav_test_connection` | 异步 PROPFIND 测试，结果显示在状态栏 |
| `on_webdav_upload` | 异步 PUT 上传，显示 SHA256 前16位 |
| `on_webdav_download` | 异步 GET 下载，显示 SHA256 前16位 |

---

## 三、使用方式

### 坚果云配置

1. 登录坚果云 → 设置 → 安全选项 → 第三方应用管理
2. 添加应用，生成专用密码
3. 在 rusterm 侧边栏点击 ☁ WebDAV
4. 填写：
   - 服务器地址：`https://dav.jianguoyun.com/dav/你的目录/`
   - 用户名：坚果云邮箱
   - 密码：第三方应用专用密码
5. 点击「测试」确认连接
6. 点击「保存」

### 同步操作

- **上传**：将本地 sessions.json 上传到 WebDAV 服务器
- **下载**：从 WebDAV 服务器下载 sessions.json（本地文件自动备份为 .bak）

---

## 四、Git 工作流

```
main (上游同步)
  └── rusterm (开发分支)

同步上游：
  git checkout main
  git fetch upstream
  git merge upstream/main
  git checkout rusterm
  git rebase main
```

---

## 五、编译验证

```bash
cargo check   # ✅ 通过（2个 dead_code warning，正常）
cargo build   # 构建
cargo run     # 运行
```

---

## 六、文件变更清单

```
 M  CHANGELOG.md
 M  CONTRIBUTING.md
 M  Cargo.lock
 M  Cargo.toml              # +reqwest, +sha2, name=rusterm
 M  README.en.md
 M  README.md
 M  build.rs
 R  lang/en/LC_MESSAGES/meatshell.po → rusterm.po
 R  lang/zh/LC_MESSAGES/meatshell.po → rusterm.po
 M  src/app.rs              # +WebDAV 回调
 M  src/config.rs            # EXPORT_KEY 更新
 M  src/errlog.rs
 M  src/forward.rs
 M  src/i18n.rs
 M  src/main.rs              # +mod webdav
 M  src/sftp.rs
 M  src/ssh.rs
 M  src/ssh_config.rs
 A  src/webdav.rs            # 新增：WebDAV 同步模块
 M  src/zmodem.rs
 M  ui/app.slint             # +WebDAV 对话框 + 属性 + 回调
 M  ui/confirm_dialog.slint
 M  ui/sidebar.slint         # +WebDAV 按钮 + 回调
 M  ui/theme.slint
 M  ui/welcome.slint
```
