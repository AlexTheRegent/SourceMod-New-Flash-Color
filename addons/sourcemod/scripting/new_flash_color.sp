// ==============================================================================================================================
// >>> GLOBAL INCLUDES
// ==============================================================================================================================
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN 
#include <clientprefs>

// ==============================================================================================================================
// >>> PLUGIN INFORMATION
// ==============================================================================================================================
#define PLUGIN_VERSION "1.0"
public Plugin:myinfo =
{
	name 			= "New Flash Color",
	author 			= "AlexTheRegent",
	description 	= "",
	version 		= PLUGIN_VERSION,
	url 			= ""
}

// ==============================================================================================================================
// >>> DEFINES
// ==============================================================================================================================
//#pragma newdecls required
#define MPS 		MAXPLAYERS+1
#define PMP 		PLATFORM_MAX_PATH
#define MTF 		MENU_TIME_FOREVER
#define CID(%0) 	GetClientOfUserId(%0)
#define UID(%0) 	GetClientUserId(%0)
#define SZF(%0) 	%0, sizeof(%0)
#define LC(%0) 		for (new %0 = 1; %0 <= MaxClients; ++%0) if ( IsClientInGame(%0) ) 

#define DEBUG
#if defined DEBUG
stock DebugMessage(const String:message[], any:...)
{
	decl String:sMessage[256];
	VFormat(sMessage, sizeof(sMessage), message, 2);
	PrintToServer("[Debug] %s", sMessage);
}
#define DbgMsg(%0); DebugMessage(%0);
#else
#define DbgMsg(%0);
#endif

// ==============================================================================================================================
// >>> CONSOLE VARIABLES
// ==============================================================================================================================
new Handle:	g_convarColorCT;
new Handle:	g_convarColorT;
new Handle:	g_convarAllowColorChange;
new Handle:	g_convarNoTeamFlash;

new bool:	g_cvAllowColorChange;
new bool:	g_cvNoTeamFlash;
new 		g_cvColorCT[3];
new 		g_cvColorT[3];

// ==============================================================================================================================
// >>> GLOBAL VARIABLES
// ==============================================================================================================================
new Handle:	g_arrayFlashbangs;
new Handle:	g_cookies;
new Float:	g_holdDuration[MPS];
new 		g_offsetFlashMaxAlpha;
new 		g_offsetFlashDuration;
new 		g_colors[MPS][3];

// ==============================================================================================================================
// >>> LOCAL INCLUDES
// ==============================================================================================================================


// ==============================================================================================================================
// >>> FORWARDS
// ==============================================================================================================================
public OnPluginStart() 
{
	g_cookies = RegClientCookie("sm_new_flash_color", "new color of flashbang", CookieAccess_Protected);
	g_offsetFlashMaxAlpha = FindSendPropInfo("CCSPlayer", "m_flFlashMaxAlpha");
	g_offsetFlashDuration = FindSendPropInfo("CCSPlayer", "m_flFlashDuration");
	g_arrayFlashbangs = CreateArray();
	
	g_convarColorCT 			= CreateConVar("sm_new_flash_color_ct_color"			, "0 0 255"	, "Default color for CT flashbangs. 0 for random colors of flashbangs");
	g_convarColorT 				= CreateConVar("sm_new_flash_color_t_color"				, "255 0 0"	, "Default color for T flashbangs. 0 for random colors of flashbangs");
	g_convarAllowColorChange 	= CreateConVar("sm_new_flash_color_allow_color_change"	, "0"		, "1 = clients can change their colors");
	g_convarNoTeamFlash 		= CreateConVar("sm_new_flash_color_no_team_flash"		, "0"		, "1 = disable team flash");
	AutoExecConfig(true, "new_flash_color");
	
	HookEvent("round_start"			, Ev_RoundStart);
	HookEvent("player_blind"		, Ev_PlayerBlind);
	HookEvent("flashbang_detonate"	, Ev_FlashbangDetonate);
	
	RegConsoleCmd("sm_new_flash_color", Command_SetNewFlashColor);
}

