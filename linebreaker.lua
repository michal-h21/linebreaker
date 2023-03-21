--  linebreaker.lua
-- 
--  (c) Michal Hoftich <michal.h21@gmail.com>
-- 
--  This program can be redistributed and/or modified under the terms
--  of the LaTeX Project Public License Distributed from CTAN archives
--  in directory macros/latex/base/lppl.txt.

local linebreaker = {}

local hlist_id = node.id "hlist"
local glyph_id = node.id "glyph"
local glue_id = node.id "glue"
local vlist_id = node.id "vlist"
local maxval = 0x10FFFF

local fonts = fonts or {}
fonts.hashes = fonts.hashes or {}
local font_identifiers = fonts.hashes.identifiers or {}


-- debugging function, it can be redefined to print debug info if needed
-- it discards arguments by default
function linebreaker.debug_print(...)
  if linebreaker.debug then
    print(table.concat({...}, "\t"))
  end
end

linebreaker.debug = false

-- max allowed value of tolerance
linebreaker.max_tolerance = 8189 -- maximal possible value of tolerance (thanks to Jan Šustek for pointing that out)
-- maximal allowed emergencystretch
linebreaker.max_emergencystretch = tex.sp("3em")
-- line breaking function is customizable
linebreaker.breaker = tex.linebreak -- linebreak function
linebreaker.max_cycles = 30 -- max # of attempts to find best solution
														-- the number is totally arbitrary

linebreaker.boxsize = 65536 -- it is used in river detection. default box size is 1pt. 
														-- value is in scaled points
linebreaker.vertical_point = tex.baselineskip.width -- vertical matrix
linebreaker.previous_points = linebreaker.vertical_point / linebreaker.boxsize
														-- number of
 														-- points which will be taken into account in 
														-- calculating river value. these points will
														-- be processed in both directions
-- factor which will multiply the parindent value to get the minimal allowed width
-- of a last line in a paragraph
linebreaker.width_factor = 1.5
-- will be linebreaker active?
linebreaker.active = true

-- use cubic method for tolerance calculation
linebreaker.use_cubic = false
-- return array with default parameters
function linebreaker.parameters()
	return {
    pardir = tex.pardir
    ,pretolerance = tex.pretolerance
    ,tracingparagraphs=tex.tracingparagraphs
    ,tolerance=tex.tolerance
    ,looseness=tex.looseness
    ,hyphenpenalty=tex.hyphenpenalty
    ,exhyphenpenalty=tex.exhyphenpenalty
    ,pdfadjustspacing=tex.pdfadjustspacing
    ,adjdemerits=tex.adjdemerits
    ,pdfprotrudechars=tex.pdfprotrudechars
    ,linepenalty=tex.linepenalty
    ,lastlinefit=tex.lastlinefit
    ,doublehyphendemerits=tex.doublehyphendemerits
    ,finalhyphendemerits=tex.finalhyphendemerits
    ,hangafter=tex.hangafter
    ,interlinepenalty=tex.interlinepenalty
    ,clubpenalty=tex.clubpenalty
    ,widowpenalty=tex.widowpenalty
    ,brokenpenalty=tex.brokenpenalty
    ,emergencystretch=tex.emergencystretch
    ,hangindent=tex.hangindent
    ,hsize=tex.hsize
    ,leftskip=tex.leftskip
    ,rightskip=tex.rightskip
    ,parshape=tex.parshape
  } 
end

-- diagnostic function for traversing nodes returned by linebreaking
-- function. only top level nodes are processed, not sublists
function linebreaker.traverse(head)
	--for n in node.traverse(node.tail(head).head) do
	for n in node.traverse(head) do
		linebreaker.debug_print(n.id, n.subtype)
		if n.id == 10 then
			local x = n.spec or {}
			--x.shrink = 111222
			linebreaker.debug_print("glue", x.shrink,x.stretch)
		end
	end
	linebreaker.debug_print "****************"
	return head
end


local utfchar = unicode.utf8.char

