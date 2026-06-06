Synapse es un microservicio de mensajería en tiempo real de ZEA Platform. Es un backend **API JSON + WebSocket** (sin frontend HTML, sin LiveViews, sin navegador).

## Project guidelines

- Usá `mix precommit` cuando termines todos los cambios y corregí cualquier problema pendiente
- Usá la librería `:req` (`Req`) para HTTP requests, **evitá** `:httpoison`, `:tesla`, y `:httpc`. Req ya está incluido y es el cliente HTTP preferido
- Synapse **no tiene UI de navegador**. Es un servicio puramente API REST (JSON) + WebSocket Channels. No agregues LiveViews, templates HTML, ni páginas
- Las dependencias `phoenix_live_view` y `phoenix_html` están presentes solo porque son dependencias transitivas de `phoenix_live_dashboard` y del scaffold de Phoenix. No las uses directamente

### Phoenix API guidelines

- Todas las rutas son `pipe_through :api` (JSON) excepto `/health` que es `:public`
- Los controladores siempre devuelven JSON con `conn |> json(%{...})` o `conn |> put_status(code) |> json(%{...})`
- Usá `conn.assigns.user_id` para obtener el usuario autenticado (lo setea `RequireAuth`)
- Las respuestas de error siguen el formato `%{error: "reason"}` o `%{error: "reason", details: %{...}}`
- Las respuestas de datos siguen el formato `%{data: ...}`

### Phoenix Channel guidelines

- Los canales se definen en `SynapseWeb.UserSocket` con el macro `channel`
- El `UserSocket.connect/3` valida JWT contra Thalamus y asigna `user_id`, `name`, `is_agent` al socket
- Los canales suscriben a PubSub en `join/3` para recibir broadcasts
- Usá `push/3` para enviar eventos al cliente, `broadcast/3` para enviar a todos los suscriptores de un tópico
- Los eventos entrantes se manejan con `handle_in/3`, los broadcasts con `handle_info/2`
- **Nunca** uses `assign/3` de LiveView en canales. En canales usá `Phoenix.Socket.assign/3`
- Siempre verificá permisos de participación en `join/3` antes de permitir la conexión

### GenServer / OTP guidelines

- Cada conversación activa tiene su propio `GenServer` (`Synapse.Conversation`), arrancado por `DynamicSupervisor`
- Usá `Registry` (`Synapse.ConversationRegistry`) para localizar procesos por `conv_id`
- Usá `via_tuple/1` para nombrar procesos via Registry: `{:via, Registry, {Synapse.ConversationRegistry, conv_id}}`
- Los GenServer de conversación se auto-apagan tras 30 min de inactividad (`@idle_timeout`)
- Efectos secundarios (forward a Glia, añadir participantes) se ejecutan en `Task.start/1` asíncrono para no bloquear el GenServer
- Usá `Process.send_after/3` para timers (ej: limpiar typing indicator a los 3 segundos)

<!-- usage-rules-start -->
<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->
<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
- Synapse usa `Phoenix.Channel` para WebSockets. Los canales **no usan** `assign/3` de LiveView. Usan `Phoenix.Socket.assign/3`
<!-- phoenix:phoenix-end -->
<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in serializers, ie a conversation serialized with `conv.participants`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- Synapse usa `:binary_id` (UUID) como primary key. Los timestamps son `:utc_datetime`
<!-- phoenix:ecto-end -->
<!-- usage-rules-end -->
