local network = {}

local PROTOCOL = "ARCADESYS_FACTORY"
local PING_MESSAGE = "PING"
local PONG_MESSAGE = "PONG"
local SEND_SCHEMA_MESSAGE = "SEND_SCHEMA"

function network.openModem()
    local modem = peripheral.find("modem", function(name, wrapped)
        return wrapped.isWireless()
    end)
    
    if modem then
        rednet.open(peripheral.getName(modem))
        return true
    end
    return false
end

function network.closeModem()
    local modem = peripheral.find("modem", function(name, wrapped)
        return wrapped.isWireless()
    end)
    if modem then
        rednet.close(peripheral.getName(modem))
    end
end

function network.broadcastPresence(label)
    if not rednet.isOpen() then return end
    rednet.broadcast({
        type = PONG_MESSAGE,
        id = os.getComputerID(),
        label = label or os.getComputerLabel() or "Turtle " .. os.getComputerID()
    }, PROTOCOL)
end

function network.findDevices(timeout)
    if not rednet.isOpen() then return {} end
    
    rednet.broadcast({ type = PING_MESSAGE }, PROTOCOL)
    
    local devices = {}
    local timer = os.startTimer(timeout or 2)
    
    while true do
        local event, senderId, message, protocol = os.pullEvent()
        if event == "timer" and senderId == timer then
            break
        elseif event == "rednet_message" and protocol == PROTOCOL then
            if type(message) == "table" and message.type == PONG_MESSAGE then
                table.insert(devices, {
                    id = senderId,
                    label = message.label
                })
            end
        end
    end
    
    return devices
end

function network.sendSchema(targetId, filename, content)
    if not rednet.isOpen() then return false end
    rednet.send(targetId, {
        type = SEND_SCHEMA_MESSAGE,
        filename = filename,
        content = content
    }, PROTOCOL)
    return true
end

function network.listen(callback)
    if not rednet.isOpen() then return end
    
    while true do
        local senderId, message, protocol = rednet.receive(PROTOCOL)
        if type(message) == "table" then
            if message.type == PING_MESSAGE then
                network.broadcastPresence()
            elseif message.type == SEND_SCHEMA_MESSAGE then
                if callback then
                    callback(senderId, message.filename, message.content)
                end
            end
        end
    end
end

return network