local getchar = function(n)
  local t = {}
  local xchar = font_identifiers[n.font].characters[n.char].unicode

  if type(xchar) == "table" then
    for k,v in pairs(xchar) do
      t[#t+1] = utfchar(v)
    end
  else
    -- 8-bit fonts don't contain the unicode value, so just return the char
    -- value of node. In some cases it will be good, for math it will be mostly wrong
    return utfchar(xchar or n.char)
  end
  return table.concat(t)
end

-- get text content of node list
local function get_text(line)
	local t = {}
	for n in node.traverse(line) do
		if n.id == glue_id then t[#t+1] = " "
		elseif n.id == glyph_id then t[#t+1] = getchar(n) 
    elseif n.id == hlist_id or n.id == vlist_id then t[#t+1] = get_text(n.head)
		end
	end
	return table.concat(t)
end

-- find badness of a line
function linebreaker.par_badness(head)
	local n = 0
	for line in node.traverse_id(hlist_id, head) do
		-- print(get_text(line.head), line.glue_order, line.glue_sign, line.glue_set)
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
	linebreaker.debug_print "best solution"
  local ignored_types = {userdata=true, table = true}
	for k,v in pairs(n) do 
    -- we must ignore some properties in the params table,
    -- as they produce errors when used in debug_print,
    -- and they are not interesting for debugging anyway
    if not ignored_types[type(v)]  then
      linebreaker.debug_print(k,v)
    end
	end
	return n
end

-- all glue_spec nodes has .width key, but it is the same all the time. real
-- width depends on line shrink and stretch
-- this will be used in river detection
local function glue_calc(n, sign,set)
  -- function for calculating glue width
  local size
  if sign ==2 then
    size=n.spec.width - n.spec.shrink*set
  else
    size=n.spec.width + n.spec.stretch*set
  end
  return size
end


local function cube_root(num)
  return num ^(1/3)
end


-- calculate new tolerance using method suggested by Jan Šustek
local function calc_tolerance_cubic(previous, step)
  local previous = previous or tex.tolerance
  local max_cycles = linebreaker.max_cycles
  local max_tolerance = linebreaker.max_tolerance 
  local new = 100 * (cube_root(previous / 100) + (cube_root(max_tolerance/100) - cube_root(previous/100)) * (step/max_cycles))^3
  -- local new =  previous + (max_tolerance / max_cycles)-- + math.sqrt(previous * 4)
  return (new < max_tolerance) and new or max_tolerance
end

-- max_tolerance / max_cycles is added to the current tolerance value
local function calc_tolerance(previous, step)
  local previous = previous or tex.tolerance
  local max_cycles = linebreaker.max_cycles
  local max_tolerance = linebreaker.max_tolerance 
  local new =  previous + (max_tolerance / max_cycles)-- + math.sqrt(previous * 4)
  return (new < max_tolerance) and new or max_tolerance
end

-- river detection -- it doesn't work at the moment, maybe in the future?
-- idea is following:
-- 1. count widths of words and spaces 
-- 2. divide widths to segments of some width (1pt?)
-- 3. assign number to segments: full glyph in the midle of a word:0
-- 						full glue: 1
-- 						edges of words: fraction depending on glyph dimensions
-- 							(it would be nice to incorporate glyph shapes, but it is 
-- 							unrealistic, we don't have access)
-- 4. add numbers from previous line, probably sum of segments in some 
-- 			distance (baselineskip / segments per sp = 45°?)
-- 5. sum segments for a glue / glue width = river ratio?
-- 6. find right threshold for telling which value of river ratio is a real
--    river
-- 7. calculate river ratio for whole paragraph (sum of over threshold 
-- 		river ratios?)
-- I am not a mathematician, so I don't know whether this method is accurate,
-- 		correct, or efficient, 
--
--
function linebreaker.detect_rivers(head)
  local lines = {} -- 
  local boxsize = linebreaker.boxsize
  local vertical_point = linebreaker.vertical_point
  local previous_points = math.ceil(linebreaker.previous_points)
  -- calculate river for current node `n` and insert values to 
  local calc_river = function(line,n, lines)
    -- get previous line
    local previous = lines and lines[#lines] or {}
    local get_point = function(i)
      return previous[i] or 0
    end
    local x = #line
    --print("soucasna delka line", x)
    local sum = 0
    for i = 1, #n do
      local v = n[i] or 0
      if v > 0 then
        v = v + get_point(i)
        -- ve add values from previous line
        --for c = 1, previous_points do
        local c = previous_points
        v = v + (get_point(i+x+c)) + (get_point(i+x-c))
        --print("adding",v)
        --end
      end
      line[i+x] = v
      sum = sum + v
      --print("Calculate for", i,v)
      --print("celkem v", i+x,v)
    end
    return line, sum / #n
  end
  for n in node.traverse_id(0, head) do
    local line = {}
    -- glue parameters
    local set = n.glue_set
    local sign = n.glue_sign
    local order =  n.glue_order
    local first_node = n.head
    local first_glyph = nil
    local first = true
    local word_count = 0
    local last_glyph = nil
    local last_glue = n.head
    local position = 0
    local remain = 0
    local get_glyph_black =  function(glyph)
      -- only calculate blackness for glyphs
      if glyph and glyph.id == glyph_id then
        local w,h,d = node.dimensions(glyph, glyph.next)
        -- 1 is maximal white
        local blackness = 1 - ((h+d) / vertical_point)
        -- print(char(glyph.char), blackness) return w / boxsize or 0, blackness
      end
      return 0,0
    end
    -- get width of nodes
    local get_width = function(start,fin)
      local w = node.dimensions(set,sign,order,start, fin) 
      return w / boxsize -- get width in pt
    end
    local add_word = function(start,fin)
      word_count = word_count + 1
      local t = {}
      local width = get_width(start,fin)
      -- first and last glyph are taken into account for blackness calculation
      local w1, f = get_glyph_black(first_glyph) 
      local w2, l = get_glyph_black(last_glyph)
      w1 = math.ceil(w1 + remain)
      w2 = math.ceil(w2)
      if word_count <= 1 then
        w1 = 0
      end
      width = width + remain
      remain = width - math.floor(width)
      width = width - remain
      for i=1, w1 do
        t[#t+1] = f/i -- add more black at the end of glyph
      end
      -- middle of the word
      for i=1, (width-w1-w2) do
        t[#t+1] = 0
      end
      -- last glyph
      for i=1, w2 do
        t[#t+1] = l/(w2-i+1)
      end
      line = calc_river(line, t, lines)
      --print("black", f,l)
    end
    add_glue = function(x)
      local t = {}
      local r
      local width = get_width(x,x.next) + remain
      remain = width - math.floor(width)
      width = width - remain
      for i=1, width do
        t[#t+1] = 1
      end
      --print("glue",#t)
      line, r  = calc_river(line,t, lines)
      if r > 1 then
        local w = node.new("whatsit","pdf_literal")                                                                             
        local color = 1 / r
        w.data = string.format("q 1 %f 1 rg 0 0 m 0 5 l 5 5 l 5 0 l f Q", color)
        -- print("color",w.data)
        node.insert_before(n.head,x,w)
      end
      return r
    end
    for x in node.traverse(n.head) do
      if x.id == glue_id and x.subtype == 0 then
        --print("glue width", get_width(x,x.next))
        add_word(last_glue, x, first_glyph,last_glyph)
        local river_value = add_glue(x)
        -- print("riverness", river_value)
        first = true
        last_glue = x.next -- calculate width of next word from here
      elseif x.id == glyph_id then
        if first then
          first_glyph = x
        end
        first = false
        last_glyph = x
      end
    end
    add_word(last_glue, x, first_glyph, last_glyph)
    --table.insert(lines, calc_river(t,lines))
    --for k,v in pairs(line) do print(k,v) end 
    table.insert(lines,line)
    -- print(table.concat(lines[#lines],","))
    -- local width, h, d = node.dimensions(set, sign, order, n.head, node.tail(n.head))
    -- print(width,table.concat(t))
  end
  return 0
end

-- End of river detection


function linebreaker.last_line_width(head)
  -- measure length of the last line in a paragraph
  local w, w1
  local last = node.tail(head)
  local n = node.copy(last)
  -- last node is not node list, return negative number
  if not n.head then return -1 end
  n.head = node.remove(n.head, node.tail(n.head))
  for x in node.traverse(n.head) do
    if x.id == glue_id then
      if x.subtype == 15 then
        n.head = node.remove(n.head, x)
      end
    end
  end
  -- something went wrong, so discard this solution
  if not n.head or not n.glue_set then return 0 end
  w, _, _ = node.dimensions(n.glue_set, n.glue_sign, n.glue_order, n.head)
  w1, _, _ = node.dimensions(n.glue_set, n.glue_sign, n.glue_order, n)
  return w
end


-- try to linebreak current paragraph with increasing tolerance and
-- emergencystretch
function linebreaker.best_solution(par, parameters, step)
  -- step is used in the tolerance calculation
  local step = (step or 0) + 1
  -- save current node list, because call to the linebreaker modifies it
  -- and we wouldn't be able to run it multiple times
  local head = node.copy_list(par)
  -- this shouldn't happen
  if #parameters > linebreaker.max_cycles then
    -- we couldn't find a solution without badness
    -- break paragraph with the least bad parameters
    return linebreaker.breaker(head,find_best(parameters))
  end
  local params = parameters[#parameters]	-- newest parameters are last in the
  -- table that will be used in recursive invocations of this function
  -- it holds updated parameters
  local newparams =  linebreaker.parameters()
  -- this value is set by hpack_quality callback that is executed by
  -- tex.linebreak when overflow or underflow happens
  linebreaker.badness = 0
  -- break paragraph
  local newhead, info = linebreaker.breaker(head, params)
  -- calc badness -- we don't use this anymore, badness of the currently 
  -- processed node list is set by hpack_filter
  local badness = linebreaker.badness or 0
  -- don't allow lines shorter than the paragraph indent
  local last_line_width = linebreaker.last_line_width(newhead)
  linebreaker.debug_print("last line width", last_line_width, "parindent:", tex.parindent * linebreaker.width_factor)
  if last_line_width > 0 and last_line_width < tex.parindent * linebreaker.width_factor then
    linebreaker.debug_print "too short last line"
    badness = 10000
  end

  params.badness =  badness
  if badness > 0 then
    -- calc new value of tolerance
    local tolerance
    if linebreaker.use_cubic then
      tolerance = calc_tolerance_cubic(params.tolerance, step) -- or 10000 
    else
      tolerance = calc_tolerance(params.tolerance, step) -- or 10000 
    end
    -- save tolerance to newparams so this value will be used in next run
    newparams.tolerance = math.floor(tolerance)
    newparams.emergencystretch = (params.emergencystretch or 0) + linebreaker.max_emergencystretch / linebreaker.max_cycles
    table.insert(parameters, newparams)
    -- run linebreaker again
    return linebreaker.best_solution(par, parameters)
  end
  -- river detection doesn't work, so we don't execute ths code anymore
  -- detect rivers only for paragraphs without overflow boxes
  -- local rivers = linebreaker.detect_rivers(newhead)
  -- print("rivers", rivers)
  -- print "normal return"
  --]]
  return newhead, info
end

-- this is just reporting function which print lines with glue widths.
-- this may be useful in river detection
local function glue_width(head)
  for n in node.traverse_id(hlist_id, head) do
    local t = {}
    local set = n.glue_set
    local sign = n.glue_sign
    local order =  n.glue_order
    for x in node.traverse(n.head) do
      if x.id == glue_id then
        local g = x.spec
        local size = glue_calc(x, sign, set)
        t[#t+1] = ":"..size.."."
      elseif x.id == glyph_id then
        t[#t+1] = getchar(x)
      end
    end
    local width, h, d = node.dimensions(set, sign, order, n.head, node.tail(n.head))
  end
end

local function fix_nest(info)
  tex.nest[tex.nest.ptr].prevdepth=info.prevdepth
  tex.nest[tex.nest.ptr].prevgraf=info.prevgraf
end


-- test whether the current overfull box message occurs inside our linebreaker function
local is_inside_linebreaker = false
function linebreaker.linebreak(head,is_display)
  local parameters = linebreaker.parameters()
  -- we can disable linebreaker processing
  if linebreaker.active == false then
    local newhead, info =  linebreaker.breaker(head, parameters)
    fix_nest(info)
    return newhead
  end
  is_inside_linebreaker = true
  local newhead, info = linebreaker.best_solution(head, {parameters}) 
  is_inside_linebreaker = false
  fix_nest(info)
  return newhead
end

function linebreaker.hpack_quality(incl, detail, head, first, last)
  if not is_inside_linebreaker then
    local detail_msg = incl=="overfull" and "overflow" or "badness"
    linebreaker.debug_print( incl .. " box at lines: " .. first .." -- " .. last ..". " .. detail_msg .. ": " .. detail .."\n text:" .. get_text(head) )
  end
  linebreaker.badness = (linebreaker.badness or 0) + detail
end

-- It seems necessary to call the post_linebreak filter in order to support floats
-- Even if it does nothing but to return the node list. I don't understand why...
function linebreaker.post_linebreak(head)
  return true
end

linebreaker.get_text = get_text

return linebreaker

