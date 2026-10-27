# 自动构建 Android APK

在仓库 Actions 选择 **Build Android APK → Run workflow**。
修改 `xianyu-mobile/` 或该工作流并推送到 main 也会自动构建。

构建成功后，进入仓库 **Releases**，下载该次预发布中的
`xianyu-mobile-arm64.apk`，传到安卓手机安装。也可从 Actions 的 Artifacts
下载 `xianyu-mobile-arm64` 压缩包，解压得到 APK。校验文件为 `SHA256SUMS.txt`。

这是 ARM64（arm64-v8a）安装包，面向 64 位安卓手机；不包含 32 位或 x86 模拟器版本。
工作流运行 Node 24、Java 17 和项目 Gradle wrapper，使用锁文件安装依赖，
调用 `assembleRelease`，打包 JavaScript 和资源，无需 Metro、Expo Go 或 Expo 账号。
构建完会校验 APK 签名。

目前沿用项目已提交的 debug.keystore 签名，供个人安装验证，不能视为私有的正式发布签名。
同一份签名可用于后续覆盖安装；正式对外发布前需要配置自己的签名密钥。

安装后在 App 的服务器配置中填写 `http://NAS局域网IP:19000`，
使用现有后台账号登录。手机需要能够访问该地址。
Android 原生配置已允许 HTTP，适用于当前局域网部署。

本流程只构建手机 App，不会更新 NAS 上的容器或数据。
