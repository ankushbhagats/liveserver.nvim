return {
  filetypes = { -- specify files to show lualine toggle button. set: "*" to allow all files.
    html = true,
    css = true,
    javascript = true,
    typescript = true,
  },
   args = { -- this table hold actual ARGS of liveserver program.
      port = 5555,
      host = "127.0.0.1",
      ["no-browser"] = false, -- set true to prevent auto opening the browser.
      watch = "*.html,*.css,*.js", -- automatically reload browser for specified files.
    },
  colortype = "hl", -- "hl" | "hex"
  states = { -- default state config
    idle = {
      icon = "",
      color = { -- hex colors only.
        fg = "#aaddff",
        bg = nil,
      },
      hl = { -- fg/bg: 1st value is the highlight group name, 2nd is hl value field to use.
        fg = { "lualine_a_normal", "bg" },
        bg = { "lualine_c_normal", "bg" },
      },
      text = "serve",
      gui = "bold",
    },
    start = {
      icon = "󰐰",
      color = {
        fg = "#ffee55",
        bg = nil,
      },
      hl = {
        fg = { "lualine_a_command", "bg" },
        bg = { "lualine_c_normal", "bg" },
      },
      text = "starting…",
      gui = "bold",
    },
    stop = {
      icon = "",
      color = {
        fg = "#fc5600",
        bg = nil,

      },
      hl = {
        fg = { "lualine_a_replace", "bg" },
        bg = { "lualine_c_normal", "bg" },
      },
      text = "stopping…",
      gui = "bold",
    },
    running = {
      icon = "",
      color = {
        fg = "#fc5600",
        bg = nil,
      },
      hl = {
        fg = { "lualine_a_replace", "bg" },
        bg = { "lualine_c_normal", "bg" },
      },
      text = "port:",
      gui = "bold",

    },
 },
}


