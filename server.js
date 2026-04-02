import express from "express";

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
const API_SECRET = process.env.API_SECRET;

const DEFAULT_INCLUDE = {
  details: true,
  votes: true,
  favorites: true,
  icons: true
};

const FAVORITES_CONCURRENCY = 5;

function getRequestSecret(req) {
  const headerSecret = req.headers["x-api-secret"];
  if (headerSecret) {
    return headerSecret;
  }

  const authHeader = req.headers.authorization;
  if (typeof authHeader === "string" && authHeader.startsWith("Bearer ")) {
    return authHeader.slice(7);
  }

  return null;
}

function requireAuth(req, res) {
  if (!API_SECRET) {
    res.status(500).json({
      error: "API secret is not configured on the server"
    });
    return false;
  }

  const secret = getRequestSecret(req);
  if (secret !== API_SECRET) {
    res.status(401).json({ error: "Unauthorized" });
    return false;
  }

  return true;
}

function normalizeInclude(input = {}) {
  const includeAll = input.includeAll === true;

  return {
    details: includeAll || input.details !== false,
    votes: includeAll || input.votes !== false,
    favorites: includeAll || input.favorites !== false,
    icons: includeAll || input.icons !== false
  };
}

function chunkArray(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

async function fetchText(url) {
  const response = await fetch(url);
  const text = await response.text();

  if (!response.ok) {
    throw new Error(`Roblox API ${response.status}: ${text}`);
  }

  return text;
}

async function fetchJson(url) {
  return JSON.parse(await fetchText(url));
}

async function fetchJsonSafe(url, fallbackValue) {
  try {
    return await fetchJson(url);
  } catch (error) {
    if (String(error).includes("Roblox API 429")) {
      return fallbackValue;
    }

    throw error;
  }
}

async function mapWithConcurrency(items, concurrency, mapper) {
  const results = new Array(items.length);
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      results[currentIndex] = await mapper(items[currentIndex], currentIndex);
    }
  }

  const workers = Array.from(
    { length: Math.min(concurrency, items.length) },
    () => worker()
  );

  await Promise.all(workers);
  return results;
}

async function getOwnedGames(ownerUserId, limit = 50) {
  let cursor = "";
  const games = [];

  do {
    const page = await fetchJson(
      `https://games.roblox.com/v2/users/${ownerUserId}/games?accessFilter=Public&limit=${limit}&sortOrder=Asc${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`
    );

    games.push(...(page.data || []));
    cursor = page.nextPageCursor || "";
  } while (cursor);

  return games.map((game) => ({
    id: game.id,
    universeId: game.id,
    placeId: game.rootPlaceId ?? null,
    rootPlaceId: game.rootPlaceId ?? null,
    name: game.name ?? "Unknown"
  }));
}

async function getGameDetails(universeIds) {
  const detailsMap = new Map();
  const chunks = chunkArray(universeIds, 100);

  await Promise.all(
    chunks.map(async (chunk) => {
      const data = await fetchJsonSafe(
        `https://games.roblox.com/v1/games?universeIds=${chunk.join(",")}`
        ,
        { data: [] }
      );

      for (const game of data.data || []) {
        detailsMap.set(game.id, game);
      }
    })
  );

  return detailsMap;
}

async function getGameVotes(universeIds) {
  const votesMap = new Map();
  const chunks = chunkArray(universeIds, 100);

  await Promise.all(
    chunks.map(async (chunk) => {
      const data = await fetchJsonSafe(
        `https://games.roblox.com/v1/games/votes?universeIds=${chunk.join(",")}`
        ,
        { data: [] }
      );

      for (const vote of data.data || []) {
        votesMap.set(vote.id, vote);
      }
    })
  );

  return votesMap;
}

async function getGameFavorites(universeIds) {
  const favoritesEntries = await mapWithConcurrency(
    universeIds,
    FAVORITES_CONCURRENCY,
    async (universeId) => {
      const data = await fetchJsonSafe(
        `https://games.roblox.com/v1/games/${universeId}/favorites/count`,
        { favoritesCount: null }
      );

      return [universeId, data.favoritesCount ?? null];
    }
  );

  return new Map(favoritesEntries);
}

