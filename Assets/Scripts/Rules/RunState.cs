using System;
using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    public sealed class Meal
    {
        public float Pts;
        public Bag Profile;
        public string Kind;
    }

    public sealed class RunState
    {
        public int SeedVal;
        public Rng Rng = new Rng();
        public string SpeciesId = "velociraptor";
        public Bag Species = new Bag();
        public Bag Look = new Bag();
        public int Level = 1;
        public int Xp;
        public int Hp = 1;
        public int Hunger = 90;
        public int Spores;
        public List<string> Deck = new List<string>();
        public List<string> Items = new List<string>();
        public int StageIdx = -1;
        public Bag Stage = new Bag();
        public Bag CurrentRoom = new Bag();
        public int ClearedRooms;
        public bool GameOver;
        public bool Victory;
        public string Cause = "";
        public string Difficulty = "normal";
        public Dictionary<string, int> Stats = new Dictionary<string, int>
        {
            { "kills", 0 }, { "ambushes", 0 }, { "sneaks", 0 }, { "cards_drafted", 0 },
            { "eaten", 0 }, { "events", 0 }, { "puzzles", 0 }, { "caves", 0 }
        };
        public int PendingEvolutionTier;
        public List<Meal> Meals = new List<Meal>();
        public Dictionary<string, float> Nutrition = new Dictionary<string, float>
        {
            { "protein", 0 }, { "fat", 0 }, { "minerals", 0 }, { "fiber", 0 }, { "toxin", 0 }
        };
        public Dictionary<string, string> Branches = new Dictionary<string, string>();

        public static int Mix(int a, int b)
        {
            long h = ((long)a * 1103515245L + (long)b * 12345L + 0x9E3779B9L) & 0x7fffffffL;
            h = ((h ^ (h >> 13)) * 1274126177L) & 0x7fffffffL;
            return (int)h;
        }

        public static int SeedFromText(string t)
        {
            if (t == null) return 0;
            t = t.Trim();
            if (t.Length == 0) return 0;
            if (int.TryParse(t, out int n)) return Math.Abs(n) % 2147483647;
            int h = 7;
            foreach (var ch in t) h = Mix(h, ch);
            return h;
        }

        public static RunState Create(string speciesId, int seedIn = 0)
        {
            var r = new RunState();
            r.SpeciesId = speciesId;
            r.Species = Db.Species(speciesId);
            if (seedIn <= 0)
            {
                var g = new Rng();
                g.Randomize();
                seedIn = g.RandiRange(1, 2147483646);
            }
            r.SeedVal = seedIn;
            r.Rng.SetSeed(seedIn);
            var sd = J.Ob(r.Species, "starter_deck") ?? new Bag();
            foreach (var id in sd.Keys)
                for (int i = 0; i < J.I(sd.Get(id)); i++) r.Deck.Add(id);
            r.Hunger = J.I(r.Species, "start_hunger", 90);
            r.Hp = r.MaxHp();
            return r;
        }

        public int FormIndex()
        {
            var forms = (List<object>)Db.Growth()["forms"];
            int idx = 0;
            for (int i = 0; i < forms.Count; i++)
                if (Level >= J.I((Bag)forms[i], "min_level")) idx = i;
            return idx;
        }

        public Bag Form() => (Bag)((List<object>)Db.Growth()["forms"])[FormIndex()];
        public int Tier() => J.I(Form(), "tier");
        public string FormSpriteId() => J.S(((Bag)Species["sprites"])[J.S(Form(), "id")]);
        public List<string> Tags()
        {
            var list = new List<string>();
            foreach (var t in J.Arr(Species, "tags")) list.Add(J.S(t));
            return list;
        }

        public int ItemBonus(string key)
        {
            int n = 0;
            foreach (var id in Items) n += J.I(J.Ob(Db.Item(id), "effects"), key);
            return n;
        }

        public bool HasItem(string id) => Items.Contains(id);

        public void AddItem(string id)
        {
            if (Items.Contains(id)) return;
            Items.Add(id);
            int gain = J.I(J.Ob(Db.Item(id), "effects"), "max_hp");
            if (gain > 0) Hp = Math.Min(MaxHp(), Hp + gain);
        }

        public bool ItemDrop(string src)
        {
            var s = Db.ItemSource(src);
            return s.Count > 0 && Rng.Randf() < J.F(s, "chance");
        }

        public List<string> OfferItems(string src, int n = -1)
        {
            var s = Db.ItemSource(src);
            if (n < 0) n = J.I(s, "choices", 1);
            var rw = J.Ob(s, "weights") ?? new Bag();
            var weights = new Bag();
            foreach (var id in Db.ItemIds())
            {
                if (Items.Contains(id)) continue;
                var d = Db.Item(id);
                if (d.Has("only"))
                {
                    bool allowed = false;
                    foreach (var o in J.Arr(d, "only")) if (J.S(o) == src) allowed = true;
                    if (!allowed) continue;
                }
                float w = J.F(rw, J.S(d, "rarity"));
                if (w > 0f) weights.Set(id, w);
            }
            var offered = new List<string>();
            while (offered.Count < n && weights.Count > 0)
            {
                string pick = J.Weighted(Rng, weights);
                offered.Add(pick);
                weights.Remove(pick);
            }
            return offered;
        }

        public int MaxHp() => J.I(J.Ob(Species, "base"), "max_hp") + J.I(Form(), "hp") + (Level - 1) * J.I(Db.Growth(), "hp_per_level") + ItemBonus("max_hp");
        public float BaseSpeed() => J.F(J.Ob(Species, "base"), "speed") + J.F(Form(), "speed");
        public int BaseMove() => J.I(J.Ob(Species, "base"), "move") + J.I(Form(), "move") + ItemBonus("move");
        public int BaseStamina() => J.I(J.Ob(Species, "base"), "stamina") + J.I(Form(), "stamina") + ItemBonus("stamina");
        public int HandSize() => J.I(J.Ob(Species, "base"), "hand_size", 5);
        public int HungerMax() => J.I(J.Ob(Db.Growth(), "hunger"), "max", 100);

        public string HungerState()
        {
            var h = J.Ob(Db.Growth(), "hunger");
            if (Hunger <= 0) return "starving";
            if (Hunger <= J.I(h, "low_threshold")) return "low";
            return "ok";
        }

        public string WeatherId() => J.S(Stage, "weather");
        public WeatherMods CurrentWeather() => WeatherSys.ModsFor(WeatherId(), Tags());

        public int HungerCost()
        {
            int baseCost = J.I(Form(), "hunger_per_room") + CurrentWeather().HungerExtra - ItemBonus("hunger_save");
            return Math.Max(1, J.Round(baseCost * global::PrimalInstinct.Rules.Difficulty.HungerMult(this)));
        }

        public int XpToNext()
        {
            var lx = (List<object>)Db.Growth()["level_xp"];
            if (Level >= lx.Count) return 0;
            return J.I(lx[Level]);
        }

        public int MaxLevel() => ((List<object>)Db.Growth()["level_xp"]).Count;

        public void ChangeHp(int delta)
        {
            Hp = J.Clamp(Hp + delta, 0, MaxHp());
            CheckDead("");
        }

        public void CheckDead(string why)
        {
            if (Hp <= 0 && !GameOver)
            {
                GameOver = true;
                Cause = string.IsNullOrEmpty(why) ? "You were killed." : why;
            }
        }

        public void ChangeHunger(int delta) => Hunger = J.Clamp(Hunger + delta, 0, HungerMax());

        public Bag GrantXp(int amount)
        {
            int bonus = J.Round(amount * XpBonus());
            var res = new Bag();
            res.Set("levels", new List<object>());
            res.Set("evolved", false);
            res.Set("bonus", bonus);
            res.Set("gained", amount + bonus);
            Xp += amount + bonus;
            while (Level < MaxLevel() && Xp >= XpToNext() && XpToNext() > 0)
            {
                int oldForm = FormIndex();
                int oldMax = MaxHp();
                Level++;
                ((List<object>)res["levels"]).Add(Level);
                int gain = MaxHp() - oldMax;
                Hp = Math.Min(MaxHp(), Hp + gain + (int)(MaxHp() * J.F(Db.Growth(), "level_up_heal_pct")));
                if (FormIndex() != oldForm)
                {
                    res.Set("evolved", true);
                    PendingEvolutionTier = Tier();
                }
            }
            return res;
        }

        public List<string> EnterRoom(Bag room)
        {
            var msgs = new List<string>();
            CurrentRoom = room;
            int cost = HungerCost();
            ChangeHunger(-cost);
            msgs.Add("Entered a room: -" + cost + " hunger.");
            if (Hunger <= 0)
            {
                int loss = J.I(J.Ob(Db.Growth(), "hunger"), "starve_hp_loss");
                Hp = Math.Max(0, Hp - loss);
                msgs.Add("You are starving! -" + loss + " HP.");
                CheckDead("You starved to death.");
            }
            if (Spores > 0) Spores = Math.Max(0, Spores - 1);
            return msgs;
        }

        public void BeginStage(int idx)
        {
            StageIdx = idx;
            string sid = J.S(Db.StageOrder()[idx]);
            var def = Db.Stage(sid);
            var srng = new Rng();
            srng.SetSeed(Mix(SeedVal, 1000 + idx));
            var steps = StageGen.GenerateSteps(sid, def, srng, SeedVal, idx);
            Stage = new Bag();
            Stage.Set("id", sid);
            Stage.Set("idx", idx);
            Stage.Set("def", def);
            var stepList = new List<object>();
            foreach (var s in steps) stepList.Add(s);
            Stage.Set("steps", stepList);
            Stage.Set("step", 0);
            Stage.Set("weather", WeatherSys.Roll(srng, def));
            Stage.Set("theme", J.S(def, "theme", "jungle"));
            Stage.Set("secret_used_step", -1);
            CurrentRoom = new Bag();
        }

        public Bag StageDef() => J.Ob(Stage, "def") ?? new Bag();

        public List<Bag> CurrentStepDoors()
        {
            var steps = (List<object>)Stage["steps"];
            int step = J.I(Stage, "step");
            if (step >= steps.Count) return new List<Bag>();
            var doors = new List<Bag>();
            foreach (var d in (List<object>)((Bag)steps[step])["doors"]) doors.Add((Bag)d);
            return doors;
        }

        public Bag ChooseDoor(int i)
        {
            var room = CurrentStepDoors()[i];
            ((Bag)((List<object>)Stage["steps"])[J.I(Stage, "step")]).Set("chosen", i);
            room.Set("visited", true);
            return room;
        }

        public string CompleteRoom()
        {
            ClearedRooms++;
            int step = J.I(Stage, "step") + 1;
            Stage.Set("step", step);
            if (step >= ((List<object>)Stage["steps"]).Count) return "stage_clear";
            return "next";
        }

        public bool AdvanceStage()
        {
            if (StageIdx + 1 >= Db.StageOrder().Count) { Victory = true; return false; }
            BeginStage(StageIdx + 1);
            return true;
        }

        public void AddCard(string id) => Deck.Add(id);

        public bool RemoveOneCard(string id)
        {
            int i = Deck.IndexOf(id);
            if (i >= 0) { Deck.RemoveAt(i); return true; }
            return false;
        }

        public List<string> OfferCards(int n, string mode = "normal")
        {
            int t = Tier();
            List<string> pool;
            if (mode == "evolution")
            {
                pool = Db.DraftCards(t, t);
                if (pool.Count < n) pool = Db.DraftCards(1, t);
            }
            else if (mode == "cave") pool = Db.CaveCards();
            else pool = Db.DraftCards(1, t);
            var weights = new Bag();
            foreach (var id in pool)
            {
                var c = Db.Card(id);
                float w = 1f;
                if (J.I(c, "tier") == t) w = 3f;
                else if (J.I(c, "tier") == t - 1) w = 2f;
                if (mode == "elite" && J.I(c, "tier") >= 2) w *= 2f;
                weights.Set(id, w);
            }
            var offered = new List<string>();
            while (offered.Count < n && weights.Count > 0)
            {
                string pick = J.Weighted(Rng, weights);
                offered.Add(pick);
                weights.Remove(pick);
            }
            return offered;
        }

        public List<string> ApplyEffects(List<object> effects, Bag ctx)
        {
            var msgs = new List<string>();
            if (effects == null) return msgs;
            foreach (var raw in effects)
            {
                var e = (Bag)raw;
                int amt = J.I(e, "amount");
                switch (J.S(e, "op"))
                {
                    case "xp":
                        var r = GrantXp(amt);
                        msgs.Add("+" + amt + " XP");
                        ctx.Set("levels", r["levels"]);
                        if (J.B(r, "evolved")) ctx.Set("evolved", true);
                        break;
                    case "hunger":
                        ChangeHunger(amt);
                        msgs.Add((amt >= 0 ? "+" : "") + amt + " hunger");
                        break;
                    case "hp":
                        if (amt < 0) { Hp = Math.Max(0, Hp + amt); CheckDead("You died from your wounds."); }
                        else ChangeHp(amt);
                        msgs.Add((amt >= 0 ? "+" : "") + amt + " HP");
                        break;
                    case "heal":
                        ChangeHp(amt);
                        msgs.Add("+" + amt + " HP");
                        break;
                    case "spores":
                        Spores += amt;
                        msgs.Add("Infected: +" + amt + " spores");
                        break;
                    case "cleanse":
                        Spores = 0;
                        msgs.Add("Spores cleansed");
                        break;
                    case "add_card":
                        string id = J.S(e, "id");
                        if (id == "")
                        {
                            var pool = Tier() >= 2 ? Db.DraftCards(2, Tier()) : Db.DraftCards(1, 1);
                            id = pool[(int)(Rng.Randi() % (uint)pool.Count)];
                        }
                        AddCard(id);
                        msgs.Add("Gained card: " + J.S(Db.Card(id), "name"));
                        break;
                    case "remove_card":
                        if (RemoveOneCard(J.S(e, "id", "claw_slash"))) msgs.Add("Lost a card");
                        break;
                    case "battle":
                        var pools = (Bag)Db.Table("events")["battle_pools"];
                        string poolId = J.S(e, "pool");
                        List<object> enemies;
                        if (pools.Has(poolId))
                        {
                            var sp = (Bag)pools[poolId];
                            string key = J.S(Stage, "id", "stage_1");
                            enemies = sp.Get(key) as List<object> ?? (List<object>)sp[sp.Keys[0]];
                        }
                        else enemies = J.Arr(e, "enemies");
                        var battle = new Bag();
                        battle.Set("enemies", enemies);
                        battle.Set("unspotted", J.B(e, "unspotted"));
                        ctx.Set("battle", battle);
                        break;
                }
            }
            return msgs;
        }

        public Bag ResolveOutcome(Bag choice, Bag ctx)
        {
            var outs = (List<object>)choice["outcomes"];
            var items = new List<(int key, float w)>();
            for (int i = 0; i < outs.Count; i++) items.Add((i, J.F((Bag)outs[i], "weight", 1f)));
            int idx = J.Weighted(Rng, items);
            var o = (Bag)outs[idx];
            var msgs = ApplyEffects(J.Arr(o, "effects"), ctx);
            if (choice.Has("nutrition"))
            {
                var nut = (Bag)choice["nutrition"];
                AddNutrition(nut);
                var fp = nut.Clone();
                foreach (var nk in (List<object>)Db.Nutrition()["order"])
                    if (!fp.Has(J.S(nk))) fp.Set(J.S(nk), 0);
                LogMeal(MealPts(fp), fp, "forage");
            }
            var res = new Bag();
            res.Set("text", J.S(o, "text"));
            var msgList = new List<object>();
            foreach (var m in msgs) msgList.Add(m);
            res.Set("msgs", msgList);
            return res;
        }

        public string DietId() => J.S(Species, "diet", "carnivore");
        public Bag Diet() => (Bag)((Bag)Db.Nutrition()["diets"])[DietId()];

        public static Bag MealProfile(string enemyId, bool infected)
        {
            var p = (J.Ob(Db.Enemy(enemyId), "nutrition") ?? new Bag()).Clone();
            foreach (var k in (List<object>)Db.Nutrition()["order"])
                if (!p.Has(J.S(k))) p.Set(J.S(k), 0);
            if (infected && !J.B(Db.Enemy(enemyId), "infected"))
                p.Set("toxin", J.I(p, "toxin") + 3);
            return p;
        }

        public void AddNutrition(Bag profile, float mult = 1f)
        {
            float cap = J.F(Db.Nutrition(), "meter_cap", 100f);
            foreach (var k in profile.Keys)
            {
                float gain = J.F(profile.Get(k)) * mult;
                if (k != "toxin") gain *= 1f + ItemBonus("nutrition_pct") / 100f;
                float cur = Nutrition.TryGetValue(k, out var c) ? c : 0f;
                Nutrition[k] = J.Clamp(cur + gain, 0f, cap);
            }
        }

        public float MealScore(Bag profile)
        {
            var w = (Bag)Diet()["weights"];
            float s = 0f;
            foreach (var k in profile.Keys) s += J.F(w, k) * J.F(profile.Get(k));
            return s;
        }

        public string MealFitLabel(Bag profile)
        {
            float sc = MealScore(profile);
            foreach (var row in (List<object>)Db.Nutrition()["fit_labels"])
            {
                var arr = (List<object>)row;
                if (sc >= J.F(arr[0])) return J.S(arr[1]);
            }
            return "Harmful";
        }

        public float MealPts(Bag profile)
        {
            var cfg = J.Ob(Db.Nutrition(), "rolling");
            return J.Clamp(MealScore(profile), J.F(cfg, "pts_min"), J.F(cfg, "pts_max"));
        }

        public void LogMeal(float pts, Bag profile, string kind)
        {
            Meals.Insert(0, new Meal { Pts = pts, Profile = profile.Clone(), Kind = kind });
            int win = J.I(J.Ob(Db.Nutrition(), "rolling"), "window");
            while (Meals.Count > win) Meals.RemoveAt(Meals.Count - 1);
        }

        int RollingScore(List<Meal> log)
        {
            var cfg = J.Ob(Db.Nutrition(), "rolling");
            var rec = (List<object>)cfg["recency"];
            float totalW = 0f;
            foreach (var w in rec) totalW += J.F(w);
            float acc = 0f;
            var shares = new Dictionary<string, float>();
            var pref = (List<object>)Diet()["prefers"];
            int n = Math.Min(log.Count, rec.Count);
            for (int i = 0; i < n; i++)
            {
                acc += J.F(rec[i]) * log[i].Pts;
                if (log[i].Kind != "fill")
                    foreach (var k in pref)
                    {
                        string ks = J.S(k);
                        float add = J.F(rec[i]) * MathF.Max(0f, J.F(log[i].Profile, ks));
                        shares[ks] = (shares.TryGetValue(ks, out var c) ? c : 0f) + add;
                    }
            }
            float score = acc / totalW * J.F(cfg, "scale");
            var bal = J.Ob(cfg, "balance");
            if (log.Count >= J.I(bal, "min_meals") && pref.Count >= 2)
            {
                float tot = 0f, top = 0f;
                foreach (var kv in shares) { tot += kv.Value; top = MathF.Max(top, kv.Value); }
                if (tot > 0f && top / tot > J.F(bal, "threshold"))
                    score -= MathF.Min(J.F(bal, "max_penalty"), (top / tot - J.F(bal, "threshold")) * J.F(bal, "scale"));
            }
            return J.Round(score);
        }

        public int DietScore() => RollingScore(Meals);
        public string QualityFor(int sc)
        {
            foreach (var row in (List<object>)Db.Nutrition()["quality_labels"])
            {
                var arr = (List<object>)row;
                if (sc >= J.I(arr[0])) return J.S(arr[1]);
            }
            return "Poor";
        }
        public float XpBonus() => J.F(J.Ob(Db.Nutrition(), "xp_bonus"), DietQuality());
        public int ScoreAfter(Bag profile, string kind = "eat")
        {
            float pts = kind == "fill" ? J.F(Db.Nutrition(), "fill_pts") : MealPts(profile);
            var log = new List<Meal>(Meals);
            log.Insert(0, new Meal { Pts = pts, Profile = profile, Kind = kind });
            return RollingScore(log);
        }
        public string QualityAfter(Bag profile, string kind = "eat") => QualityFor(ScoreAfter(profile, kind));
        public float XpBonusFor(string quality) => J.F(J.Ob(Db.Nutrition(), "xp_bonus"), quality);
        public string DietQuality() => QualityFor(DietScore());
        public int DietTier()
        {
            switch (DietQuality())
            {
                case "Fair": return 1;
                case "Good": return 2;
                case "Excellent": return 3;
                default: return 0;
            }
        }
        public int EatHunger(int food, string mode)
        {
            if (mode == "fill") return food;
            return Math.Max(1, J.Ceil(food * J.F(Db.Nutrition(), "eat_hunger_mult")));
        }
        public int MealHeal(int food, Bag prof, string mode)
        {
            var mm = (Bag)Db.Nutrition()["meal_mult"];
            string key = mode == "fill" ? "fill" : MealFitLabel(prof);
            return J.Round(food / 4f * J.F(J.Ob(mm, key), "heal")) + ItemBonus("eat_heal");
        }

        public Bag EatCorpse(Bag corpse, string mode = "eat")
        {
            bool infected = J.B(corpse, "infected");
            int foodFull = J.I(corpse, "food") / (infected ? 2 : 1);
            int food = EatHunger(foodFull, mode);
            var prof = MealProfile(J.S(corpse, "id"), infected);
            string fit = MealFitLabel(prof);
            var mm = (Bag)Db.Nutrition()["meal_mult"];
            int heal = MealHeal(food, prof, mode);
            ChangeHunger(food);
            ChangeHp(heal);
            int toxLoss = 0;
            int tox = J.I(prof, "toxin");
            if (mode == "eat")
            {
                if (tox > 0 && !infected && ItemBonus("toxin_immune") == 0)
                {
                    toxLoss = Math.Min(tox * J.I(Db.Nutrition(), "toxin_hp"), Math.Max(0, Hp - 1));
                    Hp -= toxLoss;
                }
                LogMeal(MealPts(prof), prof, "eat");
                AddNutrition(prof, J.F(J.Ob(mm, fit), "nutrients"));
            }
            else LogMeal(J.F(Db.Nutrition(), "fill_pts"), prof, "fill");
            int sp = 0;
            if (infected) { sp = 2; Spores += sp; }
            Stats["eaten"] = Stats["eaten"] + 1;
            var res = new Bag();
            res.Set("hunger", food);
            res.Set("heal", heal);
            res.Set("toxin_hp", toxLoss);
            res.Set("spores", sp);
            res.Set("profile", prof);
            res.Set("mode", mode);
            res.Set("fit", MealFitLabel(prof));
            return res;
        }

        public List<Bag> BranchOptions(int tier)
        {
            var diets = J.Ob(J.Ob(Db.Nutrition(), "branches"), DietId()) ?? new Bag();
            var rows = diets.Get(tier.ToString()) as List<object> ?? new List<object>();
            var outList = new List<Bag>();
            foreach (var raw in rows)
            {
                var b = ((Bag)raw).Clone();
                var req = (Bag)b["requires"];
                var prog = new List<object>();
                bool met = true;
                foreach (var k in req.Keys)
                {
                    float have = 0f, need = J.F(req.Get(k));
                    bool ok = true;
                    string label;
                    if (k == "diet_score") { have = DietScore(); ok = have >= need; label = "Diet score"; }
                    else if (k == "max_toxin") { have = Nutrition["toxin"]; ok = have <= need; label = "Toxins at most"; }
                    else
                    {
                        have = Nutrition.TryGetValue(k, out var hv) ? hv : 0f;
                        ok = have >= need;
                        label = J.S(J.Ob((Bag)Db.Nutrition()["nutrients"], k), "name", k);
                    }
                    var row = new Bag();
                    row.Set("label", label);
                    row.Set("have", have);
                    row.Set("need", need);
                    row.Set("ok", ok);
                    prog.Add(row);
                    if (!ok) met = false;
                }
                b.Set("unlocked", met);
                b.Set("progress", prog);
                outList.Add(b);
            }
            return outList;
        }

        public List<string> ChooseBranch(int tier, string id)
        {
            Branches[tier.ToString()] = id ?? "";
            var extra = new List<string>();
            if (string.IsNullOrEmpty(id)) return extra;
            foreach (var b in BranchOptions(tier))
            {
                if (J.S(b, "id") != id) continue;
                if (!J.B(b, "unlocked")) { Branches[tier.ToString()] = ""; return extra; }
                AddItem(J.S(b, "item"));
                foreach (var d in J.Arr(b, "extra_drafts")) extra.Add(J.S(d));
                return extra;
            }
            return extra;
        }

        public string BranchName()
        {
            var diets = J.Ob(J.Ob(Db.Nutrition(), "branches"), DietId()) ?? new Bag();
            foreach (var t in new[] { "4", "3", "2" })
            {
                if (!Branches.TryGetValue(t, out var id) || id == "") continue;
                var rows = diets.Get(t) as List<object>;
                if (rows == null) continue;
                foreach (var raw in rows)
                    if (J.S((Bag)raw, "id") == id) return J.S((Bag)raw, "name");
            }
            return "";
        }

        public void Bump(string key, int n = 1)
        {
            Stats.TryGetValue(key, out int cur);
            Stats[key] = cur + n;
        }
    }
}
