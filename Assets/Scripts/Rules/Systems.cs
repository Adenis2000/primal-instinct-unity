using System;
using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    public sealed class WeatherMods
    {
        public float Perception = 1f, Speed = 1f, Damage = 1f, Sneak;
        public int HungerExtra, StaminaDelta;
    }

    public static class WeatherSys
    {
        public static WeatherMods ModsFor(string weatherId, IReadOnlyList<string> tags)
        {
            var m = new WeatherMods();
            if (string.IsNullOrEmpty(weatherId) || !Db.Table("weather").Has(weatherId)) return m;
            var w = Db.Weather(weatherId);
            Apply(m, J.Ob(w, "global"));
            var by = J.Ob(w, "by_tag");
            if (tags != null && by != null)
                foreach (var t in tags)
                    if (by.Get(t) is Bag row) Apply(m, row);
            return m;
        }

        static void Apply(WeatherMods m, Bag src)
        {
            if (src == null) return;
            foreach (var k in src.Keys)
            {
                if (k == "perception_mult") m.Perception *= J.F(src.Get(k));
                else if (k == "speed_mult") m.Speed *= J.F(src.Get(k));
                else if (k == "damage_mult") m.Damage *= J.F(src.Get(k));
                else if (k == "hunger_extra") m.HungerExtra += J.I(src.Get(k));
                else if (k == "stamina_delta") m.StaminaDelta += J.I(src.Get(k));
                else if (k == "sneak_bonus") m.Sneak += J.F(src.Get(k));
            }
        }

        public static List<string> Describe(string weatherId, IReadOnlyList<string> tags)
        {
            var m = ModsFor(weatherId, tags);
            var lines = new List<string>();
            if (Math.Abs(m.Perception - 1f) > 0.01f) lines.Add("Enemy sight range x" + m.Perception.ToString("0.00"));
            if (Math.Abs(m.Speed - 1f) > 0.01f) lines.Add("Speed x" + m.Speed.ToString("0.00"));
            if (Math.Abs(m.Damage - 1f) > 0.01f) lines.Add("Damage x" + m.Damage.ToString("0.00"));
            if (m.HungerExtra != 0) lines.Add("+" + m.HungerExtra + " hunger per room");
            return lines;
        }

        public static string Roll(Rng rng, Bag stageDef)
        {
            var weights = J.Ob(stageDef, "weather_weights");
            if (weights == null || weights.Count == 0)
            {
                weights = new Bag();
                foreach (var k in Db.Table("weather").Keys)
                    weights.Set(k, J.F(Db.Weather(k), "weight", 1f));
            }
            return J.Weighted(rng, weights);
        }
    }

    public static class Difficulty
    {
        public static Bag Cfg() => Db.Table("difficulty");
        public static Bag Level(RunState run)
        {
            var lv = (Bag)Cfg()["levels"];
            return lv.Get(run.Difficulty) as Bag ?? (Bag)lv[J.S(Cfg(), "default", "normal")];
        }
        public static Bag StageRow(RunState run)
        {
            var rows = (List<object>)Cfg()["stages"];
            int i = J.Clamp(Math.Max(run.StageIdx, 0), 0, rows.Count - 1);
            return (Bag)rows[i];
        }
        public static bool IsTutorial(RunState run, Bag room) =>
            run.StageIdx <= 0 && J.I(room, "step", 99) < J.I(J.Ob(Cfg(), "tutorial"), "steps");

        public static Bag KindRow(Bag room)
        {
            var k = (Bag)Cfg()["kinds"];
            return k.Get(J.S(room, "type", "battle")) as Bag ?? (Bag)k["battle"];
        }

        public static float HpMult(RunState run, Bag room)
        {
            if (J.B(room, "no_scale")) return 1f;
            if (IsTutorial(run, room)) return J.F(J.Ob(Cfg(), "tutorial"), "hp") * J.F(Level(run), "hp");
            var st = StageRow(run);
            int step = J.I(room, "step", 0);
            return J.F(Level(run), "hp") * J.F(st, "hp") * (1f + J.F(st, "step_ramp") * step) * J.F(KindRow(room), "hp");
        }

        public static int DmgAdd(RunState run, Bag room)
        {
            if (J.B(room, "no_scale")) return 0;
            if (IsTutorial(run, room)) return J.I(J.Ob(Cfg(), "tutorial"), "dmg");
            return J.I(Level(run), "dmg") + J.I(StageRow(run), "dmg") + J.I(KindRow(room), "dmg");
        }

        public static float ExtraChance(RunState run, Bag room)
        {
            if (J.B(room, "no_scale")) return 0f;
            if (IsTutorial(run, room) || J.S(room, "type", "battle") != "battle" || J.S(room, "teach") != "") return 0f;
            return J.F(StageRow(run), "extra") + J.F(Level(run), "extra");
        }

        public static float HungerMult(RunState run)
        {
            if (run.StageIdx <= 0 && run.ClearedRooms < J.I(J.Ob(Cfg(), "tutorial"), "steps")) return 1f;
            return J.F(Level(run), "hunger");
        }
    }

    public static class Arch
    {
        public static Bag Table() => (Bag)Db.Table("archetypes")["archetypes"];
        public static int Threshold() => J.I(Db.Table("archetypes"), "synergy_threshold", 3);
        public static string NameOf(string tag) => J.S(Table().Get(tag) as Bag, "name", tag);

        public static Dictionary<string, int> Counts(IReadOnlyList<string> deck, IReadOnlyList<string> items)
        {
            var d = new Dictionary<string, int>();
            if (deck != null)
                foreach (var id in deck)
                    foreach (var t in J.Arr(Db.Card(id), "tags"))
                    {
                        string s = J.S(t);
                        d[s] = (d.TryGetValue(s, out int n) ? n : 0) + 1;
                    }
            if (items != null)
                foreach (var id in items)
                    foreach (var t in J.Arr(Db.Item(id), "tags"))
                    {
                        string s = J.S(t);
                        d[s] = (d.TryGetValue(s, out int n) ? n : 0) + 2;
                    }
            return d;
        }

        public static List<string> Matching(IReadOnlyList<object> tags, IReadOnlyList<string> deck, IReadOnlyList<string> items)
        {
            var c = Counts(deck, items);
            var outList = new List<string>();
            int th = Threshold();
            foreach (var t in tags)
            {
                string s = J.S(t);
                if (c.TryGetValue(s, out int n) && n >= th) outList.Add(s);
            }
            return outList;
        }

        public static string MainTag(IReadOnlyList<string> deck, IReadOnlyList<string> items)
        {
            var c = Counts(deck, items);
            string best = "";
            int bn = Threshold() - 1;
            foreach (var kv in c)
                if (kv.Value > bn) { bn = kv.Value; best = kv.Key; }
            return best;
        }
    }

    public sealed class SequencePuzzle
    {
        public List<int> Sequence = new List<int>();
        public int Buttons = 4;
        public int MistakesLeft = 2;
        public int Pos;
        public bool Finished;
        public bool Success;

        public static SequencePuzzle FromRoom(Bag room)
        {
            var p = new SequencePuzzle();
            foreach (var s in J.Arr(room, "sequence")) p.Sequence.Add(J.I(s));
            p.Buttons = J.I(room, "buttons", 4);
            p.MistakesLeft = J.I(room, "mistakes", 2);
            return p;
        }

        public string Press(int i)
        {
            if (Finished) return Success ? "done" : "fail";
            if (i == Sequence[Pos])
            {
                Pos++;
                if (Pos >= Sequence.Count) { Finished = true; Success = true; return "done"; }
                return "ok";
            }
            MistakesLeft--;
            Pos = 0;
            if (MistakesLeft <= 0) { Finished = true; Success = false; return "fail"; }
            return "wrong";
        }
    }
}
