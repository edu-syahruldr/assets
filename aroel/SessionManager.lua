print("a")
local SessionManager = {}
SessionManager.__index = SessionManager

SessionManager.CURRENT_VERSION = 1
SessionManager.BASE_FOLDER = "AroelHub/sessions"
SessionManager.AUTO_SAVE_INTERVAL = 300

local HttpService = game:GetService("HttpService")

SessionManager.AutoSaveThread = nil
SessionManager.CurrentUserId = nil
SessionManager.GetDataCallback = nil

function SessionManager:Init()
    pcall(function()
        if not isfolder(self.BASE_FOLDER) then
            makefolder(self.BASE_FOLDER)
        end
    end)
    return true
end

function SessionManager:ValidateUserId(userId)
    local numericId = tonumber(userId)
    if not numericId then return nil, "userId must be numeric" end
    if numericId <= 0 then return nil, "userId must be positive" end
    if numericId % 1 ~= 0 then return nil, "userId must be integer" end
    return numericId, nil
end

function SessionManager:ValidateData(data)
    if type(data) ~= "table" then return false, "Data must be a table" end

    local required = {
        "originalTarget", "remainingTarget", "cycleCount", "sessionStartTime",
        "totalRunningTime"
    }

    for _, field in ipairs(required) do
        if data[field] == nil then
            return false, "Missing required field: " .. field
        end
        if type(data[field]) ~= "number" then
            return false, "Field must be number: " .. field
        end
    end

    if data.originalTarget < 0 then
        return false, "originalTarget cannot be negative"
    end

    if data.remainingTarget < 0 then
        return false, "remainingTarget cannot be negative"
    end

    if data.cycleCount < 0 or data.cycleCount % 1 ~= 0 then
        return false, "cycleCount must be non-negative integer"
    end

    if data.webhookData then
        if type(data.webhookData) ~= "table" then
            return false, "webhookData must be a table"
        end

        if data.webhookData.lastWebhookTime and
            type(data.webhookData.lastWebhookTime) ~= "number" then
            return false, "lastWebhookTime must be number"
        end

        if data.webhookData.totalWebhooksSent and
            type(data.webhookData.totalWebhooksSent) ~= "number" then
            return false, "totalWebhooksSent must be number"
        end
    end

    return true, nil
end

function SessionManager:GetFilePath(userId)
    return string.format("%s/player_%d.json", self.BASE_FOLDER, userId)
end

function SessionManager:Save(userId, data)

    if not writefile or not isfile then
        return false, "File system not supported"
    end

    local safeUserId, validationError = self:ValidateUserId(userId)
    if not safeUserId then
        warn("[SessionManager] Invalid userId:", validationError)
        return false, "Invalid user ID: " .. validationError
    end

    local isValid, schemaError = self:ValidateData(data)
    if not isValid then
        warn("[SessionManager] Invalid data schema:", schemaError)
        return false, "Data validation failed: " .. schemaError
    end

    local sessionData = {
        version = self.CURRENT_VERSION,
        userId = safeUserId,
        timestamp = tick(),
        data = data
    }

    local encodeSuccess, encoded = pcall(function()
        return HttpService:JSONEncode(sessionData)
    end)

    if not encodeSuccess then
        warn("[SessionManager] JSON encode failed:", encoded)
        return false, "Failed to encode data"
    end

    local filePath = self:GetFilePath(safeUserId)

    local writeSuccess, writeError = pcall(function()
        writefile(filePath, encoded)
    end)

    if not writeSuccess then
        warn("[SessionManager] Write failed:", writeError)
        return false, "Failed to write file"
    end

    return true, nil
end

function SessionManager:Load(userId)

    if not readfile or not isfile then
        return nil, "File system not supported"
    end

    local safeUserId, err = self:ValidateUserId(userId)
    if not safeUserId then return nil, "Invalid user ID: " .. err end

    local filePath = self:GetFilePath(safeUserId)

    if not isfile(filePath) then return nil, "No session file" end

    local readSuccess, fileContent = pcall(function()
        return readfile(filePath)
    end)

    if not readSuccess then
        warn("[SessionManager] Failed to read file:", fileContent)
        return nil, "Failed to read file"
    end

    local decodeSuccess, sessionData = pcall(function()
        return HttpService:JSONDecode(fileContent)
    end)

    if not decodeSuccess then
        warn("[SessionManager] Failed to decode JSON:", sessionData)
        return nil, "File corrupted"
    end

    if not sessionData or not sessionData.data then
        return nil, "Invalid session structure"
    end

    local isValid, validationError = self:ValidateData(sessionData.data)
    if not isValid then
        warn("[SessionManager] Loaded data failed validation:", validationError)
        return nil, "Data validation failed: " .. validationError
    end

    return sessionData.data, nil
end

function SessionManager:Delete(userId)
    if not delfile or not isfile then
        return false, "File system not supported"
    end

    local safeUserId, err = self:ValidateUserId(userId)
    if not safeUserId then return false, "Invalid user ID: " .. err end

    local filePath = self:GetFilePath(safeUserId)

    if not isfile(filePath) then return false, "No session file found" end

    local success = pcall(function() delfile(filePath) end)

    if success then
        return true, nil
    else
        warn("[SessionManager] Failed to delete session")
        return false, "Delete operation failed"
    end
end

function SessionManager:StartAutoSave(userId, getDataCallback)

    self:StopAutoSave()

    local safeUserId, err = self:ValidateUserId(userId)
    if not safeUserId then
        warn("[SessionManager] Cannot start auto-save: Invalid userId")
        return
    end

    self.CurrentUserId = safeUserId
    self.GetDataCallback = getDataCallback

    self.AutoSaveThread = task.spawn(function()
        while true do
            task.wait(self.AUTO_SAVE_INTERVAL)

            if self.GetDataCallback then
                local success, data = pcall(self.GetDataCallback)

                if success and data then
                    pcall(function()
                        self:Save(self.CurrentUserId, data)
                    end)
                else
                    warn("[SessionManager] Auto-save: Failed to get data")
                end
            end
        end
    end)
end

function SessionManager:StopAutoSave()
    if self.AutoSaveThread then
        pcall(task.cancel, self.AutoSaveThread)
        self.AutoSaveThread = nil
        self.CurrentUserId = nil
        self.GetDataCallback = nil
        task.wait(0.1)
    end
end

SessionManager:Init()

return SessionManager
