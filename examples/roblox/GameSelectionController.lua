local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local screenGui = script.Parent

local Fetcher = require(ReplicatedStorage:WaitForChild("Fetcher"))
local fetcher = Fetcher.new()

local ROOT_REFS = {
	Frame = "Frame",
	Scroll = "Frame/Scroll",
	Template = "Frame/Scroll/Interface",
}

local CARD_REFS = {
	Info = {
		GameLogo = "Container/Pages/Information/Content/Scroll/Info/Icon/GameLogo",
		GameName = "Container/Pages/Information/Content/Scroll/Info/Details/GameName",
		GameId = "Container/Pages/Information/Content/Scroll/Info/Details/GameID",
		OwnerTag = "Container/Pages/Information/Content/Scroll/Info/Details/Owner",
	},
	Stats = {
		Visits = "Container/Pages/Information/Content/Scroll/MoreDetails/Visits/Number",
		Likes = "Container/Pages/Information/Content/Scroll/MoreDetails/Likes/Number",
		OwnerName = "Container/Pages/Information/Content/Scroll/MoreDetails/Owner/OwnerDisplayName",
		OwnerImage = "Container/Pages/Information/Content/Scroll/MoreDetails/Owner/OwnerImage",
	},
	Dates = {
		Updated = "Container/Pages/Information/Content/Scroll/Updated/LatestUpdate/Date",
		Created = "Container/Pages/Information/Content/Scroll/Updated/CreationDate/Date",
	},
	About = {
		Description = "Container/Pages/Information/Content/Scroll/About/Description",
	},
	Media = {
		Thumbnail = "Container/Pages/Information/Utils/GameThumbnails/Thumbnails",
	},
	Actions = {
		Play = "Container/Pages/Information/Content/Actions/Play",
	},
}

local ownerInfoCache = {}
local productInfoCache = {}

local function resolvePath(rootInstance, path)
	local current = rootInstance
	for segment in string.gmatch(path, "[^/]+") do
		current = current and current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	return current
end

local function getRefs(rootInstance, referenceMap)
	local resolved = {}
	for key, value in pairs(referenceMap) do
		if type(value) == "string" then
			resolved[key] = resolvePath(rootInstance, value)
		elseif type(value) == "table" then
			resolved[key] = getRefs(rootInstance, value)
		end
	end
	return resolved
end

local function setText(label, value)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.Text = tostring(value or "Unknown")
	end
end

local function setImage(imageObject, value)
	if imageObject and (imageObject:IsA("ImageLabel") or imageObject:IsA("ImageButton")) then
		imageObject.Image = tostring(value or "")
		imageObject.Visible = imageObject.Image ~= ""
	end
end

local function buildGameIconThumbnail(universeId)
	local numericUniverseId = tonumber(universeId)
	if not numericUniverseId or numericUniverseId <= 0 then
		return ""
	end

	return string.format("rbxthumb://type=GameIcon&id=%d&w=150&h=150", numericUniverseId)
end

local function buildGameThumbnail(rootPlaceId)
	local numericRootPlaceId = tonumber(rootPlaceId)
	if not numericRootPlaceId or numericRootPlaceId <= 0 then
		return ""
	end

	return string.format("rbxthumb://type=GameThumbnail&id=%d&w=768&h=432", numericRootPlaceId)
end

local function buildOwnerThumbnail(ownerType, ownerId)
	local numericOwnerId = tonumber(ownerId)
	if not numericOwnerId or numericOwnerId <= 0 then
		return ""
	end

	if tostring(ownerType) == "Group" then
		return string.format("rbxthumb://type=GroupIcon&id=%d&w=420&h=420", numericOwnerId)
	end

	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420", numericOwnerId)
end

local function normalizeImageSource(value)
	if value == nil then
		return ""
	end

	local image = tostring(value)
	if image == "" or image == "0" or image == "nil" then
		return ""
	end

	local normalizedImage = string.lower(image)
	if string.sub(normalizedImage, 1, 11) == "rbxthumb://" then
		return image
	end

	if string.sub(normalizedImage, 1, 13) == "rbxassetid://" then
		return image
	end

	if string.find(normalizedImage, "://[%w%-%.]+%.rbxcdn%.com", 1) ~= nil then
		return image
	end

	if string.find(normalizedImage, "://[%w%-%.]+%.roblox%.com", 1) ~= nil then
		return image
	end

	local numericId = tonumber(image)
	if numericId and numericId > 0 then
		return string.format("rbxassetid://%d", numericId)
	end

	return ""
