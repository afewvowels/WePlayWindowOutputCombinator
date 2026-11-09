local util = require("util")

local NAME = "wp-window-output-combinator"
local OUTPUT_NAME = "window-output-combinator-output"
local TINT = {r = 0.55, g = 0.85, b = 0.0, a = 1}

---------------------------------------------------------------------------
-- Visible entity: a copy of the arithmetic combinator.
-- We only use it for its input/output wire connectors and its look;
-- its own arithmetic logic is left blank and its GUI is replaced by ours.
---------------------------------------------------------------------------
local entity = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
entity.name = NAME
entity.icon = nil
entity.icons = {{icon = "__base__/graphics/icons/arithmetic-combinator.png", tint = TINT}}
entity.minable = {mining_time = 0.1, result = NAME}
entity.fast_replaceable_group = nil
entity.next_upgrade = nil
-- Custom sprites: one 576x124 sheet, 4 frames of 144x124 (N, E, S, W)
local function frame(i)
  return {
    filename = "__WePlayWindowOutputCombinator__/graphics/window-output-combinator.png",
    width = 144,
    height = 124,
    x = i * 144,
    y = 0,
    scale = 0.5,
    shift = util.by_pixel(0.5, 7.5),
  }
end
entity.sprites = {north = frame(0), east = frame(1), south = frame(2), west = frame(3)}

-- Hide the arithmetic symbols that would otherwise draw on your display
for _, field in pairs({
  "plus_symbol_sprites", "minus_symbol_sprites", "multiply_symbol_sprites",
  "divide_symbol_sprites", "modulo_symbol_sprites", "power_symbol_sprites",
  "left_shift_symbol_sprites", "right_shift_symbol_sprites",
  "and_symbol_sprites", "or_symbol_sprites", "xor_symbol_sprites",
}) do
  entity[field] = util.empty_sprite()
end

---------------------------------------------------------------------------
-- Hidden helper: a constant combinator that actually emits the output.
-- It gets wired (invisibly, by script) to the visible combinator's output side.
---------------------------------------------------------------------------
local output = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
output.name = OUTPUT_NAME
output.icon = nil
output.icons = {{icon = "__base__/graphics/icons/constant-combinator.png", tint = TINT}}
output.hidden = true
output.hidden_in_factoriopedia = true
output.flags = {
  "not-on-map", "placeable-off-grid", "not-blueprintable",
  "not-deconstructable", "hide-alt-info", "no-copy-paste", "not-upgradable"
}
output.minable = nil
output.selectable_in_game = false
output.collision_box = {{0, 0}, {0, 0}}
output.selection_box = {{0, 0}, {0, 0}}
output.collision_mask = {layers = {}}
output.sprites = util.empty_sprite()
output.activity_led_sprites = util.empty_sprite()
output.draw_circuit_wires = false
output.draw_copper_wires = false
output.create_ghost_on_death = false
output.corpse = nil
output.dying_explosion = nil

---------------------------------------------------------------------------
-- Item + recipe
---------------------------------------------------------------------------
local item = util.table.deepcopy(data.raw["item"]["arithmetic-combinator"])
item.name = NAME
item.icon = nil
item.icons = {{icon = "__base__/graphics/icons/arithmetic-combinator.png", tint = TINT}}
item.place_result = NAME
item.order = (item.order or "c[combinators]") .. "-z[window]"

local recipe = {
  type = "recipe",
  name = NAME,
  enabled = false,
  ingredients = {
    {type = "item", name = "copper-cable", amount = 5},
    {type = "item", name = "electronic-circuit", amount = 5}
  },
  results = {{type = "item", name = NAME, amount = 1}}
}

data:extend({entity, output, item, recipe})

-- Unlock with the circuit network tech
local tech = data.raw["technology"]["circuit-network"]
if tech then
  tech.effects = tech.effects or {}
  table.insert(tech.effects, {type = "unlock-recipe", recipe = NAME})
end

