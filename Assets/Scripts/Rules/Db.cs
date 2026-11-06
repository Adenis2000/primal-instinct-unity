using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json.Nodes;

namespace PrimalInstinct.Rules
{
    /// <summary>Loads data/*.json. Content edits there are picked up on the next launch.</summary>
    public static class Db
    {
        public static readonly string[] Tables = {
            "species", "growth", "cards", "enemies", "events", "weather", "tiles", "stages", "puzzles",
            "hints", "sprites", "facing", "themes", "items", "nutrition", "arenas", "difficulty",
            "archetypes", "keywords", "customization", "backdrops", "cutscene_intro", "game",
            "menu_scene", "visibility"
        };

        static readonly Dictionary<string, Bag> Data = new Dictionary<string, Bag>();
        public static string Root { get; private set; }

        public static void LoadAll(string dataDirectory)
        {
            Data.Clear();
            Root = dataDirectory;
            foreach (var name in Tables)
            {
                var path = Path.Combine(dataDirectory, name + ".json");
                if (!File.Exists(path)) throw new FileNotFoundException("Missing data file " + path);
                var node = JsonNode.Parse(File.ReadAllText(path));
                if (node is not JsonObject obj) throw new InvalidDataException("Expected object in " + path);
                Data[name] = (Bag)FromNode(obj);
            }
        }

        public static bool IsLoaded => Data.Count > 0;

        public static Bag Table(string name)
        {
            if (!IsLoaded) throw new InvalidOperationException("Call Db.LoadAll before reading data.");
            return Data[name];
        }

        public static Bag Card(string id) => (Bag)Table("cards")[id];
        public static bool HasCard(string id) => Table("cards").Has(id);
        public static Bag Enemy(string id) => (Bag)Table("enemies")[id];
        public static Bag Species(string id) => (Bag)Table("species")[id];
        public static Bag Weather(string id) => (Bag)Table("weather")[id];
        public static Bag Tile(string id) => (Bag)Table("tiles")[id];
        public static Bag Growth() => Table("growth");
        public static List<object> StageOrder() => (List<object>)Table("stages")["order"];
        public static Bag Stage(string id) => (Bag)((Bag)Table("stages")["defs"])[id];
        public static Bag SpriteDef(string id) => Table("sprites").Get(id) as Bag ?? new Bag();
        public static Bag Item(string id) => (Bag)((Bag)Table("items")["items"])[id];
        public static Bag Nutrition() => Table("nutrition");
        public static Bag Facing() => Table("facing");
        public static Bag Theme(string id)
        {
            var t = Table("themes");
            return t.Get(id) as Bag ?? (Bag)t["jungle"];
        }

        public static List<string> ItemIds()
        {
            var items = (Bag)Table("items")["items"];
            return new List<string>(items.Keys);
        }

        public static Bag ItemSource(string src) => ((Bag)Table("items")["sources"]).Get(src) as Bag ?? new Bag();

        public static List<string> DraftCards(int tierMin, int tierMax)
        {
            var outIds = new List<string>();
            var cards = Table("cards");
            foreach (var id in cards.Keys)
            {
                var c = (Bag)cards[id];
                var rarity = J.S(c, "rarity");
                if (rarity == "starter" || rarity == "cave") continue;
                int t = J.I(c, "tier", 1);
                if (t >= tierMin && t <= tierMax) outIds.Add(id);
            }
            return outIds;
        }

        public static List<string> CaveCards()
        {
            var outIds = new List<string>();
            var cards = Table("cards");
            foreach (var id in cards.Keys)
                if (J.S((Bag)cards[id], "rarity") == "cave") outIds.Add(id);
            return outIds;
        }

        public static string Title() => J.S(Table("game"), "title", "Primal Instinct");
        public static string Tagline() => J.S(Table("game"), "tagline", "");
        public static string Version() => J.S(Table("game"), "version", "0.1.0");

        public static object FromNode(JsonNode n)
        {
            if (n == null) return null;
            if (n is JsonValue v)
            {
                if (v.TryGetValue<bool>(out var b)) return b;
                if (v.TryGetValue<string>(out var s)) return s;
                if (v.TryGetValue<int>(out var i)) return i;
                if (v.TryGetValue<long>(out var l))
                    return l >= int.MinValue && l <= int.MaxValue ? (object)(int)l : (float)l;
                if (v.TryGetValue<double>(out var d))
                {
                    if (Math.Abs(d - Math.Round(d)) < 1e-8 && d >= int.MinValue && d <= int.MaxValue)
                        return (int)Math.Round(d);
                    return (float)d;
                }
                return v.ToString();
            }
            if (n is JsonArray arr)
            {
                var list = new List<object>(arr.Count);
                foreach (var child in arr) list.Add(FromNode(child));
                return list;
            }
            if (n is JsonObject obj)
            {
                var bag = new Bag();
                foreach (var kv in obj) bag.Set(kv.Key, FromNode(kv.Value));
                return bag;
            }
            return null;
        }
    }
}
