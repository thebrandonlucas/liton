## A code block's lines as tokens, each set by a class; plain text for now.
Highlight := [].{

	## A run of a line and its class ("" for plain text).
	Token : { class : Str, text : Str }

	## The lines of a block of code in `language` (a fence's info word).
	lines : Str, List(Str) -> List(List(Highlight.Token))
	lines = |_language, source| source.map(|line| [{ class: "", text: line }])
}
