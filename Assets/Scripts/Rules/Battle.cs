using System;
using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    public sealed partial class Battle
    {
        public const float MeterMax = 100f;
        public const int NoiseRadius = 3;
        public static readonly V2[] Dirs4 = { new V2(1, 0), new V2(0, 1), new V2(-1, 0), new V2(0, -1) };
        public const int SearchScanTurns = 2;
        public const float TrackMult = 1.5f;
        public const int ScentRange = 8;
        public const int RoamRadius = 3;
        public const int RoamStep = 2;
        public const int AmbushRange = 24;
        public const int MarkBonus = 3;
        public const float DazeDamage = 0.5f;
        public const int PoisonDmg = 2;
        public const int WebSlow = 2;
        public const int ExploreMp = 12;
        public static bool PendingUnlock;

        public RunState Run;
        public BGrid Grid;
        public Rng Rng = new Rng();
        public Rng EvadeRng = new Rng();
        public bool LastDodged;
        public Bag ArenaSpec = new Bag();
        public string WeatherId = "";
        public Bag Room = new Bag();
        public string Mode = "spotted";
        public BUnit Player;
        public List<BUnit> Units = new List<BUnit>();
        public List<BUnit> Enemies = new List<BUnit>();
        public string Phase = "setup";
        public int TurnNo;
        public BUnit Current;
        public List<string> DrawPile = new List<string>();
        public List<string> Hand = new List<string>();
        public List<string> DiscardPile = new List<string>();
        public List<string> Exhausted = new List<string>();
        public int Stamina, StaminaMax, Mp, MpMax;
        public List<Bag> Events = new List<Bag>();
        public List<Bag> Killed = new List<Bag>();
        public List<string> Lines = new List<string>();
        public int Stalker;
        public bool Calm, CalmUsed;
        public bool StartedUnspotted;
        public int MovedTiles;
        public bool Quicken, Patient, WellFedOn, FreeDrawUsed;
        public int EvadeTemp;
        public Dictionary<string, bool> ItemsUsed = new Dictionary<string, bool>();
        public List<Bag> Exits = new List<Bag>();
        public V2 Secret = V2.None;
        public int SecretStep = -1;
        public bool SecretReveal;
        public bool ExitsLocked;
        public bool ExitsUnlockAnim;
        public int ExitsStep = -1;
        public int StageIdx;
        public string ThemeId = "jungle";
        int _uid;
        bool _alerted;

        public static Battle Create(RunState run, Bag room, string mode = "spotted")
        {
            var b = new Battle { Run = run, Room = room, Mode = mode };
            b.Setup();
            return b;
        }

        public static Battle CreateExplore(RunState run, Battle prev = null)
        {
            var b = new Battle { Run = run, Mode = "explore", StageIdx = run.StageIdx };
            b.SetupExplore(prev);
            return b;
        }

        public static Dictionary<string, int> ResolveTerrainCosts(List<string> tags, Bag def)
        {
            var result = new Dictionary<string, int>();
            var traits = J.Ob(Db.Table("tiles"), "traits") ?? new Bag();
            if (tags != null)
                foreach (var t in tags)
                    if (traits.Get(t) is Bag row)
                        foreach (var k in row.Keys)
                        {
                            int cost = J.I(row.Get(k));
                            if (result.TryGetValue(k, out int have)) result[k] = Math.Min(have, cost);
                            else result[k] = cost;
                        }
            var own = J.Ob(def, "terrain_cost");
            if (own != null)
                foreach (var k in own.Keys) result[k] = J.I(own.Get(k));
            return result;
        }

        public static float SneakChance(RunState run, Bag room)
        {
            var enemies = J.Arr(room, "enemies");
            string w = run.WeatherId();
            float chance = 0.75f + WeatherSys.ModsFor(w, run.Tags()).Sneak;
            float sum = 0f;
            foreach (var id in enemies)
            {
                var tags = new List<string>();
                foreach (var t in J.Arr(Db.Enemy(J.S(id)), "tags")) tags.Add(J.S(t));
                sum += WeatherSys.ModsFor(w, tags).Perception;
            }
            if (enemies.Count > 0)
            {
                float avg = sum / enemies.Count;
                chance -= 0.5f * (avg - 1f);
                chance -= 0.07f * (enemies.Count - 1);
            }
            return J.Clamp(chance, 0.1f, 0.95f);
        }

        void Setup()
        {
            var sdef = Run.StageDef();
            var terrain = J.Ob(sdef, "terrain") ?? new Bag();
            if (Room.Get("terrain") is Bag rt) terrain = rt;
            ThemeId = J.S(Room, "theme", J.S(Run.Stage, "theme", "jungle"));
            int rseed = J.I(Room, "seed", 1);
            ArenaSpec = ArenaGen.Pick(rseed, Room, Mode, Run.StageIdx);
            Grid = BGrid.Generate(RunState.Mix(rseed, 31), terrain, ThemeId, ArenaSpec);
            Rng.SetSeed(RunState.Mix(rseed, 77));
            EvadeRng.SetSeed(RunState.Mix(rseed, 505));
            WeatherId = Run.WeatherId();
            StartedUnspotted = Mode == "ambush";
            MakePlayer();
            var starts = Grid.FreeTiles(new Dictionary<V2, object>(), 0, 1);
            if (starts.Count == 0) starts = Grid.FreeTiles(new Dictionary<V2, object>(), 0, Grid.W / 2);
            Player.Pos = starts[(int)(Rng.Randi() % (uint)starts.Count)];
            Units.Add(Player);
            PlaceFightExits();
            RollSecret(sdef);
            var occupied = new Dictionary<V2, object> { { Player.Pos, Player } };
            if (Secret != V2.None) occupied[Secret] = null;
            foreach (var ex in Exits) occupied[(V2)ex["pos"]] = null;
            var ids = new List<string>();
            foreach (var id in J.Arr(Room, "enemies")) ids.Add(J.S(id));
            var flags = new List<bool>();
            foreach (var f in J.Arr(Room, "infected")) flags.Add(J.B(f));
            if (Run != null && ids.Count > 0 && ids.Count < 4)
            {
                var xr = new Rng();
                xr.SetSeed(RunState.Mix(rseed, 909));
                if (xr.Randf() < Difficulty.ExtraChance(Run, Room))
                {
                    ids.Add(ids[(int)(xr.Randi() % (uint)ids.Count)]);
                    flags.Add(false);
                }
            }
            var walkable = Grid.ReachTiles(Player.Pos, 99, occupied, null).Cost;
            for (int i = 0; i < ids.Count; i++)
            {
                var u = MakeEnemy(ids[i]);
                var cands = Grid.FreeTiles(occupied, Grid.W / 2, Grid.W - 1).FindAll(p => walkable.ContainsKey(p));
                var far = cands.FindAll(p => V2.Dist(p, Player.Pos) >= 5);
                if (far.Count == 0) far = cands;
                if (far.Count == 0) far = Grid.FreeTiles(occupied, 2, Grid.W - 1, true).FindAll(p => walkable.ContainsKey(p));
                if (far.Count == 0) far = Grid.FreeTiles(occupied, 2, Grid.W - 1, true);
                u.Pos = far[(int)(Rng.Randi() % (uint)far.Count)];
                u.Home = u.Pos;
                occupied[u.Pos] = u;
                u.Aware = Mode != "ambush";
                if (i < flags.Count && flags[i] && !J.B(u.Def, "infected")) InfectUnit(u, true);
                Units.Add(u);
                Enemies.Add(u);
            }
            foreach (var e in Enemies)
            {
                e.Facing = Dirs4[(int)(Rng.Randi() % 4)];
                if (e.Aware) e.Facing = DirToward(e.Pos, Player.Pos, e.Facing);
            }
            if (Enemies.Count > 0)
            {
                var nearest = Enemies[0];
                foreach (var e in Enemies)
                    if (V2.Dist(e.Pos, Player.Pos) < V2.Dist(nearest.Pos, Player.Pos)) nearest = e;
                Player.Facing = DirToward(Player.Pos, nearest.Pos, Player.Facing);
            }
            DrawPile = new List<string>(Run.Deck);
            Shuffle(DrawPile);
            if (WeatherId != "") Log(Db.Weather(WeatherId) != null ? "Weather: " + J.S(Db.Weather(WeatherId), "name") + "." : "Battle begins.");
            else Log("Battle begins.");
            if (Mode == "ambush")
            {
                Phase = "ambush";
                Mp = EffMove(Player);
                MpMax = Mp;
                Log("They have not noticed you. Move closer and strike first - or slip away through an exit.");
            }
            else Phase = "enemy";
        }

        void PlaceFightExits()
        {
            Exits = new List<Bag>();
            ExitsLocked = false;
            string t = J.S(Room, "type");
            if (t == "cave" || t == "explore" || t == "event" || J.B(Room, "event_battle")) return;
            var steps = (List<object>)Run.Stage["steps"];
            int nxt = J.I(Run.Stage, "step") + 1;
            if (nxt >= steps.Count) return;
            var doors = (List<object>)((Bag)steps[nxt])["doors"];
            var xr = new Rng();
            xr.SetSeed(RunState.Mix(J.I(Room, "seed", 1), 1313));
            var places = ExitGen.PlaceExits(Grid, doors.Count, xr, Player.Pos);
            for (int i = 0; i < places.Count; i++)
            {
                var row = places[i].Clone();
                row.Set("door", i);
                row.Set("type", J.S((Bag)doors[i], "type"));
                Exits.Add(row);
            }
            ExitsLocked = Exits.Count > 0;
            ExitsStep = nxt;
        }

        void RollSecret(Bag sdef)
        {
            Secret = V2.None;
            SecretStep = J.I(Run.Stage, "step");
            var sec = J.Ob(sdef, "secret");
            string t = J.S(Room, "type");
            if (sec == null || sec.Count == 0 || (t != "battle" && t != "elite") || J.B(Room, "event_battle")) return;
            if (SecretStep >= ((List<object>)Run.Stage["steps"]).Count - 1) return;
            var srng = new Rng();
            srng.SetSeed(RunState.Mix(J.I(Room, "seed", 1), 909));
            if (srng.Randf() < J.F(sec, "chance"))
            {
                var avoid = new List<V2>();
                foreach (var e in Exits) avoid.Add((V2)e["pos"]);
                Secret = ExitGen.PlaceSecret(Grid, srng, Player.Pos, avoid);
            }
        }

        void MakePlayer()
        {
            Player = new BUnit();
            Player.Uid = NextUid();
            Player.Id = Run.SpeciesId;
            Player.DisplayName = J.S(Run.Species, "name");
            Player.IsPlayer = true;
            Player.Tags = Run.Tags();
            Player.MaxHp = Run.MaxHp();
            Player.Hp = Run.Hp;
            Player.BaseSpeed = Run.BaseSpeed();
            Player.Move = Run.BaseMove();
            Player.SpriteId = Run.FormSpriteId();
            Player.SpritePx = J.I(Run.Form(), "sprite_px", 16);
            Player.Aware = true;
            Player.Def = new Bag();
            Player.Def.Set("facing", J.Ob(Run.Species, "facing") ?? new Bag());
            Player.Def.Set("terrain_cost", J.Ob(Run.Species, "terrain_cost") ?? new Bag());
            Player.TerrainCosts = ResolveTerrainCosts(Player.Tags, Player.Def);
            int wc = Run.ItemBonus("water_cost");
            if (wc > 0)
            {
                int cur = Player.TerrainCosts.TryGetValue("water", out int have) ? have : J.I((Bag)Db.Table("tiles")["water"], "move_cost");
                Player.TerrainCosts["water"] = Math.Max(1, cur - wc);
            }
            if (Run.Spores > 0) Player.Status["spores"] = Run.Spores;
        }

        void SetupExplore(Battle prev)
        {
            var sdef = Run.StageDef();
            int step = J.I(Run.Stage, "step");
            int eseed = RunState.Mix(RunState.Mix(Run.SeedVal, 5000 + Run.StageIdx), step + 1);
            Room = new Bag();
            Room.Set("type", "explore");
            Room.Set("seed", eseed);
            Room.Set("step", step);
            ThemeId = J.S(Run.Stage, "theme", "jungle");
            Rng.SetSeed(RunState.Mix(eseed, 77));
            WeatherId = Run.WeatherId();
            bool keep = prev != null && prev.Grid != null && prev.StageIdx == Run.StageIdx && J.S(prev.Room, "type") != "cave";
            if (keep) { Grid = prev.Grid; ArenaSpec = prev.ArenaSpec; }
            else
            {
                ArenaSpec = ArenaGen.Pick(eseed, Room, "spotted", Run.StageIdx);
                Grid = BGrid.Generate(RunState.Mix(eseed, 31), J.Ob(sdef, "terrain") ?? new Bag(), ThemeId, ArenaSpec);
            }
            MakePlayer();
            if (keep && prev.Player != null && Grid.InBounds(prev.Player.Pos) && !Grid.BlocksMove(prev.Player.Pos))
            {
                Player.Pos = prev.Player.Pos;
                Player.Facing = prev.Player.Facing;
            }
            else
            {
                var starts = Grid.FreeTiles(new Dictionary<V2, object>(), Grid.W / 4, Grid.W * 2 / 3);
                if (starts.Count == 0) starts = Grid.FreeTiles(new Dictionary<V2, object>(), 0, Grid.W - 1);
                Player.Pos = starts[(int)(Rng.Randi() % (uint)starts.Count)];
            }
            Units.Add(Player);
            var doors = Run.CurrentStepDoors();
            ExitsStep = step;
            bool reuse = keep && prev.Exits.Count > 0 && prev.ExitsStep == step && prev.Exits.Count == doors.Count;
            ExitsUnlockAnim = (prev != null && prev.ExitsLocked) || PendingUnlock;
            PendingUnlock = false;
            if (reuse) foreach (var e in prev.Exits) Exits.Add(e.Clone());
            else
            {
                var places = ExitGen.PlaceExits(Grid, doors.Count, Rng, Player.Pos);
                for (int i = 0; i < places.Count; i++)
                {
                    var row = places[i].Clone();
                    row.Set("door", i);
                    row.Set("type", J.S(doors[i], "type"));
                    Exits.Add(row);
                }
            }
            Secret = V2.None;
            SecretStep = step;
            if (keep && prev.Secret != V2.None && J.I(Run.Stage, "secret_used_step", -1) != step)
            {
                bool okStep = prev.Mode == "explore" ? prev.SecretStep == step : prev.SecretStep == step - 1;
                if (okStep && !Grid.BlocksMove(prev.Secret) && prev.Secret != Player.Pos)
                {
                    Secret = prev.Secret;
                    SecretReveal = prev.Mode != "explore" || prev.SecretReveal;
                }
            }
            MpMax = ExploreMp;
            Mp = MpMax;
            Phase = "explore";
        }

        public int ExitAt(V2 p)
        {
            for (int i = 0; i < Exits.Count; i++)
                if ((V2)Exits[i]["pos"] == p) return i;
            return -1;
        }

        int NextUid() => ++_uid;

        BUnit MakeEnemy(string id)
        {
            var d = Db.Enemy(id);
            var u = new BUnit();
            u.Uid = NextUid();
            u.Id = id;
            u.Def = d;
            u.DisplayName = J.S(d, "name");
            foreach (var t in J.Arr(d, "tags")) u.Tags.Add(J.S(t));
            u.MaxHp = J.I(d, "hp");
            u.Hp = u.MaxHp;
            u.BaseSpeed = J.F(d, "speed");
            u.Move = J.I(d, "move");
            u.Perception = J.F(d, "perception");
            foreach (var a in J.Arr(d, "abilities")) u.Abilities.Add(((Bag)a).Clone());
            u.SpriteId = J.S(d, "sprite");
            u.SpritePx = 16;
            var sd = Db.SpriteDef(u.SpriteId);
            if (sd.Count > 0) u.SpritePx = J.I(sd, "size", 16);
            u.Infected = J.B(d, "infected");
            u.ImmuneToInfection = J.B(d, "immune");
            u.Spreader = J.B(d, "spreader");
            u.SpreadCd = 2;
            u.TerrainCosts = ResolveTerrainCosts(u.Tags, d);
            u.Armor = J.I(d, "armor");
            if (Run != null && !d.Has("fixed_stats") && !id.StartsWith("_"))
            {
                u.MaxHp = Math.Max(1, J.Round(u.MaxHp * Difficulty.HpMult(Run, Room)));
                u.Hp = u.MaxHp;
                u.BonusDamage = Difficulty.DmgAdd(Run, Room);
            }
            return u;
        }

        public void InfectUnit(BUnit u, bool silent = false)
        {
            if (u.Infected || u.ImmuneToInfection || u.IsPlayer) return;
            var cfg = Db.Enemy("_infection");
            u.Infected = true;
            int newMax = J.Round(u.MaxHp * J.F(cfg, "hp_mult"));
            u.Hp += newMax - u.MaxHp;
            u.MaxHp = newMax;
            u.BonusDamage += J.I(cfg, "damage_bonus");
            u.Abilities.Add(((Bag)cfg["extra_ability"]).Clone());
            u.DisplayName = "Infected " + u.DisplayName;
            u.SpreadCd = J.I(cfg, "spread_every");
            if (!silent)
            {
                Ev("infect", "unit", u.Uid, "hp_after", u.Hp);
                Popup(u, "INFECTED", "#8dff6a");
                Log(u.DisplayName + " is overtaken by the parasite!");
            }
        }

        void Shuffle(List<string> a)
        {
            for (int i = a.Count - 1; i > 0; i--)
            {
                int j = Rng.RandiRange(0, i);
                (a[i], a[j]) = (a[j], a[i]);
            }
        }

        public void Ev(Bag d) => Events.Add(d);
        public void Ev(string t, params object[] kv)
        {
            var b = new Bag();
            b.Set("t", t);
            for (int i = 0; i + 1 < kv.Length; i += 2) b.Set(kv[i].ToString(), kv[i + 1]);
            Events.Add(b);
        }
        public void Log(string text) { Lines.Add(text); Ev("log", "text", text); }
        void Popup(BUnit u, string text, string color) => Ev("popup", "unit", u.Uid, "text", text, "color", color);

        public BUnit UnitByUid(int uid)
        {
            foreach (var u in Units) if (u.Uid == uid) return u;
            return null;
        }
        public List<BUnit> AliveEnemies()
        {
            var list = new List<BUnit>();
            foreach (var u in Enemies) if (u.Alive) list.Add(u);
            return list;
        }
        Dictionary<V2, object> Occupied(BUnit except = null)
        {
            var o = new Dictionary<V2, object>();
            foreach (var u in Units)
                if (u.Alive && u != except) o[u.Pos] = u;
            return o;
        }
        public bool ExitsSealed() => ExitsLocked && Phase != "ambush";
        public bool ExitsVisible() => Exits.Count > 0 && !ExitsSealed();

        public WeatherMods Wm(BUnit u)
        {
            var m = WeatherSys.ModsFor(WeatherId, u.Tags);
            if (u.IsPlayer && Run != null && Run.ItemBonus("weather_resist") > 0)
            {
                m.Speed = MathF.Max(1f, m.Speed);
                m.Damage = MathF.Max(1f, m.Damage);
                m.StaminaDelta = Math.Max(0, m.StaminaDelta);
                m.HungerExtra = Math.Min(0, m.HungerExtra);
                m.Perception = MathF.Min(1f, m.Perception);
            }
            return m;
        }

        public float EffSpeed(BUnit u)
        {
            float s = (u.BaseSpeed + u.SpeedBonus) * Wm(u).Speed;
            if (u.IsPlayer)
            {
                string hs = Run.HungerState();
                var cfg = J.Ob(Db.Growth(), "hunger");
                if (hs == "low") s *= J.F(cfg, "low_speed_mult");
                else if (hs == "starving") s *= J.F(cfg, "starve_speed_mult");
            }
            return MathF.Max(1f, s);
        }

        public bool IsHidden()
        {
            foreach (var e in Enemies) if (e.Alive && e.Aware) return false;
            return true;
        }

        BUnit NextActor()
        {
            BUnit best = null;
            float bestT = float.PositiveInfinity;
            foreach (var u in Units)
            {
                if (!u.Alive) continue;
                float t = MathF.Max(0f, (MeterMax - u.Meter) / EffSpeed(u));
                if (best == null || t < bestT - 0.0001f || (MathF.Abs(t - bestT) <= 0.0001f && u.IsPlayer && !best.IsPlayer))
                { best = u; bestT = t; }
            }
            foreach (var u in Units)
                if (u.Alive) u.Meter += bestT * EffSpeed(u);
            best.Meter -= MeterMax;
            return best;
        }

        public List<BUnit> PreviewOrder(int n)
        {
            var meters = new Dictionary<BUnit, float>();
            foreach (var u in Units) if (u.Alive) meters[u] = u.Meter;
            var order = new List<BUnit>();
            for (int i = 0; i < n; i++)
            {
                BUnit best = null;
                float bestT = float.PositiveInfinity;
                foreach (var u in meters.Keys)
                {
                    float t = MathF.Max(0f, (MeterMax - meters[u]) / EffSpeed(u));
                    if (best == null || t < bestT - 0.0001f || (MathF.Abs(t - bestT) <= 0.0001f && u.IsPlayer && !best.IsPlayer))
                    { best = u; bestT = t; }
                }
                if (best == null) break;
                var keys = new List<BUnit>(meters.Keys);
                foreach (var u in keys) meters[u] += bestT * EffSpeed(u);
                meters[best] -= MeterMax;
                order.Add(best);
            }
            return order;
        }

        public void Begin()
        {
            if (Phase == "ambush") return;
            if (!_alerted)
            {
                _alerted = true;
                foreach (var e in Enemies)
                    if (e.Alive && e.Aware) Ev("spot", "unit", e.Uid);
            }
            RunTurns();
        }

        public List<BUnit> AmbushTargets()
        {
            var list = new List<BUnit>();
            if (Phase != "ambush") return list;
            foreach (var e in AliveEnemies())
                if (V2.Dist(Player.Pos, e.Pos) <= AmbushRange && LandingTile(e, AmbushRange) != V2.None)
                    list.Add(e);
            return list;
        }

        public bool AmbushStrike(BUnit target)
        {
            if (Phase != "ambush" || !AliveEnemies().Contains(target)) return false;
            int baseD = 4 + 2 * (Run.Tier() - 1);
            var land = LandingTile(target, AmbushRange);
            if (land == V2.None) return false;
            Leap(Player, land, false, "pounce");
            Log("Ambush! You pounce on " + target.DisplayName + ".");
            FacePos(Player, target.Pos);
            string fdir = FacingDir(Player.Pos, target);
            int ibonus = Run.ItemBonus("unaware_damage") + Run.ItemBonus("ambush_bonus") + (fdir == "back" ? Run.ItemBonus("back_damage") : 0);
            int dmg = CalcDamage(Player, target, baseD * 2 + Stalker + ibonus, FacingMult(Player.Pos, target, null));
            if (fdir != "front")
                Popup(target, J.S(J.Ob(Db.Facing(), "labels"), fdir) + " hit x" + Snap(FacingMult(Player.Pos, target, null)), fdir == "back" ? "#7dff8a" : "#ffd24a");
            Run.Bump("ambushes");
            Hit(target, dmg, Player, silentIfKill: true);
            if (Player.Alive && !CheckEnd()) DetectAll();
            FinishAmbush();
            return true;
        }

        public void SkipAmbush() { if (Phase == "ambush") FinishAmbush(); }
        void FinishAmbush()
        {
            Phase = "enemy";
            if (!CheckEnd()) RunTurns();
        }

        void RunTurns()
        {
            for (int guard = 0; guard < 600; guard++)
            {
                if (CheckEnd()) return;
                var a = NextActor();
                Current = a;
                a.TurnsTaken++;
                Ev("turn", "unit", a.Uid);
                TickStart(a);
                if (!a.Alive) continue;
                if (a.IsPlayer)
                {
                    BeginPlayerTurn();
                    Phase = "player";
                    return;
                }
                if (a.St("stun") > 0)
                {
                    CancelWindup(a, false);
                    Popup(a, "STUNNED", "#ffe060");
                }
                else EnemyAct(a);
                TickEnd(a);
            }
        }

        public int EffMove(BUnit u)
        {
            int m = u.Move;
            if (u.St("web") > 0) m = Math.Max(1, m - WebSlow);
            if (u.St("daze") > 0) m = Math.Max(1, m / 2);
            return m;
        }

        void TickStart(BUnit u)
        {
            u.Block = u.IsPlayer ? Run.ItemBonus("turn_block") : 0;
            u.TurnsLeft = u.SlowTurn() ? 1 : 99;
            int bl = u.St("bleed");
            if (bl > 0) { u.Status["bleed"] = bl - 1; RawDamage(u, bl, "bleed"); if (!u.Alive) return; }
            int po = u.St("poison");
            if (po > 0) { u.Status["poison"] = po - 1; RawDamage(u, PoisonDmg, "poison"); if (!u.Alive) return; }
            int sp = u.St("spores");
            if (sp > 0) { u.Status["spores"] = sp - 1; RawDamage(u, 1, "spores"); if (!u.Alive) return; }
            if (!u.IsPlayer && u.Infected && u.Alive)
            {
                u.SpreadCd--;
                if (u.SpreadCd <= 0)
                {
                    var cfg = Db.Enemy("_infection");
                    BUnit best = null;
                    foreach (var o in AliveEnemies())
                        if (o != u && !o.Infected && !o.ImmuneToInfection && V2.Dist(o.Pos, u.Pos) <= J.I(cfg, "spread_range"))
                            if (best == null || V2.Dist(o.Pos, u.Pos) < V2.Dist(best.Pos, u.Pos)) best = o;
                    u.SpreadCd = J.I(cfg, "spread_every");
                    if (best != null) InfectUnit(best);
                }
            }
        }

        void TickEnd(BUnit u)
        {
            foreach (var k in new[] { "weak", "expose", "stun", "web", "daze", "fear", "mark" })
                if (u.St(k) > 0) u.Status[k] = u.St(k) - 1;
        }

        void RawDamage(BUnit u, int amount, string why)
        {
            u.Hp -= amount;
            Ev("damage", "unit", u.Uid, "amount", amount, "blocked", 0, "hp_after", Math.Max(u.Hp, 0), "why", why);
            if (u.Hp <= 0) Kill(u);
        }

        void BeginPlayerTurn()
        {
            TurnNo++;
            string hs = Run.HungerState();
            var cfg = J.Ob(Db.Growth(), "hunger");
            StaminaMax = Run.BaseStamina() + Wm(Player).StaminaDelta;
            if (hs != "ok") StaminaMax -= J.I(cfg, "low_stamina_penalty");
            StaminaMax = Math.Max(1, StaminaMax);
            Stamina = StaminaMax;
            Mp = EffMove(Player);
            MpMax = Mp;
            CalmUsed = false;
            MovedTiles = 0;
            FreeDrawUsed = false;
            EvadeTemp = 0;
            int extra = 0;
            if (Patient && IsHidden())
            {
                Stamina++;
                extra = 1;
                Popup(Player, "Patient: +1 stamina, +1 card", "#8fd070");
            }
            if (WellFedOn && Run.DietTier() >= 2)
            {
                Stamina++;
                Popup(Player, "Well-Fed: +1 stamina", "#e0a050");
            }
            if (Grid.GetTile(Player.Pos) == "water" && Player.St("spores") > 0)
            {
                Player.Status["spores"] = 0;
                Popup(Player, "Spores washed off", "#8fc8f0");
            }
            Draw(Run.HandSize() + extra);
            Ev("player_turn");
        }

        void Draw(int n)
        {
            for (int i = 0; i < n; i++)
            {
                if (DrawPile.Count == 0)
                {
                    if (DiscardPile.Count == 0) return;
                    DrawPile = DiscardPile;
                    DiscardPile = new List<string>();
                    Shuffle(DrawPile);
                }
                Hand.Add(DrawPile[DrawPile.Count - 1]);
                DrawPile.RemoveAt(DrawPile.Count - 1);
            }
        }

        public void EndPlayerTurn()
        {
            if (Phase != "player") return;
            DiscardPile.AddRange(Hand);
            Hand.Clear();
            TickEnd(Player);
            Phase = "enemy";
            Ev("player_turn_end");
            RunTurns();
        }

        public Bag CardAt(int i) => Db.Card(Hand[i]);
        public int CardCost(int i) => J.I(CardAt(i), "cost");
        static bool HasOp(Bag card, string op)
        {
            foreach (var e in J.Arr(card, "effects"))
                if (J.S((Bag)e, "op") == op) return true;
            return false;
        }

        public List<object> CardTargets(int i)
        {
            var c = CardAt(i);
            var list = new List<object>();
            string target = J.S(c, "target");
            if (target == "enemy")
            {
                int r = J.I(c, "range", 1);
                int minr = J.I(c, "min_range");
                bool pounce = HasOp(c, "pounce");
                foreach (var e in AliveEnemies())
                {
                    int d = V2.Dist(Player.Pos, e.Pos);
                    if (d > r || d < minr) continue;
                    if (pounce) { if (LandingTile(e, r) != V2.None) list.Add(e); }
                    else if (r == 1 || Grid.Los(Player.Pos, e.Pos)) list.Add(e);
                }
            }
            else if (target == "tile")
            {
                if (J.I(c, "min_enemy_dist") > 0 && EnemyWithin(J.I(c, "min_enemy_dist") - 1)) return list;
                int r = J.I(c, "range", 3);
                var res = Grid.ReachTiles(Player.Pos, r, Occupied(Player), Player.TerrainCosts);
                string filt = J.S(c, "tile_filter");
                foreach (var p in res.Cost.Keys)
                    if (filt == "" || Grid.GetTile(p) == filt) list.Add(p);
            }
            return list;
        }

        bool EnemyWithin(int d)
        {
            foreach (var e in AliveEnemies()) if (V2.Dist(Player.Pos, e.Pos) <= d) return true;
            return false;
        }

        public string UnplayableReason(int i)
        {
            if (Phase != "player" || i < 0 || i >= Hand.Count) return "";
            var c = CardAt(i);
            if (CardCost(i) > Stamina) return "Not enough stamina.";
            string t = J.S(c, "target");
            if ((t == "enemy" || t == "tile") && CardTargets(i).Count == 0)
            {
                int minr = J.I(c, "min_range");
                if (minr > 0 && EnemyWithin(minr - 1))
                    return "Too close: needs a target at least " + minr + " tiles away (no leaping at melee range).";
                if (J.I(c, "min_enemy_dist") > 0 && EnemyWithin(J.I(c, "min_enemy_dist") - 1))
                    return "An enemy is adjacent: you cannot dive away from melee range.";
                return "No valid target in range.";
            }
            if (HasOp(c, "damage_adjacent") && !EnemyWithin(1)) return "No enemy is adjacent.";
            return "";
        }

        public bool ItemUsable(string id) => Phase == "player" && Run.HasItem(id) && Db.Item(id).Has("use") && !ItemsUsed.ContainsKey(id);

        public bool UseItem(string id)
        {
            if (!ItemUsable(id)) return false;
            ItemsUsed[id] = true;
            var ctx = NewCtx(null, new Bag());
            ctx.WasHidden = IsHidden();
            foreach (var op in J.Arr(J.Ob(Db.Item(id), "use"), "ops")) ApplyOp((Bag)op, ctx);
            Popup(Player, J.S(Db.Item(id), "name") + ": " + J.S(J.Ob(Db.Item(id), "use"), "text"), "#f0c050");
            return true;
        }

        public bool CardPlayable(int i)
        {
            if (Phase != "player" || i < 0 || i >= Hand.Count) return false;
            if (CardCost(i) > Stamina) return false;
            string t = J.S(CardAt(i), "target");
            if (t == "enemy" || t == "tile") return CardTargets(i).Count > 0;
            if (HasOp(CardAt(i), "damage_adjacent") && !EnemyWithin(1)) return false;
            return true;
        }

        public bool PlayCard(int i, object target)
        {
            if (!CardPlayable(i)) return false;
            var c = CardAt(i);
            string t = J.S(c, "target");
            var targets = CardTargets(i);
            if (t == "enemy")
            {
                if (!(target is BUnit bu) || !targets.Contains(bu)) return false;
            }
            else if (t == "tile")
            {
                if (!(target is V2 cell) || !ContainsCell(targets, cell)) return false;
            }
            Stamina -= J.I(c, "cost");
            string id = Hand[i];
            Hand.RemoveAt(i);
            var ctx = NewCtx(target, c);
            ctx.WasHidden = IsHidden();
            Ev("card_played", "id", id, "i", i);
            if (J.I(c, "cost") == 0)
            {
                if (Quicken) { Mp++; MpMax++; Popup(Player, "Quicken +1 move", "#7fd8f0"); }
                if (!FreeDrawUsed && Run.ItemBonus("free_draw") > 0)
                {
                    FreeDrawUsed = true;
                    Draw(Run.ItemBonus("free_draw"));
                    Popup(Player, "Tempo: +1 card", "#7fd8f0");
                }
            }
            foreach (var raw in J.Arr(c, "effects"))
            {
                ApplyOp((Bag)raw, ctx);
                if (CheckEnd()) break;
            }
            if (J.S(c, "type") == "attack" && ctx.Hit && ctx.WasHidden && Calm && !CalmUsed)
            {
                CalmUsed = true;
                Stamina++;
                Popup(Player, "+1 stamina (calm)", "#f0b030");
            }
            if (J.S(c, "type") == "power" || J.B(c, "exhaust")) Exhausted.Add(id);
            else DiscardPile.Add(id);
            if (!CheckEnd() && !HasOp(c, "hide")) DetectAll();
            return true;
        }

        static bool ContainsCell(List<object> targets, V2 cell)
        {
            foreach (var t in targets) if (t is V2 v && v == cell) return true;
            return false;
        }

        sealed class Ctx
        {
            public object Target;
            public bool WasHidden, Hit, Dodged;
            public Bag Card;
            public string Fdir = "";
        }

        static Ctx NewCtx(object target, Bag card) => new Ctx { Target = target, WasHidden = false, Card = card ?? new Bag() };

        // WasHidden is set by callers after construction when they know the battle. PlayCard sets it below.
    }
}
