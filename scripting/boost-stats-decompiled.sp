#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <morecolors>
#include <clientprefs>

#pragma newdecls required
#pragma semicolon 1

bool gB_LateLoaded;

int gI_Partner[MAXPLAYERS+1];
int gI_FlashCounter[MAXPLAYERS+1];
float gF_PrevSpeed[MAXPLAYERS+1];
float gF_PrevFlashSpeed[MAXPLAYERS+1];
float gF_PrevPos[MAXPLAYERS+1][3];
float gF_SkyVel[MAXPLAYERS+1];
float gF_LastPositionTP[MAXPLAYERS+1][3];
float gF_LastPositionGround[MAXPLAYERS+1][3];
char gS_VelMessages[MAXPLAYERS+1][20][200];
bool gB_AllEnabled[MAXPLAYERS+1];
bool gB_Processed[MAXPLAYERS+1];
bool gB_OnSkyNade[MAXPLAYERS+1];
bool gB_Printed[MAXPLAYERS+1];

Handle gH_BSCookie;

public Plugin myinfo =
{
	name = "Trikz Booststats",
	description = "",
	author = "daniel, Ciallo(thanks to maru and rumour)",
	version = "1.1",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_LateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_bs", Command_BSAll, "toggles all booststats");
	gH_BSCookie = RegClientCookie("booststats_enabled", "booststats_enabled", CookieAccess_Protected);
	for(int i = 1; i <= MaxClients; i++)
	{
		if (AreClientCookiesCached(i))
		{
			OnClientCookiesCached(i);
		}
	}

	if (gB_LateLoaded)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				OnClientPutInServer(i);
			}
		}
		
		OnMapStart();
		gB_LateLoaded = false;
	}
}

public Action Command_BSAll(int client, int args)
{
	if (IsValidClient(client))
	{
		gB_AllEnabled[client] = !gB_AllEnabled[client];
		
		char sStatus[32];
		if (gB_AllEnabled[client])
		{
			Format(sStatus, 32, "{green}Enabled.{default}");
		}
		
		else
		{
			Format(sStatus, 32, "{red}Disabled.{default}");
		}

		CPrintToChat(client, "{aqua}[BS]{white} BoostStats %s", sStatus);

		char sValue[8];
		IntToString(view_as<int>(gB_AllEnabled[client]), sValue, 8);
		SetClientCookie(client, gH_BSCookie, sValue);
	}

	return Plugin_Handled;
}

public void OnMapStart()
{
	int teleporters = -1;
	while ((teleporters = FindEntityByClassname(teleporters, "trigger_teleport")) != -1)
	{
		SDKHook(teleporters, SDKHook_StartTouch, TP_StartTouch);
	}
}

public void OnClientPutInServer(int client)
{
	if (0 < client <= MaxClients && !IsFakeClient(client))
	{
		SDKHook(client, SDKHook_StartTouch, Client_StartTouch);
	}
}

