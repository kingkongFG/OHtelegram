# Petrelgram

[English](README.md) · **简体中文** · [Русский](README.ru.md) · [Français](README.fr.md)

[![Telegram](https://img.shields.io/badge/Telegram-加入群组-26A5E4?style=flat&logo=telegram&logoColor=white)](https://t.me/+khkR9mLZyoliODFl)
[![Release](https://img.shields.io/github/v/release/miramira8295/Petrelgram?style=flat)](https://github.com/miramira8295/Petrelgram/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat)](LICENSE)

一个开源的**非官方 HarmonyOS NEXT Telegram 客户端**。使用 ArkTS/ArkUI 编写，
通过原生 N-API 桥接 [TDLib](https://core.telegram.org/tdlib)（Telegram 官方客户端库）。

## 功能

- **账号** —— 手机号登录与两步验证、多账号登录、切换与退出
- **会话列表** —— 文件夹、归档、未读角标、实时连接状态
- **消息** —— 富文本、图片、相册、视频、文件、贴纸（WEBP / TGS / WEBM）、
  自定义表情、回复、转发、表情回应、评论串、置顶消息、定时消息、多选
- **发送** —— 提及与命令自动补全、媒体、文件、语音、音乐、位置、联系人、
  投票、骰子
- **通话** —— 基于 tgcalls 的端到端加密一对一语音/视频
- **群组语音与直播** —— 多人语音、摄像头与屏幕共享、频道直播、应用内悬浮窗
- **话题与故事** —— 论坛话题列表与话题内独立消息流；全屏故事查看器
- **搜索** —— 覆盖 11 个类别的全局搜索
- **资料页** —— 用户、Bot、群组与频道；头像、简介、用户名编辑；二维码名片
- **设置** —— 隐私与安全、通知、存储、设备与会话、聊天文件夹、省电模式、深色模式

## 目录结构

```
AppScope/            应用级配置（包名、图标）
entry/src/main/ets/
  tdkit/             TDLib N-API 桥、客户端、鉴权服务
  store/             不可变 store + 订阅机制（会话、消息、资料等）
  pages/             ArkUI 页面（登录、会话列表、聊天、资料、搜索……）
  services/          媒体流式播放、直播后台任务、语音录制与播放
  util/              解析/格式化工具（富文本、相册、日期……）
entry/src/main/cpp/  原生桥（libentry.so → libtdjson.so / libtgcalls_ohos.so）
entry/src/test/      单元测试（通过 scripts/run-local-tests.sh 运行）
libs/                ijkplayer-2.0.13-pg.10.har（由 oh-package.json5 引用）
entry/libs/arm64-v8a/ 预编译 libentry.so / libtdjson.so / libtgcalls_ohos.so
third_party/         libvpx-ohos/、rlottie-ohos/ 静态库与头文件
scripts/             可选的重建脚本（TDLib/tgcalls/libvpx/rlottie/ijkplayer）、
                     本地测试门禁
```

## 构建

### 环境要求

- **DevEco Studio 6.0+**，含自带的 OpenHarmony SDK/NDK
- HarmonyOS NEXT 设备或模拟器（arm64-v8a）
- 华为开发者账号（仅"自动签名"这一步需要）

构建前不需要额外安装任何东西：原生库与 ijkplayer 包都已在仓库里。

### 1. 原生库（已随仓库提供）

`libentry.so` 依赖的全部产物都已入库，clone 之后既不需要下载，也不需要编译：

| 路径 | 内容 |
| --- | --- |
| `entry/libs/arm64-v8a/` | `libentry.so`（N-API 桥）、`libtdjson.so`（约 33 MB）、`libtgcalls_ohos.so`（约 18 MB） |
| `third_party/libvpx-ohos/` | `libvpx.a` 与头文件 |
| `third_party/rlottie-ohos/` | `librlottie.a` 与头文件 |
| `libs/` | `ijkplayer-2.0.13-pg.10.har`，由 `oh-package.json5` 引用 |

由此可得：

- **不需要**运行 `scripts/fetch-libs.sh`、`scripts/fetch-tdlib.sh`、
  `scripts/fetch-ijkplayer.sh`、`scripts/build-tdlib.sh`、
  `scripts/build-tgcalls-ohos.sh`、`scripts/build-libvpx-ohos.sh`、
  `scripts/build-rlottie-ohos.sh`。这些脚本仅保留用于从源码重建，需要 OHOS NDK
  工具链（clang、cmake、ninja、gperf、patchelf），且首次构建 WebRTC 耗时很长。
- `entry/build-profile.json5` 不声明 `externalNativeOptions`，hvigor 不会编译
  C++ 桥，而是把预编译的 `libentry.so` 原样打包。重建它属于独立且少见的步骤，
  见本节末尾。
- 版本参考：TDLib 1.8.65；tgcalls 见
  [`scripts/tgcalls/README.md`](scripts/tgcalls/README.md)；ijkplayer
  `2.0.13-pg.10`，异步释放补丁为 `scripts/ijkplayer-pg10-async-release.patch`。

### 2. Telegram API 凭据（需自行注册）

本仓库**不包含**任何 `api_id`/`api_hash`，也不包含任何生成、打包或混淆它们的
脚本。没有你自己申请的凭据，TDLib 无法登录：

1. 在 <https://my.telegram.org/apps> 注册一个应用，页面会给出 `api_id`（数字）
   与 `api_hash`（32 位十六进制）。
2. 把 `entry/src/main/ets/tdkit/ApiCredentials.template.ets` 复制为同目录下的
   `ApiCredentials.ets`。
3. 在这份副本里填写两个明文常量：

   ```ts
   export const apiId: number = 1234567;                              // 你的 api_id
   export const apiHash: string = '0123456789abcdef0123456789abcdef'; // 你的 api_hash
   ```

   同一文件还带四个可选字段 —— `pushRelayBase`、`pushRelayToken`、
   `crashReportBase`、`crashReportToken` —— 除非你自建推送中转或崩溃上报接收端，
   否则保持空串即可。留空只会隐藏对应功能，不影响其它任何部分。
4. 直接构建。没有其它文件读取这两个值，构建过程也不需要联网。

`**/ApiCredentials.ets` 已写入 `.gitignore`，填好的副本不会被误提交 ——
**切勿提交真实凭据**，一旦泄露请立即吊销并重新注册。也不要贴到 issue、截图或
日志里：它们标识的是你的应用而非账号，但同样不宜公开。

### 3. 签名

`build-profile.json5` 中的 `signingConfigs` 为空，仓库里没有任何证书、密钥库或
Profile：

1. 用 DevEco Studio 打开工程。
2. 进入 **File > Project Structure > Signing Configs**，勾选
   **Automatically generate signature**（HarmonyOS 自动签名，要求 IDE 已登录
   华为开发者账号）。
3. 由 DevEco Studio 为 `com.ohtelegram.client` 生成调试证书与 Profile，产物存放
   在你的用户目录下，不在仓库内。

构建产物同样不入库：HAP 只出现在 `entry/build/` 下，该目录已被 gitignore。

上游源码曾把本地证书、密钥库与 Profile 的绝对路径连同密钥库口令以明文形式提交进
仓库，本仓库已全部移除。如果你基于上游构建，请视为这些材料已泄露：务必自行生成
证书，不要复用任何已公开的密钥库或口令。

### 4. 构建与运行

整个流程就是 DevEco Studio 里的四步：

1. **打开工程** —— `File > Open` 选择仓库根目录（含 `build-profile.json5` 的那
   一层），等 IDE 打开时自动执行的同步（含 `ohpm install`）跑完。
2. **配置签名** —— 见上文第 3 步。
3. **构建 HAP** —— `Build > Build Hap(s)/APP(s) > Build Hap(s)`，或在 `PATH` 含
   `hvigorw` 的终端执行 `hvigorw assembleHap --no-daemon`。产物位于
   `entry/build/default/outputs/default/`。
4. **运行到设备** —— 连接已开启 USB 调试的 HarmonyOS NEXT 设备（或启动模拟
   器），在设备选择器中选中它并点击 **Run**。首次启动要求输入手机号与 Telegram
   下发的登录码，其余由 TDLib 完成。

因为不声明 `externalNativeOptions`，这条链路打包的是 `entry/libs/arm64-v8a/` 里
的预编译 `libentry.so`，不编译桥接层。构建前、构建中、构建后都不需要运行任何
`fetch-*` / `build-*` 脚本。

可选，仅在改动 C++ 源码后需要：把指向 `entry/src/main/cpp`、
`abiFilters: ["arm64-v8a"]` 的 `externalNativeOptions` 加回
`entry/build-profile.json5`（CMake 工程与 `entry` 共享目标仍在树内，
`project(Petrelgram)`），构建一次让 cmake/ninja 产出 `libentry.so`，复制到
`entry/libs/arm64-v8a/`，再把这个选项去掉。把桥接层排除在应用构建之外是有意为之：
它是几千行很少改动的 C++，而 HAP 构建每天要跑很多次。

可选自检，仅面向贡献者（需要 Node.js，不属于应用构建）：

```bash
./scripts/run-local-tests.sh    # 必须输出 "LOCAL TESTS: PASS"
```

该脚本先跑 i18n 检查再跑单测 —— 一秒出结果的静态检查不该排在两分钟的测试构建后面。

## 本地化

界面文案全部在资源文件里。源语言（简体中文）放在
`entry/src/main/resources/base/element/string.json`，译文放在语言限定词目录
（如 `en_US/element/string.json`），复数在 `element/plural.json`。系统按设备语言
自动匹配，匹配不到时回落 `base`。

**`$r()` 还是 `str()`。** 组件渲染的文案一律用 `$r('app.string.x')`：它是一个
`Resource`，ArkUI 在配置变更时会重新解析，所以切语言能当场生效。`str('x')`
返回的是普通字符串，构建时就定死了 —— 只在确实需要 `string` 的地方用：
`string` 类型的 `@State`、模型字段、比较、`.join()`、以及非 UI 代码。
`@Builder` 参数遇到类型冲突时把它放宽成 `ResourceStr`，不要把调用点改回 `str()`。

**模块级 `const` 不能装文案。** 常量在首次 import 时就构建了，那时字符串源还没
装好，语言会被冻在那一刻。改成函数（`fallbackCountries()` 而不是
`FALLBACK_COUNTRIES`）。

**不要拿显示文案当状态匹配。** `label.substring(0, 2)`、`text.includes('重试')`
这类写法在换语言的瞬间就失效，判断要落在结构化字段上。

只进 `console.*` 的诊断字符串不翻译，用 `// i18n-exempt: <理由>` 标注。

```bash
node scripts/i18n-extract.mjs               # 按域统计仍硬编码的中文文案
node scripts/i18n-extract.mjs --domain util # 某个域的明细与 key 建议
node scripts/i18n-lit.mjs <file>            # 列出单个文件的中文字面量与行号
node scripts/i18n-check.mjs                 # 门禁（已并入 run-local-tests.sh）
```

`i18n-check.mjs` 检查五件事：代码引用的 key 在 `base` 中存在；`base` 里的每个 key
都能在代码中找到引用；**资源值里不得残留 `${` 模板源，且各语言的占位符编号集合
必须一致**；语言目录没有 `base` 之外的孤儿 key、各语言缺哪些词条；**已纳入门禁的
目录中不得再出现中文字面量**。

第三条是补上的 —— 门禁、单测、编译器各自能看见一类错误，但谁都看不见
「`file_downloading` 的值是 `${sizeLabel} · 正在下载` 这段模板源本身」，这种错误
只会在设备上显形。

`scripts/i18n-config.mjs` 的 `MIGRATED` 现在覆盖全部源码目录 —— 新建目录要一并
加进去，否则门禁会悄悄跳过它。key 命名 `<域>_<组件>_<语义>`，如
`chat_forward_title`。

## 状态与声明

- 开发中；界面以尽量贴近官方 Android 客户端为目标。
- 这是一个**非官方**客户端。请使用你自己的 API 凭据，并遵守
  [Telegram API 服务条款](https://core.telegram.org/api/terms)。
- 陌生用户搜索遵循 Telegram/TDLib 的服务端可发现性规则，通常只能找到拥有公开
  用户名或已进入服务端搜索范围的用户，不能通过该功能枚举任意手机号。

## 许可证

[Apache License 2.0](LICENSE)
