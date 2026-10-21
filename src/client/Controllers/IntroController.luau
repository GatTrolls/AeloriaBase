--!strict
--[[
	IntroController

	Shows the title screen when the player joins. The profile has to be loaded first so the
	game underneath is ready the moment the screen fades; tapping anywhere starts the game.
]]

local ProfileController = require(script.Parent.ProfileController)
local Title = require(script.Parent.Parent.UI.Screens.Title)
local UIController = require(script.Parent.UIController)

local IntroController = {}

function IntroController:Start()
	UIController.register("title", function(ctx)
		return Title.build({
			ui = ctx.ui,
			onStart = function()
				UIController.close()
			end,
		})
	end)
	task.spawn(function()
		local deadline = os.clock() + 15
		while not ProfileController.get() and os.clock() < deadline do
			task.wait(0.1)
		end
		UIController.open("title")
	end)
end

return IntroController
