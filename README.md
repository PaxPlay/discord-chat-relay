# Sourcemod Discord Chat Relay
Discord and cross server chat relay for sourcemod servers.

Requirements:
------
* [Discord API](https://github.com/Deathknife/sourcemod-discord)
  * [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556)
  * [smjansson](https://forums.alliedmods.net/showthread.php?t=184604)
* [Socket](https://forums.alliedmods.net/showthread.php?t=67640)
* (for compilation)[chatcolors include](https://github.com/PaxPlay/chatcolors-include)

Note: You'll need a discord app with bot. [How to create](https://github.com/Deathknife/sourcemod-discord/wiki/Setting-up-a-Bot-Account)

Installation:
------
1. Put the `dcr-server.smx`/`dcr-client.smx` in your servers `addons/sourcemod/plugins` directory.
2. For the `dcr-server.smx`, you have to copy the `dcr.cfg` to `addons/sourcemod/configs` and replace `<insert-bot-token>` with your bot token
3. Start the server once and modify the now created `cfg/sourcemod/discord-chat-relay-server.cfg`/`cfg/sourcemod/discord-chat-relay-client.cfg`. To get the Channel id, enable Developer Mode in Discords `Apperance -> Andvanced` settings and right click the channel you want to get the id from. Select `Copy ID` to copy the ID.
4. Restart the server.

How it works:
------
One gameserver (with dcr-server) connects to discord and acts as 'server' for the gameservers to connect to. If you send a message from Discord, the 'server' gameserver will retrieve it and send it to all other connected gameservers. If you send a message from a 'client' gameserver, the 'server' gameserver will send it to discord and all other connected gameservers. And finally, if you send a message from the 'server' gameserver, it'll send the message to Discord and every connected gameserver.