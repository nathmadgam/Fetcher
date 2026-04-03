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
	BaseUrl = "",
	ApiSecret = "",
	Include = {
		details = true,
		votes = true,
		favorites = true,
		icons = true,
	},
	ProfileInclude = {
		basics = true,
		counts = true,
		images = true,
		presence = true,
		groups = true,
		badges = true,
		usernameHistory = true,
		friendsPreview = true,
		followersPreview = true,
		followingsPreview = true,
		ownedGames = true,
		bloxlink = true,
	},
	Names = {
		SharedModuleName = "Fetcher",
		ReplicatedFolderName = "FetcherRemotes",
		RequestFunctionName = "FetcherRequest",
		ClientBootstrapName = "FetcherClient",
		GamesFolderName = "Games",
		ProfilesFolderName = "Profiles",
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

local function trimString(value)
	if type(value) ~= "string" then
		return ""
	end

	return value:match("^%s*(.-)%s*$")
end

local function hasConfiguredValue(value)
	local normalizedValue = trimString(value)
	if normalizedValue == "" then
		return false
	end

	local lowercaseValue = string.lower(normalizedValue)
	return lowercaseValue ~= "your_api_secret_here"
		and lowercaseValue ~= "paste_your_api_secret_here"
		and lowercaseValue ~= "https://your-service.up.railway.app"
		and lowercaseValue ~= "https://your-domain.example.com"
end

local function normalizeBaseUrl(value)
	local normalizedValue = trimString(value)
	return normalizedValue:gsub("/+$", "")
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

function Fetcher:IsNetworkConfigurationReady()
	return hasConfiguredValue(self.Configuration.BaseUrl)
		and hasConfiguredValue(self.Configuration.ApiSecret)
end

function Fetcher:GetConfigurationError()
	if not hasConfiguredValue(self.Configuration.BaseUrl) then
		return "Fetcher BaseUrl is not configured. Set your deployed API base URL on the server."
	end

	if not hasConfiguredValue(self.Configuration.ApiSecret) then
		return "Fetcher ApiSecret is not configured. Set your API secret on the server only."
	end

	return nil
end

function Fetcher:GetAuthorizationHeaders()
	return {
		["Content-Type"] = "application/json",
		["Authorization"] = "Bearer " .. trimString(self.Configuration.ApiSecret),
	}
end

function Fetcher:GetHealth()
	local configurationError = self:GetConfigurationError()
	if configurationError then
		return nil, configurationError
	end

	local success, responseBody = pcall(function()
		return HttpService:GetAsync(normalizeBaseUrl(self.Configuration.BaseUrl) .. "/health")
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
	local configurationError = self:GetConfigurationError()
	if configurationError then
		return nil, configurationError
	end

	local success, response = pcall(function()
		return self:RunQueuedRequest(function()
			return HttpService:RequestAsync({
				Url = normalizeBaseUrl(self.Configuration.BaseUrl) .. endpointPath,
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

function Fetcher:GetProfileByUserId(userId, includeOverride)
	if type(userId) ~= "number" then
		return nil, "userId must be a number."
	end

	return self:PostJson("/profile", {
		userId = userId,
		include = includeOverride or self.Configuration.ProfileInclude,
	})
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

function Fetcher:PrintProfileResponse(logPrefix, profileResponse)
	local prefix = logPrefix or "[Fetcher]"

	if type(profileResponse) ~= "table" then
		warn(prefix .. " Invalid profile response.")
		return false
	end

	local basics = profileResponse.basics or {}
	local counts = profileResponse.counts or {}
	local presence = profileResponse.presence or {}

	print(prefix, "User ID:", profileResponse.userId or basics.userId or 0)
	print(prefix, "Username:", basics.username or basics.name or "Unknown")
	print(prefix, "Display Name:", basics.displayName or basics.username or "Unknown")
	print(prefix, "Created:", basics.created or "Unknown")
	print(prefix, "Followers:", counts.followers or 0)
	print(prefix, "Following:", counts.followings or 0)
	print(prefix, "Friends:", counts.friends or 0)
	print(prefix, "Presence:", presence.lastLocation or "Unknown")

	if profileResponse.ownedGames and profileResponse.ownedGames.totalGames ~= nil then
		print(prefix, "Owned Games:", profileResponse.ownedGames.totalGames)
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

function Fetcher:BuildProfileFolder(parent, profileResponse, folderName, clearExisting)
	if not parent then
		return nil, "Parent is required."
	end

	if type(profileResponse) ~= "table" then
		return nil, "profileResponse must be a table."
	end

	local containerName = folderName or "Profile"
	local container = findChildByNameAndClass(parent, containerName, "Folder")

	if not container then
		container = Instance.new("Folder")
		container.Name = containerName
		container.Parent = parent
	end

	if clearExisting ~= false then
		self:ClearChildren(container)
	end

	local basics = profileResponse.basics or {}
	local counts = profileResponse.counts or {}
	local images = profileResponse.images or {}
	local presence = profileResponse.presence or {}
	local bloxlink = profileResponse.bloxlink or {}

	self:CreateValueObject("IntValue", "UserId", tonumber(profileResponse.userId or basics.userId) or 0, container)
	self:CreateValueObject("StringValue", "Username", tostring(basics.username or basics.name or ""), container)
	self:CreateValueObject("StringValue", "DisplayName", tostring(basics.displayName or basics.username or ""), container)
	self:CreateValueObject("StringValue", "Description", tostring(basics.description or ""), container)
	self:CreateValueObject("StringValue", "Created", tostring(basics.created or ""), container)
	self:CreateValueObject("BoolValue", "HasVerifiedBadge", basics.hasVerifiedBadge == true, container)
	self:CreateValueObject("BoolValue", "IsBanned", basics.isBanned == true, container)
	self:CreateValueObject("StringValue", "ProfileUrl", tostring(profileResponse.profileUrl or basics.profileUrl or ""), container)
	self:CreateValueObject("IntValue", "FriendsCount", tonumber(counts.friends) or 0, container)
	self:CreateValueObject("IntValue", "FollowersCount", tonumber(counts.followers) or 0, container)
	self:CreateValueObject("IntValue", "FollowingsCount", tonumber(counts.followings) or 0, container)
	self:CreateValueObject("StringValue", "HeadshotImageUrl", tostring(images.headshot and images.headshot.imageUrl or ""), container)
	self:CreateValueObject("StringValue", "HeadshotWebUrl", tostring(images.headshot and images.headshot.webUrl or ""), container)
	self:CreateValueObject("StringValue", "AvatarImageUrl", tostring(images.avatar and images.avatar.imageUrl or ""), container)
	self:CreateValueObject("StringValue", "AvatarWebUrl", tostring(images.avatar and images.avatar.webUrl or ""), container)
	self:CreateValueObject("StringValue", "PresenceJson", encodeJson(presence), container)
	self:CreateValueObject("StringValue", "BloxlinkJson", encodeJson(bloxlink), container)
	self:CreateValueObject("StringValue", "ProfileJson", encodeJson(profileResponse), container)

	local groupsFolder = Instance.new("Folder")
	groupsFolder.Name = "Groups"
	groupsFolder.Parent = container

	for index, groupRecord in ipairs(((profileResponse.groups or {}).items or {})) do
		local groupFolder = Instance.new("Folder")
		groupFolder.Name = tostring(groupRecord.name or ("Group_" .. tostring(index)))
		groupFolder.Parent = groupsFolder

		self:CreateValueObject("IntValue", "GroupId", tonumber(groupRecord.id) or 0, groupFolder)
		self:CreateValueObject("StringValue", "Name", tostring(groupRecord.name or ""), groupFolder)
		self:CreateValueObject("IntValue", "MemberCount", tonumber(groupRecord.memberCount) or 0, groupFolder)
		self:CreateValueObject("StringValue", "RoleName", tostring(groupRecord.roleName or ""), groupFolder)
		self:CreateValueObject("IntValue", "RoleRank", tonumber(groupRecord.roleRank) or 0, groupFolder)
	end

	local historyFolder = Instance.new("Folder")
	historyFolder.Name = "UsernameHistory"
	historyFolder.Parent = container

	for index, username in ipairs(((profileResponse.usernameHistory or {}).items or {})) do
		self:CreateValueObject("StringValue", tostring(index), tostring(username), historyFolder)
	end

	local function buildPreviewFolder(previewName, previewData)
		local previewFolder = Instance.new("Folder")
		previewFolder.Name = previewName
		previewFolder.Parent = container

		for index, entry in ipairs((previewData and previewData.items) or {}) do
			local entryFolder = Instance.new("Folder")
			entryFolder.Name = tostring(entry.username or entry.name or ("User_" .. tostring(index)))
			entryFolder.Parent = previewFolder

			self:CreateValueObject("IntValue", "UserId", tonumber(entry.userId or entry.id) or 0, entryFolder)
			self:CreateValueObject("StringValue", "Username", tostring(entry.username or entry.name or ""), entryFolder)
			self:CreateValueObject("StringValue", "DisplayName", tostring(entry.displayName or entry.username or ""), entryFolder)
			self:CreateValueObject("StringValue", "ImageUrl", tostring(entry.imageUrl or ""), entryFolder)
			self:CreateValueObject("StringValue", "ImageWebUrl", tostring(entry.imageWebUrl or ""), entryFolder)
		end
	end

	local social = profileResponse.social or {}
	buildPreviewFolder("FriendsPreview", social.friendsPreview)
	buildPreviewFolder("FollowersPreview", social.followersPreview)
	buildPreviewFolder("FollowingsPreview", social.followingsPreview)

	if profileResponse.ownedGames then
		self:BuildOwnerGamesFolder(
			container,
			profileResponse.ownedGames,
			self.Configuration.Names.GamesFolderName or "Games",
			true
		)
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

	if actionName == "GetProfileByUserId" then
		return self:GetProfileByUserId(payload.UserId, payload.Include)
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

	if actionName == "BuildProfileFolder" then
		local response, responseError = self:GetProfileByUserId(payload.UserId, payload.Include)
		if not response then
			return nil, responseError
		end

		local folder, folderError = self:BuildProfileFolder(
			ReplicatedStorage,
			response,
			payload.FolderName or self.Configuration.Names.ProfilesFolderName or "Profiles",
			true
		)

		if not folder then
			return nil, folderError
		end

		return {
			Success = true,
			FolderName = folder.Name,
			UserId = response.userId,
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

	function clientCallable:GetProfileByUserId(userId, includeOverride)
		return requestRemote:InvokeServer({
			Action = "GetProfileByUserId",
			Payload = {
				UserId = userId,
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

	function clientCallable:BuildProfileFolder(userId, includeOverride, folderName)
		return requestRemote:InvokeServer({
			Action = "BuildProfileFolder",
			Payload = {
				UserId = userId,
				Include = includeOverride,
				FolderName = folderName,
			},
		})
	end

	return clientCallable
end

return Fetcher
