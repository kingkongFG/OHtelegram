// 复制本文件为同目录下的 ApiCredentials.ets，然后填入你自己的 Telegram 应用凭据。
//
// 获取凭据：打开 https://my.telegram.org/apps 注册一个应用，即可得到 api_id 与 api_hash。
//
// 本仓库不包含任何 api_id / api_hash，也不包含任何生成或混淆凭据的脚本，
// 必须由你自己注册后填写下面两项。ApiCredentials.ets 已被 .gitignore 忽略，
// 切勿提交；它不是本仓库的一部分，也不会出现在任何发布内容里。
//
// 填好之后的完整构建链：在 DevEco Studio 打开工程 → File > Project Structure >
// Signing Configs > 勾选 Support HarmonyOS 自动签名 → 构建 HAP → 运行到设备。
// 详见 README 的 Quick start 一节。
//
// Copy this file to ApiCredentials.ets in the same directory and fill in your own
// Telegram application credentials. This repository ships NO api_id/api_hash and no
// credential packing script — register at https://my.telegram.org/apps yourself.

// 你的 api_id：纯数字（your api_id from my.telegram.org）
export const apiId: number = 0;

// 你的 api_hash：32 位十六进制字符串（your api_hash from my.telegram.org）
export const apiHash: string = '';

// 可选：自建推送中转的基础地址（MeoW 推送模式使用，见 WebPushPage）。
// 留空则完全隐藏 MeoW 入口，只保留手动粘贴 endpoint/p256dh/auth 的 WebPush 模式。
// Optional: base URL of a self-hosted push relay (MeoW push mode). Leave empty to
// hide the MeoW entry entirely.
export const pushRelayBase: string = '';

// 每次中转请求携带的 Bearer token，与 pushRelayBase 同时非空时 MeoW 入口才会出现。
// Bearer token sent on every relay request. Must also be non-empty together with
// pushRelayBase for the MeoW entry to appear.
export const pushRelayToken: string = '';

// 可选：崩溃上报接收端。留空则完全不上传，本地记录照常保留。
// 接口：POST {crashReportBase}/crash，Authorization: Bearer {crashReportToken}，
// 请求体是一条 CrashRecord（见 services/crashReport），返回 2xx 视为成功。
// 载荷不含任何用户内容：只有时间、应用版本、崩溃类型、前后台、进程存活时长、
// 异常名/信息/堆栈；hilog 与 external_log 刻意不取（那两样含聊天痕迹）。
// Optional: crash-report collector. Leave empty to disable uploading entirely.
export const crashReportBase: string = '';
export const crashReportToken: string = '';