end

local function getSquareImageSource(value)
	local image = normalizeImageSource(value)
	if image == "" then
		return ""
	end

	local normalizedImage = string.lower(image)
	if string.find(normalizedImage, "/768/432/", 1, true) ~= nil then
		return ""
	end

	return image
end

local function getListLayout(scroll)
	if not scroll then
		return nil
	end

	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("UIListLayout") then
			return child
		end
	end

	return nil
end

local function formatNumber(value)
	local numberValue = tonumber(value)
	if not numberValue then
		return "0"
	end

	if numberValue >= 1000000000 then
		return string.format("%.1fB", numberValue / 1000000000):gsub("%.0B", "B")
	elseif numberValue >= 1000000 then
		return string.format("%.1fM", numberValue / 1000000):gsub("%.0M", "M")
	elseif numberValue >= 1000 then
		return string.format("%.1fK", numberValue / 1000):gsub("%.0K", "K")
	end

	local formatted = tostring(math.floor(numberValue))
	local reversed = formatted:reverse():gsub("(%d%d%d)", "%1,")
	return reversed:reverse():gsub("^,", "")
end

local function formatDate(value)
	if typeof(value) ~= "string" or value == "" then
		return "Unknown"
	end

	local year, month, day = string.match(value, "^(%d+)%-(%d+)%-(%d+)")
	if not (year and month and day) then
		return value
	end

	local monthNames = {
		"January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December",
	}

	local monthIndex = tonumber(month)
	if not monthIndex or not monthNames[monthIndex] then
		return value
	end

	return string.format("%s %d, %d", monthNames[monthIndex], tonumber(day) or 0, tonumber(year) or 0)
end

local function slugify(value)
	local text = tostring(value or "Game")
	text = text:gsub("[^%w]+", "_")
	text = text:gsub("_+", "_")
	text = text:gsub("^_", "")
	text = text:gsub("_$", "")
	return text ~= "" and text or "Game"
end

local function firstNonEmpty(...)
	for _, value in ipairs({ ... }) do
		if value ~= nil then
			local asString = tostring(value)
			if asString ~= "" and asString ~= "0" and asString ~= "nil" then
				return value
			end
		end
	end
	return nil
end

local function decodeJson(value)
	if typeof(value) ~= "string" or value == "" then
		return nil
	end

	local success, decoded = pcall(function()
		return HttpService:JSONDecode(value)
	end)

	if success and type(decoded) == "table" then
		return decoded
	end

	return nil
end

local function getProductInfo(placeId)
	if productInfoCache[placeId] ~= nil then
		return productInfoCache[placeId]
	end

	local success, result = pcall(function()
		return MarketplaceService:GetProductInfo(placeId)
	end)

	if success and type(result) == "table" then
		productInfoCache[placeId] = result
		return result
	end

	productInfoCache[placeId] = false
	return nil
end

local function getOwnerInfoFromMarketplace(placeId)
	if ownerInfoCache[placeId] ~= nil then
		return ownerInfoCache[placeId]
	end

	local productInfo = getProductInfo(placeId)
	local creator = productInfo and productInfo.Creator or {}
	local creatorId = creator.CreatorTargetId or creator.Id or (productInfo and (productInfo.CreatorTargetId or productInfo.CreatorId))
	local creatorType = creator.CreatorType or (productInfo and productInfo.CreatorType) or "User"
	local creatorName = creator.Name or (productInfo and (productInfo.Owner or productInfo.CreatorName)) or "Unknown"

	local image = ""
	if tonumber(creatorId) then
		image = buildOwnerThumbnail(creatorType, creatorId)
	end

	local payload = {
		Name = creatorName,
		Type = creatorType,
		Id = tonumber(creatorId) or 0,
		Image = image,
	}

	ownerInfoCache[placeId] = payload
	return payload
end

local function getThumbnailEntries(game)
	if type(game.thumbnails) == "table" then
		local thumbnails = game.thumbnails
		if type(thumbnails.list) == "table" and #thumbnails.list > 0 then
			return thumbnails.list
		end

		local entries = {}
		for _, key in ipairs({ "primary", "gameIcon", "icon" }) do
			if type(thumbnails[key]) == "table" then
				table.insert(entries, thumbnails[key])
			end
		end
		if #entries > 0 then
			return entries
		end
	end

	local directUrl = firstNonEmpty(game.thumbnailImageUrl, game.thumbnailUrl, game.imageUrl, game.image, game.iconImageUrl)
	if directUrl then
		return {
			{
				imageUrl = tostring(directUrl),
			},
		}
	end

	return nil
