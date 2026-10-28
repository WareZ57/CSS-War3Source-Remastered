// w3s_verify : server commands to inspect War3Source on a test server (not part of the release)
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include "W3SIncs/War3Source_Interface"

public Plugin myinfo =
{
    name = "War3Source - Test - Verify",
    author = "War3Source test suite",
    description = "Inspection and test commands for War3Source"
};

public void OnPluginStart()
{
    RegServerCmd("w3t_status", Cmd_Status, "Race, level, skills, gold and buffs of every player");
    RegServerCmd("w3t_races", Cmd_Races, "Loaded races and their skills");
    RegServerCmd("w3t_matrix", Cmd_Matrix, "Tests every race with two frozen bots");
    RegServerCmd("w3t_items", Cmd_Matrix, "Tests every shop item with two frozen bots");
    RegServerCmd("w3t_cmds", Cmd_Cmds, "Runs every War3Source chat command as a bot");
    RegServerCmd("w3t_kill", Cmd_Kill, "The T bot kills the CT bot: XP, gold and level up");
    RegServerCmd("w3t_set", Cmd_Set, "w3t_set <client> <race> <level> <xp> <gold>: sets a player's War3Source data");
}

public bool InitNativesForwards()
{
    return true;
}

public Action Cmd_Status(int args)
{
    char name[32], race[16], skills[64];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;
        GetClientName(i, name, sizeof(name));
        int r = War3_GetRace(i);
        race[0] = '\0';
        skills[0] = '\0';
        if (r > 0)
        {
            War3_GetRaceShortname(r, race, sizeof(race));
            for (int s = 1; s <= War3_GetRaceSkillCount(r); s++)
                Format(skills, sizeof(skills), "%s%d", skills, War3_GetSkillLevel(i, r, s));
        }
        bool alive = IsPlayerAlive(i);
        PrintToServer("%2d %-16s t%d %s %-10s lvl%2d sk[%s] xp%5d gold%3d hp%4d spd%.2f grav%.2f alpha%3d",
            i, name, GetClientTeam(i), alive ? "A" : "D", race, r > 0 ? War3_GetLevel(i, r) : 0, skills,
            r > 0 ? War3_GetXP(i, r) : 0, War3_GetGold(i), alive ? GetClientHealth(i) : 0,
            GetEntPropFloat(i, Prop_Data, "m_flLaggedMovementValue"), GetEntityGravity(i), GetEntData(i, GetEntSendPropOffs(i, "m_clrRender") + 3, 1));
    }
    return Plugin_Handled;
}

public Action Cmd_Races(int args)
{
    char name[64], shortname[16], skill[64];
    int n = War3_GetRacesLoaded();
    PrintToServer("%d races, %d items", n, W3GetItemsLoaded());
    for (int r = 1; r <= n; r++)
    {
        War3_GetRaceName(r, name, sizeof(name));
        War3_GetRaceShortname(r, shortname, sizeof(shortname));
        PrintToServer("%2d %-10s %s (max level %d)", r, shortname, name, W3GetRaceMaxLevel(r));
        for (int s = 1; s <= War3_GetRaceSkillCount(r); s++)
        {
            W3GetRaceSkillName(r, s, skill, sizeof(skill));
            PrintToServer("     %d %s%s (max %d)", s, skill, War3_IsSkillUltimate(r, s) ? " [ult]" : "", W3GetRaceSkillMaxLevel(r, s));
        }
    }
    return Plugin_Handled;
}

/* ------------------------------------------------------------------------------------------------
 * w3t_matrix [first race] [last race] [hits]
 * Needs exactly one T bot and one CT bot, frozen (sv_cheats 1; bot_stop 1). For each race, at max level:
 *   attacker role : the T bot has the race, the CT bot none -> damage dealt, heal, effects on the victim
 *   victim role   : the CT bot has the race, the T bot none -> damage taken, damage returned
 *   then the race's ultimate and ability are used by the T bot on the CT bot standing in front of it
 * Hits are 1.05 s apart: War3Source scales proc chances by the time since the attacker's last hit.
 * ---------------------------------------------------------------------------------------------- */

#define HIT_DAMAGE 20.0
#define VICTIM_HP 1000
#define ATTACKER_HP 50

int g_T, g_CT, g_Race, g_LastRace, g_Hits, g_Hit, g_Step, g_ErrLines;
bool g_ItemMode;  // w3t_items: g_Race is a shop item id
int g_DmgSum, g_HealSum, g_RetSum, g_Procs;
float g_ViewPos[3], g_ViewAng[3];
Handle g_Timer;

