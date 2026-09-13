---
name: android-build
description: 在手机上直接把 Java/静态资源小项目构建成可安装 APK：JDK17 + 静态 aapt2/zipalign + r8(D8) + apksig 直构建配方（不走 Gradle），含贪吃蛇式最小示例与签名。
author: NEXUS
version: 1.0.0
tags: [android, apk, build]
---

# 手机直构建 APK（无 Gradle）

适用：单 Activity/View 的 Java 小项目（游戏、工具页）。不适用 Flutter/大型 Gradle 工程（内存与工具链体积不允许）。

前置：先完成 `mobile-dev-basics` 的环境体检；工具链装一次，之后所有项目复用。

## 1. 一次性安装工具链（约 500MB，需网络）

```sh
TC=/root/toolchain
apk add --no-cache curl openjdk17 unzip zip
mkdir -p $TC && cd $TC
# 静态构建工具（aapt2/zipalign，静态链接，Alpine PRoot 内直接运行）
curl -L --retry 3 -o sdk-tools.zip \
  https://github.com/lzhiyong/android-sdk-tools/releases/download/35.0.2/android-sdk-tools-static-aarch64.zip
unzip -oq sdk-tools.zip && chmod +x aapt2 zipalign 2>/dev/null; find . -maxdepth 2 -name 'aapt2' -o -maxdepth 2 -name 'zipalign'
```

- 解压后若二进制在子目录里，按 `find` 结果用真实路径；`./aapt2 version` 有输出即可用。
- GitHub 下载失败（大陆网络常见）：在 URL 前加可用加速镜像前缀，如 `https://gh-proxy.com/https://github.com/...`，或换其他镜像。

```sh
TC=/root/toolchain; cd $TC
# r8.jar 内含 d8；版本可先查 maven-metadata.xml 取最新稳定版
curl -L -o r8.jar https://dl.google.com/android/maven2/com/android/tools/r8/8.3.37/r8-8.3.37.jar
# apksig 签名库
curl -L -o apksig.jar https://dl.google.com/android/maven2/com/android/tools/build/apksig/8.13.2/apksig-8.13.2.jar
# android.jar（API 35 平台 stub，Apache-2.0）
curl -L -o android.jar https://raw.githubusercontent.com/Sable/android-platforms/master/android-35/android.jar
# debug 签名密钥（一次生成，长期复用）
keytool -genkeypair -keystore $TC/debug.keystore -alias androiddebugkey \
  -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"
```

每个下载都校验文件存在且大小合理（`ls -la`；apk/jar 应为数十 KB~数十 MB），失败换源重试并如实汇报。

## 2. 签名辅助类（写入项目 build/ 目录后编译一次，复用）

```java
// build/SignApk.java
import com.android.apksig.ApkSigner;
import java.io.*;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.util.List;

public class SignApk {
  public static void main(String[] args) throws Exception {
    KeyStore ks = KeyStore.getInstance("PKCS12");
    try (FileInputStream in = new FileInputStream(args[0])) {
      ks.load(in, "android".toCharArray());
    }
    PrivateKey key = (PrivateKey) ks.getKey("androiddebugkey", "android".toCharArray());
    Certificate[] chain = ks.getCertificateChain("androiddebugkey");
    ApkSigner.SignerConfig cfg = new ApkSigner.SignerConfig.Builder(
        "debug", key, List.of(chain)).build();
    new ApkSigner.Builder(List.of(cfg))
        .setInputApk(new File(args[1]))
        .setOutputApk(new File(args[2]))
        .setV1SigningEnabled(true)
        .setV2SigningEnabled(true)
        .build().sign();
  }
}
```

```sh
javac -cp $TC/apksig.jar -d $TC $TC/../workspace/build/SignApk.java   # 按实际路径调整
```

（若 API 签名与当前 apksig 版本不符，按 javac 报错微调即可。）

## 3. 项目结构（贪吃蛇式最小示例）

```
项目根/（终端 cwd）
  AndroidManifest.xml
  src/<包路径>/MainActivity.java   # 或自定义 View + Activity
  res/values/styles.xml            # 可选；无资源可省略整个 res
```

AndroidManifest.xml 最小模板（package 和 label 按项目改）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.snake">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="35"/>
  <application android:label="Snake" android:theme="@android:style/Theme.Material.Light.NoActionBar">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
```

## 4. 构建配方（在项目根执行）

```sh
TC=/root/toolchain
mkdir -p build/gen build/classes build/dex
# 1) 资源编译与链接（有 res 才需要 compile；无 res 时从 link 里去掉 res.zip）
$TC/aapt2 compile --dir res -o build/res.zip
$TC/aapt2 link -o build/unsigned.apk -I $TC/android.jar \
  --manifest AndroidManifest.xml --java build/gen build/res.zip
# 2) 编译 Java（含 aapt2 生成的 R.java）
javac -classpath $TC/android.jar -d build/classes \
  $(find src build/gen -name '*.java')
# 3) 转 dex
java -cp $TC/r8.jar com.android.tools.r8.D8 --release --lib $TC/android.jar \
  --output build/dex $(find build/classes -name '*.class')
# 4) dex 打进 APK（在 build/dex 里执行）
cd build/dex && zip -q -u ../unsigned.apk classes.dex && cd ../..
# 5) 对齐 + 签名
$TC/zipalign -f 4 build/unsigned.apk build/aligned.apk
java -cp $TC/apksig.jar:$TC com.android.apksig.tools.SignApk \
  $TC/debug.keystore build/aligned.apk app-debug.apk 2>/dev/null || \
java -cp $TC/apksig.jar:$TC SignApk $TC/debug.keystore build/aligned.apk app-debug.apk
```

以真实编译输出为准调整类名/路径；每一步失败先读错误再修，不要跳过。

## 5. 验证与交付

```sh
ls -la app-debug.apk   # 应为数百 KB 起
unzip -l app-debug.apk | grep -E 'classes.dex|AndroidManifest'
```

- 把最终 APK 放在项目根，明确告诉用户完整路径（工作区内），用户从文件管理器安装，或用应用内工作区文件分享发给系统安装器。
- 汇报必须基于真实命令输出：构建成功要给出 APK 大小与路径；失败要给出失败步骤与原始错误。
