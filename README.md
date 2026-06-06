# Synapse

Servicio de mensajería en tiempo real de **ZEA Platform**. Backend de chat que conecta usuarios humanos con agentes de IA (Glia) mediante WebSockets, autenticándose contra Thalamus.

## Arquitectura

```
Cliente (WS/REST) ──► Synapse ──► PostgreSQL
                          │
                          ├── Thalamus (auth JWT + resolución de usuarios)
                          └── Glia (forward a agentes IA)
```

- **API REST JSON** para conversaciones y mensajes (CRUD)
- **WebSocket Channels** para mensajería en tiempo real (envío, recepción, typing indicators)
- **GenServer por conversación**: un proceso OTP aislado por conversación activa, con auto-shutdown a los 30 min de inactividad
- **@menciones**: extrae `@username` del contenido, resuelve contra Thalamus y forwardea a Glia si el mencionado es un agente

## Stack

| Capa | Tecnología |
|---|---|
| Framework | Phoenix 1.8 (API + Channels) |
| Base de datos | PostgreSQL (Ecto) |
| Tiempo real | WebSockets (Phoenix Channels) |
| PubSub | Phoenix.PubSub |
| Auth | JWT contra JWKS de Thalamus (`Joken`) |
| HTTP client | Req |
| Jobs | Oban 2.18 |
| Deployment | Docker multi-stage (Alpine) |

## Requisitos

- Elixir ~> 1.15
- PostgreSQL
- Thalamus (servicio de auth) corriendo o accesible

## Setup local

```bash
mix setup          # deps.get + ecto.create + ecto.migrate + seeds
mix phx.server     # arranca en localhost:4003
```

## Integración en otras apps

Synapse es un **servicio**. Las apps se conectan vía SDK, sin tocar este código.

**Prerrequisito:** la app ya debe estar integrada con Thalamus (tener un JWT).

### React / Vite / TypeScript

```bash
npm install github:zeacl/synapse-js
```

```ts
import { SynapseClient, useConversation } from '@zea.cl/synapse-js'

// Inicializar (el token lo obtienen de Thalamus, ya lo tienen)
const synapse = new SynapseClient({
  token: jwtFromThalamus,
  baseUrl: import.meta.env.VITE_SYNAPSE_URL || 'http://localhost:4003',
})

// REST
const conversations = await synapse.conversations.list()
const conv = await synapse.conversations.create({
  type: 'dm',
  participantIds: ['user_carlos'],
})
const { data: messages, cursor } = await synapse.messages.list(conv.id, { limit: 50 })

// Real-time + React hook
function Chat({ convId }: { convId: string }) {
  const { messages, send, typing, typingUsers, loadMore, hasMore, loading } =
    useConversation(synapse, convId)

  if (loading) return <Loading />
  return (
    <div>
      {hasMore && <button onClick={loadMore}>Más</button>}
      {messages.map(m => <Bubble key={m.id} msg={m} />)}
      {typingUsers.length > 0 && <Typing />}
      <Input onSend={send} onType={typing} />
    </div>
  )
}
```

SDK JS: [github.com/zeacl/synapse-js](https://github.com/zeacl/synapse-js)

### Phoenix / Elixir

```elixir
# mix.exs
{:synapse_client, github: "zeacl/synapse_client"}
```

```elixir
# Arrancar el cliente (en tu supervision tree)
{:ok, client} = SynapseClient.start_link(
  name: MiApp.SynapseClient,
  token: jwt_from_thalamus,
  base_url: "http://localhost:4003"
)

# REST
{:ok, conversations} = SynapseClient.list_conversations(client)
{:ok, conv} = SynapseClient.create_conversation(client,
  type: :dm, participant_ids: ["user_carlos"])
{:ok, messages, cursor} = SynapseClient.list_messages(client, conv_id, limit: 50)

# Real-time
SynapseClient.subscribe(client, conv_id)
SynapseClient.send_message(client, conv_id, "hola @carlos")

receive do
  {:new_message, msg} -> IO.puts("#{msg.sender_id}: #{msg.content}")
end
```

SDK Elixir: [github.com/zeacl/synapse_client](https://github.com/zeacl/synapse_client)

## API

### REST (JSON)

| Método | Ruta | Autenticación |
|---|---|---|
| `GET` | `/health` | Pública |
| `GET` | `/conversations` | Bearer JWT |
| `POST` | `/conversations` | Bearer JWT |
| `GET` | `/conversations/:id` | Bearer JWT |
| `GET` | `/conversations/:id/messages?before=ISO8601&limit=50` | Bearer JWT |
| `POST` | `/conversations/:id/messages` | Bearer JWT |

### WebSocket

```
ws://localhost:4003/socket/websocket?token=<JWT>
```

Canal: `conversation:<uuid>`

Eventos entrantes: `send_message`, `typing`
Eventos salientes: `new_message`, `typing_start`, `typing_stop`

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `PORT` | `4003` | Puerto HTTP |
| `DATABASE_URL` | — | URL de PostgreSQL (prod) |
| `THALAMUS_JWKS_URL` | `http://thalamus:4000/.well-known/jwks.json` | JWKS endpoint |
| `THALAMUS_API_URL` | `http://thalamus:4000` | API de Thalamus |
| `SECRET_KEY_BASE` | — | Secret de Phoenix (prod) |

## Tests

```bash
mix test                # todos los tests
mix test --failed       # re-ejecuta fallidos
mix precommit           # compile --warning-as-errors + deps.unlock + format + test
```

## Deploy

```bash
docker build -t synapse .
docker run -p 4003:4003 -e DATABASE_URL=... -e SECRET_KEY_BASE=... synapse
```

El entrypoint ejecuta migraciones automáticamente antes de arrancar.
