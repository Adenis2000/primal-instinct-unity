using System.Collections.Generic;
using UnityEngine;
using PrimalInstinct.Rules;

namespace PrimalInstinct.Game
{
    /// <summary>Runtime recolour of the raptor, matching scripts/core/Look.gd (skin, pattern, cosmetic gender).</summary>
    public static class LookPaint
    {
        static readonly Dictionary<string, Sprite> Cache = new Dictionary<string, Sprite>();

        public static bool IsDefault(Bag look)
        {
            if (look == null) return true;
            return J.S(look, "skin", "classic") == "classic"
                && J.S(look, "pattern", "solid") == "solid"
                && J.S(look, "gender", "male") == "male";
        }

        public static Sprite Apply(Sprite src, string spriteId, Bag look)
        {
            if (src == null || look == null || IsDefault(look)) return src;
            string key = spriteId + "|" + J.S(look, "skin") + "|" + J.S(look, "pattern") + "|" + J.S(look, "pcolor") + "|" + J.S(look, "gender");
            if (Cache.TryGetValue(key, out var hit)) return hit;
            if (!src.texture.isReadable) return src;
            var tex = new Texture2D(src.texture.width, src.texture.height, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point };
            tex.SetPixels(src.texture.GetPixels());
            Paint(tex, spriteId, look);
            tex.Apply();
            var sprite = Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height), new Vector2(0.5f, 0.5f), 1f);
            Cache[key] = sprite;
            return sprite;
        }

        public static string Describe(Bag look)
        {
            string sid = J.S(look, "species", "velociraptor");
            var conf = J.Ob(Db.Table("customization"), sid);
            if (conf == null) return "";
            string skin = NameOf(conf, "skins", J.S(look, "skin", "classic"));
            string pat = NameOf(conf, "patterns", J.S(look, "pattern", "solid"));
            if (J.S(look, "pattern", "solid") != "solid")
                pat += " (" + NameOf(conf, "pcolors", J.S(look, "pcolor", "cream")) + ")";
            string gender = NameOf(conf, "genders", J.S(look, "gender", "male"));
            return skin + ", " + pat + ", " + gender;
        }

        static string NameOf(Bag conf, string group, string id)
        {
            foreach (var raw in J.Arr(conf, group))
                if (J.S((Bag)raw, "id") == id) return J.S((Bag)raw, "name", id);
            return id;
        }

        static Bag Option(Bag conf, string group, string id)
        {
            foreach (var raw in J.Arr(conf, group))
                if (J.S((Bag)raw, "id") == id) return (Bag)raw;
            return new Bag();
        }

        static Color Html(string hex)
        {
            if (string.IsNullOrEmpty(hex)) return new Color(0, 0, 0, 0);
            if (ColorUtility.TryParseHtmlString(hex, out var c)) return c;
            return new Color(0, 0, 0, 0);
        }

        static void Paint(Texture2D tex, string spriteId, Bag look)
        {
            string sid = J.S(look, "species", "velociraptor");
            var conf = J.Ob(Db.Table("customization"), sid);
            if (conf == null) return;
            var sd = J.Ob(J.Ob(conf, "sprites"), spriteId);
            if (sd == null) return;
            var skinOpt = Option(conf, "skins", J.S(look, "skin", "classic"));
            var pat = Option(conf, "patterns", J.S(look, "pattern", "solid"));
            var pcol = Option(conf, "pcolors", J.S(look, "pcolor", "cream"));
            var gen = Option(conf, "genders", J.S(look, "gender", "male"));
            Color skin = skinOpt.Get("color") == null ? new Color(0, 0, 0, 0) : Html(J.S(skinOpt, "color"));
            Color patCol = pcol.Get("color") == null ? skin : Html(J.S(pcol, "color"));
            bool classic = skin.a <= 0f;
            float tone = J.F(J.Ob(conf, "stage_tone"), J.S(sd, "stage"), 1f);
            if (J.S(sd, "mode") == "brown") tone = Mathf.Lerp(1f, tone, 0.5f);
            int seed = RunState.Mix(J.S(sd, "stage", "x").Length * 31, 7);
            int w = tex.width, h = tex.height;
            var px = tex.GetPixels();
            float bv = 0, bs = 0; int bn = 0;
            var role = new byte[px.Length];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int i = y * w + x;
                    var c = px[i];
                    if (c.a < 0.5f) continue;
                    int r = Region(c, h - 1 - y, h);
                    role[i] = (byte)r;
                    if (r == 1) { Color.RGBToHSV(c, out _, out float s, out float v); bv += v; bs += s; bn++; }
                }
            float vref = bv / Mathf.Max(1, bn);
            float sref = bs / Mathf.Max(1, bn);
            float stS = J.F(gen, "crest_sat", 1f), stV = J.F(gen, "crest_val", 1f), stL = J.F(gen, "crest_lift", 0f);
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int i = y * w + x;
                    int r = role[i];
                    if (r == 0) continue;
                    var c = px[i];
                    Color.RGBToHSV(c, out float h01, out float s, out float v);
                    if (r == 2)
                    {
                        if (classic && Mathf.Approximately(stS, 1f) && Mathf.Approximately(stV, 1f) && stL == 0f) continue;
                        Color o = c;
                        if (!classic)
                        {
                            Color.RGBToHSV(skin, out float sh, out float ss, out float sv);
                            o = Color.HSVToRGB(sh, Mathf.Clamp01(ss * 0.42f), Mathf.Clamp(v * (0.55f + 0.6f * sv) * tone, 0.05f, 1f));
                            o.a = c.a;
                        }
                        Color.RGBToHSV(o, out h01, out s, out v);
                        o = Color.HSVToRGB(h01, Mathf.Clamp01(s * stS), Mathf.Clamp01(v * stV + stL * v));
                        o.a = c.a;
                        px[i] = o;
                        continue;
                    }
                    if (r == 3)
                    {
                        if (!classic)
                        {
                            Color.RGBToHSV(skin, out float sh, out float ss, out float sv);
                            var o = Color.HSVToRGB(sh, Mathf.Clamp01(ss * 0.42f), Mathf.Clamp((0.55f + 0.45f * sv) * 0.92f * tone, 0.05f, 1f));
                            o.a = c.a;
                            px[i] = o;
                        }
                        continue;
                    }
                    bool usePat = J.S(pat, "kind", "none") != "none" && PatternHit(pat, x, h - 1 - y, seed);
                    if (classic && !usePat) continue;
                    Color target = usePat ? patCol : skin;
                    Color.RGBToHSV(target, out float th, out float ts, out float tv);
                    float ratio = v / Mathf.Max(0.05f, vref);
                    float nv = Mathf.Clamp(tv * ratio * tone, 0.02f, 1f);
                    float ns = Mathf.Clamp(ts * (s / Mathf.Max(0.05f, sref)), 0f, 1f);
                    Color.RGBToHSV(patCol, out _, out float ps, out _);
                    if (usePat && ps < 0.2f) ns = ts;
                    var painted = Color.HSVToRGB(th, ns, nv);
                    painted.a = c.a;
                    px[i] = painted;
                }
            tex.SetPixels(px);
        }

        static int Region(Color c, int y, int h)
        {
            Color.RGBToHSV(c, out float h01, out float s, out float v);
            float hue = h01 * 360f;
            if (v < 0.17f) return 0;
            if (v >= 0.7f && s >= 0.74f && hue >= 15f && hue <= 55f) return 0;
            if (s < 0.34f && v < 0.58f)
            {
                if (y > (int)(h * 0.84f)) return 0;
                return 2;
            }
            if (hue >= 215f && hue <= 300f && v < 0.6f) return 2;
            if (v >= 0.7f && s >= 0.25f && s <= 0.66f && hue >= 24f && hue <= 48f) return 3;
            if ((hue <= 40f || hue >= 340f) && s >= 0.3f) return 1;
            return 0;
        }

        static bool PatternHit(Bag pat, int x, int y, int seed)
        {
            string kind = J.S(pat, "kind", "none");
            if (kind == "stripes")
            {
                int period = Mathf.Max(1, J.I(pat, "period", 6));
                return J.PosMod(x + (y >> 1) + seed % period, period) < J.I(pat, "width", 2);
            }
            if (kind == "spots")
            {
                int cell = Mathf.Max(3, J.I(pat, "cell", 5));
                int cx = x / cell, cy = y / cell;
                int hh = RunState.Mix(RunState.Mix(cx * 7 + 3 + seed, cy * 13 + 5), 17);
                if ((J.PosMod(hh, 100) / 100f) >= J.F(pat, "density", 0.75f)) return false;
                float px = cx * cell + 1f + J.PosMod(hh >> 7, cell - 2);
                float py = cy * cell + 1f + J.PosMod(hh >> 13, cell - 2);
                float dx = x + 0.5f - px, dy = y + 0.5f - py;
                return Mathf.Sqrt(dx * dx + dy * dy) <= J.F(pat, "radius", 1.7f);
            }
            if (kind == "mottled")
            {
                int cell = Mathf.Max(1, J.I(pat, "cell", 2));
                int hv = RunState.Mix(RunState.Mix((x / cell) * 11 + seed, (y / cell) * 5 + 9), 29);
                return J.PosMod(hv, 100) / 100f < J.F(pat, "density", 0.36f);
            }
            return false;
        }
    }
}
