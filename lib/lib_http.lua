-- lib_http.lua
-- Shared HTTP utilities for downloading files

local M = {}

--- Downloads a file from a URL and saves it to the specified path.
-- @param url string The URL to download from
-- @param path string The local path to save the file to
-- @return boolean success True if download succeeded
-- @return string|nil error Error message if download failed
function M.downloadFile(url, path)
    if not http then
        return false, "HTTP API disabled"
    end
    
    local response = http.get(url)
    if not response then
        return false, "Failed to connect"
    end
    
    local content = response.readAll()
    response.close()
    
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    local file = fs.open(path, "w")
    if file then
        file.write(content)
        file.close()
        return true
    else
        return false, "Write failed"
    end
end

return M
