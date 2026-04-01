local HttpService = game:GetService("HttpService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Fetcher = {}
Fetcher.__index = Fetcher

Fetcher.Configuration = {
	BaseUrl = "https://fetcher-production-2a8b.up.railway.app",
	ApiSecret = "PASTE_YOUR_API_SECRET_HERE",
	Include = {
		details = true,
		votes = true,
		favorites = true,
		icons = true,
	},
	ClientSupport = {
		Enabled = true,
		AutoInjectBootstrap = true,
		ReplicatedFolderName = "Fetcher",
		RequestFunctionName = "FetcherRequest",
		ClientBootstrapName = "FetcherClient",
	},
}

local function cloneDeep(value)
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for key, nestedValue in pairs(value) do
		result[key] = cloneDeep(nestedValue)
	end

	return result
end

local function decodeJson(jsonBody)
	local success, decodedValue = pcall(function()
		return HttpService:JSONDecode(jsonBody)
	end)

	if not success then
		return nil, "Failed to decode JSON response."
	end

	return decodedValue
end

local function getReplicatedFolder(configuration)
	local folderName = configuration.ClientSupport.ReplicatedFolderName
	local existingFolder = ReplicatedStorage:FindFirstChild(folderName)

	if existingFolder and existingFolder:IsA("Folder") then
		return existingFolder
	end

	local createdFolder = Instance.new("Folder")
	createdFolder.Name = folderName
	createdFolder.Parent = ReplicatedStorage
	return createdFolder
end

local function getPlayerScriptsContainer(player)
	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	if playerScripts then
		return playerScripts
	end

	return player:WaitForChild("PlayerScripts", 10)
end

function Fetcher.new(configurationOverride)
	local configuration = cloneDeep(Fetcher.Configuration)

	if type(configurationOverride) == "table" then
		for key, value in pairs(configurationOverride) do
			if type(value) == "table" and type(configuration[key]) == "table" then
				for nestedKey, nestedValue in pairs(value) do
					configuration[key][nestedKey] = cloneDeep(nestedValue)
				end
			else
				configuration[key] = cloneDeep(value)
			end
		end
	end

	local self = setmetatable({}, Fetcher)
	self.Configuration = configuration
	return self
end

function Fetcher:GetAuthorizationHeaders()
	return {
		["Content-Type"] = "application/json",
		["Authorization"] = "Bearer " .. self.Configuration.ApiSecret,
	}
end

function Fetcher:DecodeResponseBody(responseBody)
	return decodeJson(responseBody)
end

function Fetcher:GetHealth()
	local success, responseBody = pcall(function()
		return HttpService:GetAsync(self.Configuration.BaseUrl .. "/health")
	end)

	if not success then
		return nil, "Could not reach the Fetcher API health endpoint."
	end

	return self:DecodeResponseBody(responseBody)
end

function Fetcher:ResolveCurrentExperienceOwnerUserId()
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local success, groupInformation = pcall(function()
			return GroupService:GetGroupInfoAsync(game.CreatorId)
		end)

		if not success then
			return nil, "Failed to get group information."
		end

		if groupInformation and groupInformation.Owner and groupInformation.Owner.Id then
			return groupInformation.Owner.Id
		end

		return nil, "Group owner could not be resolved."
	end

	return nil, "Unsupported creator type."
end

function Fetcher:PostJson(endpointPath, payload)
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = self.Configuration.BaseUrl .. endpointPath,
			Method = "POST",
			Headers = self:GetAuthorizationHeaders(),
			Body = HttpService:JSONEncode(payload),
		})
	end)

	if not success then
		return nil, "HTTP request crashed before the API responded."
	end

	if not response.Success then
		return nil, string.format(
			"Request failed with status %s: %s",
			tostring(response.StatusCode),
			tostring(response.Body)
		)
	end

	return self:DecodeResponseBody(response.Body)
end

function Fetcher:GetOwnerGamesByUserId(ownerUserId, includeOverride)
	if type(ownerUserId) ~= "number" then
		return nil, "ownerUserId must be a number."
	end

	return self:PostJson("/owner-games", {
		ownerUserId = ownerUserId,
		include = includeOverride or self.Configuration.Include,
	})
end

function Fetcher:GetCurrentOwnerGames(includeOverride)
	local ownerUserId, ownerResolutionError = self:ResolveCurrentExperienceOwnerUserId()
	if not ownerUserId then
		return nil, ownerResolutionError
	end

	return self:GetOwnerGamesByUserId(ownerUserId, includeOverride)
end

