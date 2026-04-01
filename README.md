# Fetcher API

A formal Roblox metadata API for retrieving a user's public experiences together with extended game analytics and presentation data.

## Overview

Fetcher API is designed to serve Roblox game metadata to trusted consumers such as:

- Roblox server scripts
- internal dashboards
- bots and automation tools
- web panels
- analytics pipelines

The service resolves a Roblox user's public games and enriches each result with additional information, including:

- game name
- universe ID
- root place ID
- description
- creator information
- likes
- dislikes
- vote ratio
- favorites count
- visits
- concurrent player count
- max players
- created date
- published date alias
- updated date
- icon image URL
- avatar type
- genre
- VIP server availability
- API access configuration flags
- raw Roblox metadata for advanced consumers

## Base URL

```text
https://fetcher-production-2a8b.up.railway.app
```

## Authentication

Protected routes require the API secret.

You may authenticate with either:

- `x-api-secret`
- `Authorization: Bearer <secret>`

### Example

```http
Authorization: Bearer YOUR_SECRET_HERE
```

## Endpoints

### `GET /`

Returns a basic service summary.

#### Example Response

```json
{
  "name": "Fetcher API",
  "version": "2.0.0",
  "status": "online",
  "docs": "/docs",
  "health": "/health",
  "endpoints": ["/owner-games"]
}
```

### `GET /health`

Returns service health information.

#### Example Response

```json
{
  "status": "ok",
  "secretConfigured": true,
  "timestamp": "2026-04-02T12:00:00.000Z"
}
```

### `GET /docs`

Returns the built-in HTML documentation page for browser use.

### `POST /owner-games`

Returns a user's public Roblox experiences with extended metadata.

## Request Body

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
| `ownerUserId` | `number` | Yes | Roblox user ID whose public games should be resolved. |
| `include.details` | `boolean` | No | Includes extended game metadata from Roblox game detail endpoints. Default: `true`. |
| `include.votes` | `boolean` | No | Includes likes and dislikes. Default: `true`. |
| `include.favorites` | `boolean` | No | Includes favorites count. Default: `true`. |
| `include.icons` | `boolean` | No | Includes icon image URLs. Default: `true`. |
| `include.includeAll` | `boolean` | No | Enables all enrichment switches at once. |

## Response Schema

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

## Field Reference

### Top-Level Fields

| Field | Description |
| --- | --- |
| `ownerUserId` | Roblox user ID used for the query. |
| `totalGames` | Number of public games returned. |
| `requestedAt` | ISO timestamp of when the API generated the response. |
| `include` | Effective enrichment settings used during the request. |
| `games` | Array of enriched game records. |

### Game Fields

| Field | Description |
| --- | --- |
| `universeId` | Roblox universe ID. |
| `rootPlaceId` | Root place ID for the experience. |
| `name` | Final resolved game name. |
| `description` | Game description from Roblox metadata. |
| `sourceName` | Base name from the ownership listing endpoint. |
| `creator` | Roblox creator object when available. |
| `price` | Paid access price when present. |
| `allowedGearGenres` | Allowed gear genres for the experience. |
| `allowedGearCategories` | Allowed gear categories for the experience. |
| `isGenreEnforced` | Whether genre rules are enforced. |
| `copyingAllowed` | Whether copying is allowed. |
| `playing` | Current concurrent players. |
| `visits` | Total visits. |
| `maxPlayers` | Maximum players supported. |
| `created` | Roblox creation timestamp for the experience. |
| `published` | Alias of `created` for clients that prefer a published-style field. |
| `updated` | Last updated timestamp. |
| `lastUpdated` | Alias of `updated`. |
| `studioAccessToApisAllowed` | Whether Studio API access is enabled. |
| `createVipServersAllowed` | Whether VIP/private servers can be created. |
| `universeAvatarType` | Avatar rig setting. |
| `genre` | Roblox genre classification. |
| `isAllGenre` | Whether the genre is broad or unrestricted. |
| `isFavoritedByUser` | Present if Roblox includes favorite-state context. |
| `favoritedCount` | Total favorites count. |
| `iconImageUrl` | Resolved game icon URL. |
| `likes` | Up-vote count. |
| `dislikes` | Down-vote count. |
| `totalVotes` | Total vote count. |
| `likeRatio` | `likes / (likes + dislikes)`. |
| `voteData` | Raw simplified vote block. |
| `timestamps` | Grouped time metadata block. |
| `metrics` | Grouped engagement metrics block. |
| `raw` | Raw Roblox response fragments for advanced use. |