int ErrorLogLines()
{
    char path[PLATFORM_MAX_PATH], date[16], line[512];
    FormatTime(date, sizeof(date), "%Y%m%d");
    BuildPath(Path_SM, path, sizeof(path), "logs/errors_%s.log", date);
    File f = OpenFile(path, "r");
    if (f == null)
        return 0;
    int n = 0;
    while (f.ReadLine(line, sizeof(line)))
        n++;
    delete f;
    return n;
}

void SetRaceMax(int client, int race)
{
    War3_SetRace(client, race);
    if (race <= 0)
        return;
    War3_SetLevel(client, race, W3GetRaceMaxLevel(race));
    for (int s = 1; s <= War3_GetRaceSkillCount(race); s++)
    {
        War3_SetSkillLevelINTERNAL(client, race, s, W3GetRaceSkillMaxLevel(race, s));
        War3_CooldownReset(client, race, s);
    }
}

// Puts the CT bot 120 units in front of the T bot, both facing each other, on flat ground
void FaceToFace()
{
    float fwd[3], pos[3], ang[3];
    GetAngleVectors(g_ViewAng, fwd, NULL_VECTOR, NULL_VECTOR);
    fwd[2] = 0.0;
    NormalizeVector(fwd, fwd);
    TeleportEntity(g_T, g_ViewPos, g_ViewAng, view_as<float>({0.0, 0.0, 0.0}));
    pos = g_ViewPos;
    pos[0] += fwd[0] * 120.0;
    pos[1] += fwd[1] * 120.0;
    ang = g_ViewAng;
    ang[1] += 180.0;
    TeleportEntity(g_CT, pos, ang, view_as<float>({0.0, 0.0, 0.0}));
}

void Passive(int client, char[] buf, int len)
{
    Format(buf, len, "hp%d spd%.2f grav%.2f alpha%d", GetClientHealth(client),
        GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue"), GetEntityGravity(client),
        GetEntData(client, GetEntSendPropOffs(client, "m_clrRender") + 3, 1));
}

public Action Cmd_Matrix(int args)
{
    g_T = g_CT = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i) || IsClientSourceTV(i))
            continue;
        if (GetClientTeam(i) == 2) g_T = i;
        else if (GetClientTeam(i) == 3) g_CT = i;
    }
    if (!g_T || !g_CT)
    {
        PrintToServer("w3t_matrix: needs one T bot and one CT bot");
        return Plugin_Handled;
    }
    char arg[16];
    GetCmdArg(0, arg, sizeof(arg));
    g_ItemMode = StrEqual(arg, "w3t_items");
    g_Race = 1; g_LastRace = g_ItemMode ? W3GetItemsLoaded() : War3_GetRacesLoaded(); g_Hits = 12;
    if (args >= 1) { GetCmdArg(1, arg, sizeof(arg)); g_Race = StringToInt(arg); }
    if (args >= 2) { GetCmdArg(2, arg, sizeof(arg)); g_LastRace = StringToInt(arg); }
    if (args >= 3) { GetCmdArg(3, arg, sizeof(arg)); g_Hits = StringToInt(arg); }
    CS_RespawnPlayer(g_T);
    GetClientAbsOrigin(g_T, g_ViewPos);
    g_ViewAng = view_as<float>({0.0, 0.0, 0.0});
    GetClientEyeAngles(g_T, g_ViewAng);
    g_ViewAng[0] = 0.0;
    g_Step = 0;
    delete g_Timer;
    g_Timer = CreateTimer(1.05, Timer_Matrix, _, TIMER_REPEAT);
    PrintToServer("w3t_matrix: races %d-%d, %d hits of %.0f, T=%N CT=%N", g_Race, g_LastRace, g_Hits, HIT_DAMAGE, g_T, g_CT);
    return Plugin_Handled;
}

