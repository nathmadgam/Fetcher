local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = script.Parent
local bootstrapModule =
	(ReplicatedStorage:FindFirstChild("Fetcher") and ReplicatedStorage.Fetcher:IsA("ModuleScript") and ReplicatedStorage.Fetcher)
	or (packageRoot:FindFirstChild("Fetcher") and packageRoot.Fetcher:IsA("ModuleScript") and packageRoot.Fetcher)

if not bootstrapModule then
	warn("[FetcherClient] Could not find a bootstrap ModuleScript named 'Fetcher'.")
	return
end

local BootstrapFetcher = require(bootstrapModule)
local bootstrapFetcher = BootstrapFetcher.new()
local sharedFetcherModule = bootstrapFetcher:FindSharedModule(packageRoot)

if not sharedFetcherModule then
	warn("[FetcherClient] Could not find the configured shared Fetcher module.")
	return
end

local Fetcher = require(sharedFetcherModule)
local fetcher = Fetcher.new()

print("[FetcherClient] Bootstrap started.")

local clientFetcher, clientFetcherError = fetcher:GetClientCallable()
if not clientFetcher then
	warn("[FetcherClient] " .. tostring(clientFetcherError))
	return
end

local ownerGamesResponse, requestError = clientFetcher:GetCurrentOwnerGames()
if not ownerGamesResponse then
	warn("[FetcherClient] " .. tostring(requestError))
	return
end

print("[FetcherClient] Owner User ID:", ownerGamesResponse.ownerUserId)
print("[FetcherClient] Total Games:", ownerGamesResponse.totalGames)

for _, gameRecord in ipairs(ownerGamesResponse.games or {}) do
	print("[FetcherClient] Name:", gameRecord.name)
	print("[FetcherClient] Likes:", gameRecord.likes)
	print("[FetcherClient] Favorites:", gameRecord.favoritedCount)
	print("[FetcherClient] Visits:", gameRecord.visits)
end
