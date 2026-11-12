## A capability is a named, versioned interface, such as `chat` version 1.
## A widget requires capabilities; a provider supplies them.
Capability := [].{
	Id : { name : Str, version : U32 }

	chat_v1 : Id
	chat_v1 = { name: "chat", version: 1 }

	## `chat.v1`, as the docs and errors name it.
	to_str : Id -> Str
	to_str = |id| "${id.name}.v${id.version.to_str()}"

	## Whether what is advertised serves what is required: the same name and
	## version.
	satisfies : List(Id), Id -> Bool
	satisfies = |advertised, required| advertised.contains(required)
}

expect Capability.to_str(Capability.chat_v1) == "chat.v1"
expect Capability.satisfies([Capability.chat_v1], { name: "chat", version: 1 })
expect !Capability.satisfies([Capability.chat_v1], { name: "chat", version: 2 })
expect !Capability.satisfies([], Capability.chat_v1)
