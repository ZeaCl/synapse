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
