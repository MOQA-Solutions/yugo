defmodule Yugo.Presence.ImapPresence do 

  require Record

  Record.defrecord(:imap_presence, 
                   email: nil,
                   pid: nil
                  )  
end 
