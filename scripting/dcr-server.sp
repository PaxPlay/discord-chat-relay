#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <discord>
#include <socket>
#include <chatcolors>

#undef REQUIRE_PLUGIN
#include <chat-processor>

#pragma newdecls required


// Socket Handles
Handle gH_Socket = INVALID_HANDLE;

// Clients
ArrayList gAL_Clients;

// Discord Bot
DiscordBot gDB_Bot = view_as<DiscordBot>(INVALID_HANDLE);

// ConVars
ConVar gCV_DiscordChatChannel;

ConVar gCV_DiscordEnable;

ConVar gCV_SocketEnable;
ConVar gCV_SocketPort;

ConVar gCV_ServerMessageTag;
ConVar gCV_DiscordMessageTag;

char gS_BotToken[128];

char gS_ServerTag[128];
char gS_DiscordTag[128];

bool gB_ChatProcessor;
bool gB_ListeningToDiscord = false;


public Plugin myinfo = 
{
	name = "Discord Chat Relay - Server",
	author = "PaxPlay, Credits to Ryan \"FLOOR_MASTER\" Mannion, shavit and Deathknife",
	description = "Chat relay between a sourcemod server and Discord.",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart()
{
	gCV_DiscordChatChannel = CreateConVar("sm_discord_text_channel_id", "", "The Discord text channel id.");
	
	gCV_DiscordEnable = CreateConVar("sm_discord_relay_enable", "1", "Enable the chat relay with Discord.", 0, true, 0.0, true, 1.0);
	
	gCV_SocketEnable = CreateConVar("sm_discord_socket_enable", "0", "Enable the cross server chat relay.", 0, true, 0.0, true, 1.0);
	gCV_SocketPort = CreateConVar("sm_discord_socket_port", "13370", "Port for the cross server chat relay socket.");
	
	gCV_ServerMessageTag = CreateConVar("sm_discord_chat_prefix_server", "{grey}[{green}SERVER{grey}]", "Chat Tag for messages from the server.");
	gCV_DiscordMessageTag = CreateConVar("sm_discord_chat_prefix_discord", "{grey}[{blue}DISCORD{grey}]", "Chat Tag for messages from discord.");
	
	gCV_ServerMessageTag.AddChangeHook(OnConVarChanged);
	gCV_DiscordMessageTag.AddChangeHook(OnConVarChanged);
	
	AutoExecConfig(true, "discord-chat-relay-server", "sourcemod");
	
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
	
	gCV_DiscordMessageTag.GetString(buffer, sizeof(buffer));
	SCC_ReplaceColors(buffer, sizeof(buffer));
	FormatEx(gS_DiscordTag, sizeof(gS_DiscordTag), "%s", buffer);	// Update Discord Chat Tag
}

bool LoadConfig()
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/dcr.cfg");
	
	if (!FileExists(sPath))
	{
		File hFile = OpenFile(sPath, "w");
		WriteFileLine(hFile, "\"discord-chat-relay\"");
		WriteFileLine(hFile, "{");
		WriteFileLine(hFile, "\t\"bot-token\"\t\"<insert-bot-token>\"");
		WriteFileLine(hFile, "}");
		CloseHandle(hFile);
		
		LogError("[DCR] \"%s\" not found, creating!", sPath);
		return false;
	}
	
	KeyValues kv = new KeyValues("discord-chat-relay");
	
	if(!kv.ImportFromFile(sPath))
	{
		delete kv;
		LogError("[DCR] Couldnt import KeyValues from \"%s\"!", sPath);
		
		return false;
	}
	
	kv.GetString("bot-token", gS_BotToken, sizeof(gS_BotToken));
	
	LogMessage("Loaded the BotToken.");
	
	delete kv;
	return true;
}

public void OnAllPluginsLoaded()
{
	if(gDB_Bot != view_as<DiscordBot>(INVALID_HANDLE))
		return;
	
	if (LoadConfig())
		gDB_Bot = new DiscordBot(gS_BotToken);
	else
		LogError("Couldnt load the dcr config.");
}

public void OnConfigsExecuted()
{
	UpdateCvars();
	
	if (gCV_DiscordEnable.BoolValue && gDB_Bot != view_as<DiscordBot>(INVALID_HANDLE))
	{
		if(!gB_ListeningToDiscord)
			gDB_Bot.GetGuilds(GuildList, INVALID_FUNCTION);
	}
	
	if(gCV_SocketEnable.BoolValue && gH_Socket == INVALID_HANDLE)
	{
		char ip[24];
		int port = gCV_SocketPort.IntValue;
		GetServerIP(ip, sizeof(ip));
		
		gH_Socket = SocketCreate(SOCKET_TCP, OnSocketError);
		SocketBind(gH_Socket, ip, port);
		SocketListen(gH_Socket, OnSocketIncoming);
		
		gAL_Clients = CreateArray();
		
		LogMessage("%s chat-processor. DCR %s be able to send messages.", gB_ChatProcessor ? "Found" : "Couldn\'t find", gB_ChatProcessor ? "will" : "won\'t");
	
		LogMessage("[DCR] Started Server Chat Relay server on port %d", port);
	}
}

public void GuildList(DiscordBot bot, char[] id, char[] name, char[] icon, bool owner, int permissions, any data)
{
	gDB_Bot.GetGuildChannels(id, ChannelList, INVALID_FUNCTION);
}

public void ChannelList(DiscordBot bot, char[] guild, DiscordChannel Channel, any data)
{
	if(Channel.IsText) {
		char id[32];
		Channel.GetID(id, sizeof(id));
		
		char sChannelID[64];
		gCV_DiscordChatChannel.GetString(sChannelID, sizeof(sChannelID));
		
		if(StrEqual(id, sChannelID) && !gB_ListeningToDiscord)
		{
			gDB_Bot.StopListening();
			
			char name[32];
			Channel.GetName(name, sizeof(name));
			gDB_Bot.StartListeningToChannel(Channel, OnMessage);
			
			LogMessage("[DCR] Started listening to channel %s (%s)", name, id);
			gB_ListeningToDiscord = true;
		}
	}
}

