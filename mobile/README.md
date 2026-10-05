# CipherPenny Android

CipherPenny 的 Flutter Android 版。范围见 [spec 第 8 节](../docs/spec.md)，架构见 [design 第 8 节](../docs/design.md)。加密格式和同步规则与 Web 端相同（[vault-format.md](../docs/vault-format.md)），两端通过同一个 GitHub 私有仓库同步。

## 开发

需要 Flutter 3.47+、Android SDK 36、JDK 21。

```bash
flutter pub get
flutter test        # 包括 ../fixtures/ 下的解析、合并和加密测试向量
flutter analyze
flutter run         # 连接手机（开启 USB 调试）或模拟器
```

## 构建安装包

```bash
flutter build apk --release --split-per-abi
# 现代手机用 build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

release 包目前用本机的调试密钥签名。以后在同一台电脑上构建的新版本可以直接覆盖安装；换电脑构建会因为签名不同而无法覆盖，需要先卸载（卸载会删除本地数据，开启了同步的话可以再从 GitHub 恢复）。

## 在新手机上使用

1. 安装后打开，选择“已在其他设备开启同步？从 GitHub 恢复”。
2. 填写 Web 端开启同步时用的仓库（例如 `owner/cipher-penny-data`）、令牌和主密码。
3. 之后两端各自记账，解锁时、保存后约 10 秒、App 回到前台、下拉账单列表或在设置页点“立即同步”时都会同步。
