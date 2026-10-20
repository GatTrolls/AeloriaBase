--!strict
--[[
	NotebookController

	Registers the Notebook screen and its pages with the UI. Pages are modules in UI/Pages; any
	module there that returns a table with `id`, `icon` and `build` becomes a tab the Notebook can
	open, so adding a page never means touching this file.
]]

local Notebook = require(script.Parent.Parent.UI.Screens.Notebook)
local UIController = require(script.Parent.UIController)

local NotebookController = {}

function NotebookController:Init()
	local pages = script.Parent.Parent.UI.Pages
	for _, module in pages:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, def = pcall(require, module)
			if ok and type(def) == "table" and def.id and def.build then
				Notebook.registerPage(def)
			else
				warn(`[Notebook] page {module.Name} failed to load: {def}`)
			end
		end
	end
	UIController.register("notebook", Notebook.build)
end

return NotebookController