// Steps: 0 setup attacker role, 1..hits hits, then 100 setup victim role, 101.. hits, 200 ult, 201 ult result,
// 202 ability, 203 ability result, then next race
public Action Timer_Matrix(Handle timer)
{
    if (!IsClientInGame(g_T) || !IsClientInGame(g_CT))
    {
        PrintToServer("w3t_matrix: a bot left, stopped");
        g_Timer = null;
        return Plugin_Stop;
    }
    char rname[16], buf[128], buf2[128];
    if (g_ItemMode)
        W3GetItemShortname(g_Race, rname, sizeof(rname));
    else
        War3_GetRaceShortname(g_Race, rname, sizeof(rname));
    bool victimRole = g_Step >= 100 && g_Step < 200;
    int att = victimRole ? g_CT : g_T;  // the bot with the race
    if (g_Step == 0 || g_Step == 100)
    {
        if (g_Step == 0)
            g_ErrLines = ErrorLogLines();
        CS_RespawnPlayer(g_T);
        CS_RespawnPlayer(g_CT);
        if (g_ItemMode)
        {
            SetRaceMax(g_T, 0);
            SetRaceMax(g_CT, 0);
            CS_RespawnPlayer(g_T);
            CS_RespawnPlayer(g_CT);
            for (int it = 1; it <= W3GetItemsLoaded(); it++)
            {
                War3_SetOwnsItem(g_T, it, false);
                War3_SetOwnsItem(g_CT, it, false);
            }
            War3_SetGold(att, 100);
            W3SetVar(EventArg1, g_Race);
            W3CreateEvent(DoTriedToBuyItem, att);
            PrintToServer("[%s] %s bought: owns %d, gold 100 -> %d (cost %d)", rname, victimRole ? "victim  " : "attacker",
                War3_GetOwnsItem(att, g_Race), War3_GetGold(att), W3GetItemCost(g_Race));
        }
        else
        {
            SetRaceMax(g_T, victimRole ? 0 : g_Race);
            SetRaceMax(g_CT, victimRole ? g_Race : 0);
            CS_RespawnPlayer(g_T);
            CS_RespawnPlayer(g_CT);
        }
        FaceToFace();
        g_DmgSum = g_HealSum = g_RetSum = g_Procs = 0;
        g_Hit = 0;
        g_Step++;
        return Plugin_Continue;
    }
    if ((g_Step > 0 && g_Step < 100) || (g_Step > 100 && g_Step < 200))
    {
        if (g_Hit == 0)
        {
            Passive(att, buf, sizeof(buf));
            PrintToServer("[%s] %s spawn: %s", rname, victimRole ? "victim  " : "attacker", buf);
        }
        int shooter = g_T, target = g_CT;
        // The shooter's health is read one step after each hit: some skills act after a delay (thorns: 0.1 s)
        if (g_Hit > 0)
        {
            int sh = IsPlayerAlive(shooter) ? GetClientHealth(shooter) : 0;
            if (sh > ATTACKER_HP) g_HealSum += sh - ATTACKER_HP;
            else g_RetSum += ATTACKER_HP - sh;
        }
        if (g_Hit == g_Hits)
        {
            Passive(g_CT, buf, sizeof(buf));
            Passive(g_T, buf2, sizeof(buf2));
            PrintToServer("[%s] %s %d hits: dmg avg %.1f (%d/%d differ), shooter healed %d, shooter hurt %d | T %s | CT %s",
                rname, victimRole ? "victim  " : "attacker", g_Hits, float(g_DmgSum) / g_Hits, g_Procs, g_Hits, g_HealSum, g_RetSum, buf2, buf);
            g_Step = victimRole ? (g_ItemMode ? 203 : 200) : 100;
            if (g_Step == 203)
                return Timer_Matrix(timer);
            return Plugin_Continue;
        }
        SetEntProp(target, Prop_Send, "m_ArmorValue", 0);
        SetEntityHealth(target, VICTIM_HP);
        SetEntityHealth(shooter, ATTACKER_HP);
        FaceToFace();
        int weapon = GetEntPropEnt(shooter, Prop_Send, "m_hActiveWeapon");
        // Like a real bullet: damage hooks run, and every hit has its own impact point
        // (War3Source ignores a second OnTakeDamage call identical to the previous one)
        float hitpos[3], force[3];
        GetClientEyePosition(target, hitpos);
        hitpos[0] += GetRandomFloat(-8.0, 8.0);
        hitpos[2] -= GetRandomFloat(0.0, 30.0);
        force[0] = GetRandomFloat(-500.0, 500.0);
        force[1] = GetRandomFloat(-500.0, 500.0);
        SDKHooks_TakeDamage(target, shooter, shooter, HIT_DAMAGE, DMG_BULLET, weapon, force, hitpos, false);
        int dmg = VICTIM_HP - (IsPlayerAlive(target) ? GetClientHealth(target) : 0);
        g_DmgSum += dmg;
        if (dmg != RoundToFloor(HIT_DAMAGE)) g_Procs++;
        g_Hit++;
        return Plugin_Continue;
    }
    if (g_Step == 200 || g_Step == 202)
    {
        CS_RespawnPlayer(g_T);
        CS_RespawnPlayer(g_CT);
        SetRaceMax(g_T, g_Race);
        SetRaceMax(g_CT, 0);
        SetEntityHealth(g_CT, VICTIM_HP);
        FaceToFace();
        SetEntityHealth(g_CT, VICTIM_HP);
        FakeClientCommand(g_T, g_Step == 200 ? "+ultimate" : "+ability");
        CreateTimer(0.3, Timer_Release, g_Step == 200);
        g_Step++;
        return Plugin_Continue;
    }
    if ((g_Step == 201 || g_Step == 203) && !g_ItemMode)
    {
        float tp[3], cp[3], ctStart[3], fwd[3];
        GetClientAbsOrigin(g_T, tp);
        GetClientAbsOrigin(g_CT, cp);
        GetAngleVectors(g_ViewAng, fwd, NULL_VECTOR, NULL_VECTOR);
        ctStart = g_ViewPos;
        ctStart[0] += fwd[0] * 120.0;
        ctStart[1] += fwd[1] * 120.0;
        Passive(g_CT, buf, sizeof(buf));
        Passive(g_T, buf2, sizeof(buf2));
        PrintToServer("[%s] %s: CT dmg %d, T moved %.0f, CT moved %.0f, T alive %d CT alive %d | T %s | CT %s",
            rname, g_Step == 201 ? "ultimate" : "ability ",
            IsPlayerAlive(g_CT) ? VICTIM_HP - GetClientHealth(g_CT) : -1,
            GetVectorDistance(tp, g_ViewPos), GetVectorDistance(cp, ctStart), IsPlayerAlive(g_T), IsPlayerAlive(g_CT), buf2, buf);
        if (g_Step == 201)
        {
            g_Step = 202;
            return Plugin_Continue;
        }
    }
    if (g_Step == 203)
    {
        int errs = ErrorLogLines() - g_ErrLines;
        PrintToServer("[%s] error log: %d new line(s)", rname, errs);
        g_Race++;
        g_Step = 0;
        if (g_Race > g_LastRace)
        {
            PrintToServer("w3t_matrix: done");
            SetRaceMax(g_T, 0);
            SetRaceMax(g_CT, 0);
            for (int it = 1; it <= W3GetItemsLoaded(); it++)
            {
                War3_SetOwnsItem(g_T, it, false);
                War3_SetOwnsItem(g_CT, it, false);
            }
            g_Timer = null;
            return Plugin_Stop;
        }
    }
    return Plugin_Continue;
}

