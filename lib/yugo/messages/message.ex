defmodule Yugo.Messages.Message do 
 
  require Record

  Record.defrecord(:message, 
                   id: nil,
                   owner: nil,
                   from: nil,  
                   to: nil,
                   cc: nil, 
                   subject: nil, 
                   date: nil, 
                   body: nil
                  )  

  defstruct id: nil, 
            owner: nil,
            from: nil, 
            to: nil,
            cc: [],
            subject: nil,
            date: nil,
            body: nil  
end

