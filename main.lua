local Vitals = ui.require("character.vitals")
local root = ui.load("window.xml")
ui.root(root)
local restore_position, update_tooltip
local frame_field = "RaCurvedBarFrame"
local placement = ui.require("core.placement").attach(root, {
	only_moved = true,
	field = frame_field,
	restored = function(reset)
		if restore_position then restore_position(reset) end
	end,
})

local native_restore = placement.restore
function placement:restore(reset)
	-- Read the old shared frame once so existing curved layouts can carry over.
	local migrate = not reset and ui.state.read(root, frame_field) == ""
	if migrate then self.options.field = "WindowFrame" end
	native_restore(self, reset)
	self.options.field = frame_field
	if reset or (migrate and self.intended and self.intended.width >= ui.minimum_width(root)) then
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
local scale, bar_width, bar_height
local spec, bar
local curved
local arc_midpoint, arc_half_height, arc_bow = 88, 74, 28
local arc_radius = (arc_half_height ^ 2 + arc_bow ^ 2) / (2 * arc_bow)
local arc_center_x = 10 + arc_radius
local outline_radius, fill_radius = 6, 4
local stroke_width_scale = 1.15
local fill_top = arc_midpoint - arc_half_height - fill_radius
local fill_bottom = arc_midpoint + arc_half_height + fill_radius

local function stroke_span(y, thickness)
	local dy = math.abs(y / scale - arc_midpoint)
	local outer, inner = arc_radius + thickness, arc_radius - thickness
	-- Each circular edge meets the round end cap at its own tangent point.
	local cap = math.sqrt(math.max(0, thickness ^ 2 - (dy - arc_half_height) ^ 2))
	local end_x = 10 + arc_bow
	local left = dy <= arc_half_height * outer / arc_radius
		and arc_center_x - math.sqrt(outer ^ 2 - dy ^ 2) or end_x - cap
	local right = dy <= arc_half_height * inner / arc_radius
		and arc_center_x - math.sqrt(inner ^ 2 - dy ^ 2) or end_x + cap
	local extra = (right - left) * (stroke_width_scale - 1) / 2
	return (left - extra) * scale, (right + extra) * scale
end

local function add_strip(parent, y, left, right, height, color)
	local strip = ui.load("arc_strip.xml")
	ui.add(parent, strip)
	ui.fill_color(strip, color)
	local x = math.floor(left + 0.5)
	local width = math.floor(right + 0.5) - x
	ui.size(strip, width, height)
	ui.place(strip, spec.mirrored and bar_width - x - width or x, y)
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
						local key = (start * bar_width + x) * 256 + previous
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

local function build_arc(content, color)
	local arc = ui.find(content, "arc")
	ui.size(arc, bar_width, bar_height)
	draw_stroke(arc, outline_radius, "000000")
	draw_stroke(arc, fill_radius, color, curved.segments)
	local notches = ui.find(content, "notches")
	ui.size(notches, bar_width, bar_height)
	for index = 1, 9 do
		local y = (fill_bottom - (fill_bottom - fill_top) * index / 10) * scale
		local left, right = stroke_span(y, fill_radius)
		add_strip(notches, math.floor(y), left, right, 2 * scale, "#000000")
	end
end

local function build_input(content)
	local handles = {}
	ui.size(content, bar_width, bar_height)
	local top = math.floor((arc_midpoint - arc_half_height - outline_radius) * scale)
	local bottom = math.ceil((arc_midpoint + arc_half_height + outline_radius) * scale)
	-- Follow the outline in short bands so transparent space does not cover neighboring bars.
	for y = top, bottom - 1, 12 do
		local stop = math.min(y + 12, bottom)
		local middle = math.max(y, math.min(arc_midpoint * scale, stop))
		local left = stroke_span(middle, outline_radius)
		local _, right_start = stroke_span(y, outline_radius)
		local _, right_end = stroke_span(stop, outline_radius)
		left = math.max(0, math.floor(left) - 2)
		local right = math.ceil(math.max(right_start, right_end)) + 2
		local handle = ui.load("arc_input.xml")
		ui.add(content, handle)
		ui.size(handle, right - left, stop - y)
		ui.place(handle, spec.mirrored and bar_width - right or left, y)
		handles[#handles + 1] = handle
	end
	return handles
end

local function show_arc_fill(fraction)
	local rows = curved.segments
	local empty = (1 - math.max(0, math.min(1, fraction))) * #rows
	local previous = curved.empty or #rows
	if empty == previous then return end
	curved.empty = empty
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

function status_bar_initialize(kind)
	spec = assert(specs[kind], "Unknown player status bar")
	scale = full_scale * (spec.anchor and 0.75 or 1)
	bar_width, bar_height = math.ceil(86 * scale), 176 * scale
	local content = ui.load("arc.xml")
	ui.add(root, content)
	bar = ui.find(content, "status_bar")
	curved = { segments = {} }
	local maximum = ui.find(content, "scale_maximum")
	local zero = ui.find(content, "scale_zero")
	if spec.anchor then
		ui.visible(maximum, false)
		ui.visible(zero, false)
	else
		curved.scale_maximum = maximum
		local left = spec.mirrored and 0 or 48 * scale
		local right = spec.mirrored and 48 * scale or 0
		local align = spec.mirrored and "end" or "start"
		ui.font_size(maximum, 11 * scale)
		ui.font_size(zero, 11 * scale)
		ui.borders(maximum, left, 7 * scale, right, 0)
		ui.align(maximum, align, "start")
		ui.borders(zero, left, 0, right, 7 * scale)
		ui.align(zero, align, "end")
	end
	ui.size(bar, bar_width, bar_height)
	build_arc(content, spec.color)
	ui.size(root, bar_width, bar_height)
	ui.fill_color(root, "")
	ui.composite(root, false)
	ui.place(root, spec.x, spec.anchor and 12 + 176 * full_scale or 5)
	local handles = build_input(ui.find(bar, "input_regions"))
	restore_position, update_tooltip = ra_attach_curved_drag(root, handles, ui.find(bar, "position_menu"), kind, spec, placement)
end

function status_bar_apply(reading, shadowknowledge)
	show_arc_fill(reading.fraction)
	if curved.scale_maximum then
		local maximum = reading.maximum_known and tostring(reading.maximum) or "--"
		if curved.maximum ~= maximum then
			ui.text(curved.scale_maximum, maximum)
			curved.maximum = maximum
		end
	end
	update_tooltip((shadowknowledge and "Shadowknowledge" or spec.label) .. ": " .. Vitals.reading_text(reading))
end
