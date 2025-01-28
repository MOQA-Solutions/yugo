defmodule Yugo.Messages do 

  alias Yugo.Messages.Message

  @publisher :publisher
  @topic "imap_messages"
  @table :messages

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

  def normalize_date(date), do:
    "#{normalize_date_field(date.day)}/#{normalize_date_field(date.month)}/#{date.year} at #{normalize_date_field(date.hour)}:#{normalize_date_field(date.minute)}"

  

###############################################################################################

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

