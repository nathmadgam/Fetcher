# Fetcher API

A Roblox metadata API that returns a user's public experiences together with useful game details like likes, favorites, visits, icons, creator info, and timestamps.

This project is built to be easy to use from:

- Roblox `ServerScriptService`
- Railway deployments
- internal tools
- dashboards
- bots

## What This API Gives You

For each public game owned by a Roblox user, Fetcher API can return:

- game name
- universe ID
- root place ID
- description
- creator info
- likes
- dislikes
- favorites count
- visits
- current playing count
- max players
- icon URL
- genre
- avatar type
- creation timestamp
- published timestamp alias
- updated timestamp

## Quick Start

If you just want this working as fast as possible, follow these steps.

### 1. Deploy the API

Deploy this project to Railway.

### 2. Set Your Railway Secret

In Railway, open your service and add this environment variable:

```text
API_SECRET=your_secret_here
```

After adding it, redeploy the service.

### 3. Confirm the API Is Online

Open:

```text
https://your-railway-url.up.railway.app/health
```

You should see:

```json
{
  "status": "ok",
  "secretConfigured": true,
  "timestamp": "..."
}
```

If `secretConfigured` is `false`, Railway does not have `API_SECRET` set correctly yet.

### 4. Enable HTTP Requests in Roblox

In Roblox Studio:

```text
Home > Game Settings > Security > Allow HTTP Requests = ON
```

### 5. Put This Script In ServerScriptService

Use a normal `Script`, not a `LocalScript`.

```lua
local HttpService = game:GetService("HttpService")
local GroupService = game:GetService("GroupService")

local BASE_URL = "https://your-railway-url.up.railway.app"
local OWNER_GAMES_ENDPOINT = BASE_URL .. "/owner-games"
local API_SECRET = "your_secret_here"

local REQUESTED_DATA_OPTIONS = {
	details = true,
	votes = true,
	favorites = true,
	icons = true,
}

local function decodeApiJsonResponse(responseBody)
	local success, decodedData = pcall(function()
		return HttpService:JSONDecode(responseBody)
	end)

	if not success then
		return nil, "Failed to decode JSON response."
	end

	return decodedData
end

local function resolveExperienceOwnerUserId()
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

local function requestOwnerGameCatalog(ownerUserId)
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = OWNER_GAMES_ENDPOINT,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["Authorization"] = "Bearer " .. API_SECRET,
			},
			Body = HttpService:JSONEncode({
				ownerUserId = ownerUserId,
				include = REQUESTED_DATA_OPTIONS,
			}),
		})
	end)

	if not success then
		return nil, "HTTP request crashed before the API responded."
	end

	if not response.Success then
		return nil, "Request failed: " .. tostring(response.StatusCode) .. " | " .. tostring(response.Body)
	end

	return decodeApiJsonResponse(response.Body)
end

local ownerUserId, ownerResolutionError = resolveExperienceOwnerUserId()
if not ownerUserId then
	warn(ownerResolutionError)
	return
end

local ownerGameCatalog, requestError = requestOwnerGameCatalog(ownerUserId)
if not ownerGameCatalog then
	warn(requestError)
	return
end

print("Owner User ID:", ownerGameCatalog.ownerUserId)
print("Total Games:", ownerGameCatalog.totalGames)

for index, gameData in ipairs(ownerGameCatalog.games or {}) do
	print("Game #" .. index)
	print("Name:", gameData.name)
	print("Likes:", gameData.likes)
	print("Favorites:", gameData.favoritedCount)
	print("Visits:", gameData.visits)
	print("Created:", gameData.created)
	print("Updated:", gameData.updated)
end
```

## Base URL

```text
https://fetcher-production-2a8b.up.railway.app
```

Replace this with your own deployed Railway URL if needed.

## Authentication

Protected routes require your API secret.

You can send it using either:

- `Authorization: Bearer YOUR_SECRET`
- `x-api-secret: YOUR_SECRET`

## Endpoints

### `GET /`

Returns basic API information.

#### Example

```json
{
  "name": "Fetcher API",
  "version": "2.0.0",
  "status": "online",
  "docs": "/docs",
  "health": "/health",
  "endpoints": [
    "/owner-games"
  ]
}
```

### `GET /health`

Returns service health information.

#### Example

```json
{
  "status": "ok",
  "secretConfigured": true,
  "timestamp": "2026-04-02T12:00:00.000Z"
}
```

### `GET /docs`

Returns the built-in browser documentation page.

### `POST /owner-games`

Returns public games owned by a Roblox user, with optional enrichment data.

## `POST /owner-games`

### Request Body

```json
{
  "ownerUserId": 1,
  "include": {
    "details": true,
    "votes": true,
    "favorites": true,
    "icons": true
  }
}
```

### Request Fields

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `ownerUserId` | `number` | Yes | Roblox user ID to fetch games for. |
| `include.details` | `boolean` | No | Include detailed game metadata. |
| `include.votes` | `boolean` | No | Include likes and dislikes. |
| `include.favorites` | `boolean` | No | Include favorites count. |
| `include.icons` | `boolean` | No | Include icon image URLs. |
| `include.includeAll` | `boolean` | No | Turn on all enrichment options. |

## Example cURL Request

```bash
curl -X POST "https://fetcher-production-2a8b.up.railway.app/owner-games" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_SECRET_HERE" \
  -d "{\"ownerUserId\":1,\"include\":{\"details\":true,\"votes\":true,\"favorites\":true,\"icons\":true}}"
```

