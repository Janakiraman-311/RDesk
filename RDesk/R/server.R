# R/server.R
# httpuv server: handles HTTP static file serving AND WebSocket IPC

#' Start the internal httpuv server
#'
#' @param port TCP port to listen on
#' @param www_path Path to the web assets directory
#' @param ws_handler Function called when a WebSocket connection is established
#' @return An httpuv server object
#' @keywords internal
rdesk_start_server <- function(port, www_path, ws_handler) {
  # ws_handler is a function(ws_session) called when the UI connects

  httpuv::startServer("127.0.0.1", port, list(

    # ── WebSocket connection opened ─────────────────────────────────────────
    onWSOpen = function(ws) {
      ws_handler(ws)  # pass the live session to App.R to store
    },

    # ── HTTP: serve static files from www_path ──────────────────────────────
    call = function(req) {
      path_info <- req$PATH_INFO
      if (path_info == "" || path_info == "/") path_info <- "/index.html"

      # Security: block path traversal
      full_path <- normalizePath(
        file.path(www_path, substring(path_info, 2)),
        mustWork = FALSE
      )
      if (!startsWith(full_path, normalizePath(www_path))) {
        return(list(
          status  = 403L,
          headers = list("Content-Type" = "text/plain"),
          body    = "Forbidden"
        ))
      }

      # Serve rdesk.js from inst/www/ regardless of app www folder
      if (path_info == "/rdesk.js") {
        full_path <- system.file("www", "rdesk.js", package = "RDesk")
        # During dev if not installed
        if (full_path == "") {
           full_path <- file.path(getwd(), "inst", "www", "rdesk.js")
        }
      }

      if (!file.exists(full_path)) {
        return(list(
          status  = 404L,
          headers = list("Content-Type" = "text/plain"),
          body    = paste("Not found:", path_info)
        ))
      }

      content_type <- rdesk_mime_type(full_path)
      is_binary    <- !grepl("^text/|javascript|json", content_type)

      body <- if (is_binary) {
        readBin(full_path, raw(), file.info(full_path)$size)
      } else {
        paste(readLines(full_path, warn = FALSE), collapse = "\n")
      }

      list(
        status  = 200L,
        headers = list(
          "Content-Type"  = content_type,
          "Cache-Control" = "no-cache"
        ),
        body = body
      )
    }
  ))
}

#' Get MIME type based on file extension
#'
#' @param path File path
#' @return MIME type string
#' @keywords internal
rdesk_mime_type <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    html = "text/html; charset=utf-8",
    js   = "application/javascript",
    css  = "text/css",
    json = "application/json",
    png  = "image/png",
    jpg  = , jpeg = "image/jpeg",
    gif  = "image/gif",
    svg  = "image/svg+xml",
    ico  = "image/x-icon",
    woff = "font/woff",
    woff2= "font/woff2",
    "application/octet-stream"
  )
}
