local HttpService = game:GetService("HttpService")

local URL = "ws://127.0.0.1:8765"
local WebSocket = syn.websocket.connect(URL)

WebSocket.OnMessage:Connect(function(message)
    local ok, data = pcall(HttpService.JSONDecode, HttpService, message)
    if ok and type(data) == "table" then
        -- Action handling will be added after the state protocol is defined.
    end
end)

local function send(data)
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if ok then
        WebSocket:Send(encoded)
    end
end

send({type = "hello", protocol = 1})

print("[AutoGK_FSS] connected to " .. URL)
