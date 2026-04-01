import express from "express";

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
const API_SECRET = process.env.API_SECRET;

app.get("/", (req, res) => {
  res.send("API is running");
});

app.post("/owner-games", async (req, res) => {
  try {
    const secret = req.headers["x-api-secret"];
    if (secret !== API_SECRET) {
      return res.status(401).json({ error: "Unauthorized" });
    }

    const { ownerUserId } = req.body;

    if (!ownerUserId) {
      return res.status(400).json({ error: "Missing ownerUserId" });
    }

    const response = await fetch(
      `https://games.roblox.com/v2/users/${ownerUserId}/games`
    );

    if (!response.ok) {
      const text = await response.text();
      return res.status(response.status).json({
        error: "Roblox API failed",
        details: text
      });
    }

    const data = await response.json();

    const games = (data.data || []).map((g) => ({
      universeId: g.id,
      name: g.name,
      rootPlaceId: g.rootPlaceId ?? null
    }));

    res.json({
      ownerUserId,
      games
    });
  } catch (err) {
    res.status(500).json({
      error: "Server error",
      details: String(err)
    });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});