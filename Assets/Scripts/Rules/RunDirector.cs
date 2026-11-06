using System;
using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    /// <summary>Screen flow shared by the Unity UI and the headless simulator.</summary>
    public sealed class RunDirector
    {
        public RunState Run;
        public Battle Battle;
        public Battle Field;
        public string Screen = "menu";
        public Bag Room = new Bag();
        public List<string> Queue = new List<string>();
        public List<Bag> Corpses = new List<Bag>();
        public List<string> Offers = new List<string>();
        public string DraftMode = "normal";
        public string ItemSource = "";
        public string PendingText = "";
        public List<string> Notes = new List<string>();
        public SequencePuzzle Puzzle;
        public int BranchTier;
        public Bag Save = new Bag();
        public bool IntroEnabled = true;
        public bool PixelPerfect = true;
        public string IntroMode = "first";
        public bool SeenIntro;

        public RunDirector()
        {
            Save.Set("last_seed", 0);
            Save.Set("runs", 0);
            Save.Set("wins", 0);
            Save.Set("best_stage", 0);
            Save.Set("hints_enabled", true);
            var seen = new Bag();
            Save.Set("hints_seen", seen);
            Save.Set("difficulty", "normal");
        }

        public void StartRun(string speciesId, int seed, Bag look, string difficulty)
        {
            Run = RunState.Create(speciesId, seed);
            Run.Look = look ?? new Bag();
            Run.Look.Set("species", speciesId);
            var levels = (Bag)Db.Table("difficulty")["levels"];
            Run.Difficulty = levels.Has(difficulty) ? difficulty : J.S(Db.Table("difficulty"), "default", "normal");
            Save.Set("difficulty", Run.Difficulty);
            Save.Set("last_seed", Run.SeedVal);
            Run.BeginStage(0);
            Battle = null;
            Field = null;
            Notes.Clear();
        }

        public string AfterCustomize()
        {
            bool play = IntroEnabled && (IntroMode == "always" || (IntroMode == "first" && !SeenIntro));
            Screen = play ? "cutscene" : "stage_intro";
            if (play) SeenIntro = true;
            return Screen;
        }

        public void EnterStageBoard()
        {
            Battle = Battle.CreateExplore(Run, null);
            Field = Battle;
            Screen = "battle";
        }

        public void TakeExit(int i)
        {
            Room = Run.ChooseDoor(i);
            Notes = Run.EnterRoom(Room);
            OpenRoom(Room);
        }

        public void SneakOut()
        {
            Run.Bump("sneaks");
            Battle.PendingUnlock = true;
            if (Battle != null) Battle.CommitToRun();
            FinishRoom();
        }

        public void EnterSecret()
        {
            Room = StageGen.MakeCaveRoom(Run);
            Run.Stage.Set("secret_used_step", J.I(Run.Stage, "step"));
            Run.Bump("caves");
            Notes = Run.EnterRoom(Room);
            OpenRoom(Room);
        }

        void OpenRoom(Bag room)
        {
            if (Run.GameOver) { Screen = "gameover"; return; }
            string type = J.S(room, "type");
            if (type == "battle" || type == "elite" || type == "boss" || type == "cave")
            {
                string mode = J.B(room, "unspotted_allowed") ? "ambush" : "spotted";
                Battle = Battle.Create(Run, room, mode);
                if (Notes.Count > 0) Battle.Log(Notes[0]);
                Battle.Begin();
                Screen = "battle";
            }
            else if (type == "event" || type == "forage") Screen = "event";
            else if (type == "puzzle")
            {
                Puzzle = SequencePuzzle.FromRoom(room);
                Screen = "puzzle";
            }
        }

        public void OnBattleClosed()
        {
            if (Battle == null) return;
            Battle.CommitToRun();
            if (Battle.Phase == "lost" || Run.GameOver) { Screen = "gameover"; return; }
            if (Battle.Phase != "won") return;
            var res = Battle.Result();
            Run.GrantXp(J.I(res, "xp"));
            Corpses = new List<Bag>();
            foreach (var c in (List<object>)res["corpses"]) Corpses.Add((Bag)c);
            if (J.S(Room, "type") == "cave")
                foreach (var line in CaveRewardLines()) Notes.Add(line);
            Screen = "reward";
        }

        public List<string> CaveRewardLines()
        {
            var lines = new List<string>();
            int food = J.I(J.Ob(Room, "reward"), "hunger");
            if (food > 0)
            {
                Run.ChangeHunger(food);
                lines.Add("The spiders' larder: +" + food + " hunger");
            }
            return lines;
        }

        public Bag Eat(int index, string mode)
        {
            if (index < 0 || index >= Corpses.Count) return new Bag();
            var res = Run.EatCorpse(Corpses[index], mode);
            Corpses.RemoveAt(index);
            return res;
        }

        public void SkipCorpse(int index)
        {
            if (index >= 0 && index < Corpses.Count) Corpses.RemoveAt(index);
        }

        public void FinishReward()
        {
            if (Corpses.Count > 0) return;
            Queue = RewardQueue(J.S(Room, "type"));
            AdvanceQueue();
        }

        public List<string> RewardQueue(string roomType)
        {
            var q = new List<string>();
            if (Run.PendingEvolutionTier > 0) { q.Add("branch"); q.Add("evolution"); }
            if (roomType == "battle") { q.Add("normal"); if (Run.ItemDrop("battle")) q.Add("item:battle"); }
            else if (roomType == "elite") { q.Add("elite"); if (Run.ItemDrop("elite")) q.Add("item:elite"); }
            else if (roomType == "boss") { q.Add("elite"); q.Add("item:boss"); }
            else if (roomType == "cave")
            {
                var drafts = J.Arr(J.Ob(Room, "reward"), "drafts");
                if (drafts.Count == 0) q.Add("cave");
                foreach (var m in drafts) q.Add(J.S(m));
                q.Add("item:cave");
            }
            return q;
        }

        public void AdvanceQueue()
        {
            if (Run.GameOver) { Screen = "gameover"; return; }
            if (Queue.Count == 0) { FinishRoom(); return; }
            string mode = Queue[0];
            Queue.RemoveAt(0);
            if (mode == "branch")
            {
                BranchTier = Math.Max(Run.PendingEvolutionTier, Run.Tier());
                if (Run.BranchOptions(BranchTier).Count == 0) AdvanceQueue();
                else Screen = "branch";
                return;
            }
            if (mode.StartsWith("item:"))
            {
                ItemSource = mode.Substring(5);
                Offers = Run.OfferItems(ItemSource);
                if (Offers.Count == 0) AdvanceQueue();
                else Screen = "item";
                return;
            }
            DraftMode = mode;
            Offers = Run.OfferCards(3, mode);
            Screen = Offers.Count == 0 ? "battle" : "draft";
            if (Offers.Count == 0) AdvanceQueue();
        }

        public void PickCard(string id)
        {
            if (!Offers.Contains(id)) return;
            Run.AddCard(id);
            Run.Bump("cards_drafted");
            if (DraftMode == "evolution") Run.PendingEvolutionTier = 0;
            AdvanceQueue();
        }

        public void PickItem(string id)
        {
            if (Offers.Contains(id)) Run.AddItem(id);
            AdvanceQueue();
        }

        public void PickBranch(string id)
        {
            var extra = Run.ChooseBranch(BranchTier, id);
            Run.PendingEvolutionTier = 0;
            foreach (var e in extra) Queue.Insert(0, e);
            AdvanceQueue();
        }

        public void ChooseEvent(int index)
        {
            Bag choice = EventChoice(index);
            if (choice == null) return;
            var ctx = new Bag();
            var outcome = Run.ResolveOutcome(choice, ctx);
            PendingText = J.S(outcome, "text");
            Notes.Clear();
            foreach (var m in (List<object>)outcome["msgs"]) Notes.Add(J.S(m));
            Run.Bump(J.S(Room, "type") == "forage" ? "events" : "events");
            if (ctx.Get("battle") is Bag spec)
            {
                var fight = new Bag();
                fight.Set("type", "battle");
                fight.Set("enemies", spec["enemies"]);
                var inf = new List<object>();
                foreach (var e in (List<object>)spec["enemies"])
                    inf.Add(J.B(Db.Enemy(J.S(e)), "infected"));
                fight.Set("infected", inf);
                fight.Set("seed", (int)(Run.Rng.Randi() % 2000000000));
                fight.Set("unspotted_allowed", J.B(spec, "unspotted"));
                fight.Set("event_battle", true);
                fight.Set("teach", "");
                fight.Set("step", J.I(Room, "step"));
                Room = fight;
                OpenRoom(fight);
                return;
            }
            if (Run.GameOver) { Screen = "gameover"; return; }
            Screen = "event_result";
        }

        public Bag EventChoice(int index)
        {
            string type = J.S(Room, "type");
            if (type == "forage")
            {
                var ids = (List<object>)Room["forage_ids"];
                if (index < 0 || index >= ids.Count) return null;
                return (Bag)((Bag)Db.Table("events")["forage"])[J.S(ids[index])];
            }
            var ev = (Bag)((Bag)Db.Table("events")["events"])[J.S(Room, "event_id")];
            var choices = (List<object>)ev["choices"];
            if (index < 0 || index >= choices.Count) return null;
            return (Bag)choices[index];
        }

        public string PuzzlePress(int button)
        {
            string r = Puzzle.Press(button);
            var pd = (Bag)Db.Table("puzzles")[J.S(Room, "puzzle_id", "stone_sequence")];
            var ctx = new Bag();
            if (r == "wrong") Run.ApplyEffects(J.Arr(pd, "mistake_effects"), ctx);
            if (r == "fail")
            {
                Run.ApplyEffects(J.Arr(pd, "fail_effects"), ctx);
                if (Run.GameOver) Screen = "gameover";
            }
            if (r == "done")
            {
                Run.Bump("puzzles");
                Run.ApplyEffects(J.Arr(pd, "reward"), ctx);
                if (Run.PendingEvolutionTier > 0) { Queue = new List<string> { "branch", "evolution" }; AdvanceQueue(); }
                else FinishRoom();
            }
            return r;
        }

        public void ContinueAfterEvent()
        {
            if (Run.PendingEvolutionTier > 0) { Queue = new List<string> { "branch", "evolution" }; AdvanceQueue(); }
            else FinishRoom();
        }

        public void FinishRoom()
        {
            if (Run.GameOver) { Screen = "gameover"; return; }
            if (Run.PendingEvolutionTier > 0)
            {
                Queue = new List<string> { "branch", "evolution" };
                AdvanceQueue();
                return;
            }
            if (J.S(Run.CurrentRoom, "type") == "cave")
            {
                Battle = Battle.CreateExplore(Run, Field);
                Field = Battle;
                Screen = "battle";
                return;
            }
            string next = Run.CompleteRoom();
            if (next == "stage_clear")
            {
                if (Run.AdvanceStage()) Screen = "stage_intro";
                else { Run.Victory = true; Screen = "gameover"; }
            }
            else
            {
                var prev = Battle;
                Battle = Battle.CreateExplore(Run, prev);
                Field = Battle;
                Screen = "battle";
            }
        }

        public void EndRun()
        {
            if (Run == null) return;
            Save.Set("runs", J.I(Save, "runs") + 1);
            if (Run.Victory) Save.Set("wins", J.I(Save, "wins") + 1);
            Save.Set("best_stage", Math.Max(J.I(Save, "best_stage"), Run.StageIdx + 1));
        }
    }

    public static class AutoPlayer
    {
        public static string Play(Battle b, int maxTurns = 80)
        {
            if (b.Phase == "ambush")
            {
                var targets = b.AmbushTargets();
                if (targets.Count > 0) b.AmbushStrike(targets[0]);
                else b.SkipAmbush();
            }
            int guard = 0;
            while (b.Phase == "player" && guard++ < maxTurns)
            {
                if (!TakeTurn(b)) b.EndPlayerTurn();
            }
            return b.Phase;
        }

        static bool TakeTurn(Battle b)
        {
            int bestI = -1;
            BUnit best = null;
            int bestD = -1;
            for (int i = 0; i < b.Hand.Count; i++)
            {
                if (!b.CardPlayable(i)) continue;
                var card = b.CardAt(i);
                string target = J.S(card, "target");
                if (target == "enemy")
                {
                    foreach (var t in b.CardTargets(i))
                    {
                        if (t is not BUnit u) continue;
                        int est = Estimate(b, i, u);
                        if (est > bestD) { bestD = est; bestI = i; best = u; }
                    }
                }
                else if (target != "tile" && bestD < 1)
                {
                    bestD = 1;
                    bestI = i;
                    best = null;
                }
            }
            if (bestI >= 0)
            {
                if (best != null) return b.PlayCard(bestI, best);
                return b.PlayCard(bestI, null);
            }
            if (b.Mp > 0)
            {
                var reach = b.ReachableTiles();
                V2 bestCell = b.Player.Pos;
                int bestScore = int.MinValue;
                foreach (var kv in reach)
                {
                    if (kv.Key == b.Player.Pos) continue;
                    int md = 99;
                    foreach (var e in b.AliveEnemies()) md = Math.Min(md, V2.Dist(kv.Key, e.Pos));
                    int score = -md * 10 - kv.Value + (b.Grid.IsGrass(kv.Key) ? 3 : 0);
                    if (b.Player.Hp * 2 < b.Player.MaxHp) score = md * 10 - kv.Value;
                    if (score > bestScore) { bestScore = score; bestCell = kv.Key; }
                }
                if (bestCell != b.Player.Pos && b.MovePlayer(bestCell)) return true;
            }
            b.EndPlayerTurn();
            return false;
        }

        static int Estimate(Battle b, int i, BUnit tgt)
        {
            var card = b.CardAt(i);
            int dmg = 0;
            foreach (var raw in J.Arr(card, "effects"))
            {
                var op = (Bag)raw;
                if (J.S(op, "op") == "damage")
                {
                    var prev = b.PreviewAttack(i, tgt);
                    int baseD = J.I(op, "amount");
                    if (!tgt.Aware) baseD += J.I(op, "unaware_bonus");
                    dmg += b.CalcDamage(b.Player, tgt, baseD, J.F(prev, "mult", 1f));
                }
            }
            if (tgt.Hp <= dmg) dmg += 50;
            return dmg - J.I(card, "cost");
        }
    }
}
