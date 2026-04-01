local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fetcher = require(ReplicatedStorage:WaitForChild("Fetcher"))
local fetcher = Fetcher.new()

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
