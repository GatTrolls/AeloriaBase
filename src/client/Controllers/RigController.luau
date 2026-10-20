--!strict
--[[
	RigController

	Draws every player's character with their active hero's body and animates it. The real
	character stays as the physics body (it moves, collides and is what the server knows); its
	avatar is hidden on this client and replaced by a rig that follows it:

	  * heroes with a model in the private content get their skinned mesh (SkinRig);
	  * every other hero gets a plain R15 body in their colour (R15Rig);
	  * locomotion comes from the speed, floor contact and movement mode of the character;
	  * attacks, abilities, hurt and death play clips by name from Shared.Config.AnimationSets.

	RigController.play(character, "attack", {...}) is what combat feedback calls; Rig/Registry
	lets effects find the rig without depending on this controller.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AnimationSets = require(ReplicatedStorage.Shared.Config.AnimationSets)
local Content = require(ReplicatedStorage.Shared.Content)
local Heroes = require(ReplicatedStorage.Shared.Config.Heroes)
local Idles = require(ReplicatedStorage.Shared.Anim.Idles)
local Pose = require(ReplicatedStorage.Shared.Anim.Pose)

local ClipLibrary = require(script.Parent.Parent.Rig.ClipLibrary)
local MovementController = require(script.Parent.MovementController)
local R15Rig = require(script.Parent.Parent.Rig.R15Rig)
local Registry = require(script.Parent.Parent.Rig.Registry)
local RigAnimator = require(script.Parent.Parent.Rig.RigAnimator)
local RigTypes = require(script.Parent.Parent.Rig.Rig)
local SkinRig = require(script.Parent.Parent.Rig.SkinRig)

local localPlayer = Players.LocalPlayer

type Bound = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	heroId: string?,
	animator: RigAnimator.Animator?,
	building: boolean,
	frozenUntil: number,
	died: boolean,
	connections: { RBXScriptConnection },
}

local RigController = {}

local bound: { [Model]: Bound } = {}
local rigsFolder: Folder? = nil

local function folder(): Folder
	if rigsFolder and rigsFolder.Parent then
		return rigsFolder
	end
	local made = Instance.new("Folder")
	made.Name = "ClientRigs"
	made.Parent = Workspace
	rigsFolder = made
	return made
end

-- Hides the avatar parts on this client; the physics body stays.
local function hide(instance: Instance)
	if instance:IsA("BasePart") or instance:IsA("Decal") or instance:IsA("Texture") then
		(instance :: any).Transparency = 1
	end
end

local function hideAvatar(b: Bound)
	for _, descendant in b.character:GetDescendants() do
		hide(descendant)
	end
	table.insert(b.connections, b.character.DescendantAdded:Connect(hide))
end

local function bodyColors(heroId: string): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	local kit = Heroes[heroId]
	if kit then
		local color = Color3.fromRGB(kit.color[1], kit.color[2], kit.color[3])
		local skin = Color3.fromRGB(240, 205, 175)
		description.HeadColor = skin
		description.LeftArmColor = skin
		description.RightArmColor = skin
		description.TorsoColor = color
		description.LeftLegColor = color:Lerp(Color3.new(0, 0, 0), 0.35)
		description.RightLegColor = color:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	return description
end

-- Builds the rig for a hero: the skinned model if the game has one, else a plain R15 body.
local function buildRig(heroId: string): RigTypes.Rig?
	local visual = Content.visual(heroId)
	if visual then
		local models = ReplicatedStorage:FindFirstChild("CharacterRigs")
			or ReplicatedStorage:WaitForChild("CharacterRigs", 10)
		local template = models and (models:FindFirstChild(heroId) or models:WaitForChild(heroId, 10))
		if template then
			local model = template:Clone() :: Model
			model.Parent = folder()
			local ok, rig = pcall(SkinRig.fromModel, model, { map = visual.map, meshName = visual.meshName })
			if ok then
				return rig
			end
			warn(`[Rigs] {heroId}: {rig}`)
			model:Destroy()
		end
	end
	local ok, rig = pcall(function()
		return R15Rig.fromDescription(bodyColors(heroId))
	end)
	if ok then
		rig.model.Parent = folder()
		return rig
	end
	warn(`[Rigs] {heroId}: could not build a default body: {rig}`)
	return nil
end

local function teardown(b: Bound)
	if b.animator then
		RigAnimator.destroy(b.animator)
		b.animator = nil
	end
	Registry.set(b.character, nil)
end

local function playMove(b: Bound, move: AnimationSets.Move, heavy: boolean?, speedScale: number?)
	local animator = b.animator
	if not animator then
		return
	end
	local clip = ClipLibrary.get(move.clip)
	if not clip then
		return
	end
	local velocity = b.root.AssemblyLinearVelocity
	local running = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 3
	local speed = move.speed * (speedScale or 1)
	local id = RigAnimator.play(animator, clip, {
		startAt = math.max(0, move.strike - move.lead),
		speed = speed,
		mask = if running then Pose.upperBody else nil,
		fadeIn = 0.05,
		fadeOut = if heavy then 0.2 else 0.14,
	})
	-- A combo hit only shows the strike and its follow-through, not the clip's whole recovery.
	task.delay((move.lead + (if heavy then 0.5 else 0.38)) / speed, function()
		if b.animator == animator then
			RigAnimator.stop(animator, id)
		end
	end)
end

local function ensureRig(b: Bound)
	local heroId = b.character:GetAttribute("HeroId")
	if type(heroId) ~= "string" or b.building then
		return
	end
	if b.heroId == heroId and b.animator then
		return
	end
	b.building = true
	task.spawn(function()
		local rig = buildRig(heroId)
		b.building = false
		if not rig or not b.character.Parent then
			if rig then
				rig.destroy(rig)
			end
			return
		end
		teardown(b)
		b.heroId = heroId
		b.animator = RigAnimator.new(rig)
		local kit = Heroes[heroId]
		b.animator.idle = Idles.get(kit and kit.idle)
		Registry.set(b.character, {
			model = rig.model,
			play = function(name, params)
				RigController.play(b.character, name, params)
			end,
			freeze = function(seconds)
				b.frozenUntil = os.clock() + seconds
			end,
		})
		-- If the hero changed while this one was being built, build again.
		if b.character:GetAttribute("HeroId") ~= heroId then
			ensureRig(b)
		end
	end)
end

local function bind(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 15) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 15) :: BasePart?
	if not humanoid or not root or bound[character] then
		return
	end
	local b: Bound = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		heroId = nil,
		animator = nil,
		building = false,
		frozenUntil = 0,
		died = false,
		connections = {},
	}
	bound[character] = b
	hideAvatar(b)
	table.insert(
		b.connections,
		character:GetAttributeChangedSignal("HeroId"):Connect(function()
			ensureRig(b)
		end)
	)
	table.insert(
		b.connections,
		humanoid.Died:Connect(function()
			b.died = true
			RigController.play(character, "death", nil)
		end)
	)
	table.insert(
		b.connections,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(Workspace) then
				teardown(b)
				for _, connection in b.connections do
					connection:Disconnect()
				end
				bound[character] = nil
			end
		end)
	)
	ensureRig(b)
