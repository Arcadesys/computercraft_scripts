-- Legacy wrapper: prefer install.lua going forward.
if fs and fs.exists and fs.exists("install.lua") then
    shell.run("install.lua")
    return
end

print("install.lua missing; please re-download the repository.")
