import express from "express";

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
const API_SECRET = process.env.API_SECRET;
const BLOXLINK_API_KEY = process.env.BLOXLINK_API_KEY || "";
const BLOXLINK_GUILD_ID = process.env.BLOXLINK_GUILD_ID || "";

const DEFAULT_INCLUDE = {
  details: true,
  votes: true,
  favorites: true,
  icons: true
};

const DEFAULT_PROFILE_INCLUDE = {
  basics: true,
  counts: true,
  images: true,
  presence: true,
  groups: true,
  badges: true,
  usernameHistory: true,
  friendsPreview: true,
  followersPreview: true,
  followingsPreview: true,
  ownedGames: true,
  bloxlink: true
};

const FAVORITES_CONCURRENCY = 5;
const SOCIAL_PREVIEW_LIMIT = 10;
const BADGES_PREVIEW_LIMIT = 10;
const USERNAME_HISTORY_LIMIT = 10;

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

async function fetchJsonWithOptions(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();

  if (!response.ok) {
    throw new Error(`Roblox API ${response.status}: ${text}`);
  }

  return JSON.parse(text);
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

async function fetchJsonWithOptionsSafe(url, options, fallbackValue) {
  try {
    return await fetchJsonWithOptions(url, options);
  } catch (error) {
    const errorText = String(error);
    if (errorText.includes("Roblox API 429") || errorText.includes(" 404:")) {
      return fallbackValue;
    }

    throw error;
  }
}

function normalizeProfileInclude(input = {}) {
  const includeAll = input.includeAll === true;

  return {
    basics: includeAll || input.basics !== false,
    counts: includeAll || input.counts !== false,
    images: includeAll || input.images !== false,
    presence: includeAll || input.presence !== false,
    groups: includeAll || input.groups !== false,
    badges: includeAll || input.badges !== false,
    usernameHistory: includeAll || input.usernameHistory !== false,
    friendsPreview: includeAll || input.friendsPreview !== false,
    followersPreview: includeAll || input.followersPreview !== false,
    followingsPreview: includeAll || input.followingsPreview !== false,
    ownedGames: includeAll || input.ownedGames !== false,
    bloxlink: includeAll || input.bloxlink !== false
  };
}

function buildProfileUrl(userId) {
  return `https://www.roblox.com/users/${userId}/profile`;
}

function buildAvatarHeadshotContentId(userId) {
  return userId
    ? `rbxthumb://type=AvatarHeadShot&id=${userId}&w=420&h=420`
    : null;
}

function buildAvatarBustContentId(userId) {
  return userId
    ? `rbxthumb://type=AvatarBust&id=${userId}&w=420&h=420`
    : null;
}

function buildAvatarContentId(userId) {
  return userId
    ? `rbxthumb://type=Avatar&id=${userId}&w=720&h=720`
    : null;
}

function buildSocialLinkContentId(userId) {
  return userId
    ? `rbxthumb://type=AvatarHeadShot&id=${userId}&w=150&h=150`
    : null;
}

async function getUsersByIds(userIds) {
  const normalizedIds = Array.from(
    new Set(
      (userIds || [])
        .map((userId) => Number(userId))
        .filter((userId) => Number.isInteger(userId) && userId > 0)
    )
  );

  if (normalizedIds.length === 0) {
    return [];
  }

  const data = await fetchJsonWithOptions(
    "https://users.roblox.com/v1/users",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        userIds: normalizedIds
      })
    }
  );

  return data.data || [];
}

async function getUserHeadshotsByIds(userIds, size = "150x150") {
  const normalizedIds = Array.from(
    new Set(
      (userIds || [])
        .map((userId) => Number(userId))
        .filter((userId) => Number.isInteger(userId) && userId > 0)
    )
  );

  if (normalizedIds.length === 0) {
    return new Map();
  }

  const data = await fetchJsonSafe(
    `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=${normalizedIds.join(",")}&size=${size}&format=Png&isCircular=false`,
    { data: [] }
  );

  const imageMap = new Map();
  for (const entry of data.data || []) {
    imageMap.set(entry.targetId, entry.imageUrl ?? null);
  }

  return imageMap;
}

async function getUserProfileBasics(userId) {
  return fetchJson(`https://users.roblox.com/v1/users/${userId}`);
}

