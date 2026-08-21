require("duckdb"):setup({
  mode = "summarized",
  cache_size = 1000,
  row_id = "dynamic",
  minmax_column_width = 21,
  column_fit_factor = 10.0,
})
pcall(function() require("git"):setup { order = 1500 } end)