public OnMapStart() 
{
	
}

public OnConfigsExecuted() 
{
	decl String:buffer[32];
	GetConVarString(g_convarColorCT, SZF(buffer));
	if ( !GetColorFromString(buffer, g_cvColorCT) ) {
		LogError("Invalid color for convar \"sm_new_flash_color_ct_color\", plugin will use random color for CT");
		g_cvColorCT[0] = -1;
	}
	GetConVarString(g_convarColorT, SZF(buffer));
	if ( !GetColorFromString(buffer, g_cvColorT) ) {
		LogError("Invalid color for convar \"sm_new_flash_color_t_color\", plugin will use random color for T");
		g_cvColorT[0] = -1;
	}
	
	g_cvAllowColorChange = GetConVarBool(g_convarAllowColorChange);
	// g_cvAllowColorChange = true;
	g_cvNoTeamFlash = GetConVarBool(g_convarNoTeamFlash);
	// g_cvNoTeamFlash = true;
	
	LC(i) {
		OnClientCookiesCached(i);
	}
}

bool:GetColorFromString(String:color[], output[])
{
	decl String:colors[3][8];
	new length = ExplodeString(color, " ", SZF(colors), sizeof(colors[]));
	if ( length == 3 ) {
		for ( new i = 0; i < 3; ++i ) {
			output[i] = StringToInt(colors[i]);
		}
		return true;
	}
	else if ( length == 1 ) {
		output[0] = -1;
		return true;
	}
	return false;
}

