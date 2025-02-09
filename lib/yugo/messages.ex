defmodule Yugo.Messages do 

  alias Yugo.Messages.Message
  alias Yugo.Utils

  @all_messages_topic "messages:*"
  @table :message

############################ Database API ########################### 

  def global_get(key), do: MnesiaDatabase.safe_read(@table, key)

  def local_get(table, key), do: MnesiaDatabase.safe_read(String.to_atom(table), key)

  def global_put(message), do: MnesiaDatabase.safe_write(message)

  def local_put(table, id), do: MnesiaDatabase.safe_write({String.to_atom(table), id, nil})

  def delete(key), do: MnesiaDatabase.safe_delete(@table, key) 

  def global_all_keys(), do: MnesiaDatabase.all_keys(@table)

  def local_all_keys(table), do: MnesiaDatabase.all_keys(table) 

######################################################################

  def get_all_messages_topic(), do: 
    @all_messages_topic 

  def get_topic_by_email(email), do: 
    "messages:#{email}"

  def get_all_messages(), do:  
    global_all_keys()
    |> Enum.reduce(
                    [], 
                    fn(key, acc) -> 
                      [message] = global_get(key) 
                      [
                        message
                        |> make_ui_message() 
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
                    fn(id, acc) ->
                      res = global_get(id) 
                      case res do 
                        [message] -> 
                          [
                            message
                            |> make_ui_message() 
                            | acc
                          ] 
                        _ -> 
                          acc 
                      end 
                    end
                  )

  def new_message?(table, key), do: 
    global_get(key) == [] || local_get(table, key) == []

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

        body: msg[:body]
              |> case do 
                   {_, _, body} -> 
                     body 

                   [{_, _, body} | _tail] -> 
                     body

                   [[{_, _, body} | _tail1] | _tail2] -> 
                     body
                   
                 end             
    }
  end     

##################################################################################

  defp get_to({_, to}), do: to 

  defp get_to(msg_to), do: 
    Enum.reduce(msg_to, [], fn({_, to}, acc) -> [to | acc] end)

  defp make_ui_message(message), do: 
    message
    |> Utils.message_tuple_to_struct()
    |> Map.put(:cc, nil)
    |> Map.put(:body, nil) 
      
end

