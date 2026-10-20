--!strict
-- Server entry point. Loads every module in Services, calls Init on all of them,
-- then Start on all of them. Init must not yield or call other services; Start may.

local Services = script:WaitForChild("Services")

type Service = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

local loaded: { [string]: Service } = {}

for _, moduleScript in Services:GetChildren() do
	if moduleScript:IsA("ModuleScript") then
		loaded[moduleScript.Name] = (require :: any)(moduleScript)
	end
end

for _, service in loaded do
	if service.Init then
		service:Init()
	end
end

for name, service in loaded do
	if service.Start then
		task.spawn(function()
			debug.setmemorycategory(name)
			service:Start()
		end)
	end
end

print(`[Farborn] Server started with {#Services:GetChildren()} services`)
