-- A simple scene for Roblox Studio.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local part = Instance.new("Part")
part.Name = "Orion"
part.Anchored = true
part.Size = Vector3.new(4, 4, 4)
part.Position = Vector3.new(0, 8, 0)
part.Color = Color3.fromRGB(136, 181, 255)
part.Parent = workspace

local function update(deltaTime: number)
    part.CFrame *= CFrame.Angles(0, deltaTime * 0.5, 0)
end

RunService.Heartbeat:Connect(update)
print("Scene ready", player and player.Name)