end

local function getOwnerInfo(game)
	local ownerTable = type(game.owner) == "table" and game.owner or nil
	local ownerName = firstNonEmpty(
		game.ownerName,
		ownerTable and ownerTable.name,
		game.ownerDisplayName,
		ownerTable and ownerTable.displayName,
		game.ownerUsername,
		ownerTable and ownerTable.username,
		game.owner
	)
	local ownerType = firstNonEmpty(game.ownerType, ownerTable and ownerTable.type, "Unknown")
	local ownerId = tonumber(firstNonEmpty(game.ownerId, ownerTable and ownerTable.id, ownerTable and ownerTable.userId, 0)) or 0
	local directOwnerImage = firstNonEmpty(game.ownerImage, ownerTable and ownerTable.imageUrl, ownerTable and ownerTable.image, "")
	local ownerImage = getSquareImageSource(directOwnerImage)

	if ownerImage == "" then
		ownerImage = buildOwnerThumbnail(ownerType, ownerId)
	end

	if ownerName and ownerName ~= "Unknown" then
		return {
			Name = tostring(ownerName),
			Type = tostring(ownerType),
			Id = ownerId,
			Image = ownerImage,
		}
	end

	local rootPlaceId = tonumber(game.rootPlaceId) or tonumber(game.placeId) or 0
	if rootPlaceId > 0 then
		return getOwnerInfoFromMarketplace(rootPlaceId)
	end

	return {
		Name = "Unknown",
		Type = tostring(ownerType),
		Id = ownerId,
		Image = ownerImage,
	}
end

local function getGameIcon(game)
	local directIcon = firstNonEmpty(game.iconImageUrl, game.iconUrl)
	local normalizedDirectIcon = getSquareImageSource(directIcon)
	if normalizedDirectIcon ~= "" then
		return normalizedDirectIcon
	end

	local thumbnailEntries = getThumbnailEntries(game)
	if thumbnailEntries and thumbnailEntries[1] then
		local thumbnailUrl = firstNonEmpty(thumbnailEntries[1].iconUrl, thumbnailEntries[1].imageUrl, thumbnailEntries[1].url)
		local normalizedThumbnailUrl = getSquareImageSource(thumbnailUrl)
		if normalizedThumbnailUrl ~= "" then
			return normalizedThumbnailUrl
		end
	end

	local universeId = tonumber(game.universeId) or tonumber(game.gameId)
	if universeId and universeId > 0 then
		return buildGameIconThumbnail(universeId)
	end

	return ""
end

local function getGameThumbnail(game)
	local rootPlaceId = tonumber(game.rootPlaceId) or tonumber(game.placeId)
	if rootPlaceId and rootPlaceId > 0 then
		return buildGameThumbnail(rootPlaceId)
	end

	local thumbnailEntries = getThumbnailEntries(game)
	if thumbnailEntries and thumbnailEntries[1] then
		local thumbnailUrl = firstNonEmpty(thumbnailEntries[1].imageUrl, thumbnailEntries[1].url, thumbnailEntries[1].thumbnailUrl)
		local normalizedThumbnailUrl = normalizeImageSource(thumbnailUrl)
		if normalizedThumbnailUrl ~= "" then
			return normalizedThumbnailUrl
		end
	end

	local directThumbnail = firstNonEmpty(game.thumbnailImageUrl, game.thumbnailUrl, game.imageUrl, game.image)
	local normalizedDirectThumbnail = normalizeImageSource(directThumbnail)
	if normalizedDirectThumbnail ~= "" then
		return normalizedDirectThumbnail
	end

	return getGameIcon(game)
end

local function bindPlayButton(button, placeId)
	if not button or not tonumber(placeId) or tonumber(placeId) <= 0 then
		return
	end

	button.MouseButton1Click:Connect(function()
		local success, err = pcall(function()
			TeleportService:Teleport(tonumber(placeId), player)
		end)
		if not success then
			warn("[GameSelectionController] Teleport failed:", err)
		end
	end)
end

local function buildOwnerTagText(ownerInfo)
	if ownerInfo.Type == "Group" then
		return "Community"
	end

	return ownerInfo.Type ~= "" and ownerInfo.Type or ownerInfo.Name
end

