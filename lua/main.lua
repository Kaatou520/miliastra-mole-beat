-- 地鼠节拍 · 主场景（千星客户端 Lua）
-- 挂载：容器节点「容器节点」(n1)。位置由 Authoring 摆好；
-- 打击特效在运行时实例化客户端控件模板（fx块 / fx环 / fx星 / …），逐帧摆位、缩放、淡出后销毁。

-- 父容器中心固定为设计中心的 (640, 360)
local DESIGN_W, DESIGN_H = 1280, 720   -- 设计基准（手机 16:9）
local baseScale = 1                    -- 画布 / 设计基准 的等比放大（PC 1600×900 → 1.25）

-- 出洞动画（史莱姆从洞里冒出来，带回弹）
local RISE_DUR = 0.26                  -- 秒（出洞动画时长，带回弹）
local RISE_SINK = 30                   -- 起始下沉距离（设计像素）
local RISE_SCALE0 = 0.42               -- 起始缩放

-- 客户端控件模板索引（build-play.cjs 分配）
local TPL = {
  block   = 1073742200,
  dot     = 1073742210,
  ring    = 1073742220,
  star    = 1073742230,
  burst   = 1073742240,
  word    = 1073742250,
  num     = 1073742260,
  slime   = 1073742270,
  rainbow = 1073742280,
}
local TPL_SET = {}
for _, idx in pairs(TPL) do TPL_SET[idx] = true end

-- 成就信号：每个信号在「服务器信号管理器」里定义 1 个整数参数（参数名随意），
-- 这里每次发送都带一个整数 1；服务端把它接到「成就进度计数增加值」即可。
local function sendSignal(name)
  pcall(function()
    local sig = game.ServerSignal(name)
    sig:AddInt(1)
    sig:SendSignal()
  end)
end

local coinPending = 0                   -- 累计金币，满 100 发一次成就信号

-- 9 个洞的屏幕坐标（上缘为 0、向下为正，与网页 CELL_POS 一致）
local CELL = {
  { 374, 386 }, { 640, 386 }, { 906, 386 },
  { 374, 501 }, { 640, 501 }, { 906, 501 },
  { 374, 616 }, { 640, 616 }, { 906, 616 },
}
local CELL_Y_BONUS = 61               -- 涂鸦字相对洞心的高度

local INK = { 7, 10, 125 }            -- #070a7d
local MD = {                          -- 网页 MD_COLORS
  { 255, 46, 136 }, { 255, 210, 63 }, { 46, 230, 246 }, { 139, 92, 246 },
  { 255, 122, 61 }, { 255, 255, 255 }, { 74, 222, 128 }, { 255, 90, 160 },
}
local WORDCOL  = { main = { 255, 253, 247 }, cyan = { 62, 210, 232 }, pink = { 255, 95, 141 } }
local C_NUM    = { 255, 243, 107 }
local NUM_COLOR = {
  water = { 255, 250, 240 },
  ice   = { 230, 246, 255 },
  geo   = { 255, 224, 122 },
  bomb  = { 255, 180, 164 },
}

local WORDS = {
  water = { '咚', '砰', '嘭', '嘿', '啪' },
  ice   = { '咔', '唰', '叮', '冰' },
  geo   = { '轰', '金', '崩', '暴' },
  bomb  = { '砰！', '炸', 'BOOM' },
}

-- 经济
local S = { coins = 1, combo = 0, hits = 0, stage = 0, wlv = 1 }   -- 新手引导：开局 1 金币

local sfx, refresh, refreshWeapon

-- 武器成长（网页 WEAPON）：收益 ×1/2/4/8/16，费用 0/120/480/1920/7680
local WEAPON = { { 1, 0 }, { 2, 120 }, { 4, 480 }, { 8, 1920 }, { 16, 7680 } }
local page = nil          -- nil / 'shop' / 'wheel' / 'slot'
local shopPips = {}
local shopBuyBg, shopBuyShade, shopBuyText
local SH = {}                 -- 商店页控件缓存（页面内控件不能用 root:GetChild）
local CHEST = { 25, 60, 120, 250, 500 }
local CHEST_NAME = { '木质宝箱', '精致宝箱', '珍贵宝箱', '华丽宝箱', '特殊宝箱' }

local TYPES = {
  water = { icon = 30002006, lo = 1, hi = 3, dur = 0.95, w = 55 },
  ice   = { icon = 30002001, lo = 4, hi = 6, dur = 0.72, w = 20 },
  geo   = { icon = 30002008, lo = 8, hi = 12, dur = 0.58, w = 15 },
  bomb  = { icon = 20001599, lo = 0, hi = 0, dur = 0.70, w = 10 },
}
local ORDER = { 'water', 'ice', 'geo', 'bomb' }
local BONUS_ARTS = { 30002006, 30002001, 30002008 }   -- 只用确认过亮度的三种史莱姆

local root
local holes = {}
local clock = 0
local nextSpawn = 0.7
local frame = 0
local spawned = 0
local punchAt = 0
local BONUS = { active = false, hits = 0, need = 0, nextAt = 9, endAt = 0, boomAt = 0, lastHitAt = 0 }
local bonusRing = nil
local boomA = -1
local lastTimer = ''
-- 镜头：网页 applyCam() 把整个 1280×720 舞台按 (1 + camZoom) 缩放，原点在画布中心。
-- 千星没有相机，缩放挂载控件 n1（全屏 stretch 容器）就等价于整屏推镜。
local camZoom = 0
local camApplied = 1
local shakeUntil = 0
local shakeAmp = 0

-- BONUS 期间网页会淡出 HUD（.screen.bonus 隐藏 hud-left/topbar/bubble/hud-right）
local HUD_NAMES = {
  '商店-阴影', '商店-底', '商店-图标', '商店-字',
  '转盘-阴影', '转盘-底', '转盘-图标', '转盘-字',
  '老虎机-阴影', '老虎机-底', '老虎机-图标', '老虎机-字',
  '金币-阴影', '金币-底', '金币-图标', '金币-数',
  '武器-阴影', '武器-底', '武器-数',
  '进度-底', '进度-槽', '进度-条', '进度-名', '进度-数',
  '连击', '连击-字',
  '音效', '音效-字', '音效-判定', '重开', '重开-字',
}
local hudCtl = {}

-- 打击音效：网页是 WebAudio 现场合成，千星只能播已配置音效；
-- 这里按网页的「拳击 + 元素受击」两层结构挑官方素材，改 ID 即可换音色。
local SFX = {
  punch = 40106,   -- 战斗_受击_命中_躯体打击_拳击_01
  water = 40127,   -- 战斗_受击_命中_魔法元素受击_水_02
  ice   = 40170,   -- 战斗_受击_命中_魔法元素受击_冰_07
  geo   = 40118,   -- 战斗_受击_命中_魔法元素受击_岩_02
  bomb  = 40221,   -- 战斗_受击_命中_爆炸_岩_01
  boom  = 40225,   -- 战斗_受击_命中_爆炸_岩_05
  whiff = 50947,   -- 切换_轻_折叠_02（落空，短促）
  combo = 50940,   -- 切换_轻_提升_01（每 5 连）
  bonus = 50923,   -- 提示性UI_重_页面开启_01
  bonusEnd = 50935, -- 提示性UI_中_恢复
  ui    = 50865,   -- 按钮点击_重_卡通_01
  coin2 = 50880,   -- 按钮点击_重_通用_09（金币叮）
  win   = 50928,   -- 提示性UI_重_提示_03（中奖提示音，音高上扬，和打击音区分开）
  chest = 50220,   -- 场景物件_机关交互_宝箱_07（开箱）
  applause = 30132, -- 基础移动_紧张氛围_鼓掌_节奏干声_01（JACKPOT 用）
  lose  = 50931,   -- 提示性UI_轻_失败
}
local BONUS_PATS = { 40111, 40112, 40113, 40114 }   -- 巴掌 01~04

local muted = false
local soundLabel

-- 连击显示（网页 .combo-line）
local comboBox, comboMain, comboBlue, comboOrange
local comboPopT = 99
local comboBreath = 1.07
local COMBO_POP = 0.28

-- 提示气泡（网页 .bubble，say() 会自动收起）
local tipText, tipBg, tipShadow
local tipUntil = 0


-- ========== 小工具 ==========
local function ui(name)
  if not root then return nil end
  return root:GetChild(name)
end

local function setText(name, value)
  local c = ui(name)
  if c then c.text = tostring(value) end
end

local function setTextIn(bag, key, value)
  local c = bag[key]
  if not c then return end
  local v = tostring(value)
  if c.text ~= v then c.text = v end
end

local function pageOf(name)
  local pg = root and root:GetChild(name)
  return pg
end

local function show(name, on)
  local c = ui(name)
  if c then pcall(function() c:SetVisible(on) end) end
end

local function hudSet(on)
  for i = 1, #HUD_NAMES do
    local c = hudCtl[i]
    if c then pcall(function() c:SetVisible(on) end) end
  end
end

local function cacheHud()
  for i = 1, #HUD_NAMES do hudCtl[i] = ui(HUD_NAMES[i]) end
end

local function weaponMult()
  return WEAPON[S.wlv][1]
end

local function comboMult(c)
  if c >= 30 then return 1.20 end
  if c >= 20 then return 1.15 end
  if c >= 10 then return 1.10 end
  if c >= 5 then return 1.05 end
  return 1.00
end

refreshWeapon = function()
  setText('武器-数', '武器 Lv.' .. S.wlv .. '  ×' .. WEAPON[S.wlv][1])
end

