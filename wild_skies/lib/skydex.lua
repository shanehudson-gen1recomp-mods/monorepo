-- Sky Dex: a browsable dex of every species' sky art.  One page per
-- species, one row per SKY ART option, the AUTO row on top showing
-- exactly what the sky composes when the option is AUTO.  Rows resolve
-- through the same Sky.mountSprite ladder the flyers use (borrowed
-- sprite-mod art, walker sheets, battle portraits, icon strips), so the
-- dex can never drift from what the sky actually draws, on Gen 1 or
-- Gold alike.  Species come from the live dataset, never a hand list.
--
-- chunk args: the mod namespace and the shared sky library
local mod, Sky = ...

local SkyDex = {}

-- the same choices, in the same order, as the SKY ART option; AUTO
-- first because it is what the sky flies by default
SkyDex.LANES = {
  { key = "auto", label = "AUTO" },
  { key = "portrait", label = "PORTRAIT" },
  { key = "classic", label = "CLASSIC" },
}

-- a species belongs in the Sky Dex when the sky family can put it in
-- the air: FLYING-typed (a wild_skies flyer) or a FLY learner (a
-- free_fly mount, the same tmhm list the machine-teach path checks).
-- Derived from the record, never a hand list, so dataset overhauls
-- extend the dex on their own.
local function skyworthy(def)
  for _, t in ipairs(def.types or {}) do
    if t == "FLYING" then return true end
  end
  for _, m in ipairs(def.tmhm or {}) do
    if m == "FLY" then return true end
  end
  return false
end

