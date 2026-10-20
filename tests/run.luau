--!strict
-- Runs every *.spec.luau file in this folder. Usage: lune run tests/run
local fs = require("@lune/fs")
local process = require("@lune/process")

local passed, failed = 0, 0

for _, fileName in fs.readDir("tests") do
	local specName = string.match(fileName, "^(.+)%.spec%.luau$")
	if specName then
		local spec = (require :: any)(`./{specName}.spec`)
		for testName, test in spec do
			local ok, problem = pcall(test)
			if ok then
				passed += 1
				print(`  PASS  {specName} > {testName}`)
			else
				failed += 1
				print(`  FAIL  {specName} > {testName}\n        {problem}`)
			end
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed > 0 then 1 else 0)
