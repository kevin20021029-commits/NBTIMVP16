# deepdive/ — 16 人格深度解读(App 内 H5)

NeuralFin App 内展示的 16 投资人格深度解读页,与 NBTI 测试同套设计语言。

| 文件 | 说明 |
|---|---|
| `index.html` / `index-en.html` / `index-hk.html` | 三语单文件页面(zh 简中 / en 英文 / hk 粤语) |
| `deepdive-zh.json` / `deepdive-en.json` / `deepdive-hk.json` | 深度解读内容资产(改文案只动这里) |
| `*.webp` | 16 人格头像 |

访问路径:`/deepdive/`(部署后如 nbtimvp-16.vercel.app/deepdive/)

内容维护:修改 `deepdive-<lang>.json` 后需重新构建生成 index(构建脚本在本地 `D:\1\DL德林\NBTI\DEEPDIVE\`,`node build.js`)。
