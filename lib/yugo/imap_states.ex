defmodule Yugo.ImapStates do 

  @all_imap_states_topic "imap_states:*"
  @imap_states_part_size 20 

  def get_imap_states_part_size(), do: 
    @imap_states_part_size 

  def get_all_imap_states_topic(), do: 
    @all_imap_states_topic

  def get_topic_by_email(email), do: 
    "imap_states:#{email}"

  def get_next_part_of_imap_states(imap_states, start_index), do: 
    imap_states
    |> Enum.slice(start_index, @imap_states_part_size) 

end 

