local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = script.Parent
local bootstrapModule =
	(ReplicatedStorage:FindFirstChild("Fetcher") and ReplicatedStorage.Fetcher:IsA("ModuleScript") and ReplicatedStorage.Fetcher)
	or (packageRoot:FindFirstChild("Fetcher") and packageRoot.Fetcher:IsA("ModuleScript") and packageRoot.Fetcher)

if not bootstrapModule then
	warn("[FetcherServer] Could not find a bootstrap ModuleScript named 'Fetcher'.")
	return
end

local BootstrapFetcher = require(bootstrapModule)
local bootstrapFetcher = BootstrapFetcher.new()
local sharedFetcherModule = bootstrapFetcher:FindSharedModule(packageRoot)

if not sharedFetcherModule then
	warn("[FetcherServer] Could not find the configured shared Fetcher module.")
	return
end

local Fetcher = require(sharedFetcherModule)
local fetcher = Fetcher.new()

print("[FetcherServer] Bootstrap started.")

local clientRemote = fetcher:GetClientRemoteFunction()
if clientRemote then
	print("[FetcherServer] Client remote ready:", clientRemote:GetFullName())
end

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

local clientBootstrapTemplate = fetcher:FindClientBootstrapTemplate(script)
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
