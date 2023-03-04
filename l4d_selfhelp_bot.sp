#pragma semicolon 1
#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.5"

#define SOUND_KILL1  "/weapons/knife/knife_hitwall1.wav"
#define SOUND_KILL2  "/weapons/knife/knife_deploy.wav"
#define GAMEDATA "l4d_selfhelp_bot"
#define PLUGIN_NAME "Self Help with bot support"
#define INCAP	         1
#define INCAP_GRAB	     2
#define INCAP_POUNCE     3
#define INCAP_RIDE		 4
#define INCAP_PUMMEL	 5
#define INCAP_EDGEGRAB	 6

#define TICKS 10
#define STATE_NONE 0
#define STATE_SELFHELP 1
#define STATE_OK 2
#define STATE_FAILED 3

new HelpState[MAXPLAYERS+1];
new HelpOtherState[MAXPLAYERS+1];
new Attacker[MAXPLAYERS+1];
new IncapType[MAXPLAYERS+1];
new Handle:Timers[MAXPLAYERS+1];
new Float:reviveDuration;
new Float:HelpStartTime[MAXPLAYERS+1];

new Handle:l4d_selfhelp_delay = INVALID_HANDLE;
new Handle:l4d_selfhelp_hintdelay = INVALID_HANDLE;

new Handle:l4d_selfhelp_incap = INVALID_HANDLE;
new Handle:l4d_selfhelp_grab = INVALID_HANDLE;
new Handle:l4d_selfhelp_pounce = INVALID_HANDLE;
new Handle:l4d_selfhelp_ride = INVALID_HANDLE;
new Handle:l4d_selfhelp_pummel = INVALID_HANDLE;
new Handle:l4d_selfhelp_edgegrab = INVALID_HANDLE;
new Handle:l4d_selfhelp_eachother = INVALID_HANDLE;
new Handle:l4d_selfhelp_pickup = INVALID_HANDLE;
new Handle:l4d_selfhelp_bot_delay = INVALID_HANDLE;
new Handle:l4d_selfhelp_duration = INVALID_HANDLE;
new Handle:l4d_selfhelp_announce = INVALID_HANDLE;
new Handle:l4d_selfhelp_adrenaline_rush = INVALID_HANDLE;
new Handle:l4d_selfhelp_kill = INVALID_HANDLE;
new Handle:l4d_selfhelp_versus = INVALID_HANDLE;
new Handle:hOnAdrenalineRush = null;
new Handle:hOnStagger = null ;
new Handle:hOnGameData = null;
new ConVar:cvarAdrenalineDuration;
float fAdrenalineDuration;
new Handle:hConf = null;

new L4D2Version=false;
public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = "Pan Xiaohai, Yani",
	description = "",
	version = PLUGIN_VERSION,	
}