end

local function watch(player: Player)
	if player.Character then
		task.spawn(bind, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(bind, player, character)
	end)
end

-- Plays an action on a character's rig. name: "attack" | "charged" | "plunge" | "technique" |
-- "finale" (params: weapon, index, heavy), "hurt" (params: heavy), "death", "dodge".
function RigController.play(character: Model, name: string, params: { [string]: any }?)
	local b = bound[character]
	if not b or not b.animator then
		return
	end
	local p = params or {}
	if
		name == "attack"
		or name == "charged"
		or name == "plunge"
		or name == "technique"
		or name == "finale"
	then
		local kit = if b.heroId then Heroes[b.heroId] else nil
		local weapon = p.weapon or (kit and kit.weapon) or "sword"
		local set = AnimationSets.forWeapon(weapon)
		local move: AnimationSets.Move
		if name == "attack" then
			local index = math.max(1, p.index or 1)
			move = set.chain[(index - 1) % #set.chain + 1]
		else
			move = (set :: any)[name]
		end
		playMove(b, move, name ~= "attack" or p.heavy == true, p.speedScale)
	elseif name == "hurt" then
		local clip = ClipLibrary.get(
			if p.heavy then AnimationSets.Reactions.hurtLarge else AnimationSets.Reactions.hurt
		)
		if clip then
			RigAnimator.play(
				b.animator,
				clip,
				{ speed = 1.4, fadeIn = 0.04, fadeOut = 0.16, mask = Pose.upperBody }
			)
		end
	elseif name == "death" then
		local clip = ClipLibrary.get(AnimationSets.Reactions.deathBack)
		if clip then
			RigAnimator.play(b.animator, clip, { speed = 1, fadeIn = 0.1, fadeOut = 0.3, hold = 30 })
		end
	elseif name == "dodge" then
		local clip = ClipLibrary.get(AnimationSets.Reactions.dodge)
		if clip then
			RigAnimator.play(b.animator, clip, { speed = 1.6, fadeIn = 0.04, fadeOut = 0.12 })
		end
	end
end

local function locomotionOf(b: Bound): (string, number, number, number, number)
	local velocity = b.root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local airborne = b.humanoid.FloorMaterial == Enum.Material.Air
	local state = "ground"
	local mode: string
	if b.player == localPlayer then
		mode = MovementController.getMode()
	else
		local activity = b.character:GetAttribute("Activity")
		mode = if activity == "climb" or activity == "glide" then activity else "ground"
	end
	if mode == "climb" or mode == "glide" or mode == "plunge" then
		state = mode
	elseif airborne then
		state = "air"
	end
	local bank = math.clamp(b.root.AssemblyAngularVelocity.Y * 0.25, -1, 1)
	local climbing = math.clamp(math.abs(velocity.Y) / 14, 0, 1)
	return state, speed, velocity.Y, bank, climbing
end

local function step(dt: number)
	local now = os.clock()
	for character, b in bound do
		local animator = b.animator
		if animator and character.Parent and b.root.Parent then
			local state, speed, vy, bank, climbing = locomotionOf(b)
			if b.died then
				state, speed = "ground", 0
			end
			RigAnimator.setLocomotion(animator, state, speed, vy, { bank = bank, climbing = climbing })
			local rig = animator.rig
			local rootOffset = rig.hipHeight - (b.humanoid.HipHeight + b.root.Size.Y / 2)
			local frame = b.root.CFrame * CFrame.new(0, rootOffset, 0)
			RigAnimator.update(animator, if now < b.frozenUntil then 0 else dt, frame)
		end
	end
end

function RigController:Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	RunService:BindToRenderStep("FarbornRigs", Enum.RenderPriority.Character.Value + 5, step)
end

return RigController
