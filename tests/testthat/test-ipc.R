test_that("rdesk_message() produces correct envelope", {
  msg <- rdesk_message("test_type", list(x = 1))

  expect_named(msg, c("id", "type", "version", "payload", "timestamp"),
               ignore.order = TRUE)
  expect_equal(msg$type, "test_type")
  expect_equal(msg$version, getOption("rdesk.ipc_version", "1.0"))
  expect_equal(msg$payload, list(x = 1))
  expect_true(is.numeric(msg$timestamp))
  expect_true(grepl("^msg_", msg$id))
})

test_that("rdesk_message() generates unique IDs", {
  ids <- replicate(50, rdesk_message("t", list())$id)
  expect_equal(length(unique(ids)), 50)
})

test_that("rdesk_parse_message() returns NULL on bad JSON", {
  expect_null(rdesk_parse_message("not json"))
  expect_null(rdesk_parse_message(""))
  expect_null(rdesk_parse_message("{bad}"))
})

test_that("rdesk_parse_message() returns NULL on missing fields", {
  expect_warning(expect_null(rdesk_parse_message('{"type":"x"}')), "missing required fields")
  expect_warning(expect_null(rdesk_parse_message('{"payload":{}}')), "missing required fields")
})

test_that("rdesk_parse_message() parses valid envelope", {
  json <- jsonlite::toJSON(
    rdesk_message("ping", list(value = 42)),
    auto_unbox = TRUE
  )
  result <- rdesk_parse_message(json)
  expect_false(is.null(result))
  expect_equal(result$type, "ping")
  expect_equal(result$payload$value, 42)
})

test_that("rdesk_parse_message() coerces non-list payload to list", {
  json <- '{"type":"x","payload":"not_a_list"}'
  result <- rdesk_parse_message(json)
  expect_false(is.null(result))
  expect_true(is.list(result$payload))
})
