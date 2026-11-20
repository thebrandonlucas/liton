## A capability is a named, versioned interface, such as `chat` version 1.
## A widget requires capabilities; a provider supplies them.
Capability := [].{

	## A capability's name and version, as `chat.v1` names `chat` version 1.
	Id : { name : Str, version : U32 }

	## Agents' sessions: their timelines, what they ask, and starting one.
	chat_v1 : Id
	chat_v1 = { name: "chat", version: 1 }

	## The inbox of sessions by what needs you, derived from chat.v1.
	attention_v1 : Id
	attention_v1 = { name: "attention", version: 1 }

	## A workspace's git: its status, changes, hunks and commits.
	workspace_git_v1 : Id
	workspace_git_v1 = { name: "workspace.git", version: 1 }

	## The projects and their workspaces that agents work in.
	workspaces_v1 : Id
	workspaces_v1 = { name: "workspaces", version: 1 }

	## The files of a session's or a workspace's directory.
	files_v1 : Id
	files_v1 = { name: "files", version: 1 }

	## Comments on a workspace's lines, sent to an agent as a review.
	review_v1 : Id
	review_v1 = { name: "review", version: 1 }

	## Issues and tickets, and changing their status, assignees and labels.
	tickets_v1 : Id
	tickets_v1 = { name: "tickets", version: 1 }

	## Prompts that run on a cadence, and their runs.
	schedules_v1 : Id
	schedules_v1 = { name: "schedules", version: 1 }

	## Speech to text, from audio the client sends in chunks.
	voice_v1 : Id
	voice_v1 = { name: "voice", version: 1 }

	## Rooms of people and agents, and their messages.
	rooms_v1 : Id
	rooms_v1 = { name: "rooms", version: 1 }

	## The daemons the daemon connects to, changed while it runs.
	hosts_v1 : Id
	hosts_v1 = { name: "hosts", version: 1 }

	## What the accounts agents run under have used of their plans.
	usage_v1 : Id
	usage_v1 = { name: "usage", version: 1 }

	## `chat.v1`, as the docs and errors name it.
	to_str : Id -> Str
	to_str = |id| "${id.name}.v${id.version.to_str()}"

	## The capability a name such as `chat.v1` names.
	from_str : Str -> Try(Id, [NotACapability])
	from_str = |text| {
		parts = text.split_on(".")
		version = parts.last() ?? ""
		name = Str.join_with(parts.drop_last(1), ".")
		match U32.from_str(version.drop_prefix("v")) {
			Ok(number) if version.starts_with("v") and name != "" => Ok({ name, version: number })
			_ => Err(NotACapability)
		}
	}

	## Whether what is advertised serves what is required: the same name and
	## version.
	satisfies : List(Id), Id -> Bool
	satisfies = |advertised, required| advertised.contains(required)
}

expect Capability.to_str(Capability.chat_v1) == "chat.v1"
expect Capability.satisfies([Capability.chat_v1], { name: "chat", version: 1 })
expect !Capability.satisfies([Capability.chat_v1], { name: "chat", version: 2 })
expect !Capability.satisfies([], Capability.chat_v1)
expect Capability.from_str("workspace.git.v1") == Ok(Capability.workspace_git_v1)
expect Capability.from_str(Capability.to_str(Capability.chat_v1)) == Ok(Capability.chat_v1)
expect ["chat", "chat.1", ".v1", "chat.vx", "chat.v"].map(Capability.from_str).all(|parsed| parsed.is_err())
