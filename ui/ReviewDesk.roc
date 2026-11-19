## What the Review surface (docs/research/surfaces.md, Review) keeps in
## this browser, apart from the review the daemon stores: the scope its
## parts show, the folders its navigator folds, the cards its view is
## asked to scroll to (`scroll`, by their references), counted by `serial`,
## and the file of the latest until its card is on screen (`scrolling_to`,
## "" for none), the files whose cards are on screen (`seen`), and the
## files marked viewed, which the browser keeps (`viewed_key`), the
## threads its inspector lists: those open, resolved, or all; and the diff
## of each file as each round was sent from here (`rounds`), and whether
## its parts show only the files changed since the latest
## (`since_round`).
import cap.WorkspaceGit

ReviewDesk := [].{

	## What the Review surface keeps, as this module's comment says.
	State : { scope : WorkspaceGit.Scope, folded : List(Str), scroll : { serial : U64, refs : List(Str) }, scrolling_to : Str, seen : List(Str), viewed : List(Viewed), listing : [Open, Resolved, All], rounds : List(Round), since_round : Bool }

	## The files of a context's scope as round `round` was sent, each by its
	## diff's fingerprint (`Viewed`'s).
	##
	## FIXME: the diff between rounds needs the daemon to keep, with each
	## round review.v1 sends, the code it was sent against, and
	## workspace.git.v1 to diff two such trees; no provider offers either
	## yet. Until then this browser keeps which files' diffs it saw at each
	## Send, which tells the files changed since but not how, and is gone on
	## a reload or in another browser.

	## A file of a context's scope marked viewed, by its diff's fingerprint
	## then (`WorkspaceGit.fingerprint`), so a change to it unmarks it.
	Viewed : { context : Str, scope : WorkspaceGit.Scope, path : Str, fingerprint : Str }

	## The key the browser keeps the files viewed under.
	viewed_key : Str
	viewed_key = "liton.review.viewed"

	## The files viewed the browser kept, as `viewed_key` holds them.
	restored : Str -> List(Viewed)
	restored = |text| {
		parsed : Try(List(Viewed), _)
		parsed = Json.parse(text)
		parsed ?? []
	}

	## Marks a file viewed, as its diff is now, or unmarks it.
	toggle_viewed : State, Viewed -> State
	toggle_viewed = |desk, marked| {
		same = |kept| kept.context == marked.context and kept.scope == marked.scope and kept.path == marked.path
		{ ..desk, viewed: if (desk.viewed.contains(marked)) desk.viewed.drop_if(same) else desk.viewed.drop_if(same).append(marked) }
	}

	## The uncommitted changes, every folder open, until changed.
	initial : State
	initial = { scope: Uncommitted, folded: [], scroll: { serial: 0, refs: [] }, scrolling_to: "", seen: [], viewed: [], listing: Open, rounds: [], since_round: Bool.False }

	## A round sent from here: its context, scope and number, and the
	## fingerprint of each of its files' diffs then.
	Round : { context : Str, scope : WorkspaceGit.Scope, round : U32, files : List({ path : Str, fingerprint : Str }) }

	## Keeps a round's files, in place of any kept of the same round.
	sent_round : State, Round -> State
	sent_round = |desk, sent| { ..desk, rounds: desk.rounds.drop_if(|kept| kept.context == sent.context and kept.scope == sent.scope and kept.round == sent.round).append(sent) }

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
