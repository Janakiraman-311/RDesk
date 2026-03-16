# tests/manual/verify_server.R
library(devtools)
load_all("c:/Users/Janak/OneDrive/Documents/RDesk/RDesk", recompile = FALSE)

tryCatch({
  port <- RDesk:::rdesk_free_port()
  message("Found free port: ", port)
  
  www_path <- RDesk:::rdesk_resolve_www(NULL)
  message("Resolved www path: ", www_path)
  
  if (!dir.exists(www_path)) stop("www path does not exist!")
  
  server <- RDesk:::rdesk_start_server(port, www_path, function(ws) {
    message("WS handler initialized")
  })
  
  message("Server started successfully at http://127.0.0.1:", port)
  
  # Brief delay to ensure server is receptive
  Sys.sleep(1)
  
  httpuv::stopServer(server)
  message("Server stopped successfully")
  
}, error = function(e) {
  message("ERROR: ", e$message)
  quit(status = 1)
})
