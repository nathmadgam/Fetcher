local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local fetcherModule = ReplicatedStorage:WaitForChild("Fetcher")
local Fetcher = require(fetcherModule)
local fetcher = Fetcher.new()

print("[FetcherClient] Bootstrap started.")

local clientFetcher, clientFetcherError = fetcher:GetClientCallable()
if not clientFetcher then
	warn("[FetcherClient] " .. tostring(clientFetcherError))
	script:Destroy()
	return
end

local buildResult, buildError = clientFetcher:BuildGamesFolder()
if not buildResult then
	warn("[FetcherClient] " .. tostring(buildError))
	script:Destroy()
	return
end

print("[FetcherClient] Games folder built:", buildResult.FolderName)
print("[FetcherClient] Total Games:", buildResult.TotalGames)

script:Destroy()
