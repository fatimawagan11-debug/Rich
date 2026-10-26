--[[
	Constipated Hub | Paint to Get Rich
	UI: Orion
	Loop: Auto Paint → Display → Sell → Buy Upgrades → Prestige
	Prompt + remote discovery (no hard dependency on one hub)
]]

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
while not LP do task.wait() LP = Players.LocalPlayer end

local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
GENV.__ConstipatedPTGR = (GENV.__ConstipatedPTGR or 0) + 1
local GEN = GENV.__ConstipatedPTGR
local function alive() return GENV.__ConstipatedPTGR == GEN end

LP.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end)

-- ===================== CONFIG =====================
local CFG = {
	AutoPaint = false,
	AutoDisplay = false,
	StopWhenDisplaysFull = true,
	AutoSell = false,
	AutoPrestige = false,
	AutoBuy = false,
	BuyMode = "Cheapest", -- Cheapest | MostExpensive | Random
	PaintDelay = 0.45,
	SellDelay = 0.6,
	BuyDelay = 0.8,
	Humanize = true,
	TweenSpeed = 70,
	WalkSpeedOn = false,
	WalkSpeed = 24,
	InfJump = false,
	Noclip = false,
	AntiAFK = true,
	InstantPrompt = true,
}

local S = {
	conns = {},
	status = "Idle",
}

local function track(c)
	if c then table.insert(S.conns, c) end
	return c
end

local function notify(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 3 })
	end)
end

local function setStatus(t)
	S.status = t
end

local function humanWait(base)
	local j = CFG.Humanize and ((math.random() * 0.2) - 0.1) or 0
	task.wait(math.max(0.05, (base or 0.3) + j))
end

local function root()
	local c = LP.Character
	return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function hum()
	local c = LP.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

-- ===================== MOVEMENT =====================
local function tweenTo(cf, speed)
	local r = root()
	if not r then return end
	speed = speed or CFG.TweenSpeed
	local dist = (r.Position - cf.Position).Magnitude
	local t = math.clamp(dist / math.max(speed, 10), 0.05, 4)
	local tw = TweenService:Create(r, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = cf })
	tw:Play()
	tw.Completed:Wait()
end

local function firePrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then return false end
	pcall(function()
		if CFG.InstantPrompt then
			prompt.HoldDuration = 0
		end
		if typeof(fireproximityprompt) == "function" then
			fireproximityprompt(prompt)
		else
			prompt:InputHoldBegin()
			task.wait(prompt.HoldDuration or 0.05)
			prompt:InputHoldEnd()
		end
	end)
	return true
end

-- ===================== REMOTE HELPERS =====================
local function fireRemoteByName(names, ...)
	local args = { ... }
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			local n = d.Name:lower()
			for _, want in ipairs(names) do
				if n:find(want:lower()) then
					pcall(function()
						if d:IsA("RemoteEvent") then
							d:FireServer(table.unpack(args))
						else
							d:InvokeServer(table.unpack(args))
						end
					end)
					return true
				end
			end
		end
	end
	return false
end

-- ===================== SCAN =====================
local function isOwnPath(obj)
	local path = obj:GetFullName()
	if path:find(LP.Name) then return true end
	local p = obj
	for _ = 1, 8 do
		if not p then break end
		if p:GetAttribute("Owner") == LP.Name or p:GetAttribute("OwnerId") == LP.UserId then return true end
		if tostring(p.Name):find(LP.Name) then return true end
		p = p.Parent
	end
	return false
end

local function findPrompts(keywords)
	local out = {}
	for _, pr in ipairs(Workspace:GetDescendants()) do
		if pr:IsA("ProximityPrompt") then
			local at = (pr.ActionText or ""):lower()
			local ot = (pr.ObjectText or ""):lower()
			local nm = pr.Name:lower()
			local blob = at .. " " .. ot .. " " .. nm
			for _, k in ipairs(keywords) do
				if blob:find(k:lower()) then
					local part = pr.Parent
					if part and part:IsA("BasePart") then
						table.insert(out, { Prompt = pr, Part = part, Model = part.Parent })
					end
					break
				end
			end
		end
	end
	return out
end

local function findEasel()
	-- Prefer owned studio easel
	local best, bestD
	local r = root()
	for _, obj in ipairs(Workspace:GetDescendants()) do
		local n = obj.Name:lower()
		if (n:find("easel") or n:find("canvas") or n:find("paintstation")) and (obj:IsA("Model") or obj:IsA("BasePart")) then
			if isOwnPath(obj) or true then
				local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
				if part and r then
					local d = (part.Position - r.Position).Magnitude
					if not bestD or d < bestD then
						best, bestD = part, d
					end
				end
			end
		end
	end
	return best
