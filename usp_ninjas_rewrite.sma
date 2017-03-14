/*
	Marc Suesser
	2012
	
	USP Ninjas 2.0
*/

#include <amxmodx>
#include <cstrike>
#include <fun>
#include <hamsandwich>
#include <engine>
#include <fakemeta>

#define set_usp_silence(%1)	(set_pdata_int(%1, 74, 1, 4))
#define get_weapon_owner(%1) (get_pdata_cbase(%1, 41, 4))

new const prefix[] = "!g[NINJAS]!y"

enum _:Tasks (+= 1000)
{
	TASK_ROUNDWINNER = 1000,
	TASK_TEAMWINNER,
	TASK_STARTGAME,
	TASK_ENDGAME,
	TASK_CAPTAINSWINNER,
	TASK_FORCECHOOSE,
	TASK_CAPTAINALLOW,
	TASK_REVIVE,
	TASK_HUD_READY,
	TASK_HUD_SCORE,
	TASK_ADV_1,
	TASK_ADV_2,
	TASK_DELAY_CFG
}

new const Float:g_fBlockerOrigins[][3] =
{
	{876.145019, 60.044952, -172.525451},
	{1352.355590, 434.764984, -235.968749},
	{1399.409667, 434.709045, -251.968749}, //
	{1091.057373, 786.188537, -207.338623},
	{541.826110, 788.928649, -207.830276},
	{164.044540, 480.295928, -187.968749},
	{69.139778, 463.414978, -207.063705},
	{-190.696380, 60.584125, -192.226882},
	{-799.374755, -240.277328, -251.968749},
	{1272.457153, -757.851684, 442.586822},
	{1500.800659, -297.111663, -235.968749},
	{1500.800659, -297.111663, 307.007263},
	{1500.800659, -297.111663, 12.031249},
	{1838.405151, -945.429504, 404.03124},
	{1639.061767, -255.265060, -251.968749},
	{1658.197143, -151.287277, -251.968749},
	{1704.695434, -41.910175, -251.968749},
	{1690.737182, 29.872663, -251.968749},
	{1553.591430, 16.334072, -251.968749}
}

new CsTeams:g_tTeam[33]
new CsTeams:g_tCurrentTeam[2]

new g_iLive
new g_iWinningRounds
new g_iCaptainChooseSpot
new g_iHudMessage
new g_iTerroristWins
new g_iVotes[4]
new g_iTeamWins[2]
new g_iCaptains[2] = {-1, -1}

new bool:g_bCanCaptain = false
new bool:g_bFreezeTime
new bool:g_bIsReady[33]
new bool:g_bSorted[33]

new g_pRestart
new g_pFreezeTime
new g_pRoundTime

new curmenu

public plugin_cfg()
{
	set_task(2.5, "TaskDelayCfg", TASK_DELAY_CFG)
}

public TaskDelayCfg(taskid)
{
	g_pRestart = get_cvar_pointer("sv_restart")
	g_pFreezeTime = get_cvar_pointer("mp_freezetime")
	g_pRoundTime = get_cvar_pointer("mp_roundtime")
	
	set_pcvar_num(g_pFreezeTime, 0)
	set_pcvar_num(g_pRoundTime, 9)
	
	set_cvar_num("mp_footsteps", 0)
	set_cvar_num("mp_forcechasecam", 2)
	set_cvar_num("mp_flashlight", 0)
	set_cvar_num("amx_afkcheck_allow", 0)
	set_cvar_num("bullet_damage", 0)
}

