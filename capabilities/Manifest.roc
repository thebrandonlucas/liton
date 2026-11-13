## What a daemon advertises: its providers and the capabilities each supplies.
## The UI filters its widget palette by it.
import Capability

Manifest := [].{
	Provider : { id : Str, name : Str, capabilities : List(Capability.Id) }

	## What `/api/manifest` answers, until the UI moves to `/liton/v1`.
	Advertised : { protocol : U32, providers : List(Provider) }

	## A part that derives the capability it offers from those it uses, as
	## attention.v1 is from chat.v1.
	Transformer : { id : Str, name : Str, offers : Capability.Id, uses : List(Capability.Id) }

	## The topics a capability has, as patterns such as `timeline/<session_id>`.
	Topics : { capability : Capability.Id, patterns : List(Str) }

	## What `GET /liton/v1/manifest` answers. Read as `Advertised`, it lists
	## the providers alone.
	Offered : { protocol : U32, daemon : { id : Str, name : Str }, providers : List(Provider), transformers : List(Transformer), topics : List(Topics) }

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

	## Every capability a provider or a transformer offers, each once.
	offered : Offered -> List(Capability.Id)
	offered = |manifest|
		Manifest.capabilities({ protocol: manifest.protocol, providers: manifest.providers.concat(manifest.transformers.map(|transformer| { id: transformer.id, name: transformer.name, capabilities: [transformer.offers] })) })

	## The ids of the providers and transformers that offer a capability.
	offering : Offered, Capability.Id -> List(Str)
	offering = |{ providers, transformers, .. }, id|
		providers.keep_if(|provider| provider.capabilities.contains(id)).map(|provider| provider.id).concat(transformers.keep_if(|transformer| transformer.offers == id).map(|transformer| transformer.id))

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

attention : Manifest.Transformer
attention = { id: "attention", name: "Attention", offers: Capability.attention_v1, uses: [Capability.chat_v1] }

expect {
	offered = { protocol: 1, daemon: { id: "liton", name: "liton" }, providers: [mock], transformers: [attention], topics: [] }
	Manifest.offered(offered) == [Capability.chat_v1, Capability.attention_v1] and Manifest.offering(offered, Capability.attention_v1) == ["attention"] and Manifest.offering(offered, Capability.chat_v1) == ["mock"]
}