end

local function countEmptyDisplays()
	local empty = 0
	local total = 0
	for _, obj in ipairs(Workspace:GetDescendants()) do
		local n = obj.Name:lower()
		if n:find("display") or n:find("gallery") or n:find("wallslot") or n:find("frameslot") then
			if isOwnPath(obj) then
				total = total + 1
				local hasArt = obj:GetAttribute("HasPainting") or obj:GetAttribute("Occupied")
					or obj:FindFirstChild("Painting") or obj:FindFirstChildWhichIsA("Decal", true)
				if not hasArt then empty = empty + 1 end
			end
		end
	end
	return empty, total
end

local function parsePrice(text)
	if not text then return math.huge end
	local s = tostring(text):gsub("[,$]", ""):lower()
	local mult = 1
	if s:find("k") then mult = 1e3 end
	if s:find("m") then mult = 1e6 end
	if s:find("b") then mult = 1e9 end
	local num = tonumber(s:match("[%d%.]+"))
	return (num or math.huge) * mult
end

local function findBuyButtons()
	local list = {}
	for _, pr in ipairs(Workspace:GetDescendants()) do
		if pr:IsA("ProximityPrompt") then
			local at = (pr.ActionText or ""):lower()
			local ot = (pr.ObjectText or "")
			if at:find("buy") or at:find("purchase") or at:find("unlock") or at:find("upgrade") then
				if isOwnPath(pr) or true then
					local part = pr.Parent
					if part and part:IsA("BasePart") then
						table.insert(list, {
							Prompt = pr,
							Part = part,
							Price = parsePrice(ot .. " " .. at),
							Label = ot ~= "" and ot or pr.ActionText,
						})
					end
				end
			end
		end
	end
	-- also TouchInterest / ClickDetector pads named Buy
	for _, obj in ipairs(Workspace:GetDescendants()) do
		local n = obj.Name:lower()
		if (n:find("buy") or n:find("upgrade") or n:find("button")) and obj:IsA("BasePart") then
			if isOwnPath(obj) then
				local pr = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
				table.insert(list, {
					Prompt = pr,
					Part = obj,
					Price = parsePrice(obj:GetAttribute("Price") or obj:GetAttribute("Cost") or n),
					Label = obj.Name,
				})
			end
		end
	end
	return list
end

-- ===================== ACTIONS =====================
local function doPaint()
	setStatus("Painting")
	-- remotes first
	fireRemoteByName({ "paint", "startpaint", "finishpaint", "submitpaint", "createpainting", "draw" })
	-- easel proximity
	local easel = findEasel()
	if easel then
		tweenTo(easel.CFrame + Vector3.new(0, 2, 0), CFG.TweenSpeed)
		humanWait(0.15)
		local pr = easel:FindFirstChildWhichIsA("ProximityPrompt", true)
			or (easel.Parent and easel.Parent:FindFirstChildWhichIsA("ProximityPrompt", true))
		if pr then firePrompt(pr) end
	end
	-- any paint prompts
	for _, item in ipairs(findPrompts({ "paint", "draw", "create", "finish", "done", "submit" })) do
		if item.Part and root() and (item.Part.Position - root().Position).Magnitude < 40 then
			firePrompt(item.Prompt)
		end
	end
	humanWait(CFG.PaintDelay)
end

local function doDisplay()
	setStatus("Displaying")
	fireRemoteByName({ "display", "placepaint", "hang", "gallery", "putpainting", "placeart" })
	for _, item in ipairs(findPrompts({ "display", "place", "hang", "put", "frame", "wall" })) do
		if item.Part then
			tweenTo(item.Part.CFrame + Vector3.new(0, 2, 0), CFG.TweenSpeed)
			humanWait(0.1)
			firePrompt(item.Prompt)
			humanWait(0.25)
			break
		end
	end
end

local function doSell()
	setStatus("Selling")
	fireRemoteByName({ "sell", "sellpaint", "sellart", "acceptoffer", "negotiate", "collect" })
	for _, item in ipairs(findPrompts({ "sell", "accept", "offer", "collect", "claim", "buyer" })) do
		if item.Part then
			local r = root()
			if r and (item.Part.Position - r.Position).Magnitude < 80 then
				tweenTo(item.Part.CFrame + Vector3.new(0, 2, 0), CFG.TweenSpeed)
				humanWait(0.1)
				firePrompt(item.Prompt)
				humanWait(CFG.SellDelay)
			end
		end
	end
end

