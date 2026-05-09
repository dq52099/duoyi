# White Noise Tracks

`FocusSoundService`（Task 15）会从本目录加载循环播放的白噪音音轨。
`pubspec.yaml` 已在 `flutter.assets` 中声明 `assets/sounds/white_noise/`，
所以只要把文件放进来即可自动打包进 APK。

## 当前需要的音轨

每条都建议 ≥ 30 秒、mp3 格式、128 kbps 已足够：

- `rain.mp3` — 雨声
- `forest.mp3` — 森林
- `cafe.mp3` — 咖啡馆人声白噪音
- `waves.mp3` — 海浪

## 推荐素材来源

- [Freesound.org](https://freesound.org)（CC0 / CC BY 协议，注意署名）
- [Pixabay Music](https://pixabay.com/music)（免商用）
- [Kenney Game Assets](https://kenney.nl) 的 Audio Library

## 文件缺失的表现

- `FocusSoundService.play('rain')` 调用时 `AudioPlayer` 会抛出
  `MissingPluginException` 或 `PlatformException(code=AndroidAudioError)`。
  Task 16 接入番茄钟后建议在捕获异常后退回 `currentSound = 'none'`。
- 真机 / Emulator 调试时可先放一个任意 mp3 重命名为 `rain.mp3` 等来验证
  链路；产品侧再补充正式素材即可覆盖文件。

## 添加新音轨

1. 把 mp3 放进本目录；
2. 在 `lib/services/focus_sound_service.dart` 的 `_assetMap` 追加一项
   `'your_id': 'sounds/white_noise/your_id.mp3'`；
3. 在 `lib/screens/goal_edit_screen.dart` 与 `pomodoro_screen.dart` 的
   白噪音选择器（Wrap<ChoiceChip>）追加对应中文标签；
4. `pubspec.yaml` 无需改动（整个目录已纳入 assets）。