## Notes on Created vs Published

Roblox commonly exposes `created` and `updated` timestamps through game metadata endpoints. A distinct public `published` timestamp is not consistently exposed in the same response shape, so Fetcher API maps:

- `published` -> `created`
- `lastUpdated` -> `updated`

This keeps the API easier to consume for clients that expect both concepts.

## Error Responses

### Unauthorized

```json
{
  "error": "Unauthorized"
}
```

### Missing Owner User ID

```json
{
  "error": "Missing ownerUserId"
}
```

### Server Error

```json
{
  "error": "Server error",
  "details": "Error: Roblox API 500: ..."
}
```

## Roblox Lua Usage

### Minimal Example

```lua
local HttpService = game:GetService("HttpService")

local URL = "https://fetcher-production-2a8b.up.railway.app/owner-games"
local SECRET = "YOUR_SECRET_HERE"

local response = HttpService:RequestAsync({
	Url = URL,
	Method = "POST",
	Headers = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Bearer " .. SECRET,
	},
	Body = HttpService:JSONEncode({
		ownerUserId = 1,
		include = {
			details = true,
			votes = true,
			favorites = true,
			icons = true,
		},
	}),
})

if response.Success then
	local data = HttpService:JSONDecode(response.Body)
	print("Total Games:", data.totalGames)

	for _, gameInfo in ipairs(data.games) do
		print(gameInfo.name)
		print("Created:", gameInfo.created)
		print("Published:", gameInfo.published)
		print("Updated:", gameInfo.updated)
		print("Likes:", gameInfo.likes)
		print("Favorites:", gameInfo.favoritedCount)
		print("Visits:", gameInfo.visits)
	end
else
	warn(response.StatusCode, response.Body)
end
```

### Module-Oriented Example

```lua
local HttpService = game:GetService("HttpService")

local FetcherClient = {}
FetcherClient.__index = FetcherClient

function FetcherClient.new(baseUrl, secret)
	return setmetatable({
		BaseUrl = baseUrl,
		Secret = secret,
	}, FetcherClient)
end

function FetcherClient:GetOwnerGames(ownerUserId)
	local response = HttpService:RequestAsync({
		Url = self.BaseUrl .. "/owner-games",
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. self.Secret,
		},
		Body = HttpService:JSONEncode({
			ownerUserId = ownerUserId,
			include = {
				details = true,
				votes = true,
				favorites = true,
				icons = true,
			},
		}),
	})

	if not response.Success then
		return nil, response.StatusCode, response.Body
	end

	return HttpService:JSONDecode(response.Body)
end

return FetcherClient
```

## Deployment

### Railway Environment Variables

| Variable | Required | Description |
| --- | --- | --- |
| `API_SECRET` | Yes | Shared secret required to call protected routes. |
| `PORT` | No | Port assigned by the platform. |

### Start Command

```bash
npm start
```

## Security Guidance

- Keep `API_SECRET` private.
- Do not expose secrets in client-side web code.
- Prefer server-side Roblox scripts rather than client-side scripts.
- Rotate the secret if it has been shared accidentally.

## Feature Summary

Fetcher API currently supports:

- owner game enumeration
- detailed metadata enrichment
- likes and dislikes
- favorites count
- traffic metrics
- icon resolution
- creator metadata
- created and updated timestamps
- grouped metric and timestamp blocks
- raw Roblox metadata passthrough
- browser-based documentation page

## License

This project currently has no declared license.
