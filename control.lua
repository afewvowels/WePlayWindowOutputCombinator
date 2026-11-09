-- Window Output Combinator (Factorio 2.0)
-- Reads every signal on its input wires and outputs them one at a time,
-- each for a configurable number of ticks.

local NAME = "wp-window-output-combinator"
local OUTPUT_NAME = "window-output-combinator-output"
local GUI_NAME = "woc_frame"

local filters = {{filter = "name", name = NAME}}

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local function init_storage()
  storage.combinators = storage.combinators or {} -- unit_number -> data
  storage.guis = storage.guis or {}               -- player_index -> unit_number
end

local function default_interval()
  return settings.global["woc-default-interval"].value
end

---------------------------------------------------------------------------
-- Signal helpers
---------------------------------------------------------------------------
local function signal_key(id)
  return (id.type or "item") .. "/" .. id.name .. "/" .. (id.quality or "normal")
end

local ITEM_TYPES = {item = true}

-- All input signals (red + green merged), sorted so the order is stable.
-- With items_only set, anything that isn't an item signal is skipped.
local function read_inputs(entity, items_only)
  local raw = entity.get_signals(
    defines.wire_connector_id.combinator_input_red,
    defines.wire_connector_id.combinator_input_green
  )
  if not raw then return {} end
  local signals = {}
  for _, s in pairs(raw) do
    if not items_only or ITEM_TYPES[s.signal.type or "item"] then
      s.key = signal_key(s.signal)
      signals[#signals + 1] = s
    end
  end
  table.sort(signals, function(a, b) return a.key < b.key end)
  return signals
end

local function set_output(data, signal, count)
  local output = data.output
  if not (output and output.valid) then return end
  local section = output.get_control_behavior().get_section(1)
  if not section then return end
  if not signal or count == 0 then
    if data.shown_key then
      section.clear_slot(1)
      data.shown_key, data.shown_count = nil, nil
    end
    return
  end
  local key = signal_key(signal)
  if key == data.shown_key and count == data.shown_count then return end
  section.set_slot(1, {
    value = {
      type = signal.type or "item",
      name = signal.name,
      quality = signal.quality or "normal",
      comparator = "="
    },
    min = count
  })
  data.shown_key, data.shown_count = key, count
end

---------------------------------------------------------------------------
-- Building / removing
---------------------------------------------------------------------------
local function blank_arithmetic(entity)
  -- Keep the combinator's own logic empty so only our helper outputs anything.
  local cb = entity.get_or_create_control_behavior()
  cb.parameters = {operation = "+"}
end

local function on_built(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == NAME) then return end

  blank_arithmetic(entity)

  local output = entity.surface.create_entity{
    name = OUTPUT_NAME,
    position = entity.position,
    force = entity.force,
    create_build_effect_smoke = false
  }
  output.destructible = false
  local ocb = output.get_or_create_control_behavior()
  if ocb.sections_count == 0 then ocb.add_section() end

  -- Hidden script wires: visible combinator's output side -> helper.
  for _, pair in pairs({
    {defines.wire_connector_id.combinator_output_red,   defines.wire_connector_id.circuit_red},
    {defines.wire_connector_id.combinator_output_green, defines.wire_connector_id.circuit_green},
  }) do
    local from = entity.get_wire_connector(pair[1], true)
    local to = output.get_wire_connector(pair[2], true)
    from.connect_to(to, false, defines.wire_origin.script)
  end

  local interval = default_interval()
  local items_only = false
  local tags = event.tags
  if tags then
    if tags.woc_interval then interval = tags.woc_interval end
    if tags.woc_items_only then items_only = true end
  end

  storage.combinators[entity.unit_number] = {
    entity = entity,
    output = output,
    interval = interval,
    items_only = items_only,
    timer = 0,     -- ticks left on the current signal
    index = 0,     -- position in the sorted signal list
  }
  script.register_on_object_destroyed(entity)
end

local function on_destroyed(event)
  local id = event.useful_id
  local data = id and storage.combinators[id]
  if not data then return end
  if data.output and data.output.valid then data.output.destroy() end
  storage.combinators[id] = nil
end

---------------------------------------------------------------------------
-- The tick loop
---------------------------------------------------------------------------
local function update(data)
  local entity = data.entity
  if entity.status == defines.entity_status.no_power then
    set_output(data, nil, 0)
    return
  end

  local signals = read_inputs(entity, data.items_only)
  local n = #signals
  if n == 0 then
    data.index, data.timer = 0, 0
    set_output(data, nil, 0)
    return
  end

  -- Is the signal we're showing still present? (Keep its count live.)
  local current
  if data.shown_key then
    for i, s in pairs(signals) do
      if s.key == data.shown_key then current = s; data.index = i; break end
    end
  end

  data.timer = data.timer - 1
  if not current or data.timer <= 0 then
    data.index = (data.index % n) + 1
    current = signals[data.index]
    data.timer = data.interval
  end

  set_output(data, current.signal, current.count)
end

local function on_tick()
  for id, data in pairs(storage.combinators) do
    if data.entity.valid then
      update(data)
    else
      if data.output and data.output.valid then data.output.destroy() end
      storage.combinators[id] = nil
    end
  end
end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
local function close_gui(player)
  local frame = player.gui.screen[GUI_NAME]
  if frame then frame.destroy() end
  storage.guis[player.index] = nil
end

local function refresh_seconds(frame, interval)
  frame.content.row.seconds.caption = {"woc.seconds", string.format("%.2f", interval / 60)}
end

local function open_gui(player, entity)
  close_gui(player)
  local data = storage.combinators[entity.unit_number]
  if not data then return end

  local frame = player.gui.screen.add{type = "frame", name = GUI_NAME, direction = "vertical"}
  frame.auto_center = true

  local titlebar = frame.add{type = "flow", direction = "horizontal"}
  titlebar.drag_target = frame
  titlebar.add{type = "label", caption = {"woc.title"}, style = "frame_title", ignored_by_interaction = true}
  local filler = titlebar.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  titlebar.add{type = "sprite-button", name = "woc_close", style = "frame_action_button",
               sprite = "utility/close"}

  local content = frame.add{type = "frame", name = "content", style = "inside_shallow_frame_with_padding",
                            direction = "vertical"}
  content.add{type = "label", caption = {"woc.interval"}}
  local row = content.add{type = "flow", name = "row", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.add{type = "slider", name = "woc_slider", minimum_value = 1, maximum_value = 600,
          value = math.min(data.interval, 600), value_step = 1}
  local field = row.add{type = "textfield", name = "woc_text", text = tostring(data.interval),
                        numeric = true, allow_decimal = false, allow_negative = false}
  field.style.width = 70
  row.add{type = "label", name = "seconds"}
  refresh_seconds(frame, data.interval)

  content.add{type = "checkbox", name = "woc_items_only", caption = {"woc.items-only"},
              tooltip = {"woc.items-only-tooltip"}, state = data.items_only == true}

  storage.guis[player.index] = entity.unit_number
  player.opened = frame
end

local function set_interval(player, value, source)
  local id = storage.guis[player.index]
  local data = id and storage.combinators[id]
  if not data then return end
  value = math.max(1, math.min(216000, math.floor(value)))
  data.interval = value
  if data.timer > value then data.timer = value end

  local frame = player.gui.screen[GUI_NAME]
  if not frame then return end
  local row = frame.content.row
  if source ~= "slider" then row.woc_slider.slider_value = math.min(value, 600) end
  if source ~= "text" then row.woc_text.text = tostring(value) end
  refresh_seconds(frame, value)
end

script.on_event(defines.events.on_gui_opened, function(event)
  local entity = event.entity
  if entity and entity.valid and entity.name == NAME then
    open_gui(game.get_player(event.player_index), entity)
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.name == GUI_NAME then
    close_gui(game.get_player(event.player_index))
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  if event.element.valid and event.element.name == "woc_close" then
    close_gui(game.get_player(event.player_index))
  end
end)

script.on_event(defines.events.on_gui_value_changed, function(event)
  if event.element.name == "woc_slider" then
    set_interval(game.get_player(event.player_index), event.element.slider_value, "slider")
  end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  if event.element.name == "woc_text" then
    local value = tonumber(event.element.text)
    if value and value >= 1 then
      set_interval(game.get_player(event.player_index), value, "text")
    end
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  if event.element.name ~= "woc_items_only" then return end
  local id = storage.guis[event.player_index]
  local data = id and storage.combinators[id]
  if data then
    data.items_only = event.element.state
    data.timer = 0 -- jump straight to a signal that passes the filter
  end
end)

---------------------------------------------------------------------------
-- Copy/paste settings and blueprints
---------------------------------------------------------------------------
script.on_event(defines.events.on_entity_settings_pasted, function(event)
  local src, dst = event.source, event.destination
  if not (dst.valid and dst.name == NAME) then return end
  if src.name == NAME then
    local s, d = storage.combinators[src.unit_number], storage.combinators[dst.unit_number]
    if s and d then
      d.interval = s.interval
      d.items_only = s.items_only
      d.timer = math.min(d.timer, d.interval)
    end
  end
  -- Never let a normal arithmetic combinator's settings sneak in.
  blank_arithmetic(dst)
end)

script.on_event(defines.events.on_player_setup_blueprint, function(event)
  local blueprint = event.stack
  if not (blueprint and blueprint.valid_for_read and blueprint.is_blueprint) then
    blueprint = event.record
  end
  if not blueprint then return end
  local mapping = event.mapping.get()
  for index, entity in pairs(mapping) do
    if entity.valid and entity.name == NAME then
      local data = storage.combinators[entity.unit_number]
      if data then
        blueprint.set_blueprint_entity_tag(index, "woc_interval", data.interval)
        blueprint.set_blueprint_entity_tag(index, "woc_items_only", data.items_only == true)
      end
    end
  end
end)

---------------------------------------------------------------------------
-- Event wiring
---------------------------------------------------------------------------
script.on_init(init_storage)
script.on_configuration_changed(init_storage)

script.on_event(defines.events.on_built_entity, on_built, filters)
script.on_event(defines.events.on_robot_built_entity, on_built, filters)
script.on_event(defines.events.on_space_platform_built_entity, on_built, filters)
script.on_event(defines.events.script_raised_built, on_built, filters)
script.on_event(defines.events.script_raised_revive, on_built, filters)
script.on_event(defines.events.on_object_destroyed, on_destroyed)
script.on_event(defines.events.on_tick, on_tick)
