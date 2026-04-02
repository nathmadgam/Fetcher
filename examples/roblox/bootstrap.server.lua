local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MODULE_FOLDER_NAME = "Module"
local CLIENT_FOLDER_NAME = "Client"
local CONFIGURATION_FOLDER_NAME = "Configuration"
local MODULE_SOURCE_NAME = "FetcherModule"
local CLIENT_SOURCE_NAME = "FetcherClient"

local function getChildOfClass(parent, childName, className)
	local child = parent and parent:FindFirstChild(childName)
	if child and child.ClassName == className then
		return child
	end

	return nil
end

local function getNestedValue(root, folderName, valueName)
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

local function readString(root, folderName, valueName, defaultValue)
	local valueObject = getNestedValue(root, folderName, valueName)
	if valueObject and valueObject:IsA("StringValue") then
		return valueObject.Value
	end

	return defaultValue
end

local function readBoolean(root, folderName, valueName, defaultValue)
	local valueObject = getNestedValue(root, folderName, valueName)
	if valueObject and valueObject:IsA("BoolValue") then
		return valueObject.Value
	end

	return defaultValue
end

local function readNumber(root, folderName, valueName, defaultValue)
	local valueObject = getNestedValue(root, folderName, valueName)
	if valueObject and (valueObject:IsA("IntValue") or valueObject:IsA("NumberValue")) then
		return valueObject.Value
	end

	return defaultValue
end

local function buildConfiguration(configurationFolder)
	return {
		BaseUrl = readString(configurationFolder, "Network", "BaseUrl", ""),
		ApiSecret = readString(configurationFolder, "Network", "ApiSecret", ""),
		Include = {
			details = readBoolean(configurationFolder, "Include", "Details", true),
			votes = readBoolean(configurationFolder, "Include", "Votes", true),
			favorites = readBoolean(configurationFolder, "Include", "Favorites", true),
			icons = readBoolean(configurationFolder, "Include", "Icons", true),
		},
		Names = {
			SharedModuleName = readString(configurationFolder, "Names", "SharedModuleName", "Fetcher"),
			ReplicatedFolderName = readString(configurationFolder, "Names", "ReplicatedFolderName", "FetcherRemotes"),
			RequestFunctionName = readString(configurationFolder, "Names", "RequestFunctionName", "FetcherRequest"),
			ClientBootstrapName = readString(configurationFolder, "Names", "ClientBootstrapName", "FetcherClient"),
			GamesFolderName = readString(configurationFolder, "Names", "GamesFolderName", "Games"),
		},
		ClientSupport = readBoolean(configurationFolder, "Client", "ClientSupport", true),
		AutoInjectBootstrap = readBoolean(configurationFolder, "Client", "AutoInjectBootstrap", true),
		RequestQueue = {
			Enabled = readBoolean(configurationFolder, "RequestQueue", "Enabled", true),
			MaxRequestsPerSecond = readNumber(configurationFolder, "RequestQueue", "MaxRequestsPerSecond", 10),
		},
	}
end

local packageRoot = script
local moduleFolder = packageRoot:FindFirstChild(MODULE_FOLDER_NAME)
local clientFolder = packageRoot:FindFirstChild(CLIENT_FOLDER_NAME)
local configurationFolder = packageRoot:FindFirstChild(CONFIGURATION_FOLDER_NAME)

if not moduleFolder or not moduleFolder:IsA("Folder") then
	warn("[fetcher/bootstrap] Missing Module folder.")
	return
end

local sourceModule = getChildOfClass(moduleFolder, MODULE_SOURCE_NAME, "ModuleScript")
if not sourceModule then
	warn("[fetcher/bootstrap] Missing FetcherModule ModuleScript.")
	return
end

local configuration = buildConfiguration(configurationFolder)
local replicatedModuleName = configuration.Names.SharedModuleName

local replicatedModule = ReplicatedStorage:FindFirstChild(replicatedModuleName)
if not replicatedModule or not replicatedModule:IsA("ModuleScript") then
	replicatedModule = sourceModule:Clone()
	replicatedModule.Name = replicatedModuleName
	replicatedModule.Parent = ReplicatedStorage
end

local Fetcher = require(replicatedModule)
local fetcher = Fetcher.new(configuration)

if not fetcher:IsNetworkConfigurationReady() then
	warn("[fetcher/bootstrap] " .. tostring(fetcher:GetConfigurationError()))
	return
end

local healthData, healthError = fetcher:GetHealth()
if not healthData then
	warn("[fetcher/bootstrap] " .. tostring(healthError))
	return
end

if healthData.secretConfigured ~= true then
	warn("[fetcher/bootstrap] API secret is missing on the deployed API service.")
	return
end

if configuration.ClientSupport == true then
	local enabled, enableError = fetcher:EnableClientSupport()
	if not enabled then
		warn("[fetcher/bootstrap] " .. tostring(enableError))
		return
	end

	if configuration.AutoInjectBootstrap == true then
		local clientTemplate = clientFolder and getChildOfClass(clientFolder, CLIENT_SOURCE_NAME, "LocalScript")
		if not clientTemplate then
			warn("[fetcher/bootstrap] Auto-injection is enabled but FetcherClient is missing.")
		else
			local injected, injectionError = fetcher:InjectClientBootstrap(clientTemplate)
			if not injected then
				warn("[fetcher/bootstrap] " .. tostring(injectionError))
				return
			end
		end
	end
end

local ownerGamesResponse, requestError = fetcher:GetCurrentOwnerGames()
if not ownerGamesResponse then
	warn("[fetcher/bootstrap] " .. tostring(requestError))
	return
end

local gamesFolder, folderError = fetcher:BuildOwnerGamesFolder(
	ReplicatedStorage,
	ownerGamesResponse,
	configuration.Names.GamesFolderName,
	true
)

if not gamesFolder then
	warn("[fetcher/bootstrap] " .. tostring(folderError))
	return
end

print("[fetcher/bootstrap] Ready:", gamesFolder:GetFullName(), "games =", ownerGamesResponse.totalGames)
