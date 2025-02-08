defmodule Yugo.Clients.Client do 

  defmacro __using__(_) do   
    quote do

        use GenServer 
        alias Yugo.{Conn, Parser, Registry, Messages, Utils, Presence.ImapPresences}

        @common_connect_opts [packet: :line, active: :once, mode: :binary]
        @noop_poll_interval 5000
        @idle_timeout 1000 * 60 * 27
        @fetch_timeout 1000 * 60 * 5

        @default_start_time_fetch_interval 10
        @default_periodic_fetch_interval 2

        @spec start_link(
                email: String.t(),
                server: String.t(),
                username: String.t(),
                password: String.t(),
                tls: String.t(),
                port: 1..65535,
                ssl_verify: :verify_none | :verify_peer,
                mailbox: String.t()
                ) :: GenServer.on_start()

        def start_link(args) do
          for required <- [:email, :server, :username, :password, :tls, :port] do
            Keyword.has_key?(args, required) || raise "Missing required argument `:#{required}`."
          end

          args =
            args
            |> Keyword.update!(:server, &to_charlist/1)
            |> Keyword.update!(:tls, &String.to_atom/1) 
            |> Keyword.update!(:port, &String.to_integer/1)
            |> Keyword.put_new(:mailbox, "INBOX")
            |> Keyword.put_new(:ssl_verify, :verify_none)
            
            args[:ssl_verify] in [:verify_peer, :verify_none] ||
            raise ":ssl_verify option must be one of: :verify_peer, :verify_none"

            GenServer.start_link(__MODULE__, args)
        end

        def ssl_opts(server, ssl_verify),
          do:
            [
              server_name_indication: server,
              verify: ssl_verify,
              cacerts: :public_key.cacerts_get()
            ] ++ @common_connect_opts

        @impl true
        def init(args) do
          send(self(), {:do_init, args})
          {:ok, %{}}
        end

        @impl true
        def terminate(_reason, conn) do
          conn
          |> send_command("LOGOUT")
        end

        @impl true
        def handle_info({socket_kind, socket, data}, conn) when 
          socket_kind in [:ssl, :tcp] and 
          socket == conn.socket 
            do
              data = recv_literals(conn, [data])

              # we set [active: :once] each time so that we can parse packets that have synchronizing literals spanning over multiple lines
              :ok = activate_socket_once(conn)

              %Conn{} = conn = handle_packet(data, conn)

              {:noreply, conn}
        end

        @impl true
        def handle_info({close_message, _sock}, conn)
          when close_message in [:tcp_closed, :ssl_closed] do
            {:stop, :normal, conn}
        end

        @impl true
        def handle_info(:poll_with_noop, conn) do
          Process.send_after(self(), :poll_with_noop, @noop_poll_interval)

          conn =
            if command_in_progress?(conn) do
              conn
            else
              conn
              |> send_command("NOOP")
            end

          {:noreply, conn}
        end

        @impl true
        def handle_info(:idle_timeout, conn) do
          conn =
            %{conn | idle_timed_out: true}
            |> cancel_idle()

          {:noreply, conn}
        end

##################### handling infos only if the server is free #######################

        def handle_info({:timeout , fetch_timer , :fetch_messages}, conn) when 
          conn.state == :running and 
          conn.fetch_timer == fetch_timer, do:
            {:noreply, conn 
                       |> Map.put(:state, :maybe_fetching)
                       |> cancel_idle()
                       |> on_start_response(:ok, :ok)
            }

        def handle_info({caller, :manual_fetch, fetch_interval}, conn) when 
          conn.state == :running do
            :erlang.cancel_timer(conn.fetch_timer)  
              {:noreply, conn 
                         |> Map.put(:state, :maybe_fetching)
                         |> Map.put(:fetch_interval, fetch_interval)
                         |> Map.put(:caller, caller)
                         |> cancel_idle()
                         |> on_start_response(:ok, :ok)
              }
        end

        def handle_info(:restart, conn) when conn.state == :running, do: 
          exit("restart command")

