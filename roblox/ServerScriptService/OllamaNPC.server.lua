-- Place in ServerScriptService as OllamaNPC.server.lua.
-- Workspace must contain a rig Model named "OllamaNPC" with Humanoid,
-- HumanoidRootPart and Head. Enable Game Settings > Security > Allow HTTP Requests.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local CONFIG = {
    BRIDGE_URL = "https://YOUR-QUICK-TUNNEL.trycloudflare.com",
    -- Used only in Studio. In a published game, create a Roblox Secret named OLLAMA_TOKEN.
    STUDIO_TEST_TOKEN = "PASTE_THE_SAME_RANDOM_TOKEN_HERE",
    CHAT_PREFIX = "!ai ",
    WANDER_RADIUS = 35,
    THINK_COOLDOWN = 3,
    MAX_MESSAGE_LENGTH = 500,
}

local npc = Workspace:WaitForChild("OllamaNPC")
local humanoid = npc:WaitForChild("Humanoid")
local root = npc:WaitForChild("HumanoidRootPart")
local head = npc:WaitForChild("Head")
local spawnPosition = root.Position
local currentState = "wander"
local currentTarget: Player? = nil
local behaviorVersion = 0
local busy = false
local lastChat: {[number]: number} = {}

pcall(function()
    root:SetNetworkOwner(nil)
end)

local bubbleEvent = ReplicatedStorage:FindFirstChild("OllamaNPCBubble")
if not bubbleEvent then
    bubbleEvent = Instance.new("RemoteEvent")
    bubbleEvent.Name = "OllamaNPCBubble"
    bubbleEvent.Parent = ReplicatedStorage
end

local prompt = head:FindFirstChildOfClass("ProximityPrompt")
if not prompt then
    prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Поговорить"
    prompt.ObjectText = "Gemma NPC"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 12
    prompt.Parent = head
end

local function getToken()
    local ok, secret = pcall(function()
        return HttpService:GetSecret("OLLAMA_TOKEN")
    end)
    if ok and secret then
        return secret
    end
    if RunService:IsStudio() then
        return CONFIG.STUDIO_TEST_TOKEN
    end
    warn("[OllamaNPC] Roblox Secret OLLAMA_TOKEN is not configured.")
    return nil
end

local function speakToPlayer(player: Player, message: string)
    if not player or not player.Parent then return end
    message = string.sub(tostring(message), 1, 240)
    local filtered = "[сообщение скрыто]"
    local ok, result = pcall(function()
        local filterResult = TextService:FilterStringAsync(message, player.UserId, Enum.TextFilterContext.PublicChat)
        return filterResult:GetNonChatStringForBroadcastAsync()
    end)
    if ok and result then
        filtered = result
    end
    bubbleEvent:FireAllClients(head, filtered)
end

local function getNearbyContext()
    local nearby = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
        local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        if playerRoot and playerHumanoid and playerHumanoid.Health > 0 then
            local distance = (playerRoot.Position - root.Position).Magnitude
            if distance <= 60 then
                table.insert(nearby, {
                    name = player.Name,
                    distance = math.floor(distance),
                })
            end
        end
    end
    return nearby
end

local function moveToPosition(position: Vector3, version: number)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
    })

    local success = pcall(function()
        path:ComputeAsync(root.Position, position)
    end)
    if not success or path.Status ~= Enum.PathStatus.Success then
        humanoid:MoveTo(position)
        humanoid.MoveToFinished:Wait()
        return
    end

    for _, waypoint in ipairs(path:GetWaypoints()) do
        if version ~= behaviorVersion or humanoid.Health <= 0 then
            return
        end
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        humanoid:MoveTo(waypoint.Position)
        local reached = humanoid.MoveToFinished:Wait()
        if not reached then
            break
        end
    end
end

