-- Dramatic Shape adapter: both of a side's battlers in the 3D scene.
--
-- The voxel mod stands each side in the world as ONE billboard card,
-- textured with a whole 160x144 canvas its sideTexture renders.  That
-- makes texture composition the seam: a partner drawn beside the lead
-- inside that canvas stands beside it in the world, no 3D code of our
-- own.  Three wraps: sideTexture composes the pair, hudTexture follows
-- the acting partner, Stadium.covers drops a doubled side back to flat
-- cards (its models can only pose one mon a side).
return function(env)
  local adapter = {}

  local installed = false
  local Ov, St

  -- our compose canvases, one per side, lazy and cached
  local canvases = {}
  -- compose failures warn once per battle, then degrade to vanilla
  local warned = setmetatable({}, { __mode = "k" })

  local function canvasFor(side)
    local c = canvases[side]
    if c then return c end
    local ok, made = pcall(love.graphics.newCanvas, 160, 144,
                           { dpiscale = 1 })
    if not (ok and made) then return nil end
    pcall(made.setFilter, made, "nearest", "nearest")
    canvases[side] = made
    return made
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

  -- one battler onto the canvas; returns its drawn rect for the cue
  local function drawOne(battle, b, side, leadSlot)
    local rect
    pcall(function()
      if not showable(battle, b, side, leadSlot) then return end
      local img = battle:picImage(b.sprite)
      if not img then return end
      local s = 1
      local g = battle:growInScale(b)
      if type(g) == "number" then
        if g == 0 then return end
        s = s * g
      end
      local xc = ((b.dbAnchor or 1) == 2) and (80 - 44) or 80
      local w, h = img:getWidth() * s, img:getHeight() * s
      local dx, dy = xc - w / 2, 96 - h
      battle:drawBattlerPic(b, dx, dy, s)
      rect = { x = dx, y = dy, w = w, h = h }
    end)
    return rect
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

  -- ------- the three hooks (re-pointed on reload, never stacked)

  local function sideTextureHook(battle, side)
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

    local canvas = canvasFor(side)
    if not canvas then return orig(battle, side) end

    local g = love.graphics
    local prevCanvas = g.getCanvas()
    local prevBlend, prevAlpha = g.getBlendMode()
    local ok, err = pcall(function()
      g.setCanvas(canvas)
      g.clear(0, 0, 0, 0)
      g.setBlendMode("alpha")
      g.setColor(1, 1, 1, 1)
      local drawn = {}
      if lead then drawn[lead] = drawOne(battle, lead, side, true) end
      if partner then
        drawn[partner] = drawOne(battle, partner, side, false)
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
    return { canvas = canvas, ax = 80, ay = 96 }
  end

  local function hudTextureHook(battle, slide)
    local orig = Ov.__doubleBattlesOrigHudTexture
    if not (battle and battle.__double) then return orig(battle, slide) end
    -- hudTexture renders from the update tick, outside the draw-scoped
    -- borrow in main.lua, so the acting partner is swapped in here
    local focus = battle.__dbFocus
    local swapE = focus ~= nil and focus == battle.enemy2
      and env.alive(focus)
    local swapP = not swapE and focus ~= nil and focus == battle.player2
      and env.alive(focus)
    if not (swapE or swapP) then return orig(battle, slide) end
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
    local ok, result = pcall(orig, battle, slide)
    if swapE then
      battle.enemy, battle.enemy2 = battle.enemy2, battle.enemy
    else
      battle.player, battle.player2 = battle.player2, battle.player
    end
    if not ok then error(result) end
    return result
  end

  local function coversHook(battle, side)
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

  -- ------- locating and wrapping

  local function locate()
    local okG, Game = pcall(require, "src.core.Game")
    if not (okG and type(Game) == "table") then return nil end
    local exports = Game.mods and Game.mods.exports
    local V = exports and exports.DRAMATIC_SHAPE
      and exports.DRAMATIC_SHAPE.lib
    if not (V and type(V.require) == "function") then return nil end
    local okO, ov = pcall(V.require, "OverworldBattle")
    local okS, st = pcall(V.require, "Stadium")
    if not (okO and type(ov) == "table" and okS and type(st) == "table") then
      return nil
    end
    if type(ov.sideTexture) ~= "function"
       or type(ov.hudTexture) ~= "function"
       or type(st.covers) ~= "function" then
      return nil
    end
    return ov, st
  end

  -- the originals are stored ONCE on the module tables; a hot reload
  -- re-points the hook fields instead of stacking another wrap (the
  -- OverworldController.pushBattle pattern in main.lua)
  function adapter.tryInstall()
    if installed then return true end
    local ov, st = locate()
    if not ov then return false end
    Ov, St = ov, st

    if not Ov.__doubleBattlesOrigSideTexture then
      Ov.__doubleBattlesOrigSideTexture = Ov.sideTexture
      Ov.sideTexture = function(battle, side)
        local hook = Ov.__doubleBattlesSideTextureHook
        if hook then return hook(battle, side) end
        return Ov.__doubleBattlesOrigSideTexture(battle, side)
      end
    end
    if not Ov.__doubleBattlesOrigHudTexture then
      Ov.__doubleBattlesOrigHudTexture = Ov.hudTexture
      Ov.hudTexture = function(battle, slide)
        local hook = Ov.__doubleBattlesHudTextureHook
        if hook then return hook(battle, slide) end
        return Ov.__doubleBattlesOrigHudTexture(battle, slide)
      end
    end
    if not St.__doubleBattlesOrigCovers then
      St.__doubleBattlesOrigCovers = St.covers
      St.covers = function(battle, side)
        local hook = St.__doubleBattlesCoversHook
        if hook then return hook(battle, side) end
        return St.__doubleBattlesOrigCovers(battle, side)
      end
    end

    Ov.__doubleBattlesSideTextureHook = sideTextureHook
    Ov.__doubleBattlesHudTextureHook = hudTextureHook
    St.__doubleBattlesCoversHook = coversHook

    installed = true
    return true
  end

  function adapter.installed()
    return installed
  end

  return adapter
end
