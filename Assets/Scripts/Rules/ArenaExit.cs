using System;
using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    public static class ArenaGen
    {
        public static Bag Pick(int rseed, Bag room, string mode, int stageIdx)
        {
            if (room != null && room.Get("arena_fixed") is Bag pinned) return pinned.Clone();
            var cfg = Db.Table("arenas");
            var rng = new Rng();
            rng.SetSeed(RunState.Mix(rseed, 9001));
            string type = J.S(room, "type", "battle");
            if (!((Bag)cfg["types"]).Has(type)) type = "battle";
            if (type == "battle" && stageIdx == 0 && J.I(room, "step", 1) == 0) type = "tutorial";
            var t = (Bag)((Bag)cfg["types"])[type];
            var growArr = (List<object>)cfg["stage_grow"];
            int grow = type == "tutorial" ? 0 : J.I(growArr[J.Clamp(stageIdx, 0, growArr.Count - 1)]);
            int big = 0;
            foreach (var id in J.Arr(room, "enemies"))
                if (J.I(Db.Enemy(J.S(id)), "hp") >= J.I(cfg, "big_hp")) big = J.I(cfg, "big_bonus");
            int shrink = mode == "ambush" && type != "tutorial" ? J.I(cfg, "ambush_shrink") : 0;
            var lo = (List<object>)cfg["min"];
            var hi = (List<object>)cfg["max"];
            var tw = (List<object>)t["w"];
            var th = (List<object>)t["h"];
            int w = J.Clamp(rng.RandiRange(J.I(tw[0]), J.I(tw[1]) + grow) + big - shrink, J.I(lo[0]), J.I(hi[0]));
            int h = J.Clamp(rng.RandiRange(J.I(th[0]), J.I(th[1]) + grow) + big - shrink, J.I(lo[1]), J.I(hi[1]));
            string shape = J.Weighted(rng, (Bag)cfg["shapes"]);
            if (w * h < 56 && shape != "rect") shape = "rect";
            int cutX = 0, cutY = 0;
            if (shape == "chamfer")
            {
                cutX = rng.RandiRange(1, 2);
                if (Math.Min(w, h) < 7) cutX = 1;
            }
            else if (shape == "L")
            {
                cutX = rng.RandiRange(2, Math.Max(2, w / 3));
                cutY = rng.RandiRange(2, Math.Max(2, h / 3));
                cutX = Math.Min(cutX, w - 5);
                cutY = Math.Min(cutY, h - 4);
                if (cutX < 2 || cutY < 2) { shape = "rect"; cutX = 0; cutY = 0; }
            }
            var spec = new Bag();
            spec.Set("w", w);
            spec.Set("h", h);
            spec.Set("shape", shape);
            spec.Set("cut", new V2(cutX, cutY));
            spec.Set("type", type);
            spec.Set("corner", (int)(rng.Randi() % 4));
            return spec;
        }

        public static bool IsVoid(Bag spec, int x, int y)
        {
            int w = J.I(spec, "w"), h = J.I(spec, "h");
            var cut = spec.Get("cut") is V2 v ? v : V2.Zero;
            string shape = J.S(spec, "shape");
            if (shape == "chamfer")
                return Math.Min(x, w - 1 - x) + Math.Min(y, h - 1 - y) < cut.X;
            if (shape == "L")
            {
                int corner = J.I(spec, "corner");
                int cx = corner % 2 == 0 ? x : w - 1 - x;
                int cy = corner < 2 ? y : h - 1 - y;
                return cx >= w - cut.X && cy >= h - cut.Y;
            }
            return false;
        }
    }

    public static class ExitGen
    {
        public static readonly string[] Sides = { "NE", "NW", "SE", "SW" };
        public static readonly string[] Forward = { "NE", "NW" };

        public static V2 OutDir(string side)
        {
            if (side == "NE") return new V2(0, -1);
            if (side == "NW") return new V2(-1, 0);
            if (side == "SE") return new V2(1, 0);
            return new V2(0, 1);
        }

        public static List<Bag> Corridor(V2 pos, string side, int width = 3, int length = 6)
        {
            var d = OutDir(side);
            var perp = new V2(Math.Abs(d.Y), Math.Abs(d.X));
            int half = width / 2;
            var outList = new List<Bag>();
            for (int k = 1; k <= length; k++)
                for (int o = -half; o < width - half; o++)
                {
                    var cell = new Bag();
                    cell.Set("tile", pos + d * k + perp * o);
                    cell.Set("k", k);
                    cell.Set("o", o);
                    outList.Add(cell);
                }
            return outList;
        }

        public static List<V2> SideTiles(BGrid g, string side)
        {
            var outList = new List<V2>();
            if (side == "NE") for (int x = 1; x < g.W - 1; x++) outList.Add(new V2(x, 0));
            else if (side == "SW") for (int x = 1; x < g.W - 1; x++) outList.Add(new V2(x, g.H - 1));
            else if (side == "NW") for (int y = 1; y < g.H - 1; y++) outList.Add(new V2(0, y));
            else if (side == "SE") for (int y = 1; y < g.H - 1; y++) outList.Add(new V2(g.W - 1, y));
            outList.RemoveAll(g.IsVoid);
            return outList;
        }

        public static string SideOf(BGrid g, V2 p)
        {
            if (p.Y == 0) return "NE";
            if (p.Y == g.H - 1) return "SW";
            if (p.X == 0) return "NW";
            if (p.X == g.W - 1) return "SE";
            return "";
        }

        public static V2 InnerNeighbor(BGrid g, V2 p)
        {
            switch (SideOf(g, p))
            {
                case "NE": return p + new V2(0, 1);
                case "SW": return p + new V2(0, -1);
                case "NW": return p + new V2(1, 0);
                case "SE": return p + new V2(-1, 0);
                default: return p;
            }
        }

        static void MakeWalkable(BGrid g, V2 p)
        {
            var t = g.GetTile(p);
            if (t == "obstacle" || t == "water") g.SetTile(p, "ground");
        }

        public static List<Bag> PlaceExits(BGrid g, int count, Rng rng, V2 from, List<V2> avoid = null)
        {
            count = J.Clamp(count, 1, StageGen.MaxExits);
            var sides = new List<string>(Sides);
            for (int i = sides.Count - 1; i > 0; i--)
            {
                int j = rng.RandiRange(0, i);
                (sides[i], sides[j]) = (sides[j], sides[i]);
            }
            string fwd = null;
            foreach (var sd in sides) if (sd == "NE" || sd == "NW") { fwd = sd; break; }
            sides.Remove(fwd);
            sides.Insert(0, fwd);
            var placed = new List<Bag>();
            for (int k = 0; k < count; k++)
            {
                string side = sides[k];
                var tiles = SideTiles(g, side);
                for (int i = tiles.Count - 1; i > 0; i--)
                {
                    int j = rng.RandiRange(0, i);
                    (tiles[i], tiles[j]) = (tiles[j], tiles[i]);
                }
                var chosen = V2.None;
                foreach (var t in tiles)
                {
                    if (t == from || (avoid != null && avoid.Contains(t))) continue;
                    bool far = true;
                    foreach (var o in placed)
                        if (V2.Dist((V2)o["pos"], t) < 3) far = false;
                    if (!far) continue;
                    chosen = t;
                    string tile = g.GetTile(t);
                    if (tile != "obstacle" && tile != "water") break;
                }
                if (chosen == V2.None) chosen = tiles[0];
                MakeWalkable(g, chosen);
                MakeWalkable(g, InnerNeighbor(g, chosen));
                EnsureReachable(g, from, chosen);
                var row = new Bag();
                row.Set("pos", chosen);
                row.Set("side", side);
                row.Set("dir", OutDir(side));
                placed.Add(row);
            }
            return placed;
        }

        static void EnsureReachable(BGrid g, V2 from, V2 to)
        {
            if (g.ReachTiles(from, 999, new Dictionary<V2, object>(), null).Cost.ContainsKey(to)) return;
            var p = from;
            while (p.X != to.X)
            {
                p = new V2(p.X + J.Sign(to.X - p.X), p.Y);
                if (g.GetTile(p) == "obstacle") g.SetTile(p, "ground");
            }
            while (p.Y != to.Y)
            {
                p = new V2(p.X, p.Y + J.Sign(to.Y - p.Y));
                if (g.GetTile(p) == "obstacle") g.SetTile(p, "ground");
            }
        }

        public static V2 PlaceSecret(BGrid g, Rng rng, V2 from, List<V2> avoid)
        {
            var cands = new List<V2>();
            for (int y = 2; y < g.H - 2; y++)
                for (int x = 2; x < g.W - 2; x++)
                {
                    var p = new V2(x, y);
                    string t = g.GetTile(p);
                    if (t != "ground" && t != "grass") continue;
                    if (p == from || V2.Dist(p, from) < 3) continue;
                    bool ok = true;
                    if (avoid != null)
                        foreach (var a in avoid)
                            if (V2.Dist(p, a) < 3) ok = false;
                    if (ok && g.ReachTiles(from, 999, new Dictionary<V2, object>(), null).Cost.ContainsKey(p))
                        cands.Add(p);
                }
            if (cands.Count == 0) return V2.None;
            return cands[(int)(rng.Randi() % (uint)cands.Count)];
        }
    }

    public static class StageGen
    {
        public const int MaxExits = 3;

        public static int DoorCount(Bag sd, Rng rng)
        {
            int n = 1;
            var d = sd.Get("doors");
            if (d is List<object> arr) n = rng.RandiRange(J.I(arr[0]), J.I(arr[1]));
            else n = J.I(d, 1);
            return J.Clamp(n, 1, MaxExits);
        }

        public static Bag MakeCaveRoom(RunState run)
        {
            var sec = (Bag)run.StageDef()["secret"];
            int step = J.I(run.Stage, "step");
            int seed = RunState.Mix(RunState.Mix(run.SeedVal, 9000 + run.StageIdx), step + 1);
            var rng = new Rng();
            rng.SetSeed(seed);
            var enemies = new List<object>();
            foreach (var e in PickGroup(rng, (List<object>)sec["groups"], 99)) enemies.Add(e);
            var inf = new List<object>();
            foreach (var _ in enemies) inf.Add(false);
            var room = new Bag();
            room.Set("type", "cave");
            room.Set("step", step);
            room.Set("door", -1);
            room.Set("seed", seed);
            room.Set("visited", true);
            room.Set("stage", J.S(run.Stage, "id"));
            room.Set("enemies", enemies);
            room.Set("infected", inf);
            room.Set("unspotted_allowed", rng.Randf() < 0.6f);
            room.Set("trap", false);
            room.Set("teach", "");
            room.Set("theme", J.S(sec, "theme", "cave"));
            room.Set("terrain", J.Ob(sec, "terrain") ?? new Bag());
            room.Set("reward", J.Ob(sec, "reward") ?? new Bag());
            return room;
        }

        public static List<Bag> GenerateSteps(string stageId, Bag def, Rng rng, int runSeed, int idx)
        {
            var steps = new List<Bag>();
            var stepDefs = (List<object>)def["steps"];
            for (int i = 0; i < stepDefs.Count; i++)
            {
                var sd = (Bag)stepDefs[i];
                int n = DoorCount(sd, rng);
                var types = new List<object>();
                var weights = ((Bag)sd["types"]).Clone();
                for (int d = 0; d < n; d++)
                {
                    string t = J.Weighted(rng, weights);
                    int tries = 0;
                    while (types.Contains(t) && weights.Count > 1 && tries < 12)
                    {
                        t = J.Weighted(rng, weights);
                        tries++;
                    }
                    types.Add(t);
                }
                var step = new Bag();
                step.Set("types", types);
                step.Set("forced", sd.Has("force"));
                step.Set("chosen", -1);
                step.Set("doors", new List<object>());
                steps.Add(step);
            }
            foreach (var reqObj in J.Arr(def, "required"))
            {
                string req = J.S(reqObj);
                bool present = false;
                foreach (var s in steps)
                    if (((List<object>)s["types"]).Contains(req)) present = true;
                if (present) continue;
                var slots = new List<int[]>();
                for (int i = 0; i < steps.Count; i++)
                {
                    var types = (List<object>)steps[i]["types"];
                    var sd = (Bag)stepDefs[i];
                    if (J.B(steps[i], "forced") || ((Bag)sd["types"]).Has("boss")) continue;
                    for (int d = 0; d < types.Count; d++) slots.Add(new[] { i, d });
                }
                var preferred = slots.FindAll(sl => J.S(((List<object>)steps[sl[0]]["types"])[sl[1]]) == "battle");
                var pickFrom = preferred.Count > 0 ? preferred : slots;
                if (pickFrom.Count > 0)
                {
                    var sl = pickFrom[(int)(rng.Randi() % (uint)pickFrom.Count)];
                    ((List<object>)steps[sl[0]]["types"])[sl[1]] = req;
                }
            }
            var used = new List<string>();
            for (int i = 0; i < steps.Count; i++)
            {
                var types = (List<object>)steps[i]["types"];
                var doors = (List<object>)steps[i]["doors"];
                for (int d = 0; d < types.Count; d++)
                {
                    int roomSeed = RunState.Mix(RunState.Mix(RunState.Mix(runSeed, idx + 1), i + 1), d + 1);
                    var r = new Rng();
                    r.SetSeed(roomSeed);
                    doors.Add(MakeRoom(stageId, def, J.S(types[d]), i, d, roomSeed, r, (Bag)stepDefs[i], used));
                }
            }
            return steps;
        }

        public static List<object> PickGroup(Rng rng, List<object> groups, int step)
        {
            var items = new List<(int key, float w)>();
            for (int i = 0; i < groups.Count; i++)
            {
                var g = (Bag)groups[i];
                if (J.I(g, "min_step", 1) <= step + 1) items.Add((i, J.F(g, "weight", 1f)));
            }
            if (items.Count == 0) return (List<object>)((Bag)groups[0])["enemies"];
            int pick = J.Weighted(rng, items);
            var enemies = (List<object>)((Bag)groups[pick])["enemies"];
            return enemies;
        }

        static Bag MakeRoom(string stageId, Bag def, string type, int step, int door, int roomSeed, Rng rng, Bag stepDef, List<string> usedEvents)
        {
            var room = new Bag();
            room.Set("type", type);
            room.Set("step", step);
            room.Set("door", door);
            room.Set("seed", roomSeed);
            room.Set("visited", false);
            room.Set("stage", stageId);
            room.Set("enemies", new List<object>());
            room.Set("infected", new List<object>());
            room.Set("unspotted_allowed", false);
            room.Set("trap", false);
            room.Set("teach", "");
            if (type == "battle" || type == "elite" || type == "boss")
            {
                List<object> enemies;
                if (type == "boss") enemies = CloneList((List<object>)((Bag)def["boss"])["enemies"]);
                else if (type == "elite") enemies = CloneList(PickGroup(rng, (List<object>)def["elite_groups"], step));
                else if (stepDef.Has("force"))
                {
                    var force = (Bag)stepDef["force"];
                    enemies = CloneList((List<object>)force["enemies"]);
                    room.Set("teach", J.S(force, "teach", ""));
                }
                else enemies = CloneList(PickGroup(rng, (List<object>)def["battle_groups"], step));
                room.Set("enemies", enemies);
                var inf = new List<object>();
                foreach (var e in enemies)
                {
                    var ed = Db.Enemy(J.S(e));
                    inf.Add(J.B(ed, "infected") || rng.Randf() < J.F(ed, "infected_chance"));
                }
                room.Set("infected", inf);
                if (type == "boss") { room.Set("unspotted_allowed", false); room.Set("trap", true); }
                else if (stepDef.Has("force") && J.B((Bag)stepDef["force"], "unspotted")) room.Set("unspotted_allowed", true);
                else
                {
                    float chance = J.F(def, "unspotted_chance", 0.6f);
                    if (type == "elite") chance *= 0.6f;
                    if (rng.Randf() < J.F(def, "trap_chance", 0.1f)) room.Set("trap", true);
                    else room.Set("unspotted_allowed", rng.Randf() < chance);
                }
            }
            else if (type == "event")
            {
                var evs = (Bag)Db.Table("events")["events"];
                var pool = new List<string>();
                foreach (var k in evs.Keys)
                    if (StageHas((Bag)evs[k], stageId) && !usedEvents.Contains(k)) pool.Add(k);
                if (pool.Count == 0)
                    foreach (var k in evs.Keys)
                        if (StageHas((Bag)evs[k], stageId)) pool.Add(k);
                string pick = pool[(int)(rng.Randi() % (uint)pool.Count)];
                usedEvents.Add(pick);
                room.Set("event_id", pick);
            }
            else if (type == "forage")
            {
                var fg = (Bag)Db.Table("events")["forage"];
                var pool = new List<string>();
                foreach (var k in fg.Keys)
                    if (StageHas((Bag)fg[k], stageId)) pool.Add(k);
                var picked = new List<object>();
                while (picked.Count < 3 && pool.Count > 0)
                {
                    int i = (int)(rng.Randi() % (uint)pool.Count);
                    picked.Add(pool[i]);
                    pool.RemoveAt(i);
                }
                room.Set("forage_ids", picked);
            }
            else if (type == "puzzle")
            {
                string pid = "stone_sequence";
                var pd = (Bag)Db.Table("puzzles")[pid];
                var per = (Bag)pd["per_stage"];
                var cfg = per.Get(stageId) as Bag ?? (Bag)per[per.Keys[0]];
                var seq = new List<object>();
                for (int i = 0; i < J.I(cfg, "length"); i++) seq.Add((int)(rng.Randi() % (uint)J.I(cfg, "buttons")));
                room.Set("puzzle_id", pid);
                room.Set("sequence", seq);
                room.Set("buttons", J.I(cfg, "buttons"));
                room.Set("mistakes", J.I(cfg, "mistakes"));
            }
            return room;
        }

        static bool StageHas(Bag def, string stageId)
        {
            foreach (var s in J.Arr(def, "stages")) if (J.S(s) == stageId) return true;
            return false;
        }

        static List<object> CloneList(List<object> src)
        {
            var list = new List<object>();
            foreach (var s in src) list.Add(s);
            return list;
        }
    }
}
