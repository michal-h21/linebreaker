all: plain-linebreak.pdf plain.pdf latex-pokus.pdf linebreaker-doc.pdf
	mogrify -format png *.pdf

plain-linebreak.pdf: plain-linebreak.tex linebreaker.lua
	luatex $<
	
plain.pdf: plain-linebreak.tex linebreaker.lua
	luatex -jobname=plain '\def\ignorelinebreker{}\input{$<}'

latex-pokus.pdf: latex-pokus.tex
	lualatex $<

VERSION:= undefined
DATE:= undefined

ifeq ($(strip $(shell git rev-parse --is-inside-work-tree 2>/dev/null)),true)
	VERSION:= $(shell git --no-pager describe --abbrev=0 --tags --always )
	DATE:= $(firstword $(shell git --no-pager show --date=short --format="%ad" --name-only))
endif


linebreaker-doc.pdf: linebreaker-doc.tex linebreaker.sty linebreaker.lua
	latexmk -pdf -pdflatex='lualatex "\def\version{${VERSION}}\def\gitdate{${DATE}}\input{%S}"' $<
