-- Voxel-family adapter: both of a side's battlers in the 3D scene.
--
-- Dramatic Shape and its forks (BATTLE_ART_VOXEL_FORK) stand each side
-- in the world as ONE billboard card, textured with a canvas their
-- sideTexture renders.  That makes texture composition the seam: a
-- partner drawn beside the lead inside that canvas stands beside it in
-- the world, no 3D code of our own.  Three wraps: sideTexture composes
-- the pair, hudTexture follows the acting partner, and Stadium.covers
-- (where the mod has one) decides which tier a doubled side rides.
-- Any enabled mod whose exports carry lib.require("OverworldBattle")
-- with the sideTexture/textures/hudTexture trio is adapted, so a new
-- fork needs nothing from us.
--
-- Forks that carry the full STADIUM family (StadiumMon, StadiumPack)
-- get a second tier: the partner stands in the scene as its own 3D
-- model beside the lead's, driven by the same animation requests the
-- lead's model answers to.  A partner whose species has no pack, a
-- substitute, or a transform drops that side back to the composed pair
-- of cards, per side and per frame, which is the mode's own fallback
-- ladder extended by one rung.
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
        local s = St.__doubleBattlesPairState
        if partner and env.alive(partner) then
          -- the models stand only while the partner has one of its own
          -- ready (pair state below); otherwise the side rides the
          -- composed cards, and forks without the Stadium family always
          -- do
          local res = false
          if s and s.covering and s.covering[side] then
            res = St.__doubleBattlesOrigCovers(battle, side) and true
              or false
          end
          if s and s.coversLead then s.coversLead[side] = res end
          return res
        end
        local res = St.__doubleBattlesOrigCovers(battle, side)
        if s and s.coversLead then
          s.coversLead[side] = res and true or false
        end
        return res
      end
      return St.__doubleBattlesOrigCovers(battle, side)
    end
  end

  -- ------- STADIUM: the partner as a second model
  --
  -- The mode keeps ONE StadiumMon per side in a private session; the
  -- partner slots are invisible to it.  So the pair rides the public
  -- surface instead: begin/update/draw/cast are plain functions on the
  -- Stadium module table and are wrapped like everything else here.
  -- Our two partner mons live on the module table too, so a hot reload
  -- re-points the hooks and finds its state where it left it.
  --
  -- The lead model must STAND DOWN while a doubled side rides the
  -- cards, or the model and the composed pair draw on the same cell
  -- (covers only decides whether a billboard is rendered; the model's
  -- own visibility is the session's).  Showing a trainer is the one
  -- thing the mode reads as "no Pokemon here", so those flags are
  -- borrowed around the original update for exactly the sides falling
  -- back, the same shadow-and-restore the HUD hook uses on the slots.

  local function pairState(St)
    local s = St.__doubleBattlesPairState
    if not s then
      s = { mons = {}, covering = {}, coversLead = {}, spacing = {},
            broken = {}, at = {} }
      St.__doubleBattlesPairState = s
    end
    return s
  end

  local function partnerOf(battle, side)
    if side == "enemy" then return battle.enemy2 end
    return battle.player2
  end

  local function dexOf(species)
    if not species then return nil end
    local okG, Game = pcall(require, "src.core.Game")
    local data = okG and Game and Game.data
    local def = data and data.pokemon and data.pokemon[species]
    return def and def.dex or nil
  end

  -- a broken partner model retires to the card tier, once per battle
  local function retirePartner(s, side, err)
    local mon = s.mons[side]
    if mon then pcall(mon.release, mon) end
    s.mons[side] = nil
    s.broken[side] = true
    s.covering[side] = false
    if not s.warned then
      s.warned = true
      pcall(function()
        env.log:warn("stadium partner model failed and was retired: %s",
                     tostring(err))
      end)
    end
  end

  -- mirrors the mode's own onField for a partner slot: the send-out
  -- flags are lead-only, so the grow ramp is the arrival instead
  local function partnerOnField(battle, side, b, mon)
    if not (b and b.sprite) then return false end
    local okH, hidden = pcall(battle.fxHidden, battle, b)
    if okH and hidden then return false end
    local pf = battle.picFx and battle.picFx[b]
    if pf and pf.hidden then return false end
    if side == "player" then
      if battle.safari or battle.demo then return false end
      if battle.phase == "intro" then return false end
    end
    if b.mon and (b.mon.hp or 0) > 0 then return true end
    -- dead but the bar has not emptied: still on its feet, exactly as
    -- the mode holds its own collapse for the drain
    local fts = battle.__dbStadiumFaints
    if fts and fts[b] then return true end
    local okF, sliding = pcall(battle.fxFaintActive, battle, b)
    if okF and sliding then return true end
    -- and the collapse gets to finish once it fires
    return (mon and mon.__dbLinger and mon.state == "faint"
            and not mon:finished()) and true or false
  end

  -- what the battle taps recorded for this partner, played here so the
  -- request lands on the same frame cadence the mode's own hooks use
  local function consumeTaps(battle, side, b, mon, s)
    local atk = battle.__dbStadiumAttack
    if atk and atk.battler == b then
      battle.__dbStadiumAttack = nil
      if mon.rig and s.covering[side] then
        if not (atk.index and mon:attack(atk.index)) then
          mon:request("attack")
        end
      end
    end
    local ent = battle.__dbStadiumEnter
    if ent and ent[b] then
      ent[b] = nil
      if mon.rig and s.covering[side] then mon:request("entrance") end
    end
    local fts = battle.__dbStadiumFaints
    if fts and fts[b] then
      -- a switch or revive drops the owed collapse; otherwise it waits
      -- for the bar the player reads as the moment of death
      if not (b.faintQueued and b.mon and (b.mon.hp or 0) <= 0) then
        fts[b] = nil
      elseif b.shownHP == nil or b.shownHP <= 0 then
        fts[b] = nil
        -- keyed on what covers actually answered: a partner that died
        -- on the model tier falls as a model, one on the card tier
        -- leaves with its card's slide
        if mon.rig and s.coversLead[side] then
          mon:request("faint")
          mon.__dbLinger = true
        end
      end
    end
  end

  -- The engine seams a partner's own performance comes through.  The
  -- lead slots are the mode's business (its own BattleState hooks);
  -- these record what happened to a PARTNER as plain fields on the
  -- battle, and the update hook plays them.  Installed once on the
  -- class, flag-guarded like the mode's own install.
  local function installBattleTaps()
    local ok, BattleState = pcall(require, "src.battle.BattleState")
    if not (ok and type(BattleState) == "table") then return end
    if BattleState.__doubleBattlesStadiumTaps then return end
    BattleState.__doubleBattlesStadiumTaps = true

    local innerMove = BattleState.performMove
    function BattleState:performMove(user, target, moveInst, isCalled)
      if self.__double
         and (user == self.player2 or user == self.enemy2) then
        local okD, def = pcall(self.moveDef, self, moveInst)
        self.__dbStadiumAttack = { battler = user,
                                   index = okD and def and def.index
                                     or nil }
      end
      return innerMove(self, user, target, moveInst, isCalled)
    end

    local innerFaint = BattleState.onFaint
    function BattleState:onFaint(battler)
      if self.__double and battler and not battler.faintQueued
         and (battler == self.player2 or battler == self.enemy2) then
        self.__dbStadiumFaints = self.__dbStadiumFaints or {}
        self.__dbStadiumFaints[battler] = true
      end
      return innerFaint(self, battler)
    end

    local innerGrow = BattleState.startGrowIn
    function BattleState:startGrowIn(battler)
      if self.__double and battler
         and (battler == self.player2 or battler == self.enemy2) then
        self.__dbStadiumEnter = self.__dbStadiumEnter or {}
        self.__dbStadiumEnter[battler] = true
      end
      return innerGrow(self, battler)
    end

    -- a transform swaps a sprite with no word on WHICH slot; on a
    -- doubled side that cannot be attributed, so the side rides the
    -- cards for as long as it holds
    local innerSpecies = BattleState.speciesSprite
    function BattleState:speciesSprite(species, isPlayerSide)
      if self.__double then
        self.__dbStadiumMorph = self.__dbStadiumMorph or {}
        self.__dbStadiumMorph[isPlayerSide and "player" or "enemy"] = true
      end
      return innerSpecies(self, species, isPlayerSide)
    end

    local innerSwitch = BattleState.resolveSwitch
    function BattleState:resolveSwitch(newMon)
      if self.__double and self.__dbStadiumMorph then
        self.__dbStadiumMorph.player = nil
      end
      return innerSwitch(self, newMon)
    end
  end

  local function makeStadiumBeginHook(St)
    return function(arena)
      local ok = St.__doubleBattlesOrigBegin(arena)
      local s = pairState(St)
      for _, mon in pairs(s.mons) do pcall(mon.release, mon) end
      s.mons, s.covering, s.coversLead = {}, {}, {}
      s.spacing, s.broken, s.at = {}, {}, {}
      s.warned = false
      s.arena = ok and arena or nil
      s.groundY = 0
      s.forBattle = nil
      return ok
    end
  end

  local function makeStadiumFinishHook(St)
    return function(...)
      local s = St.__doubleBattlesPairState
      if s then
        for _, mon in pairs(s.mons) do pcall(mon.release, mon) end
        s.mons, s.covering, s.coversLead, s.arena = {}, {}, {}, nil
        s.forBattle = nil
      end
      return St.__doubleBattlesOrigFinish(...)
    end
  end

  local function makeStadiumUpdateHook(St, Mon, Pack, Ov)
    return function(dt, battle, groundY)
      local orig = St.__doubleBattlesOrigUpdate
      local s = St.__doubleBattlesPairState
      if not (s and battle and battle.__double and St.active()) then
        if s then s.covering = {} end
        return orig(dt, battle, groundY)
      end
      -- the mode's begin can run before this adapter is wired (it is
      -- installed off the battle-started event, the stage is picked at
      -- the push), so the pair state is keyed on the battle itself and
      -- the arena is fetched live off the mode's own public getter
      if s.forBattle ~= battle then
        for _, mon in pairs(s.mons) do pcall(mon.release, mon) end
        s.mons, s.covering, s.coversLead = {}, {}, {}
        s.spacing, s.broken, s.at = {}, {}, {}
        s.warned = false
        s.tierLogged = nil
        s.forBattle = battle
      end
      if not s.arena and type(Ov.arena) == "function" then
        local okA, arena = pcall(Ov.arena)
        if okA and type(arena) == "table" then s.arena = arena end
      end
      s.groundY = groundY or s.groundY or 0

      -- which tier each side rides this frame, decided BEFORE the
      -- original runs so the borrow can hide the lead's model in the
      -- same update that needs it hidden
      local borrow = {}
      local why = {}
      for _, side in ipairs({ "enemy", "player" }) do
        local b = partnerOf(battle, side)
        local mon = s.mons[side]
        -- a different battler in the slot: reset, exactly as the mode
        -- notices its own replacements
        if s.at[side] ~= b then
          s.at[side] = b
          s.broken[side] = nil
          if mon then
            mon.__dbLinger = nil
            if mon.rig and mon.state == "faint" then
              pcall(mon.play, mon, "idle")
            end
          end
        end
        local live = (b and env.alive(b)) and true or false
        if live and not s.broken[side] and not mon then
          local okN, made = pcall(Mon.new, side)
          mon = (okN and type(made) == "table") and made or nil
          s.mons[side] = mon
        end
        local ready = false
        if mon then
          local dex = (b and b.mon) and dexOf(b.mon.species) or nil
          local okS, errS = pcall(mon.setSpecies, mon, dex)
          if not okS then
            retirePartner(s, side, errS)
            mon = nil
          else
            ready = mon.rig ~= nil
            if mon.species then pcall(Pack.keep, mon.species) end
          end
        end
        local morph = battle.__dbStadiumMorph
          and battle.__dbStadiumMorph[side]
        local lead = side == "enemy" and battle.enemy or battle.player
        local subbed = (b and b.substituteHP)
          or (lead and lead.substituteHP)
        -- no arena means nowhere to stand a partner model, so the side
        -- rides the cards (and the borrow below hides the lead's model)
        s.covering[side] = (live and ready and s.arena ~= nil
                            and not morph and not subbed
                            and not s.broken[side]) and true or false
        why[side] = s.covering[side] and "models"
          or not live and "single"
          or s.broken[side] and "broken"
          or morph and "transform"
          or subbed and "substitute"
          or not ready and "no-pack"
          or not s.arena and "no-arena"
          or "cards"
        local trainerNow
        if side == "enemy" then
          trainerNow = battle.showEnemyTrainer and battle.trainerPic
        else
          trainerNow = battle.showPlayerBack and battle.playerBackPic
        end
        borrow[side] = live and not s.covering[side] and not trainerNow
      end
      -- one line whenever a side changes tier, so a play test that
      -- looks wrong can be read off the console instead of guessed at
      -- from a screenshot
      local tier = why.enemy .. "/" .. why.player
      if s.tierLogged ~= tier then
        s.tierLogged = tier
        pcall(function()
          env.log:info("stadium pair: enemy=%s player=%s", why.enemy,
                       why.player)
        end)
      end

      local savedSE, savedTP, savedSP, savedBP
      if borrow.enemy then
        savedSE, savedTP = battle.showEnemyTrainer, battle.trainerPic
        battle.showEnemyTrainer = true
        battle.trainerPic = battle.trainerPic or true
      end
      if borrow.player then
        savedSP, savedBP = battle.showPlayerBack, battle.playerBackPic
        battle.showPlayerBack = true
        battle.playerBackPic = battle.playerBackPic or true
      end
      local okU, errU = pcall(orig, dt, battle, groundY)
      if borrow.enemy then
        battle.showEnemyTrainer, battle.trainerPic = savedSE, savedTP
      end
      if borrow.player then
        battle.showPlayerBack, battle.playerBackPic = savedSP, savedBP
      end
      if not okU then error(errU) end

      -- and the partners themselves: requests, visibility, pose
      local arena = s.arena
      for _, side in ipairs({ "enemy", "player" }) do
        local mon = s.mons[side]
        local b = partnerOf(battle, side)
        if mon then
          mon.model_matrix = nil
          pcall(consumeTaps, battle, side, b, mon, s)
          -- keyed on coversLead, the answer covers gave for this side:
          -- it stays true through a partner's death on the model tier
          -- (the standing wait, the fall, the linger) and goes false
          -- the frame the side drops to cards
          local visible = false
          if mon.rig and s.coversLead[side] then
            visible = partnerOnField(battle, side, b, mon)
              and not (b and b.substituteHP)
          end
          mon.visible = visible and true or false
          if mon.rig then
            local okG, gsc = pcall(battle.growInScale, battle, b)
            mon.scale = (okG and type(gsc) == "number" and gsc) or 1
            local okT, errT = pcall(mon.update, mon, dt or 0)
            if not okT then retirePartner(s, side, errT) end
          end
          local cell = arena and arena[side]
          local other = arena
            and arena[side == "player" and "enemy" or "player"]
          if mon and mon.rig and mon.visible and cell and other then
            local okB, errB = pcall(function()
              -- beside the lead's cell, off the axis between the two
              -- cells, so the pairs line up across the field the way
              -- the flat layout's columns do
              local axX = (arena.player and arena.enemy)
                and (arena.player[1] - arena.enemy[1]) or 0
              local axZ = (arena.player and arena.enemy)
                and (arena.player[2] - arena.enemy[2]) or 0
              local len = math.sqrt(axX * axX + axZ * axZ)
              local px, pz = 1, 0
              if len > 0 then px, pz = -axZ / len, axX / len end
              local leadR = 0
              local okF, fp = pcall(St.__doubleBattlesOrigFootprint
                                    or function() end, side)
              if okF and type(fp) == "number" then leadR = fp end
              local selfR = mon:worldRadius() or 0
              local d = math.max(16, leadR + selfR + 6)
              s.spacing[side] = d
              local x = cell[1] + px * d
              local z = cell[2] + pz * d
              mon.model_matrix = mon:matrix(x, s.groundY, z,
                                            other[1] - x, other[2] - z)
              mon:build()
            end)
            if not okB then retirePartner(s, side, errB) end
          end
        end
      end
    end
  end

  -- drawn only while the LEAD's model stands too (coversLead is what
  -- covers actually answered): a side whose lead fell back to its card
  -- must not keep a floating partner model beside the cards
  local function partnerDrawable(s, side)
    local mon = s.mons[side]
    return (mon and mon.rig and mon.visible and mon.model_matrix
            and s.coversLead[side]) and mon or nil
  end

  local function makeStadiumDrawHook(St)
    return function(pull)
      St.__doubleBattlesOrigDraw(pull)
      local s = St.__doubleBattlesPairState
      if not s then return end
      for _, side in ipairs({ "enemy", "player" }) do
        local mon = partnerDrawable(s, side)
        if mon then
          local ok, err = pcall(function()
            mon.rig:draw(mon.model_matrix, pull)
          end)
          if not ok then retirePartner(s, side, err) end
        end
      end
    end
  end

  local function makeStadiumCastHook(St)
    return function(shadowMap)
      St.__doubleBattlesOrigCast(shadowMap)
      local s = St.__doubleBattlesPairState
      if not s then return end
      for _, side in ipairs({ "enemy", "player" }) do
        local mon = partnerDrawable(s, side)
        if mon then
          local ok, err = pcall(function()
            mon.rig:caster(shadowMap, mon.model_matrix)
          end)
          if not ok then retirePartner(s, side, err) end
        end
      end
    end
  end

  -- STADIUM B sizes each disc to this, live, so a covered pair widens
  -- its platform with no stage code of our own
  local function makeStadiumFootprintHook(St)
    return function(side)
      local base = St.__doubleBattlesOrigFootprint(side)
      local s = St.__doubleBattlesPairState
      local mon = s and s.mons[side]
      if s and s.covering[side] and mon and mon.rig then
        local okR, r = pcall(mon.worldRadius, mon)
        local ext = (s.spacing[side] or 0) + ((okR and r) or 0)
        if ext > (base or 0) then return ext end
      end
      return base
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
          local st, pair
          local okS, s = pcall(V.require, "Stadium")
          if okS and type(s) == "table"
             and type(s.covers) == "function" then
            st = s
          end
          -- the full Stadium family means the partner can stand as a
          -- model of its own; probed by surface, never by mod name
          if st and type(st.begin) == "function"
             and type(st.update) == "function"
             and type(st.draw) == "function"
             and type(st.active) == "function" then
            local okM, m = pcall(V.require, "StadiumMon")
            local okP, p = pcall(V.require, "StadiumPack")
            if okM and type(m) == "table"
               and type(m.new) == "function"
               and okP and type(p) == "table"
               and type(p.keep) == "function" then
              pair = { Mon = m, Pack = p }
            end
          end
          found[#found + 1] = { ov = ov, st = st, pair = pair }
        end
      end
    end
    return found
  end

  -- the originals are stored ONCE on the module tables; a hot reload
  -- re-points the hook fields instead of stacking another wrap (the
  -- OverworldController.pushBattle pattern in main.lua)
  -- one wrap per Stadium function, original stored once, hook field
  -- re-pointed per generation (the sideTexture pattern, made generic
  -- because the stadium surface is six functions rather than two)
  local function wrapStadiumFn(st, name, key)
    if type(st[name]) ~= "function" then return false end
    local orig = "__doubleBattlesOrig" .. key
    local hookKey = "__doubleBattlesHook" .. key
    if not st[orig] then
      st[orig] = st[name]
      st[name] = function(...)
        local hook = st[hookKey]
        if hook then return hook(...) end
        return st[orig](...)
      end
    end
    return true
  end

  local function wirePair(st, pair, ov)
    installBattleTaps()
    pairState(st)
    if wrapStadiumFn(st, "begin", "Begin") then
      st.__doubleBattlesHookBegin = makeStadiumBeginHook(st)
    end
    if wrapStadiumFn(st, "finish", "Finish") then
      st.__doubleBattlesHookFinish = makeStadiumFinishHook(st)
    end
    if wrapStadiumFn(st, "update", "Update") then
      st.__doubleBattlesHookUpdate =
        makeStadiumUpdateHook(st, pair.Mon, pair.Pack, ov)
    end
    if wrapStadiumFn(st, "draw", "Draw") then
      st.__doubleBattlesHookDraw = makeStadiumDrawHook(st)
    end
    if wrapStadiumFn(st, "cast", "Cast") then
      st.__doubleBattlesHookCast = makeStadiumCastHook(st)
    end
    if wrapStadiumFn(st, "footprint", "Footprint") then
      st.__doubleBattlesHookFootprint = makeStadiumFootprintHook(st)
    end
  end

  local function wire(ov, st, pair)
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
      -- a pair that fails to wire must say so: silently swallowed, a
      -- doubles battle on the model rungs draws the cards in front of
      -- the standing models and nothing anywhere explains why
      if pair then
        local okW, errW = pcall(wirePair, st, pair, ov)
        if okW then
          pcall(function()
            env.log:info("stadium pair tier wired")
          end)
        else
          pcall(function()
            env.log:warn("stadium pair tier failed to wire; doubles "
              .. "stay on the composed cards: %s", tostring(errW))
          end)
        end
      end
    end
    wired[ov] = true
  end

  function adapter.tryInstall()
    local found = locateAll()
    for _, f in ipairs(found) do
      if not wired[f.ov] then wire(f.ov, f.st, f.pair) end
    end
    if #found > 0 then installed = true end
    return installed
  end

  function adapter.installed()
    return installed
  end

  return adapter
end
