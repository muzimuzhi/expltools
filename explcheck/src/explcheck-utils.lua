-- Common functions used by different modules of the static analyzer explcheck.

-- Convert a byte number in a file to a line and column number in a file.
local function convert_byte_to_line_and_column(line_starting_byte_numbers, byte_number)
  local line_number = 0
  for _, line_starting_byte_number in ipairs(line_starting_byte_numbers) do
    if line_starting_byte_number > byte_number then
      break
    end
    line_number = line_number + 1
  end
  assert(line_number > 0)
  local line_starting_byte_number = line_starting_byte_numbers[line_number]
  assert(line_starting_byte_number <= byte_number)
  local column_number = byte_number - line_starting_byte_number + 1
  return line_number, column_number
end

-- Convert a pathname of a file to the suffix of the file.
local function get_suffix(pathname)
  return pathname:gsub(".*%.", "."):lower()
end

-- Convert a pathname of a file to the base name of the file.
local function get_basename(pathname)
  return pathname:gsub(".*[\\/]", "")
end

-- Convert a pathname of a file to the stem of the file.
local function get_stem(pathname)
  return get_basename(pathname):gsub("%..*", "")
end

-- Convert a pathname of a file to the pathname of its parent directory.
local function get_parent(pathname)
  if pathname:find("[\\/]") then
    return pathname:gsub("(.*)[\\/].*", "%1")
  else
    return "."
  end
end

-- Return all parameters unchanged, mostly used for no-op map-back and map-forward functions.
local function identity(...)
  return ...
end

-- Run all processing steps.
local function process_with_all_steps(pathname, content, issues, analysis_results, options)
  local get_option = require("explcheck-config").get_option
  local preprocessing = require("explcheck-preprocessing")
  local lexical_analysis = require("explcheck-lexical-analysis")
  local syntactic_analysis = require("explcheck-syntactic-analysis")
  local semantic_analysis = require("explcheck-semantic-analysis")
  local steps = {preprocessing, lexical_analysis, syntactic_analysis, semantic_analysis}
  for _, step in ipairs(steps) do
    step.process(pathname, content, issues, analysis_results, options)
    -- If a processing step ended with error, skip all following steps.
    if #issues.errors > 0 and get_option('fail_fast', options, pathname) then
      return
    end
  end
end

return {
  convert_byte_to_line_and_column = convert_byte_to_line_and_column,
  get_basename = get_basename,
  get_parent = get_parent,
  get_stem = get_stem,
  get_suffix = get_suffix,
  identity = identity,
  process_with_all_steps = process_with_all_steps,
}
