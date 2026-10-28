#pragma semicolon 1

#include <sourcemod>
#include "W3SIncs/War3Source_Interface"

public Plugin:myinfo = 
{
    name = "War3Source - Engine - Database Connect",
    author = "War3Source Team",
    description = "Connects War3Source to the database"
};

new Handle:hDB;
new War3SQLType:g_SQLType; 

public OnAllPluginsLoaded()
{
    ConnectDB();
}

ConnectDB()
{
    // Todo: Translation
    PrintToServer("[War3Source] Connecting to Database");
    new String:sCachedDBIName[256];
    new String:dbErrorMsg[512];

    new Handle:keyValue = CreateKeyValues("War3SourceSettings");
    decl String:path[1024];
    BuildPath(Path_SM, path, sizeof(path), "configs/war3source.ini");
    FileToKeyValues(keyValue, path);

    // Load level configuration
    KvRewind(keyValue);
    new String:sDBConnect[256];
    KvGetString(keyValue, "database", sDBConnect, sizeof(sDBConnect), "default");
    decl String:sError[256];
    strcopy(sCachedDBIName, 256, sDBConnect);
    
    if(StrEqual(sDBConnect, "", false) || StrEqual(sDBConnect, "default", false))
    {
        // use default connect, returns a handle...
        hDB = SQL_DefConnect(sError, sizeof(sError));
    }
    else
    {
        hDB = SQL_Connect(sDBConnect, true, sError, sizeof(sError));
    }
    if(!hDB && (StrEqual(sDBConnect, "", false) || StrEqual(sDBConnect, "default", false)))
    {
        // Out of the box, SourceMod's "default" database is MySQL on localhost, which most servers don't have:
        // fall back to SourceMod's local SQLite database so that XP is saved anyway.
        // Only for "default": a database named in war3source.ini never falls back (no silent switch when a
        // real MySQL server is briefly down). Expected on a fresh install: a normal log message, not an error
        LogMessage("Could not connect to database \"%s\" (%s), using SourceMod's local SQLite database (\"storage-local\") instead. Set \"database\" in configs/war3source.ini to choose another one.", sDBConnect, sError);
        PrintToServer("[War3Source] Database \"%s\" unavailable, using SourceMod's local SQLite database (\"storage-local\")", sDBConnect);
        strcopy(sDBConnect, sizeof(sDBConnect), "storage-local");
        hDB = SQL_Connect(sDBConnect, true, sError, sizeof(sError));
    }
    if(!hDB)
    {
        War3_LogCritical("[War3Source] ERROR: hDB invalid handle, Check SourceMod database config, could not connect.");
        Format(dbErrorMsg, sizeof(dbErrorMsg), "ERR: Could not connect to DB. \n%s", sError);
        
        War3_LogCritical("ERRMSG: (%s)", sError);
        CreateWar3GlobalError("ERR: Could not connect to Database");
    }
    else
    {
        new String:sDBMS[64];
        SQL_ReadDriver(hDB, sDBMS, sizeof(sDBMS));
        if (StrEqual(sDBMS, "mysql", false))
        {
            g_SQLType = SQLType_MySQL;
        }
        else if (StrEqual(sDBMS, "sqlite", false))
        {
            g_SQLType = SQLType_SQLite;
        }
        else
        {
            g_SQLType = SQLType_Unknown;
        }
        PrintToServer("[War3Source] SQL connection successful (%s), driver %s", sDBConnect, sDBMS);

        if(g_SQLType == SQLType_MySQL)
        {
            // utf8mb4: player names may contain any character (tables are created in utf8mb4 too)
            if(!SQL_SetCharset(hDB, "utf8mb4"))
            {
                War3_LogError("Could not set the MySQL connection character set to utf8mb4");
            }
        }
        
        W3SetVar(hDatabase, hDB);
        W3SetVar(hDatabaseType, g_SQLType);
        
        W3CreateEvent(DatabaseConnected, 0);
    }
    
    return true;
}
