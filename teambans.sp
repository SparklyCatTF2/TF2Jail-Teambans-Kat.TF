#include <sourcemod>
#include <timers>
#include <morecolors>
#include <tf2>
#include <tf2_stocks>

Handle db = INVALID_HANDLE;
bool bIsClientTeambanned[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "[TeamBans]",
	author = "Sparkly Cat",
	description = "",
	version = "1.0",
	url = "www.kat.tf"
};

public OnPluginStart()
{
	LoadTranslations("common.phrases");

	SQL_TConnect(OnConnect, "teambans", 0);
	
	HookEvent("player_spawn", PlayerSpawn);
	RegAdminCmd("sm_teamban", Cmd_Teamban, ADMFLAG_BAN);
	RegAdminCmd("sm_teamunban", Cmd_Teamunban, ADMFLAG_BAN);
	RegAdminCmd("sm_teamban_status", Cmd_TeambanStatus, ADMFLAG_BAN);
	/*RegAdminCmd("sm_teamban_offline", Cmd_Teamban, ADMFLAG_BAN);
	RegAdminCmd("sm_teamunban_offline", Cmd_Teamban, ADMFLAG_BAN);*/
	
	CreateTimer(60.0, Timer_Bantime, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public OnClientPostAdminCheck(int client)
{
	char steamid[48];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	char query[200];
	Format(query, 200, "SELECT steamid FROM teambans WHERE steamid='%s'", steamid);
	SQL_TQuery(db, OnPostAdminCheckQuery, query, client);
}

public OnPostAdminCheckQuery(Handle owner, Handle hndl, const char[] error, any client)
{
	if(hndl != INVALID_HANDLE)
	{
		if(SQL_FetchRow(hndl))
		{
			bIsClientTeambanned[client] = true;
		}
		else
		{
			bIsClientTeambanned[client] = false;
		}
	}
}

public OnConnect(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl != INVALID_HANDLE)
	{
		db = hndl;
		PrintToServer("[TeamBans] Connected to database successfully!");
	}
	else{
		PrintToServer("[TeamBans] Did not connect to database.");
	}
}

public Action PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);
	
	if(bIsClientTeambanned[client])
	{
		if(TF2_GetClientTeam(client) == TFTeam_Blue)
		{
			TF2_ChangeClientTeam(client, TFTeam_Spectator);
			PrintToChat(client, "You have been guard banned, thus you cannot join blue. Try again later.");
		}
	}
}

public Action Timer_Bantime(Handle timer)
{
	int maxc = GetMaxClients();
	for(new i = 1; i < maxc; ++i)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			new String:steamid[32];
			GetClientAuthId(i, AuthId_Steam2, steamid, sizeof(steamid));
			
			new String:query[200];
			Format(query, sizeof(query), "SELECT steamid, ban_time, admin_name, ban_time_left, reason FROM teambans WHERE steamid='%s'", steamid);
			
			SQL_TQuery(db, OnBantime, query, i);
		}
	}
	return Plugin_Handled;
}

public OnBantime(Handle owner, Handle hndl, const char[] error, any client)
{
	if(hndl != INVALID_HANDLE)
	{
		if(SQL_FetchRow(hndl))
		{
			char steamid[48];
			GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
			
			int ban_time_left = SQL_FetchInt(hndl, 3);
					
			if(ban_time_left == 1)
			{
				new String:query2[200];
				Format(query2, sizeof(query2), "DELETE FROM teambans WHERE steamid='%s'", steamid);
				SQL_TQuery(db, VoidQuery, query2, 0);
				bIsClientTeambanned[client] = false;
			}
			if(ban_time_left > 1)
			{
				new String:query2[200];
				Format(query2, sizeof(query2), "UPDATE teambans SET ban_time_left=ban_time_left-1 WHERE steamid='%s'", steamid);
				SQL_TQuery(db, VoidQuery, query2, 0);
				bIsClientTeambanned[client] = true;
			}
			if(ban_time_left == 0 || ban_time_left < 0)
			{
				bIsClientTeambanned[client] = true;
			}
		}
	}
	else
	{
		PrintToServer("[TeamBans] Could not execute query, mysql server down?");
	}
}

public VoidQuery(Handle owner, Handle hndl, const char[] error, any data)
{
	/* do nothing */
}