public Action Timer_Release(Handle timer, bool ult)
{
    if (IsClientInGame(g_T))
        FakeClientCommand(g_T, ult ? "-ultimate" : "-ability");
    return Plugin_Stop;
}

/* ------------------------------------------------------------------------------------------------
 * w3t_cmds : every War3Source chat command, typed by a bot (menus are not shown to bots, but all the
 * code behind them runs); prints the number of new lines in the SourceMod error log
 * ---------------------------------------------------------------------------------------------- */
static const char g_Cmds[][] = {
    "war3menu", "showxp", "xp", "changerace", "cr", "raceinfo", "playerinfo", "myinfo", "skillsinfo", "showskills",
    "spendskills", "resetskills", "shopmenu", "shopmenu2", "itemsinfo", "itemsinfo2", "iteminfo", "myitems", "buyprevious",
    "levelbank", "war3top", "war3top10", "war3rank", "war3stats", "war3help", "wchelp", "war3version", "maxhp", "speed",
    "help", "cvarlist", "tome", "w3s", "wcs"
};

int g_CmdBot, g_CmdStep, g_CmdErrBefore;

public Action Cmd_Cmds(int args)
{
    g_CmdBot = 0;
    for (int i = 1; i <= MaxClients && !g_CmdBot; i++)
        if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
            g_CmdBot = i;
    if (!g_CmdBot)
    {
        PrintToServer("w3t_cmds: needs a bot");
        return Plugin_Handled;
    }
    g_CmdErrBefore = ErrorLogLines();
    g_CmdStep = 0;
    // one command every 0.25 s: the engine kicks a client that sends too many commands at once
    CreateTimer(0.25, Timer_Cmds, _, TIMER_REPEAT);
    return Plugin_Handled;
}

// Each command: "say cmd", "say !cmd", then menuselect 1..9 to browse the menu it opened
#define CMD_SUBSTEPS 11

