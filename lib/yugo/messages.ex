defmodule Yugo.Messages do 

  alias Yugo.Messages.Message
  alias Yugo.Utils

  @all_messages_topic "messages:*"
  @table :message 
  @messages_part_size 20

############################ Database API ########################### 

  def global_get(key), do: MnesiaDatabase.safe_read(@table, key)

  def local_get(table, key), do: MnesiaDatabase.safe_read(String.to_atom(table), key)

  def global_put(message), do: MnesiaDatabase.safe_write(message)

  def local_put(table, id), do: MnesiaDatabase.safe_write({String.to_atom(table), id, nil})

  def delete(key), do: MnesiaDatabase.safe_delete(@table, key) 

  def global_all_keys(), do: MnesiaDatabase.all_keys(@table)

  def local_all_keys(table), do: MnesiaDatabase.all_keys(table) 

######################################################################

  def get_messages_part_size(), do: 
    @messages_part_size

  def get_all_messages_topic(), do: 
    @all_messages_topic 

  def get_topic_by_email(email), do: 
    "messages:#{email}"

  def get_all_messages(), do:  
    global_all_keys()
    |> Enum.reduce(
                    [], 
                    fn(key, acc) -> 
                      [
                        global_get(key)
                        |> List.first()
                        | acc
                      ] 
                    end
                  )

  def get_messages_by_email(email), do: 
    email 
    |> String.to_atom() 
    |> local_all_keys() 
    |> Enum.reduce(
                    [], 
                    fn(key, acc) -> 
                      [
                        global_get(key)
                        |> List.first()
                        | acc
                      ] 
                    end
                  )

  def get_next_part_of_messages(messages_IDs, start_index), do:  
    messages_IDs
    |> Enum.slice(start_index, @messages_part_size) 
    |> Enum.reduce(
                    [], 
                    fn(message_id, acc) ->
                      [
                        global_get(message_id)
                        |> List.first() 
                        |> Utils.message_tuple_to_struct() 
                        |> make_ui_message()
                        | acc
                      ]
                    end
                 )
    |> Enum.reverse()
           
  def new_message?(table, key) do
    if (global_get(key) == [] or local_get(table, key) == []) do 
      true
    else 
      false 
    end
  end 

  def normalize_message(msg) do 
    %Message{
        id: String.replace(msg[:message_id], " ", ""),

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

##################################################################################

  defp get_to({_, to}), do: to 

  defp get_to(msg_to), do: 
    Enum.reduce(msg_to, [], fn({_, to}, acc) -> [to | acc] end)

  defp get_body({_, _, body}), do: body 
  defp get_body([h | _tail]), do: get_body(h)

end