async function getUserAvatarImages(userId) {
  const [headshotData, bustData, avatarData] = await Promise.all([
    fetchJsonSafe(
      `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=${userId}&size=420x420&format=Png&isCircular=false`,
      { data: [] }
    ),
    fetchJsonSafe(
      `https://thumbnails.roblox.com/v1/users/avatar-bust?userIds=${userId}&size=420x420&format=Png&isCircular=false`,
      { data: [] }
    ),
    fetchJsonSafe(
      `https://thumbnails.roblox.com/v1/users/avatar?userIds=${userId}&size=720x720&format=Png&isCircular=false`,
      { data: [] }
    )
  ]);

  const headshotUrl = headshotData.data?.[0]?.imageUrl ?? null;
  const bustUrl = bustData.data?.[0]?.imageUrl ?? null;
  const avatarUrl = avatarData.data?.[0]?.imageUrl ?? null;

  return {
    headshot: {
      url: buildAvatarHeadshotContentId(userId),
      imageUrl: buildAvatarHeadshotContentId(userId),
      webUrl: headshotUrl,
      webImageUrl: headshotUrl
    },
    bust: {
      url: buildAvatarBustContentId(userId),
      imageUrl: buildAvatarBustContentId(userId),
      webUrl: bustUrl,
      webImageUrl: bustUrl
    },
    avatar: {
      url: buildAvatarContentId(userId),
      imageUrl: buildAvatarContentId(userId),
      webUrl: avatarUrl,
      webImageUrl: avatarUrl
    }
  };
}

async function getUserCounts(userId) {
  const [friends, followers, followings] = await Promise.all([
    fetchJsonSafe(`https://friends.roblox.com/v1/users/${userId}/friends/count`, { count: null }),
    fetchJsonSafe(`https://friends.roblox.com/v1/users/${userId}/followers/count`, { count: null }),
    fetchJsonSafe(`https://friends.roblox.com/v1/users/${userId}/followings/count`, { count: null })
  ]);

  return {
    friends: friends.count ?? null,
    followers: followers.count ?? null,
    followings: followings.count ?? null
  };
}

async function getUserPresence(userId) {
  const data = await fetchJsonWithOptionsSafe(
    "https://presence.roblox.com/v1/presence/users",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        userIds: [userId]
      })
    },
    { userPresences: [] }
  );

  return data.userPresences?.[0] ?? null;
}

async function getUserGroups(userId) {
  const data = await fetchJsonSafe(
    `https://groups.roblox.com/v2/users/${userId}/groups/roles`,
    { data: [] }
  );

  return (data.data || []).map((entry) => ({
    id: entry.group?.id ?? null,
    name: entry.group?.name ?? null,
    memberCount: entry.group?.memberCount ?? null,
    hasVerifiedBadge: entry.group?.hasVerifiedBadge ?? false,
    roleId: entry.role?.id ?? null,
    roleName: entry.role?.name ?? null,
    roleRank: entry.role?.rank ?? null
  }));
}

async function getUserBadges(userId, limit = BADGES_PREVIEW_LIMIT) {
  const data = await fetchJsonSafe(
    `https://badges.roblox.com/v1/users/${userId}/badges?limit=${limit}&sortOrder=Desc`,
    { data: [], nextPageCursor: null, previousPageCursor: null }
  );

  return {
    totalReturned: (data.data || []).length,
    nextPageCursor: data.nextPageCursor ?? null,
    previousPageCursor: data.previousPageCursor ?? null,
    items: (data.data || []).map((badge) => ({
      id: badge.id ?? null,
      name: badge.name ?? null,
      description: badge.description ?? "",
      enabled: badge.enabled ?? null
    }))
  };
}

async function getUsernameHistory(userId, limit = USERNAME_HISTORY_LIMIT) {
  const data = await fetchJsonSafe(
    `https://users.roblox.com/v1/users/${userId}/username-history?limit=${limit}&sortOrder=Desc`,
    { data: [], nextPageCursor: null, previousPageCursor: null }
  );

  return {
    totalReturned: (data.data || []).length,
    nextPageCursor: data.nextPageCursor ?? null,
    previousPageCursor: data.previousPageCursor ?? null,
    items: (data.data || []).map((entry) => entry.name).filter(Boolean)
  };
}