async function getGameIcons(universeIds) {
  const iconsMap = new Map();
  const chunks = chunkArray(universeIds, 100);

  await Promise.all(
    chunks.map(async (chunk) => {
      const data = await fetchJsonSafe(
        `https://thumbnails.roblox.com/v1/games/icons?universeIds=${chunk.join(",")}&returnPolicy=PlaceHolder&size=512x512&format=Png&isCircular=false`
        ,
        { data: [] }
      );

      for (const icon of data.data || []) {
        iconsMap.set(icon.targetId, icon.imageUrl ?? null);
      }
    })
  );

  return iconsMap;
}

function getOwnerMapKey(ownerType, ownerId) {
  if (!ownerType || !ownerId) {
    return null;
  }

  return `${String(ownerType).toLowerCase()}:${ownerId}`;
}

async function getOwnerImages(gameDetails) {
  const ownerImagesMap = new Map();
  const userIds = [];
  const groupIds = [];
  const seenKeys = new Set();

  for (const detail of gameDetails) {
    const ownerType = detail?.creator?.type ?? null;
    const ownerId = detail?.creator?.id ?? null;
    const ownerKey = getOwnerMapKey(ownerType, ownerId);

    if (!ownerKey || seenKeys.has(ownerKey)) {
      continue;
    }

    seenKeys.add(ownerKey);

    if (ownerType === "User") {
      userIds.push(ownerId);
    } else if (ownerType === "Group") {
      groupIds.push(ownerId);
    }
  }

  const userChunks = chunkArray(userIds, 100);
  await Promise.all(
    userChunks.map(async (chunk) => {
      const data = await fetchJsonSafe(
        `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=${chunk.join(",")}&size=150x150&format=Png&isCircular=false`,
        { data: [] }
      );

      for (const userThumbnail of data.data || []) {
        ownerImagesMap.set(getOwnerMapKey("User", userThumbnail.targetId), userThumbnail.imageUrl ?? null);
      }
    })
  );

  const groupChunks = chunkArray(groupIds, 100);
  await Promise.all(
    groupChunks.map(async (chunk) => {
      const data = await fetchJsonSafe(
        `https://thumbnails.roblox.com/v1/groups/icons?groupIds=${chunk.join(",")}&size=150x150&format=Png&isCircular=false`,
        { data: [] }
      );

      for (const groupThumbnail of data.data || []) {
        ownerImagesMap.set(getOwnerMapKey("Group", groupThumbnail.targetId), groupThumbnail.imageUrl ?? null);
      }
    })
  );

  return ownerImagesMap;
}

function buildOwnerRecord(creator, ownerImageUrl) {
  const ownerId = creator?.id ?? null;
  const ownerName = creator?.name ?? null;
  const ownerDisplayName = creator?.displayName ?? ownerName;
  const ownerType = creator?.type ?? null;

  return {
    id: ownerId,
    userId: ownerId,
    username: ownerName,
    name: ownerName,
    displayName: ownerDisplayName,
    type: ownerType,
    image: ownerImageUrl ?? null,
    imageUrl: ownerImageUrl ?? null
  };
}

function buildThumbnailRecord(iconUrl) {
  return {
    url: iconUrl ?? null,
    imageUrl: iconUrl ?? null,
    iconUrl: iconUrl ?? null,
    thumbnailUrl: iconUrl ?? null
  };
}