function Fetcher:BuildGamesByUniverseId(ownerGamesResponse)
	local gamesByUniverseId = {}

	for _, gameRecord in ipairs(ownerGamesResponse.games or {}) do
		gamesByUniverseId[gameRecord.universeId] = gameRecord
	end

	return gamesByUniverseId
end

function Fetcher:GetClientRemoteFunction()
	local replicatedFolder = getReplicatedFolder(self.Configuration)
	local remoteFunctionName = self.Configuration.ClientSupport.RequestFunctionName
	local existingRemote = replicatedFolder:FindFirstChild(remoteFunctionName)

	if existingRemote and existingRemote:IsA("RemoteFunction") then
		return existingRemote
	end

	local createdRemote = Instance.new("RemoteFunction")
	createdRemote.Name = remoteFunctionName
	createdRemote.Parent = replicatedFolder
	return createdRemote
end

function Fetcher:HandleClientRequest(requestPayload)
	local actionName = requestPayload and requestPayload.Action
	local payload = requestPayload and requestPayload.Payload or {}

	if actionName == "GetCurrentOwnerGames" then
		return self:GetCurrentOwnerGames(payload.Include)
	end

	if actionName == "GetOwnerGamesByUserId" then
		return self:GetOwnerGamesByUserId(payload.OwnerUserId, payload.Include)
	end

	return nil, "Unsupported Fetcher client action."
end

function Fetcher:EnableClientSupport()
	if not RunService:IsServer() then
		return false, "EnableClientSupport can only run on the server."
	end

	if self.Configuration.ClientSupport.Enabled ~= true then
		return false, "Client support is disabled in Fetcher.Configuration."
	end

	local remoteFunction = self:GetClientRemoteFunction()
	remoteFunction.OnServerInvoke = function(_, requestPayload)
		return self:HandleClientRequest(requestPayload)
	end

	return true
end

function Fetcher:InjectClientBootstrap(clientBootstrapTemplate)
	if not RunService:IsServer() then
		return false, "InjectClientBootstrap can only run on the server."
	end

	if self.Configuration.ClientSupport.Enabled ~= true then
		return false, "Client support is disabled in Fetcher.Configuration."
	end

	if self.Configuration.ClientSupport.AutoInjectBootstrap ~= true then
		return false, "Automatic client bootstrap injection is disabled."
	end

	if not clientBootstrapTemplate or not clientBootstrapTemplate:IsA("LocalScript") then
		return false, "A LocalScript bootstrap template is required for client injection."
	end

	clientBootstrapTemplate.Name = self.Configuration.ClientSupport.ClientBootstrapName

	local starterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
	local existingStarterBootstrap = starterPlayerScripts:FindFirstChild(clientBootstrapTemplate.Name)
	if existingStarterBootstrap then
		existingStarterBootstrap:Destroy()
	end

	local starterClone = clientBootstrapTemplate:Clone()
	starterClone.Parent = starterPlayerScripts

	for _, player in ipairs(Players:GetPlayers()) do
		local playerScripts = getPlayerScriptsContainer(player)
		if playerScripts then
			local existingPlayerBootstrap = playerScripts:FindFirstChild(clientBootstrapTemplate.Name)
			if existingPlayerBootstrap then
				existingPlayerBootstrap:Destroy()
			end

			local playerClone = clientBootstrapTemplate:Clone()
			playerClone.Parent = playerScripts
		end
	end

	Players.PlayerAdded:Connect(function(player)
		local playerScripts = getPlayerScriptsContainer(player)
		if playerScripts then
			local playerClone = clientBootstrapTemplate:Clone()
			playerClone.Name = clientBootstrapTemplate.Name
			playerClone.Parent = playerScripts
		end
	end)

	return true
end

function Fetcher:GetClientCallable()
	if RunService:IsServer() then
		return nil, "GetClientCallable is intended for LocalScripts."
	end

	local configuration = self.Configuration
	local replicatedFolder = ReplicatedStorage:WaitForChild(configuration.ClientSupport.ReplicatedFolderName)
	local remoteFunction = replicatedFolder:WaitForChild(configuration.ClientSupport.RequestFunctionName)

	local clientCallable = {}

	function clientCallable:GetCurrentOwnerGames(includeOverride)
		return remoteFunction:InvokeServer({
			Action = "GetCurrentOwnerGames",
			Payload = {
				Include = includeOverride,
			},
		})
	end

	function clientCallable:GetOwnerGamesByUserId(ownerUserId, includeOverride)
		return remoteFunction:InvokeServer({
			Action = "GetOwnerGamesByUserId",
			Payload = {
				OwnerUserId = ownerUserId,
				Include = includeOverride,
			},
		})
	end

	return clientCallable
end

return Fetcher
