--!strict
--[[
	IntroController

	Shows the title screen when the player joins. The profile has to be loaded first so the
	game underneath is ready the moment the screen fades; tapping anywhere starts the game.
]]

local Loading = require(script.Parent.Parent.UI.Screens.Loading)
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
	local loading = Loading.build(UIController.layer("modals"))
	loading.show()
	task.spawn(function()
		local started = os.clock()
		local deadline = started + 15
		while not ProfileController.get() and os.clock() < deadline do
			loading.setProgress((os.clock() - started) / 15 * 0.9)
			task.wait(0.1)
		end
		loading.setProgress(1)
		task.wait(0.4)
		UIController.open("title")
		loading.hide()
	end)
end

return IntroController