public void OnMessage(DiscordBot Bot, DiscordChannel Channel, DiscordMessage message)
{
	if (message.GetAuthor().IsBot())
		return;
	
	char sMessage[2048];
	message.GetContent(sMessage, sizeof(sMessage));
	
	char sAuthor[128];
	message.GetAuthor().GetUsername(sAuthor, sizeof(sAuthor));
	
	Format(sMessage, sizeof(sMessage), "%s \x01%s: %s", gS_DiscordTag, sAuthor, sMessage);
	
	PrintToChatAll(" %s", sMessage);
	Broadcast(INVALID_HANDLE, sMessage, sizeof(sMessage));
}

public void CP_OnChatMessagePost(int author, ArrayList recipients, const char[] flagstring, const char[] formatstring, const char[] name, const char[] message, bool processcolors, bool removecolors)
{
	if(message[0] == '!' || message[1] == '!') // remove chat commands
		return;
	
	char sMessage[512];
	Format(sMessage, sizeof(sMessage), "%s %s: %s", gS_ServerTag, name, message);
	
	Broadcast(INVALID_HANDLE, sMessage, sizeof(sMessage));
	
	SendToDiscord(sMessage ,sizeof(sMessage));
}

public void OnMessageSent(DiscordBot bot, char[] channel, DiscordMessage message, any data)
{
	char sMessage[2048];
	message.GetContent(sMessage, sizeof(sMessage));
	LogMessage("[SM] Message sent to discord: \"%s\".", sMessage);
}

void GetServerIP(char[] ip, int length)
{
	int hostip = FindConVar("hostip").IntValue;

	Format(ip, length, "%d.%d.%d.%d",
		(hostip >> 24 & 0xFF),
		(hostip >> 16 & 0xFF),
		(hostip >> 8 & 0xFF),
		(hostip & 0xFF)
		);
}

bool Broadcast(Handle socket, const char[] message, int maxlength)
{
	if(!gCV_SocketEnable.BoolValue)
		return false;
	
	if(gAL_Clients == INVALID_HANDLE)
	{
		LogError("In Broadcast, gAL_Clients was invalid. This should never happen!");
		return false;
	}
	
	
	int size = gAL_Clients.Length;
	Handle dest_socket = INVALID_HANDLE;
	
	for (int i = 0; i < size; i++)
	{
		dest_socket = gAL_Clients.Get(i);
		if (dest_socket != socket) // Prevent sending back to the same server.
		{
			SocketSend(dest_socket, message, maxlength);
		}
	}
	
	if (socket != INVALID_HANDLE) // Prevent printing to the server chat, if message is by the server.
	{
		PrintToChatAll(" %s", message);
	}
	return true;
}

void CloseSocket()
{
	if(gH_Socket != INVALID_HANDLE)
	{
		CloseHandle(gH_Socket);
		gH_Socket = INVALID_HANDLE;
		LogMessage("Closed local Server Chat Relay socket");
	}
	if(gAL_Clients != INVALID_HANDLE)
	{
		CloseHandle(gAL_Clients);
	}
}

void RemoveClient(Handle client)
{

	if (gAL_Clients == INVALID_HANDLE)
	{
		LogError("Attempted to remove client while g_clients was invalid. This should never happen!");
		return;
	}
	
	int size = gAL_Clients.Length;
	for (int i = 0; i < size; i++)
	{
		if(gAL_Clients.Get(i) == client)
		{
			gAL_Clients.Erase(i);
			return;
		}
	}
	
	LogError("Could not find client in RemoveClient. This should never happen!");
}

public int OnSocketIncoming(Handle socket, Handle newSocket, char[] remoteIP, int remotePort, any arg)
{
	if (gAL_Clients == INVALID_HANDLE) {
		LogError("In OnSocketIncoming, gAL_Clients was invalid. This should never happen!");
	}
	else {
		PushArrayCell(gAL_Clients, newSocket);
	}

	SocketSetReceiveCallback(newSocket, OnChildSocketReceive);
	SocketSetDisconnectCallback(newSocket, OnChildSocketDisconnected);
	SocketSetErrorCallback(newSocket, OnChildSocketError);
}

public int OnSocketDisconnected(Handle socket, any arg)
{
	CloseSocket();
}

public int OnSocketError(Handle socket, const int errorType, const int errorNum, any arg)
{
	LogError("Socket error %d (errno %d)", errorType, errorNum);
	CloseSocket();
}

public int OnChildSocketReceive(Handle socket, char[] receiveData, const int dataSize, any arg)
{
	Broadcast(socket, receiveData, dataSize);
	
	SendToDiscord(receiveData, dataSize);
}

public int OnChildSocketDisconnected(Handle socket, any arg) {
	RemoveClient(socket);
	CloseHandle(socket);
}

public int OnChildSocketError(Handle socket, const int errorType, const int errorNum, any arg)
{
	LogError("Child socket error %d (errno %d)", errorType, errorNum);
	RemoveClient(socket);
	CloseHandle(socket);
}

void SendToDiscord(const char[] message, int maxlength)
{
	char[] sMessage = new char[maxlength];
	FormatEx(sMessage, maxlength, "%s", message);
	
	SCC_RemoveColors(sMessage, maxlength);
	
	char sChannelID[64];
	gCV_DiscordChatChannel.GetString(sChannelID, sizeof(sChannelID));
	gDB_Bot.SendMessageToChannelID(sChannelID, sMessage, OnMessageSent);
}