public void OnClientCookiesCached(int client)
{
	char sValue[8];
	GetClientCookie(client, gH_BSCookie, sValue, 8);

	gB_AllEnabled[client] = view_as<bool>(StringToInt(sValue));
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (IsValidEntity(entity))
	{
		if (StrEqual(classname, "flashbang_projectile", false))
		{
			RequestFrame(PrintRun, entity);
		}
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (0 < gI_FlashCounter[client])
	{
		if (GetEntityFlags(client) & FL_ONGROUND && !gB_OnSkyNade[client] && gI_FlashCounter[client] > 0)
		{
			GetClientAbsOrigin(client, gF_LastPositionGround[client]);
			RequestFrame(OPRC, client);
		}
	}
	
	return Plugin_Continue;
}

void OPRC(int client)
{
	if (!gB_OnSkyNade[client] && gI_FlashCounter[client] > 0)
	{
		if (!gB_Processed[client])
		{
			PrintDistance(client, false);
			gB_Processed[client] = true;
		}
	}
}

public void OnClientDisconnect(int client)
{
	if (0 < client <= MaxClients && !IsFakeClient(client))
	{
		gI_FlashCounter[client] = 0;
		gF_PrevSpeed[client] = 0.0;
		gF_PrevFlashSpeed[client] = 0.0;
		gB_AllEnabled[client] = false;
		gB_Processed[client] = false;
	}
}

public Action JoinMsg(Handle timer, int client)
{
	if (!IsClientConnected(client))
	{
		return Plugin_Continue;
	}

	CPrintToChat(client, "{aqua}[BoostStats] {white}!bs to {green}enable{white}/{red}disable {white}booststats.");
	return Plugin_Continue;
}

public Action Client_StartTouch(int client, int other)
{
	bool isgrenade;
	char classname[32];
	GetEntityClassname(other, classname, 32);
	if (StrContains(classname, "_projectile", true) != -1)
	{
		isgrenade = true;
	}

	if (isgrenade || 0 < other <= MaxClients)
	{
		gB_OnSkyNade[client] = true;
		RequestFrame(RS, client);

		float toppos[3];
		float botpos[3];
		GetEntityPosition(client, toppos);
		GetEntityPosition(other, botpos);

		float botmaxs[3];
		GetEntPropVector(other, Prop_Send, "m_vecMaxs", botmaxs);

		float heightdiff = toppos[2] - botpos[2] - botmaxs[2];
		if (0.0 <= heightdiff <= 2.0)
		{
			float botvel[3];
			GetEntPropVector(other, Prop_Data, "m_vecAbsVelocity", botvel);

			if (botvel[2] > 0.0)
			{
				if (isgrenade)
				{
					float prevflyvel[3];
					GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", prevflyvel);

					int flasher = GetEntPropEnt(other, Prop_Data, "m_hThrower");
					gI_Partner[client] = flasher;
					gF_PrevSpeed[client] = SquareRoot(prevflyvel[0] * prevflyvel[0] + prevflyvel[1] * prevflyvel[1]);
					GetEntityPosition(client, gF_PrevPos[client]);
					RequestFrame(flashboost1, client);
				}

				if (0.0 <= botvel[2] < 290.0 && !view_as<bool>(GetEntityFlags(client) & FL_DUCKING))
				{
					gI_Partner[client] = other;
					gF_SkyVel[client] = botvel[2];
					PrintSky(client);
				}
			}
		}
	}

	return Plugin_Continue;
}

void RS(int client)
{
	RequestFrame(RS2, client);
}

void RS2(int client)
{
	RequestFrame(RS3, client);
}

void RS3(int client)
{
	gB_OnSkyNade[client] = false;
}

void PrintSky(int client)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && ((!IsPlayerAlive(i) && 
			(client != GetEntPropEnt(i, Prop_Data, "m_hObserverTarget") && 
				gI_Partner[client] != GetEntPropEnt(i, Prop_Data, "m_hObserverTarget")) && 
					GetEntProp(i, Prop_Data, "m_iObserverMode", 4) != 7 && gB_AllEnabled[i]) || 
						((client != i && gI_Partner[client] != i) && gB_AllEnabled[i])))
		{
			CPrintToChat(i, "{aqua}[BS]{white} Sky: %.2f", gF_SkyVel[client]);
		}
	}
}

void PrintDistance(int client, bool code)
{
	if (gB_Processed[client])
	{
		gB_Processed[client] = false;
		return;
	}

	if (gB_Printed[client])
	{
		return;
	}

	char state[2][24] = 
	{
		"units",
		"units {red}(TP/failed)"
	};

	float curpos[3];
	if (code)
	{
		curpos = gF_LastPositionTP[client];
	}

	else
	{
		curpos = gF_LastPositionGround[client];
	}
	float distance = SquareRoot(curpos[0] - gF_PrevPos[client][0] * curpos[0] - gF_PrevPos[client][0] + curpos[1] - gF_PrevPos[client][1] * curpos[1] - gF_PrevPos[client][1]);
	
	char dist[100];
	Format(dist, 100, "| Distance: {aqua}%.2f {white}%s", distance, state[code]);
	StrCat(gS_VelMessages[client][gI_FlashCounter[client] % 20 - 1], 200, dist);
	PrintVel(client, gI_FlashCounter[client]);
	RequestFrame(ClearFlashCounter, client);

	gB_Printed[client] = true;
}

void ClearFlashCounter(int client)
{
	gI_FlashCounter[client] = 0;
	gB_Processed[client] = false;
	gB_Printed[client] = false;
}

void PrintVel(int client, int flashcount)
{
	for(int i = 0; flashcount % 20 > i; i++)
	{
		for(int j = 1; j <= MaxClients; j++)
		{
			if (IsClientInGame(j) && ((!IsPlayerAlive(j) && 
				(client != GetEntPropEnt(j, Prop_Data, "m_hObserverTarget") && 
					gI_Partner[client] != GetEntPropEnt(j, Prop_Data, "m_hObserverTarget")) && 
						GetEntProp(j, Prop_Data, "m_iObserverMode", 4) != 7 && gB_AllEnabled[j]) || 
							((client != j && gI_Partner[client] != j) && gB_AllEnabled[j])))
			{
				CPrintToChat(j, gS_VelMessages[client][i]);
			}
		}
		//gS_VelMessages[client][i][0] = MissingTAG:0; ????
	}
}

