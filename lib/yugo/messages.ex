defmodule Yugo.Messages do 

  alias Yugo.Messages.Message
  alias Yugo.Utils

  @publisher :publisher
  @topic "imap_messages"
  @table :message

############################ Database API ########################### 

  def get(key), do: MnesiaDatabase.safe_read(@table, key)

  def index_get(key, index), do: MnesiaDatabase.safe_index_read(@table, key, index)

  def put(message), do: MnesiaDatabase.safe_write(message) 

  def delete(key), do: MnesiaDatabase.safe_delete(@table, key) 

######################################################################

  def get_publisher(), do: 
    @publisher

  def get_topic(), do: 
    @topic 

  def get_all_messages(), do: 
    @table 
    |> MnesiaDatabase.all_keys()
    |> Enum.reduce(
                    [], 
                    fn(key, acc) -> 
                      [message] = get(key) 
                      [
                        message
                        |> Utils.message_tuple_to_struct()
                        |> Map.put(:cc, nil)
                        |> Map.put(:body, nil) 
                        | acc
                      ] 
                    end
                  )
    |> Enum.sort_by(fn(%Message{} = message) -> message.date end, :desc)

  def publish(message), do: 
    send(@publisher, {:message, message}) 

  def new_message?(key), do: 
    get(key) == []

  def normalize_message(msg) do 
    %Message{
        id: msg[:message_id],

        from: msg[:from]
              |> case do 
                   [{_, from}] -> 
                     from 
                   {_, from} -> 
                     from 
                 end,

        to: msg[:to]
            |> case do 
                 [{_, to}] -> 
                   to 
                 {_, to} -> 
                   to 
               end,

        cc: msg[:cc],

        subject: msg[:subject],

        date: msg[:date],

        body: msg[:body]
              |> case do 
                   [{_, _, body} | _tail] -> 
                     body
                   {_, _, body} -> 
                     body 
                 end             
    }
  end     
end

