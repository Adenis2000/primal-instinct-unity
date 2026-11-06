using System;
using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    public sealed class Reach
    {
        public readonly Dictionary<V2, int> Cost = new Dictionary<V2, int>();
        public readonly Dictionary<V2, V2> Prev = new Dictionary<V2, V2>();
    }

    public sealed class BGrid
    {
        public const int DefaultW = 12;
        public const int DefaultH = 7;
        public static readonly V2[] Dirs = { new V2(1, 0), new V2(-1, 0), new V2(0, 1), new V2(0, -1) };

        public int W;
        public int H;
        public string Theme = "jungle";
        readonly string[,] _tiles;
        public readonly int[,] Variant;

        public BGrid(int w = DefaultW, int h = DefaultH)
        {
            W = w;
            H = h;
            _tiles = new string[h, w];
            Variant = new int[h, w];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    _tiles[y, x] = "ground";
        }

        public int CountTiles(string id)
        {
            int n = 0;
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                    if (_tiles[y, x] == id) n++;
            return n;
        }

        public bool InBounds(V2 p) => p.X >= 0 && p.Y >= 0 && p.X < W && p.Y < H;
        public string GetTile(V2 p) => _tiles[p.Y, p.X];
        public void SetTile(V2 p, string t) => _tiles[p.Y, p.X] = t;
        public Bag Tdef(V2 p) => Db.Tile(GetTile(p));
        public bool BlocksMove(V2 p) => J.B(Tdef(p), "blocks_move");
        public bool BlocksSight(V2 p) => J.B(Tdef(p), "blocks_sight");
        public bool IsVoid(V2 p) => GetTile(p) == "void";
        public bool IsGrass(V2 p) => GetTile(p) == "grass";
        public float Evasion(V2 p) => J.F(Tdef(p), "evasion", 0f);
        public float DetectMod(V2 p) => J.F(Tdef(p), "detect_mod", 1f);

        public int MoveCost(V2 p, Dictionary<string, int> costs)
        {
            string t = GetTile(p);
            int baseCost = J.I(Tdef(p), "move_cost", 1);
            if (costs != null && costs.TryGetValue(t, out int over) && !BlocksMove(p))
                return Math.Max(1, over);
            return baseCost;
        }

        public List<V2> Neighbors(V2 p)
        {
            var outList = new List<V2>(4);
            foreach (var d in Dirs)
            {
                var q = p + d;
                if (InBounds(q)) outList.Add(q);
            }
            return outList;
        }

        public bool Los(V2 a, V2 b)
        {
            int x0 = a.X, y0 = a.Y;
            int dx = Math.Abs(b.X - a.X), dy = Math.Abs(b.Y - a.Y);
            int sx = a.X < b.X ? 1 : -1, sy = a.Y < b.Y ? 1 : -1;
            int err = dx - dy;
            while (true)
            {
                if (x0 == b.X && y0 == b.Y) return true;
                if (!(x0 == a.X && y0 == a.Y) && BlocksSight(new V2(x0, y0))) return false;
                int e2 = 2 * err;
                if (e2 > -dy) { err -= dy; x0 += sx; }
                if (e2 < dx) { err += dx; y0 += sy; }
            }
        }

        public Reach ReachTiles(V2 start, int maxCost, Dictionary<V2, object> occupied, Dictionary<string, int> costs)
        {
            var reach = new Reach();
            reach.Cost[start] = 0;
            var open = new List<V2> { start };
            while (open.Count > 0)
            {
                int bestI = 0;
                for (int i = 1; i < open.Count; i++)
                    if (reach.Cost[open[i]] < reach.Cost[open[bestI]]) bestI = i;
                var cur = open[bestI];
                open.RemoveAt(bestI);
                foreach (var n in Neighbors(cur))
                {
                    if (BlocksMove(n) || (occupied != null && occupied.ContainsKey(n))) continue;
                    int c = reach.Cost[cur] + MoveCost(n, costs);
                    if (c > maxCost) continue;
                    if (!reach.Cost.TryGetValue(n, out int prev) || c < prev)
                    {
                        reach.Cost[n] = c;
                        reach.Prev[n] = cur;
                        if (!open.Contains(n)) open.Add(n);
                    }
                }
            }
            return reach;
        }

        public static List<V2> PathFrom(Dictionary<V2, V2> prev, V2 start, V2 target)
        {
            var path = new List<V2>();
            var cur = target;
            while (cur != start)
            {
                path.Insert(0, cur);
                if (!prev.TryGetValue(cur, out var back)) return new List<V2>();
                cur = back;
            }
            return path;
        }

        public static BGrid Generate(int seedVal, Bag terrain, string themeId, Bag spec)
        {
            int w = spec != null && spec.Has("w") ? J.I(spec, "w") : DefaultW;
            int h = spec != null && spec.Has("h") ? J.I(spec, "h") : DefaultH;
            var g = new BGrid(w, h) { Theme = themeId };
            float areaK = (g.W * g.H) / J.F(Db.Table("arenas"), "ref_area", 84f);
            var rng = new Rng();
            rng.SetSeed(seedVal);
            for (int y = 0; y < g.H; y++)
                for (int x = 0; x < g.W; x++)
                    g.Variant[y, x] = (int)(rng.Randi() % 4);
            Blobs(g, rng, "grass", Scaled(ArrOr(terrain, "grass_blobs", 3, 5), areaK), ArrOr(terrain, "grass_size", 3, 7));
            Blobs(g, rng, "water", Scaled(ArrOr(terrain, "water_blobs", 0, 2), areaK), ArrOr(terrain, "water_size", 3, 6));
            var oc = Scaled(ArrOr(terrain, "obstacles", 4, 8), areaK);
            int nObs = rng.RandiRange(oc[0], oc[1]);
            for (int i = 0; i < nObs; i++)
            {
                var p = new V2(rng.RandiRange(2, g.W - 3), rng.RandiRange(0, g.H - 1));
                g.SetTile(p, "obstacle");
                if (rng.Randf() < 0.45f)
                {
                    var d = Dirs[(int)(rng.Randi() % 4)];
                    var q = p + d;
                    if (g.InBounds(q) && q.X >= 2 && q.X <= g.W - 3) g.SetTile(q, "obstacle");
                }
            }
            for (int y = 0; y < g.H; y++)
            {
                int[] xs = { 0, 1, g.W - 2, g.W - 1 };
                foreach (int x in xs)
                    if (g.GetTile(new V2(x, y)) == "obstacle") g.SetTile(new V2(x, y), "ground");
            }
            if (spec != null && spec.Count > 0 && J.S(spec, "shape", "rect") != "rect")
            {
                for (int y = 0; y < g.H; y++)
                    for (int x = 0; x < g.W; x++)
                        if (ArenaGen.IsVoid(spec, x, y)) g.SetTile(new V2(x, y), "void");
            }
            g.FillPockets();
            return g;
        }

        static int[] ArrOr(Bag b, string key, int a, int c)
        {
            var list = J.Arr(b, key);
            if (list.Count >= 2) return new[] { J.I(list[0]), J.I(list[1]) };
            return new[] { a, c };
        }

        static int[] Scaled(int[] r, float k)
        {
            int a = J.Round(r[0] * k);
            int c = J.Round(r[1] * k);
            return new[] { a, Math.Max(a, c) };
        }

        static void Blobs(BGrid g, Rng rng, string tile, int[] countR, int[] sizeR)
        {
            int n = rng.RandiRange(countR[0], countR[1]);
            for (int i = 0; i < n; i++)
            {
                var cur = new V2(rng.RandiRange(0, g.W - 1), rng.RandiRange(0, g.H - 1));
                int size = rng.RandiRange(sizeR[0], sizeR[1]);
                var cells = new List<V2> { cur };
                g.SetTile(cur, tile);
                for (int s = 0; s < size - 1; s++)
                {
                    var basis = cells[(int)(rng.Randi() % (uint)cells.Count)];
                    var q = basis + Dirs[(int)(rng.Randi() % 4)];
                    if (g.InBounds(q))
                    {
                        g.SetTile(q, tile);
                        cells.Add(q);
                    }
                }
            }
        }

        void FillPockets()
        {
            var seen = new HashSet<V2>();
            var queue = new List<V2>();
            for (int y = 0; y < H; y++)
            {
                var p = new V2(0, y);
                if (!BlocksMove(p)) { seen.Add(p); queue.Add(p); }
            }
            if (queue.Count == 0)
            {
                for (int y = 0; y < H && queue.Count == 0; y++)
                    for (int x = 0; x < W && queue.Count == 0; x++)
                    {
                        var p = new V2(x, y);
                        if (!BlocksMove(p)) { seen.Add(p); queue.Add(p); }
                    }
            }
            while (queue.Count > 0)
            {
                var cur = queue[queue.Count - 1];
                queue.RemoveAt(queue.Count - 1);
                foreach (var n in Neighbors(cur))
                    if (!BlocksMove(n) && seen.Add(n)) queue.Add(n);
            }
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    var p = new V2(x, y);
                    if (!BlocksMove(p) && !seen.Contains(p)) SetTile(p, "obstacle");
                }
        }

        public List<V2> FreeTiles(Dictionary<V2, object> avoid, int xMin, int xMax, bool allowWater = false)
        {
            var outList = new List<V2>();
            xMax = Math.Min(xMax, W - 1);
            for (int y = 0; y < H; y++)
                for (int x = xMin; x <= xMax; x++)
                {
                    var p = new V2(x, y);
                    if (BlocksMove(p) || (avoid != null && avoid.ContainsKey(p))) continue;
                    if (!allowWater && GetTile(p) == "water") continue;
                    outList.Add(p);
                }
            return outList;
        }
    }
}
