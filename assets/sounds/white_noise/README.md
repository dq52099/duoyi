# White Noise Tracks

`FocusSoundService` 会从本目录循环播放白噪音音轨。
`pubspec.yaml` 已声明 `assets/sounds/white_noise/`，所以文件放进来就会自动打包。

## 当前音轨

- `rain.mp3` - 绵绵细雨：粉噪雨幕 + 稀疏雨点击打。
- `forest.mp3` - 宁静森林：低频林风 + 高频空气感 + 合成鸟鸣点缀。
- `cafe.mp3` - 午后咖啡馆：低频空间底噪 + 杯碟轻响，不包含人声采样。
- `waves.mp3` - 海浪拍岸：低频浪涌 + 间歇白沫。
- `brown_noise.mp3` - 低频棕噪：稳定低频铺底。
- `night_rain.mp3` - 静夜细雨：更暗、更轻的雨声底。
- `fan.mp3` - 柔和风扇：宽频风扇底噪 + 低频转动基音。
- `pink_noise.mp3` - 平稳粉噪：稳定粉噪底。
- `deep_stream.mp3` - 低频溪流：流动底噪 + 细碎水波。

## 来源与许可

这些文件使用 ffmpeg 的 `anoisesrc` / `aevalsrc` / `sine` 滤波器在本仓库本地生成，没有引入第三方采样。
生成目标是“专注背景音”：环境类音轨加入不同频谱、动态和短促点缀，粉噪/棕噪保留为纯噪声选项。2026-05 已重新生成并做响度规范化，避免 9 个选项听起来都是同一类噪声。
