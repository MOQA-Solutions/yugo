defmodule Yugo.Clients do 

  alias Yugo.Clients.BasicClient 
  alias Yugo.Clients.GoogleOAuthClient

  def get_client(email), do: 
      email 
      |> String.split("@")
      |> List.last()
      |> String.split(".")
      |> List.first()
      |> String.to_atom()
      |> do_get_client() 
  
#########################################################################################

  defp do_get_client(:finodata), do: BasicClient 

  defp do_get_client(:gmail), do: GoogleOAuthClient 

  defp do_get_client(_provider), do: BasicClient

end 

