using System;
using System.Collections.Generic;
using System.Numerics;

namespace PrimalInstinct.Rules
{
    /// <summary>Grid cell. +X is south-east on screen, +Y is south-west. Matches Godot Vector2i.</summary>
    public readonly struct V2 : IEquatable<V2>
    {
        public readonly int X;
        public readonly int Y;
        public V2(int x, int y) { X = x; Y = y; }
        public static V2 operator +(V2 a, V2 b) => new V2(a.X + b.X, a.Y + b.Y);
        public static V2 operator -(V2 a, V2 b) => new V2(a.X - b.X, a.Y - b.Y);
        public static V2 operator *(V2 a, int k) => new V2(a.X * k, a.Y * k);
        public static bool operator ==(V2 a, V2 b) => a.X == b.X && a.Y == b.Y;
        public static bool operator !=(V2 a, V2 b) => !(a == b);
        public bool Equals(V2 other) => this == other;
        public override bool Equals(object obj) => obj is V2 v && Equals(v);
        public override int GetHashCode() => (X * 73856093) ^ (Y * 19349663);
        public override string ToString() => "(" + X + "," + Y + ")";
        public static readonly V2 Zero = new V2(0, 0);
        public static readonly V2 None = new V2(-1, -1);
        public static int Dist(V2 a, V2 b) => Math.Abs(a.X - b.X) + Math.Abs(a.Y - b.Y);
    }

    /// <summary>Godot 4 RandomNumberGenerator (PCG32). Same seed produces the same draws as Godot 4.</summary>
    public sealed class Rng
    {
        const ulong DefaultInc = 1442695040888963407UL;
        const ulong Mult = 6364136223846793005UL;
        ulong _state;
        ulong _inc = DefaultInc;
        ulong _seed;

        public Rng() { SetSeed(12047754176567800795UL); }

        public ulong Seed => _seed;

        public void SetSeed(long seed) => SetSeed(unchecked((ulong)seed));

        public void SetSeed(ulong seed)
        {
            _seed = seed;
            _state = 0;
            _inc = (DefaultInc << 1) | 1UL;
            Step();
            _state += seed;
            Step();
        }

        public void Randomize() => SetSeed((ulong)DateTime.UtcNow.Ticks * 6364136223846793005UL + DefaultInc);

        uint Step()
        {
            ulong old = _state;
            _state = old * Mult + (_inc | 1UL);
            uint xorshifted = (uint)(((old >> 18) ^ old) >> 27);
            int rot = (int)(old >> 59);
            return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
        }

        public uint Randi() => Step();

        uint Bounded(uint bound)
        {
            if (bound == 0) return 0;
            uint threshold = (uint)(-bound % bound);
            while (true)
            {
                uint r = Step();
                if (r >= threshold) return r % bound;
            }
        }

        public int RandiRange(int from, int to)
        {
            if (from == to) return from;
            int lo = Math.Min(from, to);
            uint span = (uint)Math.Abs(from - to) + 1U;
            return (int)Bounded(span) + lo;
        }

        public float Randf()
        {
            uint proto = Step();
            if (proto == 0) return 0f;
            int clz = BitOperations.LeadingZeroCount(proto);
            uint sig = Step() | 0x80000001u;
            return MathF.ScaleB((float)sig, -32 - clz);
        }

        public int RandIndex(int count) => count <= 0 ? 0 : (int)(Randi() % (uint)count);
    }

    /// <summary>Ordered JSON object. Key order matches the file, which weighted picks depend on.</summary>
    public sealed class Bag
    {
        readonly List<string> _order = new List<string>();
        readonly Dictionary<string, object> _map = new Dictionary<string, object>();

        public int Count => _order.Count;
        public IReadOnlyList<string> Keys => _order;
        public bool Has(string key) => _map.ContainsKey(key);

        public object this[string key]
        {
            get => _map[key];
            set => Set(key, value);
        }

        public void Set(string key, object value)
        {
            if (!_map.ContainsKey(key)) _order.Add(key);
            _map[key] = value;
        }

