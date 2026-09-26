# just device::android-install [apk]
# 安装 Android Release APK.
android-install apk="build/app/outputs/flutter-apk/app-release.apk":
    adb install -r {{apk}}

# just device::android-run [flutter args...]
# 在 Android 设备上以 Release 模式启动应用.
android-run *args:
    flutter run --release --no-pub {{args}}

# just device::android-run-debug [flutter args...]
# 在 Android 设备上以 Debug 模式启动应用, 包名带 .debug 后缀且数据与正式包隔离.
android-run-debug *args:
    flutter run --debug --no-pub {{args}}

# just device::android-log [out]
# 抓取设备日志到文件, Ctrl+C 结束, 默认写入工作区的 .tmp/adb-logcat.log.
android-log out=".tmp/adb-logcat.log":
    adb logcat -c
    adb logcat -v time > {{out}}

# just device::android-log-dev [out]
# 抓取设备日志并只保留应用与音频框架相关的行, 用于排查播放音量问题.
android-log-dev out=".tmp/adb-logcat.log":
    adb logcat -c
    adb logcat -v time -s flutter:V AudioService:V AudioFlinger:V APM_AudioPolicyManager:V > {{out}}

# just device::ios-run [flutter args...]
# 在 iOS 设备上以 Release 模式启动应用.
ios-run *args:
    flutter run --release --no-pub {{args}}
