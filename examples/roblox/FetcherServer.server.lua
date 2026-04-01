local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fetcher = require(ReplicatedStorage:WaitForChild("Fetcher"))
local fetcher = Fetcher.new()

local healthData, healthError = fetcher:GetHealth()
if not healthData then
	warn("[FetcherServer] " .. tostring(healthError))
	return
end

if healthData.secretConfigured ~= true then
	warn("[FetcherServer] Fetcher API is online, but API_SECRET is not configured on the server.")
	return
end

local clientSupportEnabled, clientSupportError = fetcher:EnableClientSupport()
if not clientSupportEnabled and clientSupportError then
	warn("[FetcherServer] " .. tostring(clientSupportError))
end

local clientBootstrapTemplate = script:FindFirstChild("FetcherClient")
if clientBootstrapTemplate then
	local injected, injectionError = fetcher:InjectClientBootstrap(clientBootstrapTemplate)
	if not injected and injectionError then
		warn("[FetcherServer] " .. tostring(injectionError))
	end
end

local ownerGamesResponse, requestError = fetcher:GetCurrentOwnerGames()
if not ownerGamesResponse then
	warn("[FetcherServer] " .. tostring(requestError))
	return
end

print("[FetcherServer] Owner User ID:", ownerGamesResponse.ownerUserId)
print("[FetcherServer] Total Games:", ownerGamesResponse.totalGames)

local gamesByUniverseId = fetcher:BuildGamesByUniverseId(ownerGamesResponse)
for universeId, gameRecord in pairs(gamesByUniverseId) do
	print("[FetcherServer] Universe ID:", universeId)
	print("[FetcherServer] Name:", gameRecord.name)
	print("[FetcherServer] Likes:", gameRecord.likes)
	print("[FetcherServer] Favorites:", gameRecord.favoritedCount)
	print("[FetcherServer] Visits:", gameRecord.visits)
end
