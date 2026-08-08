-- The target menu, headless: while a target or switch prompt is up,
-- the overlay draws a vanilla-style box naming both candidates with
-- the cursor on the aimed one, and the cursor follows the aim.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local pushed
local fakeOw = { pushBattle = function(_, b) pushed = b end }
local pressed = {}
local fakeGame = {
  data = Data,
  overworld = fakeOw,
  input = {
    wasPressed = function(_, key) return pressed[key] == true end,
    isDown = function(_, key) return pressed[key] == true end,
  },
  save = {
    party = {},
    options = {},
    inventory = {},
    pokedex = { seen = {}, owned = {} },
    player = { name = "TEST" },
  },
}
package.loaded["src.core.Game"] = fakeGame

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/double_battles",
  { data = Data })
T.check(run.mod ~= nil, "mod discovered and loaded")
T.eq(#run.errors, 0, "loads clean")

local Pokemon = require("src.pokemon.Pokemon")
fakeGame.save.party[1] = Pokemon.new(Data, "PIDGEY", 12)
fakeGame.save.party[2] = Pokemon.new(Data, "RATTATA", 12)
fakeGame.save.party[3] = Pokemon.new(Data, "PIKACHU", 12)

local api = run.loader.exports.double_battles
T.eq(api.startWildDouble("SPEAROW", 8, "ZUBAT", 8), true, "double up")
local b = pushed

-- spy on the engine font: what the menu draws is what the player reads
local Font = require("src.render.Font")
local drawn, boxes, cursors
local origDraw, origBox, origCode = Font.draw, Font.drawBox, Font.drawCode
Font.draw = function(text, x, y)
  drawn[#drawn + 1] = { text = text, x = x, y = y }
end
Font.drawBox = function(tx, ty, tw, th)
  boxes[#boxes + 1] = { tx = tx, ty = ty, tw = tw, th = th }
end
Font.drawCode = function(code, x, y)
  if code == 0xED then cursors[#cursors + 1] = { x = x, y = y } end
end

local Runtime = require("src.mods.Runtime")
local function overlay()
  drawn, boxes, cursors = {}, {}, {}
  Runtime.call("battle.overlay", function() end, b)
end
local function names()
  local out = {}
  for _, d in ipairs(drawn) do out[#out + 1] = d.text end
  return table.concat(out, ",")
end
local function press(key)
  pressed[key] = true
  b:update(0.016)
  pressed[key] = nil
end

-- ------- the foe prompt

b:resolveTurn({ id = b.player.curMoves[1].id })
T.eq(b.phase, "db_target", "target prompt open")
overlay()
T.eq(#boxes, 1, "one menu box drawn")
T.eq(boxes[1].tx, 8, "anchored like the battle menu")
T.eq(names(), "SPEAROW,ZUBAT", "both foes named, lead first")
T.eq(#cursors, 1, "one cursor")
local leadRowY = drawn[1].y
T.eq(cursors[1].y, leadRowY, "cursor starts on the lead")

press("down")
overlay()
T.eq(names(), "SPEAROW,ZUBAT", "order is sticky while aim moves")
T.eq(cursors[1].y, drawn[2].y, "cursor follows the aim to the partner")

press("up")
overlay()
T.eq(cursors[1].y, drawn[1].y, "and back")
press("b")
overlay()
T.eq(#boxes, 0, "menu gone once the prompt closes")

-- ------- the switch prompt

b:resolveSwitch(fakeGame.save.party[3])
T.eq(b.phase, "db_switch_target", "switch prompt open")
overlay()
T.eq(#boxes, 1, "menu box drawn for your side")
T.eq(names(), "PIDGEY,RATTATA", "both of yours named, lead first")
T.eq(cursors[1].y, drawn[1].y, "cursor on the picking slot")
press("right")
overlay()
T.eq(names(), "PIDGEY,RATTATA", "sticky order through the aim swap")
T.eq(cursors[1].y, drawn[2].y, "cursor on the partner")
press("b")

Font.draw, Font.drawBox, Font.drawCode = origDraw, origBox, origCode
run.release()
T.finish("double_battles_aimmenu")
