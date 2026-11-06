using System;
using System.Collections.Generic;
using System.IO;
using NUnit.Framework;
using PrimalInstinct.Rules;

namespace PrimalInstinct.Rules.Tests
{
    public class RulesTests
    {
        static string DataDir()
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir != null)
            {
                var candidate = Path.Combine(dir.FullName, "Assets", "StreamingAssets", "data");
                if (Directory.Exists(candidate)) return candidate;
                dir = dir.Parent;
            }
            return Path.GetFullPath(Path.Combine("Assets", "StreamingAssets", "data"));
        }

        [OneTimeSetUp]
        public void Load()
        {
            if (!Db.IsLoaded) Db.LoadAll(DataDir());
        }

        [Test]
        public void Data_TitleCardsAndSpecies()
        {
            Assert.That(Db.Title(), Is.EqualTo("Primal Instinct"));
            Assert.That(Db.Table("cards").Count, Is.GreaterThanOrEqualTo(40));
            Assert.That(J.B(Db.Species("velociraptor"), "playable"));
            Assert.That(J.B(Db.Species("tyrannosaurus"), "playable"), Is.False);
            Assert.That(Db.Version(), Is.EqualTo("0.1.0"));
            Assert.That(J.F(Db.Tile("grass"), "evasion"), Is.EqualTo(0.25f).Within(0.001f));
            Assert.That(J.I(Db.Tile("water"), "move_cost"), Is.EqualTo(2));
        }

        [Test]
        public void Rng_IsDeterministic()
        {
            var a = new Rng();
            var b = new Rng();
            a.SetSeed(123456);
            b.SetSeed(123456);
            for (int i = 0; i < 20; i++)
            {
                Assert.That(b.Randi(), Is.EqualTo(a.Randi()));
                Assert.That(b.Randf(), Is.EqualTo(a.Randf()).Within(0.000001f));
                Assert.That(b.RandiRange(0, 7), Is.EqualTo(a.RandiRange(0, 7)));
            }
        }

        [Test]
        public void Mix_StaysPositive31Bit()
        {
            int h = RunState.SeedFromText("nest");
            Assert.That(h, Is.GreaterThan(0));
            Assert.That(RunState.Mix(1234, 77), Is.EqualTo(RunState.Mix(1234, 77)));
        }

        [Test]
        public void Facing_FrontSideBack()
        {
            Assert.That(Battle.RelativeDir(new V2(2, 0), new V2(0, 0), new V2(1, 0)), Is.EqualTo("front"));
            Assert.That(Battle.RelativeDir(new V2(-2, 0), new V2(0, 0), new V2(1, 0)), Is.EqualTo("back"));
            Assert.That(Battle.RelativeDir(new V2(0, 2), new V2(0, 0), new V2(1, 0)), Is.EqualTo("side"));
            Assert.That(Battle.QuarterTurns(new V2(1, 0), new V2(-1, 0)), Is.EqualTo(2));
            Assert.That(Battle.DirToward(new V2(0, 0), new V2(3, 1), new V2(0, 1)), Is.EqualTo(new V2(1, 0)));
        }

        [Test]
        public void Grid_WaterCostsTwoAndLosBlocked()
        {
            var g = new BGrid(6, 4);
            g.SetTile(new V2(2, 1), "water");
            g.SetTile(new V2(3, 1), "obstacle");
            Assert.That(g.MoveCost(new V2(2, 1), null), Is.EqualTo(2));
            var aquatic = new Dictionary<string, int> { { "water", 1 } };
            Assert.That(g.MoveCost(new V2(2, 1), aquatic), Is.EqualTo(1));
            Assert.That(g.Los(new V2(0, 1), new V2(5, 1)), Is.False);
            Assert.That(g.Los(new V2(0, 0), new V2(2, 0)), Is.True);
            var reach = g.ReachTiles(new V2(1, 1), 3, new Dictionary<V2, object>(), null);
            Assert.That(reach.Cost.ContainsKey(new V2(2, 1)));
            Assert.That(reach.Cost[new V2(2, 1)], Is.EqualTo(2));
        }

        [Test]
        public void Stage_IsDeterministicAndCoversRequiredRooms()
        {
            var run = RunState.Create("velociraptor", 4242);
            run.BeginStage(0);
            var again = RunState.Create("velociraptor", 4242);
            again.BeginStage(0);
            Assert.That(run.WeatherId(), Is.EqualTo(again.WeatherId()));
            Assert.That(Signature(run), Is.EqualTo(Signature(again)));
            var seen = new HashSet<string>();
            foreach (var step in (List<object>)run.Stage["steps"])
                foreach (var door in (List<object>)((Bag)step)["doors"])
                    seen.Add(J.S((Bag)door, "type"));
            Assert.That(seen, Does.Contain("boss"));
            Assert.That(seen, Does.Contain("elite"));
            Assert.That(((List<object>)run.Stage["steps"]).Count, Is.GreaterThanOrEqualTo(6));
        }

        static string Signature(RunState run)
        {
            var parts = new List<string>();
            foreach (var step in (List<object>)run.Stage["steps"])
                foreach (var door in (List<object>)((Bag)step)["doors"])
                {
                    var room = (Bag)door;
                    parts.Add(J.S(room, "type") + ":" + J.I(room, "seed"));
                }
            return string.Join("|", parts);
        }

        [Test]
        public void Hunger_DropsOnEnterAndStarvationHurts()
        {
            var run = RunState.Create("velociraptor", 7);
            run.BeginStage(0);
            int before = run.Hunger;
            var room = new Bag();
            room.Set("type", "battle");
            room.Set("step", 3);
            run.EnterRoom(room);
            Assert.That(run.Hunger, Is.LessThan(before));
            run.Hunger = 0;
            run.EnterRoom(room);
            Assert.That(run.Hp, Is.LessThan(run.MaxHp()));
        }

        [Test]
        public void Pounce_RefusesMelee()
        {
            var b = Duel("beetle");
            b.Phase = "player";
            b.Stamina = 5;
            b.Hand.Clear();
            b.Hand.Add("pounce");
            var enemy = b.AliveEnemies()[0];
            enemy.Pos = b.Player.Pos + new V2(1, 0);
            Assert.That(b.CardPlayable(0), Is.False);
            Assert.That(b.UnplayableReason(0), Does.Contain("Too close"));
        }

        [Test]
        public void TurnMeter_FastUnitActsMoreOften()
        {
            var b = Duel("beetle");
            b.Player.BaseSpeed = 30f;
            b.Enemies[0].BaseSpeed = 10f;
            b.Player.Meter = 0;
            b.Enemies[0].Meter = 0;
            int playerTurns = 0;
            foreach (var u in b.PreviewOrder(6)) if (u.IsPlayer) playerTurns++;
            Assert.That(playerTurns, Is.GreaterThanOrEqualTo(4));
        }

        [Test]
        public void Nutrition_EatPreviewsAndDoesNotPunishPoorDiet()
        {
            var run = RunState.Create("velociraptor", 3);
            run.BeginStage(0);
            var corpse = new Bag();
            corpse.Set("id", "beetle");
            corpse.Set("infected", false);
            corpse.Set("food", 12);
            corpse.Set("xp", 4);
            var prof = RunState.MealProfile("beetle", false);
            string fit = run.MealFitLabel(prof);
            Assert.That(fit, Is.Not.EqualTo(""));
            int hunger = run.Hunger;
            var ate = run.EatCorpse(corpse, "eat");
            Assert.That(run.Hunger, Is.GreaterThan(hunger));
            Assert.That(J.I(ate, "hunger"), Is.GreaterThan(0));
            Assert.That(run.XpBonus(), Is.GreaterThanOrEqualTo(0f));
        }

        [Test]
        public void Puzzle_RequiresTheSequence()
        {
            var room = new Bag();
            room.Set("sequence", new List<object> { 1, 0, 2 });
            room.Set("buttons", 4);
            room.Set("mistakes", 2);
            var p = SequencePuzzle.FromRoom(room);
            Assert.That(p.Press(1), Is.EqualTo("ok"));
            Assert.That(p.Press(3), Is.EqualTo("wrong"));
            Assert.That(p.Press(1), Is.EqualTo("ok"));
            Assert.That(p.Press(0), Is.EqualTo("ok"));
            Assert.That(p.Press(2), Is.EqualTo("done"));
        }

        [Test]
        public void Exits_AreOutsideTheGridOnDistinctSides()
        {
            var run = RunState.Create("velociraptor", 99);
            run.BeginStage(0);
            var room = run.CurrentStepDoors()[0];
            var battle = Battle.Create(run, room, "spotted");
            if (battle.Exits.Count == 0) Assert.Pass("Boss-less end room has no forward exits.");
            var sides = new HashSet<string>();
            foreach (var ex in battle.Exits)
            {
                var pos = (V2)ex["pos"];
                Assert.That(battle.Grid.InBounds(pos));
                Assert.That(pos.X == 0 || pos.Y == 0 || pos.X == battle.Grid.W - 1 || pos.Y == battle.Grid.H - 1);
                sides.Add(J.S(ex, "side"));
                foreach (var cell in ExitGen.Corridor(pos, J.S(ex, "side")))
                    Assert.That(battle.Grid.InBounds((V2)cell["tile"]), Is.False);
            }
            Assert.That(sides.Count, Is.EqualTo(battle.Exits.Count));
            Assert.That(J.S(battle.Exits[0], "side") == "NE" || J.S(battle.Exits[0], "side") == "NW");
        }

        [Test]
        public void TallGrass_EvasionIsSingleTargetOnly()
        {
            var b = Duel("shrew");
            b.Phase = "player";
            b.Grid.SetTile(b.Enemies[0].Pos, "grass");
            int dodges = 0;
            for (int i = 0; i < 40; i++)
            {
                b.Enemies[0].Hp = 50;
                b.Enemies[0].Alive = true;
                b.Hit(b.Enemies[0], 1, b.Player);
                if (b.LastDodged) dodges++;
            }
            Assert.That(dodges, Is.GreaterThan(0));
            int aoeDodges = 0;
            for (int i = 0; i < 20; i++)
            {
                b.Hit(b.Enemies[0], 1, b.Player, aoe: true);
                if (b.LastDodged) aoeDodges++;
            }
            Assert.That(aoeDodges, Is.EqualTo(0));
        }

        [Test]
        public void Fight_ResolvesAndGrowthChangesForm()
        {
            var b = Duel("beetle");
            string end = AutoPlayer.Play(b, 40);
            Assert.That(end, Is.EqualTo("won").Or.EqualTo("lost").Or.EqualTo("player"));
            var run = RunState.Create("velociraptor", 5);
            run.BeginStage(0);
            Assert.That(J.S(run.Form(), "id"), Is.EqualTo("baby"));
            run.GrantXp(500);
            Assert.That(run.Level, Is.GreaterThan(1));
            Assert.That(J.S(run.Form(), "id"), Is.Not.EqualTo("baby"));
        }

        [Test]
        public void Director_PlaysSeveralSeedsWithoutThrowing()
        {
            for (int seed = 11; seed <= 13; seed++)
            {
                var dir = new RunDirector { IntroEnabled = false };
                dir.StartRun("velociraptor", seed, null, "easy");
                dir.EnterStageBoard();
                int rooms = 0;
                while (dir.Screen != "gameover" && rooms < 14)
                {
                    rooms++;
                    if (dir.Screen == "stage_intro") { dir.EnterStageBoard(); continue; }
                    if (dir.Screen == "battle" && dir.Battle.Phase == "explore")
                    {
                        if (dir.Battle.Exits.Count == 0) break;
                        dir.TakeExit(0);
                        continue;
                    }
                    if (dir.Screen == "battle")
                    {
                        AutoPlayer.Play(dir.Battle, 50);
                        dir.OnBattleClosed();
                        continue;
                    }
                    if (dir.Screen == "reward")
                    {
                        while (dir.Corpses.Count > 0) dir.Eat(0, "eat");
                        dir.FinishReward();
                        continue;
                    }
                    if (dir.Screen == "draft") { dir.PickCard(dir.Offers[0]); continue; }
                    if (dir.Screen == "item") { dir.PickItem(dir.Offers[0]); continue; }
                    if (dir.Screen == "branch") { dir.PickBranch(""); continue; }
                    if (dir.Screen == "event") { dir.ChooseEvent(0); continue; }
                    if (dir.Screen == "event_result") { dir.ContinueAfterEvent(); continue; }
                    if (dir.Screen == "puzzle")
                    {
                        int guard = 0;
                        while (!dir.Puzzle.Finished && guard++ < 12)
                            dir.PuzzlePress(dir.Puzzle.Sequence[dir.Puzzle.Pos]);
                        continue;
                    }
                    break;
                }
                Assert.That(rooms, Is.GreaterThan(0));
            }
        }

        static Battle Duel(string enemy)
        {
            var run = RunState.Create("velociraptor", 70);
            run.Difficulty = "easy";
            run.BeginStage(0);
            var room = new Bag();
            room.Set("type", "battle");
            room.Set("seed", 99);
            room.Set("step", 2);
            room.Set("no_scale", true);
            room.Set("enemies", new List<object> { enemy });
            room.Set("infected", new List<object> { false });
            room.Set("unspotted_allowed", false);
            var spec = new Bag();
            spec.Set("w", 8);
            spec.Set("h", 6);
            spec.Set("shape", "rect");
            spec.Set("cut", V2.Zero);
            spec.Set("corner", 0);
            spec.Set("type", "battle");
            room.Set("arena_fixed", spec);
            var b = Battle.Create(run, room, "spotted");
            b.Begin();
            return b;
        }
    }
}