local function refreshShop()
  local w = WEAPON[S.wlv]
  local nxt = WEAPON[S.wlv + 1]
  setTextIn(SH, '商店-Lv', 'Lv.' .. S.wlv)
  setTextIn(SH, '商店-收益', '当前收益 ×' .. w[1] .. (nxt and ('　下一级 ×' .. nxt[1]) or '　已达上限'))
  setTextIn(SH, '商店-币', '金币 ' .. S.coins)
  setTextIn(SH, '商店-下一级', nxt and ('下一级 ×' .. nxt[1]) or '已满级')
  for i = 1, #shopPips do
    local on = i <= S.wlv
    pcall(function()
      shopPips[i].imageColor = on and Color.FromRGBA(255, 241, 0, 255) or Color.FromRGBA(7, 10, 125, 34)
    end)
  end
  local bg, fg
  if not nxt then
    setTextIn(SH, '商店-买字', '武器已满级')
    bg = Color.FromRGBA(7, 10, 125, 40)
    fg = Color.FromRGBA(7, 10, 125, 158)
  else
    local afford = S.coins >= nxt[2]
    setTextIn(SH, '商店-买字', '升 级　' .. nxt[2])
    bg = afford and Color.FromRGBA(255, 241, 0, 255) or Color.FromRGBA(231, 248, 255, 255)
    fg = afford and Color.FromRGBA(7, 10, 125, 255) or Color.FromRGBA(7, 10, 125, 132)
  end
  if shopBuyBg then pcall(function() shopBuyBg.imageColor = bg end) end
  if shopBuyText then pcall(function() shopBuyText.fontColor = fg end) end
end

local function openShop()
  show('转盘页', false)
  show('老虎机页', false)
  page = 'shop'
  if SH.page then pcall(function() SH.page:SetAsLastSibling() end) end
  refreshShop()
  show('商店页', true)
  sfx(SFX.ui)
end

local function closeShop()
  page = nil
  show('商店页', false)
end

local function buyWeapon()
  if page ~= 'shop' then return end
  local nxt = WEAPON[S.wlv + 1]
  if not nxt or S.coins < nxt[2] then return end
  S.coins = S.coins - nxt[2]
  S.wlv = S.wlv + 1
  sfx(SFX.ui)
  refresh()
  refreshWeapon()
  refreshShop()
end

sfx = function(id)
  if muted or not id then return end
  pcall(function() game.PlayAudio2D(id) end)
end

local function comboBump()
  comboPopT = 0
  comboBreath = math.min(1.5, 1.18 + S.combo * 0.022)
end

local function setComboTexts()
  local v = tostring(S.combo)
  if comboMain then comboMain.text = v end
  if comboBlue then comboBlue.text = v end
  if comboOrange then comboOrange.text = v end
end

local function tip(str, ms)
  if not tipText then return end
  tipText.text = str
  tipText:SetVisible(true)
  if tipBg then tipBg:SetVisible(true) end
  if tipShadow then tipShadow:SetVisible(true) end
  tipUntil = clock + (ms or 2000) / 1000
end

local function hideTip()
  if tipText then tipText:SetVisible(false) end
  if tipBg then tipBg:SetVisible(false) end
  if tipShadow then tipShadow:SetVisible(false) end
  tipUntil = 0
end

-- 连击数字逐帧：内层呼吸（2.6s 一循环）+ 命中弹跳（0.28s）
local function stepCombo(dt)
  if not comboBox then return end
  local breath = 1 + (comboBreath - 1) * (0.5 - 0.5 * math.cos(clock * 2.4166))
  local pop = 1
  local rot = 0
  if comboPopT < COMBO_POP then
    local u = comboPopT / COMBO_POP
    if u < 0.38 then
      local e = u / 0.38
      pop = 1 + 0.6 * e
      rot = -6 * e
    elseif u < 0.72 then
      local e = (u - 0.38) / 0.34
      pop = 1.6 - 0.66 * e
      rot = -6 + 8 * e
    else
      local e = (u - 0.72) / 0.28
      pop = 0.94 + 0.06 * e
      rot = 2 - 2 * e
    end
    comboPopT = comboPopT + dt
  end
  local k = breath * pop
  comboBox.localScaleX = k
  comboBox.localScaleY = k
  comboBox.localRotationZ = rot * 0.6
  if comboBreath > 1.0701 then
    comboBreath = 1.07 + (comboBreath - 1.07) * math.exp(-2.15 * dt)
    if comboBreath < 1.0701 then comboBreath = 1.07 end
  end
end

-- 屏幕坐标（上缘 0、向下为正）→ 父容器中心偏移
local function place(c, sx, sy)
  c.anchoredPositionX = sx - 640
  c.anchoredPositionY = 360 - sy
end

local function setIcon(name, id)
  local c = ui(name)
  if c then pcall(function() c:SetImage(Enum.ImageSource.Prefab, id) end) end
end

local function setScale(name, k)
  local c = ui(name)
  if c then pcall(function() c.localScaleX = k; c.localScaleY = k end) end
end

local function rnd(a, b)
  return a + (b - a) * math.random()
end

-- 推镜：只在值变化时写，避免每帧无意义刷新
-- 最终缩放 = 设备基础缩放 × 推镜倍率；手机 baseScale=1 时行为与之前完全一致
local function applyCam()
  local k = (1 + camZoom) * baseScale
  if math.abs(k - camApplied) > 1e-4 then
    camApplied = k
    pcall(function()
      root.localScaleX = k
      root.localScaleY = k
    end)
  end
end

local function kick(amp, dur)
  shakeAmp = amp
  shakeUntil = clock + dur
end

-- 连打时保持推镜；停手 0.36 秒后按 e^(-2.76·dt)（网页 0.955/帧 @60fps）回落
local function stepCam(dt)
  if BONUS.active and (clock - BONUS.lastHitAt) <= 0.36 then
    -- hold
  else
    camZoom = camZoom * math.exp(-2.76 * dt)
    if camZoom < 0.002 then camZoom = 0 end
  end
  applyCam()
  if clock < shakeUntil then
    pcall(function()
      root.anchoredPositionX = rnd(-shakeAmp, shakeAmp)
      root.anchoredPositionY = rnd(-shakeAmp, shakeAmp)
    end)
  elseif root.anchoredPositionX ~= 0 or root.anchoredPositionY ~= 0 then
    pcall(function()
      root.anchoredPositionX = 0
      root.anchoredPositionY = 0
    end)
  end
end


local function aByte(a)
  if a <= 0 then return 0 end
  if a >= 1 then return 255 end
  local q = math.floor(a * 6 + 0.5) / 6
  return math.floor(q * 255 + 0.5)
end

local function outCubic(u)
  local v = 1 - u
  return 1 - v * v * v
end

local function outBack(u)
  local c1 = 1.70158
  local c3 = c1 + 1
  local v = u - 1
  return 1 + c3 * v * v * v + c1 * v * v
end

