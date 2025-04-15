#include <amxmodx>

#if AMXX_VERSION_NUM < 183
#assert "AMX Mod X versions 1.8.2 and below are not supported."
#endif

#include <amxmisc>
#include <engine>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN_NAME             "Half-Life Bomb Reward System"
#define PLUGIN_VERSION          "1.0.0"
#define PLUGIN_AUTHOR           "szGabu"

#define BOMB_CLOCK_ID           548875487
#define BOMB_CLEANUP_ID         878124779

#define TRIGGER_MULTIPLE_CLONED 256

#define TS_AT_TOP               0
#define TS_AT_BOTTOM            1
#define TS_GOING_UP             2
#define TS_GOING_DOWN           3

//Use a higher value like 0.5 or 1.0 to reduce the amount of calcs for each cycle
//Most of the time you won't need to change this, but if you are really struggling 
//with CPU performance you may reduce CPU at the cost of accuracy in detection of who's inside the bunker
#define CLOCK_STEP              0.1 

new g_cvarPluginEnabled = INVALID_HANDLE;
new g_cvarModernDetectMethod = INVALID_HANDLE;

new bool:g_bPluginEnabled = false;
new bool:g_bModernDetectMethod = false;
new bool:g_bBombActivated = false;
new bool:g_bInsideBunker[MAX_PLAYERS+1] = { false, ... };
new bool:g_bInsideBunkerRoundRobin[MAX_PLAYERS+1] = { false, ... };
new bool:g_bOnBlastArea[MAX_PLAYERS+1] = { false, ... };
new g_iBombActivator = 0;
new Float:g_fBombTimer = 0.0;

// Configuration variables
new Float:g_flZThreshold = 0.0;
new Float:g_fMapBombTime = 0.0;
new g_szEntityTarget[64];
new g_szDamageTargetname[64];
new g_szCurrentMap[64];

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_cvarPluginEnabled = create_cvar("amx_bomb_reward_enabled", "1", FCVAR_NONE, "Enables the plugin.", true, 0.0, true, 1.0);
    g_cvarModernDetectMethod = create_cvar("amx_bomb_reward_new_detection", "1", FCVAR_NONE, "Uses a newer detection of the blast zone rather than looping & checking bounds which is slow, unreliable and doesn't even work on newer maps with complex blast zones. Leave it on 1 unless you know what are you doing.", true, 0.0, true, 1.0);

    AutoExecConfig();
}

public plugin_cfg()
{
    hook_cvar_change(g_cvarPluginEnabled, "InitializeVars");
    hook_cvar_change(g_cvarModernDetectMethod, "InitializeVars");

    InitializeVars();

    get_mapname(g_szCurrentMap, charsmax(g_szCurrentMap));
    
    // Load map configuration
    if(LoadMapConfig())
    {
        RegisterHam(Ham_Use, "trigger_hurt", "Event_TriggerHurtUse_Post", true);
        RegisterHam(Ham_Touch, "trigger_multiple", "Event_TriggerMultipleTouch_Post", true);
        RegisterHam(Ham_Use, "func_button", "Event_FuncButtonUse_Pre");
        RegisterHam(Ham_Killed, "player", "Event_PlayerKilled_Pre");
        register_message(get_user_msgid("DeathMsg"), "Message_DeathMsg");
        register_dictionary("hldm_bomb_reward.txt");
        
        server_print("[Bomb Reward] Loaded configuration for map: %s", g_szCurrentMap);
        server_print("[Bomb Reward] Z Threshold: %.1f, Bomb Time: %d", g_flZThreshold, g_fMapBombTime);
        server_print("[Bomb Reward] Entity Target: %s, Damage Targetname: %s", g_szEntityTarget, g_szDamageTargetname);
    }
    else 
    {
        server_print("[Bomb Reward] No configuration found for map: %s. Plugin paused.", g_szCurrentMap);
        pause("ad");
    }
}

public OnConfigsExecuted()
{
    create_cvar("amx_bomb_reward_version", PLUGIN_VERSION, FCVAR_SERVER);
}

public InitializeVars()
{
    g_bPluginEnabled = get_pcvar_bool(g_cvarPluginEnabled);
    g_bModernDetectMethod = get_pcvar_bool(g_cvarModernDetectMethod);

    if(!g_bPluginEnabled)
    {
        if(task_exists(BOMB_CLOCK_ID))
            remove_task(BOMB_CLOCK_ID);

        if(task_exists(BOMB_CLEANUP_ID))
            remove_task(BOMB_CLEANUP_ID);
    }
}