public plugin_init()
{
	register_plugin("USP Ninjas", "2.0", "Marc Suesser")
	
	new ent
	
	for(new i = 0; i < sizeof g_fBlockerOrigins; i++)
	{
		ent = create_entity("info_target")
		
		entity_set_string(ent, EV_SZ_classname, "uspninjas_blocker")
		entity_set_origin(ent, g_fBlockerOrigins[i])
		entity_set_float(ent, EV_FL_nextthink, 0.1)
	}
	
	register_event("HLTV", "EventNewRound", "a", "1=0", "2=0")
	register_event("TeamInfo", "EventTeamJoin", "a")
	
	register_think("uspninjas_blocker", "BlockerThinkPre")
	
	register_message(get_user_msgid("StatusIcon"), "MessageStatusIcon")
	
	register_logevent("LogEventRoundStart", 2, "1=Round_Start")
	register_logevent("LogEventRoundEnd", 2, "0=World triggered", "1=Round_Draw", "1=Round_End")
	
	register_clcmd("say .ready", "CmdReady")
	register_clcmd("say_team .ready", "CmdReady")
	register_clcmd("say /ready", "CmdReady")
	register_clcmd("say_team /ready", "CmdReady")
	register_clcmd("say .unready", "CmdUnready")
	register_clcmd("say_team .unready", "CmdUnready")
	register_clcmd("say /unready", "CmdUnready")
	register_clcmd("say_team /unready", "CmdUnready")
	register_clcmd("say /captain", "CmdCaptain")
	register_clcmd("say_team /captain", "CmdCaptain")
	register_clcmd("say /rules", "CmdRules")
	register_clcmd("say_team /rules", "CmdRules")
	register_clcmd("say /origin", "CmdOrigin")
	
	RegisterHam(Ham_Spawn, "player", "HamSpawnPost", 1)
	RegisterHam(Ham_TakeDamage, "player", "HamTakeDamagePre", 0)
	RegisterHam(Ham_Item_Deploy, "weapon_usp", "HamUspDeployPost", 1)
	RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_usp", "HamUspSecondaryPost", 1)
	RegisterHam(Ham_Item_PreFrame, "player", "HamResetPlayerSpeedPost", 1)
	RegisterHam(Ham_Killed, "player", "HamKilledPost", 1)
	
	set_task(900.0, "TaskAdvertise", TASK_ADV_1, _, _, "b")
	set_task(300.0, "TaskAdvertise", TASK_ADV_2, _, _, "b")
	set_task(1.1, "TaskDisplayScore", TASK_HUD_SCORE, _, _, "b")
	
	g_iHudMessage = CreateHudSyncObj()
}