local function doBuy()
	setStatus("Buying upgrades")
	fireRemoteByName({ "buy", "purchase", "upgrade", "unlock" })
	local buttons = findBuyButtons()
	if #buttons == 0 then return end
	if CFG.BuyMode == "Cheapest" then
		table.sort(buttons, function(a, b) return a.Price < b.Price end)
	elseif CFG.BuyMode == "MostExpensive" then
		table.sort(buttons, function(a, b) return a.Price > b.Price end)
	else
		-- shuffle-ish
		for i = #buttons, 2, -1 do
			local j = math.random(1, i)
			buttons[i], buttons[j] = buttons[j], buttons[i]
		end
	end
	local target = buttons[1]
	if target and target.Part then
		tweenTo(target.Part.CFrame + Vector3.new(0, 2.5, 0), CFG.TweenSpeed)
		humanWait(0.12)
		if target.Prompt then
			firePrompt(target.Prompt)
		else
			-- touch pad
			local r = root()
			if r and firetouchinterest then
				pcall(function()
					firetouchinterest(r, target.Part, 0)
					task.wait(0.05)
					firetouchinterest(r, target.Part, 1)
				end)
			end
		end
		humanWait(CFG.BuyDelay)
	end
end

local function doPrestige()
	setStatus("Prestige")
	fireRemoteByName({ "prestige", "rebirth", "resetprestige", "doprestige" })
	for _, item in ipairs(findPrompts({ "prestige", "rebirth" })) do
		firePrompt(item.Prompt)
	end
	-- UI button fallback via remote only; physical button
	for _, gui in ipairs(LP.PlayerGui:GetDescendants()) do
		if gui:IsA("TextButton") or gui:IsA("ImageButton") then
			local t = (gui.Text or gui.Name or ""):lower()
			if t:find("prestige") or t:find("begin prestige") then
				pcall(function()
					if firesignal then
						firesignal(gui.MouseButton1Click)
					end
					gui.MouseButton1Click:Fire()
				end)
			end
		end
	end
end

-- ===================== LOOPS =====================
task.spawn(function()
	while alive() do
		if CFG.AutoPaint then
			if CFG.StopWhenDisplaysFull then
				local empty = countEmptyDisplays()
				if empty == 0 then
					-- still try paint if we never found displays
					doPaint()
				else
					doPaint()
				end
			else
				doPaint()
			end
		end
		humanWait(CFG.PaintDelay)
	end
end)

task.spawn(function()
	while alive() do
		if CFG.AutoDisplay then
			doDisplay()
		end
		humanWait(0.8)
	end
end)

task.spawn(function()
	while alive() do
		if CFG.AutoSell then
			doSell()
		end
		humanWait(CFG.SellDelay)
	end
end)

task.spawn(function()
	while alive() do
		if CFG.AutoBuy then
			doBuy()
		end
		humanWait(CFG.BuyDelay)
	end
end)

task.spawn(function()
	while alive() do
		if CFG.AutoPrestige then
			doPrestige()
		end
		task.wait(5)
	end
end)

-- Player helpers
track(RunService.Heartbeat:Connect(function()
	if not alive() then return end
	local h = hum()
	if h and CFG.WalkSpeedOn then
		h.WalkSpeed = CFG.WalkSpeed
	end
	if CFG.Noclip then
		local c = LP.Character
		if c then
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") then p.CanCollide = false end
			end
		end
	end
end))

track(UserInputService.JumpRequest:Connect(function()
	if CFG.InfJump and alive() then
		local h = hum()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end))

-- ===================== UI (Orion) =====================
local OrionLib
do
	local urls = {
		"https://raw.githubusercontent.com/shlexware/Orion/main/source",
		"https://raw.githubusercontent.com/jensonhirst/Orion/main/source",
	}
	for _, u in ipairs(urls) do
		local ok, res = pcall(function() return loadstring(game:HttpGet(u))() end)
		if ok and res then OrionLib = res break end
	end
end
if not OrionLib then
	warn("[Constipated] Orion failed — features still run via CFG defaults")
	print("[Constipated Hub] Paint to Get Rich loaded (no UI)")
	return
end

local Window = OrionLib:MakeWindow({
	Name = "Constipated Hub · Paint to Get Rich",
	HidePremium = true,
	SaveConfig = false,
	IntroEnabled = false,
})

local TabMain = Window:MakeTab({ Name = "Main", Icon = "rbxassetid://4483362458", PremiumOnly = false })
local TabBuy = Window:MakeTab({ Name = "Upgrades", Icon = "rbxassetid://4483362458", PremiumOnly = false })
local TabPlayer = Window:MakeTab({ Name = "Player", Icon = "rbxassetid://4483362458", PremiumOnly = false })
local TabMisc = Window:MakeTab({ Name = "Misc", Icon = "rbxassetid://4483362458", PremiumOnly = false })

