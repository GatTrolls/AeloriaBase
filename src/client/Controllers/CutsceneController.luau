--!strict
--[[
	CutsceneController

	Plays conversations and short scenes: black letterbox bars slide in, the combat HUD and the
	Notebook button step aside, and the dialogue box shows the lines. Anything tagged "Npc" in the
	world with a ProximityPrompt and an `NpcId` attribute starts a conversation when used; the
	lines come from the strings `dialogue.<npcId>.1`, `.2`, ... with the speaker in
	`dialogue.<npcId>.name`. When a conversation ends the server hears a "talk" event for the
	quest tracker.

	  Cutscene.play(lines, onDone?)   lines are DialogueBox lines
	  Cutscene.talk(npcId)            plays an NPC's conversation from the strings
	  Cutscene.isPlaying()
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Content)
local Net = require(ReplicatedStorage.Shared.Net)

local DialogueBox = require(script.Parent.Parent.UI.Screens.DialogueBox)
local Kit = require(script.Parent.Parent.UI.Kit)
local UIController = require(script.Parent.UIController)

local player = Players.LocalPlayer

local CutsceneController = {}

local BAR_HEIGHT = 0.11
local MAX_LINES = 24

local layer: Frame
local topBar: Frame
local bottomBar: Frame
local box: any
local playing = false

local function setHud(visible: boolean)
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("FarbornHud")
	if hud and hud:IsA("ScreenGui") then
		hud.Enabled = visible
	end
	local button = UIController.notebookButton
	if button then
		button.Visible = visible
	end
end

local function bars(shown: boolean)
	local height = if shown then BAR_HEIGHT else 0
	Kit.tween(topBar, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, height) })
	Kit.tween(bottomBar, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, height) })
end

function CutsceneController.isPlaying(): boolean
	return playing
end

function CutsceneController.play(lines: { any }, onDone: (() -> ())?)
	if playing or UIController.isOpen() or #lines == 0 then
		return
	end
	playing = true
	setHud(false)
	bars(true)
	box.play(lines, function()
		playing = false
		bars(false)
		setHud(true)
		if onDone then
			onDone()
		end
	end)
end

-- The conversation for an NPC, read from the strings until a line is missing.
function CutsceneController.talk(npcId: string)
	local speaker = Content.text(`dialogue.{npcId}.name`)
	local lines = {}
	for index = 1, MAX_LINES do
		local key = `dialogue.{npcId}.{index}`
		local text = Content.text(key)
		if text == key then
			break
		end
		table.insert(lines, {
			speaker = if speaker ~= `dialogue.{npcId}.name` then speaker else nil,
			text = text,
		})
	end
	CutsceneController.play(lines, function()
		Net.event(Net.Names.QuestEvent):FireServer("talk", npcId)
	end)
end

local function watch(instance: Instance)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			local npcId = instance:GetAttribute("NpcId")
			if type(npcId) == "string" then
				descendant.Triggered:Connect(function(who)
					if who == player then
						CutsceneController.talk(npcId)
					end
				end)
			end
		end
	end
end

function CutsceneController:Start()
	layer = Kit.frame({
		parent = UIController.layer("modals").Parent,
		size = UDim2.fromScale(1, 1),
		name = "Letterbox",
		z = 60,
	})
	topBar =
		Kit.frame({ parent = layer, size = UDim2.fromScale(1, 0), color = Color3.new(0, 0, 0), name = "Top" })
	bottomBar = Kit.frame({
		parent = layer,
		size = UDim2.fromScale(1, 0),
		position = UDim2.fromScale(0, 1),
		anchor = Vector2.new(0, 1),
		color = Color3.new(0, 0, 0),
		name = "Bottom",
	})
	box = DialogueBox.build(UIController.layer("modals"))

	CollectionService:GetInstanceAddedSignal("Npc"):Connect(watch)
	for _, instance in CollectionService:GetTagged("Npc") do
		watch(instance)
	end
end

return CutsceneController
