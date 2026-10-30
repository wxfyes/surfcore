# SurfCore Mobile (Flutter 跨平台客户端)

一套 Dart 源码，支持 **Android** 和 **iOS** 移动端，专为 SurfCore 设计的独立私人聊天伴侣客户端。

---

## 一、核心特性
- **直接对接小主机**：无需腾讯 QQ 参与，通过专属 `pet-api` 进行一对一加密直连。
- **作息与状态感知**：实时同步搭档当前的作息节律（在线/闲聊/B站冲浪/睡眠休息/专注模式）。
- **主动找你（主动搭话）**：内置长轮询（Long-Polling）事件通道，当她在电脑上产生思考、想主动找你聊天时，手机端立刻收到消息。
- **双端自适应**：支持 Android 与 iOS，自适应深色/浅色模式，本地消息记录持久化。

---

## 二、如何连接小主机？

打开 App 顶部的 **设置图标（⚙️）**：
1. **主机 IP**：
   - 如果手机和小主机在同一个 Wi-Fi（局域网）：填小主机内网 IP（如 `192.168.1.213`）。
   - 如果手机在外面（使用流量）：打开手机上的 **Tailscale**，填小主机在 Tailscale 中的虚拟 IP（如 `100.x.x.x`）。
2. **端口 (Port)**：填 `3080`（或当前 DSH 服务端口）。
3. **Token**：填你的 `pet-token`（在小主机 DSH 设置页面的【桌宠】卡片里可直接复制）。
4. 点击 **【一键测试连接】**，绿灯亮起即代表打通！

---

## 三、如何打包与运行？

在 `mobile` 目录下：

### 1. 本地连接手机调试运行：
```bash
flutter run
```

### 2. 打包 Android APK 安装包（直接安装到安卓手机）：
```bash
flutter build apk --release
```
编译产物位于：`mobile/build/app/outputs/flutter-apk/app-release.apk`。

### 3. iOS 编译运行：
在 Mac 终端中进入工程：
```bash
flutter build ios --release
```
或直接用 Xcode 打开 `mobile/ios` 文件夹运行签名安装。
