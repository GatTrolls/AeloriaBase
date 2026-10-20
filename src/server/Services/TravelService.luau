--!strict
--[[
	TravelService

	Pads that move a player to another spot in the same place: from the test arena to a level
	blockout and back, and later between districts until each region is its own place.

	  * A pad is any BasePart tagged "TravelPad" with a "Destination" attribute.
	  * A destination is any BasePart tagged "TravelPoint" with a matching "PointId" attribute.
	  * An optional "Label" attribute on a pad is shown above it.

	Pads and points can live in the place file or be built by code, so level designers can add
	them in Studio without touching scripts. A pad whose destination isn't in the place does
	nothing.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local TravelService = {}

local COOLDOWN_SECONDS = 2

local lastTravel: { [Player]: number } = {}

local function findPoint(pointId: string): BasePart?
	for _, point in CollectionService:GetTagged("TravelPoint") do
		if point:IsA("BasePart") and point:GetAttribute("PointId") == pointId then
			return point
		end
	end
	return nil
end

local function label(pad: BasePart)
	local text = pad:GetAttribute("Label")
	if type(text) ~= "string" or pad:FindFirstChild("TravelLabel") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "TravelLabel"
	gui.Size = UDim2.fromOffset(200, 36)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.MaxDistance = 120
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.fromRGB(255, 245, 220)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.Text = text
	textLabel.Parent = gui
	gui.Parent = pad
end

local function connectPad(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end
	label(pad)
	pad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not player or not root then
			return
		end
		local now = os.clock()
		if now - (lastTravel[player] or 0) < COOLDOWN_SECONDS then
			return
		end
		local destination = pad:GetAttribute("Destination")
		local point = type(destination) == "string" and findPoint(destination) or nil
		if not point then
			return
		end
		lastTravel[player] = now
		local target = point.CFrame + Vector3.new(0, point.Size.Y / 2 + 3, 0)
		character:PivotTo(target)
		root.AssemblyLinearVelocity = Vector3.zero
	end)
end

function TravelService:Start()
	CollectionService:GetInstanceAddedSignal("TravelPad"):Connect(connectPad)
	for _, pad in CollectionService:GetTagged("TravelPad") do
		connectPad(pad)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)
end

return TravelService