local function buildCard(scroll, template, game, layoutOrder)
	local card = template:Clone()
	card.Name = string.format("Game_%s", slugify(game.name))
	card.Visible = true
	card.LayoutOrder = layoutOrder
	card.Parent = scroll
	applyManualCardLayout(scroll, template, card, layoutOrder)

	local refs = getRefs(card, CARD_REFS)
	local ownerInfo = getOwnerInfo(game)
	local gameName = game.name or "Unknown Game"
	local universeId = tonumber(game.universeId) or tonumber(game.gameId) or 0
	local rootPlaceId = tonumber(game.rootPlaceId) or tonumber(game.placeId) or 0

	setText(refs.Info.GameName, gameName)
	setText(refs.Info.GameId, string.format("Place ID: %d", rootPlaceId))
	setText(refs.Info.OwnerTag, buildOwnerTagText(ownerInfo))

	setText(refs.Stats.Visits, formatNumber(game.visits))
	setText(refs.Stats.Likes, formatNumber(game.likes))
	setText(refs.Stats.OwnerName, ownerInfo.Name)
	setImage(refs.Stats.OwnerImage, ownerInfo.Image)

	setText(refs.Dates.Updated, formatDate(game.updated))
	setText(refs.Dates.Created, formatDate(game.created))
	setText(refs.About.Description, game.description ~= "" and game.description or "No description available for this game yet.")

	setImage(refs.Info.GameLogo, getGameIcon(game))
	setImage(refs.Media.Thumbnail, getGameThumbnail(game))

	bindPlayButton(refs.Actions.Play, rootPlaceId)

	card:SetAttribute("UniverseId", universeId)
	card:SetAttribute("RootPlaceId", rootPlaceId)
	card:SetAttribute("Visits", tonumber(game.visits) or 0)
	card:SetAttribute("Likes", tonumber(game.likes) or 0)
	card:SetAttribute("OwnerType", tostring(ownerInfo.Type))
	card:SetAttribute("OwnerId", tonumber(ownerInfo.Id) or 0)
	return card
end

local function collectGamesFromFolder(folder)
	local games = {}
	if not folder then
		return games
	end

	for _, gameFolder in ipairs(folder:GetChildren()) do
		if gameFolder:IsA("Folder") then
			local function readValue(name)
				local object = gameFolder:FindFirstChild(name)
				if object and object:IsA("ValueBase") then
					return object.Value
				end
				return nil
			end

			local ownerJson = decodeJson(readValue("OwnerJson"))
			local thumbnailsJson = decodeJson(readValue("ThumbnailsJson"))

			table.insert(games, {
				name = gameFolder.Name,
				gameId = readValue("GameId"),
				universeId = readValue("UniverseId") or readValue("GameId"),
				placeId = readValue("PlaceId"),
				rootPlaceId = readValue("RootPlaceId") or readValue("PlaceId"),
				visits = readValue("PlayerVisits"),
				likes = readValue("Likes"),
				favoritedCount = readValue("Favorites"),
				playing = readValue("Playing"),
				description = readValue("Description") or "",
				created = readValue("Created") or "",
				updated = readValue("Updated") or "",
				iconImageUrl = readValue("IconImageUrl") or "",
				imageUrl = readValue("ImageUrl") or readValue("Image") or "",
				thumbnailImageUrl = readValue("ThumbnailImageUrl") or readValue("ThumbnailUrl") or "",
				thumbnailUrl = readValue("ThumbnailUrl") or readValue("ThumbnailImageUrl") or "",
				owner = ownerJson or readValue("Owner") or "",
				ownerName = readValue("OwnerName") or "",
				ownerUsername = readValue("OwnerUsername") or "",
				ownerDisplayName = readValue("OwnerDisplayName") or "",
				ownerType = readValue("OwnerType") or "",
				ownerId = readValue("OwnerId") or 0,
				ownerImage = readValue("OwnerImage") or "",
				thumbnails = thumbnailsJson,
				genre = readValue("Genre") or "",
			})
		end
	end

	return games
end

local function isRenderableGame(game)
	if type(game) ~= "table" then
		return false
	end

	local rootPlaceId = tonumber(game.rootPlaceId) or tonumber(game.placeId) or 0
	if rootPlaceId <= 0 then
		return false
	end

	if game.isPublic == false then
		return false
	end

	if game.isPlayable == false then
		return false
	end

	if game.isArchived == true then
		return false
	end

	if game.isUnderReview == true then
		return false
	end

	return true
end

