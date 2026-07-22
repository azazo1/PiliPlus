# just device::android-install [apk]
# 安装 Android Release APK.
android-install apk="build/app/outputs/flutter-apk/app-release.apk":
    adb install -r {{apk}}

# just device::android-run [flutter args...]
# 在 Android 设备上以 Release 模式启动应用.
android-run *args:
    flutter run --release --no-pub {{args}}

# just device::ios-run [flutter args...]
# 在 iOS 设备上以 Release 模式启动应用.
ios-run *args:
    flutter run --release --no-pub {{args}}