public OnPluginStart()
{
	CreateConVar("l4d_selfhelp_version", PLUGIN_VERSION, " ", FCVAR_DONTRECORD);
	
	l4d_selfhelp_incap = CreateConVar("l4d_selfhelp_incap", "3", "self help for incap , 0:disable, 1:pill, 2:medkit, 3:both  ");
	l4d_selfhelp_grab = CreateConVar("l4d_selfhelp_grab", "3", " self help for grab , 0:disable, 1:pill, 2:medkit, 3:both ");
	l4d_selfhelp_pounce = CreateConVar("l4d_selfhelp_pounce", "3", " self help for pounce , 0:disable, 1:pill, 2:medkit, 3:both ");
	l4d_selfhelp_ride = CreateConVar("l4d_selfhelp_ride", "3", " self help for ride , 0:disable, 1:pill, 2:medkit, 3:both ");
	l4d_selfhelp_pummel = CreateConVar("l4d_selfhelp_pummel", "3", "self help for pummel , 0:disable, 1:pill, 2:medkit, 3:both  ");
	l4d_selfhelp_edgegrab = CreateConVar("l4d_selfhelp_edgegrab", "3", "self help for edgegrab , 0:disable, 1:pill, 2:medkit, 3:both  ");
	l4d_selfhelp_eachother = CreateConVar("l4d_selfhelp_eachother", "1", "incap help each other , 0: disable, 1 :enable  ");
	l4d_selfhelp_pickup = CreateConVar("l4d_selfhelp_pickup", "1", "incap pick up , 0: disable, 1 :enable  ");
	l4d_selfhelp_kill = CreateConVar("l4d_selfhelp_kill", "1", "kill attacker");
	l4d_selfhelp_announce = CreateConVar("l4d_selfhelp_announce_revive", "0", "Announce when others help themselves");
	l4d_selfhelp_adrenaline_rush =  CreateConVar("l4d_selfhelp_adrenaline_rush", "1", "Announce when others help themselves");
	l4d_selfhelp_hintdelay = CreateConVar("l4d_selfhelp_hintdelay", "4.0", "hint delay");
	l4d_selfhelp_delay = CreateConVar("l4d_selfhelp_delay", "1.0", "self help delay");
	l4d_selfhelp_bot_delay = CreateConVar("l4d_selfhelp_bot_delay", "10.0", "delay this amount of seconds before bots self-recover");
	l4d_selfhelp_duration = CreateConVar("l4d_selfhelp_duration", "3.0", "Override selfhelp duration with this amount of seconds");

	l4d_selfhelp_versus = CreateConVar("l4d_selfhelp_versus", "1", "0: disable in versus, 1: enable in versus");	
	
	AutoExecConfig(true, "l4d_selfhelp_bot");
	GameCheck();

	HookEvent("player_incapacitated", Event_Incap);

	HookEvent("lunge_pounce", lunge_pounce);
	HookEvent("pounce_stopped", pounce_stopped);
	HookEvent("player_ledge_grab", resetBot);
	HookEvent("player_incapacitated", resetBot);
	HookEvent("tongue_grab", tongue_grab);
	HookEvent("tongue_release", tongue_release);

	HookEvent("player_ledge_grab", player_ledge_grab);

	HookEvent("round_start", RoundStart);

	if(L4D2Version)
	{
		HookEvent("jockey_ride", jockey_ride);
		HookEvent("jockey_ride_end", jockey_ride_end);
		
		HookEvent("charger_pummel_start", charger_pummel_start);
		HookEvent("charger_pummel_end", charger_pummel_end);

	}
	cvarAdrenalineDuration = FindConVar("adrenaline_duration");
	fAdrenalineDuration = cvarAdrenalineDuration.FloatValue;
	
	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), "gamedata/%s.txt", GAMEDATA);
	if( FileExists(filePath))
	{
		hConf = LoadGameConfigFile(GAMEDATA); // For some reason this doesn't return null even for invalid files, so check they exist first.
	} else {
		PrintToServer("[SM] %s unable to get %s.txt gamedata file. Generating...", PLUGIN_NAME, GAMEDATA);

		hConf = LoadGameConfigFile(GAMEDATA);
		if (hConf == null)
		{ 
			SetFailState("[SH] Failed to load auto-generated gamedata file!"); 
		}
	}	

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hOnGameData, SDKConf_Signature, "OnStaggered");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);
	hOnStagger = EndPrepSDKCall();
	if (hOnStagger == null)
	{
		SetFailState("[SH] Signature 'OnStaggered' Broken!");
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hOnGameData, SDKConf_Signature, "OnAdrenalineUsed");
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	hOnAdrenalineRush = EndPrepSDKCall();
	if (hOnAdrenalineRush == null)
	{
		SetFailState("[SH] Signature 'OnAdrenalineUsed' Broken!");
	}

}

new GameMode;
GameCheck()
{
	decl String:GameName[16];
	GetConVarString(FindConVar("mp_gamemode"), GameName, sizeof(GameName));
	
	if (StrEqual(GameName, "survival", false))
	GameMode = 3;
	else if (StrEqual(GameName, "versus", false) || StrEqual(GameName, "teamversus", false) || StrEqual(GameName, "scavenge", false) || StrEqual(GameName, "teamscavenge", false))
	GameMode = 2;
	else if (StrEqual(GameName, "coop", false) || StrEqual(GameName, "realism", false))
	GameMode = 1;
	else
	{
		GameMode = 0;
	}
	
	GetGameFolderName(GameName, sizeof(GameName));
	if (StrEqual(GameName, "left4dead2", false))
	{

		L4D2Version=true;
	}	
	else
	{

		L4D2Version=false;
	}
}

public OnMapStart()
{
	if(L4D2Version)	PrecacheSound(SOUND_KILL2, true) ;
	else PrecacheSound(SOUND_KILL1, true) ;

}
public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	reset();
	return Plugin_Continue;
}

public lunge_pounce (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!victim) return;
	if (!attacker) return;
	Attacker[victim] = attacker;
	IncapType[victim]=INCAP_POUNCE;
	if(	GetConVarInt(l4d_selfhelp_pounce)>0)
	{
		CreateTimer(GetConVarFloat(l4d_selfhelp_delay), WatchPlayer, victim);	
		CreateTimer(GetConVarFloat(l4d_selfhelp_hintdelay), AdvertisePills, victim); 
	}
	//PrintToChatAll("start prounce"); 
}

public pounce_stopped (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;	
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!victim) return;
	Attacker[victim] = 0;
	//PrintToChatAll("end prounce"); 
}

