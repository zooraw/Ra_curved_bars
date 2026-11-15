local Vitals = ui.require("character.vitals")
local root = ui.load("window.xml")
ui.root(root)
local restore_position, update_tooltip, apply_layout
local frame_field = "RaCurvedBarFrame"
local straight_field, horizontal_field = "RaBarStraight", "RaBarHorizontal"
local reverse_field = "RaBarCurveReversed"
local layout = { straight = false, horizontal = false, reversed = false }
local placement = ui.require("core.placement").attach(root, {
	only_moved = true,
	field = frame_field,
	restored = function(reset)
		if restore_position then restore_position(reset) end
	end,
})

local native_restore = placement.restore
function placement:restore(reset)
	if apply_layout then
		apply_layout(not reset and ui.state.read(root, straight_field) == "true",
			not reset and ui.state.read(root, horizontal_field) == "true",
			not reset and ui.state.read(root, reverse_field) == "true")
	end
	if reset then
		ui.state.write(root, straight_field, "false", "bool")
		ui.state.write(root, horizontal_field, "false", "bool")
		ui.state.write(root, reverse_field, "false", "bool")
	end
	-- Read the old shared frame once so existing curved layouts can carry over.
	local migrate = not reset and ui.state.read(root, frame_field) == ""
	if migrate then self.options.field = "WindowFrame" end
	native_restore(self, reset)
	self.options.field = frame_field
	if reset or (migrate and self.intended and self.intended.width >= math.min(ui.minimum_width(root), ui.minimum_height(root))) then
		self:changed()
	end
end

local full_scale = 1.25
local left_x, right_x = 42, 42 + 68 * full_scale
local specs = {
	health = { label = "Health", color = "BD352B", x = left_x, peer = "nano" },
	nano = { label = "Nano", color = "3085D9", x = right_x, peer = "health", mirrored = true },
	experience = { label = "Experience", color = "D4A636", x = left_x, peer = "alien", anchor = "health" },
	alien = { label = "Alien Experience", color = "63A84C", x = right_x, peer = "experience", mirrored = true, anchor = "nano" },
}
local scale, cross_size, length
local cross_offset, mirror_stroke
local spec, bar, arc, notches, input, maximum, zero
local strips, fill_rows, empty_rows
local handles = {}
local fraction, last_maximum = 0, nil
local arc_midpoint, arc_half_height, arc_bow = 88, 74, 28
local arc_radius = (arc_half_height ^ 2 + arc_bow ^ 2) / (2 * arc_bow)
local bar_center = 10
local arc_center_x = bar_center + arc_radius
local outline_radius, fill_radius = 6, 4
local stroke_width_scale = 1.15
local fill_top = arc_midpoint - arc_half_height - fill_radius
local fill_bottom = arc_midpoint + arc_half_height + fill_radius

local function stroke_span(y, thickness)
	local dy = math.abs(y / scale - arc_midpoint)
	if layout.straight then
		local past_end = math.max(0, dy - arc_half_height)
		local half_width = math.sqrt(math.max(0, thickness ^ 2 - past_end ^ 2)) * stroke_width_scale
		return (bar_center - half_width) * scale, (bar_center + half_width) * scale
	end
	local outer, inner = arc_radius + thickness, arc_radius - thickness
	-- Each circular edge meets the round end cap at its own tangent point.
	local cap = math.sqrt(math.max(0, thickness ^ 2 - (dy - arc_half_height) ^ 2))
	local end_x = bar_center + arc_bow
	local left = dy <= arc_half_height * outer / arc_radius
		and arc_center_x - math.sqrt(outer ^ 2 - dy ^ 2) or end_x - cap
	local right = dy <= arc_half_height * inner / arc_radius
		and arc_center_x - math.sqrt(inner ^ 2 - dy ^ 2) or end_x + cap
	local extra = (right - left) * (stroke_width_scale - 1) / 2
	return (left - extra) * scale, (right + extra) * scale
end

local function place_rectangle(view, x, y, width, height)
	x = x + cross_offset
	if mirror_stroke then x = cross_size - x - width end
	if layout.horizontal then
		-- The top row is the maximum. Put it on the left for Health and Nano.
		local horizontal_x = spec.anchor and length - y - height or y
		ui.size(view, height, width)
		ui.place(view, horizontal_x, x)
	else
		ui.size(view, width, height)
		ui.place(view, x, y)
	end
end

