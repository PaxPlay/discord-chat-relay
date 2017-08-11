#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <socket>
#include <chatcolors>

#undef REQUIRE_PLUGIN
#include <chat-processor>

#pragma newdecls required


// Socket Handles
Handle gH_Socket = INVALID_HANDLE;

// Clients

// ConVars
ConVar gCV_SocketIP;
ConVar gCV_SocketPort;

ConVar gCV_ServerMessageTag;

char gS_ServerTag[128];

bool gB_ChatProcessor;

public Plugin myinfo = 
{
	name = "Discord Chat Relay - Client",
	author = "PaxPlay, Credits to Ryan \"FLOOR_MASTER\" Mannion, shavit and Deathknife",
	description = "Chat relay between a sourcemod server and Discord.",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart()
{
	gCV_SocketIP = CreateConVar("sm_discord_socket_ip", "", "IP adress of the server with the dcr-server plugin.");
	gCV_SocketPort = CreateConVar("sm_discord_socket_port", "13370", "Port for the chat relay socket.");
	
	gCV_ServerMessageTag = CreateConVar("sm_discord_chat_prefix_server", "{grey}[{green}[SERVER 2]{grey}", "Chat Tag for messages from the server.");
	
	gCV_ServerMessageTag.AddChangeHook(OnConVarChanged);
	
	AutoExecConfig(true, "discord-chat-relay-client", "sourcemod");
	
	gB_ChatProcessor = LibraryExists("chat-processor");
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	UpdateCvars();
}

void UpdateCvars()
{
	char buffer[128];
	gCV_ServerMessageTag.GetString(buffer, sizeof(buffer));
	SCC_ReplaceColors(buffer, sizeof(buffer));
	FormatEx(gS_ServerTag, sizeof(gS_ServerTag), "%s", buffer);	// Update Gameserver Chat Tag
}

public void OnConfigsExecuted()
{
	UpdateCvars();
	if(gH_Socket == INVALID_HANDLE)
	{
		char ip[24];
		int port = gCV_SocketPort.IntValue;
		gCV_SocketIP.GetString(ip, sizeof(ip));
	
		gH_Socket = SocketCreate(SOCKET_TCP, OnSocketError);
		SocketConnect(gH_Socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, ip, port);
		
		LogMessage("Connected to Server Chat Relay server on %s:%d", ip, port);
	}
	
	LogMessage("%s chat-processor. DCR %s be able to send messages.", gB_ChatProcessor ? "Found" : "Couldn\'t find", gB_ChatProcessor ? "will" : "won\'t");
}

public int OnSocketConnected(Handle socket, any arg)
{
	LogMessage("Connected to server.");
}

public int OnSocketReceive(Handle socket, char[] receiveData, const int dataSize, any arg)
{
	PrintToServer("[SCR] Received \"%s\"", receiveData);
	PrintToChatAll(" %s", receiveData);
}

public int OnSocketDisconnected(Handle socket, any arg) {
	if (gH_Socket != INVALID_HANDLE) {
		CloseHandle(gH_Socket);
		gH_Socket = INVALID_HANDLE;
		LogMessage("Closed local Server Chat Relay socket");
	}
}

public int OnSocketError(Handle socket, const int errorType, const int errorNum, any arg) {
	LogError("Socket error %d (errno %d)", errorType, errorNum);
	if (gH_Socket != INVALID_HANDLE) {
		CloseHandle(gH_Socket);
		gH_Socket = INVALID_HANDLE;
		LogMessage("Closed local Server Chat Relay socket");
	}
}

public void CP_OnChatMessagePost(int author, ArrayList recipients, const char[] flagstring, const char[] formatstring, const char[] name, const char[] message, bool processcolors, bool removecolors)
{
	if(message[0] == '!' || message[1] == '!') // remove chat commands
		return;
	
	char sMessage[512];
	Format(sMessage, sizeof(sMessage), "%s %s: %s", gS_ServerTag, name, message);
	
	SocketSend(gH_Socket, sMessage, sizeof(sMessage));
}