public MessageStatusIcon(msgid, dest, id)
{
	new msg[8]
	get_msg_arg_string(2, msg, 7)
	
	if(equali(msg, "buyzone") && get_msg_arg_int(1))
	{
		set_pdata_int(id, 235, get_pdata_int(id, 235) & ~(1 << 0))
		
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public EventTeamJoin()
{
	if(g_iLive != 1)
	{
		new team[10]
		read_data(2, team, 9)
		
		if(equali(team, "CT") || equali(team, "TERRORIST"))
		{
			set_task(1.0, "TaskRevive", read_data(1) + TASK_REVIVE)
		}
	}
}

public BlockerThinkPre(ent)
{
	if(g_iLive == 1)
	{
		new Float:origin[3]
		entity_get_vector(ent, EV_VEC_origin, origin)
		
		new iPlayers[32]
		new iNum
		
		get_players(iPlayers, iNum)
		
		new id
		
		new Float:plrorigin[3]
		
		for(new i = 0; i < iNum; i++)
		{
			id = iPlayers[i]
			
			if(!is_user_alive(id) || cs_get_user_team(id) != CS_TEAM_T)
			{
				continue;
			}
			
			entity_get_vector(id, EV_VEC_origin, plrorigin)
			
			if(get_distance_f(origin, plrorigin) <= 60.0)
			{
				user_kill(id)
				
				new name[32]
				get_user_name(id, name, 31)
				ChatColor(0, "%s %s was killed for going outside during a match! Type /rules to review the rules, please.", prefix, name)
			}
		}
	}
	
	entity_set_float(ent, EV_FL_nextthink, 0.1)
}	

public CmdOrigin(id)
{
	new Float:origin[3]
	entity_get_vector(id, EV_VEC_origin, origin)
	
	client_print(0, print_chat, "%f, %f, %f", origin[0], origin[1], origin[2])
	
	return PLUGIN_HANDLED;
}

public TaskAdvertise(taskid)
{
	if(taskid == TASK_ADV_1)
	{
		ChatColor(0, "%s This server is running USP Ninjas v2.0 by Marc Suesser.", prefix)
	}
	else // TASK_ADV_2
	{
		ChatColor(0, "%s Type /rules if you are new to USP Ninjas!", prefix)
	}
}

public client_disconnect(id)
{
	if(g_iCaptains[0] == id || g_iCaptains[1] == id)
	{
		switch(g_iLive)
		{
			case 1:
			{
				new plr
				new iPlayers[32]
				new iNum
				
				get_players(iPlayers, iNum)
				
				new i
				
				do
				{
					plr = iPlayers[random(iNum)]
				}
				while(++i < 500 && (g_tTeam[plr] != g_tTeam[id] || plr == id))
				
				if(g_tTeam[plr] != g_tTeam[id])
				{
					ChatColor(0, "%s There are no players left on one team, so the match will revert to pregame.", prefix)
			
					set_task(1.5, "TaskEndGame", TASK_ENDGAME)
				}
				else
				{
					new names[2][32]
					get_user_name(id, names[0], 31)
					get_user_name(plr, names[1], 31)
					
					ChatColor(0, "%s %s has left the game, so %s will now be his team's captain!", prefix, names[0], names[1])
					
					if(id == g_iCaptains[0])
					{
						g_iCaptains[0] = plr
					}
					else
					{
						g_iCaptains[1] = plr
					}
				}
			}
				
			case 2:
			{
				ChatColor(0, "%s A captain has left during the voting rounds, so the match will revert to pregame.", prefix)
			
				set_task(1.5, "TaskEndGame", TASK_ENDGAME)
			}
		}
	}
	
	g_tTeam[id] = CS_TEAM_SPECTATOR
}

public CmdRules(id)
{
	ChatColor(id, "%s Please open your console. The rules have been printed there.", prefix)
	
	client_print(id, print_console, "USP Ninjas v2.0 by Marc Suesser")
	client_print(id, print_console, " ")
	client_print(id, print_console, "In this game, the CTs must breach the main building and kill all of the Ts. Ts must kill all of the CTs or survive until the end of the round.")
	client_print(id, print_console, " ")
	client_print(id, print_console, "1. The goal is for a team to reach the winning number of rounds, which are voted upon at the beginning.")
	client_print(id, print_console, "2. Team points are only gained through a win on T side.")
	client_print(id, print_console, "3. When CTs win a round, the teams are swapped.")
	client_print(id, print_console, "4. Knifing other players is allowed, but it will not do any damage.")
	client_print(id, print_console, "5. Ts may not fully go outside the building. They may only partially peek out of the openings in the building.")
	client_print(id, print_console, "6. In order for a match to begin, there must be at least 6 readied players in the server.")
	
	return PLUGIN_HANDLED;
}

public CmdCaptain(id)
{
	if(g_bCanCaptain && (g_iCaptains[0] != id))
	{
		new name[32]
		get_user_name(id, name, 31)
		new str[64]
		formatex(str, 63, "Allow %s to be a captain?", name)
		new menu = menu_create(str, "CaptainAllowMenuHandler")
		
		menu_additem(menu, "Yes", "0")
		menu_additem(menu, "No", "1")
		
		menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)
		
		new iPlayers[32]
		new iNum
		
		get_players(iPlayers, iNum)
		
		for(new i = 0; i < iNum; i++)
		{
			menu_display(iPlayers[i], menu, 0)
		}
		
		g_bCanCaptain = false
		
		set_task(7.0, "TaskGetCaptainAllow", TASK_CAPTAINALLOW + id)
		
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public CaptainAllowMenuHandler(id, menu, item)
{
	g_iVotes[item]++
}

public TaskGetCaptainAllow(taskid)
{
	taskid -= TASK_CAPTAINALLOW
	new name[32]
	get_user_name(taskid, name, 31)
	
	if(g_iVotes[0] > g_iVotes[1])
	{
		if(g_iCaptains[0] == -1)
		{
			g_iCaptains[0] = taskid
			
			ChatColor(0, "%s %s has been voted to be Captain #1!", prefix, name)
			
			g_bCanCaptain = true
		}
		else
		{
			g_iCaptains[1] = taskid
			
			ChatColor(0, "%s %s has been voted to be Captain #2!", prefix, name)
			
			g_bCanCaptain = false
			
			new names[2][32]
			get_user_name(g_iCaptains[0], names[0], 31)
			get_user_name(g_iCaptains[1], names[1], 31)
			
			ChatColor(0, "!gCaptain #1:!y %s", names[0])
			ChatColor(0, "!gCaptain #2:!y %s", names[1])
			
			g_tTeam[g_iCaptains[0]] = CS_TEAM_CT
			g_tTeam[g_iCaptains[1]] = CS_TEAM_T
			
			g_bSorted[g_iCaptains[0]] = true
			g_bSorted[g_iCaptains[1]] = true
			
			g_iCaptainChooseSpot = 0
			
			CaptainChooseMenu(g_iCaptains[0])
		}
	}
	else
	{
		g_bCanCaptain = true
		
		ChatColor(0, "%s More people voted No than Yes, so %s will not be a captain.", prefix, name)
	}
	
	arrayset(g_iVotes, 0, 4)
}

public CmdReady(id)
{
	if(!g_bIsReady[id] && !g_iLive)
	{
		new name[32]
		get_user_name(id, name, 31)
		
		ChatColor(0, "%s %s is now ready!", prefix, name)
		
		g_bIsReady[id] = true
		
		new iPlayers[32]
		new iNum
		
		get_players(iPlayers, iNum)
		
		if((iNum >= 6) && AllReady())
		{
			ChatColor(0, "%s All players are ready! Voting will now begin.", prefix)
			
			g_iLive = 2
			RoundsMenu()
		}
		
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public CmdUnready(id)
{
	if(g_bIsReady[id] && g_iLive != 1)
	{	
		new name[32]
		get_user_name(id, name, 31)
		
		ChatColor(0, "%s %s is no longer ready!", prefix, name)
		
		if(g_iLive == 2 && (g_iCaptains[0] == id || g_iCaptains[1] == id))
		{
			ChatColor(0, "%s A captain has unreadied during the voting rounds, so the match will revert to pregame.", prefix)
	
			set_task(1.5, "TaskEndGame", TASK_ENDGAME)
		}
		
		g_bIsReady[id] = false
		
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

bool:AllReady()
{
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	for(new i = 0; i < iNum; i++)
	{
		if(!g_bIsReady[iPlayers[i]])
		{
			return false;
		}
	}
	
	return true;
}

RoundsMenu()
{
	new menu = menu_create("How many rounds should be needed to win?", "RoundsMenuHandler")
	
	menu_additem(menu, "10", "0")
	menu_additem(menu, "12", "1")
	menu_additem(menu, "15", "2")
	menu_additem(menu, "20", "3")
	
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)
	
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	for(new i = 0; i < iNum; i++)
	{
		menu_display(iPlayers[i], menu, 0)
	}
	
	set_task(12.0, "TaskGetRoundWinner", TASK_ROUNDWINNER)
}

public RoundsMenuHandler(id, menu, item)
{
	g_iVotes[item]++
}

public TaskGetRoundWinner(taskid)
{
	new top
	
	for(new i = 1; i < 4; i++)
	{
		if(g_iVotes[i] > g_iVotes[top])
		{
			top = i
		}
	}
	
	switch(top)
	{
		case 0: g_iWinningRounds = 10
		case 1: g_iWinningRounds = 12
		case 2: g_iWinningRounds = 15
		case 3: g_iWinningRounds = 20
	}
	
	ChatColor(0, "%s The number of rounds required to win will be %i!", prefix, g_iWinningRounds)
	
	arrayset(g_iVotes, 0, 4)
	
	TeamsMenu()
}

TeamsMenu()
{
	new menu = menu_create("How should the teams be decided?", "TeamsMenuHandler")
	
	menu_additem(menu, "Random", "0")
	menu_additem(menu, "Captains", "1")
	
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)
	
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	for(new i = 0; i < iNum; i++)
	{
		menu_display(iPlayers[i], 0, 0)
		menu_display(iPlayers[i], menu, 0)
	}
	
	set_task(12.0, "TaskGetTeamWinner", TASK_TEAMWINNER)
}

public TeamsMenuHandler(id, menu, item)
{
	g_iVotes[item]++
}

public TaskGetTeamWinner(taskid)
{
	if(g_iVotes[0] > g_iVotes[1])
	{
		new CsTeams:TeamHolder = CS_TEAM_T
		
		new iPlayers[32]
		new iNum
		
		get_players(iPlayers, iNum)
		
		new id
		
		while(!AllSorted())
		{
			id = iPlayers[random(iNum)]
			
			if(!g_bSorted[id])
			{
				g_tTeam[id] = TeamHolder
				g_bSorted[id] = true
				
				TeamHolder = CsTeams:(_:TeamHolder * -1 + 3)
			}
		}
		
		ChatColor(0, "%s The teams will be randomly sorted and the game will now begin in 10 seconds!", prefix)
		
		for(new i = 0; i < iNum; i++)
		{
			id = iPlayers[i]
			
			if(g_iCaptains[0] == -1 && g_tTeam[id] == CS_TEAM_CT)
			{
				g_iCaptains[0] = id
			}
			
			else if(g_iCaptains[1] == -1 && g_tTeam[id] == CS_TEAM_T)
			{
				g_iCaptains[1] = id
			}
		}
		
		set_pcvar_num(g_pRestart, 10)
		set_task(10.3, "TaskGameStart", TASK_STARTGAME)
	}
	else
	{
		CaptainsMenu()
		
		ChatColor(0, "%s The teams will be sorted by captains!", prefix)
	}
	
	arrayset(g_iVotes, 0, 4)
}

CaptainsMenu() //show_menu(..., 0) at endgame
{
	new menu = menu_create("How will captains be decided?", "CaptainsMenuHandler")
	
	menu_additem(menu, "Random", "0")
	menu_additem(menu, "Voting", "1")
	
	menu_setprop(menu, MPROP_EXIT, MEXIT_ALL)
	
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	for(new i = 0; i < iNum; i++)
	{
		menu_display(iPlayers[i], 0, 0)
		menu_display(iPlayers[i], menu, 0)
	}
	
	set_task(12.0, "TaskGetCaptainsWinner", TASK_CAPTAINSWINNER)
}

public CaptainsMenuHandler(id, menu, item)
{
	g_iVotes[item]++
}

public TaskGetCaptainsWinner(taskid)
{
	if(g_iVotes[0] > g_iVotes[1])
	{
		new iPlayers[32]
		new iNum
		
		get_players(iPlayers, iNum)
		
		g_iCaptains[0] = iPlayers[random(iNum)]
		
		do
		{
			g_iCaptains[1] = iPlayers[random(iNum)]
		}
		while(g_iCaptains[0] == g_iCaptains[1])
		
		ChatColor(0, "%s The captains will be randomly chosen!", prefix)
		
		new names[2][32]
		get_user_name(g_iCaptains[0], names[0], 31)
		get_user_name(g_iCaptains[1], names[1], 31)
		
		ChatColor(0, "!gCaptain #1:!y %s", names[0])
		ChatColor(0, "!gCaptain #2:!y %s", names[1])
		
		g_tTeam[g_iCaptains[0]] = CS_TEAM_CT
		g_tTeam[g_iCaptains[1]] = CS_TEAM_T
		
		g_bSorted[g_iCaptains[0]] = true
		g_bSorted[g_iCaptains[1]] = true
		
		CaptainChooseMenu(g_iCaptains[0])
		g_iCaptainChooseSpot = 0
	}
	else
	{
		ChatColor(0, "%s The captains will be voted upon! If anyone would like to be a captain, they must type !g/captain!y.", prefix)
	
		g_bCanCaptain = true
	}
	
	arrayset(g_iVotes, 0, 4)
}

CaptainChooseMenu(id)
{
	curmenu = menu_create("Choose Your Players", "CaptainChooseMenuHandler")
	
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	new plr
	new szId[3]
	new name[32]
	
	for(new i = 0; i < iNum; i++)
	{
		plr = iPlayers[i]
		
		if(!g_bSorted[plr])
		{
			get_user_name(plr, name, 31)
			num_to_str(plr, szId, 2)
			
			menu_additem(curmenu, name, szId)
		}
	}
	
	menu_setprop(curmenu, MPROP_EXITNAME, "Choose a Random Player")
	
	menu_display(id, curmenu, 0)
	
	set_task(20.0, "TaskForceCaptainChoose", TASK_FORCECHOOSE)
}

public CaptainChooseMenuHandler(id, menu, item)
{
	if(g_iLive == 1)
	{
		return;
	}
	
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	new plr
	new names[2][32]
	
	if(item == MENU_EXIT)
	{
		while((plr = iPlayers[random(iNum)]))
		{
			if(g_bSorted[plr])
			{
				continue;
			}
			
			break;
		}
	}
	else
	{
		new access, callback, data[3]
		menu_item_getinfo(menu, item, access, data, 2, _, _, callback)
		
		plr = str_to_num(data)
	}
	
	get_user_name(id, names[0], 31)
	get_user_name(plr, names[1], 31)
			
	g_tTeam[plr] = g_tTeam[g_iCaptains[g_iCaptainChooseSpot%2]]
	g_bSorted[plr] = true
	
	ChatColor(0, "%s %s has picked %s to be on their team!", prefix, names[0], names[1])
	
	remove_task(TASK_FORCECHOOSE)
	
	if(++g_iCaptainChooseSpot >= (iNum - 2))
	{
		ChatColor(0, "%s The teams have been picked and sorted out! The game will now begin.", prefix)
		g_iLive = 1
		
		set_pcvar_num(g_pRestart, 10)
		set_task(10.3, "TaskGameStart", TASK_STARTGAME)
		
		return;
	}
	
	CaptainChooseMenu(g_iCaptains[g_iCaptainChooseSpot%2])
}

public TaskForceCaptainChoose(taskid)
{
	menu_display(g_iCaptains[g_iCaptainChooseSpot%2], 0, 0)
}

public TaskGameStart(taskid)
{
	arrayset(g_iTeamWins, 0, 2)
	g_iTerroristWins = 0
	
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	new id
	
	for(new i = 0; i < iNum; i++)
	{
		id = iPlayers[i]
		
		ChatColor(0, "!gLIVE")
		cs_set_user_team(id, g_tTeam[id])
	}
	
	set_pcvar_num(g_pFreezeTime, 15)
	set_pcvar_num(g_pRoundTime, 4)
	set_pcvar_num(g_pRestart, 1)
	
	set_hudmessage(155, 155, 155)
	show_hudmessage(0, "GL HF")
	
	g_tCurrentTeam[0] = CS_TEAM_T
	g_tCurrentTeam[1] = CS_TEAM_CT
	g_iTeamWins[0] = 0
	g_iTeamWins[1] = 0
	
	g_iCaptainChooseSpot = 0
	
	g_iLive = 1
}

public TaskEndGame(taskid)
{
	arrayset(g_iVotes, 0, 4)
	arrayset(g_bIsReady, false, 33)
	arrayset(g_bSorted, false, 33)
	arrayset(g_iTeamWins, 0, 2)
	arrayset(g_iCaptains, -1, 2)
	
	g_iWinningRounds = 0
	g_iCaptainChooseSpot = 0
	g_iLive = 0
	
	g_bFreezeTime = false
	
	set_pcvar_num(g_pRestart, 1)
	set_pcvar_num(g_pFreezeTime, 0)
	set_pcvar_num(g_pRoundTime, 9)
	
	for(new i = 1000; i < Tasks; i += 1000)
	{
		if(i == TASK_HUD_SCORE)
		{
			continue;
		}
		
		remove_task(i)
	}
	
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	for(new i = 0; i < iNum; i++)
	{
		menu_display(iPlayers[i], -1, 0)
	}
}

public TaskDisplayScore(taskid)
{
	switch(g_iLive)
	{
		case 0:
		{
			new name[34]
			new iPlayers[32]
			new iNum
			new id
			
			get_players(iPlayers, iNum)
			
			new str[360]
			formatex(str, 359, "Players Not Ready:")
			
			for(new i = 0; i < iNum; i++)
			{
				id = iPlayers[i]
				
				if(!g_bIsReady[id])
				{
					get_user_name(id, name, 33)
					format(name, 33, "^n%s", name)
					add(str, 359, name, _)
				}
			}
			
			set_hudmessage(255, 255, 255, 0.78, 0.0, 0, 0.1, 1.0)
			ShowSyncHudMsg(0, g_iHudMessage, str)
		}
		
		case 1:
		{
			new names[2][32]
			get_user_name(g_iCaptains[0], names[0], 31)
			get_user_name(g_iCaptains[1], names[1], 31)
			
			new var
			
			if(g_iCaptains[0] != -1 && g_iCaptains[1] != -1)
			{
				if(g_tCurrentTeam[0] == g_tTeam[g_iCaptains[0]])
				{
					var = 1
				}
			}
			
			//client_print(0, print_chat, "0")
			
			set_hudmessage(255, 255, 255, 0.78, 0.0, 0, 0.1, 1.0)
			ShowSyncHudMsg(0, g_iHudMessage, "%s's Team: %i^n%s's Team: %i", names[0], var ? g_iTeamWins[0] : g_iTeamWins[1], names[1], var ? g_iTeamWins[1] : g_iTeamWins[0])
		}
	}
}

public TaskRevive(id)
{
	id -= TASK_REVIVE
	
	if(!is_user_alive(id))
	{
		ExecuteHamB(Ham_CS_RoundRespawn, id)
	}
}

public EventNewRound()
{
	g_bFreezeTime = true
}

public LogEventRoundStart()
{
	g_bFreezeTime = false
}

public LogEventRoundEnd()
{
	if(!g_iLive || g_iLive == 2)
	{
		return;
	}
	
	set_hudmessage(155, 155, 155)
	
	if(TeamAlive(CS_TEAM_T) || !TeamAlive(CS_TEAM_CT))
	{
		show_hudmessage(0, "TERRORISTS WIN")
		
		new winner
		
		if(g_tCurrentTeam[1] == CS_TEAM_T)
		{
			winner = 1
		}
		
		g_iTeamWins[winner]++
		
		if(g_iTeamWins[winner] >= g_iWinningRounds)
		{
			new name[32]
			
			if(g_tTeam[g_iCaptains[0]] == g_tCurrentTeam[winner])
			{
				get_user_name(g_iCaptains[0], name, 31)
			}
			else
			{
				get_user_name(g_iCaptains[1], name, 31)
			}
			
			ChatColor(0, "%s %s's team has won the match!", prefix, name)
			
			set_task(1.0, "TaskEndGame", TASK_ENDGAME)
		}
		
		if(++g_iTerroristWins == 5)
		{
			ChatColor(0, "%s Terrorists have won 5 rounds in a row, teams are being swapped due to the mercy rule.", prefix)
			
			SwapTeams()
			g_iTerroristWins = 0
		}
	}
	else
	{
		show_hudmessage(0, "COUNTER-TERRORISTS WIN^n^nSwitching Teams...")
		
		SwapTeams()
		g_iTerroristWins = 0
	}
}

SwapTeams()
{
	new iPlayers[32]
	new iNum
	new id
	
	get_players(iPlayers, iNum)
	
	g_tCurrentTeam[0] = CsTeams:(_:g_tCurrentTeam[0] * -1 + 3)
	g_tCurrentTeam[1] = CsTeams:(_:g_tCurrentTeam[1] * -1 + 3)
	
	for(new i = 0; i < iNum; i++)
	{
		id = iPlayers[i]
		
		if(!(CS_TEAM_T <= g_tTeam[id] <= CS_TEAM_CT))
		{
			g_tTeam[id] = cs_get_user_team(id)
		}
		
		g_tTeam[id] = CsTeams:(_:cs_get_user_team(id) * -1 + 3)
		
		cs_set_user_team(id, g_tTeam[id])
	}
	
	set_pcvar_num(g_pRestart, 1)
}

public HamKilledPost(vic, att)
{
	if(g_iLive == 2 || !g_iLive)
	{
		set_task(2.0, "TaskRevive", TASK_REVIVE + vic)
	}
}

public HamUspDeployPost(eWeapon)
{
	set_usp_silence(eWeapon)
	SendWeaponAnim(get_weapon_owner(eWeapon), 6)
}

public HamUspSecondaryPost(eWeapon)
{
	set_usp_silence(eWeapon)
	SendWeaponAnim(get_weapon_owner(eWeapon), 0)
	
	set_pdata_float(eWeapon, 47, 9999.9, 4)
}

public HamResetPlayerSpeedPost(id)
{
	if(is_user_connected(id))
	{
		if(g_bFreezeTime && cs_get_user_team(id) == CS_TEAM_CT)
		{
			set_pev(id, pev_maxspeed, -1.0)
		}
		else
		{
			new Float:flMaxSpeed

			new iActiveItem = get_pdata_cbase(id, 373, 5)
			if(iActiveItem > 0)
			{
				ExecuteHam(Ham_CS_Item_GetMaxSpeed, iActiveItem, flMaxSpeed)
			}
			else
			{
				flMaxSpeed = 250.0
			}

			set_pev(id, pev_maxspeed, flMaxSpeed)
		}
	}
}

public HamTakeDamagePre(vic, inf, att, Float:dmg, dmgbits)
{
	if(cs_get_user_team(vic) == CS_TEAM_CT && (dmgbits == DMG_FALL))
	{
		SetHamReturnInteger(0)
		
		return HAM_SUPERCEDE;
	}
	else if(get_user_weapon(att) == CSW_KNIFE || g_bFreezeTime)
	{
		SetHamParamFloat(4, 0.0)
		
		return HAM_SUPERCEDE;
	}
	
	return HAM_IGNORED;
}

public HamSpawnPost(id)
{
	if(is_user_alive(id))
	{
		if(g_iLive == 2 || !g_iLive) 
		{
			ChatColor(id, "%s Type %s.", prefix, g_bIsReady[id] ? "!g.unready!y if you are suddenly not ready to play" : "!g.ready!y when you are ready to play")
		}
		
		strip_user_weapons(id)
		new eUsp = give_item(id, "weapon_usp")
		give_item(id, "weapon_knife")
		
		cs_set_weapon_ammo(eUsp, 12)
		cs_set_user_bpammo(id, CSW_USP, (!g_iLive || g_iLive == 2) ? 400 : 24)
	}
}

SendWeaponAnim(id, iAnim)
{
	if(!id || !entity_get_int(id, EV_INT_body))
	{
		return;
	}
	
	entity_set_int(id, EV_INT_weaponanim, iAnim)

	message_begin(MSG_ONE, SVC_WEAPONANIM, _, id)
	write_byte(iAnim)
	write_byte(entity_get_int(id, EV_INT_body))
	message_end()
}

bool:AllSorted()
{
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	for(new i = 0; i < iNum; i++)
	{
		if(!g_bSorted[iPlayers[i]])
		{
			return false;
		}
	}
	
	return true;
}

bool:TeamAlive(CsTeams:iTeam)
{
	new iPlayers[32]
	new iNum
	
	get_players(iPlayers, iNum)
	
	new id
	
	for(new i = 0; i < iNum; i++)
	{
		id = iPlayers[i]
		
		if(is_user_alive(id) && cs_get_user_team(id) == iTeam)
		{
			return true;
		}
	}
	
	return false;
}

ChatColor(id, const input[], any:...)
{
    new count = 1;
    new players[32];
    static msg[191];
    vformat(msg, 190, input, 3);
    
    replace_all(msg, 190, "!g", "^4"); // Green Color
    replace_all(msg, 190, "!y", "^1"); // Default Color
    
    if (id > 0)
	players[0] = id; 
    else
	get_players(players, count, "ch");
	
    for (new i = 0; i < count; i++)
    {
        if (is_user_connected(players[i]))
        {
            message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("SayText"), _, players[i]);
            write_byte(players[i]);
            write_string(msg);
            message_end();
        }
    }
}