public OnEntityCreated(entity, const String:classname[])
{
	if ( StrEqual(classname, "flashbang_projectile") ) {
		CreateTimer(0.0, Timer_OnFlashbangCreated, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:Timer_OnFlashbangCreated(Handle:timer, any:entRef)
{
	new entity = EntRefToEntIndex(entRef);
	if ( entity != INVALID_ENT_REFERENCE ) {
		new owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
		PushArrayCell(g_arrayFlashbangs, UID(owner));
	}
}

public OnClientCookiesCached(client)
{
	if ( g_cvAllowColorChange ) {
		decl String:buffer[32];
		GetClientCookie(client, g_cookies, SZF(buffer));
		if ( buffer[0] ) {
			g_colors[client][0] = -2;
		}
		else if ( !GetColorFromString(buffer, g_colors[client]) ) {
			g_colors[client][0] = -1;
		}
	}
	else {
		g_colors[client][0] = -2;
	}
}

public OnClientDisconnect(client)
{
	decl String:buffer[32];
	FormatEx(SZF(buffer), "%d %d %d", g_colors[client][0], g_colors[client][1], g_colors[client][2]);
	SetClientCookie(client, g_cookies, buffer);
}

// ==============================================================================================================================
// >>> 
// ==============================================================================================================================
public Ev_RoundStart(Handle:event, const String:ev_name[], bool:silent)
{
	ClearArray(g_arrayFlashbangs);
}

public Ev_PlayerBlind(Handle:event, const String:ev_name[], bool:silent)
{
	if ( GetArraySize(g_arrayFlashbangs) != 0 ) {
		new Handle:datapack = CreateDataPack(), attacker = GetArrayCell(g_arrayFlashbangs, 0), client = GetEventInt(event, "userid");
		WritePackCell(datapack, attacker);
		WritePackCell(datapack, client);
		
		CreateTimer(0.0, Timer_BlindClient, datapack, TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:Timer_BlindClient(Handle:timer, any:datapack)
{
	ResetPack(datapack);
	new attacker = CID(ReadPackCell(datapack)), client = CID(ReadPackCell(datapack));
	if ( attacker && client ) {
		new Float:flashAlpha = GetEntDataFloat(client, g_offsetFlashMaxAlpha);
		SetEntDataFloat(client, g_offsetFlashMaxAlpha, 0.5);
		if ( g_cvNoTeamFlash && GetClientTeam(attacker) == GetClientTeam(client) ) {
			return Plugin_Continue;
		}
		
		PerformFade(client, attacker, flashAlpha);
	}
	
	return Plugin_Continue;
}

PerformFade(client, attacker, Float:flashAlpha)
{
	new fade_duration = RoundToNearest(GetEntDataFloat(client, g_offsetFlashDuration)) * 1000,
		hold_duration = RoundToNearest(fade_duration * 0.25);
		
	new Float:time = GetEngineTime(), color[4];
	DeterminateColor(attacker, color);
	if ( flashAlpha < 250.0 ) {
		if ( g_holdDuration[client] > time ) {
			return;
		}
		
		color[3] = 230;
	}
	else {
		if ( g_holdDuration[client] > time+hold_duration/1000.0 ) {
			return;
		}
		
		g_holdDuration[client] = time+hold_duration/1000.0;
		color[3] = 255;
	}
	
	new Handle:message = StartMessageOne("Fade", client);
	if ( GetUserMessageType() == UM_Protobuf ) {
		PbSetInt(message	, "duration"	, fade_duration - hold_duration); 
		PbSetInt(message	, "hold_time"	, hold_duration); 
		PbSetInt(message	, "flags"		, 0x0010|0x0001); // FFADE_PURGE|FFADE_IN
		PbSetColor(message	, "clr"			, color); 
	} else {
		BfWriteShort(message, fade_duration - hold_duration); 
		BfWriteShort(message, hold_duration); 
		BfWriteShort(message, 0x0010|0x0001); // FFADE_PURGE|FFADE_IN
		BfWriteByte(message	, color[0]); 
		BfWriteByte(message	, color[1]); 
		BfWriteByte(message	, color[2]); 
		BfWriteByte(message	, color[3]); 
	}
	EndMessage();
}

DeterminateColor(client, color[])
{
	if ( g_colors[client][0] == -2 ) {
		switch ( GetClientTeam(client) ) {
			case 2: {
				SetColor(color, g_cvColorT);
			}
			case 3: {
				SetColor(color, g_cvColorCT);
			}
		}
	}
	else {
		SetColor(color, g_colors[client]);
	}
}

SetColor(output[], color[])
{
	if ( color[0] == -1 ) {
		for ( new i = 0; i < 3; ++i ) {
			output[i] = GetRandomInt(0, 255);
		}
	}
	else {
		for ( new i = 0; i < 3; ++i ) {
			output[i] = color[i];
		}
	}
}

public Ev_FlashbangDetonate(Handle:event, const String:ev_name[], bool:silent)
{
	RemoveFromArray(g_arrayFlashbangs, 0);
}


// ==============================================================================================================================
// >>> 
// ==============================================================================================================================
public Action:Command_SetNewFlashColor(client, argc)
{
	if ( g_cvAllowColorChange ) {
		decl String:buffer[32], colors[3];
		GetCmdArgString(SZF(buffer));
		StripQuotes(buffer);
		
		if ( argc == 1 ) {
			if ( StrEqual(buffer, "team") ) {
				g_colors[client][0] = -2;
			}
			if ( StrEqual(buffer, "random") ) {
				g_colors[client][0] = -1;
			}
			else if ( GetColorFromString(buffer, colors) ) {
				DbgMsg("%d %d %d", colors[0], colors[1], colors[2]);
				g_colors[client] = colors;
			}
			else {
				ReplyToCommand(client, "SYNTAX:\n\tsm_new_flash_color <default|random>");
			}
		}
		else if ( argc == 3 ) {
			DbgMsg(buffer);
			
			if ( GetColorFromString(buffer, colors) ) {
				g_colors[client] = colors;
			}
			else {
				ReplyToCommand(client, "SYNTAX:\n\tsm_new_flash_color <RR> <GG> <BB>");
			}
		}
		else {
			ReplyToCommand(client, "SYNTAX:\n\tsm_new_flash_color default\n\tsm_new_flash_color <R> <G> <B>");
		}
	}
	
	DbgMsg("%N -> %d %d %d", client, g_colors[client][0], g_colors[client][1], g_colors[client][2]);
	
	return Plugin_Handled;
}