local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local SessionManager = {}
SessionManager.Folder = "CDID"
SessionManager.FilePath = "CDID/player.json"
SessionManager.Data = {players = {}}
SessionManager.Library = nil

function SessionManager:BuildFolder()
    if not isfolder(self.Folder) then makefolder(self.Folder) end
end

function SessionManager:Load()
    self:BuildFolder()

    if isfile(self.FilePath) then
        local success, data = pcall(function()
            return HttpService:JSONDecode(readfile(self.FilePath))
        end)

        if success and data and data.players then
            self.Data = data
            return true
        end
    end

    self.Data = {players = {}}
    return false
end

function SessionManager:Save()
    self:BuildFolder()

    local success = pcall(function()
        writefile(self.FilePath, HttpService:JSONEncode(self.Data))
    end)

    return success
end

function SessionManager:GetPlayer(username) return self.Data.players[username] end

function SessionManager:SetPlayer(username, data)
    self.Data.players[username] = data
    self:Save()
end

function SessionManager:GetPlayerList()
    local list = {}
    for username, _ in pairs(self.Data.players) do
        table.insert(list, username)
    end

    table.sort(list)
    return list
end

function SessionManager:PlayerExists(username)
    return self.Data.players[username] ~= nil
end

function SessionManager:SaveSession(username, targetEarning, totalEarned,
                                    cycleCount)
    local sessionData = {
        targetEarning = targetEarning or 0,
        totalEarned = totalEarned or 0,
        cycleCount = cycleCount or 0,
        lastSession = os.date("%Y-%m-%dT%H:%M:%S")
    }

    self:SetPlayer(username, sessionData)
    return true
end

function SessionManager:LoadSession(username)
    local data = self:GetPlayer(username)
    if data then
        return {
            targetEarning = data.targetEarning or 0,
            totalEarned = data.totalEarned or 0,
            cycleCount = data.cycleCount or 0,
            lastSession = data.lastSession or "Unknown"
        }
    end
    return nil
end

function SessionManager:DeleteSession(username)
    if self.Data.players[username] then
        self.Data.players[username] = nil
        self:Save()
        return true
    end
    return false
end

function SessionManager:AutoLoadCurrentPlayer()
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return nil end

    local username = localPlayer.Name
    local session = self:LoadSession(username)

    if session then return session, username end
    return nil, username
end

function SessionManager:SetLibrary(library) self.Library = library end

function SessionManager:BuildConfigSection(tab, onSessionLoad)
    assert(self.Library, "Must set SessionManager.Library first")

    self:Load()

    local localPlayerName = Players.LocalPlayer and Players.LocalPlayer.Name or
                                "Unknown"
    local playerList = self:GetPlayerList()

    if not table.find(playerList, localPlayerName) then
        table.insert(playerList, 1, localPlayerName)
    end

    local section = tab:AddLeftGroupbox("Session Manager", "save")

    section:AddDropdown("SessionManager_PlayerList", {
        Text = "Select Player",
        Values = playerList,
        Default = localPlayerName,
        Searchable = true
    })

    section:AddButton({
        Text = "Load Session",
        Func = function()
            local selected = self.Library.Options.SessionManager_PlayerList
                                 .Value
            if not selected then
                self.Library:Notify("No player selected", 2)
                return
            end

            local session = self:LoadSession(selected)
            if session then
                if onSessionLoad then
                    onSessionLoad(session, selected)
                end
                self.Library:Notify(string.format(
                                        "Loaded session: %s\nTarget: %s | Earned: %s | Cycles: %d",
                                        selected,
                                        tostring(session.targetEarning),
                                        tostring(session.totalEarned),
                                        session.cycleCount), 4)
            else
                self.Library:Notify("No session found for: " .. selected, 2)
            end
        end
    })

    section:AddButton({
        Text = "Save Current Session",
        Func = function()
            if onSessionLoad and onSessionLoad("GET_CURRENT") then
                local current = onSessionLoad("GET_CURRENT")
                self:SaveSession(localPlayerName, current.targetEarning,
                                 current.totalEarned, current.cycleCount)
                self.Library:Notify("Session saved for: " .. localPlayerName, 2)

                -- Refresh dropdown
                self.Library.Options.SessionManager_PlayerList:SetValues(
                    self:GetPlayerList())
            end
        end
    })

    section:AddButton({
        Text = "Delete Session",
        Func = function()
            local selected = self.Library.Options.SessionManager_PlayerList
                                 .Value
            if selected and self:DeleteSession(selected) then
                self.Library:Notify("Deleted session: " .. selected, 2)
                self.Library.Options.SessionManager_PlayerList:SetValues(
                    self:GetPlayerList())
            else
                self.Library:Notify("Failed to delete session", 2)
            end
        end
    })

    section:AddButton({
        Text = "Refresh List",
        Func = function()
            self:Load()
            self.Library.Options.SessionManager_PlayerList:SetValues(
                self:GetPlayerList())
            self.Library:Notify("Player list refreshed", 2)
        end
    })

    local session, username = self:AutoLoadCurrentPlayer()
    if session then
        section:AddLabel("Last session: " .. (session.lastSession or "Unknown"))

        if onSessionLoad then
            onSessionLoad(session, username)
            self.Library:Notify("Auto-loaded session for: " .. username, 3)
        end
    else
        section:AddLabel("No previous session found")
    end

    return section
end

SessionManager:BuildFolder()
SessionManager:Load()

return SessionManager