void PrintRun(int entity)
{
	char sClassname[32];
	GetEntityClassname(entity, sClassname, 32);
	if (!StrEqual(sClassname, "flashbang_projectile", false))
	{
		return;
	}

	char colors[5][12] = 
	{
		"{red}",
		"{orange}",
		"{yellow}",
		"{lime}",
		"{aqua}"
	};

	int clrind;
	int flasher = GetEntPropEnt(entity, Prop_Data, "m_hThrower");
	float prevbotvel[3];
	GetEntPropVector(flasher, Prop_Data, "m_vecAbsVelocity", prevbotvel);
	float speed = SquareRoot(prevbotvel[0] * prevbotvel[0] + prevbotvel[1] * prevbotvel[1]);

	if (GetEntityFlags(flasher) & FL_DUCKING)
	{
		clrind = DuckColors(speed);
	}
	
	else
	{
		clrind = Colors(speed);
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && ((!IsPlayerAlive(i) && 
			(flasher == GetEntPropEnt(i, Prop_Data, "m_hObserverTarget") && 
				GetEntProp(i, Prop_Data, "m_iObserverMode", 4) != 7 && 
					gB_AllEnabled[i])) || (flasher == i && gB_AllEnabled[i])))
		{
			CPrintToChat(i, "{aqua}[BS]{white} Run: %s%.2f u/s", colors[clrind], speed);
		}
	}
}

void GetEntityPosition(int entity, float pos[3])
{
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
}

public Action TP_StartTouch(int entity, int other)
{
	if (0 < other <= MaxClients)
	{
		if (gI_FlashCounter[other] > 0 && !gB_OnSkyNade[other])
		{
			GetClientAbsOrigin(other, gF_LastPositionTP[other]);
			RequestFrame(CheckForTeleport, other);
		}
	}

	return Plugin_Continue;
}

void CheckForTeleport(int client)
{
	float vPos[3];
	GetClientAbsOrigin(client, vPos);

	float distance = SquareRoot(Pow(vPos[0] - gF_LastPositionTP[client][0], 2.0) + Pow(vPos[1] - gF_LastPositionTP[client][1], 2.0) + Pow(vPos[2] - gF_LastPositionTP[client][2], 2.0));
	if (distance > 35.0)
	{
		if (!gB_Processed[client])
		{
			PrintDistance(client, true);
			gB_Processed[client] = true;
		}
	}
}

void flashboost1(int client)
{
	RequestFrame(flashboost2, client);
}

void flashboost2(int client)
{
	RequestFrame(flashboost3, client);
}

void flashboost3(int client)
{
	RequestFrame(flashboost4, client);
}

void flashboost4(int client)
{
	RequestFrame(flashboost5, client);
}

void flashboost5(int client)
{
	if (!IsClientInGame(client))
	{
		return;
	}
	float flyvel[3] = 0.0;
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", flyvel);

	float xyvel = SquareRoot(flyvel[0] * flyvel[0] + flyvel[1] * flyvel[1]);
	if (xyvel == 0.0)
	{
		return;
	}

	int fc = ++gI_FlashCounter[client];
	float prevspeed = gF_PrevSpeed[client];
	if (fc == 1)
	{
		Format(gS_VelMessages[client][fc + -1 % 20], 200, "{aqua}[BS]{white} x1 | {aqua}%.0f {white}-> {aqua}%.0f{white} ", prevspeed, xyvel);
	}

	else
	{
		float gain = gF_PrevSpeed[client] - gF_PrevFlashSpeed[client];
		Format(gS_VelMessages[client][fc + -1 % 20], 200, "{aqua}[BS]{white} x%d | {aqua}%.0f {white}-> {aqua}%.0f {white}| {violet}Gains {white}= {violet}%.0f{white} ", fc, prevspeed, xyvel, gain);
	}

	gF_PrevFlashSpeed[client] = xyvel;
}

int Colors(float speed)
{
	if (speed < 150)
	{
		return 0;
	}

	if (speed < 180)
	{
		return 1;
	}

	if (speed < 220)
	{
		return 2;
	}

	if (speed < 249)
	{
		return 3;
	}

	return 4;
}

int DuckColors(float speed)
{
	if (speed < 44)
	{
		return 0;
	}

	if (speed < 55)
	{
		return 1;
	}

	if (speed < 75)
	{
		return 2;
	}

	if (speed < 84)
	{
		return 3;
	}

	return 4;
}

stock bool IsValidClient(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}
