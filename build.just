# just build::android [args...]
# 构建 Android Release APK.
android *args:
    flutter build apk --release --no-pub {{args}}

# just build::android-release [args...]
# 构建 Android Release APK.
android-release *args:
    flutter build apk --release --no-pub {{args}}

# just build::android-debug [args...]
# 构建 Android Debug APK.
android-debug *args:
    flutter build apk --debug --no-pub {{args}}

# just build::android-aab [args...]
# 构建用于应用商店发布的 Android App Bundle.
android-aab *args:
    flutter build appbundle --release --no-pub {{args}}

# just build::ios [args...]
# 构建已签名的 iOS Release app.
ios *args:
    flutter build ios --release --no-pub {{args}}

# just build::ios-unsigned [args...]
# 构建未签名的 iOS Release app.
ios-unsigned *args:
    flutter build ios --release --no-codesign --no-pub {{args}}

# just build::ipa [args...]
# 构建用于分发的已签名 iOS IPA.
ipa *args:
    flutter build ipa --release --no-pub {{args}}

# just build::macos [args...]
# 构建 macOS Release app.
macos *args:
    flutter build macos --release --no-pub {{args}}

# just build::web [args...]
# 构建 Web Release 产物.
web *args:
    flutter build web --release --no-pub {{args}}
