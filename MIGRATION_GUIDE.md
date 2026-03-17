# Migrating Existing Shiny Apps to RDesk
This guide explains how to take an existing R Shiny application and adapt it to the RDesk framework to gain native desktop features and standalone portability.

> [!IMPORTANT]
> **Do I need to know C++?**
> **No.** You do **not** need to know any C++ to use RDesk. The native C++ launcher is provided as a pre-compiled engine within the R package. You only focus on your **R logic** and **HTML/CSS/JS UI**.

## 1. Understanding the Architecture
RDesk is **not** a direct wrapper for Shiny's `ui.R` and `server.R`. Instead, it replaces the web browser with a **Native C++ Window** and the Shiny server with a high-performance **IPC Bridge**.

| Feature | Shiny | RDesk |
| :--- | :--- | :--- |
| **UI** | `fluidPage()`, `bslib`, etc. | Standard HTML5, CSS3, JS (Vanilla or React/Vue) |
| **Backend** | Reactive Server Logic | R6 `App` class with `on_message` handlers |
| **Window** | Chrome/Edge/Firefox | Custom Native C++ Shell (WebView2) |
| **Nativism** | Web-isolated | Full access to System Tray, Notifications, Dialogs |

---

## 2. Step-by-Step Migration

### Step 1: Create your Project Folder
Organize your new project like this:
```text
my_new_app/
├── www/
│   ├── index.html   <-- Your UI (HTML/CSS/JS)
│   ├── style.css
│   └── script.js
└── app.R           <-- Your Logic
```

### Step 2: Convert your UI to HTML
Instead of `sidebarPanel()` or `actionButton()`, use standard HTML. Include the `rdesk.js` bridge:
```html
<!-- www/index.html -->
<script src="rdesk.js"></script>
<button onclick="rdesk.send('calculate', {x: 10})">Calculate</button>
<div id="result"></div>

<script>
  rdesk.on('display', (payload) => {
    document.getElementById('result').innerText = payload.value;
  });
</script>
```

### Step 3: Convert Server Logic to RDesk
Replace your `server <- function(input, output)` logic with `app$on_message()` handlers:

```r
# app.R
library(RDesk)

app <- App$new(title = "My New Mobile App", width = 800, height = 600)

# Replace input$calculate with this:
app$on_message("calculate", function(payload) {
  result <- payload$x * 2
  # Replace output$result with this:
  app$send("display", list(value = result))
})

app$run()
```

### Step 4: Add Desktop Extras
Now you can add features Shiny cannot do:
```r
app$on_ready(function() {
  app$set_tray(label = "My App is Running")
  app$notify("Started!", "The application is ready.")
})
```

---

## 3. Creating the Portable Desktop App
Once your `app.R` is working, you can turn it into a standalone `.exe` folder that requires **zero** setup for the end user:

```r
RDesk::build_app(
  app_dir  = "path/to/my_new_app",
  app_name = "DesktopStatsApp"
)
```

## 4. Tips for bslib Users
If you love `bslib` styling, you can simply use the [Bootstrap 5 CSS CDN](https://getbootstrap.com/) in your `index.html`. You get the same beautiful look as your old Shiny apps, but with the speed and power of a native desktop application.

---

**RDesk turns your R scripts into professional software.** 🚀
