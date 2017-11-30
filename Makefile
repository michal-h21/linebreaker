all: plain-linebreak.pdf plain.pdf latex-pokus.pdf
	mogrify -format png *.pdf

plain-linebreak.pdf: plain-linebreak.tex linebreaker.lua
	luatex $<
	
plain.pdf: plain-linebreak.tex linebreaker.lua
	luatex -jobname=plain '\def\ignorelinebreker{}\input{$<}'

latex-pokus.pdf: latex-pokus.tex
	lualatex $<


