defmodule Yugo.Messages do 

  import Yugo.Messages.Message

  alias Yugo.Messages.Message
  alias Yugo.Utils

  @publisher :publisher
  @all_messages_topic "messages:*"
  @table :message

############################ Database API ########################### 

  def get(key), do: MnesiaDatabase.safe_read(@table, key)

  def put(message), do: MnesiaDatabase.safe_write(message) 

  def delete(key), do: MnesiaDatabase.safe_delete(@table, key) 

  def all_keys(), do: MnesiaDatabase.all_keys(@table)

  def first_key(), do: MnesiaDatabase.first_key(@table)

  def next_key(key), do: MnesiaDatabase.next_key(@table, key)

######################################################################

  def get_publisher(), do: 
    @publisher

  def get_all_messages_topic(), do: 
    @all_messages_topic 

  def get_topic_by_email(email), do: 
    "messages:#{email}"

  def get_all_messages(), do:  
    all_keys()
    |> Enum.reduce(
                    [], 
                    fn(key, acc) -> 
                      [message] = get(key) 
                      [
                        message
                        |> make_ui_message() 
                        | acc
                      ] 
                    end
                  )

  def get_messages_by_email(email), do: 
    do_get_messages_by_email(first_key(), email, [])

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

  defp do_get_messages_by_email(:"$end_of_table", _email, acc), do: acc 

  defp do_get_messages_by_email(key, email, acc) do 
    [message] = get(key) 
    to = message(message, :to) 
    cc = message(message, :cc)

    new_acc = 
      case check_destination(to, email) do 
        :found ->
          [make_ui_message(message) | acc] 
        :not_found -> 
          case check_destination(cc, email) do
            :found -> 
              [make_ui_message(message) | acc]
            :not_found -> 
              acc 
          end 
      end

    do_get_messages_by_email(next_key(key), email, new_acc) 
  end  

  defp check_destination(destinations, email) when is_list(destinations) do 
    if Enum.member?(destinations, email) do 
      :found 
    else 
      :not_found 
    end 
  end 

  defp check_destination(destination, destination), do: :found 

  defp check_destination(_destination, _email), do: :not_found

  defp get_to({_, to}), do: to 

  defp get_to(msg_to), do: 
    Enum.reduce(msg_to, [], fn({_, to}, acc) -> [to | acc] end)

  defp make_ui_message(message), do: 
    message
    |> Utils.message_tuple_to_struct()
    |> Map.put(:cc, nil)
    |> Map.put(:body, nil) 
      
end