public bool:LoadMapConfig()
{
    // Create default config path
    new szConfigsDir[PLATFORM_MAX_PATH];
    new szMapConfig[PLATFORM_MAX_PATH];
    get_configsdir(szConfigsDir, charsmax(szConfigsDir))
    formatex(szMapConfig, charsmax(szMapConfig), "%s/bomb_reward/%s.ini", szConfigsDir, g_szCurrentMap);
    
    // Check if the config file exists
    if(!file_exists(szMapConfig))
    {
        server_print("[Bomb Reward] Configuration file not found: %s", szMapConfig);
        return false;
    }
    
    // Open the file
    new iFileHandle = fopen(szMapConfig, "rt");
    if(!iFileHandle)
    {
        server_print("[Bomb Reward] Failed to open configuration file: %s", szMapConfig);
        return false;
    }
    
    new szBuffer[128], szKey[64];

    while(!feof(iFileHandle))
    {
        fgets(iFileHandle, szBuffer, charsmax(szBuffer));

        trim(szBuffer);
        
        // Skip comments and empty lines
        if(szBuffer[0] == ';' || szBuffer[0] == '/' || szBuffer[0] == 0 || strlen(szBuffer) == 0)
            continue;
        
        // probably there are a better way to do this, but previous tries with parse were not working for me
        // replacing in each key was more consistent but inefficient, but at this point who cares
        // ah well!
        parse(szBuffer, szKey, charsmax(szKey));
        
        if(equal(szKey, "z_threshold"))
        {
            replace_stringex(szBuffer, charsmax(szBuffer), "z_threshold = ", "");
            g_flZThreshold = str_to_float(szBuffer);
        }
        else if(equal(szKey, "bomb_time"))
        {
            replace_stringex(szBuffer, charsmax(szBuffer), "bomb_time = ", "");
            g_fMapBombTime = str_to_float(szBuffer);
        }
        else if(equal(szKey, "entity_target"))
        {
            replace_stringex(szBuffer, charsmax(szBuffer), "entity_target = ", "");
            copy(g_szEntityTarget, charsmax(g_szEntityTarget), szBuffer);
        }
        else if(equal(szKey, "damage_targetname"))
        {
            replace_stringex(szBuffer, charsmax(szBuffer), "damage_targetname = ", "");
            copy(g_szDamageTargetname, charsmax(g_szDamageTargetname), szBuffer);
        }
    }
    
    fclose(iFileHandle);
    
    // Verify required fields are set
    if(strlen(g_szEntityTarget) == 0 || strlen(g_szDamageTargetname) == 0)
    {
        server_print("[Bomb Reward] Configuration is incomplete. Values detected:");
        server_print("[Bomb Reward] g_flZThreshold: %f", g_flZThreshold);
        server_print("[Bomb Reward] g_fMapBombTime: %d", g_fMapBombTime);
        server_print("[Bomb Reward] g_szEntityTarget: %s", g_szEntityTarget);
        server_print("[Bomb Reward] g_szDamageTargetname: %s", g_szDamageTargetname);
        return false;
    }

    //we have a targetname, we need to clone it into trigger_multiple entities to ensure safe and unsafe walking spots (bunker)
    new iEnt = -1;
    while((iEnt = find_ent_by_tname(iEnt, g_szDamageTargetname))) {
        new szClassName[MAX_NAME_LENGTH];
        pev(iEnt, pev_classname, szClassName, charsmax(szClassName));
        if(pev(iEnt, pev_iuser1) != TRIGGER_MULTIPLE_CLONED && equali(szClassName, "trigger_hurt"))
        {
            // Create a new trigger_multiple entity
            new iClone = create_entity("trigger_multiple");
            if(is_valid_ent(iClone))
            {
                new Float:fOrigin[3], Float:fAngles[3], Float:fMins[3], Float:fMaxs[3], szModel[MAX_NAME_LENGTH];
                pev(iEnt, pev_origin, fOrigin);
                pev(iEnt, pev_angles, fAngles);
                pev(iEnt, pev_mins, fMins);
                pev(iEnt, pev_maxs, fMaxs);
                pev(iEnt, pev_model, szModel, charsmax(szModel));

                set_pev(iClone, pev_origin, fOrigin);
                set_pev(iClone, pev_angles, fAngles);
                set_pev(iClone, pev_mins, fMins);
                set_pev(iClone, pev_maxs, fMaxs);
                set_pev(iClone, pev_model, szModel);
                set_pev(iClone, pev_solid, SOLID_TRIGGER);
                set_pev(iClone, pev_movetype, MOVETYPE_NONE);
                set_pev(iClone, pev_iuser1, TRIGGER_MULTIPLE_CLONED);
                
                dllfunc(DLLFunc_Spawn, iClone);

                set_ent_data_float(iClone, "CBaseToggle", "m_flWait", 0.1);
            }
        }
    }
    
    return true;
}

