require "vis"
ec = require "editorconfig"

-- Simple wrapper
function vis_set(option, value)
  if type(value) == "boolean" then
    if value then
      value = "yes"
    else
      value = "no"
    end
  end

  vis:command("set " .. option .. " " .. value)
end

function set_pre_save(f, value)
  if value == "true" then
    vis.events.subscribe(vis.events.FILE_SAVE_PRE, f)
  else
    vis.events.unsubscribe(vis.events.FILE_SAVE_PRE, f)
  end
end

function set_file_open(f, value)
  if value == "true" then
    vis.events.subscribe(vis.events.FILE_OPEN, f)
  else
    vis.events.unsubscribe(vis.events.FILE_OPEN, f)
  end
end

-- Custom functionality
function insert_final_newline(file, path)
  if file:content(file.size-1, file.size) ~= '\n' then
    file:insert(file.size, '\n')
  end
end

function trim_trailing_whitespace(file, path)
  for i=1, #file.lines do
    if string.match(file.lines[i], '[ \t]$') then
      file.lines[i] = string.gsub(file.lines[i], '[ \t]*$', '')
    end
  end
end

function enforce_crlf_eol(file, path)
  for i=1, #file.lines do
    if not string.match(file.lines[i], '\r$') then
      file.lines[i] = string.gsub(file.lines[i], '$', '\r')
    end
  end
end

function enforce_lf_eol(file, path)
  for i=1, #file.lines do
    if string.match(file.lines[i], '\r$') then
      file.lines[i] = string.gsub(file.lines[i], '\r$', '')
    end
  end
end

global_max_line_length = 80     -- This is ugly, but we do want to use
                                -- single function that we can register
                                -- or unregister as needed
function max_line_length(file, path)
  local overlong_lines = {}
  for i=1, #file.lines do
    if string.len(file.lines[i]) > global_max_line_length then
      table.insert(overlong_lines, i)
    end
  end
  if #overlong_lines > 0 then
    local lines_are = (function(x)
        if x>1 then return "lines are" else return "line is" end
    end)(#overlong_lines)
    vis:info(string.format(
      "%d %s longer than %d characters: %s",
      #overlong_lines, lines_are, global_max_line_length,
      table.concat(overlong_lines, ",")
    ))
  end
end

OPTIONS = {
  indent_style = function (value)
    vis_set("expandtab", (value == "space"))
  end,

  indent_size = function (value)
    if value ~= "tab" then -- tab_width is a synonym anyway
      vis_set("tabwidth", value)
    end
  end,

  tab_width = function (value)
    vis_set("tabwidth", value)
  end,

  insert_final_newline = function (value)
    set_pre_save(insert_final_newline, value)
  end,

  trim_trailing_whitespace = function (value)
    set_pre_save(trim_trailing_whitespace, value)
  end,

  -- End of line is only partially implemented. While vis does not
  -- support customized newlines, it does work well enough with crlf
  -- newlines. Therefore, setting end_of_line=crlf will just ensure
  -- that there is a cr at the end of each line. Setting end_of_line=lf
  -- will strip any cr characters at the end of lines. This hopefully
  -- eases the pain of working with crlf files a little.
  end_of_line = function (value)
    set_pre_save(enforce_crlf_eol, tostring(value == "crlf"))
    set_pre_save(enforce_lf_eol, tostring(value == "lf"))
  end,

  -- There is probably no straightforward way to enforce a maximum line
  -- length across different programming languages. If a maximum line
  -- length is set, we can at least issue a warning, however.
  max_line_length = function(value)
    if value ~= "off" then
      global_max_line_length = tonumber(value)
    end
    set_pre_save(max_line_length, tostring(value ~= "off"))
  end,

  -- Not supported by vis
  --   charset
  -- Partial support
  --   end_of_line
  --   max_line_length
}

-- Compatible with editorconfig-core-lua v0.3.0
function ec_iter(p)
  i = 0
  props, keys = ec.parse(p)
  n = #keys
  return function ()
    i = i + 1
    if i <= n then
      return keys[i], props[keys[i]]
    end
  end
end

function ec_set_values(path)
  if path then
    for name, value in ec_iter(path) do
      if OPTIONS[name] then
        OPTIONS[name](value)
      end
    end
  end
end

function ec_parse_cmd() ec_set_values(vis.win.file.path) end
vis:command_register("econfig_parse", ec_parse_cmd, "(Re)parse an editorconfig file")

vis.events.subscribe(vis.events.FILE_OPEN, function (file)
  ec_set_values(file.path)
end)

vis.events.subscribe(vis.events.FILE_SAVE_POST, function (file, path)
  ec_set_values(file.path)
end)
