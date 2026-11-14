## A provider of voice.v1 from a speech engine on the daemon's machine. Pure:
## it builds the engine's requests from an utterance's audio and reads its
## answers, and the daemon sends and receives them.
package [LocalSpeech] { cap: "../../capabilities/main.roc" }
