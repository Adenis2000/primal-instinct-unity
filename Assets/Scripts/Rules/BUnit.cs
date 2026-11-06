using System.Collections.Generic;

namespace PrimalInstinct.Rules
{
    public sealed class BUnit
    {
        public int Uid;
        public string Id = "";
        public string DisplayName = "";
        public bool IsPlayer;
        public List<string> Tags = new List<string>();
        public int MaxHp = 1;
        public int Hp = 1;
        public float BaseSpeed = 10f;
        public int Move = 3;
        public float Perception = 3f;
        public V2 Pos;
        public Dictionary<string, int> TerrainCosts = new Dictionary<string, int>();
        public V2 Facing = new V2(1, 0);
        public int TurnsLeft = 99;
        public int Block;
        public float Meter;
        public string State = "idle";
        public V2 LastSeen = V2.None;
        public V2 Home = V2.None;
        public V2 RoamTarget = V2.None;
        public string SearchPhase = "go";
        public int ScanLeft;
        public bool Alive = true;
        public bool Infected;
        public bool ImmuneToInfection;
        public bool Spreader;
        public int BonusDamage;
        public float SpeedBonus;
        public Dictionary<string, int> Status = new Dictionary<string, int>();
        public List<Bag> Abilities = new List<Bag>();
        public int AbilityIdx;
        public Bag Def = new Bag();
        public string SpriteId = "";
        public int SpritePx = 16;
        public int SpreadCd = 1;
        public int TurnsTaken;
        public Bag Windup = new Bag();
        public List<V2> WindupTiles = new List<V2>();
        public bool SurpriseReady;
        public bool Retreated;
        public List<int> PhaseDone = new List<int>();
        public int Armor;

        public bool Aware
        {
            get => State == "spotted";
            set
            {
                if (value) State = "spotted";
                else if (State == "spotted") State = "idle";
            }
        }

        public bool IsBoss() => J.B(Def, "boss");
        public int St(string name) => Status.TryGetValue(name, out int n) ? n : 0;
        public void AddStatus(string name, int amount) => Status[name] = St(name) + amount;
        public Bag NextAbility() => Abilities.Count == 0 ? new Bag() : Abilities[AbilityIdx % Abilities.Count];
        public Bag FacingTrait() => J.Ob(Def, "facing") ?? new Bag();
        public bool SlowTurn() => J.S(FacingTrait(), "turn") == "slow";
    }
}
