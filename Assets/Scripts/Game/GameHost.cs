using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using PrimalInstinct.Rules;

namespace PrimalInstinct.Game
{
    /// <summary>Playable shell: menu, egg, customize, cutscene, stage intro, board, rewards and the other rooms.</summary>
    public sealed class GameHost : MonoBehaviour
    {
        public const int NativeW = 640;
        public const int NativeH = 360;

        RunDirector _dir;
        Font _font;
        Font _title;
        RectTransform _root;
        Canvas _canvas;
        Transform _world;
        readonly Dictionary<string, GameObject> _pages = new Dictionary<string, GameObject>();
        int _selectedCard = -1;
        bool _moveMode;
        string _hover = "";
        float _cutT;
        int _cutShot;
        float _introT;
        V2 _hoverTile = V2.None;
        string _builtKey = "";
        float _zoom;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (FindAnyObjectByType<GameHost>() != null) return;
            var go = new GameObject("Primal Instinct");
            go.AddComponent<GameHost>();
        }

        void Awake()
        {
            if (FindObjectsByType<GameHost>(FindObjectsSortMode.None).Length > 1)
            {
                Destroy(gameObject);
                return;
            }
            if (!Db.IsLoaded)
            {
                string dir = System.IO.Path.Combine(Application.streamingAssetsPath, "data");
                Db.LoadAll(dir);
            }
            _font = Resources.Load<Font>("Fonts/Jersey15-Regular") ?? Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            _title = Resources.Load<Font>("Fonts/Jersey25-Regular") ?? _font;
            _dir = new RunDirector();
            _dir.PixelPerfect = PlayerPrefs.GetInt("pi_pixel", 1) == 1;
            _dir.IntroMode = PlayerPrefs.GetString("pi_intro", "first");
            _dir.SeenIntro = PlayerPrefs.GetInt("pi_seen_intro", 0) == 1;
            _dir.IntroEnabled = _dir.IntroMode != "off";
            _dir.Save.Set("difficulty", PlayerPrefs.GetString("pi_diff", "normal"));
            EnsureCamera();
            EnsureEvents();
            BuildCanvas();
            Show("menu");
        }