-- every flight-capable species the dataset carries, in dex order.  On
-- Gold the data facade serves the merged species table, so Johto (and
-- Crystal 251's extensions) appear without any list here knowing about
-- them.
function SkyDex.speciesList(data)
  local list = {}
  for id, def in pairs((data and data.pokemon) or {}) do
    if type(def) == "table" and type(def.dex) == "number"
        and skyworthy(def) then
      list[#list + 1] = { species = id, dex = def.dex,
                          name = tostring(def.name or id) }
    end
  end
  table.sort(list, function(a, b)
    if a.dex ~= b.dex then return a.dex < b.dex end
    return a.species < b.species
  end)
  return list
end

-- what a resolved renderer actually is, read off its def the way the
-- draw path does: a battle portrait, an icon strip, a sprite-source
-- mod's own-geometry sheet, or a stock walker sheet
function SkyDex.laneTag(renderer)
  local def = renderer and renderer.def
  if not def then return "----" end
  if def.spriteType == "POKEMON_PIC" then return "PIC" end
  if def.icon then return "ICON" end
  if Sky.trueSized(renderer) then return "TRUE SIZE" end
  return "SHEET"
end

-- the three art rows for one species.  Distinct cache seeds per lane:
-- mountSprite caches by (seed, sprite id), and the same species asked
-- under different skyArt answers with different art, so the dex must
-- never share a cache line with the live sky or across its own lanes.
function SkyDex.lanes(data, species)
  local lanes = {}
  for _, lane in ipairs(SkyDex.LANES) do
    local ok, renderer, class = pcall(Sky.mountSprite, data, species,
      "skydex_" .. lane.key, { skyArt = lane.key })
    if not ok then renderer, class = nil, nil end
    lanes[#lanes + 1] = { key = lane.key, label = lane.label,
      renderer = renderer or nil, class = class,
      tag = SkyDex.laneTag(ok and renderer or nil),
      source = ok and renderer and (renderer.skySource or "game") or nil }
  end
  return lanes
end

-- hold-to-scroll in SECONDS, not frames: state updates ride the frame
-- rate (120 with the default cap), so a frame-counted repeat scrolled
-- twice as fast as the 60Hz ListMenu cadence it copied
local REPEAT_DELAY = 0.28
local REPEAT_RATE = 0.09

-- feet lines for the three art rows; portraits stand 20px over their
-- feet, so each row keeps 32px of air
local LANE_Y = { 60, 92, 124 }

function SkyDex.open(game)
  local list = SkyDex.speciesList(game and game.data)
  if #list == 0 then
    mod.log:warn("sky dex: no species with dex numbers in the dataset")
    return nil
  end
  local Font  -- required on first draw, so headless opens stay clean

  local screen = { isOpaque = true, screenId = "WildSkiesSkyDex",
                   index = 1, t = 0,
                   holdDir = nil, holdTime = 0, repeatTime = 0,
                   laneCache = {} }
  screen.list = list
  screen.data = game.data
  -- the modern-UI surface reads renderers through here, never the model
  SkyDex._active = screen

  local function lanesFor(entry)
    local cached = screen.laneCache[entry.species]
    if cached == nil then
      cached = SkyDex.lanes(game.data, entry.species)
      screen.laneCache[entry.species] = cached
    end
    return cached
  end

  local function move(delta)
    screen.index = ((screen.index - 1 + delta) % #list) + 1
  end

  screen.lanesFor = function(_, entry) return lanesFor(entry) end
  function screen:jumpTo(index)
    index = math.floor(tonumber(index) or self.index)
    if index >= 1 and index <= #list then self.index = index end
  end
  function screen:back()
    if not game.stack.top or game.stack:top() == self then
      game.stack:pop()
    end
    return true
  end

  function screen:update(dt)
    self.t = self.t + (dt or 0)
    local input = game.input
    if not input then return end
    if input:wasPressed("b") then
      game.stack:pop()
      return
    end
    local pressed
    if input:wasPressed("up") then pressed = "up"
    elseif input:wasPressed("down") then pressed = "down"
    elseif input:wasPressed("left") then pressed = "left"
    elseif input:wasPressed("right") then pressed = "right" end
    if pressed then
      move((pressed == "up" and -1) or (pressed == "down" and 1)
        or (pressed == "left" and -10) or 10)
      self.holdDir, self.holdTime, self.repeatTime = pressed, 0, 0
      return
    end
    local dir = self.holdDir
    if dir and input:isDown(dir) then
      self.holdTime = (self.holdTime or 0) + (dt or 0)
      if self.holdTime >= REPEAT_DELAY then
        self.repeatTime = (self.repeatTime or 0) + (dt or 0)
        if self.repeatTime >= REPEAT_RATE then
          self.repeatTime = self.repeatTime - REPEAT_RATE
          move((dir == "up" and -1) or (dir == "down" and 1)
            or (dir == "left" and -10) or 10)
        end
      end
    else
      self.holdDir, self.holdTime, self.repeatTime = nil, 0, 0
    end
  end

  function screen:draw()
    Font = Font or mod.ui.Font
    local G = love.graphics
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 0, 0, 160, 144)
    G.setColor(0, 0, 0, 1)
    Font.draw("SKY DEX", 8, 4)
    local entry = list[self.index]
    local no = ("#%03d"):format(entry.dex)
    Font.draw(no, 160 - 8 - Font.width(no), 4)
    Font.draw(entry.name, 8, 20)
    local inUse = mod.options:get("skyart") or "auto"
    local flap = math.floor(self.t * 6) % 2
    for i, lane in ipairs(lanesFor(entry)) do
      local feetY = LANE_Y[i]
      Font.draw(lane.label, 16, feetY - 12)
      if lane.key == inUse then
        -- the row the sky is flying with right now
        Font.drawCode(mod.ui.Theme.cursor, 8, feetY - 12)
      end
      local tag = lane.tag
      Font.draw(tag, 160 - 8 - Font.width(tag), feetY - 12)
      if lane.source and lane.source ~= "game" then
        -- provenance, squeezed to the free right column
        local src = lane.source:sub(1, 9)
        Font.draw(src, 160 - 8 - Font.width(src), feetY - 2)
      end
      local renderer = lane.renderer
      if renderer then
        -- the sky's own composition: species-true dex scale unless the
        -- sheet's geometry already states the size (True Size art)
        local s = Sky.trueSized(renderer) and 1
          or Sky.dexScale(game.data, entry.species)
        local fx, fy = 96, feetY
        G.setColor(1, 1, 1, 1)
        if s ~= 1 then
          G.push()
          G.translate(fx, fy)
          G.scale(s, s)
          G.translate(-fx, -fy)
        end
        -- feet at (fx, fy): renderers anchor on (px + 8, py + 12);
        -- side-on, the pose the sky itself flies in
        local okD, err = pcall(renderer.draw, renderer,
          fx - 8, fy - 12, 0, 0, "left", flap)
        if s ~= 1 then G.pop() end
        if not okD then
          G.setColor(0, 0, 0, 1)
          Font.draw("?", fx, fy - 8)
          mod.log:warn("sky dex: %s/%s draw failed: %s",
            tostring(entry.species), lane.key, tostring(err))
        end
        G.setColor(0, 0, 0, 1)
      else
        Font.draw("NO ART", 96, feetY - 8)
      end
    end
  end

  game.stack:push(screen)
  return screen
end

-- ------- Gen1 Modern UI presentation (apiVersion 2 custom surface)
--
-- When Gen1 Modern UI is enabled, the Sky Dex hands it this contract and
-- the dex renders as a Pokedex-style page in the modern theme: species
-- list on the left, the three animated art lanes on the right, all drawn
-- by this mod on the surface's private canvas.  The classic 160x144 draw
-- above stays the fallback everywhere else (Gold included): the surface
-- host replaces it transactionally only after a successful frame.

local function themeColor(ctx, name, fallback)
  local colors = ctx.theme and ctx.theme.colors or nil
  local value = colors and colors[name] or nil
  return type(value) == "table" and value or fallback
end

local function setColor(c)
  love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1,
    c[4] == nil and 1 or c[4])
