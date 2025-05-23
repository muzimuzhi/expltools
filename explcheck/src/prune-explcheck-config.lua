#!/usr/bin/env texlua
-- A checker that reads the default configuration of the static analyzer explcheck and regression test results
-- and then tests which parts of the configuration can be removed without affecting the results of the static analysis.

local kpse = require("kpse")
kpse.set_program_name("texlua", "prune-explcheck-config")

local config = require("explcheck-config")
local new_issues = require("explcheck-issues")
local process_with_all_steps = require("explcheck-utils").process_with_all_steps

local default_config = config.default_config
local default_config_pathname = config.default_config_pathname
local get_package = config.get_package

-- Read regression test results and use KPathSea to find the files in the results.
local function read_results(results_pathname)
  local num_skipped = 0
  local results = {
    filenames = {},
    pathnames = {},
    issues = {},
  }
  for line in io.lines(results_pathname) do
    local line_filename, issues = line:match("^(%S+)%s+(%S+)$")
    assert(line_filename ~= nil)
    assert(issues ~= nil)
    local line_pathname = kpse.find_file(line_filename)
    if line_pathname == nil then
      num_skipped = num_skipped + 1
      goto continue
    end
    table.insert(results.filenames, line_filename)
    results.pathnames[line_filename] = line_pathname
    results.issues[line_filename] = new_issues()
    for issue in issues:gmatch("[^,]+") do
      results.issues[line_filename]:add(issue)
    end
    ::continue::
  end
  io.write(string.format('Read %d files', #results.filenames))
  if num_skipped > 0 then
    io.write(string.format(', skipped %d files', num_skipped))
  end
  print(string.format(' from file "%s".', results_pathname))
  return results
end

-- For each file from regression test results, try to remove all options in the default configuration that apply to it and check
-- whether this affects the results of the static analysis or not.
local function main(results_pathname)
  -- Read the results.
  local results = read_results(results_pathname)

  local num_options = 0
  local key_locations = {
    seen = {},
    results = {},
    to_remove = {},
  }

  -- Try to remove a single option.
  local function try_to_remove_option(pathname, key, key_location, default_value, expected_issues)
    if key_locations.results[key_location] == nil then
      table.insert(key_locations.seen, key_location)
      key_locations.results[key_location] = {}
    end

    num_options = num_options + 1

    -- Run all steps of the static analysis.
    local actual_issues = new_issues()
    local options = {[key] = default_value}
    local file = assert(io.open(pathname, "r"))
    local content = assert(file:read("*a"))
    assert(file:close())
    local analysis_results = {}
    process_with_all_steps(pathname, content, actual_issues, analysis_results, options)

    -- Compare the expected results of the static analysis with the actual results.
    local result = actual_issues:has_same_codes_as(expected_issues)
    table.insert(key_locations.results[key_location], result)
  end

  -- Try to remove all options in a section of the config file.
  local function try_to_remove_all_options(pathname, options, options_location, expected_issues)
    local keys = {}
    for key, _ in pairs(options) do
      table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local value = options[key]
      assert(value ~= nil)
      if type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' then
        local default_value = default_config.defaults[key]
        assert(default_value ~= nil)
        local key_location = string.format('Option "%s" in %s', key, options_location)
        try_to_remove_option(pathname, key, key_location, default_value, expected_issues)
      elseif type(value) == 'table' then
        for i, item in ipairs(value) do
          local key_location = string.format('Item "%s" in option "%s" in %s', item, key, options_location)
          local smaller_value = {}
          for j = 1, #value do
            if i ~= j then
              table.insert(smaller_value, value[j])
            end
          end
          try_to_remove_option(pathname, key, key_location, smaller_value, expected_issues)
        end
      end
    end
  end

  -- Try to remove all options for the individual files from the test results.
  for _, filename in ipairs(results.filenames) do
    local pathname = results.pathnames[filename]
    local expected_issues = results.issues[filename]
    assert(pathname ~= nil)
    assert(expected_issues ~= nil)
    -- If the configuration specifies options for this filename, check them.
    if default_config.filename and default_config.filename[filename] ~= nil then
      local options_location = string.format('section [filename."%s"]', filename)
      try_to_remove_all_options(pathname, default_config.filename[filename], options_location, expected_issues)
    end
    -- If the configuration specifies options for this package, check them.
    local package = get_package(pathname)
    if default_config.package and default_config.package[package] ~= nil then
      local options_location = string.format('section [package."%s"]', package)
      try_to_remove_all_options(pathname, default_config.package[package], options_location, expected_issues)
    end
  end

  -- Collect all options that can be removed without affecting any files from the test results.
  for _, key_location in ipairs(key_locations.seen) do
    for _, result in ipairs(key_locations.results[key_location]) do
      if not result then
        goto skip_key_location
      end
    end
    table.insert(key_locations.to_remove, key_location)
    ::skip_key_location::
  end

  -- Print the results.
  io.write(string.format('Checked %d different options in file "%s"', num_options, default_config_pathname))
  if #key_locations.to_remove == 0 then
    print(string.format(', none of which can be removed without affecting file "%s".', results_pathname))
  else
    print(string.format(', %d of which can be removed without affecting file "%s":', #key_locations.to_remove, results_pathname))
    for _, key_location in ipairs(key_locations.to_remove) do
      print(string.format('- %s', key_location))
    end
  end

  if #key_locations.to_remove > 0 then
    os.exit(1)
  end
end

local function print_usage()
  print("Usage: " .. arg[0] .. " TEST_RESULTS\n")
  print("Test which parts of the default config file can be removed without affecting static analysis results.")
end

if #arg ~= 1 then
  print_usage()
  os.exit(1)
else
  local results_pathname = arg[1]
  main(results_pathname)
end
