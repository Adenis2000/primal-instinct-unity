using UnityEngine;
using PrimalInstinct.Rules;

namespace PrimalInstinct.Game
{
    /// <summary>2:1 isometric projection. Grid logic stays square; only drawing and picking use this.</summary>
    public static class IsoMath
    {
        public const float BaseTw = 32f;
        public const float BaseTh = 16f;
        public static float Zoom = 2f;
        public static Vector2 Origin = new Vector2(320f, 40f);

        public static void SetZoom(float z)
        {
            Zoom = z;
        }

        public static Vector2 BoardSize(int w, int h, float z)
        {
            return new Vector2((w + h) * BaseTw * 0.5f * z, (w + h) * BaseTh * 0.5f * z);
        }

        public static float AutoZoom(int w, int h)
        {
            var cam = (Bag)Db.Table("arenas")["camera"];
            var view = (System.Collections.Generic.List<object>)cam["view"];
            float vw = J.F(view[2]), vh = J.F(view[3]);
            var steps = (System.Collections.Generic.List<object>)cam["zoom_steps"];
            foreach (var step in steps)
            {
                var bs = BoardSize(w, h, J.F(step));
                if (bs.x <= vw && bs.y <= vh) return J.F(step);
            }
            return J.F(steps[steps.Count - 1]);
        }

        public static float MinZoom(int w, int h)
        {
            var cam = (Bag)Db.Table("arenas")["camera"];
            var view = (System.Collections.Generic.List<object>)cam["view"];
            float margin = 1f + J.F(cam, "zoom_out_margin", 0.12f);
            float vw = J.F(view[2]), vh = J.F(view[3]);
            var steps = (System.Collections.Generic.List<object>)cam["zoom_steps"];
            float best = J.F(steps[steps.Count - 1]);
            foreach (var step in steps)
            {
                var bs = BoardSize(w, h, J.F(step)) * margin;
                if (bs.x <= vw && bs.y <= vh) return J.F(step);
            }
            return best;
        }

        public static void Fit(int w, int h, float z = 0f)
        {
            var cam = (Bag)Db.Table("arenas")["camera"];
            var view = (System.Collections.Generic.List<object>)cam["view"];
            if (z <= 0f) z = AutoZoom(w, h);
            SetZoom(z);
            float cx = J.F(view[0]) + J.F(view[2]) * 0.5f;
            float cy = J.F(view[1]) + J.F(view[3]) * 0.5f;
            Origin = new Vector2(
                Mathf.Round(cx - (w - h) * BaseTw * z * 0.25f),
                Mathf.Round(cy - (w + h) * BaseTh * z * 0.25f));
        }

        public static Vector2 ToScreen(float gx, float gy)
        {
            float tw = BaseTw * Zoom, th = BaseTh * Zoom;
            return Origin + new Vector2((gx - gy) * tw * 0.5f, (gx + gy) * th * 0.5f);
        }

        public static Vector2 ToGrid(Vector2 screen)
        {
            float tw = BaseTw * Zoom * 0.5f, th = BaseTh * Zoom * 0.5f;
            float a = (screen.x - Origin.x) / tw;
            float b = (screen.y - Origin.y) / th;
            return new Vector2((a + b) * 0.5f, (b - a) * 0.5f);
        }

        public static Vector2 Center(V2 p) => ToScreen(p.X + 0.5f, p.Y + 0.5f);

        public static V2 TileAt(Vector2 screen)
        {
            var g = ToGrid(screen);
            return new V2(Mathf.FloorToInt(g.x), Mathf.FloorToInt(g.y));
        }
    }
}