public Message_DeathMsg(iMsgId, iMsgDest, iMsgEntity)
{
    if(!g_bPluginEnabled || !g_bBombActivated)
        return PLUGIN_CONTINUE;

    if(g_bOnBlastArea[get_msg_arg_int(2)])
    {
        new szWeapon[32];
        get_msg_arg_string(3, szWeapon, charsmax(szWeapon));
        if(equali("trigger_hurt", szWeapon))
        {
            set_msg_arg_string(3, "teammate"); //this turns the kill feed into a green skull
            if(!task_exists(BOMB_CLEANUP_ID))
                set_task(0.1, "Task_BombCleanUp", BOMB_CLEANUP_ID);
        }
    }
   
    return PLUGIN_CONTINUE;
}

public plugin_end()
{
    CleanUp();
}

public Event_TriggerHurtUse_Post(const iEntity, const iCaller, const iActivator, const iUseType, const Float:fValue) 
{
    if (!g_bPluginEnabled || !g_bBombActivated)
        return HAM_IGNORED;

    new szTargetname[32];
    pev(iEntity, pev_targetname, szTargetname, charsmax(szTargetname));

    if(equal(szTargetname, g_szDamageTargetname) && !task_exists(BOMB_CLEANUP_ID))
        set_task(0.1, "Task_BombCleanUp", BOMB_CLEANUP_ID);

    return HAM_IGNORED;
}

public Event_FuncButtonUse_Pre(const iEntity, const iCaller, const iActivator, const iUseType, const Float:fValue) 
{
    if (!g_bPluginEnabled || g_bBombActivated || iCaller == 0 || iCaller > MaxClients || !is_user_alive(iCaller))
        return HAM_IGNORED;

    new iToggleState = get_ent_data(iEntity, "CBaseToggle", "m_toggle_state");

    if(iToggleState != TS_AT_BOTTOM)
        return HAM_IGNORED;

    new szTarget[MAX_NAME_LENGTH];
    pev(iEntity, pev_target, szTarget, charsmax(szTarget));

    if(equali(szTarget, g_szEntityTarget))
    {
        g_bBombActivated = true;
        g_fBombTimer = g_fMapBombTime;
        g_iBombActivator = iCaller;
        set_task(CLOCK_STEP, "Task_BombClock", BOMB_CLOCK_ID, _, _, "b");
    }

    return HAM_IGNORED;
}

public Event_TriggerMultipleTouch_Post(const iEntity, const iClient)
{
    if (!g_bPluginEnabled || !is_user_alive(iClient))
        return HAM_IGNORED;

    if(g_bBombActivated && pev(iEntity, pev_iuser1) == TRIGGER_MULTIPLE_CLONED && g_bModernDetectMethod)
        g_bOnBlastArea[iClient] = true;
    else if(!g_bBombActivated)
    {
        new szTarget[MAX_NAME_LENGTH];
        pev(iEntity, pev_target, szTarget, charsmax(szTarget));

        if(equali(szTarget, g_szEntityTarget))
        {
            g_bBombActivated = true;
            g_fBombTimer = g_fMapBombTime;
            g_iBombActivator = iClient;
            set_task(CLOCK_STEP, "Task_BombClock", BOMB_CLOCK_ID, _, _, "b");
        }
    }

    return HAM_IGNORED;
}

