## What the Review surface (docs/research/surfaces.md, Review) keeps in
## this browser, apart from the review the daemon stores: the scope its
## parts show, the folders its navigator folds, the cards its view is
## asked to scroll to (`scroll`, by their references), counted by `serial`,
## and the file of the latest until its card is on screen (`scrolling_to`,
## "" for none), and the files whose cards are on screen (`seen`).
import cap.WorkspaceGit

ReviewDesk := [].{

	State : { scope : WorkspaceGit.Scope, folded : List(Str), scroll : { serial : U64, refs : List(Str) }, scrolling_to : Str, seen : List(Str) }

	## The uncommitted changes, every folder open, until changed.
	initial : State
	initial = { scope: Uncommitted, folded: [], scroll: { serial: 0, refs: [] }, scrolling_to: "", seen: [] }

	## Folds a folder of the navigator, or unfolds it.
	toggle_folder : State, Str -> State
	toggle_folder = |desk, path| { ..desk, folded: if (desk.folded.contains(path)) desk.folded.drop_if(|folded| folded == path) else desk.folded.append(path) }

	## Asks the view to scroll to the elements `refs` names, of the file
	## `path`.
	scrolled_to : State, Str, List(Str) -> State
	scrolled_to = |desk, path, refs| { ..desk, scroll: { serial: desk.scroll.serial + 1, refs }, scrolling_to: path }

	## The file in view once the card of `path` comes on screen or leaves
	## it, of those `files` in order: the file scrolled to once its card is
	## on screen, else `focused` until then, else the first on screen, if
	## any is.
	seen_card : State, List(Str), Str, { path : Str, on_screen : Bool } -> { desk : State, focused : Str }
	seen_card = |desk, files, focused, { path, on_screen }| {
		seen = files.keep_if(|file| if (file == path) on_screen else desk.seen.contains(file))
		if desk.scrolling_to.is_empty() {
			{ desk: { ..desk, seen }, focused: seen.first() ?? focused }
		} else if seen.contains(desk.scrolling_to) {
			{ desk: { ..desk, seen, scrolling_to: "" }, focused: desk.scrolling_to }
		} else {
			{ desk: { ..desk, seen }, focused }
		}
	}

	## The reference of a Review pane's card of a file.
	card_ref : Str, Str -> Str
	card_ref = |pane_id, path| "${pane_id}:${path}"
}
