using System;
using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    public sealed partial class Battle
    {
        static readonly string[] RiderOps = { "bleed", "poison", "web", "weak", "expose", "stun", "daze", "mark", "double_bleed" };

        void ApplyOp(Bag op, Ctx ctx)
        {
            object tgt = ctx.Target;
            int amt = J.I(op, "amount");
            string kind = J.S(op, "op");
            if (ctx.Dodged && Array.IndexOf(RiderOps, kind) >= 0) return;
            switch (kind)
            {
                case "damage":
                    if (!(tgt is BUnit victim) || !victim.Alive) return;
                    int baseD = amt;
                    if (!victim.Aware) baseD += J.I(op, "unaware_bonus");
                    baseD += J.I(op, "per_bleed") * victim.St("bleed");
                    if (ctx.WasHidden) baseD += Stalker;
                    FacePos(Player, victim.Pos);
                    string fdir = FacingDir(Player.Pos, victim);
                    baseD += SynergyDamage(op, victim, fdir);
                    var over = J.Ob(op, "facing");
                    float fm = FacingMult(Player.Pos, victim, over);
                    if (fdir == "back") baseD += Run.ItemBonus("back_damage");
                    if (!victim.Aware) baseD += Run.ItemBonus("unaware_damage");
                    ctx.Fdir = fdir;
                    int dmg = CalcDamage(Player, victim, baseD, fm);
                    if (fdir != "front" && Math.Abs(fm - 1f) > 0.001f)
                        Popup(victim, J.S(J.Ob(Db.Facing(), "labels"), fdir) + " x" + Snap(fm), fdir == "back" ? "#7dff8a" : "#ffd24a");
                    bool wasUnaware = !victim.Aware;
                    bool killed = Hit(victim, dmg, Player, silentIfKill: wasUnaware);
                    ctx.Dodged = LastDodged;
                    ctx.Hit = !LastDodged;
                    if (!LastDodged && J.B(op, "consume_bleed") && victim.Alive)
                    {
                        victim.Status["bleed"] = 0;
                        Popup(victim, "Bleed consumed", "#e04050");
                    }
                    if (killed && op.Has("on_kill"))
                        foreach (var k in J.Arr(op, "on_kill")) ApplyOp((Bag)k, ctx);
                    break;
                case "bleed":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive)
                        {
                            int ba = amt;
                            if (op.Has("back_bonus") && ctx.Fdir == "back") ba += J.I(op, "back_bonus");
                            ba += Run.ItemBonus("bleed_bonus");
                            u.AddStatus("bleed", ba);
                            Popup(u, "Bleed +" + ba, "#e04050");
                        }
                    break;
                case "poison":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive)
                        {
                            int pa = amt + Run.ItemBonus("poison_bonus");
                            if (op.Has("back_mult") && ctx.Fdir == "back") pa *= J.I(op, "back_mult");
                            u.AddStatus("poison", pa);
                            Popup(u, "Poison +" + pa, "#9aff5a");
                        }
                    break;
                case "web":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive) { u.AddStatus("web", J.I(op, "turns", 1)); Popup(u, "Webbed", "#e8e8ff"); }
                    break;
                case "weak":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive)
                        {
                            if (J.B(op, "back_only") && ctx.Fdir != "back") continue;
                            u.AddStatus("weak", J.I(op, "turns", 1));
                            Popup(u, "Weakened", "#a0a0c0");
                        }
                    break;
                case "expose":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive) { u.AddStatus("expose", J.I(op, "turns", 1)); Popup(u, "Exposed", "#f0b030"); }
                    break;
                case "stun":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive) u.AddStatus("stun", J.I(op, "turns", 1));
                    break;
                case "block":
                    Player.Block += amt;
                    Ev("block", "unit", Player.Uid, "amount", amt);
                    break;
                case "gain_mp":
                    Mp += amt; MpMax += amt;
                    Popup(Player, "+" + amt + " move", "#7fd8f0");
                    break;
                case "gain_stamina":
                    if (op.Has("cond") && MovedTiles < J.I(J.Ob(op, "cond"), "momentum_min")) return;
                    Stamina += amt;
                    Popup(Player, "+" + amt + " stamina", "#f0b030");
                    break;
                case "draw": Draw(amt); break;
                case "heal":
                    Player.Hp = Math.Min(Player.MaxHp, Player.Hp + amt);
                    Ev("heal", "unit", Player.Uid, "amount", amt, "hp_after", Player.Hp);
                    break;
                case "hunger":
                    Run.ChangeHunger(amt);
                    Popup(Player, "+" + amt + " hunger", "#e8a060");
                    break;
                case "self_damage": RawDamage(Player, amt, "self"); break;
                case "speed_buff":
                    Player.SpeedBonus += amt;
                    Popup(Player, "+" + amt + " speed", "#7fd8f0");
                    break;
                case "stalker":
                    Stalker += amt;
                    Popup(Player, "Stalker", "#6fc24e");
                    break;
                case "calm":
                    Calm = true;
                    Popup(Player, "Calm", "#6fc24e");
                    break;
                case "extra_turn":
                    Player.Meter += MeterMax;
                    Popup(Player, "EXTRA TURN", "#ffe060");
                    break;
                case "pounce":
                    if (tgt is BUnit pu && V2.Dist(Player.Pos, pu.Pos) > 1)
                    {
                        var land = LandingTile(pu, J.I(ctx.Card, "range", 4));
                        if (land != V2.None) Leap(Player, land, false, "pounce");
                    }
                    if (tgt is BUnit face) FacePos(Player, face.Pos);
                    break;
                case "dash":
                    if (tgt is V2 dest && dest != Player.Pos)
                    {
                        var res = Grid.ReachTiles(Player.Pos, J.I(ctx.Card, "range", 4), Occupied(Player), Player.TerrainCosts);
                        MoveAlong(Player, BGrid.PathFrom(res.Prev, Player.Pos, dest));
                    }
                    break;
                case "retreat":
                    Retreat(Player, J.I(op, "tiles", 2) + Run.ItemBonus("retreat_bonus"));
                    break;
                case "mark":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive) { u.AddStatus("mark", J.I(op, "turns", 2)); Popup(u, "Marked", "#ffb060"); }
                    break;
                case "daze":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive) { u.AddStatus("daze", J.I(op, "turns", 1)); Popup(u, "Dazed", "#c8a0ff"); }
                    break;
                case "fear":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive)
                        {
                            if (u.IsBoss()) Popup(u, "Resists fear", "#a0a0a0");
                            else { u.AddStatus("fear", J.I(op, "turns", 1)); CancelWindup(u, false); Popup(u, "Feared", "#d890ff"); }
                        }
                    break;
                case "double_bleed":
                    foreach (var u in OpTargets(ctx))
                        if (u.Alive && u.St("bleed") > 0)
                        {
                            u.Status["bleed"] = u.St("bleed") * 2;
                            Popup(u, "Bleed x2 (" + u.St("bleed") + ")", "#e04050");
                        }
                    break;
                case "patient": Patient = true; Popup(Player, "Patient Hunter", "#8fd070"); break;
                case "quicken": Quicken = true; Popup(Player, "Quicken", "#7fd8f0"); break;
                case "well_fed": WellFedOn = true; Popup(Player, "Well-Fed", "#e0a050"); break;
                case "evade": EvadeTemp += amt; Popup(Player, "+" + amt + "% evasion", "#7fd8f0"); break;
                case "heal_per_bleeding":
                    int nb = 0;
                    foreach (var e in AliveEnemies()) if (e.St("bleed") > 0) nb++;
                    if (nb > 0)
                    {
                        Player.Hp = Math.Min(Player.MaxHp, Player.Hp + amt * nb);
                        Ev("heal", "unit", Player.Uid, "amount", amt * nb, "hp_after", Player.Hp);
                    }
                    break;
                case "draw_if_bleeding":
                    foreach (var e in AliveEnemies()) if (e.St("bleed") > 0) { Draw(amt); break; }
                    break;
                case "draw_if_grass":
                    if (Grid.IsGrass(Player.Pos)) { Draw(amt); Popup(Player, "Cover: +" + amt + " card", "#8fd070"); }
                    break;
                case "draw_diet":
                    int dn = amt * Run.DietTier();
                    if (dn > 0) { Draw(dn); Popup(Player, "Diet: +" + dn + " cards", "#e0a050"); }
                    break;
                case "damage_adjacent":
                    foreach (var e in AliveEnemies())
                    {
                        if (V2.Dist(Player.Pos, e.Pos) > 1) continue;
                        string fd = FacingDir(Player.Pos, e);
                        int d2 = CalcDamage(Player, e, amt + SynergyDamage(new Bag(), e, fd), 1f);
                        Hit(e, d2, Player, aoe: true);
                        ctx.Hit = true;
                        if (CheckEnd()) return;
                    }
                    break;
                case "hide": TryHide(); break;
            }
        }

        List<BUnit> OpTargets(Ctx ctx)
        {
            if (J.S(ctx.Card, "target") == "all_enemies") return AliveEnemies();
            if (ctx.Target is BUnit u) return new List<BUnit> { u };
            return new List<BUnit>();
        }

        public static V2 DirToward(V2 a, V2 b, V2 keep)
        {
            var d = b - a;
            if (d == V2.Zero) return keep;
            if (Math.Abs(d.X) > Math.Abs(d.Y)) return new V2(J.Sign(d.X), 0);
            if (Math.Abs(d.Y) > Math.Abs(d.X)) return new V2(0, J.Sign(d.Y));
            if (keep.X != 0 && J.Sign(d.X) == keep.X) return new V2(keep.X, 0);
            if (keep.Y != 0 && J.Sign(d.Y) == keep.Y) return new V2(0, keep.Y);
            return new V2(J.Sign(d.X), 0);
        }

        public static int QuarterTurns(V2 a, V2 b)
        {
            int ia = Array.IndexOf(Dirs4, a);
            int ib = Array.IndexOf(Dirs4, b);
            int d = J.PosMod(ib - ia, 4);
            return Math.Min(d, 4 - d);
        }

        public static string RelativeDir(V2 from, V2 tgtPos, V2 tgtFacing)
        {
            var v = from - tgtPos;
            if (v == V2.Zero) return "front";
            int dot = v.X * tgtFacing.X + v.Y * tgtFacing.Y;
            int p = Math.Abs(v.X * tgtFacing.Y - v.Y * tgtFacing.X);
            if (dot > p) return "front";
            if (-dot > p) return "back";
            return "side";
        }

        public string FacingDir(V2 from, BUnit tgt) => RelativeDir(from, tgt.Pos, tgt.Facing);

        public float FacingMult(V2 from, BUnit tgt, Bag over)
        {
            string d = FacingDir(from, tgt);
            var defaults = (Bag)Db.Facing()["defaults"];
            var trait = tgt.FacingTrait();
            if (tgt.IsPlayer) return J.F(over, d, J.F(trait, d, J.F(defaults, d)));
            return J.F(over, d, J.F(defaults, d)) * J.F(trait, d, 1f);
        }

        public float VisionMult(BUnit e, V2 p)
        {
            string d = RelativeDir(p, e.Pos, e.Facing);
            var table = (Bag)Db.Facing()["vision"];
            var own = J.Ob(e.FacingTrait(), "vision") ?? new Bag();
            return J.F(own, d, J.F(table, d));
        }

        bool SetFacing(BUnit u, V2 dir)
        {
            if (dir == u.Facing || dir == V2.Zero) return false;
            int need = QuarterTurns(u.Facing, dir);
            var target = dir;
            if (need > u.TurnsLeft)
            {
                if (u.TurnsLeft <= 0) return false;
                int ia = Array.IndexOf(Dirs4, u.Facing);
                int ib = Array.IndexOf(Dirs4, dir);
                int step = J.PosMod(ib - ia, 4) <= 2 ? 1 : -1;
                target = Dirs4[J.PosMod(ia + step * u.TurnsLeft, 4)];
                need = u.TurnsLeft;
            }
            u.TurnsLeft -= need;
            u.Facing = target;
            Ev("face", "unit", u.Uid, "dir", target);
            return true;
        }

        void FacePos(BUnit u, V2 p) => SetFacing(u, DirToward(u.Pos, p, u.Facing));

        public V2 FacePlayerToward(V2 p)
        {
            if (Phase != "player" && Phase != "ambush" && Phase != "explore") return Player.Facing;
            Player.TurnsLeft = 99;
            FacePos(Player, p);
            return Player.Facing;
        }

        public Bag PreviewAttack(int i, BUnit tgt)
        {
            var c = CardAt(i);
            var from = Player.Pos;
            if (HasOp(c, "pounce") && V2.Dist(Player.Pos, tgt.Pos) > 1)
            {
                var land = LandingTile(tgt, J.I(c, "range", 4));
                if (land != V2.None) from = land;
            }
            Bag over = null;
            foreach (var e in J.Arr(c, "effects"))
                if (J.S((Bag)e, "op") == "damage" && ((Bag)e).Has("facing")) { over = J.Ob((Bag)e, "facing"); break; }
            var res = new Bag();
            res.Set("dir", FacingDir(from, tgt));
            res.Set("mult", FacingMult(from, tgt, over));
            res.Set("from", from);
            return res;
        }

        public int CalcDamage(BUnit src, BUnit tgt, int baseD, float fmult = 1f)
        {
            float amt = (baseD + src.BonusDamage) * fmult;
            amt *= Wm(src).Damage;
            if (src.St("weak") > 0) amt *= 0.75f;
            if (src.St("daze") > 0) amt *= DazeDamage;
            if (tgt.St("expose") > 0) amt *= 1.5f;
            return Math.Max(0, J.Round(amt));
        }

        public bool Hit(BUnit tgt, int dmg, BUnit src, bool silentIfKill = false, bool aoe = false)
        {
            LastDodged = false;
            if (src != null && tgt.Alive && !aoe && (tgt.IsPlayer || tgt.Aware))
            {
                float evade = Grid.Evasion(tgt.Pos);
                if (tgt.IsPlayer)
                {
                    if (Grid.IsGrass(tgt.Pos)) evade += Run.ItemBonus("grass_evasion") / 100f;
                    evade += EvadeTemp / 100f;
                }
                evade = MathF.Min(evade, 0.75f);
                if (evade > 0f && EvadeRng.Randf() < evade)
                {
                    LastDodged = true;
                    Ev("dodge", "unit", tgt.Uid, "src", src.Uid);
                    Log((tgt.IsPlayer ? "You" : tgt.DisplayName) + " dodges in the tall grass!");
                    return false;
                }
            }
            if (src != null && tgt.Alive && !tgt.IsPlayer && tgt.Armor > 0 && tgt.St("expose") == 0 && dmg > 0 && FacingDir(src.Pos, tgt) == "front")
            {
                int reduced = Math.Max(J.Ceil(dmg / 2f), dmg - tgt.Armor);
                dmg = reduced;
                Popup(tgt, "Armor -" + tgt.Armor, "#b0b8c8");
            }
            int absorbed = Math.Min(tgt.Block, dmg);
            tgt.Block -= absorbed;
            int real = dmg - absorbed;
            tgt.Hp -= real;
            Ev("hit", "src", src != null ? src.Uid : -1, "unit", tgt.Uid, "amount", real, "blocked", absorbed, "hp_after", Math.Max(tgt.Hp, 0), "why", "attack");
            if (tgt.Hp <= 0)
            {
                bool silent = silentIfKill && src != null && src.IsPlayer;
                Kill(tgt);
                if (silent) Popup(src, "Silent kill", "#6fc24e");
                else Noise(tgt.Pos, src);
                return true;
            }
            if (!tgt.IsPlayer) CheckPhases(tgt);
            if (src != null && src.IsPlayer && !tgt.IsPlayer)
            {
                if (!tgt.Aware) { tgt.Aware = true; tgt.LastSeen = Player.Pos; Ev("spot", "unit", tgt.Uid); }
                Noise(tgt.Pos, src);
            }
            return false;
        }

        void Noise(V2 at, BUnit src)
        {
            if (src == null || !src.IsPlayer) return;
            foreach (var e in AliveEnemies())
                if (!e.Aware && V2.Dist(e.Pos, at) <= NoiseRadius)
                {
                    e.Aware = true;
                    e.LastSeen = Player.Pos;
                    Ev("spot", "unit", e.Uid);
                    Log(e.DisplayName + " heard the commotion.");
                }
        }

        void Kill(BUnit u)
        {
            u.Alive = false;
            u.Hp = 0;
            Ev("death", "unit", u.Uid);
            if (!u.IsPlayer && Run != null && Run.ItemBonus("kill_heal") > 0 && Player.Alive)
            {
                int kh = Run.ItemBonus("kill_heal");
                Player.Hp = Math.Min(Player.MaxHp, Player.Hp + kh);
                Ev("heal", "unit", Player.Uid, "amount", kh, "hp_after", Player.Hp);
            }
            if (!u.IsPlayer)
            {
                var row = new Bag();
                row.Set("id", u.Id);
                row.Set("infected", u.Infected);
                row.Set("xp", J.I(u.Def, "xp"));
                row.Set("food", J.I(u.Def, "food"));
                row.Set("name", u.DisplayName);
                Killed.Add(row);
                Log(u.DisplayName + " is defeated.");
            }
            else Log("You fall...");
        }

        public bool CheckEnd()
        {
            if (Phase == "won" || Phase == "lost") return true;
            if (!Player.Alive) { Phase = "lost"; Ev("end", "result", "lost"); return true; }
            if (AliveEnemies().Count == 0 && Phase != "explore" && Mode != "explore")
            {
                Phase = "won";
                Ev("end", "result", "won");
                return true;
            }
            return false;
        }

        public Bag Result()
        {
            int xp = 0, food = 0, inf = 0;
            foreach (var k in Killed)
            {
                xp += J.I(k, "xp");
                food += J.I(k, "food") / (J.B(k, "infected") ? 2 : 1);
                if (J.B(k, "infected")) inf++;
            }
            var res = new Bag();
            res.Set("won", Phase == "won");
            res.Set("xp", xp);
            res.Set("food", food);
            res.Set("infected_corpses", inf);
            res.Set("kills", Killed.Count);
            var corpses = new List<object>();
            foreach (var k in Killed) corpses.Add(k.Clone());
            res.Set("corpses", corpses);
            return res;
        }

        public void CommitToRun()
        {
            Run.Hp = J.Clamp(Player.Hp, 0, Run.MaxHp());
            Run.Spores = Player.St("spores");
            Run.Bump("kills", Killed.Count);
            if (!Player.Alive) { Run.GameOver = true; Run.Cause = "Slain in battle."; }
        }

        public Dictionary<V2, int> ReachableTiles()
        {
            if (Phase != "player" && Phase != "explore" && Phase != "ambush") return new Dictionary<V2, int>();
            return Grid.ReachTiles(Player.Pos, Mp, Occupied(Player), Player.TerrainCosts).Cost;
        }

        public bool CanStillMove()
        {
            if (Mp <= 0) return false;
            foreach (var kv in ReachableTiles())
                if (kv.Key != Player.Pos && kv.Value <= Mp && kv.Value > 0) return true;
            return false;
        }

        public bool MovePlayer(V2 dest)
        {
            if (Phase != "player" && Phase != "explore" && Phase != "ambush") return false;
            var res = Grid.ReachTiles(Player.Pos, Mp, Occupied(Player), Player.TerrainCosts);
            if (!res.Cost.ContainsKey(dest) || dest == Player.Pos) return false;
            var path = BGrid.PathFrom(res.Prev, Player.Pos, dest);
            Mp -= res.Cost[dest];
            MoveAlong(Player, path);
            if (Phase == "ambush")
            {
                bool seen = false;
                foreach (var e in AliveEnemies()) if (e.Aware) seen = true;
                if (seen) FinishAmbush();
            }
            return true;
        }

        void MoveAlong(BUnit u, List<V2> path)
        {
            if (path == null || path.Count == 0) return;
            var pathObjs = new List<object>();
            foreach (var p in path) pathObjs.Add(p);
            Ev("move", "unit", u.Uid, "path", pathObjs);
            if (u.IsPlayer) MovedTiles += path.Count;
            var prev = u.Pos;
            foreach (var p in path)
            {
                SetFacing(u, DirToward(prev, p, u.Facing));
                prev = p;
            }
            u.Pos = path[path.Count - 1];
            if (u.IsPlayer) DetectAll();
        }

        void Leap(BUnit u, V2 dest, bool detect = true, string style = "leap")
        {
            if (dest == u.Pos) return;
            Ev("leap", "unit", u.Uid, "from", u.Pos, "to", dest, "style", style);
            if (u.IsPlayer) MovedTiles += V2.Dist(u.Pos, dest);
            SetFacing(u, DirToward(u.Pos, dest, u.Facing));
            u.Pos = dest;
            if (u.IsPlayer && detect) DetectAll();
        }

        V2 LandingTile(BUnit target, int maxRange)
        {
            var best = V2.None;
            int bestScore = 9999;
            var occ = Occupied();
            foreach (var n in Grid.Neighbors(target.Pos))
            {
                if (Grid.BlocksMove(n)) continue;
                if (occ.TryGetValue(n, out var who) && !ReferenceEquals(who, Player)) continue;
                int d = V2.Dist(Player.Pos, n);
                if (d > maxRange) continue;
                int score = d * 10 - (Grid.IsGrass(n) ? 3 : 0) + (Grid.GetTile(n) == "water" ? 2 : 0);
                string face = FacingDir(n, target);
                if (face == "back") score -= 12;
                else if (face == "side") score -= 5;
                if (score < bestScore) { bestScore = score; best = n; }
            }
            return best;
        }

        void Retreat(BUnit u, int tiles)
        {
            var res = Grid.ReachTiles(u.Pos, tiles, Occupied(u), u.TerrainCosts);
            var foes = new List<BUnit>();
            foreach (var e in Enemies) if (e.Alive && e.Aware) foes.Add(e);
            if (foes.Count == 0) foes = AliveEnemies();
            var best = u.Pos;
            int bestScore = RetreatScore(u.Pos, foes, 0);
            foreach (var p in res.Cost.Keys)
            {
                int s = RetreatScore(p, foes, res.Cost[p]);
                if (s > bestScore) { bestScore = s; best = p; }
            }
            if (best != u.Pos) MoveAlong(u, BGrid.PathFrom(res.Prev, u.Pos, best));
        }

        int RetreatScore(V2 p, List<BUnit> foes, int cost)
        {
            int md = 99;
            foreach (var f in foes) md = Math.Min(md, V2.Dist(p, f.Pos));
            return md * 10 + (Grid.IsGrass(p) ? 6 : 0) - cost;
        }

        void TryHide()
        {
            if (!Grid.IsGrass(Player.Pos)) { Popup(Player, "Nowhere to hide", "#a0a0a0"); return; }
            bool lost = false;
            foreach (var e in AliveEnemies())
                if (e.Aware && V2.Dist(e.Pos, Player.Pos) >= 2) { LoseTrack(e); lost = true; }
            if (lost) { Popup(Player, "HIDDEN", "#6fc24e"); Log("You melt into the tall grass."); }
            else if (!IsHidden()) Popup(Player, "Too close!", "#a0a0a0");
        }

        public bool CanDetectAt(BUnit e, V2 p)
        {
            float vm = VisionMult(e, p);
            if (vm <= 0f) return false;
            int d = V2.Dist(e.Pos, p);
            if (d <= 1) return true;
            int r = Math.Max(1, J.Floor(e.Perception * Wm(e).Perception * Grid.DetectMod(p) * vm + 0.0001f));
            return d <= r && Grid.Los(e.Pos, p);
        }

        public bool CanDetect(BUnit e) => CanDetectAt(e, Player.Pos);

        public int DetectRange(BUnit e)
        {
            float r = e.Perception * Wm(e).Perception * Grid.DetectMod(Player.Pos);
            return Math.Max(1, J.Floor(r + 0.0001f) - Run.ItemBonus("stealth"));
        }

        void DetectAll()
        {
            foreach (var e in AliveEnemies())
            {
                if (e.State != "spotted") { if (CanDetect(e)) Spot(e, e.State != "searching"); }
                else if (TracksPlayer(e)) e.LastSeen = Player.Pos;
            }
        }

        void Spot(BUnit e, bool alertOthers = true)
        {
            if (e.State == "idle" && J.I(e.Def, "surprise") > 0) e.SurpriseReady = true;
            e.Aware = true;
            e.LastSeen = Player.Pos;
            e.RoamTarget = V2.None;
            Ev("spot", "unit", e.Uid);
            Log(e.DisplayName + " spots you!");
            if (!alertOthers) return;
            foreach (var o in AliveEnemies())
                if (o.State == "idle" && V2.Dist(o.Pos, e.Pos) <= NoiseRadius)
                {
                    o.Aware = true;
                    o.LastSeen = Player.Pos;
                    Ev("spot", "unit", o.Uid);
                }
        }

        public bool TracksPlayer(BUnit e)
        {
            int d = V2.Dist(e.Pos, Player.Pos);
            if (d <= 1) return true;
            if (e.IsBoss()) return true;
            if (J.B(e.Def, "elite") && d <= 10) return true;
            if (e.Tags.Contains("scent") && d <= ScentRange) return true;
            int r = Math.Max(1, J.Floor(e.Perception * Wm(e).Perception * Grid.DetectMod(Player.Pos) * TrackMult + 0.0001f));
            return d <= r && Grid.Los(e.Pos, Player.Pos);
        }

        void LoseTrack(BUnit e)
        {
            e.State = "searching";
            e.SearchPhase = "go";
            e.ScanLeft = SearchScanTurns;
            if (e.LastSeen == V2.None) e.LastSeen = Player.Pos;
            Ev("lose_track", "unit", e.Uid, "last_seen", e.LastSeen);
            Log(e.DisplayName + " loses sight of you.");
        }

        static string Snap(float v) => MathF.Round(v, 2).ToString("0.##");
    }
}
