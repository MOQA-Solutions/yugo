defmodule Yugo.Presence.ImapPresences do 

  alias Yugo.Utils

  @table :imap_presence
  @index :pid

  def get(key), do: MnesiaDatabase.safe_read(@table, key) 

  def put(imap_presence), do: MnesiaDatabase.safe_write(imap_presence) 

  def index_get(key), do: MnesiaDatabase.safe_index_read(@table, key, @index) 

  def delete(key), do: MnesiaDatabase.safe_delete(@table, key)

#####################################################################################

  def register(imap_presence) do
    :ok = put(imap_presence)
    Utils.get_presence_server()
    |> :erlang.whereis()
    |> Process.link()
  end

end
