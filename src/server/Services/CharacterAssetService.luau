--!strict
--[[
	CharacterAssetService

	Loads each hero's character model and shares it with every client. Models are uploaded
	assets (a skinned mesh with its bones); only the server can load an asset by id, so this
	service loads them once at start, applies the texture and puts them in
	ReplicatedStorage.CharacterRigs, where clients clone them for every player wearing that
	hero. Which heroes have a model, and the asset ids, come from the private content
	(Content.visual); a hero without an entry is drawn with the default body.
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)

local CharacterAssetService = {}

local FOLDER_NAME = "CharacterRigs"

local function load(heroId: string, visual: { [string]: any }, folder: Folder)
	local ok, result = pcall(function()
		return InsertService:LoadAsset(visual.assetId)
	end)
	if not ok then
		warn(`[CharacterAssets] {heroId}: could not load asset {visual.assetId}: {result}`)
		return
	end
	local model = (result :: Instance):FindFirstChildOfClass("Model")
	if not model then
		warn(`[CharacterAssets] {heroId}: the asset has no model`)
		result:Destroy()
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("MeshPart") then
			-- SurfaceAppearance maps cannot be set by scripts, so a hero with a full material set
			-- (colour, normal, roughness, metalness) is stored in the place under CharacterRigs
			-- already dressed, and this loader only handles the single-texture ones.
			if visual.texture then
				descendant.TextureID = visual.texture
			end
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	model.Name = heroId
	model.Parent = folder
	result:Destroy()
end

function CharacterAssetService:Start()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
	if not folder then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
	for _, heroId in Content.visualIds() do
		local visual = Content.visual(heroId)
		if visual and visual.assetId and not (folder :: Folder):FindFirstChild(heroId) then
			task.spawn(load, heroId, visual, folder :: Folder)
		end
	end
end

return CharacterAssetService
