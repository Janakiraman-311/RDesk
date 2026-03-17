#' Construct a standard RDesk IPC message envelope
#'
#' @param type The message type/action name
#' @param payload A list representing the message data
#' @param version The contract version (default "1.0")
#' @return A list representing the standard JSON envelope
#' @keywords internal
rdesk_message <- function(type, payload = list(), version = getOption("rdesk.ipc_version", "1.0")) {
  list(
    id = paste0("msg_", digest::digest(runif(1), algo = "crc32")),
    type = type,
    version = version,
    payload = payload,
    timestamp = as.numeric(Sys.time())
  )
}

#' Parse and validate an incoming RDesk IPC message
#'
#' @param raw_json The raw JSON string from the frontend
#' @return A list containing the validated message components, or NULL if invalid
#' @keywords internal
rdesk_parse_message <- function(raw_json) {
  msg <- tryCatch(jsonlite::fromJSON(raw_json, simplifyVector = FALSE), 
                  error = function(e) NULL)
  
  if (is.null(msg)) return(NULL)
  
  # Structural validation
  required <- c("type", "payload")
  if (!all(required %in% names(msg))) {
    warning("[RDesk] IPC: Incoming message missing required fields: ", 
            paste(setdiff(required, names(msg)), collapse = ", "))
    return(NULL)
  }
  
  # Ensure payload is a list
  if (!is.list(msg$payload)) msg$payload <- list()
  
  msg
}

#' Create an IPC message router
#'
#' @return A list with register() and dispatch() methods
#' @keywords internal
rdesk_make_router <- function() {
  handlers <- new.env(parent = emptyenv())
  
  list(
    register = function(type, fn) {
      handlers[[type]] <- fn
    },
    dispatch = function(type, payload) {
      fn <- handlers[[type]]
      if (is.function(fn)) {
        tryCatch(fn(payload), 
                 error = function(e) warning("[RDesk] handler error for ", type, ": ", e$message))
      } else {
        # Silent ignore for unknown types (common in JS events)
      }
    }
  )
}
