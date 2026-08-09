-- Voxel-family adapter: both of a side's battlers in the 3D scene.
--
-- Dramatic Shape and its forks (BATTLE_ART_VOXEL_FORK) stand each side
-- in the world as ONE billboard card, textured with a canvas their
-- sideTexture renders.  That makes texture composition the seam: a
-- partner drawn beside the lead inside that canvas stands beside it in
-- the world, no 3D code of our own.  Three wraps: sideTexture composes
-- the pair, hudTexture follows the acting partner, and Stadium.covers
-- (where the mod has one) drops a doubled side back to flat cards.
-- Any enabled mod whose exports carry lib.require("OverworldBattle")
-- with the sideTexture/textures/hudTexture trio is adapted, so a new
-- fork needs nothing from us.
return function(env)
  local adapter = {}

  local installed = false
  local wired = {}       -- module tables already carrying our hooks

  -- our compose canvases, one per side, grown but never shrunk so
  -- per-frame art changes (grow-ins, animation frames) cannot thrash
  local canvases = {}
  -- compose failures warn once per battle, then degrade to vanilla
  local warned = setmetatable({}, { __mode = "k" })

  local function canvasFor(side, w, h)
    local c = canvases[side]
    if c and c.w >= w and c.h >= h then return c.canvas, c.w, c.h end
    local ok, made = pcall(love.graphics.newCanvas, w, h,
                           { dpiscale = 1 })
    if not (ok and made) then return nil end
    pcall(made.setFilter, made, "nearest", "nearest")
    canvases[side] = { canvas = made, w = w, h = h }
    return made, w, h
  end

  local function sideBattlers(battle, side)
    if side == "enemy" then return battle.enemy, battle.enemy2 end
    return battle.player, battle.player2
  end

  -- mirrors main.lua's showable, plus the vanilla lead-slot hide flags
  -- (leadSlot: the battler sitting in battle.enemy / battle.player)
  local function showable(battle, b, side, leadSlot)
    if not (b and b.mon and b.sprite) then return false end
    local okH, hidden = pcall(battle.fxHidden, battle, b)
    if okH and hidden then return false end
    if leadSlot then
      if side == "enemy" then
        if battle.enemyHidden or battle.enemySendingOut then return false end
      else
        if battle.sendingOut or battle.safari or battle.demo then
          return false
        end
      end
    end
    if b.mon.hp > 0 then return true end
    local okF, active = pcall(battle.fxFaintActive, battle, b)
    return okF and active or false
  end

  local function measure(battle, b)
    local okI, img = pcall(battle.picImage, battle, b.sprite)
    if not (okI and img) then return nil end
    local s = 1
    local okG, g = pcall(battle.growInScale, battle, b)
    if okG and type(g) == "number" then
      if g == 0 then return nil end
      s = s * g
    end
    return { b = b, s = s,
             w = img:getWidth() * s, h = img:getHeight() * s }
  end

  -- the blinking aim frame, around whichever battler the prompt aims at
  local function drawCue(battle, side, drawn)
    local aimed, color
    if side == "enemy" and battle.phase == "db_target" then
      aimed = battle.__dbAimBattler or battle.enemy
      color = { 1, 0.2, 0.2, 1 }
    elseif side == "player" and battle.phase == "db_switch_target" then
      aimed = battle.__dbSwitchAim or battle.player
      color = { 0.2, 1, 0.4, 1 }
    end
    local r = aimed and drawn[aimed]
    if not r then return end
    if math.floor(love.timer.getTime() * 4) % 2 ~= 0 then return end
    love.graphics.setColor(color[1], color[2], color[3], color[4])
    love.graphics.rectangle("line", r.x - 2, r.y - 2, r.w + 4, r.h + 4)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- ------- the three hooks, made per wired module set

  local function makeSideTextureHook(Ov, St)
    return function(battle, side)
      local orig = Ov.__doubleBattlesOrigSideTexture
      if not (battle and battle.__double) then return orig(battle, side) end
      -- the intro trainer frames belong to the original whole: it hangs
      -- them from the trainer pic's own slot (trainer = true results)
      if side == "enemy" and battle.showEnemyTrainer then
        return orig(battle, side)
      end
      if side == "player" and battle.showPlayerBack
         and battle.playerBackPic then
        return orig(battle, side)
      end
      local lead, partner = sideBattlers(battle, side)
      -- collapsed back to the vanilla 1v1: the lead in its vanilla spot
      -- and nobody beside it is exactly the scene the original renders
      if not partner and (not lead or (lead.dbAnchor or 1) == 1) then
        return orig(battle, side)
      end

      -- the anchor-1 battler hangs on the cell column; its partner
      -- stands beside it.  Measured up front so oversized art (the
      -- Battle Art fork's animated frames) gets a canvas that fits.
      local a1, a2 = lead, partner
      if a1 and (a1.dbAnchor or 1) == 2 then a1, a2 = a2, a1 end
      local m1 = a1 and showable(battle, a1, side, a1 == lead)
        and measure(battle, a1) or nil
      local m2 = a2 and showable(battle, a2, side, a2 == lead)
        and measure(battle, a2) or nil
      if not (m1 or m2) then return nil end

      -- classic-sized art keeps the proven fixed layout (anchor 1 on
      -- column 80, anchor 2 on 36, feet on 96); anything bigger packs
      -- side by side on a canvas grown to fit
      local wide = (m1 and (m1.w > 72 or m1.h > 96))
        or (m2 and (m2.w > 72 or m2.h > 96))
      local W, H, ay = 160, 144, 96
      if wide then
        local packW = 12 + (m1 and m1.w or 0) + (m2 and m2.w or 0)
          + ((m1 and m2) and 8 or 0)
        W = math.max(160, math.ceil(packW))
        H = math.max(144, math.ceil(math.max(m1 and m1.h or 0,
                                             m2 and m2.h or 0)) + 6)
        ay = H - 4
      end
      local canvas, cw, chh = canvasFor(side, W, H)
      if not canvas then return orig(battle, side) end
      W, H = cw, chh
      if wide then ay = H - 4 end

      local centers = {}
      if wide then
        local used = 12 + (m1 and m1.w or 0) + (m2 and m2.w or 0)
          + ((m1 and m2) and 8 or 0)
        local x = math.floor((W - used) / 2) + 6
        if m2 then
          centers[m2.b] = x + m2.w / 2
          x = x + m2.w + 8
        end
        if m1 then centers[m1.b] = x + m1.w / 2 end
      else
        if m1 then centers[m1.b] = 80 end
        if m2 then centers[m2.b] = 36 end
      end

      local g = love.graphics
      local prevCanvas = g.getCanvas()
      local prevBlend, prevAlpha = g.getBlendMode()
      local drawn = {}
      local ok, err = pcall(function()
        g.setCanvas(canvas)
        g.clear(0, 0, 0, 0)
        g.setBlendMode("alpha")
        g.setColor(1, 1, 1, 1)
        local order = {}
        if m2 then order[#order + 1] = m2 end
        if m1 then order[#order + 1] = m1 end
        for _, m in ipairs(order) do
          local dx = centers[m.b] - m.w / 2
          local dy = ay - m.h
          pcall(battle.drawBattlerPic, battle, m.b, dx, dy, m.s)
          drawn[m.b] = { x = dx, y = dy, w = m.w, h = m.h }
        end
        drawCue(battle, side, drawn)
      end)
      if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
      g.setBlendMode(prevBlend or "alpha", prevAlpha)
      if not ok then
        -- a compose bug degrades to the old single-mon scene, not a
        -- black card
        if not warned[battle] then
          warned[battle] = true
          pcall(function()
            env.log:warn("3d pair compose failed: %s", tostring(err))
          end)
        end
        return orig(battle, side)
      end
      -- ax is the CELL column: anchor 1's center, or where it would
      -- stand.  In the fixed layout that is always column 80, which is
      -- what keeps a lone anchor-2 survivor at the partner spot.
      local ax
      if wide then
        ax = (m1 and centers[m1.b])
          or (m2 and centers[m2.b] + m2.w / 2 + 36) or W / 2
      else
        ax = 80
      end
      return { canvas = canvas, ax = ax, ay = ay }
    end
  end

  local function makeHudTextureHook(Ov)
    return function(battle, slide, ...)
      local orig = Ov.__doubleBattlesOrigHudTexture
      if not (battle and battle.__double) then
        return orig(battle, slide, ...)
      end
      -- hudTexture renders from the update tick, outside the
      -- draw-scoped borrow in main.lua, so the acting partner is
      -- swapped in here
      local focus = battle.__dbFocus
      local swapE = focus ~= nil and focus == battle.enemy2
        and env.alive(focus)
      local swapP = not swapE and focus ~= nil and focus == battle.player2
        and env.alive(focus)
      if not (swapE or swapP) then return orig(battle, slide, ...) end
      local shown = focus.shownHP or focus.mon.hp
      local diff = focus.mon.hp - shown
      if diff ~= 0 then
        focus.shownHP = shown + (diff > 0 and math.min(diff, 2)
                                 or math.max(diff, -2))
      end
      focus.shownStatus = focus.mon.status
      if swapE then
        battle.enemy, battle.enemy2 = battle.enemy2, battle.enemy
      else
        battle.player, battle.player2 = battle.player2, battle.player
      end
      local ok, result = pcall(orig, battle, slide, ...)
      if swapE then
        battle.enemy, battle.enemy2 = battle.enemy2, battle.enemy
      else
        battle.player, battle.player2 = battle.player2, battle.player
      end
      if not ok then error(result) end
      return result
    end
  end

  local function makeCoversHook(St)
    return function(battle, side)
      if battle and battle.__double then
        local partner
        if side == "enemy" then
          partner = battle.enemy2
        elseif side == "player" then
          partner = battle.player2
        end
        -- a doubled side rides the flat cards; the models resume when
        -- the side collapses back to one
        if partner and env.alive(partner) then return false end
      end
      return St.__doubleBattlesOrigCovers(battle, side)
    end
  end

  -- ------- locating and wrapping

  -- every enabled mod whose exports expose the voxel battle surface;
  -- Stadium is optional (the Battle Art fork has none)
  local function locateAll()
    local okG, Game = pcall(require, "src.core.Game")
    if not (okG and type(Game) == "table") then return {} end
    local exports = Game.mods and Game.mods.exports
    if type(exports) ~= "table" then return {} end
    local found = {}
    for _, entry in pairs(exports) do
      local V = type(entry) == "table" and entry.lib
      if type(V) == "table" and type(V.require) == "function" then
        local okO, ov = pcall(V.require, "OverworldBattle")
        if okO and type(ov) == "table"
           and type(ov.sideTexture) == "function"
           and type(ov.hudTexture) == "function" then
          local st
          local okS, s = pcall(V.require, "Stadium")
          if okS and type(s) == "table"
             and type(s.covers) == "function" then
            st = s
          end
          found[#found + 1] = { ov = ov, st = st }
        end
      end
    end
    return found
  end

  -- the originals are stored ONCE on the module tables; a hot reload
  -- re-points the hook fields instead of stacking another wrap (the
  -- OverworldController.pushBattle pattern in main.lua)
  local function wire(ov, st)
    if not ov.__doubleBattlesOrigSideTexture then
      ov.__doubleBattlesOrigSideTexture = ov.sideTexture
      ov.sideTexture = function(battle, side)
        local hook = ov.__doubleBattlesSideTextureHook
        if hook then return hook(battle, side) end
        return ov.__doubleBattlesOrigSideTexture(battle, side)
      end
    end
    if not ov.__doubleBattlesOrigHudTexture then
      ov.__doubleBattlesOrigHudTexture = ov.hudTexture
      ov.hudTexture = function(battle, slide, ...)
        local hook = ov.__doubleBattlesHudTextureHook
        if hook then return hook(battle, slide, ...) end
        return ov.__doubleBattlesOrigHudTexture(battle, slide, ...)
      end
    end
    ov.__doubleBattlesSideTextureHook = makeSideTextureHook(ov, st)
    ov.__doubleBattlesHudTextureHook = makeHudTextureHook(ov)
    if st then
      if not st.__doubleBattlesOrigCovers then
        st.__doubleBattlesOrigCovers = st.covers
        st.covers = function(battle, side)
          local hook = st.__doubleBattlesCoversHook
          if hook then return hook(battle, side) end
          return st.__doubleBattlesOrigCovers(battle, side)
        end
      end
      st.__doubleBattlesCoversHook = makeCoversHook(st)
    end
    wired[ov] = true
  end

  function adapter.tryInstall()
    local found = locateAll()
    for _, f in ipairs(found) do
      if not wired[f.ov] then wire(f.ov, f.st) end
    end
    if #found > 0 then installed = true end
    return installed
  end

  function adapter.installed()
    return installed
  end

  return adapter
end