public tongue_grab (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!victim) return;
	if (!attacker) return;
	Attacker[victim] = attacker;
	IncapType[victim]=INCAP_GRAB;
	if(	GetConVarInt(l4d_selfhelp_grab)>0)
	{
		CreateTimer(GetConVarFloat(l4d_selfhelp_delay), WatchPlayer, victim);	
		CreateTimer(GetConVarFloat(l4d_selfhelp_hintdelay), AdvertisePills, victim); 
	}
}

public tongue_release (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!victim) return;
	if (!attacker) return;
	if(Attacker[victim] ==attacker)
	{
		Attacker[victim] = 0;
	}
	//PrintToChatAll("end grab"); 

}

public jockey_ride (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!victim) return;
	if (!attacker) return;
	Attacker[victim] = attacker;
	IncapType[victim]=INCAP_RIDE;
	if(	GetConVarInt(l4d_selfhelp_ride)>0)
	{
		CreateTimer(GetConVarFloat(l4d_selfhelp_delay), WatchPlayer, victim);	
		CreateTimer(GetConVarFloat(l4d_selfhelp_hintdelay), AdvertisePills, victim); 
	}
	//PrintToChatAll("jockey_ride"); 
}

public jockey_ride_end (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!victim) return;
	if (!attacker) return;
	if(Attacker[victim] ==attacker)
	{
		Attacker[victim] = 0;
	}
	//PrintToChatAll("jockey_ride_end"); 

}

public charger_pummel_start (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!victim) return;
	if (!attacker) return;
	Attacker[victim] = attacker;
	IncapType[victim]=INCAP_PUMMEL;
	if(	GetConVarInt(l4d_selfhelp_pummel)>0)
	{
		CreateTimer(GetConVarFloat(l4d_selfhelp_delay), WatchPlayer, victim);	
		CreateTimer(GetConVarFloat(l4d_selfhelp_hintdelay), AdvertisePills, victim); 
	}
	//PrintToChatAll("charger_pummel_start"); 
}

public charger_pummel_end (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!victim) return;
	if (!attacker) return;
	if(Attacker[victim] ==attacker)
	{
		Attacker[victim] = 0;
	}
	//PrintToChatAll("charger_pummel_end"); 

}

public Event_Incap (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	IncapType[victim]=INCAP;
	if(GetConVarInt(l4d_selfhelp_incap)>0)
	{
		CreateTimer(GetConVarFloat(l4d_selfhelp_delay), WatchPlayer, victim);	
		CreateTimer(GetConVarFloat(l4d_selfhelp_hintdelay), AdvertisePills, victim); 
	}
}
public Action:player_ledge_grab(Handle:event, String:event_name[], bool:dontBroadcast)
{
	if(GameMode==2 && GetConVarInt(l4d_selfhelp_versus)==0)return;
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	IncapType[victim]=INCAP_EDGEGRAB;
	if(GetConVarInt(l4d_selfhelp_edgegrab)>0)
	{
		CreateTimer(GetConVarFloat(l4d_selfhelp_delay), WatchPlayer, victim);	
		CreateTimer(GetConVarFloat(l4d_selfhelp_hintdelay), AdvertisePills, victim); 
	}
}