public Action Cmd_Teamban(int client, int args)
{
	if(args < 2 || args > 3)
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Usage: sm_teamban <name|#userid> <time>(minutes) <reason>(optional). Reason must be written with underscores or without spaces.");
		return Plugin_Handled;
	}
	
	if(args == 2)
	{
		new String:arg1[128];
		char arg2[17];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		
		int target = FindTarget(client, arg1);
		int time = StringToInt(arg2);
		
		if(target == -1)
		{
			CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Could not find target.");
			return Plugin_Handled;
		}
		if(bIsClientTeambanned[target])
		{
			CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Target is already teambanned");
			return Plugin_Handled;
		}
		if(IsCharAlpha(arg2[0]) || IsCharAlpha(arg2[1]) || IsCharAlpha(arg2[3]) || IsCharAlpha(arg2[4]) || IsCharAlpha(arg2[5]) || IsCharAlpha(arg2[6]) || IsCharAlpha(arg2[7]) || IsCharAlpha(arg2[8]))
		{
			CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Time must be numerical.");
			return Plugin_Handled;
		}
		if(time < 0)
		{
			CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Invalid time, value must be 0 or above (0 - permanent).");
			return Plugin_Handled;
		}
		
		new String:steamid[32];
		GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
		
		new String:query[200];
		Format(query, sizeof(query), "INSERT INTO teambans (steamid, ban_time, admin_name, ban_time_left) VALUES ('%s', '%i', '%N', '%i')", steamid, time, client, time);
		
		Handle pack = new DataPack();
		WritePackCell(pack, client);
		WritePackCell(pack, target);
		WritePackCell(pack, time);
		
		SQL_TQuery(db, TeambanQuery, query, pack);
		
		return Plugin_Handled;		
	}
	
	if(args == 3)
	{
		new String:arg1[128];
		char arg2[17];
		new String:arg3[128];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		GetCmdArg(3, arg3, sizeof(arg3));
		
		new target = FindTarget(client, arg1);
		int time = StringToInt(arg2);
		
		if(target == -1)
		{
			CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Could not find target.");
			return Plugin_Handled;
		}
		if(bIsClientTeambanned[target])
		{
			CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Target is already teambanned");
			return Plugin_Handled;
		}
		if(IsCharAlpha(arg2[0]) || IsCharAlpha(arg2[1]) || IsCharAlpha(arg2[3]) || IsCharAlpha(arg2[4]) || IsCharAlpha(arg2[5]) || IsCharAlpha(arg2[6]) || IsCharAlpha(arg2[7]) || IsCharAlpha(arg2[8]))
		{
			CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Time must be numerical.");
			return Plugin_Handled;
		}
		if(time < 0)
		{
			CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Invalid time, value must be 0 or above (0 - permanent).");
			return Plugin_Handled;
		}
		
		new String:steamid[32];
		GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
		
		new String:query[200];
		char reason2[128];
		SQL_EscapeString(db, arg3, reason2, sizeof(reason2));
		Format(query, sizeof(query), "INSERT INTO teambans (steamid, ban_time, admin_name, ban_time_left, reason) VALUES ('%s', '%i', '%N', '%i', '%s')", steamid, time, client, time, reason2);
		
		Handle pack = new DataPack();
		WritePackCell(pack, client);
		WritePackCell(pack, target);
		WritePackCell(pack, time);
		
		SQL_TQuery(db, TeambanQuery, query, pack);
	}
	
	return Plugin_Handled;
}

public TeambanQuery(Handle owner, Handle hndl, const char[] error, any pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int target = ReadPackCell(pack);
	int time = ReadPackCell(pack);
	CloseHandle(pack);
	
	if(hndl != INVALID_HANDLE)
	{
		bIsClientTeambanned[target] = true;
		new String:targetname[128];
		GetClientName(target, targetname, sizeof(targetname));
		if(time == 0)
		{
			CPrintToChatAll("{white}[{darkblue}TeamBans{white}] Player {yellow}%s {white}has been {darkblue}permanently{white} guard banned.", targetname);
		}
		else{
			CPrintToChatAll("{white}[{darkblue}TeamBans{white}] Player {yellow}%s {white}has been guard banned for {darkblue}%i {white}minutes.", targetname, time);
		}
			
		if(TF2_GetClientTeam(target) == TFTeam_Blue)
		{
			ForcePlayerSuicide(target);
			TF2_ChangeClientTeam(target, TFTeam_Spectator);
		}
	}
	else
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] MySQL issues, try using the command again.");
		bIsClientTeambanned[target] = false;
	}
}

public Action Cmd_Teamunban(int client, int args)
{
	if(args != 1)
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Usage: sm_teamunban <target>.");
		return Plugin_Handled;
	}
	
	new String:arg1[128];
	GetCmdArg(1, arg1, sizeof(arg1));
	
	int target = FindTarget(client, arg1);
	if(target == -1)
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Could not find target.");
		return Plugin_Handled;
	}
	if(!bIsClientTeambanned[target])
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Target is not teambanned from blue.");
		return Plugin_Handled;
	}
	
	new String:authid[32];
	GetClientAuthId(target, AuthId_Steam2, authid, sizeof(authid));
	
	new String:query[200];
	Format(query, sizeof(query), "DELETE FROM teambans WHERE steamid='%s'", authid);
	SQL_TQuery(db, VoidQuery, query);
	CPrintToChatAll("{white}[{darkblue}TeamBans{white}] Player {yellow}%N {white}has been unbanned from blue.", target);
	bIsClientTeambanned[target] = false;

	return Plugin_Handled;
	
}

public Action Cmd_TeambanStatus(int client, int args)
{
	if(args != 1)
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Usage: sm_teamban_status <name|#userid>");
		return Plugin_Handled;
	}
	
	char TargetArg[64];
	GetCmdArg(1, TargetArg, 64);
	int target = FindTarget(client, TargetArg);
	if(target == -1)
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Could not find target.");
		return Plugin_Handled;
	}
	
	if(!bIsClientTeambanned[target])
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Player %N is not teambanned.", target);
		return Plugin_Handled;
	}
	
	char steamid[48];
	GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
	
	char query[200];
	Format(query, 200, "SELECT ban_time_left FROM teambans WHERE steamid='%s'", steamid);
	Handle pack = new DataPack();
	WritePackCell(pack, client);
	WritePackCell(pack, target);
	
	SQL_TQuery(db, TeambanStatus, query, pack);
	
	return Plugin_Handled;
}

public TeambanStatus(Handle owner, Handle hndl, const char[] error, any pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int target = ReadPackCell(pack);
	CloseHandle(pack);
	
	if(hndl == INVALID_HANDLE)
	{
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] Error sending query to mysql server. Error: %s.", error);
	}
	
	if(SQL_FetchRow(hndl))
	{
		int timeleft = SQL_FetchInt(hndl, 0);
		CPrintToChat(client, "{white}[{darkblue}TeamBans{white}] {yellow}%N{white}'s teamban will last for {darkblue}%i {white}more minutes.", target, timeleft);
	}
}