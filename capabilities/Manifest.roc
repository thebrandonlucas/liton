## What a daemon advertises: its providers and the capabilities each supplies.
## The UI filters its widget palette by it.
import Capability

Manifest := [].{
	Provider : { id : Str, name : Str, capabilities : List(Capability.Id) }

	Advertised : { protocol : U32, providers : List(Provider) }

	## The version of the daemon's wire protocol these types describe.
	protocol : U32
	protocol = 1

	## Every capability some provider supplies, each once.
	capabilities : Advertised -> List(Capability.Id)
	capabilities = |advertised|
		advertised.providers.fold(
			[],
			|found, provider|
				provider.capabilities.fold(
					found,
					|so_far, id| if (so_far.contains(id)) so_far else so_far.append(id),
				),
		)

	## The providers that supply a capability, as `merged` views list sources.
	providers_of : Advertised, Capability.Id -> List(Provider)
	providers_of = |advertised, id|
		advertised.providers.keep_if(|provider| provider.capabilities.contains(id))
}

mock : Manifest.Provider
mock = { id: "mock", name: "Mock", capabilities: [Capability.chat_v1] }

expect Manifest.capabilities({ protocol: 1, providers: [mock, mock] }) == [Capability.chat_v1]
expect Manifest.providers_of({ protocol: 1, providers: [mock] }, Capability.chat_v1) == [mock]
expect Manifest.providers_of({ protocol: 1, providers: [mock] }, { name: "ci", version: 1 }) == []