end

local function fontHeight(f)
  if not f or type(f.getHeight) ~= "function" then return 0 end
  local ok, h = pcall(f.getHeight, f)
  return ok and tonumber(h) or 0
end

local VIRTUAL_W, VIRTUAL_H = 480, 360

local function renderSurface(model, ctx)
  local screen = SkyDex._active
  if not screen then return false end
  local G = love.graphics
  local width, height = ctx.virtual.width, ctx.virtual.height
  local pad = 10
  local titleFont = ctx.fonts and ctx.fonts.title
  local bodyFont = ctx.fonts and ctx.fonts.body
  local captionFont = ctx.fonts and ctx.fonts.caption
  if fontHeight(titleFont) > height * 0.14 then titleFont = bodyFont end
  local titleH = fontHeight(titleFont)
  local bodyH = fontHeight(bodyFont)
  local captionH = fontHeight(captionFont)
  local headerH = math.max(28, titleH + pad)
  local footerH = captionH + 8

  local surface = themeColor(ctx, "surface", { 0.94, 0.93, 0.85, 1 })
  local raised = themeColor(ctx, "surfaceRaised", { 0.87, 0.87, 0.80, 1 })
  local selectedC = themeColor(ctx, "selected", { 0.78, 0.81, 0.76, 1 })
  local text = themeColor(ctx, "text", { 0.07, 0.08, 0.09, 1 })
  local muted = themeColor(ctx, "textMuted", { 0.30, 0.32, 0.35, 1 })
  local divider = themeColor(ctx, "divider", { 0.40, 0.42, 0.45, 1 })
  local accent = themeColor(ctx, "accent", { 0.12, 0.45, 0.60, 1 })

  setColor(surface)
  G.rectangle("fill", 0, 0, width, height)
  if titleFont then G.setFont(titleFont) end
  setColor(text)
  G.print(tostring(model.title or "SKY DEX"), pad,
    math.max(1, math.floor((headerH - titleH) * 0.5)))

  -- left: the species list, selected row highlighted like the Pokedex
  local listX, listY = pad, headerH
  local listW = math.floor(width * 0.52)
  local listH = height - headerH - footerH - pad
  local rowH = math.max(18, bodyH + 8)
  local visible = math.max(1, math.floor(listH / rowH))
  local rows = model.rows or {}
  local selected = math.max(1, math.min(tonumber(model.selected) or 1, #rows))
  local scroll = math.max(0, math.min(selected - math.ceil(visible / 2),
    #rows - visible))
  if bodyFont then G.setFont(bodyFont) end
  for slot = 1, visible do
    local i = scroll + slot
    local row = rows[i]
    if not row then break end
    local y = listY + (slot - 1) * rowH
    if i == selected then
      setColor(selectedC)
      G.rectangle("fill", listX, y, listW, rowH, 3, 3)
    end
    setColor(i == selected and text or muted)
    G.print(row.label or "", listX + 6,
      y + math.floor((rowH - bodyH) * 0.5))
    setColor(divider)
    G.rectangle("fill", listX, y + rowH - 1, listW, 1)
    ctx.input.region({ id = "skydex-row-" .. tostring(i),
      x = listX, y = y, w = listW, h = rowH,
      action = "jump", payload = { index = i } })
  end

  -- right: the three art lanes for the selected species, animated
  local paneX = listX + listW + pad
  local paneW = width - paneX - pad
  setColor(raised)
  G.rectangle("fill", paneX, listY, paneW, listH, 4, 4)
  local entry = screen.list[selected]
  local lanes = entry and screen:lanesFor(entry) or {}
  local laneH = math.floor((listH - pad) / math.max(1, #lanes))
  local frameTime = ctx.frame and tonumber(ctx.frame.time) or 0
  local flap = math.floor(frameTime * 6) % 2
  for i, lane in ipairs(lanes) do
    local ly = listY + (i - 1) * laneH + math.floor(pad / 2)
    if captionFont then G.setFont(captionFont) end
    setColor(lane.key == model.skyart and accent or muted)
    local label = lane.label
      .. (lane.key == model.skyart and "  <IN USE>" or "")
    G.print(label, paneX + 8, ly)
    local tag = lane.tag or "----"
    if captionFont then
      G.print(tag, paneX + paneW - 8 - captionFont:getWidth(tag), ly)
      if lane.source then
        -- provenance: the mod that dressed this lane, or the game data
        local src = lane.source == "game" and "game data" or lane.source
        setColor(muted)
        G.print(src, paneX + paneW - 8 - captionFont:getWidth(src),
          ly + captionH + 2)
      end
    end
    local renderer = lane.renderer
    if renderer then
      local s = 2 * ((Sky.trueSized(renderer) and 1)
        or Sky.dexScale(screen.data, entry.species))
      local fx = paneX + math.floor(paneW / 2)
      local fy = ly + laneH - 10
      G.setScissor(paneX + 1, listY + (i - 1) * laneH + 1,
        paneW - 2, laneH - 2)
      G.push()
      G.translate(fx, fy)
      G.scale(s, s)
      G.translate(-fx, -fy)
      setColor({ 1, 1, 1, 1 })
      pcall(renderer.draw, renderer, fx - 8, fy - 12, 0, 0, "left", flap)
      G.pop()
      G.setScissor(0, 0, width, height)
    else
      setColor(muted)
      if captionFont then
        G.print("NO ART", paneX + 8, ly + math.floor(laneH / 2))
      end
    end
  end

  if captionFont then G.setFont(captionFont) end
  setColor(muted)
  G.print("UP/DOWN MON   L/R +10   B BACK", pad, height - footerH + 3)
  ctx.input.region({ id = "skydex-back",
    x = 0, y = height - footerH, w = width, h = footerH,
    action = "back" })
  G.setScissor(0, 0, width, height)
  return true
end

-- the surface contract Gen1 Modern UI consumes; data below, render above
function SkyDex.modernUiContract()
  return {
    apiVersion = 2,
    surfaces = {
      WildSkiesSkyDex = {
        match = function(state)
          return type(state) == "table"
            and state.screenId == "WildSkiesSkyDex"
        end,
        model = function(_, state)
          local rows = {}
          for i, entry in ipairs(state.list or {}) do
            rows[i] = { label = ("%03d %s"):format(entry.dex, entry.name) }
          end
          return { title = "SKY DEX", rows = rows,
                   selected = tonumber(state.index) or 1,
                   skyart = mod.options:get("skyart") or "auto" }
        end,
        layout = {
          default = { virtualWidth = VIRTUAL_W, virtualHeight = VIRTUAL_H,
                      preset = "L" },
          portrait = { virtualWidth = VIRTUAL_H, virtualHeight = VIRTUAL_W,
                       preset = "M" },
          fit = "contain",
          scaleMode = "integer-fit",
        },
        native = { policy = "replace", scope = "uiCanvas" },
        render = renderSurface,
        actions = {
          jump = function(_, state, payload)
            if type(state.jumpTo) == "function" then
              state:jumpTo(payload and payload.index)
            end
            return true
          end,
          back = function(_, state)
            if type(state.back) == "function" then return state:back() end
            return false
          end,
        },
      },
    },
  }
end

-- hand the contract over whenever Gen1 Modern UI is present; harmless
-- when it is not (the classic draw carries the screen everywhere else)
function SkyDex.registerModernUi()
  local ui = mod.find and mod.find("gen1_modern_ui")
  local exports = ui and ui.exports or nil
  if not (exports and type(exports.registerAdapter) == "function") then
    return false
  end
  local supported = type(exports.supports) == "function"
    and exports.supports("custom_surface", 2)
    or tonumber(exports.surfaceApiVersion) == 2
  if not supported then return false end
  local ok, err = pcall(exports.registerAdapter, {
    owner = "wild_skies",
    contract = mod.exports.gen1ModernUi,
  })
  if not ok then
    mod.log:warn("sky dex: modern UI adapter refused: " .. tostring(err))
    return false
  end
  return true
end

return SkyDex
