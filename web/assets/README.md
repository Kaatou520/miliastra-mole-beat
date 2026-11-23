# web/assets —— 占位美术与素材映射

![占位美术预览](placeholder-preview.png)

## 现在仓库里是什么

`*.png` 全部是 **256×256 的自绘占位图**（Pillow 画的扁平小图，配色取自游戏自己的调色板），
目的是让 Demo 克隆下来就能直接跑、直接上 GitHub Pages。

它们和《原神》/ 千星元件库里的任何素材都没有关系，可以随 MIT 一起用。

## 开发时用的是官方贴图

网页原型和千星版本用的都是**千星奇域元件库**里的图（版权归米哈游，所以没进仓库）。
`index.html` 里的 `ASSETS` 表就是这张对照关系，`imageId` 是千星里的元件编号：

| 文件（占位图同名） | 用途 | 千星 imageId | 元件名 |
|---|---|---|---|
| `slime_water.png` | 普通史莱姆 | 30002006 | 水史莱姆 |
| `slime_ice.png` | 稀有史莱姆 | 30002001 | 冰史莱姆 |
| `slime_geo.png` | 高价值史莱姆 | 30002008 | 岩史莱姆 |
| `slime_fire.png` | BONUS 备选 | 30002007 | 火史莱姆 |
| `slime_thunder.png` | BONUS 备选 | 30002004 | 雷史莱姆 |
| `bomb.png` | 炸弹 / 爆桶 | 20001599 | 火史莱姆爆桶 |
| `coin.png` | 金币 | 10005009 | 冒险币 |
| `chest_wood.png` | 木质宝箱 | 10005008 | 普通宝箱 |
| `chest_gold.png` | 珍贵宝箱 | 10005006 | 珍贵宝箱 |
| `stall.png` | 商店图标 | 20001125 | 木质摊位铺 |
| `pinwheel.png` | 转盘图标 / 轮心 | 10005010 | 木质风车 |

## 想换回官方贴图

1. 在千星编辑器里用「图片控件 → 图片设置 → 图片源：元件」按上面的 `imageId` 找到对应图；
2. 导出成 PNG，**保持文件名不变**，覆盖 `web/assets/` 下的同名占位图；
3. 这样 `git status` 会显示这些图被修改——**别提交**，或者提交前执行：

```bash
git update-index --skip-worktree web/assets/*.png
```

（`.gitignore` 里有同样的提示。用完之后 `--no-skip-worktree` 恢复跟踪。）

替代方案是把你的版本放到别的目录、自己改 `index.html` 顶部的 `ASSETS` 表，这样仓库永远不会脏。
