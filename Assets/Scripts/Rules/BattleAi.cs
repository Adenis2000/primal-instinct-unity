using System;
using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    public sealed partial class Battle
    {
        void EnemyAct(BUnit e)
        {
            if (e.State == "idle")
            {
                Idle(e);
                if (e.Alive && CanDetect(e)) Spot(e);
                return;
            }
            if (e.State == "searching") { Search(e); return; }
            if (e.St("fear") > 0 && !e.IsBoss())
            {
                CancelWindup(e, false);
                Popup(e, "Flees in fear", "#d890ff");
                Flee(e, EffMove(e));
                return;
            }
            float rh = J.F(e.Def, "retreat_hp");
            if (rh > 0f && !e.Retreated && e.Hp <= e.MaxHp * rh && e.State == "spotted")
            {
                e.Retreated = true;
                e.BonusDamage += 1;
                CancelWindup(e, false);
                Popup(e, "Retreats!", "#ffd080");
                Log(e.DisplayName + " breaks off and retreats!");
                Flee(e, EffMove(e) + 1);
                return;
            }
            if (!TracksPlayer(e)) { LoseTrack(e); Search(e); return; }
            e.LastSeen = Player.Pos;
            FacePos(e, Player.Pos);
            var ab = e.NextAbility();
            if (ab.Count == 0) return;
            DoAbility(e, ab, 0);
        }

        Dictionary<V2, int> DistMap(V2 target, Dictionary<string, int> costs) =>
            Grid.ReachTiles(target, 99, new Dictionary<V2, object>(), costs).Cost;

        bool StepToward(BUnit e, V2 target, int budget, bool avoidWater = false)
        {
            var dm = DistMap(target, e.TerrainCosts);
            var res = Grid.ReachTiles(e.Pos, budget, Occupied(e), e.TerrainCosts);
            var best = e.Pos;
            int bestD = dm.TryGetValue(e.Pos, out int startD) ? startD : 999;
            int bestC = 0;
            foreach (var p in res.Cost.Keys)
            {
                if (avoidWater && Grid.GetTile(p) == "water") continue;
                int d = dm.TryGetValue(p, out int dd) ? dd : 999;
                int c = res.Cost[p];
                if (d < bestD || (d == bestD && best != e.Pos && c < bestC))
                { best = p; bestD = d; bestC = c; }
            }
            if (best == e.Pos) return false;
            MoveAlong(e, BGrid.PathFrom(res.Prev, e.Pos, best));
            return true;
        }

        void Search(BUnit e)
        {
            if (CanDetect(e)) { Spot(e, false); return; }
            if (e.SearchPhase == "go")
            {
                if (e.Pos != e.LastSeen)
                {
                    bool moved = StepToward(e, e.LastSeen, EffMove(e));
                    if (e.Alive && CanDetect(e)) { Spot(e, false); return; }
                    if (moved)
                    {
                        if (e.Pos == e.LastSeen) e.SearchPhase = "scan";
                        return;
                    }
                }
                e.SearchPhase = "scan";
            }
            int i = Array.IndexOf(Dirs4, e.Facing);
            int step = (SearchScanTurns - e.ScanLeft) % 2 == 0 ? 1 : -2;
            SetFacing(e, Dirs4[J.PosMod(i + step, 4)]);
            e.ScanLeft--;
            if (CanDetect(e)) { Spot(e, false); return; }
            if (e.ScanLeft <= 0)
            {
                e.State = "idle";
                e.RoamTarget = V2.None;
                Ev("give_up", "unit", e.Uid);
                Popup(e, "Hm.", "#c8c8c8");
                Log(e.DisplayName + " gives up the search.");
            }
        }

        void Idle(BUnit e)
        {
            if (e.Home == V2.None) e.Home = e.Pos;
            float roll = Rng.Randf();
            if (roll >= 0.55f)
            {
                if (roll < 0.80f)
                {
                    int i = Array.IndexOf(Dirs4, e.Facing);
                    SetFacing(e, Dirs4[J.PosMod(i + (Rng.Randf() < 0.5f ? 1 : -1), 4)]);
                }
                return;
            }
            bool far = V2.Dist(e.Pos, e.Home) > RoamRadius;
            if (far) e.RoamTarget = e.Home;
            else if (e.RoamTarget == V2.None || e.RoamTarget == e.Pos || Rng.Randf() < 0.2f)
            {
                var opts = new List<V2>();
                var occ = Occupied(e);
                for (int dx = -RoamRadius; dx <= RoamRadius; dx++)
                    for (int dy = -RoamRadius; dy <= RoamRadius; dy++)
                    {
                        var p = e.Home + new V2(dx, dy);
                        if (V2.Dist(p, e.Home) <= RoamRadius && Grid.InBounds(p) && !Grid.BlocksMove(p) && !occ.ContainsKey(p) && Grid.GetTile(p) != "water" && p != e.Pos)
                            opts.Add(p);
                    }
                e.RoamTarget = opts.Count > 0 ? opts[(int)(Rng.Randi() % (uint)opts.Count)] : e.Pos;
            }
            if (e.RoamTarget != e.Pos && !StepToward(e, e.RoamTarget, RoamStep, true))
                e.RoamTarget = V2.None;
        }

        bool InRange(BUnit e, Bag ab, V2 from)
        {
            int d = V2.Dist(from, Player.Pos);
            string kind = J.S(ab, "kind");
            if (kind == "aoe") return d <= J.I(ab, "radius", 1);
            if (kind == "attack" || kind == "infect")
            {
                int r = J.I(ab, "range", 1);
                if (d > r || d < J.I(ab, "min_range")) return false;
                return r <= 1 || J.B(ab, "leap") || Grid.Los(from, Player.Pos);
            }
            return true;
        }

        void DoAbility(BUnit e, Bag ab, int depth)
        {
            string kind = J.S(ab, "kind");
            if (e.Windup.Count > 0) { FireWindup(e); return; }
            if (kind == "block")
            {
                e.Block += J.I(ab, "amount");
                Ev("block", "unit", e.Uid, "amount", J.I(ab, "amount"));
                Log(e.DisplayName + " uses " + J.S(ab, "name") + ".");
                e.AbilityIdx++;
                var dummy = new Bag();
                dummy.Set("kind", "attack");
                dummy.Set("range", 1);
                Approach(e, dummy);
                return;
            }
            if (kind == "summon")
            {
                int limit = J.I(ab, "limit", 3);
                int existing = 0;
                foreach (var o in AliveEnemies()) if (o.Id == J.S(ab, "summon")) existing++;
                if (existing >= limit)
                {
                    e.AbilityIdx++;
                    if (depth < 3) DoAbility(e, e.NextAbility(), depth + 1);
                    return;
                }
                Log(e.DisplayName + " broods...");
                for (int i = 0; i < J.I(ab, "count", 1); i++) SpawnNear(e, J.S(ab, "summon"));
                e.AbilityIdx++;
                return;
            }
            if (kind == "infect")
            {
                BUnit ally = null;
                foreach (var o in AliveEnemies())
                    if (o != e && !o.Infected && !o.ImmuneToInfection && V2.Dist(o.Pos, e.Pos) <= J.I(ab, "range", 3))
                    { ally = o; break; }
                if (ally != null && Rng.Randf() < 0.45f)
                {
                    Log(e.DisplayName + " spits spores at " + ally.DisplayName + ".");
                    Ev("attack", "unit", e.Uid, "target", ally.Uid, "ranged", V2.Dist(e.Pos, ally.Pos) > 1);
                    if (V2.Dist(e.Pos, ally.Pos) > 1)
                        Ev("projectile", "unit", e.Uid, "target", ally.Uid, "kind", "spore", "from", e.Pos, "to", ally.Pos);
                    InfectUnit(ally);
                    e.AbilityIdx++;
                    return;
                }
            }
            if (J.I(ab, "min_range") > V2.Dist(e.Pos, Player.Pos) && depth < e.Abilities.Count)
            {
                e.AbilityIdx++;
                DoAbility(e, e.NextAbility(), depth + 1);
                return;
            }
            bool kiter = J.S(e.Def, "behavior") == "kiter";
            if (kiter && depth == 0 && V2.Dist(e.Pos, Player.Pos) <= 1 && kind == "attack" && J.I(ab, "range", 1) > 1)
            {
                Popup(e, "Backs off", "#c0c0ff");
                Flee(e, EffMove(e));
            }
            if (J.B(ab, "windup")) { StartWindup(e, ab); return; }
            if (!InRange(e, ab, e.Pos)) Approach(e, ab);
            if (!InRange(e, ab, e.Pos) || !Player.Alive) return;
            if (J.B(ab, "leap") && V2.Dist(e.Pos, Player.Pos) > 1)
            {
                var land = LandingFor(e);
                if (land == V2.None) return;
                Leap(e, land);
            }
            e.AbilityIdx++;
            EnemyAttack(e, ab);
            if (e.Alive && ab.Has("hit_and_run") && Player.Alive) Flee(e, J.I(ab, "hit_and_run"));
            else if (e.Alive && kiter && Player.Alive && J.I(ab, "range", 1) > 1) Flee(e, 1);
        }

        V2 LandingFor(BUnit e)
        {
            var occ = Occupied(e);
            var best = V2.None;
            int bd = 999;
            foreach (var n in Grid.Neighbors(Player.Pos))
            {
                if (Grid.BlocksMove(n) || occ.ContainsKey(n)) continue;
                int d = V2.Dist(e.Pos, n);
                if (d < bd) { bd = d; best = n; }
            }
            return best;
        }

        List<V2> AoeTiles(V2 c, int radius)
        {
            var list = new List<V2>();
            for (int dy = -radius; dy <= radius; dy++)
                for (int dx = -radius; dx <= radius; dx++)
                {
                    var p = c + new V2(dx, dy);
                    if (Grid.InBounds(p) && !Grid.IsVoid(p) && V2.Dist(c, p) <= radius) list.Add(p);
                }
            return list;
        }

        void StartWindup(BUnit e, Bag ab)
        {
            if (!InRange(e, ab, e.Pos)) Approach(e, ab);
            if (!InRange(e, ab, e.Pos) || !Player.Alive) return;
            FacePos(e, Player.Pos);
            e.Windup = ab;
            e.WindupTiles = J.S(ab, "kind") == "aoe" ? AoeTiles(e.Pos, J.I(ab, "radius", 1)) : new List<V2> { Player.Pos };
            var tiles = new List<object>();
            foreach (var t in e.WindupTiles) tiles.Add(t);
            Ev("windup", "unit", e.Uid, "tiles", tiles);
            Popup(e, J.S(ab, "name") + "!", "#ff9040");
            Log(e.DisplayName + " winds up " + J.S(ab, "name") + ": step out of the red tiles!");
        }

        void FireWindup(BUnit e)
        {
            var ab = e.Windup;
            var tiles = e.WindupTiles;
            e.Windup = new Bag();
            e.WindupTiles = new List<V2>();
            e.AbilityIdx++;
            Ev("windup_end", "unit", e.Uid);
            if (Player.Alive && tiles.Contains(Player.Pos)) EnemyAttack(e, ab, J.F(ab, "windup_mult", 1.5f));
            else
            {
                Ev("attack", "unit", e.Uid, "target", Player.Uid, "ranged", false);
                Popup(Player, "Sidestepped!", "#7dff8a");
                Log("You avoid " + J.S(ab, "name") + ".");
            }
        }

        void CancelWindup(BUnit e, bool quiet = true)
        {
            if (e.Windup.Count == 0) return;
            e.Windup = new Bag();
            e.WindupTiles = new List<V2>();
            Ev("windup_end", "unit", e.Uid);
            if (!quiet) Popup(e, "Interrupted!", "#ffe060");
        }

        void CheckPhases(BUnit u)
        {
            foreach (var raw in J.Arr(u.Def, "phases")) { }
            var ph = J.Arr(u.Def, "phases");
            for (int i = 0; i < ph.Count; i++)
            {
                if (u.PhaseDone.Contains(i) || !u.Alive) continue;
                var p = (Bag)ph[i];
                if (u.Hp > u.MaxHp * J.F(p, "hp_pct")) continue;
                u.PhaseDone.Add(i);
                u.BonusDamage += J.I(p, "bonus_damage");
                u.Move += J.I(p, "move");
                u.SpeedBonus += J.F(p, "speed");
                Popup(u, J.S(p, "popup", "PHASE 2"), "#ff5040");
                Ev("phase", "unit", u.Uid);
                Log(J.S(p, "text", u.DisplayName + " changes tactics!"));
                if (p.Has("summon"))
                    for (int k = 0; k < J.I(p, "count", 1); k++) SpawnNear(u, J.S(p, "summon"));
            }
        }

        int SynergyDamage(Bag op, BUnit tgt, string fdir)
        {
            int b = 0;
            bool bleeding = tgt.St("bleed") > 0;
            if (op.Has("flank_bonus") && fdir != "front") b += J.I(op, "flank_bonus");
            if (op.Has("bleed_bonus") && bleeding) b += J.I(op, "bleed_bonus");
            if (op.Has("per_momentum")) b += J.I(op, "per_momentum") * Math.Min(MovedTiles, J.I(op, "momentum_max", 6));
            if (op.Has("per_diet")) b += J.I(op, "per_diet") * Run.DietTier();
            if (tgt.St("mark") > 0)
            {
                int bonus = MarkBonus + Run.ItemBonus("mark_bonus");
                b += bonus;
                tgt.Status["mark"] = 0;
                Popup(tgt, "Mark +" + bonus, "#ffb060");
            }
            if (bleeding) b += Run.ItemBonus("bleed_vuln");
            if (fdir != "front") b += Run.ItemBonus("side_damage");
            b += Math.Min(3, MovedTiles / 2) * Run.ItemBonus("momentum_dmg");
            b += Run.DietTier() * Run.ItemBonus("diet_damage");
            return b;
        }

        public Bag IntentOf(BUnit e)
        {
            var empty = new Bag();
            if (!e.Alive) return empty;
            if (e.St("stun") > 0) { empty.Set("kind", "stun"); empty.Set("label", "Stunned"); return empty; }
            if (e.St("fear") > 0 && !e.IsBoss()) { empty.Set("kind", "flee"); empty.Set("label", "Fleeing"); return empty; }
            if (e.State == "idle") { empty.Set("kind", "idle"); empty.Set("label", "Unaware"); return empty; }
            if (e.State == "searching") { empty.Set("kind", "search"); empty.Set("label", "Searching"); return empty; }
            if (e.Windup.Count > 0)
            {
                int wd = J.Round(CalcDamage(e, Player, J.I(e.Windup, "damage"), 1f) * J.F(e.Windup, "windup_mult", 1.5f));
                empty.Set("kind", "windup");
                empty.Set("label", J.S(e.Windup, "name"));
                empty.Set("dmg", wd);
                return empty;
            }
            float rh = J.F(e.Def, "retreat_hp");
            if (rh > 0f && !e.Retreated && e.Hp <= e.MaxHp * rh) { empty.Set("kind", "flee"); empty.Set("label", "Retreating"); return empty; }
            Bag ab = null;
            int dist = V2.Dist(e.Pos, Player.Pos);
            for (int k = 0; k < e.Abilities.Count; k++)
            {
                var a = e.Abilities[(e.AbilityIdx + k) % e.Abilities.Count];
                if (J.I(a, "min_range") > dist) continue;
                ab = a;
                break;
            }
            if (ab == null) return empty;
            string kind = J.S(ab, "kind");
            var status = new List<object>();
            int dmg = 0;
            if (kind == "attack" || kind == "aoe" || kind == "infect")
            {
                int baseD = J.I(ab, "damage");
                dmg = baseD > 0 ? CalcDamage(e, Player, baseD, 1f) : 0;
                if (J.B(ab, "windup")) kind = "charge";
                else if (kind == "attack" && J.I(ab, "range", 1) > 1 && !J.B(ab, "leap")) kind = "ranged";
                else if (J.B(ab, "leap")) kind = "leap";
            }
            foreach (var k in new[] { "bleed", "poison", "web", "spores", "weak" })
                if (ab.Has(k)) status.Add(k);
            var res = new Bag();
            res.Set("kind", kind);
            res.Set("label", J.S(ab, "name"));
            res.Set("dmg", dmg);
            res.Set("status", status);
            return res;
        }

        void EnemyAttack(BUnit e, Bag ab, float mult = 1f)
        {
            FacePos(e, Player.Pos);
            string kind = J.S(ab, "kind");
            bool ranged = V2.Dist(e.Pos, Player.Pos) > 1 && !J.B(ab, "leap") && (kind == "attack" || kind == "infect");
            Ev("attack", "unit", e.Uid, "target", Player.Uid, "ranged", ranged);
            if (ranged)
            {
                string proj = J.S(ab, "projectile", kind == "infect" ? "spore" : "spit");
                Ev("projectile", "unit", e.Uid, "target", Player.Uid, "kind", proj, "from", e.Pos, "to", Player.Pos);
            }
            Log(e.DisplayName + " uses " + J.S(ab, "name") + ".");
            int baseD = J.I(ab, "damage");
            if (baseD > 0 && J.B(e.Def, "pack"))
            {
                int mates = 0;
                foreach (var o in AliveEnemies())
                    if (o != e && o.Id == e.Id && V2.Dist(o.Pos, Player.Pos) <= 1) mates++;
                mates = Math.Min(mates, 2);
                if (mates > 0) { baseD += mates; Popup(e, "Pack +" + mates, "#ffb060"); }
            }
            if (baseD > 0 && e.SurpriseReady)
            {
                e.SurpriseReady = false;
                int bonus = J.I(e.Def, "surprise");
                baseD += bonus;
                Popup(e, "Ambush! +" + bonus, "#ff7050");
            }
            if (baseD > 0 || kind == "attack" || kind == "aoe")
            {
                float fm = FacingMult(e.Pos, Player, J.Ob(ab, "facing"));
                string fdir = FacingDir(e.Pos, Player);
                int dmg = J.Round(CalcDamage(e, Player, baseD, fm) * mult);
                if (fdir != "front" && Math.Abs(fm - 1f) > 0.001f)
                    Popup(Player, J.S(J.Ob(Db.Facing(), "labels"), fdir) + " hit x" + Snap(fm), "#ff9a6a");
                Hit(Player, dmg, e, aoe: kind == "aoe");
                if (LastDodged) return;
            }
            if (!Player.Alive) return;
            if (ab.Has("bleed")) { Player.AddStatus("bleed", J.I(ab, "bleed")); Popup(Player, "Bleed +" + J.I(ab, "bleed"), "#e04050"); }
            if (ab.Has("poison")) { Player.AddStatus("poison", J.I(ab, "poison")); Popup(Player, "Poison +" + J.I(ab, "poison"), "#9aff5a"); }
            if (ab.Has("web")) { Player.AddStatus("web", J.I(ab, "web")); Popup(Player, "Webbed", "#e8e8ff"); }
            if (ab.Has("spores")) { Player.AddStatus("spores", J.I(ab, "spores")); Popup(Player, "Spores +" + J.I(ab, "spores"), "#8dff6a"); }
            if (ab.Has("weak")) Player.AddStatus("weak", J.I(ab, "weak"));
        }

        void Approach(BUnit e, Bag ab)
        {
            var res = Grid.ReachTiles(e.Pos, EffMove(e), Occupied(e), e.TerrainCosts);
            var best = e.Pos;
            int bestKey = ApproachKey(e, ab, e.Pos, 0);
            foreach (var p in res.Cost.Keys)
            {
                int k = ApproachKey(e, ab, p, res.Cost[p]);
                if (k < bestKey) { bestKey = k; best = p; }
            }
            if (best != e.Pos) MoveAlong(e, BGrid.PathFrom(res.Prev, e.Pos, best));
        }

        int ApproachKey(BUnit e, Bag ab, V2 p, int cost)
        {
            int d = V2.Dist(p, Player.Pos);
            bool inR = InRange(e, ab, p);
            int grass = Grid.IsGrass(p) ? 0 : 1;
            if (inR)
            {
                int flank = 0;
                if (J.I(ab, "range", 1) <= 1)
                {
                    string face = FacingDir(p, Player);
                    if (face == "back") flank = -6;
                    else if (face == "side") flank = -3;
                }
                return -1000 + cost * 2 + grass + flank + (J.I(ab, "range", 1) <= 1 ? 0 : -d);
            }
            return d * 10 + cost;
        }

        void Flee(BUnit e, int tiles)
        {
            var res = Grid.ReachTiles(e.Pos, tiles, Occupied(e), e.TerrainCosts);
            var best = e.Pos;
            int bestD = V2.Dist(e.Pos, Player.Pos);
            foreach (var p in res.Cost.Keys)
            {
                int d = V2.Dist(p, Player.Pos);
                if (d > bestD) { bestD = d; best = p; }
            }
            if (best != e.Pos) MoveAlong(e, BGrid.PathFrom(res.Prev, e.Pos, best));
        }

        void SpawnNear(BUnit e, string id)
        {
            var occ = Occupied();
            var spots = new List<V2>();
            for (int dy = -2; dy <= 2; dy++)
                for (int dx = -2; dx <= 2; dx++)
                {
                    var p = e.Pos + new V2(dx, dy);
                    if (Grid.InBounds(p) && !Grid.BlocksMove(p) && !occ.ContainsKey(p) && p != Player.Pos) spots.Add(p);
                }
            if (spots.Count == 0) return;
            var u = MakeEnemy(id);
            u.Pos = spots[(int)(Rng.Randi() % (uint)spots.Count)];
            u.Home = u.Pos;
            u.Aware = true;
            u.LastSeen = Player.Pos;
            u.Meter = 40f;
            Units.Add(u);
            Enemies.Add(u);
            Ev("spawn", "unit", u.Uid);
            Log(u.DisplayName + " emerges!");
        }
    }
}
