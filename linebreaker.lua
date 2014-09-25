local linebreaker = {}

-- max allowed value of tolerance
linebreaker.max_tolerance = 9999
-- line breaking function is customizable
linebreaker.breaker = tex.linebreak -- linebreak function
linebreaker.max_cycles = 30 -- max # of attempts to find best solution
-- the number is totally arbitrary

-- return array with default parameters
function linebreaker.parameters()
	return {}--{emergencystretch=tex.sp(".5em")}
end

-- function linebreaker.make_default_parameters()
-- 				local parameters = {}
-- 				parameters.pardir = tex.pardir 
-- 				parameters.pretolerance= tex.pretolerance
-- 				parameters.tracingparagraphs= tex.tracingparagraphs
-- 				parameters.tolerance= tex.tolerance
-- 				parameters.looseness= tex.looseness
-- 				parameters.hyphenpenalty= tex.hyphenpenalty
-- 				parameters.exhyphenpenalty= tex.exhyphenpenalty
-- 				parameters.pdfadjustspacing= tex.pdfadjustspacing
-- 				parameters.adjdemerits= tex.adjdemerits
-- 				parameters.pdfprotrudechars= tex.pdfprotrudechars
-- 				parameters.linepenalty= tex.linepenalty
-- 				parameters.lastlinefit= tex.lastlinefit
-- 				parameters.doublehyphendemerits = tex.doublehyphendemerits 
-- 				parameters.finalhyphendemerits= tex.finalhyphendemerits
-- 				parameters.hangafter= tex.hangafter
-- 				parameters.interlinepenalty= tex.interlinepenalty
-- 				parameters.clubpenalty= tex.clubpenalty
-- 				parameters.widowpenalty= tex.widowpenalty
-- 				parameters.brokenpenalty= tex.brokenpenalty
-- 				parameters.emergencystretch= tex.emergencystretch
-- 				parameters.hangindent= tex.hangindent
-- 				parameters.hsize= tex.hsize
-- 				parameters.leftskip= tex.leftskip
-- 				parameters.rightskip= tex.rightskip
-- 				parameters.pdfeachlineheight= tex.pdfeachlineheight
-- 				parameters.pdfeachlinedepth= tex.pdfeachlinedepth
-- 				parameters.pdffirstlineheight= tex.pdffirstlineheight
-- 				parameters.pdflastlinedepth= tex.pdflastlinedepth
-- 				parameters.pdfignoreddimen= tex.pdfignoreddimen
-- 				parameters.parshape= tex.parshape
-- 				return parameters
-- end
-- 

-- diagnostic function for traversing nodes returned by linebreaking
-- function. only top level nodes are processed, not sublists
function linebreaker.traverse(head)
	--for n in node.traverse(node.tail(head).head) do
	for n in node.traverse(head) do
		print(n.id, n.subtype)
		if n.id == 10 then
			local x = n.spec or {}
			--x.shrink = 111222
			print("glue", x.shrink,x.stretch)
		end
	end
	print "****************"
	return head
end


local char = unicode.utf8.char
local glyph_id = node.id("glyph")

-- get text content of node list
local function get_text(line)
	local t = {}
	for n in node.traverse(line) do
		if n.id == 10 then t[#t+1] = " "
		elseif n.id == glyph_id then t[#t+1] = char(n.char or "?") 
		end
	end
	return table.concat(t)
end

-- find badness of a line
function linebreaker.par_badness(head)
	local n = 0
	for line in node.traverse_id(0, head) do
		print(get_text(line.head), line.glue_order, line.glue_sign, line.glue_set)
		-- glue_sign: > 0 = normal, 1 = stretch,  2 = shrink
		-- we count only shrink, but stretch may result in overfull box as well
		-- I just don't know, how to detect which value of glue_set means error
		if line.glue_sign == 2 and line.glue_set >= 1 then n = n + 1 end
	end;
	return n
end

-- we have table with guessed param tables. we loop over them and find one with
-- lowest value of badness. this situation shouldn't happen, as at the moment
-- tolerance may be as high as 9999 and this should fix all overfulls
-- this code is remain of older method of guessing right value of tolerance
local function find_best(params)
	local min = 10000 -- arbitrary high value
	local n = params[1] or {}
	for _, p in ipairs(params) do
		local badness = p.badness or min
		if badness <= min then 
			n = p
			min = badness
		end
	end
	print "best solution"
	for k,v in pairs(n) do 
		print(k,v)
	end
	return n
end

-- all glue_spec nodes has .width key, but it is the same all the time. real
-- width depends on line shrink and stretch
-- this will be used in river detection
local function glue_calc(n, sign,set)
 	-- function for calculating glue width
 	if sign ==2 then
 		size=n.spec.width - n.spec.shrink*set
 	else
 		size=n.spec.width + n.spec.stretch*set
 	end
	return size
end


-- calculate new tolerance
-- max_tolerance / max_cycles is added to the current tolerance value
local function calc_tolerance(previous)
  local previous = previous or tex.tolerance
	local max_cycles = linebreaker.max_cycles
	local max_tolerance = linebreaker.max_tolerance 
  local new =  previous + (max_tolerance / max_cycles)-- + math.sqrt(previous * 4)
	return (new < max_tolerance) and new or max_tolerance
end


function linebreaker.best_solution(par, parameters)
	-- save current node list, because call to the linebreaker modifies it
	-- and we wouldn't be able to run it multiple times
	local head = node.copy_list(par)
	-- this shouldn't happen
	if #parameters > linebreaker.max_cycles then
		print "max cycles found"
		return linebreaker.breaker(head,find_best(parameters))
	end
	local params = parameters[#parameters]	-- newest parameters are last in the
	-- table
	local newparams =  {}
	-- break paragraph
	local newhead, info = linebreaker.breaker(head, params)
	-- calc badness
	local badness = linebreaker.par_badness(newhead)
	params.badness =  badness
	print("badness", badness, tex.hfuzz, tex.tolerance)
	-- [[
	if badness > 0 then
		-- calc new value of tolerance
		local tolerance = calc_tolerance(params.tolerance) -- or 10000 
		print("tolerance", tolerance)
		-- save tolerance to newparams so this value will be used in next run
		newparams.tolerance = tolerance 
		table.insert(parameters, newparams)
		print("high badness", badness)
		-- run linebreaker again
		return linebreaker.best_solution(par, parameters)
	end
	print "normal return"
	--]]
	return newhead, info
end

-- this is just reporting function which print lines with glue widths.
-- this may be useful in river detection
local function glue_width(head)
	for n in node.traverse_id(0, head) do
		local t = {}
		local set = n.glue_set
		local sign = n.glue_sign
		for x in node.traverse(n.head) do
			if x.id == 10 then
				local g = x.spec
				local size = glue_calc(x, sign, set)
				t[#t+1] = ":"..size.."."
			elseif x.id == 37 then
				t[#t+1] = char(x.char)
			end
		end
		print(table.concat(t))
	end
end

function linebreaker.linebreak(head,is_display)
	local parameters = linebreaker.parameters()
	local newhead, info = linebreaker.best_solution(head, {parameters}) 
	--print(tex.tolerance,tex.looseness, tex.adjdemerits, info.looseness, info.demerits)
	glue_width(newhead)
	tex.nest[tex.nest.ptr].prevdepth=info.prevdepth
	tex.nest[tex.nest.ptr].prevgraf=info.prevgraf
	--return linebreaker.traverse(add_parskip(newhead))
	return newhead
end


return linebreaker

