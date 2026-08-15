-- Narakim Roblox bridge v1.0.0
-- Place this Script in ServerScriptService. Enable HttpService (Game Settings → Security).
-- Create an experience secret named NARAKIM_BRIDGE_TOKEN matching ROBLOX_BRIDGE_SECRET in Narakim.
-- Set Config.BridgeUrl to https://engine.narakim.cloud/api/webhooks/roblox/bridge/<botId>
--   (local: your public tunnel + /api/webhooks/roblox/bridge/<botId> — Roblox cannot call localhost).

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Config = {
	BridgeUrl = "https://engine.narakim.cloud/api/webhooks/roblox/bridge/YOUR_BOT_ID",
	TokenSecretName = "NARAKIM_BRIDGE_TOKEN",
	CommandsTopic = "narakim.commands",
	EmitJoin = true,
	EmitLeave = true,
	EmitChat = false,
}

local function getToken()
	local ok, secret = pcall(function()
		return HttpService:GetSecret(Config.TokenSecretName)
	end)
	if ok then
		return secret
	end
	warn("[Narakim] Missing experience secret " .. Config.TokenSecretName)
	return nil
end

local function emit(event, extra)
	local token = getToken()
	if not token then
		return
	end
	local body = {
		event = event,
		placeId = game.PlaceId,
		jobId = game.JobId,
		at = DateTime.now():ToIsoDate(),
	}
	if extra then
		for k, v in pairs(extra) do
			body[k] = v
		end
	end
	task.spawn(function()
		local ok, err = pcall(function()
			HttpService:RequestAsync({
				Url = Config.BridgeUrl,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["X-Narakim-Webhook-Token"] = token,
				},
				Body = HttpService:JSONEncode(body),
			})
		end)
		if not ok then
			warn("[Narakim] emit failed: " .. tostring(err))
		end
	end)
end

local function announce(text)
	text = tostring(text or "")
	local channels = TextChatService:FindFirstChild("TextChannels")
	local sys = channels
		and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral"))
	if sys and sys.DisplaySystemMessage then
		sys:DisplaySystemMessage("[Narakim] " .. text)
		return
	end
	warn("[Narakim announce] " .. text)
end

local function handleCommand(raw)
	local data = raw
	if type(raw) == "string" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok then
			data = decoded
		else
			announce(raw)
			return
		end
	end
	if type(data) ~= "table" then
		return
	end
	local op = data.op or data.Op
	if op == "announce" then
		announce(data.text or data.Text or "")
	elseif op == "kick" then
		local userId = tonumber(data.userId or data.UserId)
		if not userId then
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:Kick(tostring(data.reason or data.Reason or "Kicked"))
		end
	end
end

local subOk, subErr = pcall(function()
	MessagingService:SubscribeAsync(Config.CommandsTopic, function(message)
		handleCommand(message.Data)
	end)
end)
if not subOk then
	warn("[Narakim] SubscribeAsync failed: " .. tostring(subErr))
end

if Config.EmitJoin then
	Players.PlayerAdded:Connect(function(player)
		emit("player_joined", {
			userId = player.UserId,
			username = player.Name,
		})
	end)
end

if Config.EmitLeave then
	Players.PlayerRemoving:Connect(function(player)
		emit("player_left", {
			userId = player.UserId,
			username = player.Name,
		})
	end)
end

if Config.EmitChat then
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(msg)
			emit("player_chat", {
				userId = player.UserId,
				username = player.Name,
				payload = { text = msg },
			})
		end)
	end)
end