public Action Timer_Cmds(Handle timer)
{
    if (!IsClientInGame(g_CmdBot))
    {
        PrintToServer("w3t_cmds: the bot left, stopped at step %d", g_CmdStep);
        return Plugin_Stop;
    }
    int c = g_CmdStep / CMD_SUBSTEPS, sub = g_CmdStep % CMD_SUBSTEPS;
    if (c >= sizeof(g_Cmds))
    {
        PrintToServer("w3t_cmds: %d commands (with and without !, then menus browsed), error log: %d new line(s)", sizeof(g_Cmds), ErrorLogLines() - g_CmdErrBefore);
        return Plugin_Stop;
    }
    char cmd[64];
    if (sub == 0)
        Format(cmd, sizeof(cmd), "say %s", g_Cmds[c]);
    else if (sub == 1)
        Format(cmd, sizeof(cmd), "say !%s", g_Cmds[c]);
    else
        Format(cmd, sizeof(cmd), "menuselect %d", sub - 1);
    FakeClientCommand(g_CmdBot, cmd);
    g_CmdStep++;
    return Plugin_Continue;
}

/* ------------------------------------------------------------------------------------------------
 * w3t_kill [race] [times] : the T bot (level 0 of the race) kills the CT bot, XP/gold/level after each kill
 * ---------------------------------------------------------------------------------------------- */
int g_KillsLeft;

public Action Cmd_Kill(int args)
{
    Cmd_Matrix_FindBots();
    if (!g_T || !g_CT)
    {
        PrintToServer("w3t_kill: needs one T bot and one CT bot");
        return Plugin_Handled;
    }
    char arg[16];
    int race = 1;
    g_KillsLeft = 5;
    if (args >= 1) { GetCmdArg(1, arg, sizeof(arg)); race = StringToInt(arg); }
    if (args >= 2) { GetCmdArg(2, arg, sizeof(arg)); g_KillsLeft = StringToInt(arg); }
    War3_SetRace(g_T, race);
    War3_SetLevel(g_T, race, 0);
    War3_SetXP(g_T, race, 0);
    War3_SetGold(g_T, 0);
    PrintToServer("w3t_kill: race %d, start lvl %d xp %d gold %d", race, War3_GetLevel(g_T, race), War3_GetXP(g_T, race), War3_GetGold(g_T));
    CreateTimer(1.5, Timer_Kill, race, TIMER_REPEAT);
    return Plugin_Handled;
}

void Cmd_Matrix_FindBots()
{
    g_T = g_CT = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i) || IsClientSourceTV(i))
            continue;
        if (GetClientTeam(i) == 2) g_T = i;
        else if (GetClientTeam(i) == 3) g_CT = i;
    }
}

public Action Timer_Kill(Handle timer, int race)
{
    if (!IsClientInGame(g_T) || !IsClientInGame(g_CT))
        return Plugin_Stop;
    if (!IsPlayerAlive(g_T)) CS_RespawnPlayer(g_T);
    if (!IsPlayerAlive(g_CT)) CS_RespawnPlayer(g_CT);
    FaceToFace();
    SetEntProp(g_CT, Prop_Send, "m_ArmorValue", 0);
    SetEntityHealth(g_CT, 10);
    float hitpos[3];
    GetClientEyePosition(g_CT, hitpos);
    int weapon = GetEntPropEnt(g_T, Prop_Send, "m_hActiveWeapon");
    SDKHooks_TakeDamage(g_CT, g_T, g_T, 50.0, DMG_BULLET, weapon, view_as<float>({100.0, 0.0, 0.0}), hitpos, false);
    CreateTimer(0.5, Timer_KillReport, race);
    if (--g_KillsLeft <= 0)
        return Plugin_Stop;
    return Plugin_Continue;
}

public Action Timer_KillReport(Handle timer, int race)
{
    PrintToServer("w3t_kill: CT alive %d -> T lvl %d xp %d gold %d", IsPlayerAlive(g_CT), War3_GetLevel(g_T, race), War3_GetXP(g_T, race), War3_GetGold(g_T));
    return Plugin_Stop;
}

public Action Cmd_Set(int args)
{
    if (args < 5)
    {
        PrintToServer("w3t_set <client> <race> <level> <xp> <gold>");
        return Plugin_Handled;
    }
    char arg[16];
    int v[5];
    for (int i = 0; i < 5; i++)
    {
        GetCmdArg(i + 1, arg, sizeof(arg));
        v[i] = StringToInt(arg);
    }
    War3_SetRace(v[0], v[1]);
    War3_SetLevel(v[0], v[1], v[2]);
    War3_SetXP(v[0], v[1], v[3]);
    War3_SetGold(v[0], v[4]);
    // one point in each skill except the ultimate (it needs a minimum level)
    for (int s = 1; s <= War3_GetRaceSkillCount(v[1]) && s <= v[2]; s++)
        if (!War3_IsSkillUltimate(v[1], s))
            War3_SetSkillLevelINTERNAL(v[0], v[1], s, 1);
    PrintToServer("w3t_set: done");
    return Plugin_Handled;
}
