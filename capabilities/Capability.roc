## A capability is a named, versioned interface, such as `chat` version 1.
## A widget requires capabilities; a provider supplies them.
Capability := [].{
	Id : { name : Str, version : U32 }

	chat_v1 : Id
	chat_v1 = { name: "chat", version: 1 }

	attention_v1 : Id
	attention_v1 = { name: "attention", version: 1 }

	workspace_git_v1 : Id
	workspace_git_v1 = { name: "workspace.git", version: 1 }

	workspaces_v1 : Id
	workspaces_v1 = { name: "workspaces", version: 1 }

	files_v1 : Id
	files_v1 = { name: "files", version: 1 }

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
