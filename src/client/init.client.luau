--!strict
-- Client entry point. Same Init/Start pattern as the server, for modules in Controllers.

local Controllers = script:WaitForChild("Controllers")

type Controller = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

local loaded: { [string]: Controller } = {}

for _, moduleScript in Controllers:GetChildren() do
	if moduleScript:IsA("ModuleScript") then
		loaded[moduleScript.Name] = (require :: any)(moduleScript)
	end
end

for _, controller in loaded do
	if controller.Init then
		controller:Init()
	end
end

for _, controller in loaded do
	if controller.Start then
		task.spawn(controller.Start, controller)
	end
end
