defmodule Yugo.Messages.Message do 

  defstruct id: nil, 
            from: nil, 
            to: nil,
            cc: [],
            subject: nil,
            date: nil,
            body: nil  
end

