# Fetcher

Fetcher is a small Express service plus a Roblox integration package for resolving public Roblox metadata for owners and user profiles.

## Features

- owner-to-games lookup for Roblox users and groups
- user-profile lookup by Roblox user ID
- enriched metrics, votes, favorites, ownership, and timestamps
- public profile basics, counts, groups, badges, username history, social previews, presence, and avatar thumbnails
- optional Bloxlink enrichment from Roblox user ID when a Bloxlink API key is configured
- Roblox-native thumbnail content IDs in API responses
- server-safe Roblox bootstrap flow that keeps secrets out of client code

## Project Layout

```text
.
|-- .env.example
|-- package.json
|-- server.js
`-- examples/
    `-- roblox/
        |-- bootstrap.server.lua
        |-- client-bootstrap.client.lua
        `-- fetcher.module.lua
```

## Quick Start

### 1. Install dependencies

```bash
npm install
```

### 2. Configure environment

Copy `.env.example` and set your secret:

```text
API_SECRET=replace_with_a_long_random_secret
```

### 3. Run the API

```bash
npm start
```

### 4. Verify the service

```text
GET /health
```

Expected shape:

```json
{
  "status": "ok",
  "secretConfigured": true,
  "timestamp": "2026-04-02T00:00:00.000Z"
}
```

## Roblox Example Package

The Roblox example is intentionally split into three files:

- [fetcher.module.lua](/c:/Users/arthu/Downloads/Fetcher/examples/roblox/fetcher.module.lua): shared module used by both server and client
- [bootstrap.server.lua](/c:/Users/arthu/Downloads/Fetcher/examples/roblox/bootstrap.server.lua): secure server bootstrap
- [client-bootstrap.client.lua](/c:/Users/arthu/Downloads/Fetcher/examples/roblox/client-bootstrap.client.lua): optional client helper routed through remotes

### Recommended Studio Layout

```text
ReplicatedStorage
`-- Fetcher

ServerScriptService
`-- FetcherBootstrap
    `-- Module
    |   `-- FetcherModule
    `-- Client
    |   `-- FetcherClient
    `-- Configuration
```

### Required Configuration Values

Set these in your server-side `Configuration` folder:

- `Network/BaseUrl`
- `Network/ApiSecret`

No real secrets are shipped in this repository. The Roblox samples now default to empty values and fail with a clear error message until the server configuration is set.

## API

### `POST /owner-games`

Request body:

```json
{
  "ownerType": "User",
  "ownerId": 1,
  "include": {
    "details": true,
    "votes": true,
    "favorites": true,
    "icons": true
  }
}
```

Response highlights:

- `games[].universeId`
- `games[].rootPlaceId`
- `games[].iconImageUrl`
- `games[].thumbnailImageUrl`
- `games[].ownerImage`

The image fields now prefer Roblox-native `rbxthumb://...` content IDs. Debug-friendly CDN URLs are also included as `iconWebUrl`, `thumbnailWebUrl`, and `ownerImageWebUrl`.

### `POST /profile`

Request body:

```json
{
  "userId": 1,
  "include": {
    "ownedGames": true,
    "bloxlink": true
  }
}
```

Response highlights:

- `basics.username`, `basics.displayName`, `basics.description`, `basics.created`
- `counts.followers`, `counts.followings`, `counts.friends`
- `images.headshot`, `images.avatar`
- `groups.items[]`
- `badges.items[]`
- `usernameHistory.items[]`
- `social.followersPreview.items[]`
- `ownedGames.games[]`
- `bloxlink`

## Optional Environment Variables

- `BLOXLINK_API_KEY`: enables optional Bloxlink enrichment on `/profile`
- `BLOXLINK_GUILD_ID`: if set, uses the guild-specific Bloxlink `roblox-to-discord` route instead of the global route

## Example Roblox Usage

```lua
local profile, err = fetcher:GetProfileByUserId(1)
if not profile then
	warn(err)
	return
end

fetcher:PrintProfileResponse("[Fetcher/Profile]", profile)
fetcher:BuildProfileFolder(game:GetService("ReplicatedStorage"), profile, "Profiles", true)
```

## Development

Syntax check:

```bash
npm run check
```

## Security Notes

- keep `API_SECRET` in environment variables on the API host
- keep `ApiSecret` in Roblox server-only configuration
- never place the API secret in client-only Roblox scripts
- do not automate RoPro access; their Terms of Service prohibit automated access through APIs, bots, and scrapers

## License

No license has been declared yet.