        public void Remove(string key)
        {
            if (_map.Remove(key)) _order.Remove(key);
        }

        public object Get(string key, object fallback = null) => _map.TryGetValue(key, out var v) ? v : fallback;

        public Bag Clone()
        {
            var b = new Bag();
            foreach (var k in _order) b.Set(k, CloneValue(_map[k]));
            return b;
        }

        public static object CloneValue(object v)
        {
            if (v is Bag b) return b.Clone();
            if (v is List<object> list)
            {
                var copy = new List<object>(list.Count);
                foreach (var item in list) copy.Add(CloneValue(item));
                return copy;
            }
            return v;
        }
    }

    public static class J
    {
        public static int I(object v, int d = 0)
        {
            if (v == null) return d;
            if (v is int i) return i;
            if (v is long l) return (int)l;
            if (v is float f) return (int)f;
            if (v is double n) return (int)n;
            if (v is bool b) return b ? 1 : 0;
            if (v is string s && int.TryParse(s, out var p)) return p;
            return d;
        }

        public static float F(object v, float d = 0f)
        {
            if (v == null) return d;
            if (v is float f) return f;
            if (v is double n) return (float)n;
            if (v is int i) return i;
            if (v is long l) return l;
            if (v is string s && float.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var p)) return p;
            return d;
        }

        public static bool B(object v, bool d = false)
        {
            if (v == null) return d;
            if (v is bool b) return b;
            if (v is int i) return i != 0;
            if (v is float f) return f != 0f;
            if (v is string s) return s == "true";
            return d;
        }

        public static string S(object v, string d = "") => v == null ? d : v.ToString();

        public static int I(Bag b, string key, int d = 0) => b != null && b.Has(key) ? I(b.Get(key), d) : d;
        public static float F(Bag b, string key, float d = 0f) => b != null && b.Has(key) ? F(b.Get(key), d) : d;
        public static bool B(Bag b, string key, bool d = false) => b != null && b.Has(key) ? B(b.Get(key), d) : d;
        public static string S(Bag b, string key, string d = "") => b != null && b.Has(key) ? S(b.Get(key), d) : d;
        public static Bag Ob(Bag b, string key) => b != null && b.Get(key) is Bag child ? child : null;
        public static List<object> Arr(Bag b, string key)
        {
            if (b != null && b.Get(key) is List<object> list) return list;
            return new List<object>();
        }

        public static int Round(float v) => (int)MathF.Round(v, MidpointRounding.AwayFromZero);
        public static int Ceil(float v) => (int)MathF.Ceiling(v);
        public static int Floor(float v) => (int)MathF.Floor(v);
        public static int Clamp(int v, int lo, int hi) => Math.Max(lo, Math.Min(hi, v));
        public static float Clamp(float v, float lo, float hi) => MathF.Max(lo, MathF.Min(hi, v));
        public static int PosMod(int a, int m)
        {
            int r = a % m;
            return r < 0 ? r + m : r;
        }
        public static int Sign(int v) => v < 0 ? -1 : (v > 0 ? 1 : 0);

        public static string Weighted(Rng rng, Bag weights)
        {
            if (weights == null || weights.Count == 0) return null;
            float total = 0f;
            foreach (var k in weights.Keys) total += F(weights.Get(k));
            if (total <= 0f) return null;
            float r = rng.Randf() * total;
            string last = null;
            foreach (var k in weights.Keys)
            {
                last = k;
                r -= F(weights.Get(k));
                if (r <= 0f) return k;
            }
            return last;
        }

        public static T Weighted<T>(Rng rng, IReadOnlyList<(T key, float w)> items)
        {
            if (items == null || items.Count == 0) return default;
            float total = 0f;
            foreach (var it in items) total += it.w;
            if (total <= 0f) return items[items.Count - 1].key;
            float r = rng.Randf() * total;
            T last = items[items.Count - 1].key;
            foreach (var it in items)
            {
                last = it.key;
                r -= it.w;
                if (r <= 0f) return it.key;
            }
            return last;
        }
    }
}
