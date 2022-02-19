# The `Linebreaker` package

This package tries to prevent overflow lines in paragraphs or boxes.
It changes the LuaTeX's `linebreak` callback, and it re-typesets the paragraph 
with increased values of `\tolerance` and `\emergencystretch`
until the overflow doesn't happen. If that doesn't help, it chooses the solution
with the lowest badness.


## Usage


     \usepackage{linebreaker}


## Example

<table>
<tr>
<td><img src="plain.png" /></td>
<td><img src="plain-linebreak.png" /></td>
</tr>
<tr><td>Without `linebreaker`</td><td>With `linebreaker`</td></tr>
</table>

## Documentation 

See [the PDF documentation](https://github.com/michal-h21/linebreaker/blob/master/linebreaker-doc.pdf)

## License

Permission is granted to copy, distribute and/or modify this software
under the terms of the LaTeX Project Public License, version 1.3.