local function getFallbackGamesFolders()
	local folders = {}
	for _, folderName in ipairs({ "Games", "FetcherGames" }) do
		local folder = ReplicatedStorage:FindFirstChild(folderName)
		if folder and folder:IsA("Folder") then
			table.insert(folders, folder)
		end
	end
	return folders
end

local function requestGames()
	local clientCallable, clientError = fetcher:GetClientCallable()
	if not clientCallable then
		warn("[GameSelectionController] " .. tostring(clientError))
	else
		local response, responseError = clientCallable:GetCurrentOwnerGames()
		if response and type(response) == "table" and type(response.games) == "table" then
			local filteredGames = {}
			for _, gameData in ipairs(response.games) do
				if isRenderableGame(gameData) then
					table.insert(filteredGames, gameData)
				end
			end
			return filteredGames
		end

		warn("[GameSelectionController] Remote fetch failed:", responseError)
	end

	for _, folder in ipairs(getFallbackGamesFolders()) do
		local fallbackGames = collectGamesFromFolder(folder)
		if #fallbackGames > 0 then
			local filteredGames = {}
			for _, gameData in ipairs(fallbackGames) do
				if isRenderableGame(gameData) then
					table.insert(filteredGames, gameData)
				end
			end
			if #filteredGames > 0 then
				return filteredGames
			end
		end
	end

	return nil
end

local function clearGeneratedCards(scroll, template)
	for _, child in ipairs(scroll:GetChildren()) do
		if child ~= template and child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function applyManualCardLayout(scroll, template, card, layoutOrder)
	if not scroll or not template or not card or getListLayout(scroll) then
		return
	end

	local templateHeight = template.AbsoluteSize.Y > 0 and template.AbsoluteSize.Y or template.Size.Y.Offset
	local templateWidth = template.AbsoluteSize.X > 0 and template.AbsoluteSize.X or template.Size.X.Offset
	local spacing = 16

	if templateHeight <= 0 then
		templateHeight = 420
	end

	if templateWidth <= 0 then
		templateWidth = scroll.AbsoluteSize.X > 0 and scroll.AbsoluteSize.X or 450
	end

	card.Position = UDim2.new(
		template.Position.X.Scale,
		template.Position.X.Offset,
		0,
		template.Position.Y.Offset + ((layoutOrder - 1) * (templateHeight + spacing))
	)
	card.Size = UDim2.new(template.Size.X.Scale, templateWidth, 0, templateHeight)
end

local function updateScrollCanvas(scroll, template, cardCount)
	if not scroll then
		return
	end

	local listLayout = getListLayout(scroll)
	if listLayout then
		task.defer(function()
			if scroll.Parent and listLayout.Parent == scroll then
				scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
			end
		end)
		return
	end

	local templateHeight = template and (template.AbsoluteSize.Y > 0 and template.AbsoluteSize.Y or template.Size.Y.Offset) or 0
	local spacing = 16

	if templateHeight <= 0 then
		templateHeight = 420
	end

	local totalHeight = 0
	if cardCount > 0 then
		totalHeight = (cardCount * templateHeight) + ((cardCount - 1) * spacing)
	end

	scroll.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end

local function sortGames(games)
	table.sort(games, function(a, b)
		local aVisits = tonumber(a.visits) or 0
		local bVisits = tonumber(b.visits) or 0
		if aVisits == bVisits then
			return tostring(a.name or "") < tostring(b.name or "")
		end
		return aVisits > bVisits
	end)
end

local function dedupeGames(games)
	local dedupedGames = {}
	local seenKeys = {}

	for _, game in ipairs(games) do
		local key = tostring(tonumber(game.universeId) or tonumber(game.gameId) or tonumber(game.rootPlaceId) or game.name or "")
		if key ~= "" and not seenKeys[key] then
			seenKeys[key] = true
			table.insert(dedupedGames, game)
		end
	end

	return dedupedGames
end

local function render()
	local refs = getRefs(screenGui, ROOT_REFS)
	local frame = refs.Frame
	local scroll = refs.Scroll
	local template = refs.Template

	if not frame or not scroll or not template then
		warn("[GameSelectionController] Required UI references are missing.")
		return
	end

	template.Visible = false
	clearGeneratedCards(scroll, template)

	local games = requestGames()
	if not games or #games == 0 then
		warn("[GameSelectionController] No games available to render.")
		return
	end

	sortGames(games)
	games = dedupeGames(games)

	for index, game in ipairs(games) do
		buildCard(scroll, template, game, index)
	end

	updateScrollCanvas(scroll, template, #games)
end

render()