local function add_strip(parent, y, left, right, height, color)
	local strip = ui.load("arc_strip.xml")
	ui.add(parent, strip)
	ui.fill_color(strip, color)
	local x = math.floor(left + 0.5)
	local width = math.floor(right + 0.5) - x
	place_rectangle(strip, x, y, width, height)
	strips[#strips + 1] = strip
	return strip
end

local function draw_stroke(arc, thickness, color, fill_rows)
	local top = (arc_midpoint - arc_half_height - thickness) * scale
	local bottom = (arc_midpoint + arc_half_height + thickness) * scale
	local samples = 4
	local colors = {}
	local outline_runs = {}
	local left_samples, right_samples = {}, {}
	for y = math.floor(top), math.ceil(bottom) - 1 do
		local count = 0
		local first, last = math.huge, -math.huge
		for index = 1, samples do
			local sample_y = y + (index - 0.5) / samples
			if sample_y >= top and sample_y < bottom then
				local left, right = stroke_span(sample_y, thickness)
				count = count + 1
				left_samples[count], right_samples[count] = left, right
				first = math.min(first, math.floor(left))
				last = math.max(last, math.ceil(right))
			end
		end
		local strips
		if fill_rows then
			strips = {}
			fill_rows[#fill_rows + 1] = strips
		end

		-- Sample edge coverage and join adjacent pixels with equal opacity.
		local start, previous = first, 0
		for x = first, last do
			local coverage = 0
			for index = 1, count do
				coverage = coverage + math.max(0, math.min(x + 1, right_samples[index]) - math.max(x, left_samples[index]))
			end
			local alpha = math.floor(255 * coverage / samples + 0.5)
			if alpha ~= previous then
				if previous > 0 then
					local paint = colors[previous]
					if not paint then
						paint = string.format("#%02X%s", previous, color)
						colors[previous] = paint
					end
					if strips then
						local strip = add_strip(arc, y, start, x, 1, paint)
						ui.opacity(strip, 0)
						strips[#strips + 1] = strip
					else
						-- A static outline run can span consecutive rows with the same coverage.
						local key = (start * cross_size + x) * 256 + previous
						local run = outline_runs[key]
						if run and run.bottom < y then
							add_strip(arc, run.y, start, x, run.bottom - run.y, paint)
							run = nil
						end
						if not run then
							run = { y = y, left = start, right = x, paint = paint }
							outline_runs[key] = run
						end
						run.bottom = y + 1
					end
				end
				start, previous = x, alpha
			end
		end
	end
	for _, run in pairs(outline_runs) do
		add_strip(arc, run.y, run.left, run.right, run.bottom - run.y, run.paint)
	end
end

local function build_stroke(color)
	draw_stroke(arc, outline_radius, "000000")
	draw_stroke(arc, fill_radius, color, fill_rows)
	for index = 1, 9 do
		local y = (fill_bottom - (fill_bottom - fill_top) * index / 10) * scale
		local left, right = stroke_span(y, fill_radius)
		add_strip(notches, math.floor(y), left, right, 2 * scale, "#000000")
	end
end

local function layout_input()
	local top = math.floor((arc_midpoint - arc_half_height - outline_radius) * scale)
	local bottom = math.ceil((arc_midpoint + arc_half_height + outline_radius) * scale)
	-- Follow the outline in short bands so transparent space does not cover neighboring bars.
	local index = 0
	for y = top, bottom - 1, 12 do
		index = index + 1
		local stop = math.min(y + 12, bottom)
		local middle = math.max(y, math.min(arc_midpoint * scale, stop))
		local left_middle, right_middle = stroke_span(middle, outline_radius)
		local left_start, right_start = stroke_span(y, outline_radius)
		local left_end, right_end = stroke_span(stop, outline_radius)
		local left = math.max(0, math.floor(math.min(left_middle, left_start, left_end)) - 2)
		local right = math.ceil(math.max(right_middle, right_start, right_end)) + 2
		local handle = handles[index]
		if not handle then
			handle = ui.load("arc_input.xml")
			ui.add(input, handle)
			handles[index] = handle
		end
		place_rectangle(handle, left, y, right - left, stop - y)
	end
end

local function show_arc_fill(fraction)
	local rows = fill_rows
	local empty = (1 - math.max(0, math.min(1, fraction))) * #rows
	local previous = empty_rows or #rows
	if empty == previous then return end
	empty_rows = empty
	-- Only the rows swept by the moving fill edge can change.
	local first = math.floor(math.min(previous, empty)) + 1
	local last = math.ceil(math.max(previous, empty))
	for index = first, last do
		local opacity = math.max(0, math.min(1, index - empty))
		for _, strip in ipairs(rows[index]) do
			ui.opacity(strip, opacity)
		end
	end
end

local function layout_numbers()
	if spec.anchor then return end
	local side = (layout.straight and 20 or 48) * scale
	local edge = 7 * scale
	if layout.horizontal then side = cross_size / 2 + 8 * scale end
	local near = mirror_stroke and 0 or side
	local far = mirror_stroke and side or 0
	local align = mirror_stroke and "end" or "start"
	if layout.horizontal then
		ui.borders(maximum, edge, near, 0, far)
		ui.align(maximum, "start", align)
		ui.borders(zero, 0, near, edge, far)
		ui.align(zero, "end", align)
	else
		ui.borders(maximum, near, edge, far, 0)
		ui.align(maximum, align, "start")
		ui.borders(zero, near, 0, far, edge)
		ui.align(zero, align, "end")
	end
end

apply_layout = function(straight, horizontal, reversed)
	local resize = not layout.width or horizontal ~= layout.horizontal
	local flip = not straight and reversed ~= layout.reversed
	layout.reversed = reversed
	if not resize and straight == layout.straight and not flip then return end
	layout.straight, layout.horizontal = straight, horizontal
	local center_horizontal = horizontal and not spec.anchor
	-- Health and Nano share an endpoint height. Curved versions bow to opposite sides of it.
	local end_center = (straight and bar_center or bar_center + arc_bow) * scale
	cross_offset = center_horizontal and math.floor(cross_size / 2 - end_center + 0.5) or 0
	mirror_stroke = spec.mirrored and not (center_horizontal and straight)
	if not straight and reversed then mirror_stroke = not mirror_stroke end
	if resize then
		layout.width = horizontal and length or cross_size
		layout.height = horizontal and cross_size or length
		for _, view in ipairs({ root, bar, arc, notches, input }) do
			ui.size(view, layout.width, layout.height)
		end
	end
	layout_numbers()
	layout_input()
	if strips then
		for _, strip in ipairs(strips) do ui.destroy(strip) end
	end
	strips, fill_rows, empty_rows = {}, {}, nil
	build_stroke(spec.color)
	show_arc_fill(fraction)
end

function layout.change(straight, horizontal, reversed)
	local rotate = horizontal ~= layout.horizontal
	local reshape = straight ~= layout.straight
	local flip = reversed ~= layout.reversed
	local old_width, old_height = layout.width, layout.height
	local x, y = ui.offset_x(root), ui.offset_y(root)
	apply_layout(straight, horizontal, reversed)
	if reshape then ui.state.write(root, straight_field, tostring(straight), "bool") end
	if flip then ui.state.write(root, reverse_field, tostring(reversed), "bool") end
	if rotate then
		-- Keep the same center when the frame swaps width and height.
		ui.place(root, x + (old_width - layout.width) / 2, y + (old_height - layout.height) / 2)
		placement:changed()
		ui.state.write(root, horizontal_field, tostring(horizontal), "bool")
	end
end

function status_bar_initialize(kind)
	spec = assert(specs[kind], "Unknown player status bar")
	scale = full_scale * (spec.anchor and 0.75 or 1)
	cross_size, length = math.ceil(86 * scale), 176 * scale
	bar = ui.load("arc.xml")
	ui.add(root, bar)
	arc, notches = ui.find(bar, "arc"), ui.find(bar, "notches")
	input = ui.find(bar, "input_regions")
	maximum, zero = ui.find(bar, "scale_maximum"), ui.find(bar, "scale_zero")
	if spec.anchor then
		ui.visible(maximum, false)
		ui.visible(zero, false)
	else
		ui.font_size(maximum, 11 * scale)
		ui.font_size(zero, 11 * scale)
	end
	apply_layout(false, false, false)
	ui.fill_color(root, "")
	ui.composite(root, false)
	ui.place(root, spec.x, spec.anchor and 12 + 176 * full_scale or 5)
	restore_position, update_tooltip = ra_attach_curved_drag(root, handles, ui.find(bar, "position_menu"), kind, spec, placement, layout)
end

function status_bar_apply(reading, shadowknowledge)
	fraction = reading.fraction
	show_arc_fill(fraction)
	if not spec.anchor then
		local text = reading.maximum_known and tostring(reading.maximum) or "--"
		if last_maximum ~= text then
			ui.text(maximum, text)
			last_maximum = text
		end
	end
	update_tooltip((shadowknowledge and "Shadowknowledge" or spec.label) .. ": " .. Vitals.reading_text(reading))
end
