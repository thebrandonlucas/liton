## What the Review surface (docs/research/surfaces.md, Review) keeps in
## this browser, apart from the review the daemon stores: the scope its
## parts show, the folders its navigator folds, and the cards its view is
## asked to scroll to (`scroll`, by their references), counted by `serial`.
import cap.WorkspaceGit

ReviewDesk := [].{

	State : { scope : WorkspaceGit.Scope, folded : List(Str), scroll : { serial : U64, refs : List(Str) } }

	## The uncommitted changes, every folder open, until changed.
	initial : State
	initial = { scope: Uncommitted, folded: [], scroll: { serial: 0, refs: [] } }

	## Folds a folder of the navigator, or unfolds it.
	toggle_folder : State, Str -> State
	toggle_folder = |desk, path| { ..desk, folded: if (desk.folded.contains(path)) desk.folded.drop_if(|folded| folded == path) else desk.folded.append(path) }

	## Asks the view to scroll to the elements `refs` names.
	scrolled_to : State, List(Str) -> State
	scrolled_to = |desk, refs| { ..desk, scroll: { serial: desk.scroll.serial + 1, refs } }

	## The reference of a Review pane's card of a file.
	card_ref : Str, Str -> Str
	card_ref = |pane_id, path| "${pane_id}:${path}"
}
