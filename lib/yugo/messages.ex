defmodule Yugo.Messages do 

  alias Yugo.Messages.Message
  alias Yugo.Utils

  @all_messages_topic "messages:*"
  @table :message 
  @messages_part_size 40

  @index :owner

############################ Database API ########################### 

  def get(key), do: MnesiaDatabase.safe_read(@table, key)

  def index_get(key), do: MnesiaDatabase.safe_index_read(@table, key, @index)

  def put(message), do: MnesiaDatabase.safe_write(message)

  def delete(key), do: MnesiaDatabase.safe_delete(@table, key) 

  def all_keys(), do: MnesiaDatabase.all_keys(@table)

######################################################################

  def get_messages_part_size(), do: 
    @messages_part_size

  def get_all_messages_topic(), do: 
    @all_messages_topic 

  def get_topic_by_email(email), do: 
    "messages:#{email}"

  def get_all_messages(), do:  
    all_keys()
    |> Enum.reduce(
                    [], 
                    fn(key, acc) -> 
                      [
                        get(key)
                        |> List.first()
                        | acc
                      ] 
                    end
                  )

  def get_messages_by_email(email), do: 
    index_get(email)

  def get_next_part_of_messages(messages_IDs, start_index), do:  
    messages_IDs
    |> Enum.slice(start_index, @messages_part_size) 
    |> Enum.reduce(
                    [], 
                    fn(message_id, acc) ->
                      [
                        get(message_id)
                        |> List.first() 
                        |> Utils.message_tuple_to_struct() 
                        |> make_ui_message()
                        | acc
                      ]
                    end
                 )
    |> Enum.reverse()
           
  def new_message?(id) do
    msg_id = message_id(id)
    get(msg_id) == []
  end 

  def normalize_message(msg, owner) do 
    %Message{
        id: message_id(msg[:message_id]),

        owner: owner,

        from: msg[:from]
              |> case do 
                   [{_, from}] -> 
                     from 
                   {_, from} -> 
                     from 
                 end,

        to: get_to(msg[:to]),

        cc: msg[:cc],

        subject: msg[:subject],

        date: msg[:date],

        body: get_body(msg[:body])        
    }
  end     

  def make_ui_message(message), do: 
    message
    |> Map.put(:cc, nil)
    |> Map.put(:body, nil)

  def message_id(id), do: 
    id   
    |> String.replace(" ", "")
    

##################################################################################

  defp get_to({_, to}), do: to 

  defp get_to(msg_to), do: 
    Enum.reduce(msg_to, [], fn({_, to}, acc) -> [to | acc] end)

  defp get_body({_, _, body}), do: body 
  defp get_body([h | _tail]), do: get_body(h)

end

