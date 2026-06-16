# ───────────────────────────────────────────────────────────────────────────
# react-native-mail-engine — consumer R8/ProGuard rules.
#
# The JavaMail (com.sun.mail) Android port resolves providers, DataHandlers, and
# MIME command maps reflectively from META-INF resources. Without these keeps,
# R8 strips them in release builds and IMAP/SMTP fail at runtime with
# "no provider" / "no object DCH" errors. Nitro's own classes are annotated
# @Keep / @DoNotStrip, so they need no rules here.
# ───────────────────────────────────────────────────────────────────────────

-keep class com.sun.mail.** { *; }
-keep class javax.mail.** { *; }
-keep class javax.activation.** { *; }
-keep class com.sun.activation.** { *; }
-keep class myjava.awt.datatransfer.** { *; }

-keep class * extends javax.mail.Provider { *; }
-keep class * implements javax.activation.DataContentHandler { *; }

-keepattributes *Annotation*

-dontwarn com.sun.mail.**
-dontwarn javax.mail.**
-dontwarn javax.activation.**
-dontwarn java.awt.**
-dontwarn myjava.awt.**