public Task_BombClock()
{
    g_fBombTimer -= CLOCK_STEP;

    if(g_fBombTimer < 1.0)
        remove_task(BOMB_CLOCK_ID);

    new iBombTimer = floatround(g_fBombTimer, floatround_ceil);
    new iMapBombTime = floatround(g_fMapBombTime, floatround_ceil);

    if(iBombTimer == iMapBombTime)
    {
        set_hudmessage(255, 200, 128, -1.0, 0.25, 2, 0.0, 8.0, 0.01, 1.0);
        new szActivatorName[MAX_NAME_LENGTH];
        if(is_user_connected(g_iBombActivator))
        {
            get_user_name(g_iBombActivator, szActivatorName, charsmax(szActivatorName));
            show_hudmessage(0, "%L", LANG_PLAYER, "BOMB_ACTIVATED", szActivatorName);
        }
        else
            show_hudmessage(0, "%L", LANG_PLAYER, "BOMB_ACTIVATED_UNKNOWN");
    }
    else if(iBombTimer <= iMapBombTime - 10)
    {
        set_hudmessage(255, 0, 0, -1.0, 0.8, 0, 0.1);
        show_hudmessage(0, "%02d:%02d", (iBombTimer-1 % 3600) / 60, iBombTimer-1 % 60);

        //detect players inside the bunker
        new szPlayersInsideBunker[1024] = "";
        new iPlayersInsideBunker = 0;
        for(new iClient = 1; iClient <= MaxClients; iClient++)
        {
            if(is_user_connected(iClient))
            {
                new Float:fOrigin[3];
                pev(iClient, pev_origin, fOrigin);
                if(g_bModernDetectMethod)
                {
                    g_bInsideBunker[iClient] = false;
                    
                    if(is_user_alive(iClient) && !g_bOnBlastArea[iClient] && fOrigin[2] < g_flZThreshold)
                    {
                        g_bInsideBunker[iClient] = true;
                        new szPlayerName[MAX_NAME_LENGTH];
                        get_user_name(iClient, szPlayerName, charsmax(szPlayerName));
                        if(iPlayersInsideBunker > 0)
                            add(szPlayersInsideBunker, charsmax(szPlayersInsideBunker), ", ");

                        add(szPlayersInsideBunker, charsmax(szPlayersInsideBunker), szPlayerName, charsmax(szPlayerName));
                        iPlayersInsideBunker++;
                    }

                    g_bOnBlastArea[iClient] = false;
                }
                else 
                {
                    new bool:bIsTouchingPain = false;
                    if(is_user_alive(iClient))
                    {
                        g_bInsideBunker[iClient] = false;
                        new iHurt = 0;
                        while((iHurt = find_ent_by_class(iHurt, "trigger_hurt")))
                        {
                            new szTargetname[32];
                            pev(iHurt, pev_targetname, szTargetname, charsmax(szTargetname));
                            
                            if (equal(szTargetname, g_szDamageTargetname) && IsColliding(iClient, iHurt))
                                bIsTouchingPain = true;
                        }
                    }
                    else 
                        bIsTouchingPain = true;

                    if(!bIsTouchingPain && fOrigin[2] < g_flZThreshold)
                    {
                        g_bInsideBunker[iClient] = true;
                        new szPlayerName[MAX_NAME_LENGTH];
                        get_user_name(iClient, szPlayerName, charsmax(szPlayerName));
                        if(iPlayersInsideBunker > 0)
                            add(szPlayersInsideBunker, charsmax(szPlayersInsideBunker), ", ");

                        add(szPlayersInsideBunker, charsmax(szPlayersInsideBunker), szPlayerName, charsmax(szPlayerName));
                        iPlayersInsideBunker++;
                    }
                }
            }
        }

        set_hudmessage(255, 255, 255, -1.0, 0.2, 0, 1.0);
        if(iPlayersInsideBunker > 0)
            show_hudmessage(0, "%L", LANG_PLAYER, "BOMB_INSIDE", szPlayersInsideBunker);
        else 
            show_hudmessage(0, "%L", LANG_PLAYER, "BOMB_INSIDE_NO_ONE");
    }
}

// Handle player kills from the airstrike to redistribute
public Event_PlayerKilled_Pre(iVictim, iAttacker, shouldgib)
{
    if (!g_bPluginEnabled || !g_bBombActivated) 
        return HAM_IGNORED;
    
    // Check if the kill was caused by the airstrike
    new iInflictor = pev(iVictim, pev_dmg_inflictor);
    if (iInflictor <= 0)
        return HAM_IGNORED;
    
    new szTargetname[32];
    pev(iInflictor, pev_targetname, szTargetname, charsmax(szTargetname));
    
    if (equal(szTargetname, g_szDamageTargetname) && RoundRobin_PeopleInsideBunker())
    {
        if(!RoundRobin_Next())
            g_bInsideBunkerRoundRobin = g_bInsideBunker;

        new iNewAttacker = 0;
        for(new iClient = 1; iClient <= MaxClients; iClient++)
        {
            if(g_bInsideBunkerRoundRobin[iClient] && is_user_connected(iClient))
            {
                iNewAttacker = iClient;
                g_bInsideBunkerRoundRobin[iClient] = false;
                break;
            }
        }

        if(iNewAttacker == 0)
            return HAM_IGNORED;

        set_pev(iVictim, pev_dmg_inflictor, iNewAttacker);
        SetHamParamEntity2(2, iNewAttacker);
        g_bOnBlastArea[iVictim] = true;
        return HAM_HANDLED;
    }
    
    return HAM_IGNORED;
}

