defmodule Yugo.Clients.GoogleOAuthClient do 
  
  use Yugo.Clients.Client

  alias Yugo.Clients.WebClient

  @soh to_string([1])
  @expiration_timeout 1000 * 60 * 59

  @moduledoc """
  A persistent connection to an IMAP server.

      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = [
            {Yugo.Client,
             server: "imap.example.com",
             username: "me@example.com",
             password: "pa55w0rd"
             encryption: "true", 
             port: "993"
             }
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  Starts an IMAP client process linked to the calling process.

  Takes arguments as a keyword list.

  ## Arguments

    * `:username` - Required. Username used to authenticate, it should be the full gmail address.

    * `:password` - Required. Represents the user's refresh token.

    * `:server` - Required. The location of the IMAP server, e.g. `"imap.gmail.com"`.

    * `:tls` - Whether or not to connect using TLS. Defaults to `true`. If you set this to `false`,
    Yugo will make the initial connection without TLS, then upgrade to a TLS connection (using STARTTLS)
    before logging in. Yugo will never send login credentials over an insecure connection.

    * `:port` - The port to connect to the server via. Defaults to `993`.

    * `:mailbox` - The name of the mailbox to monitor for emails. Defaults to `"INBOX"`.
    The default "INBOX" mailbox is defined in the IMAP standard. If your account has other mailboxes,
    you can pass the name of one as a string. A single [`Client`](`Yugo.Client`) can only monitor a single mailbox -
    to monitor multiple mailboxes, you need to start multiple [`Client`](`Yugo.Client`)s.

  ### Advanced Arguments

    The following options are provided because they can be useful, but in most cases you won't
    need to change them from the default, unless you know what you're doing.

    * `:ssl_verify` - The `:verify` option passed to `:ssl.connect/2`. Can be `:verify_peer` or `:verify_none`.
    Defaults to `:verify_peer`.

  ## Example

  Normally, you do not call this function directly, but rather run it as part of your application's supervision tree.
  See the top of this page for example `Application` usage.
  """

  def handle_info({:do_init, args}, _state) do 
    credentials = Application.get_env(:yugo, :google) 
    token = WebClient.get_access_token(
                      Keyword.get(credentials, :client_id), 
                      Keyword.get(credentials, :client_secret), 
                      args[:password]
                    )
            |> Map.get("access_token")

    {:ok, socket} =
      if args[:tls] do
        :ssl.connect(
          args[:server],
          args[:port],
          ssl_opts(args[:server], args[:ssl_verify])
        ) 
      else
        :gen_tcp.connect(args[:server], args[:port], @common_connect_opts)
      end

    conn = %Conn{
      tls: args[:tls],
      socket: socket,
      server: args[:server],
      username: args[:username],
      password: token,
      mailbox: args[:mailbox],
      ssl_verify: args[:ssl_verify]
    }

    {:noreply, conn}
  end

  def handle_info({:timeout , expiration_timer , :expired_token}, conn) when 
          conn.expiration_timer == expiration_timer, do: 
          exit("expired token") 

  def access_imap_server(conn) do
    core = xoauth_core(conn.username, conn.password)
    conn
    |> send_command(
       "AUTHENTICATE XOAUTH2 #{core}", 
       &on_authenticate_response/3 
      )
    |> Map.put(:token, nil)
  end

  def on_authenticate_response(conn, :ok, _text) do
    expiration_timer = :erlang.start_timer(@expiration_timeout , self() , :expired_token)
    conn
    |> Map.put(:state, :authenticated)
    |> Map.put(:expiration_timer, expiration_timer)
    |> send_command("CAPABILITY", &on_start_response/3)
  end

  def xoauth_core(username, token), do: 
    "user=#{username}" 
    <> 
    @soh
    <>
    "auth=Bearer #{token}" 
    <> 
    @soh 
    <> 
    @soh      
    |> Base.encode64(padding: true)

end
