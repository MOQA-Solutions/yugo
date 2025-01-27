defmodule Yugo.Messages do 

  alias Yugo.Messages.Message

  @publisher :publisher
  @topic "imap_messages"
  @table :messages
  @new_line "\n"

  def get_publisher(), do: 
    @publisher

  def get_topic(), do: 
    @topic 

  def get_all_messages(), do: 
    @table 
    |> :ets.tab2list()
    |> Enum.reduce([], fn(message, acc) -> 
                         [
                            tuple_to_struct(message)
                            |> Map.put(:cc, nil)
                            |> Map.put(:body, nil)               
                            | acc
                         ] 
                       end
                  )
    |> Enum.sort_by(fn(%Message{} = message) -> message.date end, :desc)

  def publish(message), do: 
    send(@publisher, {:message, message})

  def create_messages_table(), do: 
    :ets.new(@table, [:public, :named_table])

  def store_new_message(message), do: 
    :ets.insert(@table, struct_to_tuple(message))    

  def get_message_by_id(id), do: 
    :ets.lookup(@table, id)
    |> List.first() 
    |> tuple_to_struct() 
  

  def normalize_message(msg) do 
    %Message{
        id: msg[:message_id],

        from: msg[:from]
              |> List.first()
              |> elem(1),

        to: msg[:to]
            |> List.first()
            |> elem(1),

        cc: msg[:cc],

        subject: msg[:subject],

        date: msg[:date],

        body: msg[:body]
              |> List.first()
              |> elem(2)
              |> get_message_body(msg[:in_reply_to]) 
                                 
    }
  end 

  def normalize_date(date), do:
    "#{normalize_date_field(date.day)}/#{normalize_date_field(date.month)}/#{date.year} at #{normalize_date_field(date.hour)}:#{normalize_date_field(date.minute)}"

  

###############################################################################################"

  defp get_message_body(body, nil), do: body

  defp get_message_body(body, _in_reply_to), do:  
    body 
    |> String.split(Integer.to_string(DateTime.utc_now().year))
    |> List.first() 
    |> String.split(@new_line)
    |> List.pop_at(-1)
    |> elem(1)
    |> Enum.join(@new_line)

  defp struct_to_tuple(message), do: 
    {
      message.id, 
      message.from, 
      message.to, 
      message.cc, 
      message.subject, 
      message.date, 
      message.body 
    }

  defp tuple_to_struct(message), do: 
    %Message{
      id: elem(message, 0),
      from: elem(message, 1),
      to: elem(message, 2),
      cc: elem(message, 3),
      subject: elem(message, 4),
      date: elem(message, 5),
      body: elem(message, 6)
    }

  defp normalize_date_field(date_field) do 
    date_field 
    |> to_string()
    |> String.pad_leading(2, "0")
  end

end

