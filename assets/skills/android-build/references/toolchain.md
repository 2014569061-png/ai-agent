# Android 工具链

仅在工具链缺失、版本不符或缓存校验失败时读取和执行本文件。工具链目录和 Android Linux rootfs 都可能跨会话持久化；已验证的文件直接复用。

## 安装与下载

以下操作会写入持久化环境并使用网络，只在任务明确需要且缺少工具时执行。不要自动修改 apk 源或使用任意代理镜像。

    set -eu
    TC=/root/toolchain
    mkdir -p "$TC"

    missing=0
    for cmd in curl java javac keytool unzip zip; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing: $cmd"
        missing=1
      fi
    done
    if [ "$missing" -ne 0 ]; then
      apk add --no-cache curl openjdk17 unzip zip
    fi

    cd "$TC"
    if [ ! -s sdk-tools.zip ]; then
      curl --fail --show-error --location --retry 3 --output sdk-tools.zip \
        https://github.com/lzhiyong/android-sdk-tools/releases/download/35.0.2/android-sdk-tools-static-aarch64.zip
    fi
    unzip -t sdk-tools.zip
    unzip -nq sdk-tools.zip

    AAPT2=$(find . -maxdepth 2 -type f -name aapt2 -print -quit)
    ZIPALIGN=$(find . -maxdepth 2 -type f -name zipalign -print -quit)
    test -n "$AAPT2" && test -n "$ZIPALIGN"
    chmod +x "$AAPT2" "$ZIPALIGN"
    "$AAPT2" version

    if [ ! -s r8.jar ]; then
      curl --fail --show-error --location --output r8.jar \
        https://dl.google.com/android/maven2/com/android/tools/r8/8.3.37/r8-8.3.37.jar
    fi
    if [ ! -s apksig.jar ]; then
      curl --fail --show-error --location --output apksig.jar \
        https://dl.google.com/android/maven2/com/android/tools/build/apksig/8.13.2/apksig-8.13.2.jar
    fi
    if [ ! -s android.jar ]; then
      # Set ANDROID_JAR_URL to a trusted immutable URL before running.
      : "$ANDROID_JAR_URL"
      curl --fail --show-error --location --output android.jar \
        "$ANDROID_JAR_URL"
    fi

在运行下载的二进制或 jar 前，用可信、固定版本的发布元数据核对 SHA-256。没有可信摘要时不要换用任意镜像，直接报告无法验证。

## Debug 密钥

下面的密钥只用于本地 debug APK，不得用于 release 或生产发布。已存在时复用，不覆盖：

    TC=/root/toolchain
    if [ ! -f "$TC/debug.keystore" ]; then
      keytool -genkeypair -keystore "$TC/debug.keystore" -alias androiddebugkey \
        -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
    fi

发布版本必须使用用户提供的 release keystore 和秘密输入，不把密码写入 Skill、源码或命令记录。
