-dontwarn javax.annotation.Nullable
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.OpenSSLProvider

# 扫一扫: OpenCV 原生库按类名回调 Java 层, aar 没有自带 keep 规则.
-keep class org.opencv.** { *; }