local function setBehavior(action: string, player: Player?)
    behaviorVersion += 1
    local version = behaviorVersion
    currentTarget = player

    if action == "stop" then
        currentState = "idle"
        humanoid:MoveTo(root.Position)
    elseif action == "follow" or action == "come" then
        currentState = action
        if player and player.Character then
            local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local offset = action == "follow" and Vector3.new(3, 0, 3) or Vector3.new(0, 0, 3)
                moveToPosition(targetRoot.Position + offset, version)
            end
        end
    elseif action == "look_at" then
        currentState = "idle"
        if player and player.Character then
            local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local lookPosition = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
                root.CFrame = CFrame.lookAt(root.Position, lookPosition)
            end
        end
    elseif action == "jump" then
        currentState = "idle"
        humanoid.Jump = true
    elseif action == "wander" then
        currentState = "wander"
        currentTarget = nil
    else
        currentState = "idle"
    end
end

local function askGemma(player: Player, message: string)
    if busy or not player or not player.Parent then return end
    local now = os.clock()
    if now - (lastChat[player.UserId] or 0) < CONFIG.THINK_COOLDOWN then
        return
    end
    lastChat[player.UserId] = now
    busy = true

    local token = getToken()
    if not token or CONFIG.BRIDGE_URL:find("YOUR%-QUICK%-TUNNEL") then
        speakToPlayer(player, "Сначала настрой адрес HTTPS-моста и токен.")
        busy = false
        return
    end

    local payload = {
        player = player.Name,
        message = string.sub(message, 1, CONFIG.MAX_MESSAGE_LENGTH),
        nearby = getNearbyContext(),
        npc_state = currentState,
    }

    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url = CONFIG.BRIDGE_URL .. "/chat",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["x-api-key"] = token,
            },
            Body = HttpService:JSONEncode(payload),
        })
    end)

    if not ok or not response.Success then
        speakToPlayer(player, "Не получается связаться с моей моделью. Проверь мост Ollama.")
        busy = false
        return
    end

    local decodedOk, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)
    if not decodedOk or type(data) ~= "table" then
        speakToPlayer(player, "Я получил непонятный ответ от модели.")
        busy = false
        return
    end

    speakToPlayer(player, tostring(data.reply or "Хорошо."))
    local allowed = {
        idle = true, follow = true, come = true, stop = true,
        wander = true, look_at = true, jump = true,
    }
    local action = tostring(data.action or "idle")
    if not allowed[action] then action = "idle" end
    task.spawn(setBehavior, action, player)
    busy = false
end

prompt.Triggered:Connect(function(player)
    askGemma(player, "Привет! Поздоровайся и предложи поговорить.")
end)

local function onPlayerChatted(player: Player, message: string)
    if string.sub(string.lower(message), 1, #CONFIG.CHAT_PREFIX) == CONFIG.CHAT_PREFIX then
        askGemma(player, string.sub(message, #CONFIG.CHAT_PREFIX + 1))
    end
end

local connections = {}
local function connectPlayer(player: Player)
    connections[player] = player.Chatted:Connect(function(message)
        onPlayerChatted(player, message)
    end)
end
Players.PlayerAdded:Connect(connectPlayer)
Players.PlayerRemoving:Connect(function(player)
    if connections[player] then
        connections[player]:Disconnect()
        connections[player] = nil
    end
    lastChat[player.UserId] = nil
    if currentTarget == player then
        setBehavior("wander", nil)
    end
end)
for _, player in ipairs(Players:GetPlayers()) do
    connectPlayer(player)
end

task.spawn(function()
    while humanoid.Health > 0 do
        task.wait(1)
        if currentState == "wander" and not busy then
            local offset = Vector3.new(
                math.random(-CONFIG.WANDER_RADIUS, CONFIG.WANDER_RADIUS),
                0,
                math.random(-CONFIG.WANDER_RADIUS, CONFIG.WANDER_RADIUS)
            )
            local destination = spawnPosition + offset
            local version = behaviorVersion
            moveToPosition(destination, version)
            task.wait(math.random(2, 5))
        elseif currentState == "follow" and currentTarget and currentTarget.Character then
            local targetRoot = currentTarget.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot and (targetRoot.Position - root.Position).Magnitude > 7 then
                local version = behaviorVersion
                moveToPosition(targetRoot.Position + Vector3.new(3, 0, 3), version)
            end
        end
    end
end)

print("[OllamaNPC] Ready. Chat with: !ai привет")
