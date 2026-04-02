local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local HttpService = game:GetService("HttpService")

local Fetcher = {}
Fetcher.__index = Fetcher

local GlobalRequestQueue = {}
local IsProcessingGlobalRequestQueue = false
local ActiveRateWindowStartedAt = 0
local ActiveRateWindowCount = 0

local DEFAULT_CONFIGURATION = {
	BaseUrl = "https://fetcher-production-2a8b.up.railway.app",
	ApiSecret = "d94801c5-5f97-4b68-9cbf-1933858f724e",
	Include = {
		details = true,
		votes = true,
		favorites = true,
		icons = true,
	},
	Names = {
		SharedModuleName = "Fetcher",
		ReplicatedFolderName = "FetcherRemotes",
		RequestFunctionName = "FetcherRequest",
		ClientBootstrapName = "Fetcher",
		GamesFolderName = "Games",
	},
	ClientSupport = true,
	AutoInjectBootstrap = true,
	RequestQueue = {
		Enabled = true,
		MaxRequestsPerSecond = 10,
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

local function mergeDeep(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" and type(target[key]) == "table" then
			mergeDeep(target[key], value)
		else
			target[key] = cloneDeep(value)
		end
	end
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

local function encodeJson(value)
	local success, encodedValue = pcall(function()
		return HttpService:JSONEncode(value)
	end)

	if not success then
		return "{}"
	end

	return encodedValue
end

local function findChildByNameAndClass(parent, objectName, className)
	if not parent then
		return nil
	end

	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == objectName and child.ClassName == className then
			return child
		end
	end

	return nil
end

local function findDescendantByNameAndClass(root, objectName, className)
	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == objectName and descendant.ClassName == className then
			return descendant
		end
	end

	return nil
end

local function getPlayerScriptsContainer(player)
	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	if playerScripts then
		return playerScripts
	end

	return player:WaitForChild("PlayerScripts", 10)
end

local function getQueueLength()
	return #GlobalRequestQueue
end

local function processGlobalRequestQueue()
	if IsProcessingGlobalRequestQueue then
		return
	end

	IsProcessingGlobalRequestQueue = true

	while getQueueLength() > 0 do
		local nextRequest = GlobalRequestQueue[1]
		local queueConfiguration = nextRequest.QueueConfiguration or {}
		local maxRequestsPerSecond = math.max(1, queueConfiguration.MaxRequestsPerSecond or 10)
		local now = os.clock()

		if ActiveRateWindowStartedAt == 0 or now - ActiveRateWindowStartedAt >= 1 then
			ActiveRateWindowStartedAt = now
			ActiveRateWindowCount = 0
		end

		if ActiveRateWindowCount >= maxRequestsPerSecond then
			local remainingWindowTime = 1 - (now - ActiveRateWindowStartedAt)
			if remainingWindowTime > 0 then
				task.wait(remainingWindowTime)
			else
				task.wait()
			end
		else
			table.remove(GlobalRequestQueue, 1)
			ActiveRateWindowCount += 1

			local success, firstResult, secondResult = pcall(nextRequest.Executor)
			nextRequest.Signal:Fire(success, firstResult, secondResult)
			nextRequest.Signal:Destroy()
		end
	end

	IsProcessingGlobalRequestQueue = false
end

function Fetcher.new(configurationOverride)
	local configuration = cloneDeep(DEFAULT_CONFIGURATION)

	if type(configurationOverride) == "table" then
		mergeDeep(configuration, configurationOverride)
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

function Fetcher:GetHealth()
	local success, responseBody = pcall(function()
		return HttpService:GetAsync(self.Configuration.BaseUrl .. "/health")
	end)

	if not success then
		return nil, "Could not reach the Fetcher API health endpoint."
	end

	return decodeJson(responseBody)
end

function Fetcher:RunQueuedRequest(executor)
	local queueConfiguration = self.Configuration.RequestQueue or {}

	if queueConfiguration.Enabled == false then
		return executor()
	end

	local signal = Instance.new("BindableEvent")
	table.insert(GlobalRequestQueue, {
		Executor = executor,
		Signal = signal,
		QueueConfiguration = queueConfiguration,
	})

	task.spawn(processGlobalRequestQueue)

	local success, firstResult, secondResult = signal.Event:Wait()
	if not success then
		error(firstResult)
	end

	return firstResult, secondResult
end

function Fetcher:ResolveCurrentExperienceOwner()
	if game.CreatorType == Enum.CreatorType.User then
		return "User", game.CreatorId
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local success, groupInformation = pcall(function()
			return GroupService:GetGroupInfoAsync(game.CreatorId)
		end)

		if not success then
			return nil, "Failed to get group information."
		end

		if groupInformation and groupInformation.Id then
			return "Group", groupInformation.Id
		end

		return nil, "Group/community could not be resolved."
	end

	return nil, "Unsupported creator type."
end

function Fetcher:PostJson(endpointPath, payload)
	local success, response = pcall(function()
		return self:RunQueuedRequest(function()
			return HttpService:RequestAsync({
				Url = self.Configuration.BaseUrl .. endpointPath,
				Method = "POST",
				Headers = self:GetAuthorizationHeaders(),
				Body = HttpService:JSONEncode(payload),
			})
		end)
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

	return decodeJson(response.Body)
end

function Fetcher:GetOwnerGamesByUserId(ownerUserId, includeOverride)
	if type(ownerUserId) ~= "number" then
		return nil, "ownerUserId must be a number."
	end

	return self:PostJson("/owner-games", {
		ownerType = "User",
		ownerId = ownerUserId,
		ownerUserId = ownerUserId,
		include = includeOverride or self.Configuration.Include,
	})
end

function Fetcher:GetOwnerGamesByGroupId(ownerGroupId, includeOverride)
	if type(ownerGroupId) ~= "number" then
		return nil, "ownerGroupId must be a number."
	end

	return self:PostJson("/owner-games", {
		ownerType = "Group",
		ownerId = ownerGroupId,
		ownerGroupId = ownerGroupId,
		include = includeOverride or self.Configuration.Include,
	})
end

function Fetcher:GetCurrentOwnerGames(includeOverride)
	local ownerType, ownerIdOrError = self:ResolveCurrentExperienceOwner()
	if not ownerType then
		return nil, ownerIdOrError
	end

	if ownerType == "Group" then
		return self:GetOwnerGamesByGroupId(ownerIdOrError, includeOverride)
	end

	if ownerType == "User" then
		return self:GetOwnerGamesByUserId(ownerIdOrError, includeOverride)
	end

	return nil, "Unsupported owner type."
end

function Fetcher:GetCurrentOwnerIdentity()
	local ownerType, ownerIdOrError = self:ResolveCurrentExperienceOwner()
	if not ownerType then
		return nil, ownerIdOrError
	end

	return {
		ownerType = ownerType,
		ownerId = ownerIdOrError,
	}
end

function Fetcher:BuildGamesByUniverseId(ownerGamesResponse)
	local gamesByUniverseId = {}

	for _, gameRecord in ipairs(ownerGamesResponse.games or {}) do
		gamesByUniverseId[gameRecord.universeId] = gameRecord
	end

	return gamesByUniverseId
end

function Fetcher:PrintOwnerGamesResponse(logPrefix, ownerGamesResponse)
	local prefix = logPrefix or "[Fetcher]"

	if type(ownerGamesResponse) ~= "table" then
		warn(prefix .. " Invalid owner games response.")
		return false
	end

	print(prefix, "Owner Type:", ownerGamesResponse.ownerType or "Unknown")
	print(prefix, "Owner ID:", ownerGamesResponse.ownerId or ownerGamesResponse.ownerUserId or ownerGamesResponse.ownerGroupId or 0)
	print(prefix, "Total Games:", ownerGamesResponse.totalGames)
	print(prefix, "Requested At:", ownerGamesResponse.requestedAt)

	local games = ownerGamesResponse.games or {}
	if #games == 0 then
		print(prefix, "No public games were returned.")
		return true
	end

	for _, gameRecord in ipairs(games) do
		print(prefix, "------------------------------")
		print(prefix, "Name:", gameRecord.name)
		print(prefix, "Universe ID:", gameRecord.universeId)
		print(prefix, "Place ID:", gameRecord.placeId)
		print(prefix, "Root Place ID:", gameRecord.rootPlaceId)
		print(prefix, "Owner Username:", gameRecord.ownerUsername or gameRecord.ownerName or "Unknown")
		print(prefix, "Owner Display Name:", gameRecord.ownerDisplayName or gameRecord.ownerName or "Unknown")
		print(prefix, "Likes:", gameRecord.likes)
		print(prefix, "Favorites:", gameRecord.favoritedCount)
		print(prefix, "Visits:", gameRecord.visits)
		print(prefix, "Playing:", gameRecord.playing)
		print(prefix, "Created:", gameRecord.created)
		print(prefix, "Updated:", gameRecord.updated)
	end

	return true
end

function Fetcher:CreateValueObject(className, name, value, parent)
	local valueObject = Instance.new(className)
	valueObject.Name = name
	valueObject.Value = value
	valueObject.Parent = parent
	return valueObject
end

function Fetcher:ClearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		child:Destroy()
	end
end

function Fetcher:BuildOwnerGamesFolder(parent, ownerGamesResponse, folderName, clearExisting)
	if not parent then
		return nil, "Parent is required."
	end

	if type(ownerGamesResponse) ~= "table" then
		return nil, "ownerGamesResponse must be a table."
	end

	local containerName = folderName or "Fetcher"
	local container = findChildByNameAndClass(parent, containerName, "Folder")

	if not container then
		container = Instance.new("Folder")
		container.Name = containerName
		container.Parent = parent
	end

	if clearExisting ~= false then
		self:ClearChildren(container)
	end

	for _, gameRecord in ipairs(ownerGamesResponse.games or {}) do
		local gameFolder = Instance.new("Folder")
		gameFolder.Name = tostring(gameRecord.name or ("Game_" .. tostring(gameRecord.universeId or "Unknown")))
		gameFolder.Parent = container

		self:CreateValueObject("IntValue", "GameId", tonumber(gameRecord.universeId) or 0, gameFolder)
		self:CreateValueObject("IntValue", "UniverseId", tonumber(gameRecord.universeId) or 0, gameFolder)
		self:CreateValueObject("IntValue", "PlaceId", tonumber(gameRecord.placeId or gameRecord.rootPlaceId) or 0, gameFolder)
		self:CreateValueObject("IntValue", "RootPlaceId", tonumber(gameRecord.rootPlaceId) or 0, gameFolder)
		self:CreateValueObject("IntValue", "PlayerVisits", tonumber(gameRecord.visits) or 0, gameFolder)
		self:CreateValueObject("IntValue", "Likes", tonumber(gameRecord.likes) or 0, gameFolder)
		self:CreateValueObject("IntValue", "Favorites", tonumber(gameRecord.favoritedCount) or 0, gameFolder)
		self:CreateValueObject("IntValue", "Playing", tonumber(gameRecord.playing) or 0, gameFolder)
		self:CreateValueObject("IntValue", "OwnerId", tonumber(gameRecord.ownerId) or 0, gameFolder)

		self:CreateValueObject("StringValue", "Description", tostring(gameRecord.description or ""), gameFolder)
		self:CreateValueObject("StringValue", "Created", tostring(gameRecord.created or ""), gameFolder)
		self:CreateValueObject("StringValue", "Updated", tostring(gameRecord.updated or ""), gameFolder)
		self:CreateValueObject("StringValue", "IconImageUrl", tostring(gameRecord.iconImageUrl or ""), gameFolder)
		self:CreateValueObject("StringValue", "Image", tostring(gameRecord.imageUrl or gameRecord.iconImageUrl or ""), gameFolder)
		self:CreateValueObject("StringValue", "ImageUrl", tostring(gameRecord.imageUrl or gameRecord.iconImageUrl or ""), gameFolder)
		self:CreateValueObject("StringValue", "ThumbnailImageUrl", tostring(gameRecord.thumbnailImageUrl or gameRecord.iconImageUrl or ""), gameFolder)
		self:CreateValueObject("StringValue", "ThumbnailUrl", tostring(gameRecord.thumbnailUrl or gameRecord.thumbnailImageUrl or gameRecord.iconImageUrl or ""), gameFolder)
		self:CreateValueObject("StringValue", "Owner", tostring(gameRecord.ownerDisplayName or gameRecord.ownerUsername or gameRecord.ownerName or ""), gameFolder)
		self:CreateValueObject("StringValue", "OwnerName", tostring(gameRecord.ownerName or gameRecord.ownerDisplayName or ""), gameFolder)
		self:CreateValueObject("StringValue", "OwnerUsername", tostring(gameRecord.ownerUsername or gameRecord.ownerName or ""), gameFolder)
		self:CreateValueObject("StringValue", "OwnerDisplayName", tostring(gameRecord.ownerDisplayName or gameRecord.ownerName or ""), gameFolder)
		self:CreateValueObject("StringValue", "OwnerType", tostring(gameRecord.ownerType or ""), gameFolder)
		self:CreateValueObject("StringValue", "OwnerImage", tostring(gameRecord.ownerImage or ""), gameFolder)
		self:CreateValueObject("StringValue", "OwnerJson", encodeJson(gameRecord.owner or {}), gameFolder)
		self:CreateValueObject("StringValue", "ThumbnailsJson", encodeJson(gameRecord.thumbnails or {}), gameFolder)
		self:CreateValueObject("StringValue", "Genre", tostring(gameRecord.genre or ""), gameFolder)
	end

	return container
end

function Fetcher:GetRemotesFolder()
	local folderName = self.Configuration.Names.ReplicatedFolderName
	local existingFolder = findChildByNameAndClass(ReplicatedStorage, folderName, "Folder")

	if existingFolder then
		return existingFolder
	end

	local createdFolder = Instance.new("Folder")
	createdFolder.Name = folderName
	createdFolder:SetAttribute("FetcherRemoteFolder", true)
	createdFolder:SetAttribute("FetcherRequestFunctionName", self.Configuration.Names.RequestFunctionName)
	createdFolder.Parent = ReplicatedStorage
	return createdFolder
end

function Fetcher:FindRemotesFolder()
	local configuredFolder = findChildByNameAndClass(ReplicatedStorage, self.Configuration.Names.ReplicatedFolderName, "Folder")
	if configuredFolder then
		return configuredFolder
	end

	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if child:IsA("Folder") and child:GetAttribute("FetcherRemoteFolder") == true then
			return child
		end
	end

	return findDescendantByNameAndClass(ReplicatedStorage, self.Configuration.Names.ReplicatedFolderName, "Folder")
end

function Fetcher:GetClientRemoteFunction()
	local remotesFolder = self:GetRemotesFolder()
	local remoteName = self.Configuration.Names.RequestFunctionName
	local existingRemote = findChildByNameAndClass(remotesFolder, remoteName, "RemoteFunction")

	if existingRemote then
		return existingRemote
	end

	local createdRemote = Instance.new("RemoteFunction")
	createdRemote.Name = remoteName
	createdRemote.Parent = remotesFolder
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

	if actionName == "GetOwnerGamesByGroupId" then
		return self:GetOwnerGamesByGroupId(payload.OwnerGroupId, payload.Include)
	end

	if actionName == "BuildGamesFolder" then
		local response, responseError = self:GetCurrentOwnerGames(payload.Include)
		if not response then
			return nil, responseError
		end

		local folder, folderError = self:BuildOwnerGamesFolder(
			ReplicatedStorage,
			response,
			self.Configuration.Names.GamesFolderName or "Games",
			true
		)

		if not folder then
			return nil, folderError
		end

		return {
			Success = true,
			FolderName = folder.Name,
			TotalGames = response.totalGames,
		}
	end

	return nil, "Unsupported Fetcher client action."
end

function Fetcher:EnableClientSupport()
	if not RunService:IsServer() then
		return false, "EnableClientSupport can only run on the server."
	end

	if self.Configuration.ClientSupport ~= true then
		return false, "Client support is disabled."
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

	if self.Configuration.ClientSupport ~= true then
		return false, "Client support is disabled."
	end

	if self.Configuration.AutoInjectBootstrap ~= true then
		return false, "Automatic client bootstrap injection is disabled."
	end

	if not clientBootstrapTemplate or not clientBootstrapTemplate:IsA("LocalScript") then
		return false, "A LocalScript bootstrap template is required."
	end

	local bootstrapName = self.Configuration.Names.ClientBootstrapName
	clientBootstrapTemplate.Name = bootstrapName

	local starterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
	local existingStarterBootstrap = findChildByNameAndClass(starterPlayerScripts, bootstrapName, "LocalScript")
	if not existingStarterBootstrap then
		local starterClone = clientBootstrapTemplate:Clone()
		starterClone.Name = bootstrapName
		starterClone.Parent = starterPlayerScripts
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local playerScripts = getPlayerScriptsContainer(player)
		if playerScripts then
			local existingPlayerBootstrap = findChildByNameAndClass(playerScripts, bootstrapName, "LocalScript")
			if not existingPlayerBootstrap then
				local playerClone = clientBootstrapTemplate:Clone()
				playerClone.Name = bootstrapName
				playerClone.Parent = playerScripts
			end
		end
	end

	return true
end

function Fetcher:CleanupInjectedClientBootstrap()
	if not RunService:IsServer() then
		return false, "CleanupInjectedClientBootstrap can only run on the server."
	end

	local bootstrapName = self.Configuration.Names.ClientBootstrapName
	local removedAny = false

	local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if starterPlayerScripts then
		local starterBootstrap = findChildByNameAndClass(starterPlayerScripts, bootstrapName, "LocalScript")
		if starterBootstrap then
			starterBootstrap:Destroy()
			removedAny = true
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local playerScripts = getPlayerScriptsContainer(player)
		if playerScripts then
			local playerBootstrap = findChildByNameAndClass(playerScripts, bootstrapName, "LocalScript")
			if playerBootstrap then
				playerBootstrap:Destroy()
				removedAny = true
			end
		end
	end

	return true, removedAny
end

function Fetcher:CleanupClientSupportRemotes()
	if not RunService:IsServer() then
		return false, "CleanupClientSupportRemotes can only run on the server."
	end

	local remotesFolder = self:FindRemotesFolder()
	if not remotesFolder then
		return true, false
	end

	remotesFolder:Destroy()
	return true, true
end

function Fetcher:GetClientCallable()
	if RunService:IsServer() then
		return nil, "GetClientCallable is intended for LocalScripts."
	end

	local remotesFolder = self:FindRemotesFolder()
	if not remotesFolder then
		return nil, "Could not find the Fetcher remotes folder."
	end

	local requestFunctionName = remotesFolder:GetAttribute("FetcherRequestFunctionName")
		or self.Configuration.Names.RequestFunctionName
	local requestRemote = remotesFolder:WaitForChild(requestFunctionName)

	local clientCallable = {}

	function clientCallable:GetCurrentOwnerGames(includeOverride)
		return requestRemote:InvokeServer({
			Action = "GetCurrentOwnerGames",
			Payload = {
				Include = includeOverride,
			},
		})
	end

	function clientCallable:GetOwnerGamesByUserId(ownerUserId, includeOverride)
		return requestRemote:InvokeServer({
			Action = "GetOwnerGamesByUserId",
			Payload = {
				OwnerUserId = ownerUserId,
				Include = includeOverride,
			},
		})
	end

	function clientCallable:GetOwnerGamesByGroupId(ownerGroupId, includeOverride)
		return requestRemote:InvokeServer({
			Action = "GetOwnerGamesByGroupId",
			Payload = {
				OwnerGroupId = ownerGroupId,
				Include = includeOverride,
			},
		})
	end

	function clientCallable:BuildGamesFolder(includeOverride)
		return requestRemote:InvokeServer({
			Action = "BuildGamesFolder",
			Payload = {
				Include = includeOverride,
			},
		})
	end

	return clientCallable
end

return Fetcher