public Action:WatchPlayer(Handle:timer, any:client)
{

	if (!client) return;
	if (!IsClientInGame(client)) return;
	if (!IsPlayerAlive(client)) return;
	if (!IsPlayerIncapped(client) && !IsPlayerGrapEdge(client) && Attacker[client]==0 )return;
	
	if(Timers[client]!=INVALID_HANDLE)return;

	HelpOtherState[client]=HelpState[client]=STATE_NONE;

	Timers[client]=CreateTimer(1.0/TICKS, PlayerTimer, client, TIMER_REPEAT);
}
public Action:AdvertisePills(Handle:timer, any:client)
{
	
	if (!client) return;
	if (!IsClientInGame(client)) return;
	if (!IsPlayerAlive(client)) return;

	if(CanSelfHelp(client))
	{
		if(GetConVarInt(l4d_selfhelp_announce) > 0) 
			PrintToChat(client, "Press \x04CROUCH\x03 to help yourself!");
	}

}
bool:CanSelfHelp(client)
{
	new bool:pills=HavePills(client);
	new bool:kid=HaveKit(client);
	new bool:adrenaline=HaveAdrenaline(client);
	new bool:ok=false;
	new self;
	if(IncapType[client]==INCAP)
	{
		self=GetConVarInt( l4d_selfhelp_incap);
		if((self==1 || self==3) && (pills || adrenaline))ok=true;
		else if ((self==2 || self==3) && kid)ok=true;
	}
	else if(IncapType[client]== INCAP_EDGEGRAB)
	{
		self=GetConVarInt( l4d_selfhelp_edgegrab);
		if((self==1 || self==3) && (pills || adrenaline))ok=true;
		else if ((self==2 || self==3) && kid)ok=true;
	}
	else if(IncapType[client]== INCAP_GRAB)
	{
		self=GetConVarInt( l4d_selfhelp_grab);
		if((self==1 || self==3) && (pills || adrenaline))ok=true;
		else if ((self==2 || self==3) && kid)ok=true;
	}
	else if(IncapType[client]== INCAP_POUNCE)
	{
		self=GetConVarInt( l4d_selfhelp_pounce);
		if((self==1 || self==3) && (pills || adrenaline))ok=true;
		else if ((self==2 || self==3) && kid)ok=true;
	}
	else if(IncapType[client]== INCAP_RIDE)
	{
		self=GetConVarInt( l4d_selfhelp_ride);
		if((self==1 || self==3) && (pills || adrenaline))ok=true;
		else if ((self==2 || self==3) && kid)ok=true;
	}
	else if(IncapType[client]== INCAP_PUMMEL)
	{
		self=GetConVarInt( l4d_selfhelp_pummel);
		if((self==1 || self==3) && (pills || adrenaline))ok=true;
		else if ((self==2 || self==3) && kid)ok=true;
	}
	return ok;
}
SelfHelpUseSlot(client)
{
	new pills = GetPlayerWeaponSlot(client, 4);
	new kid=GetPlayerWeaponSlot(client, 3);
	new slot=-1;
	new self;
	if(IncapType[client]==INCAP)
	{
		self=GetConVarInt( l4d_selfhelp_incap);
		if((self==1 || self==3) && pills!=-1)slot=4;
		else if ((self==2 || self==3) && kid)slot=3;
	}
	else if(IncapType[client]== INCAP_EDGEGRAB)
	{
		self=GetConVarInt( l4d_selfhelp_edgegrab);
		if((self==1 || self==3) && pills!=-1)slot=4;
		else if ((self==2 || self==3) && kid)slot=3;
	}
	else if(IncapType[client]== INCAP_GRAB)
	{
		self=GetConVarInt( l4d_selfhelp_grab);
		if((self==1 || self==3) && pills!=-1)slot=4;
		else if ((self==2 || self==3) && kid)slot=3;
	}
	else if(IncapType[client]== INCAP_POUNCE)
	{
		self=GetConVarInt( l4d_selfhelp_pounce);
		if((self==1 || self==3) && pills!=-1)slot=4;
		else if ((self==2 || self==3) && kid)slot=3;
	}
	else if(IncapType[client]== INCAP_RIDE)
	{
		self=GetConVarInt( l4d_selfhelp_ride);
		if((self==1 || self==3) && pills!=-1)slot=4;
		else if ((self==2 || self==3) && kid)slot=3;
	}
	else if(IncapType[client]== INCAP_PUMMEL)
	{
		self=GetConVarInt( l4d_selfhelp_pummel);
		if((self==1 || self==3) && pills!=-1)slot=4;
		else if ((self==2 || self==3) && kid)slot=3;
	}
	return slot;
}

