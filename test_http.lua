local url = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/manifest.json"

print("Testing HTTP connectivity...")
print("URL: " .. url)

if not http then
    print("Error: HTTP API is disabled!")
    return
end

print("Attempting fetch...")
local response, err = http.get(url)

if response then
    print("Success! Response code: " .. response.getResponseCode())
    response.close()
else
    print("Failed!")
    print("Error: " .. tostring(err))
end
