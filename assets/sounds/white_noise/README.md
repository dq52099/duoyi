# White Noise Tracks

`FocusSoundService` 会从本目录循环播放专注背景音。
`pubspec.yaml` 已声明 `assets/sounds/white_noise/`，所以文件放进来就会自动打包。

## 当前音轨

- `rain.mp3` - 窗边雨声，来自真实雨声录音。
- `forest.mp3` - 雨林步行环境音，来自真实户外录音。
- `cafe.mp3` - 咖啡馆环境声，来自真实室内环境录音。
- `waves.mp3` - 海浪拍岸，来自真实海浪录音。
- `brown_noise.mp3` - 棕噪，保留为低频稳定噪声选项。
- `night_rain.mp3` - 夜间雨声与动物环境声，来自真实夜间录音。
- `fan.mp3` - 桌面风扇，来自真实风扇录音。
- `pink_noise.mp3` - 粉噪，保留为稳定噪声选项。
- `deep_stream.mp3` - 林地溪流，来自真实溪流录音。

## 来源与许可

2026-05-18 已移除本仓库脚本合成的环境音，改用 Wikimedia Commons 上可追溯授权的录音；处理方式为裁切或循环到约 60 秒、响度标准化、淡入淡出后转为 MP3。

| 文件 | 来源 | 作者 | 许可 |
| --- | --- | --- | --- |
| `rain.mp3` | https://commons.wikimedia.org/wiki/File:Rain_against_the_window.ogg | cori / PDSounds | Public domain |
| `forest.mp3` | https://commons.wikimedia.org/wiki/File:Walk_in_the_rainforest.ogg | ezwa / PDSounds | Public domain |
| `cafe.mp3` | https://commons.wikimedia.org/wiki/File:Cafe_ambiance.ogg | Marble Toast | CC0 |
| `waves.mp3` | https://commons.wikimedia.org/wiki/File:Oceanwavescrushing.ogg | Luftrum | CC BY 3.0 |
| `brown_noise.mp3` | https://commons.wikimedia.org/wiki/File:Brown_noise.ogg | Wikimedia Commons contributor | CC BY-SA 3.0 |
| `night_rain.mp3` | https://commons.wikimedia.org/wiki/File:2013-07-24_00-19-04hrs_Chiang_Mai_Chang_Khien_rain_animal_sounds_night_time.ogg | Takeaway | CC BY-SA 3.0 |
| `fan.mp3` | https://commons.wikimedia.org/wiki/File:Table_ventilator.ogg | stephan / PDSounds | Public domain |
| `pink_noise.mp3` | https://commons.wikimedia.org/wiki/File:Pink.Noise.ogg | Bautsch | Public domain |
| `deep_stream.mp3` | https://commons.wikimedia.org/wiki/File:Forest_lawn_creek.ogg | Dsw4 | Public domain |

## 处理命令

示例：

```bash
ffmpeg -i SOURCE -t 60 \
  -af "loudnorm=I=-24:TP=-2:LRA=11,afade=t=in:st=0:d=0.6,afade=t=out:st=59:d=1" \
  -ar 44100 -ac 2 -codec:a libmp3lame -b:a 112k OUTPUT.mp3
```