public Action:PlayerTimer(Handle:timer, any:client)
{
	new Float:time=GetEngineTime();

	if (client==0 )
	{
		HelpOtherState[client]=HelpState[client]=STATE_NONE;
		Timers[client]=INVALID_HANDLE;
		return Plugin_Stop;
	}
	if(!IsClientInGame(client) || !IsPlayerAlive(client)  ) 
	{
		HelpOtherState[client]=HelpState[client]=STATE_NONE;
		Timers[client]=INVALID_HANDLE;
		return Plugin_Stop;
	}

	if( !IsPlayerIncapped(client) && !IsPlayerGrapEdge(client) && Attacker[client]==0)
	{

		HelpOtherState[client]=HelpState[client]=STATE_NONE;
		Timers[client]=INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if(!IsPlayerIncapped(client) && !IsPlayerGrapEdge(client) && Attacker[client]!=0)
	{
		if (!IsClientInGame(Attacker[client]) || !IsPlayerAlive(Attacker[client]))
		{
			HelpOtherState[client]=HelpState[client]=STATE_NONE;
			Timers[client]=INVALID_HANDLE;
			Attacker[client]=0;
			return Plugin_Stop;
		}

	}
	if(HelpState[client]==STATE_OK )
	{
		HelpOtherState[client]=HelpState[client]=STATE_NONE;
		Timers[client]=INVALID_HANDLE;
		return Plugin_Stop;
	}

	new buttons = GetClientButtons(client);

	new haveone=0;
	new PillSlot = GetPlayerWeaponSlot(client, 4);  
	new KidSlot=GetPlayerWeaponSlot(client, 3);

	if (PillSlot != -1)  
	{
		haveone++;
	}
	if(KidSlot !=-1)
	{
		if(HaveKit(client))haveone++;
	}
	
	if(haveone>0)
	{
		if((buttons & IN_DUCK) ||  (buttons & IN_USE)) 
		{
			if(CanSelfHelp(client))
			{
				if(L4D2Version)
				{
					if(HelpState[client]==STATE_NONE)
					{
						HelpStartTime[client]=time;						
						SetupProgressBar(client, reviveDuration);
					}

				}
				else
				{
					if(HelpState[client]==STATE_NONE) HelpStartTime[client]=time;
					ShowBar(client,"self help ", time-HelpStartTime[client], reviveDuration);
				}
				HelpState[client]=STATE_SELFHELP;
				//PrintToChatAll("%f  %f", time-HelpStartTime[client], reviveDuration);
				if((time-HelpStartTime[client])>reviveDuration)
				{
					if(HelpState[client]!=STATE_OK)
					{

						SelfHelp(client);
						if(L4D2Version)KillProgressBar(client);
					}

				}					
			}
			else if(HelpState[client]==STATE_SELFHELP)
			{
				if(L4D2Version)KillProgressBar(client);
				HelpState[client]=STATE_NONE;
			}
		}
		else
		{
			if(HelpState[client]==STATE_SELFHELP)
			{
				if(L4D2Version)
				{
					KillProgressBar(client);
				}
				else 
				{
					ShowBar(client, "self help ", 0.0, reviveDuration);
				}
				HelpState[client]=STATE_NONE;
			}
			
		}

	}
	else if(GetConVarInt(l4d_selfhelp_eachother)>0)
	{

		if (buttons & IN_USE)
		{

			new Float:dis=50.0;
			new Float:pos[3];
			new Float:targetVector[3];
			GetClientEyePosition(client, pos);
			new bool:findone=false;
			new other=0;
			for (new target = 1; target <= MaxClients; target++)
			{
				if (IsClientInGame(target) && target!=client)
				{
					if (IsPlayerAlive(target))
					{
						if(GetClientTeam(target)==2 && (IsPlayerIncapped(target) || IsPlayerGrapEdge(target)))
						{ 
							GetClientAbsOrigin(target, targetVector);
							new Float:distance = GetVectorDistance(targetVector, pos);
							if(distance<dis)
							{
								findone=true;
								other=target;
								break;
							}
						}
					}
				}
			}
			if(findone)
			{
				decl String:msg[30];
				Format(msg, sizeof(msg), "You are helping %N", other);
				if(HelpOtherState[client]==STATE_NONE)
				{
					if(L4D2Version) 
					{
						SetupProgressBar(client, reviveDuration);
						PrintToChat(client, msg);											 
					}
					PrintToChat(other, "%N is helping you", client);
					HelpStartTime[client]=time;
				}
				HelpOtherState[client]=STATE_SELFHELP;

				if(!L4D2Version) ShowBar(client, msg, time-HelpStartTime[client],reviveDuration);

				if(time-HelpStartTime[client]>reviveDuration)
				{
					HelpOther(other, client);
					HelpOtherState[client]=STATE_NONE;
					if(L4D2Version) KillProgressBar(client);							
				}

			}
			else
			{
				if(HelpOtherState[client]!=STATE_NONE)
				{
					if(L4D2Version) KillProgressBar(client);
					else ShowBar(client, "help other", 0.0, reviveDuration);
				}
				HelpOtherState[client]=STATE_NONE;

			}
		}
		else
		{
			if(HelpOtherState[client]!=STATE_NONE)
			{
				if(L4D2Version) KillProgressBar(client);
				else ShowBar(client, "help other", 0.0, reviveDuration);
			}
			HelpOtherState[client]=STATE_NONE;

		}
	}

	if ((buttons & IN_DUCK) && GetConVarInt(l4d_selfhelp_pickup)>0 ) 
	{	
		new bool:pickup=false;
		new Float:dis=100.0;
		new ent = -1;
		if (PillSlot == -1)  
		{
			decl Float:targetVector1[3];
			decl Float:targetVector2[3];
			GetClientEyePosition(client, targetVector1);
			ent=-1;
			while ((ent = FindEntityByClassname(ent,  "weapon_pain_pills" )) != -1)
			{
				if (IsValidEntity(ent))
				{
					GetEntPropVector(ent, Prop_Send, "m_vecOrigin", targetVector2);
					if(GetVectorDistance(targetVector1  , targetVector2)<dis)
					{

						CheatCommand(client, "give", "pain_pills", "");
						RemoveEdict(ent);
						pickup=true;
						PrintHintText(client,"You found pills!");

						break;
					}
				}
			}
			if(!pickup)
			{
				ent = -1;
				while ((ent = FindEntityByClassname(ent,  "weapon_adrenaline" )) != -1)
				{
					if (IsValidEntity(ent))
					{
						GetEntPropVector(ent, Prop_Send, "m_vecOrigin", targetVector2);
						if(GetVectorDistance(targetVector1  , targetVector2)<dis)
						{

							CheatCommand(client, "give", "adrenaline", "");
							RemoveEdict(ent);
							pickup=true;
							PrintHintText(client,"You found adrenaline!");
							
							break;
						}
					}
				}

			}
		}
		if (KidSlot == -1 && !pickup)  
		{
			decl Float:targetVector1[3];
			decl Float:targetVector2[3];
			GetClientEyePosition(client, targetVector1);
			ent = -1;
			while ((ent = FindEntityByClassname(ent,  "weapon_first_aid_kit" )) != -1)
			{
				if (IsValidEntity(ent))
				{
					GetEntPropVector(ent, Prop_Send, "m_vecOrigin", targetVector2);
					if(GetVectorDistance(targetVector1  , targetVector2)<dis)
					{

						CheatCommand(client, "give", "first_aid_kit", "");
						RemoveEdict(ent);
						pickup=true;
						PrintHintText(client,"You found medkit!");
						break;
					}
				}
			}
		}
		if (GetPlayerWeaponSlot(client, 1)==-1 && !pickup)  
		{
			decl Float:targetVector1[3];
			decl Float:targetVector2[3];
			GetClientEyePosition(client, targetVector1);
			ent = -1;
			while ((ent = FindEntityByClassname(ent,  "weapon_pistol" )) != -1)
			{
				if (IsValidEntity(ent))
				{
					GetEntPropVector(ent, Prop_Send, "m_vecOrigin", targetVector2);
					if(GetVectorDistance(targetVector1  , targetVector2)<dis)
					{
						CheatCommand(client, "give", "pistol", "");
						RemoveEdict(ent);
						pickup=true;
						PrintHintText(client,"You found useless pistol!");
						break;
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

SelfHelp(client)
{

	if (!IsClientInGame(client) || !IsPlayerAlive(client) )
	{
		return;
	} 
	if( !IsPlayerIncapped(client) && !IsPlayerGrapEdge(client) && Attacker[client]==0) 
	{
		return;
	} 
	new bool:pills=HavePills(client);

	new bool:adrenaline=HaveAdrenaline(client);
	new slot=SelfHelpUseSlot(client);
	if(slot!=-1)
	{
		new weaponslot=GetPlayerWeaponSlot(client, slot);
		if(slot ==4)
		{
			if(GetConVarInt(l4d_selfhelp_kill)>0) KillAttack(client);
			RemovePlayerItem(client, weaponslot);

			ReviveClientWithPills(client);
			

			HelpState[client]=STATE_OK;
			
			if(adrenaline) { 
				if(GetConVarInt(l4d_selfhelp_announce) > 0) 
					PrintToChatAll("\x04%N\x03 helped himself with adrenaline!", client); 
				if(GetConVarInt(l4d_selfhelp_adrenaline_rush) > 0) { 
					if (!GetEntProp(client, Prop_Send, "m_bAdrenalineActive", 1))
					{
						SetEntProp(client, Prop_Send, "m_bAdrenalineActive", 1, 1);
					}
					
					Event eAdrenalineUsed = CreateEvent("adrenaline_used", true);
					eAdrenalineUsed.SetInt("userid", GetClientUserId(client));
					eAdrenalineUsed.Fire();
					
					SDKCall(hOnAdrenalineRush, client, fAdrenalineDuration);
				}
			}
			else if(pills)	{
				
				if(GetConVarInt(l4d_selfhelp_announce) > 0) 
					PrintToChatAll("\x04%N\x03 helped himself with pills!", client); 	
			}
			//EmitSoundToClient(client, "player/items/pain_pills/pills_use_1.wav"); // add some sound
		}
		else if(slot==3)
		{
			if(GetConVarInt(l4d_selfhelp_kill)>0) KillAttack(client);
			RemovePlayerItem(client, weaponslot);

			ReviveClientWithKid(client);
			
			HelpState[client]=STATE_OK;
			if(GetConVarInt(l4d_selfhelp_announce) > 0) 
				PrintToChatAll("\x04%N\x03 helped himself with medkit!", client); 

			//EmitSoundToClient(client, "player/items/pain_pills/pills_use_1.wav"); // add some sound
		}

	}
	else 
	{
		PrintHintText(client, "help self failed");
		HelpState[client]=STATE_FAILED;
	}
}
HelpOther(client, helper)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client) )
	{
		return;
	} 
	if( !IsPlayerIncapped(client) && !IsPlayerGrapEdge(client) && Attacker[client]==0) 
	{
		return;
	}
	new propincapcounter = FindSendPropInfo("CTerrorPlayer", "m_currentReviveCount");
	new count = GetEntData(client, propincapcounter, 1);

	count++;
	if(count>2)count=2;

	new userflags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	new iflags=GetCommandFlags("give");
	SetCommandFlags("give", iflags & ~FCVAR_CHEAT);
	FakeClientCommand(client,"give health");
	SetCommandFlags("give", iflags);
	SetUserFlagBits(client, userflags);

	SetEntData(client, propincapcounter, count, 1);

	new Handle:revivehealth = FindConVar("pain_pills_health_value");  

	new temphpoffset = FindSendPropInfo("CTerrorPlayer","m_healthBuffer");
	SetEntDataFloat(client, temphpoffset, GetConVarFloat(revivehealth), true);
	SetEntityHealth(client, 1);
	PrintToChatAll("\x04%N\x03 helped\x04 %N \x03 when incapacitated", helper, client);  
	//first(client);
}
ReviveClientWithKid(client)
{
	new propincapcounter = FindSendPropInfo("CTerrorPlayer", "m_currentReviveCount");
	new userflags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	new iflags=GetCommandFlags("give");
	SetCommandFlags("give", iflags & ~FCVAR_CHEAT);
	FakeClientCommand(client,"give health");
	SetCommandFlags("give", iflags);
	SetUserFlagBits(client, userflags);
	SetEntData(client, propincapcounter, 0, 1);
	new Handle:revivehealth = FindConVar("first_aid_heal_percent"); 
	new temphpoffset = FindSendPropInfo("CTerrorPlayer","m_healthBuffer");
	SetEntDataFloat(client, temphpoffset, GetConVarFloat(revivehealth)*100.0, true);
	SetEntityHealth(client, 1);
}
ReviveClientWithPills(client)
{

	new propincapcounter = FindSendPropInfo("CTerrorPlayer", "m_currentReviveCount");
	new count = GetEntData(client, propincapcounter, 1);
	count++;
	if(count>2)count=2;
	CheatCommand(client, "give", "health", "");
	
	SetEntData(client, propincapcounter,count, 1);
	
	new Handle:revivehealth = FindConVar("pain_pills_health_value");  
	new temphpoffset = FindSendPropInfo("CTerrorPlayer","m_healthBuffer");
	SetEntDataFloat(client, temphpoffset, GetConVarFloat(revivehealth), true);
	SetEntityHealth(client, 1);
}

KillAttack(client)
{
	new a=Attacker[client];
	if(GetConVarInt(l4d_selfhelp_kill)==1 && a!=0)
	{
		if(IsClientInGame(a) && GetClientTeam(a)==3 &&  IsPlayerAlive(a))
		{
			ForcePlayerSuicide(a);		
			if(L4D2Version)	EmitSoundToAll(SOUND_KILL2, client); 
			else EmitSoundToAll(SOUND_KILL1, client); 
		}

		if (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1))
		{
			SetEntProp(client, Prop_Send, "m_isIncapacitated", 0, 1);
			if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1))
			{
				SetEntProp(client, Prop_Send, "m_isHangingFromLedge", 0, 1);
				SetEntProp(client, Prop_Send, "m_isFallingFromLedge", 0, 1);
			}
		}
	}
}

bool:HaveKit(client)
{
	decl String:weapon[32];
	new KidSlot=GetPlayerWeaponSlot(client, 3);

	if(KidSlot !=-1)
	{
		GetEdictClassname(KidSlot, weapon, 32);
		if(StrEqual(weapon, "weapon_first_aid_kit"))
		{
			return true;
		}
	}
	return false;
}
bool:HavePills(client)
{
	decl String:weapon[32];
	new KidSlot=GetPlayerWeaponSlot(client, 4);

	if(KidSlot !=-1)
	{
		GetEdictClassname(KidSlot, weapon, 32);
		if(StrEqual(weapon, "weapon_pain_pills"))
		{
			return true;
		}
	}
	return false;
}
bool:HaveAdrenaline(client)
{
	decl String:weapon[32];
	new KidSlot=GetPlayerWeaponSlot(client, 4);

	if(KidSlot !=-1)
	{
		GetEdictClassname(KidSlot, weapon, 32);
		if(StrEqual(weapon, "weapon_adrenaline"))
		{
			return true;
		}
	}
	return false;
}


bool:IsPlayerIncapped(client)
{
	if (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1)) return true;
	return false;
}
bool:IsPlayerGrapEdge(client)
{
	if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1))return true;
	return false;
}
reset()
{
	for (new x = 0; x < MAXPLAYERS+1; x++)
	{
		HelpOtherState[x]=HelpState[x]=STATE_NONE;
		Attacker[x]=0;
		HelpStartTime[x]=0.0;
		if(Timers[x]!=INVALID_HANDLE)
		{
			KillTimer(Timers[x]);

		}
		Timers[x]=INVALID_HANDLE;
	}
}
stock SetupProgressBar(client, Float:time)
{
	SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
	SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", time);
}

