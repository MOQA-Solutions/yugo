defmodule Yugo.Clients.WebClient do 

  @refresh_token_endpoint "https://oauth2.googleapis.com/token"

  def get_access_token(client_id, client_secret, refresh_token) do 
    path = 
      @refresh_token_endpoint
        <> 
      "?client_id=#{client_id}" 
        <>
      "&client_secret=#{client_secret}"
        <>
      "&refresh_token=#{refresh_token}" 
        <> 
      "&grant_type=refresh_token" 
        <> 
      "&access_type=offline"

    headers = %{
           "Content-Type" => "application/x-www-form-urlencoded",
           "Content-Length" => "0"
           }
    
    post(path, headers)
  end 

###########################################################################################

  defp post(path, headers) do
    {:ok, res} = Req.post(
                        path, 
                        headers: headers
                      )
    res.body
  end
end 