TabMain:AddToggle({
	Name = "Auto Paint",
	Default = false,
	Callback = function(v) CFG.AutoPaint = v end,
})
TabMain:AddToggle({
	Name = "Auto Display Paint",
	Default = false,
	Callback = function(v) CFG.AutoDisplay = v end,
})
TabMain:AddToggle({
	Name = "Stop Paint When Displays Full",
	Default = true,
	Callback = function(v) CFG.StopWhenDisplaysFull = v end,
})
TabMain:AddToggle({
	Name = "Auto Sell",
	Default = false,
	Callback = function(v) CFG.AutoSell = v end,
})
TabMain:AddToggle({
	Name = "Auto Prestige",
	Default = false,
	Callback = function(v) CFG.AutoPrestige = v end,
})
TabMain:AddSlider({
	Name = "Paint Delay",
	Min = 0.15, Max = 2, Default = 0.45, Increment = 0.05,
	Callback = function(v) CFG.PaintDelay = v end,
})
TabMain:AddSlider({
	Name = "Sell Delay",
	Min = 0.2, Max = 3, Default = 0.6, Increment = 0.05,
	Callback = function(v) CFG.SellDelay = v end,
})
TabMain:AddButton({
	Name = "Paint Once",
	Callback = function() doPaint() end,
})
TabMain:AddButton({
	Name = "Sell Once",
	Callback = function() doSell() end,
})
TabMain:AddParagraph("Status", "Enable Auto Paint + Auto Sell for AFK. Display helps fill gallery for buyers.")

TabBuy:AddToggle({
	Name = "Auto Buy Buttons",
	Default = false,
	Callback = function(v) CFG.AutoBuy = v end,
})
TabBuy:AddDropdown({
	Name = "Buy Mode",
	Default = "Cheapest",
	Options = { "Cheapest", "MostExpensive", "Random" },
	Callback = function(v) CFG.BuyMode = v end,
})
TabBuy:AddSlider({
	Name = "Buy Delay",
	Min = 0.3, Max = 5, Default = 0.8, Increment = 0.1,
	Callback = function(v) CFG.BuyDelay = v end,
})
TabBuy:AddButton({
	Name = "Buy Once",
	Callback = function() doBuy() end,
})
TabBuy:AddButton({
	Name = "Prestige Now",
	Callback = function() doPrestige() end,
})

TabPlayer:AddToggle({
	Name = "WalkSpeed",
	Default = false,
	Callback = function(v) CFG.WalkSpeedOn = v end,
})
TabPlayer:AddSlider({
	Name = "Speed",
	Min = 16, Max = 80, Default = 24, Increment = 1,
	Callback = function(v) CFG.WalkSpeed = v end,
})
TabPlayer:AddToggle({
	Name = "Infinite Jump",
	Default = false,
	Callback = function(v) CFG.InfJump = v end,
})
TabPlayer:AddToggle({
	Name = "Noclip",
	Default = false,
	Callback = function(v) CFG.Noclip = v end,
})
TabPlayer:AddToggle({
	Name = "Humanized Delays",
	Default = true,
	Callback = function(v) CFG.Humanize = v end,
})
TabPlayer:AddToggle({
	Name = "Instant ProximityPrompt",
	Default = true,
	Callback = function(v) CFG.InstantPrompt = v end,
})
TabPlayer:AddSlider({
	Name = "Tween Speed",
	Min = 20, Max = 200, Default = 70, Increment = 5,
	Callback = function(v) CFG.TweenSpeed = v end,
})

TabMisc:AddButton({
	Name = "Server Hop",
	Callback = function()
		pcall(function()
			local placeId = game.PlaceId
			local servers = HttpService:JSONDecode(game:HttpGet(
				"https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=50"
			))
			for _, s in ipairs(servers.data or {}) do
				if s.playing < s.maxPlayers and s.id ~= game.JobId then
					TeleportService:TeleportToPlaceInstance(placeId, s.id, LP)
					return
				end
			end
		end)
	end,
})
TabMisc:AddButton({
	Name = "Rejoin",
	Callback = function()
		pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
	end,
})
TabMisc:AddButton({
	Name = "Unload",
	Callback = function()
		GENV.__ConstipatedPTGR = GEN + 1
		for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
		pcall(function() OrionLib:Destroy() end)
	end,
})
TabMisc:AddParagraph(
	"About",
	"Constipated Hub · Paint to Get Rich\nAuto paint / display / sell / buy / prestige.\nUses prompts + remote name discovery — works across minor updates."
)

OrionLib:MakeNotification({
	Name = "Constipated Hub",
	Content = "Paint to Get Rich loaded — enable Auto Paint + Auto Sell",
	Time = 4,
})

print("[Constipated Hub] Paint to Get Rich ready")
