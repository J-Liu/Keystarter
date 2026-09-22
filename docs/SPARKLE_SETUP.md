# Sparkle 自动更新设置指南

## 1. 安装 Sparkle 工具

从 https://github.com/sparkle-project/Sparkle/releases 下载最新版本，解压后找到 `bin/generate_keys`。

## 2. 生成 EdDSA 密钥对

```bash
# 生成密钥对（公钥会显示，私钥保存在钥匙串）
/Applications/Sparkle-2.x/bin/generate_keys

# 输出示例：
# Public EdDSA key: ABC123...
```

## 3. 更新配置

### 3.1 更新 Info.plist

将 `Resources/Info.plist` 中的 `SUPublicEDKey` 替换为你生成的公钥：
```xml
<key>SUPublicEDKey</key>
<string>你的公钥</string>
```

### 3.2 设置 appcast.xml URL

选择托管方式：

**方案 A：GitHub Releases**
- URL: `https://github.com/你的用户名/Keystarter/releases/download/v0.1.0/appcast.xml`
- 每次发布新版本时上传 appcast.xml

**方案 B：GitHub Pages**
- 将 appcast.xml 放在 `docs/` 目录
- 开启 GitHub Pages (Settings → Pages → Source: main branch, /docs)
- URL: `https://你的用户名.github.io/keystarter/appcast.xml`

更新 `Info.plist` 中的 `SUFeedURL`：
```xml
<key>SUFeedURL</key>
<string>你的appcast.xml地址</string>
```

## 4. 发布新版本

```bash
# 1. 更新版本号
# 编辑 Resources/Info.plist 中的 CFBundleVersion 和 CFBundleShortVersionString

# 2. 构建
./scripts/build-app.sh

# 3. 打包
cd build && zip -r Keystarter-X.X.X.zip Keystarter.app

# 4. 签名
/Applications/Sparkle-2.x/bin/sign_update Keystarter-X.X.X.zip

# 输出示例：
# EdDSA signature: XYZ789...
# Length: 123456

# 5. 更新 docs/appcast.xml
# - 更新 version
# - 更新 enclosure url
# - 更新 sparkle:edSignature
# - 更新 length

# 6. 创建 GitHub Release
# - 上传 Keystarter-X.X.X.zip
# - 上传 appcast.xml (如果用 Releases 托管)
```

## 5. 测试更新

应用启动后会自动检查更新，也可以在菜单中手动检查。

## 注意事项

- 私钥保存在 macOS 钥匙串中，不要丢失
- 每次发布新版本都要重新签名
- appcast.xml 必须通过 HTTPS 访问