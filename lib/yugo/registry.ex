defmodule Yugo.Registry do

  @registry :yugo_registry

  def start() do 
    ets_tables = :ets.all()
    case Enum.member?(ets_tables, @registry) do 
      true ->
        :ok
      _ ->
        try do
          :ets.new(@registry, [:named_table, :public, :set])  
          :ok
        rescue
          _error ->
            :ok
        end
    end
  end
  
  def register(key, value), do: :ets.insert(@registry, {key, value})

  def lookup(key) do
    case :ets.lookup(@registry, key) do 
      [{_key, value}] -> 
        {:ok, value}
      _ -> 
        :error  
    end
  end
end 