function buildGameRecord(baseGame, detail, vote, favoritesCount, iconUrl, ownerImageUrl) {
  const upVotes = vote?.upVotes ?? 0;
  const downVotes = vote?.downVotes ?? 0;
  const totalVotes = upVotes + downVotes;
  const likeRatio = totalVotes > 0 ? upVotes / totalVotes : null;
  const created = detail?.created ?? null;
  const updated = detail?.updated ?? null;
  const creator = detail?.creator ?? null;
  const owner = buildOwnerRecord(creator, ownerImageUrl);
  const ownerId = owner.id;
  const ownerName = owner.name;
  const ownerUsername = owner.username;
  const ownerDisplayName = owner.displayName;
  const ownerType = owner.type;
  const placeId = baseGame.placeId ?? baseGame.rootPlaceId ?? detail?.rootPlaceId ?? null;
  const thumbnail = buildThumbnailRecord(iconUrl);
  const thumbnails = {
    icon: thumbnail,
    gameIcon: thumbnail,
    primary: thumbnail,
    list: [thumbnail]
  };

  return {
    universeId: baseGame.universeId,
    placeId,
    gameId: placeId,
    rootPlaceId: placeId,
    name: detail?.name ?? baseGame.name,
    description: detail?.description ?? "",
    sourceName: baseGame.name,
    creator,
    ownerId,
    ownerUserId: ownerId,
    ownerName,
    ownerUsername,
    ownerDisplayName,
    ownerType,
    ownerImage: ownerImageUrl ?? null,
    owner,
    price: detail?.price ?? null,
    allowedGearGenres: detail?.allowedGearGenres ?? [],
    allowedGearCategories: detail?.allowedGearCategories ?? [],
    isGenreEnforced: detail?.isGenreEnforced ?? false,
    copyingAllowed: detail?.copyingAllowed ?? false,
    playing: detail?.playing ?? 0,
    visits: detail?.visits ?? 0,
    maxPlayers: detail?.maxPlayers ?? null,
    created,
    published: created,
    updated,
    lastUpdated: updated,
    studioAccessToApisAllowed: detail?.studioAccessToApisAllowed ?? false,
    createVipServersAllowed: detail?.createVipServersAllowed ?? false,
    universeAvatarType: detail?.universeAvatarType ?? null,
    genre: detail?.genre ?? null,
    isAllGenre: detail?.isAllGenre ?? false,
    isFavoritedByUser: detail?.isFavoritedByUser ?? false,
    favoritedCount: favoritesCount ?? 0,
    iconImageUrl: iconUrl ?? null,
    imageUrl: iconUrl ?? null,
    thumbnailImageUrl: iconUrl ?? null,
    thumbnailUrl: iconUrl ?? null,
    thumbnails,
    likes: upVotes,
    dislikes: downVotes,
    totalVotes,
    likeRatio,
    voteData: vote
      ? {
          upVotes,
          downVotes
        }
      : null,
    timestamps: {
      created,
      published: created,
      updated,
      lastUpdated: updated
    },
    metrics: {
      playing: detail?.playing ?? 0,
      visits: detail?.visits ?? 0,
      favorites: favoritesCount ?? 0,
      likes: upVotes,
      dislikes: downVotes,
      totalVotes,
      likeRatio
    },
    raw: {
      detail: detail ?? null,
      vote: vote ?? null
    }
  };
}

async function buildOwnerGamesResponse(ownerUserId, include = DEFAULT_INCLUDE) {
  const baseGames = await getOwnedGames(ownerUserId);
  const universeIds = baseGames.map((game) => game.universeId);

  if (universeIds.length === 0) {
    return {
      ownerUserId,
      totalGames: 0,
      requestedAt: new Date().toISOString(),
      include,
      games: []
    };
  }

  const [detailsMap, votesMap, favoritesMap, iconsMap] = await Promise.all([
    include.details ? getGameDetails(universeIds) : Promise.resolve(new Map()),
    include.votes ? getGameVotes(universeIds) : Promise.resolve(new Map()),
    include.favorites ? getGameFavorites(universeIds) : Promise.resolve(new Map()),
    include.icons ? getGameIcons(universeIds) : Promise.resolve(new Map())
  ]);
  const ownerImagesMap = include.details
    ? await getOwnerImages(Array.from(detailsMap.values()))
    : new Map();

  const games = baseGames.map((game) =>
    buildGameRecord(
      game,
      detailsMap.get(game.universeId),
      votesMap.get(game.universeId),
      favoritesMap.get(game.universeId),
      iconsMap.get(game.universeId),
      ownerImagesMap.get(
        getOwnerMapKey(
          detailsMap.get(game.universeId)?.creator?.type,
          detailsMap.get(game.universeId)?.creator?.id
        )
      )
    )
  );

  return {
    ownerUserId,
    totalGames: games.length,
    requestedAt: new Date().toISOString(),
    include,
    games
  };
}

