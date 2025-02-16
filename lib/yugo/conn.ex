defmodule Yugo.Conn do
  @moduledoc false

  @type t :: %__MODULE__{
          tls: boolean,
          socket: :gen_tcp.socket() | :ssl.sslsocket(),
          email: String.t(),
          server: String.t(),
          username: String.t(),
          mailbox: String.t(),
          password: String.t(),
          fetch_interval: integer(),
          fetch_size: integer(),
          caller: pid(),
          next_cmd_tag: integer,
          capabilities: [String.t()],
          got_server_greeting: boolean,
          state: :not_authenticated | :authenticated | :selected,
          tag_map: %{
            String.t() => %{
              command: String.t(),
              on_response: (__MODULE__.t(), :ok | :no | :bad -> __MODULE__.t())
            }
          },
          applicable_flags: [String.t()],
          permanent_flags: [String.t()],
          num_exists: nil | integer,
          num_recent: nil | integer,
          first_unseen: nil | integer,
          uid_validity: nil | integer,
          uid_next: nil | integer,
          mailbox_mutability: :read_only | :read_write,
          idling: boolean,
          idle_timer: reference() | nil,
          expiration_timer: reference() | nil, 
          fetch_timer: reference() | nil,
          auth_timer: reference() | nil,
          idle_timed_out: boolean,
          unprocessed_messages: %{integer: %{}},
          ssl_verify: :verify_none | :verify_peer,
          
        }

  @derive {Inspect, except: [:password]}
  @enforce_keys [:tls, :socket, :username, :password, :server, :mailbox, :ssl_verify]
  defstruct [
    :tls,
    :socket,
    :email,
    :server,
    :username,
    :mailbox,
    # only stored temporarily; gets cleared from memory after sending LOGIN
    :password,
    :ssl_verify,
    :caller,
    :fetch_interval,
    :fetch_size,
    next_cmd_tag: 0,
    capabilities: [],
    got_server_greeting: false,
    state: :not_authenticated,
    tag_map: %{},
    applicable_flags: [],
    permanent_flags: [],
    num_exists: nil,
    num_recent: nil,
    first_unseen: nil,
    uid_validity: nil,
    uid_next: nil,
    mailbox_mutability: nil,
    idling: false,
    idle_timer: nil,
    expiration_timer: nil, 
    fetch_timer: nil,
    auth_timer: nil,
    idle_timed_out: false,
    unprocessed_messages: %{}
  ]
end
