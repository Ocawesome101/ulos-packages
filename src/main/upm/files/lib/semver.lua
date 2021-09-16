-- semver: Very scrict semantic versioning library --

local lib = {}

local pattern = "^(%d+)%.(%d+)%.(%d+)([%S%-%.a-zA-Z0-9]*)([%S%+%.a-zA-Z0-9]*)$"

function lib.build(version)
  checkArg(1, version, "table")
  checkArg("major", version.major, "number")
  checkArg("minor", version.minor, "number")
  checkArg("patch", version.patch, "number")
  checkArg("prerelease", version.prerelease, "table", "string", "nil")
  checkArg("build", version.build, "table", "string", "nil")
  version.prerelease = version.prerelease or ""
  version.build = version.build or ""
  if type(version.prerelease) == "table" then
    version.prerelease = table.concat(version.prerelease, ".")
  end
  if type(version.build) == "table" then
    version.build = table.concat(version.build, ".")
  end
  if version.prerelease:match("[^%S%-a-zA-Z0-9%.]")
      or version.prerelease:match("%.%.") then
    return nil, "pre-release suffix contains invalid character(s)"
  end
  if version.build:match("[^%S%-a-zA-Z0-9%.]")
      or version.build:match("%.%.") then
    return nil, "build metadata suffix contains invalid character(s)"
  end
  local final = string.format("%d.%d.%d", version.major, version.minor,
    version.patch)
  if #version.prerelease > 0 then
    final = final .. "-" .. version.prerelease
  end
  if #version.build > 0 then
    final = final .. "+" .. version.build
  end
  return final
end

function lib.parse(vers)
  checkArg(1, vers, "string")
  local maj, min, pat, pre, build = vers:match(pattern)
  if not maj then
    return nil, "invalid version string"
  end

  if pre:sub(1,1) == "+" then
    build = pre
    pre = ""
  end
  pre = pre:sub(2)
  build = build:sub(2)
  if build:match("%+") then
    return nil, "invalid build metadata"
  end

  local pt, bt = {}, {}
  for ent in pre:gmatch("[^%.]+") do
    pt[#pt + 1] = ent
  end
  for ent in build:gmatch("[^.]+") do
    bt[#bt + 1] = ent
  end

  return {
    major = tonumber(maj),
    minor = tonumber(min),
    patch = tonumber(pat),
    prerelease = pt,
    build = bt
  }
end

local function cmp_pre(a, b)
  for i=1, #a, 1 do
    if not b[i] then return true end
    if type(a[i]) == type(b[i]) then
      if a[i] > b[i] then
        return true
      end
    elseif type(a[i]) == "string" then
      return true
    end
  end
  return false
end

-- if v1 > v2
function lib.isGreater(v1, v2)
  checkArg(1, v1, "table")
  checkArg(2, v2, "table")
  return (
    v1.major > v2.major or
    v1.minor > v2.minor or
    v1.patch > v2.patch or
    (#v1.prerelease == 0 and #v2.prerelease > 0) or
    cmp_pre(v1.prerelease, v2.prerelease) or
    #v1.prerelease > #v2.prerelease
  )
end

return lib
