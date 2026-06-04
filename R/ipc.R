#' @importFrom digest digest
#' @importFrom stats runif
NULL

#' Construct a standard RDesk IPC message envelope
#'
#' @description
#' Builds the JSON envelope that both R and the JavaScript frontend use to
#' exchange typed messages. Each envelope carries a unique ID, a message type
#' string, a contract version, an arbitrary payload, and a millisecond-precision
#' Unix timestamp.
#'
#' @details
#' The envelope schema is:
#' \preformatted{
#'   {
#'     "id":        "msg_<epoch_ms>_<random>",
#'     "type":      "<action_name>",
#'     "version":   "1.0",
#'     "payload":   { ... },
#'     "timestamp": <unix_seconds>
#'   }
#' }
#' Large payloads (above 1 MB) trigger a warning so developers notice
#' performance-sensitive serialization early.
#'
#' @param type    Character string. The message type / action name (e.g. \code{"get_data"}).
#' @param payload A named list representing the message data. Defaults to an empty list.
#' @param version IPC contract version string. Defaults to the \code{rdesk.ipc_version} option
#'   (currently \code{"1.0"}).
#' @return A named list representing the standard JSON envelope. Pass this directly to
#'   \code{jsonlite::toJSON()} or to \code{app$send()}.
#' @seealso [rdesk_parse_message()] for the corresponding deserializer.
#' @examples
#' # Construct a typed message with a simple payload
#' msg <- rdesk_message("get_data", list(filter = "cyl == 6"))
#' stopifnot(msg$type == "get_data")
#' stopifnot(msg$version == "1.0")
#' stopifnot(!is.null(msg$id))
#' @export
rdesk_message <- function(type, payload = list(), version = getOption("rdesk.ipc_version", "1.0")) {
  msg <- list(
    id = paste0("msg_", format(Sys.time(), "%s%OS3"), "_", sample.int(9999, 1)),
    type = type,
    version = version,
    payload = payload,
    timestamp = as.numeric(Sys.time())
  )

  msg_json <- jsonlite::toJSON(msg, auto_unbox = TRUE, null = "null")
  msg_size <- nchar(msg_json, type = "bytes")
  if (msg_size > 1e6) {
    warning(
      "[RDesk] Large IPC payload (",
      round(msg_size / 1e6, 1),
      " MB). Consider chunking."
    )
  }

  msg
}

#' Parse and validate an incoming RDesk IPC message
#'
#' @description
#' Deserializes a raw JSON string received from the JavaScript frontend (or from
#' a bundled launcher via stdin) into a validated R list. Performs lightweight
#' structural validation: both \code{type} and \code{payload} fields must be
#' present. Launcher/native events (which carry an \code{event} field instead)
#' bypass validation and are returned as-is.
#'
#' @param raw_json A single-element character string containing the JSON to parse.
#' @return A named list containing the validated message components, or
#'   \code{NULL} if the JSON is malformed or the required fields are absent.
#' @seealso [rdesk_message()] for constructing outgoing messages.
#' @examples
#' # Round-trip: construct then parse
#' msg <- rdesk_message("ping", list(ts = 1234))
#' raw <- jsonlite::toJSON(msg, auto_unbox = TRUE)
#' parsed <- rdesk_parse_message(raw)
#' stopifnot(parsed$type == "ping")
#'
#' # Malformed JSON returns NULL
#' stopifnot(is.null(rdesk_parse_message("not_json")))
#' @export
rdesk_parse_message <- function(raw_json) {
  msg <- tryCatch(jsonlite::fromJSON(raw_json, simplifyVector = FALSE), 
                  error = function(e) NULL)
  
  if (is.null(msg)) return(NULL)

  # Launcher/native events have their own schema
  if (!is.null(msg$event)) return(msg)
  
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