function docsHtml() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Fetcher API Documentation</title>
  <style>
    :root {
      --bg: #0b1220;
      --panel: #121b2d;
      --muted: #9fb0cf;
      --text: #e8eefc;
      --accent: #72e1d1;
      --line: #24314a;
      --code: #0d1526;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Georgia, "Times New Roman", serif;
      background: radial-gradient(circle at top, #182542 0%, var(--bg) 55%);
      color: var(--text);
      line-height: 1.6;
    }
    .wrap {
      max-width: 980px;
      margin: 0 auto;
      padding: 48px 20px 72px;
    }
    .hero, .card {
      background: rgba(18, 27, 45, 0.88);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 28px;
      backdrop-filter: blur(8px);
      box-shadow: 0 20px 60px rgba(0, 0, 0, 0.28);
    }
    .hero { margin-bottom: 22px; }
    .card { margin-top: 18px; }
    h1, h2, h3 { margin: 0 0 12px; }
    h1 { font-size: 2.4rem; }
    h2 { font-size: 1.35rem; color: var(--accent); }
    p, li { color: var(--muted); }
    code, pre {
      font-family: Consolas, Monaco, monospace;
      background: var(--code);
    }
    code {
      padding: 2px 6px;
      border-radius: 6px;
      color: #d9fff7;
    }
    pre {
      padding: 16px;
      overflow: auto;
      border-radius: 12px;
      border: 1px solid var(--line);
    }
    a { color: var(--accent); }
    ul { padding-left: 20px; }
  </style>
</head>
<body>
  <div class="wrap">
    <section class="hero">
      <h1>Fetcher API</h1>
      <p>A formal Roblox owner-game aggregation API for server-side tooling, in-experience scripts, and automation workflows.</p>
      <p>Authentication is required on protected routes. Send either <code>x-api-secret</code> or <code>Authorization: Bearer &lt;secret&gt;</code>.</p>
    </section>

    <section class="card">
      <h2>Endpoints</h2>
      <ul>
        <li><code>GET /</code> returns a service summary.</li>
        <li><code>GET /health</code> returns service health and secret configuration state.</li>
        <li><code>GET /docs</code> returns this HTML documentation page.</li>
        <li><code>POST /owner-games</code> returns an owner's public Roblox games with extended metadata.</li>
      </ul>
    </section>

    <section class="card">
      <h2>Request Example</h2>
      <pre>{
  "ownerUserId": 123456789,
  "includeAll": true
}</pre>
    </section>

    <section class="card">
      <h2>Response Highlights</h2>
      <ul>
        <li><code>ownerUserId</code>: the user whose public games were resolved.</li>
        <li><code>totalGames</code>: total returned game count.</li>
        <li><code>games[].likes</code> and <code>games[].dislikes</code>: Roblox vote counts.</li>
        <li><code>games[].favoritedCount</code>: Roblox favorites count.</li>
        <li><code>games[].visits</code>, <code>games[].playing</code>, <code>games[].maxPlayers</code>: traffic and concurrency metadata.</li>
        <li><code>games[].iconImageUrl</code>: resolved game icon.</li>
      </ul>
    </section>
  </div>
</body>
</html>`;
}

app.get("/", (req, res) => {
  res.json({
    name: "Fetcher API",
    version: "2.0.0",
    status: "online",
    docs: "/docs",
    health: "/health",
    endpoints: ["/owner-games"]
  });
});

app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    secretConfigured: Boolean(API_SECRET),
    timestamp: new Date().toISOString()
  });
});

app.get("/docs", (req, res) => {
  res.type("html").send(docsHtml());
});

app.post("/owner-games", async (req, res) => {
  if (!requireAuth(req, res)) {
    return;
  }

  try {
    const { ownerUserId, include = DEFAULT_INCLUDE } = req.body || {};

    if (!ownerUserId) {
      return res.status(400).json({ error: "Missing ownerUserId" });
    }

    const response = await buildOwnerGamesResponse(ownerUserId, normalizeInclude(include));
    return res.json(response);
  } catch (error) {
    return res.status(500).json({
      error: "Server error",
      details: String(error)
    });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});
