all: plain-linebreak.pdf plain.pdf
	mogrify -format png *.pdf

plain-linebreak.pdf: plain-linebreak.tex linebreaker.lua
	luatex $<
	
plain.pdf: plain-linebreak.tex linebreaker.lua
	luatex -jobname=plain '\def\ignorelinebreker{}\input{$<}'



