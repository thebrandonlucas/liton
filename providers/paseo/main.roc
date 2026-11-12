## A provider of the agents a running Paseo daemon hosts. Pure: it builds
## Paseo's requests and turns its answers into chat.v1 events, and the daemon
## sends and receives them.
package [WebSocket] { cap: "../../capabilities/main.roc" }