############################################################################################

        # If the previously received line ends with `{123}` (a synchronizing literal), parse more lines until we
        # have at least 123 bytes. If the line ends with another `{123}`, repeat the process.
        defp recv_literals(%Conn{} = conn, [prev | _] = acc, n_remaining \\ 0) do
          if n_remaining <= 0 do
          # n_remaining <= 0 - we don't need any more bytes to fulfil the previous literal. We might be done...
            case Regex.run(~r/\{(\d+)\}\r\n$/, prev, capture: :all_but_first) do
              [n] ->
                # ...unless there is another literal.
                # +2 so that we make sure we get the full command (either the last 2 \r\n, or the next part of the command)
                n = String.to_integer(n) + 2
                recv_literals(conn, acc, n)

              _ ->
                # The last line didn't end with a literal. The packet is complete.
                acc
                |> Enum.reverse()
                |> Enum.join()
            end
          else
            # we need more bytes to complete the current literal. Recv the next line.
            {:ok, next_line} =
              if conn.tls do
                :ssl.recv(conn.socket, 0)
              else
                :gen_tcp.recv(conn.socket, 0)
              end

            recv_literals(conn, [next_line | acc], n_remaining - byte_size(next_line))
          end
        end

        defp handle_packet(data, conn) do
          if conn.got_server_greeting do
            actions = Parser.parse_response(data) 

            conn =
              conn
              |> apply_actions(actions) 

            conn =
              if conn.idling and conn.unprocessed_messages != %{} do
                conn
                |> cancel_idle()
              else
                conn
              end

            conn
            |> maybe_process_messages()
            |> maybe_idle()
          else
            # ignore the first message from the server, which is the unsolicited greeting
            %{conn | got_server_greeting: true}
            |> send_command("CAPABILITY", &on_unauthed_capability_response/3)
          end
        end

        defp on_unauthed_capability_response(conn, :ok, _text) do
          if !conn.tls do
            if "STARTTLS" in conn.capabilities do
              conn
              |> send_command("STARTTLS", &on_starttls_response/3)
            else
              raise "Server does not support STARTTLS as required by RFC3501."
            end
          else
            conn
            |> __MODULE__.access_imap_server() 
          end
        end

        defp on_starttls_response(conn, :ok, _text) do
          {:ok, socket} = :ssl.connect(conn.socket, ssl_opts(conn.server, conn.ssl_verify), :infinity)

          %{conn | tls: true, socket: socket}
          |> __MODULE__.access_imap_server() 
        end

        defp on_start_response(conn, :ok, data) do
          if conn.state == :authenticated do 
            true = ImapPresences.register(conn.email) 
            Utils.publish({:imap_state, conn.email, :on})
          end
          conn
          |> send_command("SELECT #{Utils.quote_string(conn.mailbox)}", &on_select_response/3)
        end

        defp on_select_response(conn, :ok, text) do
          period = 
            if conn.fetch_interval do 
              conn.fetch_interval 
            else 
              case conn.state do 
                :authenticated -> 
                  Application.get_env(
                                      :petal_core, 
                                      :start_time_fetch_period, 
                                      @default_start_time_fetch_interval
                                    ) 
                _ -> 
                  @default_periodic_fetch_interval
              end
            end
  
          if Regex.match?(~r/^\[READ-ONLY\]/i, text) do
            %{conn | mailbox_mutability: :read_only}
          else
            %{conn | mailbox_mutability: :read_write}
          end
          |> Map.put(:state, :maybe_fetching)
          |> fetch_messages(period)
          |> maybe_noop_poll()
        end

        defp command_in_progress?(conn), do: conn.tag_map != %{}

        # starts NOOP polling unless the server supports IDLE
        defp maybe_noop_poll(conn) do
          unless "IDLE" in conn.capabilities do
            send(self(), :poll_with_noop)
          end

          conn
        end

        defp on_idle_response(conn, :ok, _text) do
          if conn.idle_timed_out do
            maybe_idle(conn)
          else
            conn
          end
        end

        # IDLEs if there is no command in progress, we're not already idling, and the server supports IDLE
        defp maybe_idle(conn) do
          if "IDLE" in conn.capabilities and not command_in_progress?(conn) and not conn.idling do
            timer = Process.send_after(self(), :idle_timeout, @idle_timeout)
            %{conn | idling: true, idle_timer: timer, idle_timed_out: false}
            |> send_command("IDLE", &on_idle_response/3)
          else
            conn
          end
        end

        defp cancel_idle(conn) do
          Process.cancel_timer(conn.idle_timer)

          %{conn | idling: false, idle_timer: nil}
          |> send_raw("DONE\r\n")
        end

        defp maybe_process_messages(conn) do
          if command_in_progress?(conn) or 
             conn.unprocessed_messages == %{} or 
             (
               conn.state != :running and 
               conn.state != :fetching and 
               conn.state != :maybe_fetching
             ) 
               do
                 conn 

          else
            process_earliest_message(conn)
          end
        end

        defp process_earliest_message(conn) do
          {seqnum, msg} = Enum.min_by(conn.unprocessed_messages, fn {k, _v} -> k end)

          cond do
            not Map.has_key?(msg, :fetched) ->
              conn
              |> fetch_message(seqnum)
              |> maybe_process_messages()

            msg.fetched == :filter ->
              parts_to_fetch =
              [flags: "FLAGS", envelope: "ENVELOPE"]
              |> Enum.reject(fn {key, _} -> Map.has_key?(msg, key) end)
              |> Enum.map(&elem(&1, 1))

              parts_to_fetch = ["BODY" | parts_to_fetch]

              conn =
                conn
                |> put_in([Access.key!(:unprocessed_messages), seqnum, :fetched], :pre_body)

              unless Enum.empty?(parts_to_fetch) do
                conn
                |> send_command("FETCH #{seqnum} (#{Enum.join(parts_to_fetch, " ")})")
              else
                conn
              end

            msg.fetched == :pre_body ->
              body_parts =
              body_part_paths(msg.body_structure)
              |> Enum.map(&"BODY.PEEK[#{&1}]")

              conn
              |> send_command(
                               "FETCH #{seqnum} (#{Enum.join(body_parts, " ")})", 
                               fn conn, :ok, _text ->
                                 put_in(
                                        conn, 
                                        [
                                          Access.key!(:unprocessed_messages), 
                                          seqnum, 
                                          :fetched
                                        ], 
                                        :full
                                        )
                               end
                             )

            msg.fetched == :full ->
              conn
              |> release_message(seqnum)
          end
        end

        defp body_part_paths(body_structure, path_acc \\ []) do
          case body_structure do
            {:onepart, _body} ->
              path =
                if path_acc == [] do
                  "1"
                else
                  path_acc
                  |> Enum.reverse()
                  |> Enum.join(".")
                end

              [path]

            {:multipart, bodies} ->
              bodies
              |> Enum.with_index(1)
              |> Enum.flat_map(fn {b, idx} -> body_part_paths(b, [idx | path_acc]) end)
          end
        end

        # Removes the message from conn.unprocessed_messages and process it
        defp release_message(conn, seqnum) do
          {msg, conn} = pop_in(conn, [Access.key!(:unprocessed_messages), seqnum]) 
          
          new_msg = msg
                    |> package_message()
                    |> Messages.normalize_message()

          :ok = Messages.global_put(Utils.message_struct_to_tuple(new_msg))
          :ok = Messages.local_put(conn.email, new_msg.id) 
          Utils.publish({:message, conn.email, new_msg})
          
          if (conn.state == :fetching) do 
            conn 
            |> Map.put(:fetch_size, conn.fetch_size - 1)
          else 
            conn 
          end 
          |> set_state()
        end

        # Preprocesses/cleans the message before it is sent to a subscriber
        defp package_message(msg) do
          msg
          |> Map.merge(msg.envelope)
          |> Map.drop([:fetched, :body_structure, :envelope])
          |> Map.put(:body, normalize_structure(msg.body, msg.body_structure))
        end

        defp normalize_structure(msg_body, msg_structure) do
          combine_bodies_if_multipart(msg_body)
          |> get_part_structures(msg_structure)
        end

        defp combine_bodies_if_multipart(_, depth \\ 0)
        defp combine_bodies_if_multipart([body], _depth), do: body
        defp combine_bodies_if_multipart(body, _depth) when is_tuple(body), do: body

        defp combine_bodies_if_multipart(bodies, depth) when is_list(bodies) and length(bodies) > 1 do
          bodies
          |> Enum.group_by(fn {path, _} -> Enum.at(path, depth) end)
          |> Map.values()
          |> Enum.map(&combine_bodies_if_multipart(&1, depth + 1))
        end

        defp get_part_structures({_, content}, {:onepart, map}),
          do: {map.mime_type, map.params, Parser.decode_body(content, map.encoding)}

        defp get_part_structures({[idx | path], content}, {:multipart, parts}),
          do: get_part_structures({path, content}, Enum.at(parts, idx - 1))

        defp get_part_structures(bodies, structure) when is_list(bodies),
          do: Enum.map(bodies, &get_part_structures(&1, structure))

        defp apply_action(conn, action) do
          case action do
            {:capabilities, caps} ->
              %{conn | capabilities: caps}

            {:tagged_response, {tag, status, text}} when status == :ok ->
              {%{on_response: resp_fn}, conn} = pop_in(conn, [Access.key!(:tag_map), tag])

              resp_fn.(conn, status, text)

            {:tagged_response, {tag, status, text}} when status in [:bad, :no] ->
              raise "Got `#{status |> to_string() |> String.upcase()}` response status: `#{text}`. Command that caused this response: `#{conn.tag_map[tag].command}`"

            :continuation ->
              conn

            {:applicable_flags, flags} ->
              %{conn | applicable_flags: flags}

            {:permanent_flags, flags} ->
              %{conn | permanent_flags: flags}

            {:num_exists, num} ->
              conn =
                if conn.num_exists < num do
                  %{
                    conn
                    | unprocessed_messages:
                        Map.merge(
                            Map.from_keys(Enum.to_list((conn.num_exists + 1)..num), %{}),
                            conn.unprocessed_messages
                        )
                   }
                else
                  conn
                end

                %{conn | num_exists: num}

            {:num_recent, num} ->
              %{conn | num_recent: num}

            {:first_unseen, num} ->
              %{conn | first_unseen: num}

            {:uid_validity, num} ->
              %{conn | uid_validity: num}

            {:uid_next, num} ->
              %{conn | uid_next: num}

            {:expunge, expunged_num} ->
              %{
                conn
                | num_exists: conn.num_exists - 1,
                  unprocessed_messages:
                  conn.unprocessed_messages
                  |> Enum.reject(fn {k, _v} -> k == expunged_num end)
                  |> Enum.map(
                      fn {k, v} ->
                        cond do
                          expunged_num < k ->
                            {k - 1, v}

                          expunged_num > k ->
                            {k, v}
                        end
                      end
                    )
                  |> Map.new()
               }

            {:fetch, {seq_num, :flags, flags}} ->
              if Map.has_key?(conn.unprocessed_messages, seq_num) do
                flags = Parser.system_flags_to_atoms(flags)

                conn
                |> put_in([Access.key!(:unprocessed_messages), seq_num, :flags], flags)
              else
                conn
              end

            {:fetch, {seq_num, :envelope, envelope}} ->
              if Map.has_key?(conn.unprocessed_messages, seq_num) do
                conn
                |> put_in([Access.key!(:unprocessed_messages), seq_num, :envelope], envelope)
              else
                conn
              end

            {:fetch, {seq_num, :body, one_or_mpart}} ->
              if Map.has_key?(conn.unprocessed_messages, seq_num) do
                conn
                |> put_in(
                    [Access.key!(:unprocessed_messages), seq_num, :body_structure],
                    one_or_mpart
                   )
              else
                conn
              end

            {:fetch, {seq_num, :body_content, {body_number, content}}} ->
              msg = Map.get(conn.unprocessed_messages, seq_num)

              if msg do
                body =
                  case msg.body_structure do
                    {:onepart, _} ->
                      {body_number, content}

                    {:multipart, _} ->
                      [{body_number, content} | msg[:body] || []]
                  end

                conn
                |> put_in([Access.key!(:unprocessed_messages), seq_num, :body], body)
              else
                conn
              end

            {:fetch, {_seq_num, :uid, _uid}} ->
              conn
          end
        end

        defp apply_actions(conn, []), do: conn

        defp apply_actions(conn, [action | rest]),
          do: conn |> apply_action(action) |> apply_actions(rest)

        defp send_raw(conn, stuff) do
            if conn.tls do
              :ssl.send(conn.socket, stuff)
            else
              :gen_tcp.send(conn.socket, stuff)
            end

            conn
        end

        defp fetch_message(conn, seqnum) do
          conn
          |> put_in([Access.key!(:unprocessed_messages), seqnum, :fetched], :filter)
        end

        defp send_command(conn, cmd, on_response \\ fn conn, _status, _text -> conn end) do
          tag = conn.next_cmd_tag 
          cmd = "#{tag} #{cmd}\r\n"

          conn 
          |> send_raw(cmd)
          |> Map.put(:next_cmd_tag, tag + 1)
          |> put_in([Access.key!(:tag_map), tag], %{command: cmd, on_response: on_response})
        end

        defp send_manual_command(conn, cmd, on_response \\ fn conn, _status, _text -> conn end) do
          tag = conn.next_cmd_tag 
          cmd = "#{tag} #{cmd}\r\n"

          conn 
          |> send_raw(cmd)
          |> Map.put(:next_cmd_tag, tag + 1)
        end

        defp fetch_messages(conn, period) do
          fetch_timer = :erlang.start_timer(@fetch_timeout , self() , :fetch_messages) 
          conn = 
            if conn.idling do
              conn
              |> cancel_idle()
            else
              conn
            end 
            |> Map.put(:fetch_timer, fetch_timer)
            |> do_fetch_messages(period) 
            |> set_state()
            |> maybe_process_messages()     
            |> maybe_idle()
        end

        defp do_fetch_messages(conn, period) do 
          fetch_start_date = Utils.get_fetch_start_date(period)
          conn = conn 
                 |> send_manual_command("SEARCH SINCE #{fetch_start_date}")
                  
          messages_indexes = receive_search_result(conn)
                             |> case do 
                                  [] -> 
                                    [] 
                                  res ->
                                    String.split(res) 
                                end 

          {conn, new_messages} = get_new_messages(conn, messages_indexes) 
          add_new_messages(conn, new_messages)

        end 

        defp get_new_messages(conn, messages_indexes), do: 
          Enum.reduce(
                messages_indexes, 
                {conn, []}, 
                fn(message_index, {current_conn, acc}) -> 
                  new_conn = current_conn
                             |> send_manual_command(
                                  "FETCH #{message_index} (BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)])"
                                )
                  message_ID = receive_fetch_message_id_result(new_conn)
                   
                  {new_conn, if Messages.new_message?(conn.email, message_ID) do 
                               [message_index | acc]
                             else 
                               acc 
                             end 
                  } 
                end                         
             )

        defp add_new_messages(conn, new_messages), do:  
          Map.put(
                   conn,
                   :unprocessed_messages,
                    Enum.reduce(
                                 new_messages, 
                                 conn.unprocessed_messages, 
                                 fn(new_message, acc) -> 
                                   Map.put(acc, String.to_integer(new_message), %{}) 
                                 end 
                              )
                  )
          |> Map.put(:fetch_size, length(new_messages))
          

        defp receive_search_result(conn, res \\ nil) do 
          receive do 
            {socket_kind, socket, data} when 
              socket == conn.socket and  
              socket_kind in [:ssl, :tcp] -> 

                case data do           
                  <<"* SEARCH", _rest::binary>> ->        
                    :ok = activate_socket_once(conn)
                    receive_search_result(conn, Parser.parse_response(data))

                  other ->
                    :ok = activate_socket_once(conn)
                    if String.contains?(String.downcase(other), "ok search completed") do
                      res
                    else 
                      receive_search_result(conn, res)
                    end 
                end             

            after 5000 -> 
              exit("timeout receiving messages list")
          end 
        end

        defp receive_fetch_message_id_result(conn, res \\ nil) do 
          receive do 
            {socket_kind, socket, data} when  
              socket == conn.socket and  
              socket_kind in [:ssl, :tcp] -> 
                case data do 
                  <<"Message-ID: ", message_id::binary>> -> 
                    :ok = activate_socket_once(conn)
                    receive_fetch_message_id_result(conn, message_id
                                                          |> String.split()
                                                          |> List.first()
                                                   )

                  other ->
                    :ok = activate_socket_once(conn)
                    if String.contains?(String.downcase(other), "ok success") or 
                       String.contains?(String.downcase(other), "ok fetch completed")
                         do 
                          res
                    else 
                      receive_fetch_message_id_result(conn, res)
                    end 
                end

            after 5000 -> 
              exit("timeout receiving message id")
          end 
        end

        defp activate_socket_once(conn) do 
          if conn.tls do
            :ssl.setopts(conn.socket, active: :once)
          else
            :inet.setopts(conn.socket, active: :once)
          end
        end          

        defp set_state(conn) do 
          case conn.fetch_size do 
            0 ->
              if conn.caller do 
                send(conn.caller, :done)
                Map.put(conn, :caller, nil)
              else 
                conn 
              end 
              |> Map.put(:state, :running)
              |> Map.put(:fetch_interval, nil)

            _ -> 
              conn
              |> Map.put(:state, :fetching) 
          end 
        end 

    end  
  end
end
