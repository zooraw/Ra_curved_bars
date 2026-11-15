local Move = ui.require("core.move")
local snap_radius = 46
local snap_strength = 0.95
local release_radius = 18
local lock_indices = { health = 1, nano = 2, experience = 3, alien = 4 }
local unset_locks = "...."
local all_unlocked = string.rep("0", #unset_locks)
local all_locked = string.rep("1", #unset_locks)
local lock_field = "RaPositionLocked"

local function softened(position, target)
	if not target then return position end
	local delta = position - target
	local distance = math.abs(delta) / snap_radius
	if distance >= 1 then return position end
	-- Match ordinary motion at the edge and slow through the center.
	return target + delta * (1 - snap_strength * (1 - distance ^ 2) ^ 2)
end

-- Invert the drag curve at pickup so a bar already in range starts where it rests.
local function drag_origin(position, target)
	local low = target - snap_radius
	local high = target + snap_radius
	for _ = 1, 16 do
		local middle = (low + high) / 2
		if softened(middle, target) < position then low = middle else high = middle end
	end
	return (low + high) / 2
end

local function drag_axis(origin, target)
	if not target then return function(delta) return origin + delta end end

	local pickup = origin - target
	local pickup_distance = math.abs(pickup)
	local correction = 0
	if pickup_distance > 0 and pickup_distance < snap_radius then
		correction = drag_origin(origin, target) - origin
	end
	return function(delta, settle)
		local raw = origin + delta
		local offset = raw - target
		local distance = math.abs(offset)
		if settle and distance <= release_radius then return target end
		-- Hold the pickup point in place and taper its correction to zero at both
		-- the alignment point and the edge of the snap range.
		if correction ~= 0 and offset * pickup > 0 and distance < snap_radius then
			local weight = math.min(distance / pickup_distance,
				(snap_radius - distance) / (snap_radius - pickup_distance))
			local eased = softened(raw + correction * weight, target)
			return offset < 0 and math.max(raw, eased) or math.min(raw, eased)
		end
		return softened(raw, target)
	end
end

function ra_attach_curved_drag(view, handles, menu, kind, spec, placement, layout)
	local own_key = "drag-pose-" .. kind
	local scope, last_published, next_sample = nil, nil, 0
	local published_x, published_y, published_width, published_height
	local published_bar_width, published_bar_height
	local gesture
	local needs_anchor
	local lock_key
	local lock_index = lock_indices[kind]
	local legacy_locked = false
	local reset_pending = false
	local backdrop = ui.load("position_menu.xml")
	local toggle = ui.find(menu, "position_toggle")
	local bulk = ui.find(menu, "position_bulk")
	local lock_all = ui.find(menu, "position_lock_all")
	local straight = ui.find(menu, "position_straight")
	local curved = ui.find(menu, "position_curved")
	local orientation = ui.find(menu, "position_orientation")
	local column_width = ui.minimum_width(menu) - 2
	local row_height = ui.minimum_height(toggle)
	local pointer_x, pointer_y
	local hovered_handle, tooltip
	local lock_on_click, bulk_locks

	local function close_menu()
		if not ui.requested_visible(menu) then return end
		ui.visible(menu, false)
		ui.visible(backdrop, false)
		if hovered_handle and tooltip then ui.tooltip(hovered_handle, tooltip) end
	end
	local function size_backdrop()
		local width, height = ui.parent_width(view), ui.parent_height(view)
		if width ~= ui.minimum_width(backdrop) or height ~= ui.minimum_height(backdrop) then
			ui.size(backdrop, width, height)
		end
	end
	-- The bar owns the menu buttons. The scene attachment handles outside clicks.
	ui.attach(view, backdrop, size_backdrop)
	ui.place(backdrop, 0, 0)
	ui.on_click(backdrop, close_menu)
	ui.on_pointer_release(backdrop, "right", close_menu)
	ui.align(menu, "start", "start")
	for _, button in ipairs({ toggle, bulk, lock_all, straight, curved, orientation }) do
		ui.align(button, "start", "start")
		ui.size(button, column_width, row_height)
	end

	local function shared_locks()
		local value = lock_key and ui.storage.read(lock_key) or ""
		return #value == #unset_locks and value or unset_locks
	end
	local function is_locked(locks)
		-- A dot leaves the lock setting saved by earlier versions in effect.
		local value = (locks or shared_locks()):sub(lock_index, lock_index)
		if value == "." then return legacy_locked end
		return value == "1"
	end
	local function save_lock(locked, all)
		if lock_key then
			-- A single write changes all four bars, even if some are hidden.
			local digit = locked and "1" or "0"
			local value
			if all then
				value = locked and all_locked or all_unlocked
			else
				local previous = shared_locks()
				value = previous:sub(1, lock_index - 1) .. digit .. previous:sub(lock_index + 1)
			end
			ui.storage.write(lock_key, value)
		else
			legacy_locked = locked
			ui.state.write(view, lock_field, tostring(locked), "bool")
		end
	end

	local function publish(value)
		if value == last_published then return end
		ui.storage.write(own_key, value)
		last_published = value
	end
	local function clear_position()
		published_x, published_y = nil, nil
		publish("")
	end
	clear_position()

	-- Each bar has its own Lua runtime. Share current poses and character locks
	-- through package storage. The client still saves each bar's position.
	game.character.subscribe("self", "", function(update, character)
		local identity = character and character.present and character.key
		local current = identity and (update.session .. "\n" .. identity .. "\n") or nil
		if current == scope then return end
		close_menu()
		scope, gesture, next_sample = current, nil, 0
		lock_key = identity and ("position-locks:" .. identity) or nil
		if lock_key and reset_pending then
			save_lock(false, false)
			reset_pending = false
		end
		clear_position()
	end)
	local function publish_position(x, y)
		if not scope then return end
		local width, height = ui.parent_width(view), ui.parent_height(view)
		if width <= 0 or height <= 0 then return end
		if x == published_x and y == published_y and width == published_width and height == published_height
			and layout.width == published_bar_width and layout.height == published_bar_height then return end
		publish(scope .. table.concat({ width, height, x, y, layout.width, layout.height }, ","))
		published_x, published_y, published_width, published_height = x, y, width, height
		published_bar_width, published_bar_height = layout.width, layout.height
	end
	local function finish_drag()
		if gesture and gesture.final_x then placement:changed() end
		gesture, next_sample = nil, 0
	end
	local function choose_lock(locked, all)
		if all and not lock_key then return end
		close_menu()
		save_lock(locked, all)
		if locked then
			finish_drag()
			if needs_anchor then placement:changed() end
			needs_anchor = false
		end
	end
	ui.on_click(toggle, function() choose_lock(lock_on_click, false) end)
	ui.on_click(bulk, function() choose_lock(bulk_locks, true) end)
	ui.on_click(lock_all, function() choose_lock(true, true) end)
	local function choose_layout(is_straight, horizontal, reversed)
		close_menu()
		finish_drag()
		if horizontal ~= layout.horizontal then needs_anchor = false end
		layout.change(is_straight, horizontal, reversed)
	end
	ui.on_click(straight, function()
		choose_layout(true, layout.horizontal, layout.reversed)
	end)
	ui.on_click(curved, function()
		local reversed = layout.reversed
		if not layout.straight then reversed = not reversed end
		choose_layout(false, layout.horizontal, reversed)
	end)
	ui.on_click(orientation, function()
		choose_layout(layout.straight, not layout.horizontal, layout.reversed)
	end)
	local function place_button(button, column, row)
		ui.place(button, 1 + column * column_width, 1 + row * row_height)
	end
	local function show_menu(x, y)
		local locks = shared_locks()
		bulk_locks = locks == all_unlocked
		-- Reuse the middle bulk row for Unlock all. Mixed and legacy states offer both actions.
		local show_lock_all = lock_key ~= nil and not bulk_locks and locks ~= all_locked
		ui.text(bulk, bulk_locks and "Lock all" or "Unlock all")
		ui.visible(bulk, lock_key ~= nil)
		ui.visible(lock_all, show_lock_all)
		ui.text(orientation, layout.horizontal and "Vertical" or "Horizontal")
		local lock_rows = show_lock_all and 3 or lock_key and 2 or 1
		local shape_column, shape_row = 0, lock_rows
		local columns, rows = 1, lock_rows + 3
		-- Use two columns to keep the menu inside a short horizontal bar.
		if layout.horizontal then
			shape_column, shape_row = 1, 0
			columns, rows = 2, 3
		end
		place_button(toggle, 0, 0)
		place_button(bulk, 0, 1)
		place_button(lock_all, 0, 2)
		place_button(straight, shape_column, shape_row)
		place_button(curved, shape_column, shape_row + 1)
		place_button(orientation, shape_column, shape_row + 2)
		local menu_width = columns * column_width + 2
		local menu_height = rows * row_height + 2
		ui.size(menu, menu_width, menu_height)
		local local_x = x and x - ui.x(view) or layout.width / 2
		local local_y = y and y - ui.y(view) or layout.height / 2
		ui.place(menu, math.max(0, math.min(local_x - menu_width / 2, layout.width - menu_width)),
			math.max(0, math.min(local_y - menu_height / 2, layout.height - menu_height)))
		lock_on_click = not is_locked(locks)
		ui.text(toggle, lock_on_click and "Lock in place" or "Unlock")
		if hovered_handle then ui.tooltip(hovered_handle, "") end
		size_backdrop()
		ui.visible(backdrop, true)
		ui.visible(menu, true)
	end
	local function show_at_pointer()
		-- Right-release observers provide no coordinates. Use the latest hover.
		show_menu(pointer_x, pointer_y)
	end
	ui.on_visibility(view, function(visible)
		if not visible then
			pointer_x, pointer_y = nil, nil
			close_menu()
			finish_drag()
			clear_position()
		end
		next_sample = 0
	end)
	local function read_position(bar_kind)
		if not scope then return end
		local pose = ui.storage.read("drag-pose-" .. bar_kind)
		if pose:sub(1, #scope) ~= scope then return end
		local width, height, x, y, box_width, box_height =
			pose:sub(#scope + 1):match("^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")
		width, height, x, y = tonumber(width), tonumber(height), tonumber(x), tonumber(y)
		box_width, box_height = tonumber(box_width), tonumber(box_height)
		if width ~= ui.parent_width(view) or height ~= ui.parent_height(view) or not x or not y
			or not box_width or not box_height then
			return
		end
		return x, y, width, height, box_width, box_height
	end

	ui.on_update(function(time)
		if not scope or gesture or time < next_sample then return end
		next_sample = time + 120
		local x, y = ui.local_x(view), ui.local_y(view)
		if needs_anchor and is_locked() then
			placement:changed()
			needs_anchor = false
		end
		if needs_anchor then
			local anchor_x, anchor_y, _, height, anchor_width, anchor_height = read_position(spec.anchor)
			if anchor_x then
				local below = anchor_y + anchor_height + 7
				local above = anchor_y - layout.height - 7
				local next_y = (below + layout.height <= height or above < 0) and below or above
				local next_x = spec.mirrored and anchor_x + anchor_width - layout.width or anchor_x
				x, y = Move.place(view, next_x, next_y)
				placement:changed()
				needs_anchor = false
			end
		end
		publish_position(x, y)
	end)

	local function targets()
		local x, y, width, _, peer_width, peer_height = read_position(spec.peer)
		if not x then return end
		-- Pair centers stay aligned even when the bars have different orientations.
		return width - x - (peer_width + layout.width) / 2, y + (peer_height - layout.height) / 2
	end

	local function on_pointer(handle, phase, x, y)
		if phase == "hover" then
			pointer_x, pointer_y = x, y
			if handle ~= hovered_handle then
				if hovered_handle then ui.tooltip(hovered_handle, "") end
				hovered_handle = handle
				if tooltip and not ui.requested_visible(menu) then ui.tooltip(handle, tooltip) end
			end
		elseif phase == "start" then
			pointer_x, pointer_y = x, y
			ui.capture_pointer(handle)
			gesture = { press_x = x, press_y = y }
			if not is_locked() then
				local snap_x, snap_y = targets()
				gesture.x = drag_axis(ui.local_x(view), snap_x)
				gesture.y = drag_axis(ui.local_y(view), snap_y)
				gesture.snap_x, gesture.snap_y = snap_x, snap_y
			end
		elseif gesture and (phase == "move" or phase == "end") then
			local dx, dy = x - gesture.press_x, y - gesture.press_y
			if not gesture.moved and (dx ~= 0 or dy ~= 0) then
				gesture.moved = true
				close_menu()
			end
			if gesture.x and gesture.moved then
				needs_anchor = false
				local settle_x, settle_y = false, false
				if phase == "end" then
					local snap_x, snap_y = targets()
					settle_x = snap_x ~= nil and snap_x == gesture.snap_x
					settle_y = snap_y ~= nil and snap_y == gesture.snap_y
				end
				local next_x, next_y = gesture.x(dx, settle_x), gesture.y(dy, settle_y)
				if next_x ~= gesture.next_x or next_y ~= gesture.next_y then
					gesture.final_x, gesture.final_y = Move.place(view, next_x, next_y)
					gesture.next_x, gesture.next_y = next_x, next_y
				end
			end
			if phase == "end" then
				pointer_x, pointer_y = x, y
				local moved = gesture.final_x ~= nil
				if moved then publish_position(gesture.final_x, gesture.final_y) end
				if not gesture.moved then
					if ui.requested_visible(menu) then close_menu() else show_menu(x, y) end
				end
				finish_drag()
				if moved then ui.notify(view, "moved", x, y) end
			end
		elseif phase == "cancel" then
			finish_drag()
		end
	end
	for _, handle in ipairs(handles) do
		ui.on_pointer(handle, function(phase, x, y) on_pointer(handle, phase, x, y) end)
		ui.on_pointer_release(handle, "right", show_at_pointer)
	end
	local function restore(reset)
		close_menu()
		legacy_locked = not reset and ui.state.read(view, lock_field) == "true"
		reset_pending = reset and not lock_key
		if reset and lock_key then save_lock(false, false) end
		if spec.anchor then
			local pose = placement.intended
			-- Stock XP frames were narrower. Choose a new default for that layout.
			needs_anchor = not is_locked() and (not pose or pose.width < math.min(layout.width, layout.height))
		end
	end
	local function update_tooltip(text)
		if text == tooltip then return end
		tooltip = text
		if hovered_handle and not ui.requested_visible(menu) then ui.tooltip(hovered_handle, text) end
	end
	return restore, update_tooltip
end
