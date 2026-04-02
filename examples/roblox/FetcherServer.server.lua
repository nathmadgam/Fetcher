local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local function findConfigValue(root, folderName, valueName)
	if not root then
		return nil
	end

	local directValue = root:FindFirstChild(valueName)
	if directValue then
		return directValue
	end

	local nestedFolder = root:FindFirstChild(folderName)
	if nestedFolder and nestedFolder:IsA("Folder") then
		return nestedFolder:FindFirstChild(valueName)
	end

	return nil
end

local function getStringValue(parent, folderName, name, defaultValue)
	local valueObject = findConfigValue(parent, folderName, name)
	if valueObject and valueObject:IsA("StringValue") then
		return valueObject.Value
	end
	return defaultValue
end

local function getBoolValue(parent, folderName, name, defaultValue)
	local valueObject = findConfigValue(parent, folderName, name)
	if valueObject and valueObject:IsA("BoolValue") then
		return valueObject.Value
	end
	return defaultValue
end

local function getNumberValue(parent, folderName, name, defaultValue)
	local valueObject = findConfigValue(parent, folderName, name)
	if valueObject and (valueObject:IsA("IntValue") or valueObject:IsA("NumberValue")) then
		return valueObject.Value
	end
	return defaultValue
end

local packageRoot = script
local moduleFolder = packageRoot:WaitForChild("Module")
local clientFolder = packageRoot:WaitForChild("Client")
local configurationFolder = packageRoot:WaitForChild("Configuration")

local sourceModule = moduleFolder:WaitForChild("FetcherModule")
local clientBootstrap = clientFolder:WaitForChild("FetcherClient")

local configuration = {
	BaseUrl = getStringValue(configurationFolder, "Network", "BaseUrl", "https://fetcher-production-2a8b.up.railway.app"),
	ApiSecret = getStringValue(configurationFolder, "Network", "ApiSecret", "d94801c5-5f97-4b68-9cbf-1933858f724e"),
	Include = {
		details = getBoolValue(configurationFolder, "Include", "Details", true),
		votes = getBoolValue(configurationFolder, "Include", "Votes", true),
		favorites = getBoolValue(configurationFolder, "Include", "Favorites", true),
		icons = getBoolValue(configurationFolder, "Include", "Icons", true),
	},
	Names = {
		SharedModuleName = getStringValue(configurationFolder, "Names", "SharedModuleName", "Fetcher"),
		ReplicatedFolderName = getStringValue(configurationFolder, "Names", "ReplicatedFolderName", "FetcherRemotes"),
		RequestFunctionName = getStringValue(configurationFolder, "Names", "RequestFunctionName", "FetcherRequest"),
		ClientBootstrapName = getStringValue(configurationFolder, "Names", "ClientBootstrapName", "Fetcher"),
		GamesFolderName = getStringValue(configurationFolder, "Names", "GamesFolderName", "Games"),
	},
	ClientSupport = getBoolValue(configurationFolder, "Client", "ClientSupport", true),
	AutoInjectBootstrap = getBoolValue(configurationFolder, "Client", "AutoInjectBootstrap", true),
	RequestQueue = {
		Enabled = getBoolValue(configurationFolder, "RequestQueue", "Enabled", true),
		MaxRequestsPerSecond = getNumberValue(configurationFolder, "RequestQueue", "MaxRequestsPerSecond", 10),
	},
}

local replicatedModule = ReplicatedStorage:FindFirstChild(configuration.Names.SharedModuleName)
if not replicatedModule or not replicatedModule:IsA("ModuleScript") then
	replicatedModule = sourceModule:Clone()
	replicatedModule.Name = configuration.Names.SharedModuleName
	replicatedModule.Parent = ReplicatedStorage
end

if moduleFolder and moduleFolder.Parent then
	moduleFolder:Destroy()
end

local Fetcher = require(replicatedModule)
local fetcher = Fetcher.new(configuration)

print("[FetcherServer] Bootstrap started.")

local healthData, healthError = fetcher:GetHealth()
if not healthData then
	warn("[FetcherServer] " .. tostring(healthError))
	return
end

if healthData.secretConfigured ~= true then
	warn("[FetcherServer] API secret is not configured on the server.")
	return
end

local remoteFunction = fetcher:GetClientRemoteFunction()
print("[FetcherServer] Client remote ready:", remoteFunction:GetFullName())

if configuration.ClientSupport == true then
	local enabled, enableError = fetcher:EnableClientSupport()
	if not enabled then
		warn("[FetcherServer] " .. tostring(enableError))
		return
	end

	local injected, injectionError = fetcher:InjectClientBootstrap(clientBootstrap)
	if not injected and injectionError then
		warn("[FetcherServer] " .. tostring(injectionError))
	else
		print("[FetcherServer] Client bootstrap ensured.")
	end
end

local ownerGamesResponse, requestError = fetcher:GetCurrentOwnerGames()
if not ownerGamesResponse then
	warn("[FetcherServer] " .. tostring(requestError))
	return
end

fetcher:PrintOwnerGamesResponse("[FetcherServer]", ownerGamesResponse)

local gamesFolder, folderError = fetcher:BuildOwnerGamesFolder(
	ReplicatedStorage,
	ownerGamesResponse,
	configuration.Names.GamesFolderName,
	true
)

if not gamesFolder then
	warn("[FetcherServer] " .. tostring(folderError))
	return
end

print("[FetcherServer] Game values folder ready:", gamesFolder:GetFullName())

if configuration.ClientSupport == true then
	local cleanedUp, cleanupResult = fetcher:CleanupInjectedClientBootstrap()
	if not cleanedUp then
		warn("[FetcherServer] " .. tostring(cleanupResult))
	else
		if cleanupResult == true then
			print("[FetcherServer] Injected client bootstrap cleaned up.")
		end
	end

	local remotesCleanedUp, remotesCleanupResult = fetcher:CleanupClientSupportRemotes()
	if not remotesCleanedUp then
		warn("[FetcherServer] " .. tostring(remotesCleanupResult))
	else
		if remotesCleanupResult == true then
			print("[FetcherServer] Client support remotes cleaned up.")
		end
	end
end

local gamesFolder, folderError = fetcher:BuildOwnerGamesFolder(ReplicatedStorage, ownerGamesResponse, "Games")
if not gamesFolder then
	warn("[FetcherServer] " .. tostring(folderError))
	return
end

print("[FetcherServer] Game values folder ready:", gamesFolder:GetFullName())

if configuration.ClientSupport == true then
	local cleanedUp, cleanupResult = fetcher:CleanupInjectedClientBootstrap()
	if not cleanedUp then
		warn("[FetcherServer] " .. tostring(cleanupResult))
	else
		if cleanupResult == true then
			print("[FetcherServer] Injected client bootstrap cleaned up.")
		else
			print("[FetcherServer] No injected client bootstrap needed cleanup.")
		end
	end
end

local gamesFolder, folderError = fetcher:BuildOwnerGamesFolder(ReplicatedStorage, ownerGamesResponse, "FetcherGames")
if not gamesFolder then
	warn("[FetcherServer] " .. tostring(folderError))
	return
end

print("[FetcherServer] Game values folder ready:", gamesFolder:GetFullName())
