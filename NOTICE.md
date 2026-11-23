# 素材与商标说明

本仓库的 **代码**（HTML / CSS / JavaScript / Lua / 文档 / 自绘占位图）以 [MIT](LICENSE) 授权。

下面这些内容**不属于**本仓库，也不在 MIT 授权范围内：

## 1. 官方游戏素材

`web/assets/` 里的 11 张贴图是**自绘的占位图**（作者手写 Python/Pillow 生成），
用来让 Demo 在没有官方资源时也能跑通。它们与《原神》及千星元件库里的任何素材都无关。

游戏原型开发时使用的史莱姆 / 金币 / 宝箱 / 摊位贴图来自**千星奇域元件库**
（`imageId` 见 [`web/assets/README.md`](web/assets/README.md)），版权归米哈游所有，
因此**没有随仓库分发**。如果你想在本地看到开发时的原样，请自己从编辑器导出后替换占位图。

同理，`docs/` 里提到的音效 ID 只是千星官方音效库里的编号，仓库里没有任何音频文件。

## 2. 截图

`screenshots/` 与 `press/` 里的图片是本项目自己的运行截图 / 宣传图，用于说明作品；
其中出现的游戏内贴图、角色与美术资源版权仍归米哈游所有。请勿把这些截图当作素材再分发。

## 3. 字体

`web/assets/fonts/` 里是两个开源字体子集（仅拉丁字母）：

| 文件 | 字体 | 授权 |
|---|---|---|
| `archivo-black-latin.woff2` | Archivo Black（Omnibus-Type） | SIL Open Font License 1.1 |
| `outfit-latin.woff2` | Outfit（Smartsheet / Rodrigo Fuenzalida） | SIL Open Font License 1.1 |

字体本身的授权见各自上游页面（Google Fonts 上的 Archivo Black / Outfit），
本仓库只做子集化与转 woff2，未修改字形。

## 4. 商标

「原神」「千星奇域」「Genshin Impact」等名称与标识是米哈游的商标。
本项目是玩家的个人作品，与米哈游官方无关，也未获得官方认可或背书。
