# 字体

两个子集化的拉丁字体（woff2），只包含 A–Z a–z 0–9 和少量标点，因此文件很小（18 KB / 32 KB）。
中文用系统字体，不随仓库分发。

| 文件 | 字体 | 授权 | 上游 |
|---|---|---|---|
| `archivo-black-latin.woff2` | Archivo Black | SIL OFL 1.1 | https://fonts.google.com/specimen/Archivo+Black |
| `outfit-latin.woff2` | Outfit | SIL OFL 1.1 | https://fonts.google.com/specimen/Outfit |

用途：Archivo Black 给标题和数字（`GAME 02 / FORTUNE WHEEL` 这类 kicker 和金币数字），
Outfit 给正文与按钮。两者都在 `index.html` / `wheel.html` / `slot.html` 的 `@font-face` 里声明。
