# Fetcher

Fetcher is a Roblox-focused metadata API with a reusable Roblox integration layer.

The project is designed to grow into a family of fetchers under one shared system. Right now, the first implemented fetcher is:

- `owner-games`

The current Roblox integration is structured so developers can install a shared module once, then consume server and client support without manually rebuilding request logic for each script.

## Goals

Fetcher is designed to be:

- modular
- configurable
- secure
- friendly to require from Roblox
- ready for future fetcher types such as game passes, badges, groups, and more

## Current Fetcher

### Owner Games Fetcher

The Owner Games Fetcher returns a user's public Roblox experiences together with enriched metadata such as:

- name
- universe ID
- root place ID
- description
- creator details
- likes
- dislikes
- favorites count
- visits
- live playing count
- max players
- icon URL
- creation timestamp
- published timestamp alias
- updated timestamp
- grouped metric and timestamp blocks

## Quick Start

### 1. Deploy the API

Deploy this project to Railway.

### 2. Set Your Secret

In Railway, add:

```text
API_SECRET=your_secret_here
```

Redeploy the service after saving the variable.

### 3. Verify the Service

Open:

```text
https://your-railway-url.up.railway.app/health
```

Expected response:

```json
{
  "status": "ok",
  "secretConfigured": true,
  "timestamp": "..."
}
```

### 4. Enable HTTP Requests in Roblox

In Roblox Studio:

```text
Home > Game Settings > Security > Allow HTTP Requests = ON
```

## Roblox Integration

Fetcher now includes three Roblox example scripts:

- [Fetcher.module.lua](c:\Users\arthu\Downloads\Fetcher\examples\roblox\Fetcher.module.lua)
- [FetcherServer.server.lua](c:\Users\arthu\Downloads\Fetcher\examples\roblox\FetcherServer.server.lua)
- [FetcherClient.client.lua](c:\Users\arthu\Downloads\Fetcher\examples\roblox\FetcherClient.client.lua)

These examples are meant to work together:

1. `Fetcher.module.lua` is the shared configurable module
2. `FetcherServer.server.lua` enables secure server access and optional client support
3. `FetcherClient.client.lua` is the client bootstrap that can be injected automatically when client support is enabled

## Recommended Roblox Placement

Use this structure in Studio:

```text
ReplicatedStorage
`- Fetcher               (ModuleScript)

ServerScriptService
`- FetcherServer         (Script)
   `- FetcherClient      (LocalScript, optional child template for injection)
```

### Why this layout

- `ReplicatedStorage.Fetcher` lets both server and client `require(...)` the same module
- `ServerScriptService.FetcherServer` keeps the API secret on the server
- the optional child `LocalScript` lets the server automatically inject client support into players

## Configuration

All primary configuration lives in the module.

Inside `Fetcher.module.lua`, edit:

```lua
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
```

### Configuration Fields

| Field | Description |
| --- | --- |
| `BaseUrl` | Base URL of your deployed Fetcher API |
| `ApiSecret` | Secret sent to the API from secure server calls |
| `Include` | Default enrichment fields to request |
| `ClientSupport.Enabled` | Enables client support through remotes |
| `ClientSupport.AutoInjectBootstrap` | Automatically injects the client LocalScript into player scripts |
| `ClientSupport.ReplicatedFolderName` | ReplicatedStorage folder name used for remotes |
| `ClientSupport.RequestFunctionName` | RemoteFunction name used for client requests |
| `ClientSupport.ClientBootstrapName` | Name used when injecting the client bootstrap |

## How the Three Scripts Work

### 1. `Fetcher.module.lua`

This is the shared module that developers `require(...)`.

It handles:

- configuration
- health checks
- authenticated server requests
- owner user ID resolution
- owner game requests
- optional client remote support
- automatic LocalScript injection helpers
- utility shaping such as building games by universe ID

### 2. `FetcherServer.server.lua`

This is the secure server bootstrap.

It handles:

- checking API health
- confirming `API_SECRET` exists on the deployed API
- enabling client support when configured
- injecting the client bootstrap into player scripts when configured
- making secure owner-games requests from the server

### 3. `FetcherClient.client.lua`

This is the client bootstrap.

It does **not** use the API secret directly.

Instead, it:

- requires the shared module
- connects to the server-created RemoteFunction
- requests supported fetcher actions through the server
- receives the same returned data shape safely

This keeps your secret protected while still giving client-side code access when you choose to enable it.

## Server Setup

### Step 1

Place [Fetcher.module.lua](c:\Users\arthu\Downloads\Fetcher\examples\roblox\Fetcher.module.lua) into `ReplicatedStorage` and rename it to:

```text
Fetcher
```

### Step 2

Place [FetcherServer.server.lua](c:\Users\arthu\Downloads\Fetcher\examples\roblox\FetcherServer.server.lua) into `ServerScriptService` and rename it to:

```text
FetcherServer
```

### Step 3

If you want automatic client support injection, parent [FetcherClient.client.lua](c:\Users\arthu\Downloads\Fetcher\examples\roblox\FetcherClient.client.lua) under the server script and rename it to:

```text
FetcherClient
```

That gives you this structure:

```text
ServerScriptService
`- FetcherServer
   `- FetcherClient