public client_disconnected(iClient)
{
    g_bInsideBunker[iClient] = false;
    g_bInsideBunkerRoundRobin[iClient] = false;
    g_bOnBlastArea[iClient] = false;
}

public Task_BombCleanUp()
{
    //print final message
    new szPlayersInsideBunker[1024] = "";
    new szPlayersOutsideExplosionRange[1024] = "";
    new iPlayersInsideBunker = 0;
    new iPlayersOutsideExplosionRange = 0;
    new bool:bKillerInside = false;
    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(is_user_connected(iClient) && is_user_alive(iClient))
        {
            new szPlayerName[MAX_NAME_LENGTH];
            get_user_name(iClient, szPlayerName, charsmax(szPlayerName));

            if(g_bInsideBunker[iClient])
            {
                if(g_iBombActivator == iClient)
                    bKillerInside = true;

                if(iPlayersInsideBunker > 0)
                    add(szPlayersInsideBunker, charsmax(szPlayersInsideBunker), ", ");

                add(szPlayersInsideBunker, charsmax(szPlayersInsideBunker), szPlayerName, charsmax(szPlayerName));
                iPlayersInsideBunker++;
            }
            else 
            {
                new Float:fOrigin[3];
                pev(iClient, pev_origin, fOrigin);
                if(fOrigin[2] >= g_flZThreshold)
                {
                    if(iPlayersOutsideExplosionRange > 0)
                        add(szPlayersOutsideExplosionRange, charsmax(szPlayersOutsideExplosionRange), ", ");

                    add(szPlayersOutsideExplosionRange, charsmax(szPlayersOutsideExplosionRange), szPlayerName, charsmax(szPlayerName));
                    iPlayersOutsideExplosionRange++;
                    ExecuteHam(Ham_AddPoints, iClient, 1, true);
                }
            }
        }
    }

    if(iPlayersInsideBunker > 0)
    {
        client_print(0, print_chat, "%L", LANG_PLAYER, "BOMB_KILLS");
        client_print(0, print_chat, "    %s", szPlayersInsideBunker);
    }

    if(iPlayersOutsideExplosionRange > 0)
    {
        client_print(0, print_chat, "%L", LANG_PLAYER, "BOMB_SURVIVED");
        client_print(0, print_chat, "    %s", szPlayersOutsideExplosionRange);
    }

    if(!bKillerInside && is_user_connected(g_iBombActivator))
    {
        new szActivatorName[MAX_NAME_LENGTH];
        get_user_name(g_iBombActivator, szActivatorName, charsmax(szActivatorName));
        client_print(0, print_chat, "%L", LANG_PLAYER, "BOMB_KILLS_PITY", szActivatorName);
        ExecuteHam(Ham_AddPoints, g_iBombActivator, 1, true);
    }

    CleanUp();
}

CleanUp()
{
    g_bBombActivated = false;
    g_fBombTimer = 0.0;
    for(new iClient = 0; iClient <= MaxClients; iClient++)
    {
        g_bInsideBunker[iClient] = false;
        g_bInsideBunkerRoundRobin[iClient] = false;
        g_bOnBlastArea[iClient] = false;
    }

    if(task_exists(BOMB_CLOCK_ID))
        remove_task(BOMB_CLOCK_ID);
}

stock IsColliding(iEntity1, iEntity2)
{
    new Float:fAbsMin1[3], Float:fAbsMin2[3], Float:fAbsMax1[3], Float:fAbsMax2[3];
    
    pev(iEntity1, pev_absmin, fAbsMin1);
    pev(iEntity1, pev_absmax, fAbsMax1);
    pev(iEntity2, pev_absmin, fAbsMin2);
    pev(iEntity2, pev_absmax, fAbsMax2);
    
    if(fAbsMin1[0] > fAbsMax2[0] ||
        fAbsMin1[1] > fAbsMax2[1] ||
        fAbsMin1[2] > fAbsMax2[2] ||
        fAbsMax1[0] < fAbsMin2[0] ||
        fAbsMax1[1] < fAbsMin2[1] ||
        fAbsMax1[2] < fAbsMin2[2])
        return 0;
    
    return 1;
}

stock bool:RoundRobin_Next()
{
    new bool:bFound = false;
    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(g_bInsideBunkerRoundRobin[iClient] && is_user_connected(iClient))
            bFound = true;
    }
    
    return bFound;
}

stock bool:RoundRobin_PeopleInsideBunker()
{
    new bool:bFound = false;
    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(g_bInsideBunker[iClient] && is_user_connected(iClient))
            bFound = true;
    }
    
    return bFound;
}