defmodule Yugo.Utils do 

  import Yugo.Messages.Message

  alias Yugo.Messages.Message

  def get_fetch_start_date(period), do:
    DateTime.utc_now() 
    |> DateTime.to_unix() 
    |> Kernel.-(period * 24 * 60 * 60) 
    |> DateTime.from_unix() 
    |> elem(1)
    |> imap_format()

  def quote_string(string) do
    if Regex.match?(~r/[\r\n]/, string) do
      raise "string passed to quote_string contains a CR or LF. TODO: support literals"
    end

    string
    |> String.replace("\\", "\\\\")
    |> String.replace(~S("), ~S(\"))
    |> then(&~s("#{&1}"))
  end

  def normalize_date(date), do:
    "#{normalize_date_field(date.day)}/#{normalize_date_field(date.month)}/#{date.year} at #{normalize_date_field(date.hour)}:#{normalize_date_field(date.minute)}"

  def normalize_date_field(date_field), do:
    date_field 
    |> to_string()
    |> String.pad_leading(2, "0")

  def message_struct_to_tuple(message), do: 
    message(
        id: message.id, 
        from: message.from, 
        to: message.to, 
        cc: message.cc, 
        subject: message.subject, 
        date: message.date, 
        body: message.body 
      )

  def message_tuple_to_struct(message), do: 
    %Message{
      id: message(message, :id),
      from: message(message, :from),
      to: message(message, :to),
      cc: message(message, :cc),
      subject: message(message, :subject),
      date: message(message, :date),
      body: message(message, :body)
    }

################################################################################################

  defp imap_format(%DateTime{} = date), do: 
    normalize_date_field(date.day) 
    <> 
    "-" 
    <>
    month_abbr(date.month)
    <> 
    "-" 
    <>
    Integer.to_string(date.year) 

  defp month_abbr(1), do: "jan"
  defp month_abbr(2), do: "feb"
  defp month_abbr(3), do: "mar"
  defp month_abbr(4), do: "apr"
  defp month_abbr(5), do: "may"
  defp month_abbr(6), do: "jun"
  defp month_abbr(7), do: "jul"
  defp month_abbr(8), do: "aug"
  defp month_abbr(9), do: "sep"
  defp month_abbr(10), do: "oct"
  defp month_abbr(11), do: "nov"
  defp month_abbr(12), do: "dec"

end 

