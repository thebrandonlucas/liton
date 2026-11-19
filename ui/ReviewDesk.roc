## What the Review surface (docs/research/surfaces.md, Review) keeps in
## this browser, apart from the review the daemon stores: the scope its
## parts show.
import cap.WorkspaceGit

ReviewDesk := [].{

	State : { scope : WorkspaceGit.Scope }

	## The uncommitted changes, until another scope is picked.
	initial : State
	initial = { scope: Uncommitted }
}
