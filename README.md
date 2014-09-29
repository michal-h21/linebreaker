# linebreaking examples

This repository contains experimental linebreaking callback for LuaTeX engine (
it should work with any format). Motivation for this was a
[question](http://tex.stackexchange.com/q/200989/2891) by Frank Mittelbach on
TeX.sx. His idea is to rewrite TeX paragraph building algorithm in Lua, in
order to support river detection and similar tasks, unsupported by standard TeX
linebreaking algorithm.

As complete rewrite of linebreaking algorithm seems to be huge task, I tried
different approach. Several callbacks for working with nodes are provided by
LuaTeX. These are for ligaturing, kerning, before linebreaking, after
linebreaking and callback for doing the linebreaking. Function exists
`tex.linebreak`, which takes node list and table with TeX parameters (lineskip,
baselineskip, tolerance, etc.) New node list with lines broken into horizontal
boxes is returned by this function.

My idea is to process this returned node list, detect problems and call
`tex.linebreak` with different parameters if problems were detected. At the
moment, overflow box detection works somehow, river detection is a proof of
concept and it needs further corrections.

## Usage
