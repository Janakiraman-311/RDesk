library(RDesk)
app <- App$new(title = "Verification App")
app$on_ready(function() {
  message("Success: App is ready!")
  app$quit()
})

# Run the app
# Note: This will print Phase 1 pending message as expected
app$run()
