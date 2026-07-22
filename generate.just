# 生成应用图标资源.
icons:
    dart run flutter_launcher_icons

# 生成启动画面资源.
splash:
    dart run flutter_native_splash:create

# just generate::code [args...]
# 运行一次 build_runner 代码生成.
code *args:
    dart run build_runner build --delete-conflicting-outputs {{args}}

# just generate::watch [args...]
# 持续监听并运行 build_runner 代码生成.
watch *args:
    dart run build_runner watch --delete-conflicting-outputs {{args}}
