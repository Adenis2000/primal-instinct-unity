using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace PrimalInstinct.Game
{
    /// <summary>
    /// Sprites load from Resources/Sprites (imported, point-filtered).
    /// A file in StreamingAssets/sprite_overrides with the same name replaces it at play time.
    /// </summary>
    public static class SpriteBank
    {
        static readonly Dictionary<string, Sprite> Cache = new Dictionary<string, Sprite>();
        static bool _loaded;

        public static void Ensure()
        {
            if (_loaded) return;
            _loaded = true;
            foreach (var s in Resources.LoadAll<Sprite>("Sprites"))
                if (s != null && !Cache.ContainsKey(s.name)) Cache[s.name] = s;
        }

        public static Sprite Get(string name)
        {
            if (string.IsNullOrEmpty(name)) return null;
            Ensure();
            if (Cache.TryGetValue(name, out var cached) && cached != null) return cached;
            var over = Override(name);
            if (over != null) { Cache[name] = over; return over; }
            var fromRes = Resources.Load<Sprite>("Sprites/" + name);
            if (fromRes != null) Cache[name] = fromRes;
            return fromRes;
        }

        public static Sprite Facing(string id, PrimalInstinct.Rules.V2 facing)
        {
            string suffix = "";
            if (facing.X == 0 && facing.Y == 1) suffix = "_sw";
            else if (facing.X == -1 && facing.Y == 0) suffix = "_nw";
            else if (facing.X == 0 && facing.Y == -1) suffix = "_b";
            return Get(id + suffix) ?? Get(id);
        }

        static Sprite Override(string name)
        {
            string path = Path.Combine(Application.streamingAssetsPath, "sprite_overrides", name + ".png");
            if (!File.Exists(path)) return null;
            var tex = new Texture2D(2, 2, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            if (!tex.LoadImage(File.ReadAllBytes(path))) return null;
            tex.name = name;
            return Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height), new Vector2(0.5f, 0.5f), 1f);
        }

        public static void ClearOverride(string name) => Cache.Remove(name);
    }
}
