# APK 构建、签名与验证

从项目根（终端 cwd）执行。只在需要构建 APK、创建签名辅助类或验证交付物时读取。

## 项目结构

    项目根/
      AndroidManifest.xml
      src/<包路径>/MainActivity.java
      res/values/styles.xml  # 可选；无资源时省略 res

Manifest 的 package、label 和 Activity 按项目修改：

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

## 签名辅助类

仅在 apksig 工具类不可用时，将以下文件写入项目 build/ 目录并编译一次。它只读取本地 debug keystore，不用于 release。

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

    TC=/root/toolchain
    javac -cp "$TC/apksig.jar" -d "$TC" build/SignApk.java

## 构建

    set -eu
    TC=/root/toolchain
    mkdir -p build/gen build/classes build/dex

    if [ -d res ]; then
      "$TC/aapt2" compile --dir res -o build/res.zip
      "$TC/aapt2" link -o build/unsigned.apk -I "$TC/android.jar" \
        --manifest AndroidManifest.xml --java build/gen build/res.zip
    else
      "$TC/aapt2" link -o build/unsigned.apk -I "$TC/android.jar" \
        --manifest AndroidManifest.xml --java build/gen
    fi

    javac -classpath "$TC/android.jar" -d build/classes \
      $(find src build/gen -name '*.java')

    java -cp "$TC/r8.jar" com.android.tools.r8.D8 --release --lib "$TC/android.jar" \
      --output build/dex $(find build/classes -name '*.class')

    cd build/dex
    zip -q -u ../unsigned.apk classes.dex
    cd ../..

    "$TC/zipalign" -f 4 build/unsigned.apk build/aligned.apk
    if java -cp "$TC/apksig.jar:$TC" com.android.apksig.tools.SignApk \
        "$TC/debug.keystore" build/aligned.apk app-debug.apk
    then
      :
    else
      java -cp "$TC/apksig.jar:$TC" SignApk \
        "$TC/debug.keystore" build/aligned.apk app-debug.apk
    fi

以真实输出为准调整类名和路径。失败时保留原始错误，修复后重跑受影响步骤，不跳过。

## 验证与交付

    ls -la app-debug.apk
    unzip -t app-debug.apk
    unzip -l app-debug.apk | grep -E 'classes.dex|AndroidManifest'

    if command -v apksigner >/dev/null 2>&1; then
      apksigner verify --verbose app-debug.apk
    else
      echo "signature verifier unavailable; report APK as not signature-verified"
    fi

构建成功时报告真实 APK 大小、完整路径和签名验证状态；没有签名验证工具时不要声称已证明可安装。最终 APK 放在项目根。
