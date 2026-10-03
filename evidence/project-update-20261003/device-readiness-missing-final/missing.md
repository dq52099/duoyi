# Missing Device Readiness

| Check | Detail |
| --- | --- |
| android_runtime | Flutter does not detect an Android device or emulator. |
| ios_runtime | Flutter does not detect an iOS device. |
| adb_device | adb lists no connected Android device. |
| android_system_images | Android system images are missing under /home/ubuntu/android-sdk/system-images. |
| kvm | /dev/kvm is missing; accelerated Android emulator is unavailable. |
| android_emulator_launchability | Linux host architecture aarch64 is not x86_64; use an attached Android device or a matching host. |
| ios_host | iOS evidence requires macOS with xcrun and xcodebuild. |
