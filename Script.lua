local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local URL = "ws://127.0.0.1:8765"

local Socket = WebSocket.connect(URL)

local function vector3ToTable(value)
    return {
        x = value.X,
        y = value.Y,
        z = value.Z,
    }
end

local function getPlayerState()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not root then
        return nil
    end

    return {
        position = vector3ToTable(root.Position),
        velocity = vector3ToTable(root.AssemblyLinearVelocity),
        team = LocalPlayer.Team and LocalPlayer.Team.Name or nil,
    }
end

Socket.OnMessage:Connect(function(message)
    local ok, data = pcall(HttpService.JSONDecode, HttpService, message)

    if ok and type(data) == "table" then
        if data.type == "hello" then
            print("[AutoGK_FSS] Python server connected")
        elseif data.type == "action" then
            -- Action handling will be added later.
        end
    end
end)

local function send(data)
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)

    if ok then
        Socket:Send(encoded)
    end
end

local function sendState()
    send({
        type = "state",
        timestamp = os.clock(),
        player = getPlayerState(),
    })
end

send({
    type = "hello",
    protocol = 1,
})

task.spawn(function()
    while true do
        sendState()
        task.wait(0.1)
    end
end)

print("[AutoGK_FSS] connected to " .. URL)
