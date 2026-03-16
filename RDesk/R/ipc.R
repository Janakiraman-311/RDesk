# R/ipc.R
# Bidirectional message router: dispatches incoming WS messages to R handlers

#' Initialize a message router for bidirectional IPC
#'
#' @return A list of functions: register, dispatch, get_handlers
#' @keywords internal
rdesk_make_router <- function() {
  # Returns a list: $register, $dispatch, $handlers
  handlers <- list()

  list(
    register = function(type, fn) {
      handlers[[type]] <<- fn
    },

    dispatch = function(raw_message) {
      tryCatch({
        msg <- jsonlite::fromJSON(raw_message, simplifyVector = FALSE)

        # Validate structure
        if (is.null(msg$type)) {
          warning("[RDesk] Message missing 'type' field: ", raw_message)
          return(invisible(NULL))
        }

        handler <- handlers[[msg$type]]
        if (is.null(handler)) {
          # Unknown type — not an error, just ignore (forward compat)
          return(invisible(NULL))
        }

        # Call handler with payload (default to empty list)
        payload <- if (is.null(msg$payload)) list() else msg$payload
        handler(payload)

      }, error = function(e) {
        warning("[RDesk] Error dispatching message '", raw_message, "': ", e$message)
      })
    },

    get_handlers = function() handlers
  )
}

#' Encode a message into JSON for WebSocket transmission
#'
#' @param type Message type string
#' @param payload Data payload (list)
#' @return JSON string
#' @keywords internal
rdesk_encode_message <- function(type, payload = list()) {
  jsonlite::toJSON(
    list(type = type, payload = payload),
    auto_unbox = TRUE,
    null       = "null",
    na         = "null"
  )
}
