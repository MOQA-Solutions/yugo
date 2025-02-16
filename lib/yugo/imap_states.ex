defmodule Yugo.ImapStates do 

  alias Yugo.Utils

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
    |> Enum.reduce(
                    [], 
                    fn(imap_state, acc) ->
                      [
                        imap_state 
                        |> Utils.imap_state_tuple_to_struct() 
                        | acc
                      ]
                    end
                 )
 

end 