```

When `ClientSupport.Enabled = true` and `ClientSupport.AutoInjectBootstrap = true`, the server bootstrap will clone that LocalScript into player script containers automatically.

## Manual Client Setup

If you do not want automatic injection, set:

```lua
ClientSupport = {
	Enabled = true,
	AutoInjectBootstrap = false,
}
```

Then place [FetcherClient.client.lua](c:\Users\arthu\Downloads\Fetcher\examples\roblox\FetcherClient.client.lua) directly into:

```text
StarterPlayer
`- StarterPlayerScripts
```

## Example Usage

### Server Example

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fetcher = require(ReplicatedStorage:WaitForChild("Fetcher"))
local fetcher = Fetcher.new()

local ownerGamesResponse, requestError = fetcher:GetCurrentOwnerGames()
if not ownerGamesResponse then
	warn(requestError)
	return
end

print(ownerGamesResponse.ownerUserId)
print(ownerGamesResponse.totalGames)
```

### Client Example

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fetcher = require(ReplicatedStorage:WaitForChild("Fetcher"))
local fetcher = Fetcher.new()

local clientFetcher, clientFetcherError = fetcher:GetClientCallable()
if not clientFetcher then
	warn(clientFetcherError)
	return
end

local ownerGamesResponse, requestError = clientFetcher:GetCurrentOwnerGames()
if not ownerGamesResponse then
	warn(requestError)
	return
end

print(ownerGamesResponse.totalGames)
```

## Current Server Methods

The shared module currently supports these main server-side methods:

- `Fetcher.new(configurationOverride)`
- `fetcher:GetHealth()`
- `fetcher:ResolveCurrentExperienceOwnerUserId()`
- `fetcher:GetOwnerGamesByUserId(ownerUserId, includeOverride)`
- `fetcher:GetCurrentOwnerGames(includeOverride)`
- `fetcher:BuildGamesByUniverseId(ownerGamesResponse)`
- `fetcher:EnableClientSupport()`
- `fetcher:InjectClientBootstrap(clientBootstrapTemplate)`

## Current Client Methods

The client callable currently supports:

- `clientFetcher:GetCurrentOwnerGames(includeOverride)`
- `clientFetcher:GetOwnerGamesByUserId(ownerUserId, includeOverride)`

These are routed through the server so the client never needs direct access to the API secret.

## API Endpoints

### `GET /`

Returns service metadata.

### `GET /health`

Returns service health information.

### `GET /docs`

Returns the built-in browser documentation page.

### `POST /owner-games`

Returns public games owned by a Roblox user with optional enrichment data.

## `POST /owner-games` Request Body

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

## Example API Response

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
      "likes": 3000,
      "dislikes": 150,
      "favoritedCount": 10000,
      "visits": 500000,
      "playing": 120,
      "created": "2024-01-01T12:00:00.000Z",
      "published": "2024-01-01T12:00:00.000Z",
      "updated": "2026-03-31T16:50:00.000Z",
      "lastUpdated": "2026-03-31T16:50:00.000Z",
      "iconImageUrl": "https://tr.rbxcdn.com/example.png"
    }
  ]
}
```

## Troubleshooting

### `Unauthorized`

The secret sent from the server module does not match the API server's `API_SECRET`.

### `API secret is not configured on the server`

Railway is online, but `API_SECRET` has not been configured for that deployed service.

### `Too many requests`

Roblox throttled one or more underlying Roblox web endpoints. Some fields may be temporarily unavailable.

### Client cannot fetch

Check:

- `ClientSupport.Enabled` is `true`
- the server bootstrap ran successfully
- the remote function exists in `ReplicatedStorage`
- the client bootstrap was injected or placed correctly

## Security Notes

- Keep the API secret server-side only
- do not expose `ApiSecret` in public client-only packages
- prefer using the server bootstrap for authenticated access
- use client support only when you intentionally want client scripts to consume fetcher data

## Future Expansion

Fetcher is intentionally named broadly so future fetchers can be added under the same module style.

Likely future additions:

- game pass fetchers
- badge fetchers
- asset fetchers
- group fetchers
- inventory fetchers

## License

This project currently has no declared license.
