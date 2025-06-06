-- A registry of warnings and errors identified by different processing steps.

local Issues = {}

function Issues.new(cls)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.errors = {}
  self.warnings = {}
  self.seen_issues = {}
  self.ignored_issues = {}
  return self
end

-- Normalize an issue identifier.
function Issues._normalize_identifier(identifier)
  return identifier:lower()
end

-- Convert an issue identifier to either a table of warnings or a table of errors.
function Issues:_get_issue_table(identifier)
  identifier = self._normalize_identifier(identifier)
  local prefix = identifier:sub(1, 1)
  if prefix == "s" or prefix == "w" then
    return self.warnings
  elseif prefix == "t" or prefix == "e" then
    return self.errors
  else
    assert(false, 'Identifier "' .. identifier .. '" has an unknown prefix "' .. prefix .. '"')
  end
end

-- Add an issue to the table of issues.
function Issues:add(identifier, message, range)
  identifier = self._normalize_identifier(identifier)

  -- Discard duplicate issues.
  local range_start = (range ~= nil and range:start()) or false
  local range_end = (range ~= nil and range:stop()) or false
  if self.seen_issues[identifier] == nil then
    self.seen_issues[identifier] = {}
  end
  if self.seen_issues[identifier][range_start] == nil then
    self.seen_issues[identifier][range_start] = {}
  end
  if self.seen_issues[identifier][range_start][range_end] == nil then
    self.seen_issues[identifier][range_start][range_end] = true
  else
    return
  end

  -- Construct the issue.
  local issue = {identifier, message, range}

  -- Determine if the issue should be ignored.
  for _, ignore_issue in ipairs(self.ignored_issues) do
    if ignore_issue(issue) then
      return
    end
  end

  -- Add the issue to the table of issues.
  local issue_table = self:_get_issue_table(identifier)
  table.insert(issue_table, issue)
end

-- Prevent issues from being present in the table of issues.
function Issues:ignore(identifier, range)
  if identifier ~= nil then
    identifier = self._normalize_identifier(identifier)
  end

  -- Determine which issues should be ignored.
  local function match_issue_range(issue_range)
    return (
      issue_range:start() >= range:start() and issue_range:start() <= range:stop()  -- issue starts within range
      or issue_range:start() <= range:start() and issue_range:stop() >= range:stop()  -- issue is in middle of range
      or issue_range:stop() >= range:start() and issue_range:stop() <= range:stop()  -- issue ends within range
    )
  end
  local function match_issue_identifier(issue_identifier)
    return issue_identifier == identifier
  end

  local ignore_issue, issue_tables
  if identifier == nil then
    -- Prevent any issues within the given range.
    assert(range ~= nil)
    issue_tables = {self.warnings, self.errors}
    ignore_issue = function(issue)
      local issue_range = issue[3]
      if issue_range == nil then  -- file-wide issue
        return false
      else  -- ranged issue
        return match_issue_range(issue_range)
      end
    end
  elseif range == nil then
    -- Prevent any issues with the given identifier.
    assert(identifier ~= nil)
    issue_tables = {self:_get_issue_table(identifier)}
    ignore_issue = function(issue)
      local issue_identifier = issue[1]
      return match_issue_identifier(issue_identifier)
    end
  else
    -- Prevent any issues with the given identifier that are also either within the given range or file-wide.
    assert(range ~= nil and identifier ~= nil)
    issue_tables = {self:_get_issue_table(identifier)}
    ignore_issue = function(issue)
      local issue_identifier = issue[1]
      local issue_range = issue[3]
      if issue_range == nil then  -- file-wide issue
        return match_issue_identifier(issue_identifier)
      else  -- ranged issue
        return match_issue_range(issue_range) and match_issue_identifier(issue_identifier)
      end
    end
  end

  -- Remove the issue if it has already been added.
  for _, issue_table in ipairs(issue_tables) do
    local filtered_issues = {}
    for _, issue in ipairs(issue_table) do
      if not ignore_issue(issue) then
        table.insert(filtered_issues, issue)
      end
    end
    for issue_index, issue in ipairs(filtered_issues) do
      issue_table[issue_index] = issue
    end
    for issue_index = #filtered_issues + 1, #issue_table, 1 do
      issue_table[issue_index] = nil
    end
  end

  -- Prevent the issue from being added later.
  table.insert(self.ignored_issues, ignore_issue)
end

-- Check whether two registries only contain issues with the same codes.
function Issues:has_same_codes_as(other)
  -- Collect codes of all issues.
  local self_codes, other_codes = {}, {}
  for _, table_name in ipairs({'warnings', 'errors'}) do
    for _, tables in ipairs({{self[table_name], self_codes}, {other[table_name], other_codes}}) do
      local issue_table, codes = table.unpack(tables)
      for _, issue in ipairs(issue_table) do
        local code = issue[1]
        codes[code] = true
      end
    end
  end
  -- Check whether this registry has any extra codes.
  for code, _ in pairs(self_codes) do
    if other_codes[code] == nil then
      return false
    end
  end
  -- Check whether the other registry has any extra codes.
  for code, _ in pairs(other_codes) do
    if self_codes[code] == nil then
      return false
    end
  end
  return true
end

-- Sort the warnings/errors using location as the primary key.
function Issues.sort(warnings_and_errors)
  local sorted_warnings_and_errors = {}
  for _, issue in ipairs(warnings_and_errors) do
    local identifier = issue[1]
    local message = issue[2]
    local range = issue[3]
    table.insert(sorted_warnings_and_errors, {identifier, message, range})
  end
  table.sort(sorted_warnings_and_errors, function(a, b)
    local a_identifier, b_identifier = a[1], b[1]
    local a_range, b_range = (a[3] and a[3]:start()) or 0, (b[3] and b[3]:start()) or 0
    return a_range < b_range or (a_range == b_range and a_identifier < b_identifier)
  end)
  return sorted_warnings_and_errors
end

return function()
  return Issues:new()
end
