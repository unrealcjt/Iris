# 保持 Flutter 引擎和插件的关键类
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# 🛠️ 关键：保持 Pigeon 生成的代码，防止 shared_preferences (dev.flutter.pigeon) 报错
-keep class dev.flutter.pigeon.** { *; }

# 保持你的应用包名下的类
-keep class com.example.iris.** { *; }

-dontwarn com.google.android.play.core.**
-ignorewarnings
