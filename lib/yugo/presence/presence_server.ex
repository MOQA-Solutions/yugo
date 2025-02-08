defmodule Yugo.Presence.PresenceServer do
  @moduledoc false
  use GenServer

  alias Yugo.{Utils, Presence.ImapPresences}

  def start_link(args), do: 
    GenServer.start_link(__MODULE__, args, name: Utils.get_presence_server())

  def init(args) do 
    Process.flag(:trap_exit, true)
    {:ok, %{parent: args[:parent]}}
  end

  def handle_call(_call, _from, state), do: {:noreply, state}

  def handle_cast(_cast, state), do: {:noreply, state}

  def handle_info({:"EXIT", parent, reason}, %{parent: parent}) do 
    exit("Parent exit: #{reason}")
  end

  def handle_info({:"EXIT", pid, _reason}, state) do
    {:ok, email} = clear_imap_worker_data(pid)
    msg = {:imap_state, email, :off}
    Utils.publish(msg)
    {:noreply, state}
  end

  def handle_info(_info, state), do: {:noreply, state}

############################################################################################### 

  defp clear_imap_worker_data(pid) do
    str_pid = Utils.pid_to_string(pid)
    [imap_presence] = ImapPresences.index_get(str_pid) 
    email = elem(imap_presence, 1)
    :ok = ImapPresences.delete(email)
    {:ok, email}
  end
end