## Example Response

```json
{
  "ownerUserId": 1,
  "totalGames": 1,
  "requestedAt": "2026-04-02T12:00:00.000Z",
  "include": {
    "details": true,
    "votes": true,
    "favorites": true,
    "icons": true
  },
  "games": [
    {
      "universeId": 1818,
      "rootPlaceId": 12345,
      "name": "Example Experience",
      "description": "Example description",
      "sourceName": "Example Experience",
      "creator": {
        "id": 1,
        "name": "Roblox",
        "type": "User",
        "isRNVAccount": false,
        "hasVerifiedBadge": true
      },
      "price": null,
      "allowedGearGenres": [],
      "allowedGearCategories": [],
      "isGenreEnforced": false,
      "copyingAllowed": false,
      "playing": 120,
      "visits": 500000,
      "maxPlayers": 50,
      "created": "2024-01-01T12:00:00.000Z",
      "published": "2024-01-01T12:00:00.000Z",
      "updated": "2026-03-31T16:50:00.000Z",
      "lastUpdated": "2026-03-31T16:50:00.000Z",
      "studioAccessToApisAllowed": false,
      "createVipServersAllowed": true,
      "universeAvatarType": "MorphToR15",
      "genre": "All",
      "isAllGenre": true,
      "isFavoritedByUser": false,
      "favoritedCount": 10000,
      "iconImageUrl": "https://tr.rbxcdn.com/example.png",
      "likes": 3000,
      "dislikes": 150,
      "totalVotes": 3150,
      "likeRatio": 0.9523809524,
      "voteData": {
        "upVotes": 3000,
        "downVotes": 150
      },
      "timestamps": {
        "created": "2024-01-01T12:00:00.000Z",
        "published": "2024-01-01T12:00:00.000Z",
        "updated": "2026-03-31T16:50:00.000Z",
        "lastUpdated": "2026-03-31T16:50:00.000Z"
      },
      "metrics": {
        "playing": 120,
        "visits": 500000,
        "favorites": 10000,
        "likes": 3000,
        "dislikes": 150,
        "totalVotes": 3150,
        "likeRatio": 0.9523809524
      },
      "raw": {
        "detail": {},
        "vote": {}
      }
    }
  ]
}
```

## Response Field Guide

### Top-Level Fields

| Field | Meaning |
| --- | --- |
| `ownerUserId` | The Roblox user ID that was requested. |
| `totalGames` | Total number of public games returned. |
| `requestedAt` | ISO timestamp for when the API built the response. |
| `include` | The enrichment options used for the request. |
| `games` | List of returned games. |

### Important Game Fields

| Field | Meaning |
| --- | --- |
| `name` | Game name. |
| `universeId` | Roblox universe ID. |
| `rootPlaceId` | Roblox root place ID. |
| `description` | Game description. |
| `likes` | Up-vote count. |
| `dislikes` | Down-vote count. |
| `favoritedCount` | Favorites count. |
| `visits` | Total visits. |
| `playing` | Current active players. |
| `maxPlayers` | Max players allowed. |
| `created` | Creation timestamp. |
| `published` | Alias of `created`. |
| `updated` | Last updated timestamp. |
| `lastUpdated` | Alias of `updated`. |
| `iconImageUrl` | Game icon URL. |
| `creator` | Creator information. |
| `metrics` | Grouped engagement metrics. |
| `timestamps` | Grouped time information. |
| `raw` | Raw Roblox detail and vote payloads. |

## Created vs Published

Roblox commonly exposes:

- `created`
- `updated`

A separate public `published` timestamp is not always returned in the same endpoint shape, so this API maps:

- `published = created`
- `lastUpdated = updated`

This keeps the API more convenient for consumers that expect both names.

## Troubleshooting

### Error: Unauthorized

This means the secret you sent does not match the server's `API_SECRET`.

Check:

- the Railway variable is named exactly `API_SECRET`
- your Roblox script uses the same exact secret
- you redeployed after updating Railway variables

### Error: API secret is not configured on the server

This means Railway is running, but `API_SECRET` was never set for that service.

Fix:

```text
1. Open Railway
2. Open your service
3. Go to Variables
4. Add API_SECRET
5. Save
6. Redeploy
```

### Error: Too many requests

This comes from Roblox rate limits, not from your Roblox script directly.

Fetcher API already tries to handle this more gracefully, but if Roblox throttles hard enough, some fields may be missing temporarily.

### Error: No public games were found

This means the resolved owner does not currently have public games available through the Roblox API.

## Railway Setup

### Required Variables

| Variable | Required | Description |
| --- | --- | --- |
| `API_SECRET` | Yes | Secret used to authenticate protected routes. |
| `PORT` | No | Provided automatically by Railway. |

### Start Command

```bash
npm start
```

## Project Structure

```text
Fetcher/
├─ package.json
├─ package-lock.json
├─ server.js
└─ README.md
```

## Security Notes

- Keep your API secret private.
- Do not put your secret in public GitHub repositories.
- Do not expose the secret in client-side browser code.
- Prefer Roblox server scripts over local scripts for requests like this.
- Rotate the secret if it has been exposed.

## Feature Summary

Fetcher API supports:

- owner game lookup
- likes and dislikes
- favorites count
- visits and playing count
- icon URLs
- creator metadata
- timestamps
- grouped metrics
- grouped timestamps
- raw Roblox payload passthrough
- browser docs page

## License

This project currently has no declared license.
