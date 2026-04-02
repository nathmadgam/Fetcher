local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED_MODULE_NAME = "Fetcher"

local fetcherModule = ReplicatedStorage:WaitForChild(SHARED_MODULE_NAME)
local Fetcher = require(fetcherModule)
local fetcher = Fetcher.new()

local clientFetcher, clientError = fetcher:GetClientCallable()
if not clientFetcher then
	warn("[fetcher/client] " .. tostring(clientError))
	script:Destroy()
	return
end

local buildResult, buildError = clientFetcher:BuildGamesFolder()
if not buildResult then
	warn("[fetcher/client] " .. tostring(buildError))
	script:Destroy()
	return
end

print("[fetcher/client] Folder:", buildResult.FolderName, "games =", buildResult.TotalGames)
script:Destroy()