async function getSocialPreview(kind, userId, limit = SOCIAL_PREVIEW_LIMIT) {
  let url = "";

  if (kind === "friends") {
    url = `https://friends.roblox.com/v1/users/${userId}/friends?userSort=Alphabetical&limit=${limit}`;
  } else if (kind === "followers") {
    url = `https://friends.roblox.com/v1/users/${userId}/followers?sortOrder=Desc&limit=${limit}`;
  } else if (kind === "followings") {
    url = `https://friends.roblox.com/v1/users/${userId}/followings?sortOrder=Desc&limit=${limit}`;
  } else {
    return {
      totalReturned: 0,
      nextPageCursor: null,
      previousPageCursor: null,
      items: []
    };
  }

  const page = await fetchJsonSafe(url, {
    data: [],
    nextPageCursor: null,
    previousPageCursor: null
  });

  const ids = (page.data || [])
    .map((entry) => Number(entry.id))
    .filter((entryId) => Number.isInteger(entryId) && entryId > 0);

  const [users, headshots] = await Promise.all([
    getUsersByIds(ids),
    getUserHeadshotsByIds(ids)
  ]);

  const usersById = new Map(users.map((entry) => [entry.id, entry]));

  return {
    totalReturned: ids.length,
    nextPageCursor: page.nextPageCursor ?? null,
    previousPageCursor: page.previousPageCursor ?? null,
    items: ids.map((entryId) => {
      const user = usersById.get(entryId) || {};
      const webImageUrl = headshots.get(entryId) ?? null;

      return {
        id: entryId,
        userId: entryId,
        username: user.name ?? null,
        name: user.name ?? null,
        displayName: user.displayName ?? user.name ?? null,
        hasVerifiedBadge: user.hasVerifiedBadge ?? false,
        profileUrl: buildProfileUrl(entryId),
        image: buildSocialLinkContentId(entryId),
        imageUrl: buildSocialLinkContentId(entryId),
        imageWebUrl: webImageUrl
      };
    })
  };
}

async function getBloxlinkProfileByRobloxUserId(robloxUserId) {
  if (!BLOXLINK_API_KEY) {
    return {
      enabled: false,
      configured: false,
      mode: null,
      data: null
    };
  }

  const mode = BLOXLINK_GUILD_ID ? "guild" : "global";
  const url = mode === "guild"
    ? `https://api.blox.link/v4/public/guilds/${encodeURIComponent(BLOXLINK_GUILD_ID)}/roblox-to-discord/${robloxUserId}`
    : `https://api.blox.link/v4/public/roblox-to-discord/${robloxUserId}`;

  const data = await fetchJsonWithOptionsSafe(
    url,
    {
      headers: {
        Authorization: BLOXLINK_API_KEY
      }
    },
    null
  );

  return {
    enabled: true,
    configured: true,
    mode,
    guildId: BLOXLINK_GUILD_ID || null,
    data
  };
}