        void EnsureCamera()
        {
            var cam = Camera.main;
            if (cam == null)
            {
                var go = new GameObject("Main Camera");
                cam = go.AddComponent<Camera>();
                go.tag = "MainCamera";
            }
            cam.orthographic = true;
            cam.orthographicSize = 180f;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.05f, 0.07f, 0.06f);
            cam.nearClipPlane = -50f;
            cam.farClipPlane = 50f;
            _world = new GameObject("Board").transform;
        }

        void EnsureEvents()
        {
            if (FindAnyObjectByType<EventSystem>() == null)
            {
                var es = new GameObject("EventSystem");
                es.AddComponent<EventSystem>();
                es.AddComponent<StandaloneInputModule>();
            }
        }

        void BuildCanvas()
        {
            var canvasGo = new GameObject("Canvas");
            _canvas = canvasGo.AddComponent<Canvas>();
            _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvasGo.AddComponent<GraphicRaycaster>();
            var scaler = canvasGo.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ConstantPixelSize;
            _root = NewRect("Native", canvasGo.transform);
            _root.anchorMin = _root.anchorMax = new Vector2(0.5f, 0.5f);
            _root.sizeDelta = new Vector2(NativeW, NativeH);
            foreach (var name in new[] { "menu", "egg", "customize", "cutscene", "stage_intro", "battle", "overlay" })
            {
                var page = NewRect(name, _root).gameObject;
                var img = page.AddComponent<Image>();
                img.color = new Color(0, 0, 0, 0);
                img.raycastTarget = name != "battle";
                Stretch(page.GetComponent<RectTransform>());
                _pages[name] = page;
            }
        }

        void Update()
        {
            ApplyPixelScale();
            if (_dir.Screen == "cutscene") TickCutscene();
            if (_dir.Screen == "stage_intro") TickIntro();
            if (_dir.Screen == "battle") BattleInput();
        }

        void ApplyPixelScale()
        {
            float scale = _dir.PixelPerfect
                ? Mathf.Max(1, Mathf.Min(Screen.width / NativeW, Screen.height / NativeH))
                : Mathf.Max(1f, Mathf.Min(Screen.width / (float)NativeW, Screen.height / (float)NativeH));
            _root.localScale = new Vector3(scale, scale, 1f);
            var cam = Camera.main;
            if (cam == null) return;
            float vw = NativeW * scale, vh = NativeH * scale;
            cam.pixelRect = new Rect((Screen.width - vw) * 0.5f, (Screen.height - vh) * 0.5f, vw, vh);
            cam.orthographicSize = NativeH * 0.5f;
        }

        public void Show(string screen)
        {
            _dir.Screen = screen;
            bool overlay = OverlayOpen();
            foreach (var kv in _pages) kv.Value.SetActive(false);
            if (screen == "gameover")
            {
                _pages["overlay"].SetActive(true);
                BuildGameOver();
                return;
            }
            if (overlay)
            {
                if (_dir.Run != null && _dir.Battle != null) _pages["battle"].SetActive(true);
                else _pages["menu"].SetActive(screen == "settings");
                _pages["overlay"].SetActive(true);
                Clear(_pages["overlay"].transform);
                BuildOverlay();
                return;
            }
            string pageName = _pages.ContainsKey(screen) ? screen : "menu";
            _pages[pageName].SetActive(true);
            Clear(_pages[pageName].transform);
            _pages["overlay"].SetActive(false);
            _builtKey = "";
            switch (screen)
            {
                case "menu": BuildMenu(); break;
                case "egg": BuildEgg(); break;
                case "customize": BuildCustomize(); break;
                case "cutscene": BuildCutscene(); break;
                case "stage_intro": BuildStageIntro(); break;
                case "battle": BuildBattleChrome(); RefreshBoard(true); break;
            }
        }

        bool OverlayOpen()
        {
            switch (_dir.Screen)
            {
                case "reward":
                case "draft":
                case "item":
                case "branch":
                case "event":
                case "event_result":
                case "puzzle":
                case "settings":
                case "deck":
                case "gameover":
                    return true;
                default: return false;
            }
        }

        void BuildMenu()
        {
            var page = _pages["menu"].transform;
            Backdrop(page, "bg_jungle_0");
            Label(page, Db.Title(), 18, 28, 604, 48, 30, "#f0c050", _title, TextAnchor.MiddleCenter);
            Label(page, Db.Tagline(), 40, 74, 560, 24, 15, "#e8f0f8", _font, TextAnchor.MiddleCenter);
            Button(page, "Play", 262, 150, 116, 28, () => Show("egg"));
            Button(page, "Settings", 262, 186, 116, 28, OpenSettings);
            Button(page, "Quit", 262, 222, 116, 28, Quit);
            Label(page, "Pines by @kianamosser", 8, 330, 300, 18, 15, "#8fa4b8", _font, TextAnchor.LowerLeft);
            Label(page, "v" + Db.Version(), 440, 330, 190, 18, 15, "#8fa4b8", _font, TextAnchor.LowerRight);
        }

        void BuildEgg()
        {
            var page = _pages["egg"].transform;
            Backdrop(page, "bg_egg_nest");
            Label(page, "Choose an egg", 20, 16, 400, 28, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            Button(page, "Main menu", 8, 8, 110, 22, () => Show("menu"));
            int x = 36;
            foreach (var id in Db.Table("species").Keys)
            {
                if (id.StartsWith("_")) continue;
                var sp = Db.Species(id);
                bool playable = J.B(sp, "playable");
                string sprite = playable ? "egg_raptor" : "egg_locked";
                var icon = Image(page, sprite, x, 70, 64, 72);
                var captured = id;
                Button(page, J.S(sp, "name"), x - 10, 150, 100, 36, () =>
                {
                    if (!playable) return;
                    int seed = _dir.Save.Has("last_seed") ? J.I(_dir.Save, "last_seed") : 0;
                    var field = page.Find("SeedField");
                    if (field != null)
                    {
                        var input = field.GetComponent<InputField>();
                        if (input != null && input.text.Trim().Length > 0) seed = RunState.SeedFromText(input.text);
                    }
                    string diff = J.S(_dir.Save, "difficulty", "normal");
                    _dir.StartRun(captured, seed, DefaultLook(captured), diff);
                    Show("customize");
                });
                if (!playable) Label(page, "Locked", x, 190, 80, 18, 15, "#8fa4b8", _font, TextAnchor.MiddleCenter);
                x += 140;
            }
            Label(page, "Seed", 36, 230, 80, 20, 15, "#e8f0f8", _font, TextAnchor.MiddleLeft);
            var seedGo = NewRect("SeedField", page);
            Place(seedGo, 100, 226, 180, 26);
            var seedImg = seedGo.gameObject.AddComponent<Image>();
            seedImg.color = new Color(0.08f, 0.1f, 0.12f, 0.9f);
            var inputGo = NewRect("Text", seedGo);
            Stretch(inputGo);
            var text = inputGo.gameObject.AddComponent<Text>();
            text.font = _font;
            text.fontSize = 15;
            text.color = Hex("#e8f0f8");
            text.supportRichText = false;
            var input = seedGo.gameObject.AddComponent<InputField>();
            input.textComponent = text;
            input.text = PlayerPrefs.GetString("pi_seed", "");
            Label(page, "Difficulty", 300, 230, 120, 20, 15, "#e8f0f8", _font, TextAnchor.MiddleLeft);
            int dx = 300;
            foreach (var level in ((Bag)Db.Table("difficulty")["levels"]).Keys)
            {
                string captured = level;
                Button(page, captured, dx, 254, 90, 24, () =>
                {
                    _dir.Save.Set("difficulty", captured);
                    PlayerPrefs.SetString("pi_diff", captured);
                });
                dx += 96;
            }
            Label(page, "Only the Velociraptor is playable. The other eggs are placeholders.", 36, 300, 560, 36, 15, "#8fa4b8", _font, TextAnchor.UpperLeft);
        }

        static Bag DefaultLook(string species)
        {
            var look = new Bag();
            look.Set("species", species);
            var conf = J.Ob(Db.Table("customization"), species);
            var defs = conf != null ? J.Ob(conf, "defaults") : null;
            look.Set("skin", J.S(defs, "skin", "classic"));
            look.Set("pattern", J.S(defs, "pattern", "solid"));
            look.Set("pcolor", J.S(defs, "pcolor", "cream"));
            look.Set("gender", J.S(defs, "gender", "male"));
            return look;
        }

        void BuildCustomize()
        {
            var page = _pages["customize"].transform;
            Backdrop(page, "bg_customize");
            Label(page, "Hatchling", 16, 8, 300, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            var look = _dir.Run.Look;
            Image(page, "egg_raptor", 40, 50, 80, 90);
            var portrait = Image(page, "portrait_" + J.S(_dir.Run.Form(), "id"), 140, 48, 48, 48);
            if (portrait != null && portrait.sprite != null)
                portrait.sprite = LookPaint.Apply(portrait.sprite, "portrait_" + J.S(_dir.Run.Form(), "id"), look);
            Label(page, LookPaint.Describe(look), 200, 56, 400, 40, 15, "#e8f0f8", _font, TextAnchor.UpperLeft);
            float y = 120;
            AddOptions(page, "Skin", "skins", "skin", y); y += 48;
            AddOptions(page, "Pattern", "patterns", "pattern", y); y += 48;
            AddOptions(page, "Pattern colour", "pcolors", "pcolor", y); y += 48;
            AddOptions(page, "Gender (cosmetic)", "genders", "gender", y);
            Button(page, "Random", 16, 320, 100, 26, () =>
            {
                var rng = new Rng();
                rng.Randomize();
                var conf = J.Ob(Db.Table("customization"), _dir.Run.SpeciesId);
                foreach (var group in new[] { "skins", "patterns", "pcolors", "genders" })
                {
                    var opts = J.Arr(conf, group);
                    if (opts.Count == 0) continue;
                    string key = group == "skins" ? "skin" : group == "patterns" ? "pattern" : group == "pcolors" ? "pcolor" : "gender";
                    _dir.Run.Look.Set(key, J.S((Bag)opts[rng.RandIndex(opts.Count)], "id"));
                }
                Show("customize");
            });
            Button(page, "Hatch", 500, 320, 120, 26, () =>
            {
                PlayerPrefs.SetInt("pi_seen_intro", 1);
                string next = _dir.AfterCustomize();
                if (next == "cutscene") { _cutShot = 0; _cutT = 0; }
                _introT = 0;
                Show(next);
            });
        }

        void AddOptions(Transform page, string title, string group, string key, float y)
        {
            Label(page, title, 16, y, 140, 20, 15, "#f0c050", _font, TextAnchor.MiddleLeft);
            var conf = J.Ob(Db.Table("customization"), _dir.Run.SpeciesId);
            float x = 150;
            foreach (var raw in J.Arr(conf, group))
            {
                var opt = (Bag)raw;
                string id = J.S(opt, "id");
                bool on = J.S(_dir.Run.Look, key) == id;
                string capturedKey = key;
                string capturedId = id;
                Button(page, J.S(opt, "name"), x, y, 110, 22, () =>
                {
                    _dir.Run.Look.Set(capturedKey, capturedId);
                    Show("customize");
                });
                if (on) Label(page, "*", x - 10, y, 12, 20, 15, "#f0c050", _font, TextAnchor.MiddleCenter);
                x += 116;
                if (x > 520) { x = 150; y += 24; }
            }
        }

        void BuildCutscene()
        {
            var page = _pages["cutscene"].transform;
            var shots = (List<object>)Db.Table("cutscene_intro")["shots"];
            if (_cutShot >= shots.Count) { _introT = 0; Show("stage_intro"); return; }
            var shot = (Bag)shots[_cutShot];
            string img = "bg_customize";
            foreach (var layer in J.Arr(shot, "layers"))
            {
                var l = (Bag)layer;
                if (l.Has("img")) { img = J.S(l, "img"); break; }
            }
            Backdrop(page, img);
            var caps = J.Arr(shot, "captions");
            string text = caps.Count > 0 ? J.S((Bag)caps[0], "text") : J.S(shot, "name");
            Label(page, text, 40, 280, 560, 48, 15, "#e8f0f8", _font, TextAnchor.MiddleCenter);
            Label(page, "Hold Esc or click Skip", 240, 330, 160, 18, 15, "#8fa4b8", _font, TextAnchor.MiddleCenter);
            Button(page, "Skip", 520, 8, 100, 24, () => { _introT = 0; Show("stage_intro"); });
        }

        void TickCutscene()
        {
            _cutT += Time.deltaTime;
            if (Input.GetKey(KeyCode.Escape) && _cutT > 0.6f) { _introT = 0; Show("stage_intro"); return; }
            var shots = (List<object>)Db.Table("cutscene_intro")["shots"];
            if (_cutShot >= shots.Count) return;
            float dur = J.F((Bag)shots[_cutShot], "dur", 4f);
            if (_cutT > dur) { _cutShot++; _cutT = 0; Show("cutscene"); }
        }

        void BuildStageIntro()
        {
            var page = _pages["stage_intro"].transform;
            string theme = J.S(_dir.Run.Stage, "theme", "jungle");
            Backdrop(page, "bg_" + theme + "_0");
            var def = _dir.Run.StageDef();
            Label(page, J.S(def, "name"), 20, 120, 600, 40, 30, "#f0c050", _title, TextAnchor.MiddleCenter);
            string weather = _dir.Run.WeatherId();
            string wname = weather == "" ? "" : J.S(Db.Weather(weather), "name");
            Label(page, wname, 20, 170, 600, 28, 20, "#e8f0f8", _font, TextAnchor.MiddleCenter);
            var lines = WeatherSys.Describe(weather, _dir.Run.Tags());
            Label(page, string.Join("\n", lines), 80, 210, 480, 60, 15, "#e8f0f8", _font, TextAnchor.UpperCenter);
            Button(page, "Continue", 250, 300, 140, 26, () => { _dir.EnterStageBoard(); _zoom = 0; Show("battle"); });
        }

        void TickIntro()
        {
            _introT += Time.deltaTime;
            if (_introT > 4f || Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.Return))
            {
                _dir.EnterStageBoard();
                _zoom = 0;
                Show("battle");
            }
        }

        void BuildBattleChrome()
        {
            var page = _pages["battle"].transform;
            var theme = _dir.Battle != null ? _dir.Battle.ThemeId : "jungle";
            Backdrop(page, "bg_" + theme + "_0");
            var topLeft = NewRect("TurnOrder", page);
            Place(topLeft, 4, 4, 220, 70);
            var topRight = NewRect("PlayerHud", page);
            Place(topRight, 430, 2, 206, 86);
            var hand = NewRect("Hand", page);
            Place(hand, 70, 268, 420, 88);
            var actions = NewRect("Actions", page);
            Place(actions, 500, 250, 132, 104);
            var log = NewRect("Log", page);
            Place(log, 4, 200, 220, 60);
            Button(page, "Deck", 4, 332, 64, 22, () => { _dir.Screen = "deck"; Show("battle"); });
        }

        void RefreshBoard(bool rebuild)
        {
            var b = _dir.Battle;
            if (b == null) return;
            string key = b.Phase + ":" + b.TurnNo + ":" + b.Player.Pos + ":" + b.Hand.Count + ":" + b.Stamina + ":" + b.Mp;
            if (!rebuild && key == _builtKey) return;
            _builtKey = key;
            if (_zoom <= 0f) _zoom = IsoMath.AutoZoom(b.Grid.W, b.Grid.H);
            float min = IsoMath.MinZoom(b.Grid.W, b.Grid.H);
            float max = J.F(((List<object>)((Bag)Db.Table("arenas")["camera"])["zoom_steps"])[0]);
            _zoom = Mathf.Clamp(_zoom, Mathf.Min(min, max), Mathf.Max(min, max));
            IsoMath.Fit(b.Grid.W, b.Grid.H, _zoom);
            for (int i = _world.childCount - 1; i >= 0; i--) Destroy(_world.GetChild(i).gameObject);
            DrawTerrain(b);
            DrawUnits(b);
            RefreshHud(b);
            RefreshHand(b);
            RefreshActions(b);
            MaybeHint(b);
        }

        void DrawTerrain(Battle b)
        {
            var theme = Db.Theme(b.ThemeId);
            for (int y = 0; y < b.Grid.H; y++)
                for (int x = 0; x < b.Grid.W; x++)
                {
                    var p = new V2(x, y);
                    string tile = b.Grid.GetTile(p);
                    if (tile == "void") continue;
                    string name = TileName(b.ThemeId, tile, b.Grid.Variant[y, x], theme);
                    PlaceSprite(name, IsoMath.Center(p), (x + y) * 10, 1f);
                }
            bool open = b.ExitsVisible();
            var exitCells = new HashSet<V2>();
            if (open)
            {
                int width = J.I(J.Ob(Db.Table("visibility"), "exit_path"), "width", 3);
                int length = J.I(J.Ob(Db.Table("visibility"), "exit_path"), "length", 6);
                foreach (var ex in b.Exits)
                    foreach (var cell in ExitGen.Corridor((V2)ex["pos"], J.S(ex, "side"), width, length))
                        exitCells.Add((V2)cell["tile"]);
            }
            float borderA = J.F(Db.Table("visibility"), "border_alpha", 0.42f);
            float behindA = J.F(Db.Table("visibility"), "border_behind_alpha", 0.28f);
            for (int y = -6; y < b.Grid.H + 6; y++)
                for (int x = -6; x < b.Grid.W + 6; x++)
                {
                    var p = new V2(x, y);
                    if (b.Grid.InBounds(p) && !b.Grid.IsVoid(p)) continue;
                    if (exitCells.Contains(p))
                    {
                        PlaceSprite(TileName(b.ThemeId, "ground", (x * 3 + y) & 3, theme), IsoMath.Center(p), (x + y) * 10, 1f);
                        continue;
                    }
                    if (((x + y) & 3) == 0) continue;
                    string tree = ((x * 5 + y) & 1) == 0 ? "tree_pine_0" + (1 + Mathf.Abs(x + y) % 2 * 2) : "deco_tree_0" + (1 + Mathf.Abs(y) % 9);
                    bool nearUnit = false;
                    foreach (var u in b.Units)
                        if (u.Alive && V2.Dist(u.Pos, p) <= 2) nearUnit = true;
                    PlaceSprite(tree, IsoMath.Center(p), (x + y) * 10 + 5, nearUnit ? behindA : (b.Grid.InBounds(new V2(Mathf.Clamp(x, 0, b.Grid.W - 1), Mathf.Clamp(y, 0, b.Grid.H - 1))) ? borderA : 1f));
                }
            if (b.Secret != V2.None)
            {
                string crack = open || b.Phase == "explore" || b.Phase == "won" ? "secret_hole" : "secret_crack";
                PlaceSprite(SpriteBank.Get(crack) != null ? crack : "bd_cave_stone_0", IsoMath.Center(b.Secret), (b.Secret.X + b.Secret.Y) * 10 + 3, 1f);
            }
        }

        static string TileName(string theme, string tile, int variant, Bag th)
        {
            if (tile == "grass") return "tile_" + theme + "_tall_" + Mod(variant, J.I(th, "tall_variants", 1));
            if (tile == "water") return "tile_" + theme + "_water_" + Mod(variant, J.I(th, "water_variants", 1)) + "_0";
            if (tile == "obstacle") return "prop_" + theme + "_obstacle_" + Mod(variant, J.I(th, "obstacle_variants", 1));
            var pool = J.Arr(th, "ground_pool");
            int g = Mathf.Max(1, J.I(th, "ground_variants", 1));
            int idx = pool.Count > 0 ? J.I(pool[Mod(variant, pool.Count)]) : variant;
            return "tile_" + theme + "_ground_" + Mod(idx, g);
        }

        static int Mod(int v, int m) { m = Mathf.Max(1, m); int r = v % m; return r < 0 ? r + m : r; }

        void DrawUnits(Battle b)
        {
            foreach (var u in b.Units)
            {
                if (!u.Alive) continue;
                var sprite = SpriteBank.Facing(u.SpriteId, u.Facing);
                if (u.IsPlayer) sprite = LookPaint.Apply(sprite, u.SpriteId, _dir.Run.Look);
                var pos = IsoMath.Center(u.Pos);
                PlaceSprite(sprite, pos + new Vector2(0f, 6f), (u.Pos.X + u.Pos.Y) * 10 + 8, u.Aware || u.IsPlayer ? 1f : 0.85f);
                if (!u.IsPlayer)
                {
                    var intent = b.IntentOf(u);
                    if (intent.Count > 0)
                    {
                        string mark = u.State == "idle" ? "?" : (J.I(intent, "dmg") > 0 ? J.I(intent, "dmg").ToString() : J.S(intent, "label"));
                        WorldLabel(mark, pos + new Vector2(0, 18), u.State == "spotted" ? "#ffb0a0" : "#c8c8c8");
                    }
                }
            }
            if (_moveMode)
                foreach (var kv in b.ReachableTiles())
                    if (kv.Key != b.Player.Pos)
                        PlaceSprite("icon_drop", IsoMath.Center(kv.Key), (kv.Key.X + kv.Key.Y) * 10 + 6, 0.8f);
        }

        void PlaceSprite(string name, Vector2 godot, int order, float alpha)
        {
            PlaceSprite(SpriteBank.Get(name), godot, order, alpha);
        }

        void PlaceSprite(Sprite sprite, Vector2 godot, int order, float alpha)
        {
            if (sprite == null) return;
            var go = new GameObject(sprite.name);
            go.transform.SetParent(_world, false);
            var sr = go.AddComponent<SpriteRenderer>();
            sr.sprite = sprite;
            sr.sortingOrder = order;
            var c = sr.color; c.a = alpha; sr.color = c;
            go.transform.position = GodotToWorld(godot);
        }

        void WorldLabel(string text, Vector2 godot, string color)
        {
            var go = new GameObject("mark");
            go.transform.SetParent(_world, false);
            var tm = go.AddComponent<TextMesh>();
            tm.text = text;
            tm.font = _font;
            tm.fontSize = 32;
            tm.characterSize = 0.4f;
            tm.anchor = TextAnchor.MiddleCenter;
            tm.color = Hex(color);
            go.transform.position = GodotToWorld(godot);
        }

        static Vector3 GodotToWorld(Vector2 s) => new Vector3(s.x - 320f, 180f - s.y, 0f);

        void RefreshHud(Battle b)
        {
            var page = _pages["battle"].transform;
            var hud = page.Find("PlayerHud");
            var order = page.Find("TurnOrder");
            var log = page.Find("Log");
            Clear(hud);
            Clear(order);
            Clear(log);
            var portraitId = "portrait_" + J.S(_dir.Run.Form(), "id");
            var img = Image(hud, portraitId, 150, 0, 48, 48);
            if (img != null && img.sprite != null) img.sprite = LookPaint.Apply(img.sprite, portraitId, _dir.Run.Look);
            if (img != null) img.color = Color.white;
            Label(hud, _dir.Run.Form().Get("name") + "  Lv" + _dir.Run.Level, 0, 0, 150, 16, 15, "#f0c050", _font, TextAnchor.MiddleLeft);
            Label(hud, "HP " + b.Player.Hp + "/" + b.Player.MaxHp, 0, 18, 150, 16, 15, "#e8f0f8", _font, TextAnchor.MiddleLeft);
            Label(hud, "STA " + b.Stamina + "/" + Mathf.Max(1, b.StaminaMax) + "  MV " + b.Mp, 0, 34, 160, 16, 15, "#e8f0f8", _font, TextAnchor.MiddleLeft);
            Label(hud, "Hunger " + _dir.Run.Hunger + "  " + _dir.Run.DietQuality(), 0, 50, 200, 16, 15, "#e8a060", _font, TextAnchor.MiddleLeft);
            string weather = _dir.Run.WeatherId();
            if (weather != "") Image(hud, J.S(Db.Weather(weather), "icon"), 0, 66, 16, 16);
            var turns = b.Phase == "explore" ? new List<BUnit>() : b.PreviewOrder(5);
            string line = "";
            foreach (var u in turns) line += (u.IsPlayer ? "You" : u.DisplayName) + "  ";
            if (b.Phase == "ambush") line = "Unseen";
            if (b.Phase == "explore") line = "Choose a path";
            Label(order, line, 0, 0, 220, 32, 15, "#e8f0f8", _font, TextAnchor.UpperLeft);
            string stage = J.S(_dir.Run.StageDef(), "name");
            Label(order, stage, 0, 34, 220, 18, 15, "#8fa4b8", _font, TextAnchor.UpperLeft);
            string last = b.Lines.Count > 0 ? b.Lines[b.Lines.Count - 1] : "";
            if (b.Lines.Count > 1) last = b.Lines[b.Lines.Count - 2] + "\n" + last;
            Label(log, last, 0, 0, 220, 60, 15, "#e8f0f8", _font, TextAnchor.LowerLeft);
        }

        void RefreshHand(Battle b)
        {
            var hand = _pages["battle"].transform.Find("Hand");
            Clear(hand);
            if (b.Phase != "player" && b.Phase != "ambush") return;
            for (int i = 0; i < b.Hand.Count; i++)
            {
                var card = Db.Card(b.Hand[i]);
                int index = i;
                var btn = Button(hand, J.S(card, "name"), 4 + i * 82, 8, 78, 72, () => SelectCard(index));
                var colors = btn.colors;
                bool playable = b.Phase == "player" && b.CardPlayable(i);
                colors.normalColor = i == _selectedCard ? Hex("#f0c050") : (playable ? Color.white : new Color(0.55f, 0.55f, 0.55f));
                btn.colors = colors;
                var art = Image(btn.transform, "card_" + b.Hand[i], 8, 4, 40, 24);
                if (art == null || art.sprite == null) Image(btn.transform, J.S(card, "icon"), 8, 4, 16, 16);
                Label(btn.transform, J.I(card, "cost").ToString(), 52, 2, 22, 16, 15, "#f0c050", _font, TextAnchor.MiddleCenter);
            }
        }

        void RefreshActions(Battle b)
        {
            var actions = _pages["battle"].transform.Find("Actions");
            Clear(actions);
            if (b.Phase == "player" || b.Phase == "ambush" || b.Phase == "explore")
            {
                Button(actions, _moveMode ? "Moving" : "Move", 0, 0, 120, 24, ToggleMove);
                if (b.Phase == "player") Button(actions, "End turn", 0, 28, 120, 24, () => { _moveMode = false; _selectedCard = -1; b.EndPlayerTurn(); AfterAct(); });
                if (b.Phase == "ambush") Button(actions, "Wait", 0, 28, 120, 24, () => { b.SkipAmbush(); AfterAct(); });
            }
            Label(actions, b.Phase, 0, 58, 120, 18, 15, "#8fa4b8", _font, TextAnchor.MiddleLeft);
        }

        void SelectCard(int index)
        {
            if (_dir.Battle.Phase != "player") return;
            _selectedCard = _selectedCard == index ? -1 : index;
            _moveMode = false;
            _hover = _selectedCard >= 0 ? _dir.Battle.UnplayableReason(_selectedCard) : "";
            if (_hover == "" && _selectedCard >= 0) _hover = J.S(_dir.Battle.CardAt(_selectedCard), "text");
            RefreshBoard(true);
            ShowHover();
        }

        void ShowHover()
        {
            var page = _pages["battle"].transform;
            var old = page.Find("HoverCard");
            if (old != null) Destroy(old.gameObject);
            if (_selectedCard < 0 || _dir.Battle == null) return;
            var card = _dir.Battle.CardAt(_selectedCard);
            var box = NewRect("HoverCard", page);
            Place(box, 180, 70, 280, 120);
            var img = box.gameObject.AddComponent<Image>();
            img.color = new Color(0.08f, 0.12f, 0.16f, 0.92f);
            Label(box, J.S(card, "name"), 8, 6, 260, 22, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            string why = _dir.Battle.UnplayableReason(_selectedCard);
            string body = J.S(card, "text");
            if (why != "") body += "\nCan't play: " + why;
            Label(box, body, 8, 32, 264, 80, 15, "#e8f0f8", _font, TextAnchor.UpperLeft);
        }

        void ToggleMove()
        {
            _moveMode = !_moveMode;
            _selectedCard = -1;
            if (_moveMode && _dir.Battle != null && !_dir.Battle.CanStillMove())
            {
                _moveMode = false;
                _hover = "Out of moves";
            }
            RefreshBoard(true);
        }

        void BattleInput()
        {
            var b = _dir.Battle;
            if (b == null) return;
            if (Input.mouseScrollDelta.y != 0f)
            {
                _zoom = Mathf.Max(0.1f, _zoom) + (Input.mouseScrollDelta.y > 0 ? 1f : -1f);
                RefreshBoard(true);
            }
            for (int i = 0; i < 9; i++)
                if (Input.GetKeyDown(KeyCode.Alpha1 + i) && i < b.Hand.Count) SelectCard(i);
            if (Input.GetKeyDown(KeyCode.M)) ToggleMove();
            if (Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.E))
            {
                if (b.Phase == "player") { b.EndPlayerTurn(); _moveMode = false; AfterAct(); }
            }
            if (Input.GetKeyDown(KeyCode.Escape)) { _selectedCard = -1; _moveMode = false; RefreshBoard(true); }
            if (!Input.GetMouseButtonDown(0) || EventSystem.current != null && EventSystem.current.IsPointerOverGameObject()) return;
            var godot = MouseGodot();
            var tile = IsoMath.TileAt(godot);
            if (b.Phase == "explore" || (b.Phase == "ambush" && b.ExitsVisible()))
            {
                int exit = ExitUnder(b, tile);
                if (exit >= 0)
                {
                    if (b.Phase == "ambush") { _dir.SneakOut(); Show(_dir.Screen); return; }
                    _dir.TakeExit(exit);
                    _zoom = 0;
                    Show(_dir.Screen == "battle" ? "battle" : _dir.Screen);
                    return;
                }
                if (b.Phase == "explore" && tile == b.Secret) { _dir.EnterSecret(); _zoom = 0; Show("battle"); return; }
            }
            if (b.Phase == "ambush")
            {
                foreach (var e in b.AmbushTargets())
                    if (e.Pos == tile) { b.AmbushStrike(e); AfterAct(); return; }
            }
            if (_moveMode && (b.Phase == "player" || b.Phase == "ambush" || b.Phase == "explore"))
            {
                if (b.MovePlayer(tile))
                {
                    if (!b.CanStillMove()) _moveMode = false;
                    if (b.Phase == "explore" && b.ExitAt(b.Player.Pos) >= 0) { _dir.TakeExit(b.ExitAt(b.Player.Pos)); Show(_dir.Screen); return; }
                    if (b.Phase == "ambush" && b.ExitAt(b.Player.Pos) >= 0 && b.ExitsVisible()) { _dir.SneakOut(); Show(_dir.Screen); return; }
                    AfterAct();
                }
                return;
            }
            if (_selectedCard >= 0 && b.Phase == "player")
            {
                var card = b.CardAt(_selectedCard);
                string target = J.S(card, "target");
                bool played = false;
                if (target == "enemy")
                {
                    foreach (var e in b.AliveEnemies())
                        if (e.Pos == tile) played = b.PlayCard(_selectedCard, e);
                }
                else if (target == "tile") played = b.PlayCard(_selectedCard, tile);
                else played = b.PlayCard(_selectedCard, null);
                if (played) { _selectedCard = -1; AfterAct(); }
            }
            else if (b.Phase == "player" || b.Phase == "ambush" || b.Phase == "explore")
                b.FacePlayerToward(tile);
            RefreshBoard(true);
        }

        int ExitUnder(Battle b, V2 tile)
        {
            int direct = b.ExitAt(tile);
            if (direct >= 0) return direct;
            int width = J.I(J.Ob(Db.Table("visibility"), "exit_path"), "width", 3);
            int length = J.I(J.Ob(Db.Table("visibility"), "exit_path"), "length", 6);
            for (int i = 0; i < b.Exits.Count; i++)
                foreach (var cell in ExitGen.Corridor((V2)b.Exits[i]["pos"], J.S(b.Exits[i], "side"), width, length))
                    if ((V2)cell["tile"] == tile) return i;
            return -1;
        }

        Vector2 MouseGodot()
        {
            RectTransformUtility.ScreenPointToLocalPointInRectangle(_root, Input.mousePosition, null, out var local);
            return new Vector2(local.x + NativeW * 0.5f, NativeH * 0.5f - local.y);
        }

        void AfterAct()
        {
            var b = _dir.Battle;
            if (b.Phase == "won" || b.Phase == "lost")
            {
                _dir.OnBattleClosed();
                Show(_dir.Screen == "battle" ? "battle" : _dir.Screen);
                if (OverlayOpen()) { _pages["overlay"].SetActive(true); BuildOverlay(); }
                return;
            }
            RefreshBoard(true);
        }

        void BuildOverlay()
        {
            var page = _pages["overlay"].transform;
            Clear(page);
            var dim = page.gameObject.GetComponent<Image>();
            if (dim == null) dim = page.gameObject.AddComponent<Image>();
            dim.color = new Color(0, 0, 0, 0.45f);
            dim.raycastTarget = true;
            switch (_dir.Screen)
            {
                case "reward": BuildReward(page); break;
                case "draft": BuildDraft(page); break;
                case "item": BuildItems(page); break;
                case "branch": BuildBranch(page); break;
                case "event":
                case "event_result": BuildEvent(page); break;
                case "puzzle": BuildPuzzle(page); break;
                case "settings": BuildSettings(page); break;
                case "deck": BuildDeck(page); break;
                case "gameover": BuildGameOver(); break;
            }
        }

        void BuildReward(Transform page)
        {
            Panel(page, 70, 30, 500, 300);
            Label(page, "Encounter cleared", 90, 40, 400, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            float y = 74;
            if (_dir.Corpses.Count == 0)
            {
                Label(page, "Nothing left to eat.", 90, y, 400, 20, 15, "#e8f0f8", _font, TextAnchor.MiddleLeft);
                Button(page, "Continue", 400, 280, 140, 26, () => { _dir.FinishReward(); AdvanceFlow(); });
                return;
            }
            for (int i = 0; i < _dir.Corpses.Count; i++)
            {
                var c = _dir.Corpses[i];
                var prof = RunState.MealProfile(J.S(c, "id"), J.B(c, "infected"));
                string fit = _dir.Run.MealFitLabel(prof);
                string after = _dir.Run.QualityAfter(prof, "eat");
                Label(page, J.S(c, "name", J.S(c, "id")) + "  " + fit + "  diet " + after + "  food " + J.I(c, "food"), 90, y, 340, 32, 15, "#e8f0f8", _font, TextAnchor.MiddleLeft);
                int index = i;
                Button(page, "Eat", 430, y, 60, 24, () => { _dir.Eat(index, "eat"); Show("reward"); });
                Button(page, "Skip", 496, y, 60, 24, () => { _dir.SkipCorpse(index); Show("reward"); });
                y += 36;
            }
        }

        void BuildDraft(Transform page)
        {
            Panel(page, 40, 40, 560, 270);
            Label(page, _dir.DraftMode == "evolution" ? "Evolution draft" : "Take a card", 60, 50, 400, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            float x = 60;
            foreach (var id in _dir.Offers)
            {
                var card = Db.Card(id);
                string captured = id;
                Button(page, J.S(card, "name") + "\n" + J.S(card, "text"), x, 90, 160, 160, () => { _dir.PickCard(captured); AdvanceFlow(); });
                x += 176;
            }
        }

        void BuildItems(Transform page)
        {
            Panel(page, 40, 40, 560, 270);
            Label(page, "Found supplies", 60, 50, 400, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            float y = 90;
            foreach (var id in _dir.Offers)
            {
                var item = Db.Item(id);
                string captured = id;
                Button(page, J.S(item, "name") + "  " + J.S(item, "text"), 60, y, 500, 36, () => { _dir.PickItem(captured); AdvanceFlow(); });
                y += 42;
            }
        }

        void BuildBranch(Transform page)
        {
            Panel(page, 40, 30, 560, 300);
            Label(page, "Growth", 60, 40, 400, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            Button(page, "Steady Growth\nAlways available.", 60, 80, 240, 64, () => { _dir.PickBranch(""); AdvanceFlow(); });
            float y = 156;
            foreach (var b in _dir.Run.BranchOptions(_dir.BranchTier))
            {
                bool open = J.B(b, "unlocked");
                string captured = J.S(b, "id");
                string progress = "";
                foreach (var p in J.Arr(b, "progress"))
                    progress += J.S((Bag)p, "label") + " " + J.F((Bag)p, "have").ToString("0") + "/" + J.F((Bag)p, "need").ToString("0") + "  ";
                Button(page, J.S(b, "name") + (open ? "" : " (locked)") + "\n" + progress, 60, y, 500, 40, () =>
                {
                    if (!open) return;
                    _dir.PickBranch(captured);
                    AdvanceFlow();
                });
                y += 46;
            }
        }

        void BuildEvent(Transform page)
        {
            Panel(page, 50, 40, 540, 280);
            bool forage = J.S(_dir.Room, "type") == "forage";
            Bag ev = null;
            if (!forage && _dir.Room.Has("event_id"))
                ev = (Bag)((Bag)Db.Table("events")["events"])[J.S(_dir.Room, "event_id")];
            Label(page, ev != null ? J.S(ev, "name") : "Forage", 70, 50, 480, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            if (_dir.Screen == "event_result")
            {
                Label(page, _dir.PendingText + "\n" + string.Join("\n", _dir.Notes), 70, 90, 480, 140, 15, "#e8f0f8", _font, TextAnchor.UpperLeft);
                Button(page, "Continue", 400, 250, 140, 26, () => { _dir.ContinueAfterEvent(); AdvanceFlow(); });
                return;
            }
            if (ev != null) Label(page, J.S(ev, "text"), 70, 80, 480, 70, 15, "#e8f0f8", _font, TextAnchor.UpperLeft);
            float y = 160;
            int count = forage ? ((List<object>)_dir.Room["forage_ids"]).Count : ((List<object>)ev["choices"]).Count;
            for (int i = 0; i < count; i++)
            {
                var choice = _dir.EventChoice(i);
                int index = i;
                Button(page, J.S(choice, "label", J.S(choice, "name")), 70, y, 480, 28, () => { _dir.ChooseEvent(index); AdvanceFlow(); });
                y += 34;
            }
        }

        void BuildPuzzle(Transform page)
        {
            Panel(page, 80, 60, 480, 240);
            var pd = (Bag)Db.Table("puzzles")[J.S(_dir.Room, "puzzle_id", "stone_sequence")];
            Label(page, J.S(pd, "name"), 100, 70, 440, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            Label(page, J.S(pd, "intro"), 100, 100, 440, 50, 15, "#e8f0f8", _font, TextAnchor.UpperLeft);
            string shown = "";
            for (int i = 0; i < _dir.Puzzle.Sequence.Count; i++)
                shown += (i == _dir.Puzzle.Pos ? "[" : "") + (_dir.Puzzle.Sequence[i] + 1) + (i == _dir.Puzzle.Pos ? "]" : "") + " ";
            Label(page, _dir.Puzzle.Finished ? (_dir.Puzzle.Success ? "Solved" : "Failed") : shown, 100, 150, 440, 24, 15, "#f0c050", _font, TextAnchor.MiddleLeft);
            for (int i = 0; i < _dir.Puzzle.Buttons; i++)
            {
                int n = i;
                Button(page, (i + 1).ToString(), 100 + i * 70, 190, 60, 36, () =>
                {
                    string r = _dir.PuzzlePress(n);
                    if (r == "done" || r == "fail") AdvanceFlow();
                    else Show("puzzle");
                });
            }
        }

        void BuildDeck(Transform page)
        {
            Panel(page, 40, 30, 560, 300);
            Label(page, "Deck", 60, 40, 200, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            var counts = new Dictionary<string, int>();
            foreach (var id in _dir.Run.Deck) counts[id] = counts.TryGetValue(id, out int n) ? n + 1 : 1;
            float y = 74;
            foreach (var kv in counts)
            {
                Label(page, kv.Value + "  " + J.S(Db.Card(kv.Key), "name"), 60, y, 400, 18, 15, "#e8f0f8", _font, TextAnchor.MiddleLeft);
                y += 18;
            }
            Button(page, "Close", 460, 280, 110, 26, () => { _dir.Screen = "battle"; Show("battle"); });
        }

        void BuildSettings(Transform page)
        {
            Panel(page, 140, 50, 360, 250);
            Label(page, "Settings", 160, 60, 300, 24, 20, "#f0c050", _title, TextAnchor.MiddleLeft);
            Button(page, "Pixel Perfect: " + (_dir.PixelPerfect ? "On" : "Off"), 170, 100, 280, 26, () =>
            {
                _dir.PixelPerfect = !_dir.PixelPerfect;
                PlayerPrefs.SetInt("pi_pixel", _dir.PixelPerfect ? 1 : 0);
                Show("settings");
            });
            Button(page, "Fullscreen", 170, 136, 280, 26, () => Screen.fullScreen = !Screen.fullScreen);
            Button(page, "Intro: " + _dir.IntroMode, 170, 172, 280, 26, () =>
            {
                _dir.IntroMode = _dir.IntroMode == "always" ? "first" : _dir.IntroMode == "first" ? "off" : "always";
                _dir.IntroEnabled = _dir.IntroMode != "off";
                PlayerPrefs.SetString("pi_intro", _dir.IntroMode);
                Show("settings");
            });
            Label(page, "Volume is saved. This build has no audio clips.", 170, 210, 300, 36, 15, "#8fa4b8", _font, TextAnchor.UpperLeft);
            Button(page, "Close", 170, 252, 120, 26, () => Show(_dir.Run == null ? "menu" : "battle"));
        }

        void OpenSettings()
        {
            _dir.Screen = "settings";
            foreach (var kv in _pages) kv.Value.SetActive(kv.Key == "menu" || kv.Key == "overlay");
            _pages["overlay"].SetActive(true);
            BuildOverlay();
        }

        void BuildGameOver()
        {
            var page = _pages["overlay"].transform;
            Clear(page);
            page.gameObject.SetActive(true);
            var dim = page.gameObject.GetComponent<Image>() ?? page.gameObject.AddComponent<Image>();
            dim.color = new Color(0, 0, 0, 0.55f);
            Panel(page, 120, 70, 400, 210);
            bool win = _dir.Run != null && _dir.Run.Victory;
            Label(page, win ? "You lived" : "Back to the egg", 140, 86, 360, 28, 20, "#f0c050", _title, TextAnchor.MiddleCenter);
            string cause = _dir.Run == null ? "" : (_dir.Run.Victory ? "The frozen verge is quiet." : _dir.Run.Cause);
            Label(page, cause, 140, 124, 360, 40, 15, "#e8f0f8", _font, TextAnchor.UpperCenter);
            Button(page, "Return to the egg", 200, 180, 240, 26, () => { _dir.EndRun(); Show("egg"); });
            Button(page, "Main menu", 200, 216, 240, 26, () => { _dir.EndRun(); Show("menu"); });
        }

        void AdvanceFlow()
        {
            if (_dir.Screen == "gameover") { BuildGameOver(); return; }
            if (_dir.Screen == "battle" || _dir.Screen == "stage_intro") { _zoom = 0; Show(_dir.Screen); return; }
            if (OverlayOpen())
            {
                _pages["battle"].SetActive(true);
                _pages["overlay"].SetActive(true);
                BuildOverlay();
                return;
            }
            Show(_dir.Screen);
        }

        void MaybeHint(Battle b)
        {
            if (!J.B(_dir.Save, "hints_enabled", true)) return;
            var seen = _dir.Save.Get("hints_seen") as Bag ?? new Bag();
            string id = b.Phase == "ambush" ? "ambush" : b.Phase == "explore" ? "exits" : "welcome";
            if (seen.Has(id)) return;
            var hints = (Bag)Db.Table("hints")["hints"];
            if (!hints.Has(id)) return;
            var h = (Bag)hints[id];
            var page = _pages["battle"].transform;
            var box = NewRect("Hint", page);
            Place(box, 16, 250, 360, 70);
            var img = box.gameObject.AddComponent<Image>();
            img.color = new Color(0.08f, 0.1f, 0.12f, 0.92f);
            Label(box, J.S(h, "title"), 8, 4, 340, 18, 15, "#f0c050", _font, TextAnchor.MiddleLeft);
            Label(box, J.S(h, "text"), 8, 22, 340, 28, 15, "#e8f0f8", _font, TextAnchor.UpperLeft);
            Button(box, "OK", 280, 44, 64, 20, () => { seen.Set(id, true); _dir.Save.Set("hints_seen", seen); RefreshBoard(true); });
        }

        void Quit()
        {
#if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
#else
            Application.Quit();
#endif
        }

        void Backdrop(Transform page, string sprite)
        {
            var img = Image(page, sprite, 0, 0, NativeW, NativeH);
            if (img == null) return;
            img.color = new Color(1, 1, 1, 0.55f);
            img.raycastTarget = false;
        }

        void Panel(Transform parent, float x, float y, float w, float h)
        {
            var rt = NewRect("Panel", parent);
            Place(rt, x, y, w, h);
            var img = rt.gameObject.AddComponent<Image>();
            img.color = new Color(0.08f, 0.12f, 0.16f, 0.94f);
        }

        Text Label(Transform parent, object text, float x, float y, float w, float h, int size, string color, Font font, TextAnchor align)
        {
            var rt = NewRect("Label", parent);
            Place(rt, x, y, w, h);
            var t = rt.gameObject.AddComponent<Text>();
            t.font = font;
            t.fontSize = Mathf.Max(15, size);
            t.color = Hex(color);
            t.alignment = align;
            t.horizontalOverflow = HorizontalWrapMode.Wrap;
            t.verticalOverflow = VerticalWrapMode.Truncate;
            t.text = text == null ? "" : text.ToString();
            t.raycastTarget = false;
            return t;
        }

        Button Button(Transform parent, string text, float x, float y, float w, float h, UnityEngine.Events.UnityAction click)
        {
            var prefab = Resources.Load<GameObject>("Prefabs/UiButton");
            if (prefab != null)
            {
                var go = Object.Instantiate(prefab, parent);
                go.name = "Button";
                var rtPrefab = go.GetComponent<RectTransform>();
                Place(rtPrefab, x, y, w, h);
                var label = go.GetComponentInChildren<Text>();
                if (label != null)
                {
                    label.font = _font;
                    label.fontSize = 15;
                    label.text = text;
                    label.color = Hex("#1a140c");
                }
                var skinned = go.GetComponent<Image>();
                var skin = SpriteBank.Get("ui_btn");
                if (skinned != null && skin != null) skinned.sprite = skin;
                var btnPrefab = go.GetComponent<Button>();
                btnPrefab.onClick.AddListener(click);
                return btnPrefab;
            }
            var rt = NewRect("Button", parent);
            Place(rt, x, y, w, h);
            var img = rt.gameObject.AddComponent<Image>();
            var fallbackSkin = SpriteBank.Get("ui_btn");
            if (fallbackSkin != null) { img.sprite = fallbackSkin; img.type = Image.Type.Simple; }
            img.color = Color.white;
            var btn = rt.gameObject.AddComponent<Button>();
            btn.targetGraphic = img;
            btn.onClick.AddListener(click);
            var label = Label(rt, text, 4, 2, w - 8, h - 4, 15, "#1a140c", _font, TextAnchor.MiddleCenter);
            label.raycastTarget = false;
            return btn;
        }

        Image Image(Transform parent, string spriteName, float x, float y, float w, float h)
        {
            var sprite = SpriteBank.Get(spriteName);
            var rt = NewRect(spriteName ?? "img", parent);
            Place(rt, x, y, w, h);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = sprite;
            img.preserveAspect = true;
            img.raycastTarget = false;
            if (sprite == null) img.color = new Color(1, 1, 1, 0);
            return img;
        }

        static RectTransform NewRect(string name, Transform parent)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            return go.AddComponent<RectTransform>();
        }

        static void Place(RectTransform rt, float x, float y, float w, float h)
        {
            rt.anchorMin = rt.anchorMax = new Vector2(0f, 1f);
            rt.pivot = new Vector2(0f, 1f);
            rt.anchoredPosition = new Vector2(x, -y);
            rt.sizeDelta = new Vector2(w, h);
        }

        static void Stretch(RectTransform rt)
        {
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero;
            rt.offsetMax = Vector2.zero;
        }

        static void Clear(Transform t)
        {
            for (int i = t.childCount - 1; i >= 0; i--) Destroy(t.GetChild(i).gameObject);
        }

        static Color Hex(string html)
        {
            if (ColorUtility.TryParseHtmlString(html, out var c)) return c;
            return Color.white;
        }
    }
}
