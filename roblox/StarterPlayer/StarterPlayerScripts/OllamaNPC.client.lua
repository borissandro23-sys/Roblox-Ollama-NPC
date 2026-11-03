-- Place in StarterPlayer > StarterPlayerScripts as a LocalScript.
-- DisplayBubble is a client-side TextChatService feature.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local event = ReplicatedStorage:WaitForChild("OllamaNPCBubble")

event.OnClientEvent:Connect(function(part, message)
    if typeof(part) == "Instance" and part:IsDescendantOf(workspace) then
        pcall(function()
            TextChatService:DisplayBubble(part, tostring(message))
        end)
    end
end)