async function buildUserProfileResponse(userId, include = DEFAULT_PROFILE_INCLUDE) {
  const numericUserId = Number(userId);
  if (!Number.isInteger(numericUserId) || numericUserId <= 0) {
    throw new Error("userId must be a positive integer");
  }

  const [
    basics,
    counts,
    images,
    presence,
    groups,
    badges,
    usernameHistory,
    friendsPreview,
    followersPreview,
    followingsPreview,
    ownedGames,
    bloxlink
  ] = await Promise.all([
    include.basics ? getUserProfileBasics(numericUserId) : Promise.resolve(null),
    include.counts ? getUserCounts(numericUserId) : Promise.resolve(null),
    include.images ? getUserAvatarImages(numericUserId) : Promise.resolve(null),
    include.presence ? getUserPresence(numericUserId) : Promise.resolve(null),
    include.groups ? getUserGroups(numericUserId) : Promise.resolve([]),
    include.badges ? getUserBadges(numericUserId) : Promise.resolve(null),
    include.usernameHistory ? getUsernameHistory(numericUserId) : Promise.resolve(null),
    include.friendsPreview ? getSocialPreview("friends", numericUserId) : Promise.resolve(null),
    include.followersPreview ? getSocialPreview("followers", numericUserId) : Promise.resolve(null),
    include.followingsPreview ? getSocialPreview("followings", numericUserId) : Promise.resolve(null),
    include.ownedGames ? buildOwnerGamesResponse("User", numericUserId, DEFAULT_INCLUDE) : Promise.resolve(null),
    include.bloxlink ? getBloxlinkProfileByRobloxUserId(numericUserId) : Promise.resolve(null)
  ]);

  if (!basics && include.basics) {
    throw new Error("Profile basics could not be resolved");
  }

  return {
    userId: numericUserId,
    requestedAt: new Date().toISOString(),
    profileUrl: buildProfileUrl(numericUserId),
    include,
    basics: basics
      ? {
          id: basics.id ?? numericUserId,
          userId: basics.id ?? numericUserId,
          username: basics.name ?? null,
          name: basics.name ?? null,
          displayName: basics.displayName ?? basics.name ?? null,
          description: basics.description ?? "",
          created: basics.created ?? null,
          isBanned: basics.isBanned ?? null,
          hasVerifiedBadge: basics.hasVerifiedBadge ?? false,
          externalAppDisplayName: basics.externalAppDisplayName ?? null,
          profileUrl: buildProfileUrl(numericUserId)
        }
      : null,
    counts,
    images,
    presence,
    groups: include.groups
      ? {
          totalReturned: groups.length,
          items: groups
        }
      : null,
    badges,
    usernameHistory,
    social: {
      friendsPreview,
      followersPreview,
      followingsPreview
    },
    ownedGames,
    bloxlink
  };
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

async function getOwnedGamesByUserId(ownerUserId, limit = 50) {
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

async function getOwnedGamesByGroupId(groupId, limit = 50) {
  let cursor = "";
  const games = [];

  do {
    const page = await fetchJson(
      `https://games.roblox.com/v2/groups/${groupId}/gamesV2?accessFilter=Public&limit=${limit}&sortOrder=Asc${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`
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

async function getGameThumbnails(universeIds) {
  const thumbnailsMap = new Map();
  const chunks = chunkArray(universeIds, 100);

  await Promise.all(
    chunks.map(async (chunk) => {
      const data = await fetchJsonSafe(
        `https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds=${chunk.join(",")}&countPerUniverse=1&defaults=true&size=768x432&format=Png&isCircular=false`,
        { data: [] }
      );

      for (const thumbnail of data.data || []) {
        if (!thumbnailsMap.has(thumbnail.universeId ?? thumbnail.targetId)) {
          thumbnailsMap.set(
            thumbnail.universeId ?? thumbnail.targetId,
            thumbnail.imageUrl ?? null
          );
        }
      }
    })
  );

  return thumbnailsMap;
}

function getOwnerMapKey(ownerType, ownerId) {
  if (!ownerType || !ownerId) {
    return null;
  }

  return `${String(ownerType).toLowerCase()}:${ownerId}`;
}

function buildGameIconContentId(universeId) {
  if (!universeId) {
    return null;
  }

  return `rbxthumb://type=GameIcon&id=${universeId}&w=150&h=150`;
}

function buildGameThumbnailContentId(placeId) {
  if (!placeId) {
    return null;
  }

  return `rbxthumb://type=GameThumbnail&id=${placeId}&w=768&h=432`;
}

function buildOwnerContentId(ownerType, ownerId) {
  if (!ownerId) {
    return null;
  }

  if (ownerType === "Group") {
    return `rbxthumb://type=GroupIcon&id=${ownerId}&w=420&h=420`;
  }

  return `rbxthumb://type=AvatarHeadShot&id=${ownerId}&w=420&h=420`;
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
  const ownerContentId = buildOwnerContentId(ownerType, ownerId);

  return {
    id: ownerId,
    userId: ownerId,
    username: ownerName,
    name: ownerName,
    displayName: ownerDisplayName,
    type: ownerType,
    image: ownerContentId ?? ownerImageUrl ?? null,
    imageUrl: ownerContentId ?? ownerImageUrl ?? null,
    imageWebUrl: ownerImageUrl ?? null
  };
}

function buildThumbnailRecord(contentImageUrl, contentIconUrl, webImageUrl, webIconUrl) {
  return {
    url: contentImageUrl ?? null,
    imageUrl: contentImageUrl ?? null,
    iconUrl: contentIconUrl ?? null,
    thumbnailUrl: contentImageUrl ?? null,
    webUrl: webImageUrl ?? null,
    webImageUrl: webImageUrl ?? null,
    webIconUrl: webIconUrl ?? null
  };
}

function buildGameRecord(baseGame, detail, vote, favoritesCount, iconUrl, thumbnailUrl, ownerImageUrl) {
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
  const placeId = detail?.rootPlaceId ?? baseGame.rootPlaceId ?? baseGame.placeId ?? null;
  const iconContentId = buildGameIconContentId(baseGame.universeId);
  const thumbnailContentId = buildGameThumbnailContentId(placeId);
  const thumbnail = buildThumbnailRecord(thumbnailContentId, iconContentId, thumbnailUrl, iconUrl);
  const thumbnails = {
    icon: thumbnail,
    gameIcon: thumbnail,
    primary: thumbnail,
    list: [thumbnail]
  };

  return {
    universeId: baseGame.universeId,
    placeId,
    gameId: baseGame.universeId,
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
    ownerImage: owner.image ?? null,
    ownerImageWebUrl: ownerImageUrl ?? null,
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
    iconImageUrl: iconContentId ?? iconUrl ?? null,
    iconWebUrl: iconUrl ?? null,
    imageUrl: thumbnailContentId ?? iconContentId ?? thumbnailUrl ?? iconUrl ?? null,
    imageWebUrl: thumbnailUrl ?? iconUrl ?? null,
    thumbnailImageUrl: thumbnailContentId ?? thumbnailUrl ?? null,
    thumbnailWebUrl: thumbnailUrl ?? null,
    thumbnailUrl: thumbnailContentId ?? thumbnailUrl ?? null,
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

async function buildOwnerGamesResponse(ownerType, ownerId, include = DEFAULT_INCLUDE) {
  const normalizedOwnerType = String(ownerType || "User").toLowerCase();
  const baseGames = normalizedOwnerType === "group"
    ? await getOwnedGamesByGroupId(ownerId)
    : await getOwnedGamesByUserId(ownerId);
  const universeIds = baseGames.map((game) => game.universeId);

  if (universeIds.length === 0) {
    return {
      ownerType: normalizedOwnerType === "group" ? "Group" : "User",
      ownerId,
      ownerUserId: normalizedOwnerType === "user" ? ownerId : null,
      ownerGroupId: normalizedOwnerType === "group" ? ownerId : null,
      totalGames: 0,
      requestedAt: new Date().toISOString(),
      include,
      games: []
    };
  }

  const [detailsMap, votesMap, favoritesMap, iconsMap, thumbnailsMap] = await Promise.all([
    include.details ? getGameDetails(universeIds) : Promise.resolve(new Map()),
    include.votes ? getGameVotes(universeIds) : Promise.resolve(new Map()),
    include.favorites ? getGameFavorites(universeIds) : Promise.resolve(new Map()),
    include.icons ? getGameIcons(universeIds) : Promise.resolve(new Map()),
    include.details ? getGameThumbnails(universeIds) : Promise.resolve(new Map())
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
      thumbnailsMap.get(game.universeId),
      ownerImagesMap.get(
        getOwnerMapKey(
          detailsMap.get(game.universeId)?.creator?.type,
          detailsMap.get(game.universeId)?.creator?.id
        )
      )
    )
  );

  return {
    ownerType: normalizedOwnerType === "group" ? "Group" : "User",
    ownerId,
    ownerUserId: normalizedOwnerType === "user" ? ownerId : null,
    ownerGroupId: normalizedOwnerType === "group" ? ownerId : null,
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
        <li><code>POST /profile</code> returns a public Roblox user profile bundle by user ID.</li>
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

    <section class="card">
      <h2>Profile Request Example</h2>
      <pre>{
  "userId": 1,
  "include": {
    "ownedGames": true,
    "bloxlink": true
  }
}</pre>
      <p>The profile response can include basics, avatar images, counts, presence, groups, badges, username history, social previews, owned games, and optional Bloxlink enrichment.</p>
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
    endpoints: ["/owner-games", "/profile"]
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
    const {
      ownerType = "User",
      ownerId,
      ownerUserId,
      ownerGroupId,
      include = DEFAULT_INCLUDE
    } = req.body || {};

    const resolvedOwnerId = ownerId ?? ownerUserId ?? ownerGroupId;
    if (!resolvedOwnerId) {
      return res.status(400).json({ error: "Missing ownerId" });
    }

    const response = await buildOwnerGamesResponse(ownerType, resolvedOwnerId, normalizeInclude(include));
    return res.json(response);
  } catch (error) {
    return res.status(500).json({
      error: "Server error",
      details: String(error)
    });
  }
});

app.post("/profile", async (req, res) => {
  if (!requireAuth(req, res)) {
    return;
  }

  try {
    const {
      userId,
      targetUserId,
      ownerUserId,
      include = DEFAULT_PROFILE_INCLUDE
    } = req.body || {};

    const resolvedUserId = userId ?? targetUserId ?? ownerUserId;
    if (!resolvedUserId) {
      return res.status(400).json({ error: "Missing userId" });
    }

    const response = await buildUserProfileResponse(resolvedUserId, normalizeProfileInclude(include));
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