local function pickMD()
  return MD[math.random(#MD)]
end

local function tint(c, rgb, a)
  if not c then return end
  c.imageColor = Color.FromRGBA(rgb[1], rgb[2], rgb[3], a)
end

local function fontTint(c, rgb, a)
  if not c then return end
  c.fontColor = Color.FromRGBA(rgb[1], rgb[2], rgb[3], a)
end


-- ========== 粒子系统 ==========
local parts = {}
local MAX_PARTS = 150

local function killPart(p)
  local c = p.c
  p.c = nil
  if not c then return end
  -- 真机上 game.DestroyClientUIControl 对运行时实例不保证立即移除（BONUS 彩虹环会残留堆积），
  -- 所以先彻底隐藏/停用，再销毁；两道都不依赖对方成功。
  pcall(function()
    c:SetVisible(false)
    c:SetActive(false)
  end)
  pcall(function()
    if c.alive then game.DestroyClientUIControl(c) end
  end)
end

local function clearParts()
  for i = #parts, 1, -1 do
    killPart(parts[i])
    parts[i] = nil
  end
end

-- ===== 模板索引自检 =====
-- 真机导入后可能重新分配「客户端控件模板索引」，此时 TPL 会指向别的模板
-- （症状：命中特效变成彩虹环）。这里用子控件名字/图元特征反查真实索引。
local TPL_PROBE_RANGES = {
  { 1073742175, 1073742230 },
  { 1073742520, 1073742580 },
}

local function tplKindOf(children)
  local names, count, firstImage = {}, 0, nil
  for i = 1, #children do
    local c = children[i]
    count = count + 1
    names[c.name or ''] = true
    if i == 1 and c.imageId then firstImage = c.imageId end
  end
  if names['光晕外'] or names['段1'] then return 'rainbow' end
  if names['影青'] or names['影粉'] then return 'word' end
  if names['环'] then return 'ring' end
  if names['星'] then return 'star' end
  if names['爆'] then return 'burst' end
  if count == 1 and names['数'] then return 'num' end
  if count == 1 and names['图'] then return 'slime' end
  if names['面'] and names['描边'] then
    if firstImage == 100002 then return 'dot' end
    return 'block'
  end
  return nil
end

local function probeTemplateKind(idx)
  if not root then return nil end
  local ok, c = pcall(function() return game.InstantiateClientUIControl(idx, root) end)
  if not ok or not c then return nil end
  local kind = nil
  pcall(function()
    c:SetVisible(false)
    kind = tplKindOf(c:GetChildren() or {})
  end)
  pcall(function() c:SetVisible(false); c:SetActive(false) end)
  pcall(function() if c.alive then game.DestroyClientUIControl(c) end end)
  return kind
end

-- 返回认出的数量与仍缺的种类；同时改写 TPL / TPL_SET
local function resolveTemplates()
  local need, found = {}, 0
  for key in pairs(TPL) do need[key] = true end
  for key, idx in pairs(TPL) do                 -- 先验：索引没被重排就不用扫
    if probeTemplateKind(idx) == key then
      need[key] = nil
      found = found + 1
    end
  end
  if next(need) ~= nil then
    for _, range in ipairs(TPL_PROBE_RANGES) do
      if next(need) == nil then break end
      for idx = range[1], range[2] do
        local kind = probeTemplateKind(idx)
        if kind and need[kind] then
          TPL[kind] = idx
          need[kind] = nil
          found = found + 1
        end
      end
    end
  end
  TPL_SET = {}
  for _, idx in pairs(TPL) do TPL_SET[idx] = true end
  return found, need
end

-- ===== 素材兜底：真机取不到的「元件」图片在运行时换成图元 =====
-- 这批 id 在真机显示为空白（编辑器预览也是问号），其它图元类素材正常。
local RESKIN = {
  [20001125] = { 100001, { 139, 90, 43, 255 } },    -- 摊位/店标 → 棕色矩形
  [10005010] = { 100006, { 74, 222, 128, 255 } },   -- 风车 → 绿色环
  [10005009] = { 100002, { 255, 210, 63, 255 } },   -- 金币 → 金色圆
  [10005008] = { 100001, { 176, 106, 44, 255 } },   -- 宝箱 → 棕色矩形
}

local function reskinAll()
  if not root then return 0 end
  local n = 0
  local function rec(c)
    if not c then return end
    local id = nil
    pcall(function() id = c.imageId end)
    local spec = id and RESKIN[id]
    if spec then
      pcall(function()
        c:SetImage(Enum.ImageSource.StaticReference, spec[1])
        c.imageColor = Color.FromRGBA(spec[2][1], spec[2][2], spec[2][3], spec[2][4])
      end)
      n = n + 1
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if kids then
      for i = 1, #kids do rec(kids[i]) end
    end
  end
  pcall(function() rec(root) end)
  return n
end

-- ===== 图标重绘：真机没有这些美术素材，用图元色块画出可辨认的简单图标 =====
-- 100001 矩形 / 100002 圆 / 100003 三角 / 100004 四角星 / 100005 五角星 / 100006 环
local PAINT = {
  ['商店-图标']   = { 100003, { 255, 112, 49, 255 }, 34, 30 },    -- 橙红三角 = 摊棚
  ['转盘-图标']   = { 100006, { 46, 230, 166, 255 }, 34, 34 },    -- 绿色环 = 轮盘
  ['老虎机-图标'] = { 100001, { 7, 10, 125, 255 }, 32, 26 },      -- 靛蓝矩形 = 机身
  ['金币-图标']   = { 100002, { 255, 210, 63, 255 }, 30, 30 },    -- 金色圆 = 金币
  ['武器-底']     = { 100001, { 255, 226, 150, 255 }, 140, 34 },  -- 奶油金条 = 武器槽
  ['转盘-中心图'] = { 100006, { 46, 230, 166, 255 }, 96, 96 },    -- 轮盘中心环
  ['商店-店标']   = { 100003, { 255, 112, 49, 255 }, 40, 34 },
}

-- 这几个卡片标签高度 26 < 字号 15×1.75，真机会裁掉整行字 → 抬高到 32
local LABEL_FIX = { ['商店-字'] = 1, ['转盘-字'] = 1, ['老虎机-字'] = 1 }

local function applyPaint()
  if not root then return 0, 0 end
  local painted, fixed = 0, 0
  local function rec(c)
    if not c then return end
    local nm = nil
    pcall(function() nm = c.name end)
    local spec = nm and PAINT[nm]
    if spec then
      pcall(function()
        c:SetImage(Enum.ImageSource.StaticReference, spec[1])
        c.imageColor = Color.FromRGBA(spec[2][1], spec[2][2], spec[2][3], spec[2][4])
        if spec[3] and spec[4] then c:SetSizeDelta(spec[3], spec[4]) end
      end)
      painted = painted + 1
    end
    if nm and LABEL_FIX[nm] then
      pcall(function() c:SetSizeDelta(72, 32) end)
      fixed = fixed + 1
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if kids then
      for i = 1, #kids do rec(kids[i]) end
    end
  end
  pcall(function() rec(root) end)
  return painted, fixed
end

-- ===== 背景动态：云和地砖条缓慢循环右移 =====
-- 用图元实例拼（不新增控件资源）；名字以「景」开头，兜底清扫会跳过它们。
local DECOR_PREFIX = '景'
local decor = {}

local function isDecor(c)
  local nm = nil
  pcall(function() nm = c.name end)
  if type(nm) ~= 'string' then return false end
  return string.sub(nm, 1, #DECOR_PREFIX) == DECOR_PREFIX
end

local function makeShape(template, name, w, h, r, g, b, a, sx, sy, speed)
  if not root then return nil end
  local ok, c = pcall(function() return game.InstantiateClientUIControl(template, root) end)
  if not ok or not c then return nil end
  local face, edge
  pcall(function()
    c.name = name
    c:SetSizeDelta(w, h)
    face = c:GetChild('面')
    edge = c:GetChild('描边')
    if edge then edge:SetVisible(false) end
    if face then
      face:SetSizeDelta(w, h)
      face.imageColor = Color.FromRGBA(r, g, b, a)
    end
    place(c, sx, sy)
  end)
  local d = { c = c, x = sx, y = sy, w = w, speed = speed }
  decor[#decor + 1] = d
  return c
end

local function clearDecor()
  for i = #decor, 1, -1 do
    local d = decor[i]
    decor[i] = nil
    if d.c then killPart({ c = d.c }) end
  end
  -- 上一局遗留的同名前缀实例
  if root then
    pcall(function()
      local list = root:GetChildren()
      for i = 1, #list do
        local c = list[i]
        if c and isDecor(c) then killPart({ c = c }) end
      end
    end)
  end
end

local function buildDecor()
  -- 五朵云：压在 HUD 与洞口之间的天空带里缓慢右移，出画后从左侧回卷
  makeShape(TPL.dot, '景云1', 280, 92, 255, 255, 255, 135, 120, 168, 11)
  makeShape(TPL.dot, '景云2', 200, 74, 255, 255, 255, 115, 470, 232, 7)
  makeShape(TPL.dot, '景云3', 320, 104, 255, 255, 255, 125, 860, 186, 15)
  makeShape(TPL.dot, '景云4', 160, 62, 255, 255, 255, 105, 1150, 258, 9)
  makeShape(TPL.dot, '景云5', 240, 84, 255, 255, 255, 120, 300, 292, 13)
end

local function stepDecor(dt)
  for i = 1, #decor do
    local d = decor[i]
    local c = d.c
    if c and c.alive then
      d.x = d.x + d.speed * dt
      if d.x > 1280 + d.w * 0.5 then d.x = -d.w * 0.5 end
      pcall(function() place(c, d.x, d.y) end)
    end
  end
end

-- 扫掉所有模板实例残留（真机销毁可能不立即生效 → 重进关卡/结束 BONUS 时兜底清理）
local function sweepStaleInstances()
  if not root then return 0 end
  local removed = 0
  pcall(function()
    local list = root:GetChildren()
    if not list then return end
    for i = 1, #list do
      local c = list[i]
      if c and c.prefabIndex and TPL_SET[c.prefabIndex] and not isDecor(c) then
        removed = removed + 1
        pcall(function() c:SetVisible(false); c:SetActive(false) end)
        pcall(function() if c.alive then game.DestroyClientUIControl(c) end end)
      end
    end
  end)
  return removed
end

local function newRoot(tplIndex)
  if not root then return nil end
  while #parts >= MAX_PARTS do
    local idx = 1                     -- 优先淘汰最老的普通粒子，常驻粒子（BONUS 标题）不淘汰
    for j = 1, #parts do
      if not parts[j].keep then idx = j; break end
    end
    killPart(parts[idx])
    table.remove(parts, idx)
  end
  local ok, c = pcall(function() return game.InstantiateClientUIControl(tplIndex, root) end)
  if not ok or not c then
    if not ok then printerr('地鼠节拍：实例化模板失败 ' .. tostring(tplIndex)) end
    return nil
  end
  return c
end

local function childOf(c, name)
  if not c then return nil end
  local ok, v = pcall(function() return c:GetChild(name) end)
  if ok then return v end
  return nil
end

-- 命中爆点（白芯一闪）
local function spawnBurst(sx, sy, scale)
  local c = newRoot(TPL.burst)
  if not c then return end
  local base = (scale or 1) * rnd(70, 140) / 90
  place(c, sx, sy)
  c.localScaleX = base * 0.3
  c.localScaleY = base * 0.3
  parts[#parts + 1] = {
    kind = 'burst', c = c, t = 0, dur = 0.26, base = base,
    sx = sx, sy = sy, color = pickMD(), face = childOf(c, '爆'), lastA = -1,
  }
end

-- 冲击圆环
local function spawnRing(sx, sy, delay)
  local c = newRoot(TPL.ring)
  if not c then return end
  local base = rnd(80, 150) / 100
  place(c, sx, sy)
  c.localScaleX = base * 0.18
  c.localScaleY = base * 0.18
  parts[#parts + 1] = {
    kind = 'ring', c = c, t = 0, delay = delay or 0, dur = 0.38, base = base,
    sx = sx, sy = sy, color = pickMD(), face = childOf(c, '环'), lastA = -1,
  }
end

-- 糖果色块 / 圆形碎片
local function spawnBlock(sx, sy)
  local round = math.random() < 0.4
  local c = newRoot(round and TPL.dot or TPL.block)
  if not c then return end
  local sz = rnd(24, 82)
  local hh = sz
  if math.random() < 0.35 then hh = sz * 0.45 end
  local ang = math.random() * math.pi * 2
  local dist = rnd(90, 280)
  local p = {
    kind = 'block', c = c, t = 0, dur = rnd(0.34, 0.50),
    sx = sx + rnd(-6, 6), sy = sy + rnd(-6, 6),
    ax = math.cos(ang) * dist,
    ay = math.sin(ang) * dist - 20,          -- 网页 dy 里固定的 -20px 上抛
    rot = rnd(-230, 230),
    bsx = sz / 40, bsy = hh / 40,
    color = pickMD(),
    face = childOf(c, '面'), edge = childOf(c, '描边'), lastA = -1,
  }
  place(c, p.sx, p.sy)
  c.localScaleX = p.bsx * 0.45
  c.localScaleY = p.bsy * 0.45
  c.localRotationZ = 0
  parts[#parts + 1] = p
end

-- 四角星闪光
local function spawnStar(sx, sy)
  local c = newRoot(TPL.star)
  if not c then return end
  local ang = math.random() * math.pi * 2
  local dist = rnd(40, 150)
  local base = rnd(18, 44) / 40
  local color = MD[math.random(#MD)]
  if math.random() < 0.5 then color = { 255, 255, 255 } end
  place(c, sx + math.cos(ang) * dist, sy + math.sin(ang) * dist)
  c.localScaleX = base * 0.2
  c.localScaleY = base * 0.2
  parts[#parts + 1] = {
    kind = 'star', c = c, t = 0, delay = rnd(0, 0.08), dur = 0.34, base = base,
    color = color, face = childOf(c, '星'), lastA = -1,
  }
end

-- 涂鸦字（白字 + 靛蓝描边 + 粉/青错位）
local function spawnWord(sx, sy, str, fontScale, deg, keep)
  local c = newRoot(TPL.word)
  if not c then return nil end
  local c1 = childOf(c, '字')
  local c2 = childOf(c, '影青')
  local c3 = childOf(c, '影粉')
  if c1 then c1.text = str end
  if c2 then c2.text = str end
  if c3 then c3.text = str end
  place(c, sx, sy)
  c.localRotationZ = deg or 0
  local p = {
    kind = keep and 'title' or 'word', c = c, t = 0, dur = keep and 0.5 or 0.72,
    sx = sx, sy = sy, scale = fontScale or 1, deg = deg or 0,
    c1 = c1, c2 = c2, c3 = c3, keep = keep, lastA = -1, done = false,
  }
  local s = (fontScale or 1) * 0.35
  c.localScaleX = s
  c.localScaleY = s
  parts[#parts + 1] = p
  return p
end

-- 结算数字（+N）
local function spawnNum(sx, sy, str, base, color, dur)
  local c = newRoot(TPL.num)
  if not c then return end
  local face = childOf(c, '数')
  if face then face.text = str end
  place(c, sx, sy)
  local b = base or 1
  c.localScaleX = 0.7 * b
  c.localScaleY = 0.7 * b
  parts[#parts + 1] = {
    kind = 'num', c = c, t = 0, dur = dur or 0.85, sx = sx, sy = sy,
    face = face, lastA = -1, base = b, color = color or C_NUM,
  }
end

-- 史莱姆被打飞
local function spawnFling(sx, sy, artId)
  local c = newRoot(TPL.slime)
  if not c then return end
  local img = childOf(c, '图')
  if img then pcall(function() img:SetImage(Enum.ImageSource.Prefab, artId) end) end
  local ang = -math.pi / 2 + rnd(-0.55, 0.55) * math.pi
  local dist = rnd(520, 940)
  local sign = 1
  if math.random() < 0.5 then sign = -1 end
  place(c, sx, sy)
  c.localScaleX = 1.1
  c.localScaleY = 1.1
  parts[#parts + 1] = {
    kind = 'fling', c = c, t = 0, dur = 0.68, sx = sx, sy = sy,
    ax = math.cos(ang) * dist, ay = math.sin(ang) * dist,
    rot = sign * rnd(260, 680), base = 1.1, face = img, lastA = -1,
  }
end

-- 新手引导：常驻涂鸦字提示（fx涂鸦 模板 keep=true，和命中字同一套样式）
local TUT = { step = 1, word = nil, hideAt = 0 }

local function hintHide()
  if not TUT.word then return end
  for i = #parts, 1, -1 do
    if parts[i] == TUT.word then
      table.remove(parts, i)
      break
    end
  end
  killPart(TUT.word)
  TUT.word = nil
end

local function hintShow(text, sx, sy, scale)
  hintHide()
  TUT.word = spawnWord(sx, sy, text, scale or 0.85, 0, true)
end

-- 一整套打击特效（网页 impact()）
-- ===== 画布适配：贴边 HUD 拉到屏幕边缘（16:9 画布位移为 0） =====
local CW, CH = DESIGN_W, DESIGN_H
local fit = { L = 0, R = 0, T = 0, B = 0 }

local function measureCanvas()
  pcall(function()
    local w, h = game.GetUICanvasSize()
    if w and h and w > 0 and h > 0 then
      CW, CH = w, h
      baseScale = math.min(w / DESIGN_W, h / DESIGN_H)
      local k = baseScale
      if k > 0 then
        fit.L = 640 - w / (2 * k)
        fit.R = w / (2 * k) - 640
        fit.T = h / (2 * k) - 360
        fit.B = 360 - h / (2 * k)
      end
    end
  end)
end

local FITL = {
  left = { '商店-阴影', '商店-底', '商店-图标', '商店-字', '转盘-阴影', '转盘-底', '转盘-图标', '转盘-字',
    '老虎机-阴影', '老虎机-底', '老虎机-图标', '老虎机-字', '金币-阴影', '金币-底', '金币-图标', '金币-数',
    '武器-阴影', '武器-底', '武器-数', '商店-入口', '转盘-入口', '老虎机-入口' },
  topc = { '进度-底', '进度-槽', '进度-条', '进度-名', '进度-数', '连击', '连击-字' },
  topr = { '提示', '提示-底', '提示-影' },
  botr = { '音效', '音效-字', '音效-判定', '重开', '重开-字' },
}

local function nudge(c, dx, dy)
  if not c then return end
  if dx == 0 and dy == 0 then return end
  pcall(function()
    c.anchoredPositionX = c.anchoredPositionX + dx
    c.anchoredPositionY = c.anchoredPositionY + dy
  end)
end

local function fitHud()
  for i = 1, #FITL.left do nudge(ui(FITL.left[i]), fit.L, fit.T) end
  for i = 1, #FITL.topc do nudge(ui(FITL.topc[i]), 0, fit.T) end
  for i = 1, #FITL.topr do nudge(ui(FITL.topr[i]), fit.R, fit.T) end
  for i = 1, #FITL.botr do nudge(ui(FITL.botr[i]), fit.R, fit.B) end
end

local function hintNearCard(text, scale)
  local c = ui('转盘-入口')
  local ox, oy = -571, 220
  if c then pcall(function() ox = c.anchoredPositionX; oy = c.anchoredPositionY end) end
  hintShow(text, ox + 160 + 640, 360 - oy, scale)
end

-- 提示按屏幕坐标摆（自动换算到画布缩放后的父级偏移）
local function hintScreen(text, px, py, scale)
  local k = baseScale > 0 and baseScale or 1
  hintShow(text, (px - CW / 2) / k + 640, 360 - (py - CH / 2) / k, scale)
end

local function impactAt(sx, sy, power)
  local n = (power >= 2 and 16 or 11) + math.floor(math.random() * 5)
  spawnBurst(sx, sy, power >= 2 and 1.2 or 1)
  local rings = 1 + math.floor(math.random() * 2)
  for k = 1, rings do
    spawnRing(sx + rnd(-15, 15), sy + rnd(-15, 15), (k - 1) * 0.055)
  end
  for _ = 1, n do spawnBlock(sx, sy) end
  local stars = 2 + math.floor(math.random() * 3)
  for _ = 1, stars do spawnStar(sx, sy) end
end

local function hitFx(ci, key, power)
  local cell = CELL[ci]
  local w = WORDS[key] or WORDS.water
  impactAt(cell[1], cell[2], power or 1)
  if key ~= 'bomb' then
    spawnFling(cell[1], cell[2] - 16, TYPES[key].icon)
  end
  spawnWord(cell[1], cell[2] - CELL_Y_BONUS, w[math.random(#w)], 1, rnd(-11, 11))
end

-- ========== 粒子逐帧 ==========
local function stepParts(dt)
  local i = #parts
  while i >= 1 do
    local p = parts[i]
    local c = p.c
    local dead = false
    if c == nil or not c.alive then
      dead = true
    else
      p.t = p.t + dt
      local lt = p.t - (p.delay or 0)
      if lt < 0 then
        if not p.hidden then p.hidden = true; c:SetVisible(false) end
      else
        if p.hidden then p.hidden = false; c:SetVisible(true) end
        local u = p.dur > 0 and math.min(1, lt / p.dur) or 1
        local kind = p.kind
        local a = 1

        if kind == 'block' then
          local px, py, k, rot
          if u < 0.34 then
            local e = outCubic(u / 0.34)
            px = p.sx + p.ax * 0.6 * e
            py = p.sy + p.ay * 0.6 * e
            k = 0.45 + 0.70 * e
            rot = p.rot * 0.55 * e
          else
            local e = outCubic((u - 0.34) / 0.66)
            px = p.sx + p.ax * (0.6 + 0.4 * e)
            py = p.sy + p.ay * (0.6 + 0.4 * e)
            k = 1.15 - 0.45 * e
            rot = p.rot * (0.55 + 0.45 * e)
            a = 1 - e
          end
          place(c, px, py)
          c.localScaleX = p.bsx * k
          c.localScaleY = p.bsy * k
          c.localRotationZ = rot
        elseif kind == 'ring' then
          local e = outCubic(u)
          c.localScaleX = p.base * (0.18 + 1.57 * e)
          c.localScaleY = c.localScaleX
          a = 1 - e
        elseif kind == 'burst' then
          local e = outCubic(u)
          c.localScaleX = p.base * (0.3 + 1.2 * e)
          c.localScaleY = c.localScaleX
          a = 1 - e
        elseif kind == 'star' then
          local sc, rot
          if u < 0.30 then
            local e = u / 0.30
            sc = 0.2 + 1.05 * e
            rot = 20 * e
            a = e
          else
            local e = (u - 0.30) / 0.70
            sc = 1.25 - 0.75 * e
            rot = 20 + 50 * e
            a = 1 - e
          end
          c.localScaleX = p.base * sc
          c.localScaleY = p.base * sc
          c.localRotationZ = rot
        elseif kind == 'word' then
          local dy, sc
          if u < 0.30 then
            local e = outCubic(u / 0.30)
            dy = -22 + 28 * e
            sc = 0.35 + 0.81 * e
            a = e
          elseif u < 0.46 then
            local e = (u - 0.30) / 0.16
            dy = 6 - 4 * e
            sc = 1.16 - 0.18 * e
          elseif u < 0.74 then
            local e = (u - 0.46) / 0.28
            dy = 2 + 12 * e
            sc = 0.98 + 0.02 * e
          else
            local e = outCubic((u - 0.74) / 0.26)
            dy = 14 + 32 * e
            sc = 1 - 0.06 * e
            a = 1 - e
          end
          place(c, p.sx, p.sy - dy)
          c.localScaleX = p.scale * sc
          c.localScaleY = p.scale * sc
        elseif kind == 'title' then
          if not p.done then
            local e = math.min(1, p.t / 0.5)
            local sc = p.scale * (2.4 - 1.4 * outBack(e))
            place(c, p.sx, p.sy)
            c.localScaleX = sc
            c.localScaleY = sc
            a = math.min(1, e * 1.6)
            if e >= 1 then
              p.done = true
              c.localScaleX = p.scale
              c.localScaleY = p.scale
              a = 1
            end
          else
            a = nil
          end
        elseif kind == 'num' then
          local dy, sc
          if u < 0.22 then
            local e = u / 0.22
            dy = -14 + 18 * e
            sc = 0.7 + 0.38 * e
            a = e
          else
            local e = (u - 0.22) / 0.78
            dy = 4 + 48 * e
            sc = 1.08 - 0.08 * e
            a = 1 - e
          end
          place(c, p.sx, p.sy - dy)
          c.localScaleX = sc * (p.base or 1)
          c.localScaleY = sc * (p.base or 1)
        elseif kind == 'fling' then
          local dx, dy, rot, sc
          if u < 0.15 then
            local e = u / 0.15
            dx = p.ax * 0.1 * e
            dy = p.ay * 0.1 * e - 26 * e
            rot = p.rot * 0.12 * e
            sc = 1 + 0.08 * e
          else
            local t = (u - 0.15) / 0.85
            local e = 1 - (1 - t) * (1 - t)
            dx = p.ax * (0.1 + 0.9 * e)
            dy = (p.ay * 0.1 - 26) + (p.ay * 0.9 + 26 + 160) * e
            rot = p.rot * (0.12 + 0.88 * e)
            sc = 1.08 - 0.73 * e
            a = 1 - e
          end
          place(c, p.sx + dx, p.sy + dy)
          c.localScaleX = p.base * sc
          c.localScaleY = p.base * sc
          c.localRotationZ = rot
        end

        if a ~= nil then
          local ab = aByte(a)
          if ab ~= p.lastA then
            p.lastA = ab
            if kind == 'word' or kind == 'title' then
              fontTint(p.c1, WORDCOL.main, ab)
              fontTint(p.c2, WORDCOL.cyan, ab)
              fontTint(p.c3, WORDCOL.pink, ab)
            elseif kind == 'num' then
              fontTint(p.face, p.color or C_NUM, ab)
            elseif kind == 'fling' then
              tint(p.face, { 255, 255, 255 }, ab)
            elseif p.face then
              tint(p.face, p.color, ab)
              if p.edge then tint(p.edge, INK, ab) end
            end
          end
        end

        if u >= 1 and not p.keep then dead = true end
      end
    end
    if dead then
      killPart(p)
      table.remove(parts, i)
    end
    i = i - 1
  end
end

-- ========== HUD ==========
refresh = function()
  setText('金币-数', S.coins)
  setComboTexts()
  local need = CHEST[S.stage + 1]
  setText('进度-名', need and CHEST_NAME[S.stage + 1] or '全部领完')
  setText('进度-数', need and (math.min(S.hits, need) .. ' / ' .. need) or '★')
  local bar = ui('进度-条')
  if bar then
    local ratio = need and math.min(1, S.hits / need) or 1
    bar.sizeDeltaX = math.max(1, 462 * ratio)
  end
end

-- ========== 地鼠 ==========
local function pickType()
  local total = 0
  for _, k in ipairs(ORDER) do total = total + TYPES[k].w end
  local r = math.random() * total
  for _, k in ipairs(ORDER) do
    r = r - TYPES[k].w
    if r <= 0 then return k end
  end
  return 'water'
end

local function hideMole(i)
  local h = holes[i]
  h.state = 'idle'
  h.type = nil
  h.rise = nil
  local c = h.ctrl
  if c then
    pcall(function()
      c.localScaleX = 1
      c.localScaleY = 1
      c.anchoredPositionX = h.baseX
      c.anchoredPositionY = h.baseY
    end)
  else
    setScale('史莱姆' .. i, 1)
  end
  show('史莱姆' .. i, false)
end

-- 出洞位移/缩放：e=0 在洞底且缩小，e=1 恢复到原位原尺寸
local function applyRise(i, e)
  local h = holes[i]
  local c = h.ctrl
  if not c then return end
  local s, yOff
  if e >= 1 then
    s = 1
    yOff = 0
  else
    local k = 1 - (1 - e) * (1 - e)                  -- 缓出
    local rebound = 0.10 * math.sin(math.pi * e) * (1 - e)   -- 冒出时的小回弹
    s = RISE_SCALE0 + (1 - RISE_SCALE0) * k + rebound
    yOff = -RISE_SINK * (1 - k)
  end
  pcall(function()
    c.localScaleX = s
    c.localScaleY = s
    c.anchoredPositionX = h.baseX
    c.anchoredPositionY = h.baseY + yOff
  end)
end

local function stepMoleRise()
  for i = 1, 9 do
    local h = holes[i]
    if h.state == 'up' and h.rise and h.rise < 1 then
      local e = (clock - h.riseAt) / RISE_DUR
      if e > 1 then e = 1 end
      if e ~= h.rise then
        h.rise = e
        applyRise(i, e)
      end
    end
  end
end

local function showMole(i, key)
  local h = holes[i]
  h.state = 'up'
  h.type = key
  h.expire = clock + TYPES[key].dur
  setIcon('史莱姆' .. i, TYPES[key].icon)
  show('史莱姆' .. i, true)
  h.riseAt = clock
  h.rise = 0
  applyRise(i, 0)              -- 先摆到洞底的小尺寸，再逐帧冒出来
  spawned = spawned + 1
  if spawned <= 3 then print('地鼠节拍：spawn #' .. spawned .. ' 洞' .. i .. ' ' .. key) end
end

local function punchBig()
  setScale('大史莱姆', 1.25)
  punchAt = clock + 0.12
end

-- ========== BONUS ==========
local function startBonus()
  BONUS.active = true
  BONUS.hits = 0
  BONUS.need = math.random(9, 11)
  BONUS.endAt = clock + 3.0
  BONUS.boomAt = 0
  BONUS.lastHitAt = clock
  for i = 1, 9 do
    if holes[i].state == 'up' then hideMole(i) end
    show('判定' .. i, false)          -- BONUS 期间只让「判定大」吃点击
  end
  hudSet(false)                       -- 网页 .screen.bonus 会淡出 HUD
  setIcon('大史莱姆', BONUS_ARTS[math.random(#BONUS_ARTS)])
  setScale('大史莱姆', 1)
  local big = ui('大史莱姆')
  if big then pcall(function() big.imageColor = Color.FromRGBA(255, 255, 255, 255) end) end
  show('大史莱姆', true)
  show('倒计时', true)
  hideTip()
  setText('倒计时', '3.0s')
  lastTimer = '3.0s'

  bonusRing = newRoot(TPL.rainbow)
  if bonusRing then
    place(bonusRing, 640, 360)
    bonusRing.localScaleX = 1
    bonusRing.localScaleY = 1
    bonusRing.localRotationZ = 0
  else
    printerr('地鼠节拍：彩虹环实例化失败')
  end
  spawnWord(640, 86, 'BONUS!', 1.75, -5, true)
  impactAt(640, 360, 2)
  sfx(SFX.bonus)
  print('地鼠节拍：BONUS 开始，需要 ' .. BONUS.need .. ' 下')
end

local function endBonus()
  if bonusRing then
    local ring = bonusRing
    bonusRing = nil
    killPart({ c = ring })
  end
  for i = #parts, 1, -1 do
    if parts[i].kind == 'title' then
      killPart(parts[i])
      table.remove(parts, i)
    end
  end
  sweepStaleInstances()                 -- 兜底：把上一轮漏掉的彩虹环等实例一起扫掉
  for i = 1, 9 do show('判定' .. i, true) end
  hudSet(true)                        -- 恢复 HUD（推镜会自己衰减回去）
  hideTip()
  sfx(SFX.bonusEnd)
  sendSignal('地鼠_BONUS')            -- 成就：累计完成 BONUS
  show('倒计时', false)
  show('大史莱姆', false)
  setScale('大史莱姆', 1)
  local big = ui('大史莱姆')
  if big then pcall(function() big.imageColor = Color.FromRGBA(255, 255, 255, 255) end) end
  BONUS.active = false
  BONUS.boomAt = 0
  BONUS.nextAt = S.hits + math.random(7, 15)
  nextSpawn = 0.25
  print('地鼠节拍：BONUS 结束')
end

local function onBonusHit()
  if not BONUS.active or BONUS.boomAt > 0 then return end
  BONUS.hits = BONUS.hits + 1
  local gain = BONUS.hits
  S.coins = S.coins + gain
  BONUS.lastHitAt = clock
  camZoom = math.min(0.52, camZoom + 0.05)     -- 网页 applyCam()：每下 +0.05，上限 0.52
  kick(6, 0.18)
  punchBig()
  sfx(SFX.punch)
  sfx(BONUS_PATS[(BONUS.hits - 1) % #BONUS_PATS + 1])
  spawnNum(640 + rnd(-80, 80), 180, '+' .. gain)
  impactAt(640, 360, 1)
  refresh()
  print('地鼠节拍：BONUS 第 ' .. BONUS.hits .. ' 下 +' .. gain)
  if BONUS.hits >= BONUS.need then
    S.combo = S.combo + BONUS.need
    refresh()
    BONUS.boomAt = clock + 0.42
    impactAt(640, 360, 3)
    spawnBurst(640, 360, 3)
    kick(11, 0.3)
    sfx(SFX.boom)
    print('地鼠节拍：BONUS 爆炸')
  end
end

-- ========== 命中 ==========
local function onHit(i)
  if BONUS.active then return end
  local h = holes[i]
  if h.state ~= 'up' then
    sfx(SFX.whiff)
    if S.combo > 0 then
      S.combo = 0
      refresh()
    end
    return
  end
  local key = h.type
  local def = TYPES[key]
  if key == 'bomb' then
    S.combo = 0
    impactAt(CELL[i][1], CELL[i][2], 2)
    spawnWord(CELL[i][1], CELL[i][2] - CELL_Y_BONUS, '砰！', 1, rnd(-11, 11))
    sfx(SFX.bomb)
    hideMole(i)
    refresh()
    tip('砰！爆炸桶不能敲', 1800)
    return
  end
  local gain = math.max(1, math.floor(math.random(def.lo, def.hi) * comboMult(S.combo + 1) * weaponMult()))
  S.coins = S.coins + gain
  S.combo = S.combo + 1
  S.hits = S.hits + 1
  sendSignal('地鼠_命中')                   -- 成就：累计命中次数
  coinPending = coinPending + gain          -- 成就：每累计 100 金币计 1 次
  while coinPending >= 100 do
    coinPending = coinPending - 100
    sendSignal('地鼠_金币100')
  end
  if S.combo == 30 then sendSignal('地鼠_连击') end   -- 成就：单局 30 连击
  hitFx(i, key, key == 'geo' and 2 or 1)
  sfx(SFX.punch)
  sfx(SFX[key] or SFX.water)
  if S.combo % 5 == 0 then sfx(SFX.combo) end
  comboBump()
  spawnNum(CELL[i][1], CELL[i][2] - 84, '+' .. gain, 0.38, NUM_COLOR[key], 0.75)
  hideMole(i)
  refresh()
  print('地鼠节拍：命中 洞' .. i .. ' +' .. gain .. ' 金币=' .. S.coins)
end

local function toggleMute()
  muted = not muted
  if soundLabel then soundLabel.text = muted and '静音' or '音效' end
  if not muted then sfx(SFX.ui) end
end

local function bind()
  for i = 1, 9 do
    local j = ui('判定' .. i)
    if j then
      j:AddCursorEventListener(Enum.CursorEventType.CursorClick, function() onHit(i) end)
    else
      printerr('地鼠节拍：找不到 判定' .. i)
    end
  end
  local b = ui('判定大')
  if b then
    b:AddCursorEventListener(Enum.CursorEventType.CursorClick, onBonusHit)
  else
    printerr('地鼠节拍：找不到 判定大')
  end
  local s = ui('音效-判定')
  if s then
    s:AddCursorEventListener(Enum.CursorEventType.CursorClick, toggleMute)
  else
    printerr('地鼠节拍：找不到 音效-判定')
  end
  local enter = ui('商店-入口')
  if enter then enter:AddCursorEventListener(Enum.CursorEventType.CursorClick, openShop) end
end

-- ========== 中奖演出（网页 .jackpot：全屏浅蓝闪屏 + JACKPOT 黄字弹出） ==========
local jack = { on = false, t = 0, dur = 1.1, flash = nil, text = nil, shadow = nil }

local function playJack(flashCtrl, textCtrl, shadowCtrl, str, dur, lose)
  if textCtrl then
    pcall(function()
      textCtrl.fontColor = lose and Color.FromRGBA(247, 252, 255, 255) or Color.FromRGBA(255, 241, 0, 255)
    end)
  end
  if shadowCtrl then
    pcall(function()
      shadowCtrl.fontColor = lose and Color.FromRGBA(143, 180, 204, 255) or Color.FromRGBA(255, 112, 49, 255)
    end)
  end
  jack.on = true
  jack.t = 0
  jack.dur = dur or 1.1
  jack.flash, jack.text, jack.shadow = flashCtrl, textCtrl, shadowCtrl
  if textCtrl then pcall(function() textCtrl.text = str; textCtrl:SetVisible(true) end) end
  if shadowCtrl then pcall(function() shadowCtrl.text = str; shadowCtrl:SetVisible(true) end) end
  if flashCtrl then pcall(function() flashCtrl:SetVisible(true) end) end
end

local function stepJack(dt)
  if not jack.on then return end
  jack.t = jack.t + dt
  local u = jack.t / jack.dur
  if u >= 1 then
    jack.on = false
    if jack.flash then pcall(function() jack.flash:SetVisible(false) end) end
    if jack.text then pcall(function() jack.text:SetVisible(false) end) end
    if jack.shadow then pcall(function() jack.shadow:SetVisible(false) end) end
    return
  end
  local fa = 0
  if u < 0.08 then fa = u / 0.08
  elseif u < 0.62 then fa = 1
  else fa = (1 - u) / 0.38 end
  if jack.flash then
    local ab = math.floor(fa * 128 + 0.5)
    pcall(function() jack.flash.imageColor = Color.FromRGBA(189, 239, 255, ab) end)
  end
  local sc
  if u < 0.28 then sc = 0.45 + 0.67 * (u / 0.28)
  elseif u < 0.44 then sc = 1.12 - 0.12 * ((u - 0.28) / 0.16)
  else sc = 1 end
  if jack.text then pcall(function() jack.text.localScaleX = sc; jack.text.localScaleY = sc end) end
  if jack.shadow then pcall(function() jack.shadow.localScaleX = sc; jack.shadow.localScaleY = sc end) end
end

-- 转盘中奖格高亮（网页 .seg.win：亮黄描边 + 提亮，常驻到下一次开转）
local function wheelHighlight(bag, idx)
  local c = bag['转盘-中奖格']
  if not c then return end
  local deg = idx * 11.6129
  local th = deg * math.pi / 180
  pcall(function()
    c.anchoredPositionX = math.sin(th) * 99.5
    c.anchoredPositionY = math.cos(th) * 99.5
    c.localRotationZ = 180 - deg
    c:SetVisible(true)
  end)
end

-- 老虎机三窗黄圈（网页 .reel.win：黄描边 + 0.5s 弹一下）
local function reelGlow(bag, on)
  for i = 1, 3 do
    local c = bag['老虎机-窗亮' .. i]
    if c then pcall(function() c:SetVisible(on) end) end
  end
  bag.glowT = on and 0.5 or 0
end

local function stepReelGlow(bag, dt)
  local t = bag.glowT or 0
  if t <= 0 then return end
  t = t - dt
  bag.glowT = t
  local u = 1 - math.max(0, t) / 0.5
  local sc
  if u < 0.45 then sc = 1 + 0.06 * (u / 0.45) else sc = 1.06 - 0.06 * ((u - 0.45) / 0.55) end
  if t <= 0 then sc = 1 end
  for i = 1, 3 do
    local c = bag['老虎机-窗亮' .. i]
    if c then pcall(function() c.localScaleX = sc; c.localScaleY = sc end) end
  end
end

-- ========== 转盘页 ==========
local WCFG = { step = 11.6129, spin = 3.4, settle = 3.55 }
local W = { bet = 10, spinning = false, t = 0, from = 0, to = 0, idx = 0, color = 'red', hist = {} }

local function cachePage(pgName, bag, names)
  local pg = pageOf(pgName)
  if not pg then
    printerr('地鼠节拍：找不到页面 ' .. pgName)
    return
  end
  bag.page = pg
  for i = 1, #names do bag[names[i]] = pg:GetChild(names[i]) end
end

local function setIconIn(ctrl, id)
  if ctrl then pcall(function() ctrl:SetImage(Enum.ImageSource.Prefab, id) end) end
end

local function syncWheel()
  if not W.page then return end
  setTextIn(W, '转盘-金额', W.bet)
  setTextIn(W, '转盘-金币数', S.coins)
  for i = 1, 5 do
    local chip = W['转盘-筹' .. i]
    if chip then
      local on = tonumber(W.CHIPS[i]) == W.bet
      pcall(function() chip.imageColor = on and Color.FromRGBA(255, 241, 0, 255) or Color.FromRGBA(247, 252, 255, 255) end)
    end
  end
end

local function wheelSetBet(n)
  n = math.floor(n)
  if n < 1 then n = 1 end
  if n > 9999999 then n = 9999999 end
  W.bet = n
  syncWheel()
end

local function wheelLandTip(color, net, ret)
  if color == 'green' then
    W.tipText = '绿格通杀！　' .. (net >= 0 and '+' or '') .. net .. ' 金币（返还 ' .. ret .. '）'
  else
    W.tipText = '中！' .. (color == 'red' and '红' or '黑') .. '　+' .. net .. ' 金币（返还 ' .. ret .. '）'
  end
end

local function wheelPress(color)
  if page ~= 'wheel' or W.spinning then return end
  if S.coins < W.bet then
    W.tipText = '金币不足，去地鼠那边打一点回来'
    W.tipColor = Color.FromRGBA(255, 112, 49, 255)
    return
  end
  S.coins = S.coins - W.bet
  W.spinning = true
  W.t = 0
  W.color = color
  W.idx = math.random(0, 30)
  if TUT.step == 2 then
    -- 引导第一把必中：让他一定看到中奖演出
    W.idx = (color == 'red') and 1 or ((color == 'black') and 2 or 0)
  end
  local cur = W.sectors and W.sectors.localRotationZ or 0
  W.from = cur
  local target = W.idx * WCFG.step + rnd(-2.9, 2.9)
  local delta = (target - cur) % 360
  if delta < 0 then delta = delta + 360 end
  W.to = cur + 2160 + delta
  local lastWin = W['转盘-中奖格']
  if lastWin then pcall(function() lastWin:SetVisible(false) end) end
  W.tipText = '转动中…　押 ' .. (color == 'red' and '红' or color == 'black' and '黑' or '绿')
  W.tipColor = Color.FromRGBA(7, 10, 125, 190)
  sfx(SFX.ui)
  syncWheel()
end

local function wheelSettle()
  local idx = W.idx
  local color = 'black'
  if idx == 0 then color = 'green'
  elseif idx % 2 == 1 then color = 'red' end
  local letter = color == 'green' and 'G' or color == 'red' and 'R' or 'B'
  local mult = color == 'green' and 15 or 2
  local ret = 0
  local net = -W.bet
  if color == W.color then
    ret = W.bet * mult
    S.coins = S.coins + ret
    net = ret - W.bet
    wheelLandTip(color, net, ret)
    wheelHighlight(W, idx)
    -- 红/黑 ×2 也给中奖演出；绿格 ×15 用 JACKPOT 文案
    local big = mult >= 15
    sfx(SFX.win)
    sfx(SFX.chest)
    sfx(SFX.coin2)
    if big then sfx(SFX.applause) end
    playJack(W['转盘-闪光'], W['转盘-JACKPOT'], W['转盘-JACKPOT影'],
      (big and 'JACKPOT! ×' or 'WIN! ×') .. mult,
      big and 1.1 or 0.85, false)
  else
    W.tipText = '未中　-' .. W.bet .. ' 金币'
    sfx(SFX.lose)
    hintHide()
    playJack(W['转盘-闪光'], W['转盘-JACKPOT'], W['转盘-JACKPOT影'], 'LOSE QWQ', 0.85, true)
  end
  table.insert(W.hist, 1, { letter = letter, color = color })
  while #W.hist > 12 do table.remove(W.hist) end
  for i = 0, 11 do
    local blk, txt = W['转盘-史' .. i], W['转盘-史字' .. i]
    local row = W.hist[i + 1]
    if blk then
      local c = row and (row.color == 'red' and Color.FromRGBA(255, 216, 210, 255)
        or row.color == 'green' and Color.FromRGBA(204, 245, 218, 255)
        or Color.FromRGBA(7, 10, 125, 255)) or Color.FromRGBA(7, 10, 125, 20)
      pcall(function() blk.imageColor = c end)
    end
    if txt then
      txt.text = row and row.letter or ''
      pcall(function()
        txt.fontColor = (row and row.color == 'black') and Color.FromRGBA(255, 255, 255, 255)
          or Color.FromRGBA(7, 10, 125, 255)
      end)
    end
  end
  W.spinning = false
  if TUT.step == 2 then
    TUT.step = 3
    hintScreen(color == W.color and '中啦！' or '没中…', CW / 2, 52 * baseScale, 1.0)
    TUT.hideAt = clock + 3.2
  end
  refresh()
  refreshWeapon()
  syncWheel()
end

local function stepWheel(dt)
  if not W.page then return end
  if W.tipText and W.tipText ~= W.shownTip then
    W.shownTip = W.tipText
    setTextIn(W, '转盘-提示', W.tipText)
    if W.tipTextCtrl and W.tipColor then
      pcall(function() W.tipTextCtrl.fontColor = W.tipColor end)
    end
  end
  if not W.spinning then return end
  W.t = W.t + dt
  local u = math.min(1, W.t / WCFG.spin)
  local e = 1 - (1 - u) * (1 - u) * (1 - u) * (1 - u)
  if W.sectors then
    W.sectors.localRotationZ = W.from + (W.to - W.from) * e
  end
  if W.t >= WCFG.settle then
    local ok, err = pcall(wheelSettle)
    if not ok then printerr('转盘结算异常: ' .. tostring(err)) end
  end
end

-- ========== 老虎机页 ==========
local SLOTC = {
  syms = { 30002006, 10005010, 30002001, 30002008, 10005009, 10005008 },
  pay = { 12, 20, 30, 45, 90, 140 },
  w = { 26, 20, 18, 15, 13, 8 },
}
local SL = { bet = 10, spinning = false, stopped = 0, land = { 1, 1, 1 }, t = 0, cycle = 0,
  autoT = 0, settleAt = 0, jackpotUntil = 0, spins = 0, wins = 0, hist = {}, tipText = '', tipColor = nil }

local function pickSymbol()
  local total = 0
  for i = 1, #SLOTC.w do total = total + SLOTC.w[i] end
  local r = math.random() * total
  for i = 1, #SLOTC.w do
    r = r - SLOTC.w[i]
    if r <= 0 then return i end
  end
  return 1
end

local function syncSlot()
  if not SL.page then return end
  setTextIn(SL, '老虎机-金额', SL.bet)
  setTextIn(SL, '老虎机-金币数', S.coins)
  setTextIn(SL, '老虎机-统计', '已转 ' .. SL.spins .. ' 次 · 中 ' .. SL.wins .. ' 次')
  for i = 1, 5 do
    local chip = SL['老虎机-筹' .. i]
    if chip then
      local on = tonumber(SL.CHIPS[i]) == SL.bet
      pcall(function() chip.imageColor = on and Color.FromRGBA(255, 241, 0, 255) or Color.FromRGBA(247, 252, 255, 255) end)
    end
  end
  if SL.spinning then
    setTextIn(SL, '老虎机-按钮字', '停 止 ' .. SL.stopped .. '/3')
  else
    setTextIn(SL, '老虎机-按钮字', '转 动 ' .. SL.bet)
  end
  setTextIn(SL, '老虎机-提示', SL.tipText)
  if SL.tipCtrl and SL.tipColor then
    pcall(function() SL.tipCtrl.fontColor = SL.tipColor end)
  end
end

local function slotBet(n)
  n = math.floor(n)
  if n < 1 then n = 1 end
  if n > 9999999 then n = 9999999 end
  SL.bet = n
  syncSlot()
end

local function slotStopOne()
  if not SL.spinning or SL.stopped >= 3 then return end
  SL.stopped = SL.stopped + 1
  setIconIn(SL['老虎机-符' .. SL.stopped], SLOTC.syms[SL.land[SL.stopped]])
  sfx(SFX.ui)
  if SL.stopped >= 3 then
    SL.settleAt = clock + 0.28
    SL.tipText = '开 奖…'
    syncSlot()
  else
    syncSlot()
  end
end

local function slotSettle()
  local a, b, c = SL.land[1], SL.land[2], SL.land[3]
  SL.spins = SL.spins + 1
  if a == b and b == c then
    local mult = SLOTC.pay[a]
    local ret = SL.bet * mult
    S.coins = S.coins + ret
    local net = ret - SL.bet
    SL.wins = SL.wins + 1
    SL.tipText = '三连！　×' .. mult .. '　+' .. net .. ' 金币'
    SL.tipColor = Color.FromRGBA(7, 10, 125, 255)
    table.insert(SL.hist, 1, tostring(mult))
    while #SL.hist > 8 do table.remove(SL.hist) end
    reelGlow(SL, true)
    sfx(SFX.win)
    sfx(SFX.chest)
    sfx(SFX.coin2)
    if mult >= 90 then sfx(SFX.applause) end
    if mult >= 90 then
      playJack(SL['老虎机-闪光'], SL['老虎机-JACKPOT'], SL['老虎机-JACKPOT影'], 'JACKPOT! ×' .. mult)
    end
  else
    reelGlow(SL, false)
    SL.tipText = '未中　-' .. SL.bet .. ' 金币'
    SL.tipColor = Color.FromRGBA(255, 112, 49, 255)
    table.insert(SL.hist, 1, '0')
    while #SL.hist > 8 do table.remove(SL.hist) end
    sfx(SFX.whiff)
  end
  for i = 0, 7 do
    local blk, txt = SL['老虎机-史' .. i], SL['老虎机-史字' .. i]
    local v = SL.hist[i + 1]
    if txt then txt.text = v and (v == '0' and '—' or ('×' .. v)) or '' end
    if blk then
      pcall(function() blk.imageColor = (v and v ~= '0') and Color.FromRGBA(204, 245, 218, 255) or Color.FromRGBA(7, 10, 125, 18) end)
    end
  end
  SL.spinning = false
  SL.stopped = 0
  refresh()
  refreshWeapon()
  syncSlot()
end

local function slotStart()
  if page ~= 'slot' or SL.spinning then return end
  if S.coins < SL.bet then
    SL.tipText = '金币不足，去地鼠那边打一点回来'
    SL.tipColor = Color.FromRGBA(255, 112, 49, 255)
    syncSlot()
    return
  end
  S.coins = S.coins - SL.bet
  SL.spinning = true
  SL.stopped = 0
  SL.t = 0
  SL.cycle = 0
  SL.autoT = 0
  SL.settleAt = 0
  for i = 1, 3 do SL.land[i] = pickSymbol() end
  SL.tipText = '按「停 止」定格'
  SL.tipColor = Color.FromRGBA(7, 10, 125, 190)
  sfx(SFX.ui)
  syncSlot()
end

local function slotPress()
  if page ~= 'slot' then return end
  if SL.spinning then slotStopOne() else slotStart() end
end

local function stepSlot(dt)
  if not SL.page then return end
  if SL.settleAt > 0 and clock >= SL.settleAt then
    SL.settleAt = 0
    slotSettle()
    return
  end
  if not SL.spinning then return end
  SL.t = SL.t + dt
  SL.cycle = SL.cycle + dt
  if SL.cycle >= 0.09 then
    SL.cycle = 0
    for i = 1, 3 do
      if i > SL.stopped then setIconIn(SL['老虎机-符' .. i], SLOTC.syms[math.random(1, 6)]) end
    end
  end
  if SL.t > 9 and SL.stopped < 3 then
    SL.autoT = SL.autoT + dt
    if SL.autoT >= 0.6 then
      SL.autoT = 0
      slotStopOne()
    end
  end
end

local function openWheel()
  show('商店页', false)
  show('老虎机页', false)
  page = 'wheel'
  if W.page then pcall(function() W.page:SetAsLastSibling() end) end
  if TUT.step == 1 then TUT.step = 2 end
  if TUT.step == 2 then
    if S.coins >= 1 and W.bet > S.coins then wheelSetBet(S.coins) end
    hintScreen('押红或押黑', CW / 2, 52 * baseScale, 0.9)
  end
  syncWheel()
  show('转盘页', true)
  sfx(SFX.ui)
end

local function openSlot()
  show('商店页', false)
  show('转盘页', false)
  page = 'slot'
  if SL.page then pcall(function() SL.page:SetAsLastSibling() end) end
  SL.tipText = SL.tipText ~= '' and SL.tipText or '三个图案一样就中奖'
  syncSlot()
  show('老虎机页', true)
  sfx(SFX.ui)
end

local function closePage()
  hintHide()
  show('商店页', false)
  show('转盘页', false)
  show('老虎机页', false)
  show('老虎机-JACKPOT', false)
  page = nil
end

local W_NAMES = { '转盘扇区', '转盘-金额', '转盘-金币数', '转盘-提示', '转盘-闪光',
  '转盘-JACKPOT', '转盘-JACKPOT影', '转盘-中奖格', '转盘-减判', '转盘-加判',
  '转盘-全押判', '转盘-押红判', '转盘-押黑判', '转盘-押绿判', '转盘-返回判定' }
local SL_NAMES = { '老虎机-符1', '老虎机-符2', '老虎机-符3', '老虎机-金额', '老虎机-金币数', '老虎机-闪光',
  '老虎机-JACKPOT', '老虎机-JACKPOT影', '老虎机-窗亮1', '老虎机-窗亮2', '老虎机-窗亮3',
  '老虎机-按钮字', '老虎机-提示', '老虎机-统计', '老虎机-全押判', '老虎机-台判定',
  '老虎机-按钮判', '老虎机-返回判定', '老虎机-JACKPOT' }
for i = 1, 5 do
  W_NAMES[#W_NAMES + 1] = '转盘-筹判' .. i
  W_NAMES[#W_NAMES + 1] = '转盘-筹' .. i
  SL_NAMES[#SL_NAMES + 1] = '老虎机-筹判' .. i
  SL_NAMES[#SL_NAMES + 1] = '老虎机-筹' .. i
end
for i = 0, 11 do
  W_NAMES[#W_NAMES + 1] = '转盘-史' .. i
  W_NAMES[#W_NAMES + 1] = '转盘-史字' .. i
end
for i = 0, 7 do
  SL_NAMES[#SL_NAMES + 1] = '老虎机-史' .. i
  SL_NAMES[#SL_NAMES + 1] = '老虎机-史字' .. i
end
W.CHIPS = { '1', '5', '10', '50', '100' }
SL.CHIPS = { '1', '5', '10', '50', '100' }

local function bindPages()
  cachePage('商店页', SH, { '商店-Lv', '商店-收益', '商店-币', '商店-下一级', '商店-买字',
    '商店-pip1', '商店-pip2', '商店-pip3', '商店-pip4', '商店-pip5', '商店-买底', '商店-买影',
    '商店-关闭判定', '商店-买判定' })
  shopBuyBg = SH['商店-买底']
  shopBuyShade = SH['商店-买影']
  shopBuyText = SH['商店-买字']
  for i = 1, 5 do shopPips[i] = SH['商店-pip' .. i] end
  cachePage('转盘页', W, W_NAMES)
  cachePage('老虎机页', SL, SL_NAMES)
  W.sectors = W['转盘扇区']
  if W['转盘扇区'] then W['转盘-中奖格'] = W['转盘扇区']:GetChild('转盘-中奖格') end
  W.tipCtrl = W['转盘-提示']
  SL.tipCtrl = SL['老虎机-提示']
  local function on(ctrl, fn)
    if ctrl then ctrl:AddCursorEventListener(Enum.CursorEventType.CursorClick, fn) end
  end
  on(SH['商店-关闭判定'], closeShop)
  on(SH['商店-买判定'], buyWeapon)
  on(W['转盘-返回判定'], closePage)
  on(SL['老虎机-返回判定'], closePage)
  on(ui('转盘-入口'), openWheel)
  on(ui('老虎机-入口'), openSlot)
  for i = 1, 5 do
    local v = tonumber(W.CHIPS[i])
    local chipW, chipS = W['转盘-筹判' .. i], SL['老虎机-筹判' .. i]
    on(chipW, function() wheelSetBet(v) end)
    on(chipS, function() slotBet(v) end)
  end
  on(W['转盘-减判'], function() wheelSetBet(W.bet - 1) end)
  on(W['转盘-加判'], function() wheelSetBet(W.bet + 1) end)
  on(W['转盘-全押判'], function() wheelSetBet(S.coins) end)
  on(W['转盘-押红判'], function() wheelPress('red') end)
  on(W['转盘-押黑判'], function() wheelPress('black') end)
  on(W['转盘-押绿判'], function() wheelPress('green') end)
  on(SL['老虎机-全押判'], function() slotBet(S.coins) end)
  on(SL['老虎机-台判定'], slotPress)
  on(SL['老虎机-按钮判'], slotPress)
end

-- ========== 生命周期 ==========
function OnStart()
  root = script.object
  if root == nil then
    printerr('地鼠节拍：拿不到挂载控件')
    return
  end
  -- 设备适配：PC 画布 1600×900 与设计基准 1280×720 同为 16:9，等比放大 1.25 即铺满；
  -- 手机 1280×720 → 1.0（超宽屏 1560×720 取 min 只左右留窄边，不拉伸变形）。
  measureCanvas()
  applyCam()
  local found, missing = resolveTemplates()
  local missList = {}
  for k in pairs(missing) do missList[#missList + 1] = k end
  print('地鼠节拍：模板索引自检 认出 ' .. found .. '/9' ..
    (#missList > 0 and ('，未识别: ' .. table.concat(missList, ',')) or '') ..
    '（fx块=' .. tostring(TPL.block) .. ' fx彩虹=' .. tostring(TPL.rainbow) .. '）')
  local stale = sweepStaleInstances()
  if stale > 0 then print('地鼠节拍：清理模板实例残留 ' .. stale .. ' 个') end
  local reskinned = reskinAll()
  if reskinned > 0 then print('地鼠节拍：素材兜底替换 ' .. reskinned .. ' 张图') end
  local painted, fixedLabels = applyPaint()
  if painted > 0 or fixedLabels > 0 then
    print('地鼠节拍：图标重绘 ' .. painted .. ' 个，标签加高 ' .. fixedLabels .. ' 个')
  end
  clearDecor()
  buildDecor()
  print('地鼠节拍：背景动态 ' .. #decor .. ' 个')
  for i = 1, 9 do
    local c = ui('史莱姆' .. i)
    local bx, by = 0, 0
    if c then
      pcall(function()
        bx = c.anchoredPositionX
        by = c.anchoredPositionY
      end)
    end
    holes[i] = { state = 'idle', type = nil, expire = 0, ctrl = c, baseX = bx, baseY = by }
    show('史莱姆' .. i, false)
  end
  show('大史莱姆', false)
  show('倒计时', false)
  cacheHud()
  fitHud()
  comboBox = ui('连击')
  if comboBox then
    comboMain = comboBox:GetChild('数')
    comboBlue = comboBox:GetChild('影蓝')
    comboOrange = comboBox:GetChild('影橙')
  else
    printerr('地鼠节拍：找不到 连击')
  end
  tipText = ui('提示')
  tipBg = ui('提示-底')
  tipShadow = ui('提示-影')
  hideTip()
  soundLabel = ui('音效-字')
  for i = 1, 5 do shopPips[i] = ui('商店-pip' .. i) end
  shopBuyBg = ui('商店-买底')
  shopBuyShade = ui('商店-买影')
  shopBuyText = ui('商店-买字')
  refreshWeapon()
  bind()
  bindPages()
  tip('点冒头的史莱姆！小心爆炸桶', 2600)
  hintNearCard('点转盘试试', 0.8)
  BONUS.nextAt = math.random(7, 15)
  refresh()
  pcall(function() script:EnableUpdate(true) end)
  print('地鼠节拍：主场景已启动（运行时粒子特效） baseScale=' .. string.format('%.3f', baseScale))
end

function OnUpdate(dt)
  if root == nil then return end
  frame = frame + 1
  clock = clock + dt
  if frame % 120 == 0 then
    print(string.format('地鼠节拍：t=%.1f frame=%d 粒子=%d', clock, frame, #parts))
  end

  stepParts(dt)
  stepCam(dt)
  stepDecor(dt)
  stepMoleRise()
  stepCombo(dt)
  if tipUntil > 0 and clock >= tipUntil then hideTip() end
  stepWheel(dt)
  stepSlot(dt)
  stepJack(dt)
  stepReelGlow(SL, dt)
  if TUT.hideAt > 0 and clock >= TUT.hideAt then
    TUT.hideAt = 0
    hintHide()
  end
  if page then return end          -- 打开商店/转盘/老虎机时暂停出地鼠

  if punchAt > 0 and clock >= punchAt then
    punchAt = 0
    setScale('大史莱姆', 1)
  end

  if bonusRing and bonusRing.alive then
    pcall(function()
      bonusRing.localRotationZ = (bonusRing.localRotationZ + 70 * dt) % 360
      local k = 1 + 0.05 * math.sin(clock * 4.4)
      bonusRing.localScaleX = k
      bonusRing.localScaleY = k
    end)
  end

  for i = 1, 9 do
    local h = holes[i]
    if h.state == 'up' and clock >= h.expire then hideMole(i) end
  end

  if BONUS.active then
    if BONUS.boomAt > 0 then
      local left = BONUS.boomAt - clock
      local u = math.max(0, math.min(1, 1 - left / 0.42))
      setScale('大史莱姆', 1 + 2.2 * u)
      local ab = aByte(1 - u)
      if ab ~= boomA then
        boomA = ab
        local big = ui('大史莱姆')
        if big then pcall(function() big.imageColor = Color.FromRGBA(255, 255, 255, ab) end) end
      end
      if clock >= BONUS.boomAt then
        boomA = -1
        endBonus()
      end
      return
    end
    local ts = string.format('%.1fs', math.max(0, BONUS.endAt - clock))
    if ts ~= lastTimer then
      lastTimer = ts
      setText('倒计时', ts)
    end
    if clock >= BONUS.endAt then endBonus() end
    return
  end

  nextSpawn = nextSpawn - dt
  if nextSpawn <= 0 then
    nextSpawn = 0.85 + math.random() * 0.45
    local free = {}
    for i = 1, 9 do
      if holes[i].state == 'idle' then free[#free + 1] = i end
    end
    if #free > 0 then
      showMole(free[math.random(#free)], pickType())
    end
  end

  if S.hits >= BONUS.nextAt then startBonus() end
end

function OnDestroy()
  clearParts()
  clearDecor()
  if bonusRing then
    local ring = bonusRing
    bonusRing = nil
    killPart({ c = ring })
  end
  print('地鼠节拍：主场景已销毁')
end