stock KillProgressBar(client)
{
	
	SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
	SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
}
new String:Gauge1[2] = "-";
new String:Gauge3[2] = "#";

public ShowBar(client, String:msg[], Float:pos, Float:max)
{
        new i;
        new String:ChargeBar[100];
        Format(ChargeBar, sizeof(ChargeBar), "");

        new Float:GaugeNum = pos/max*100;
        if(GaugeNum > 100.0)
        GaugeNum = 100.0;
        if(GaugeNum<0.0)
        GaugeNum = 0.0;
        for(i=0; i<100; i++)
        ChargeBar[i] = Gauge1[0];
        new p=RoundFloat( GaugeNum);

        if(p>=0 && p<100)ChargeBar[p] = Gauge3[0];
        /* Display gauge */
        PrintHintText(client, "%s  %3.0f %\n<< %s >>", msg, GaugeNum, ChargeBar);
}

// Get medpack item entity
stock int GetMedkitEntity(const int client){
	int Tmp = GetPlayerWeaponSlot(client, 3);
	return ((HaveKit(client) && IsValidEntity(Tmp)) ? Tmp : -1);
}

// Get health item entity
stock int GetHealthItemEntity(const int client){
	int Tmp = GetPlayerWeaponSlot(client, 4);
	return ((IsValidEntity(Tmp)) ? Tmp : -1);
}
// Return true if  Can Auto revive, or return true and take items if Take = true
bool ManageClientInventory(const int client,const bool Take = false){
	if((!IsIncapacitated(client) && !IsHanging(client)) || capped(client)){ return false;}
	int Temp = GetHealthItemEntity(client);
	int Kit  = GetMedkitEntity(client);
	int item = Temp>0?Temp:Kit>0?Kit:-1;
	return (item ==-1) ? false : (Take ? RemovePlayerItem(client, item) : true);
}
// if player can self help display a message for them, also starts ot selff help timer
public void resetBot(Event event, char []hEvent, bool dontBroadcast){
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int botdelay = GetConVarInt(l4d_selfhelp_bot_delay);	
	float fBotdelay = GetConVarFloat(l4d_selfhelp_bot_delay);	

	if(CanSelfHelp(client)) {

		if(IsFakeClient(client))
		{
			if(GetConVarInt(l4d_selfhelp_announce) > 0) 
				PrintToChatAll("%N Will revive in %i seconds",client, botdelay );
			
			CreateTimer(fBotdelay, AutoHelpBot,client,TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);	
		} else {
			//PrintToChat(client,"Hold CROUCH to help yourself up!");
		}
	}		
}

public Action AutoHelpBot(Handle hTimer, int client)
{
	if(((client < 0) || (client > MaxClients)) || !IsClientInGame(client))
	return Plugin_Stop;
	if(!IsPlayerAlive(client) || (GetClientTeam(client) != 2))
	return Plugin_Stop;

	if(ManageClientInventory(client,true) && IsFakeClient(client) && !capped(client))
	{
		CheatCommand(client, "give", "health", "");
		SetEntDataFloat(client, FindSendPropInfo("CTerrorPlayer","m_healthBuffer"), 60.0, true);
		SetEntityHealth(client, 1);
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

stock bool IsIncapacitated(const int client){
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_isIncapacitated"));
}

stock bool IsHanging(const int client){
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_isHangingFromLedge"));
}

stock void CheatCommand(const int client, char []command, char []parameter1, char []parameter2)
{
	int userflags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s %s", command, parameter1, parameter2);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userflags);
}

bool capped(const int client){
	return 
	(GetEntPropEnt(client, Prop_Send, "m_tongueOwner"   ) > 0) ? true : 
	(GetEntPropEnt(client, Prop_Send, "m_carryAttacker" ) > 0) ? true : 
	(GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0) ? true : false;          
}
