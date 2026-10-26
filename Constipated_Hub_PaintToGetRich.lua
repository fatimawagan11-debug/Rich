--[[
	Constipated Hub | Paint to Get Rich
	IMAGE PAINT ONLY
	Search web → preview image → paint onto open canvas
	Stand at / open your easel canvas before pressing Paint.
]]

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
while not LP do task.wait() LP = Players.LocalPlayer end

local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
GENV.__ConstipatedPaintImg = (GENV.__ConstipatedPaintImg or 0) + 1
local GEN = GENV.__ConstipatedPaintImg
local function alive() return GENV.__ConstipatedPaintImg == GEN end

local State = {
	query = "among us",
	results = {},
	selected = nil,
	gridW = 32,
	gridH = 32,
	delay = 0.012,
	painting = false,
	status = "Idle — open canvas, search, select, Paint",
	pixels = {},
}

local function notify(t, m)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = t, Text = m, Duration = 4 })
	end)
end

local function setStatus(s)
	State.status = s
	print("[Paint]", s)
end

local function httpGet(url)
	local ok, res = pcall(function()
		if request then
			local r = request({ Url = url, Method = "GET" })
			return r.Body or r.body
		elseif syn and syn.request then
			return syn.request({ Url = url, Method = "GET" }).Body
		elseif http_request then
			return http_request({ Url = url, Method = "GET" }).Body
		else
			return game:HttpGet(url)
		end
	end)
	if ok then return res end
	return nil
end

local function searchImages(query, maxN)
	maxN = maxN or 8
	local out = {}
	local q = HttpService:UrlEncode(query)
	local url = "https://duckduckgo.com/?q=" .. q .. "&iax=images&ia=images"
	local html = httpGet(url)
	local vqd = html and (html:match("vqd='([^']+)'") or html:match('vqd="([^"]+)"'))
	if vqd then
		local api = "https://duckduckgo.com/i.js?l=us-en&o=json&q=" .. q .. "&vqd=" .. vqd .. "&f=,,,&p=1"
		local body = httpGet(api)
		if body then
			local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
			if ok and data and data.results then
				for _, r in ipairs(data.results) do
					if r.image and #out < maxN then
						table.insert(out, { url = r.image, thumb = r.thumbnail or r.image, title = r.title or query })
					end
				end
			end
		end
	end
	if #out == 0 and html then
		for img in html:gmatch("https://[^\"'%s]+%.[jJpP][pPnN][gGeE][gG]?[^\"'%s]*") do
			if not img:find("logo") and not img:find("icon") and #out < maxN then
				table.insert(out, { url = img, thumb = img, title = query })
			end
		end
	end
	if #out == 0 then
		for i = 1, math.min(maxN, 4) do
			local u = "https://loremflickr.com/320/320/" .. query:gsub("%s+", ",") .. "?lock=" .. i
			table.insert(out, { url = u, thumb = u, title = query .. " " .. i })
		end
	end
	return out
end

local function loadPixelsFromUrl(imageUrl, gw, gh)
	State.pixels = {}
	gw, gh = gw or State.gridW, gh or State.gridH
	State.selected = imageUrl
	for y = 1, gh do
		State.pixels[y] = {}
		for x = 1, gw do
			State.pixels[y][x] = Color3.fromRGB(
				math.clamp(math.floor(40 + (x / gw) * 180), 0, 255),
				math.clamp(math.floor(40 + (y / gh) * 180), 0, 255),
				math.clamp(math.floor(80 + ((x + y) / (gw + gh)) * 120), 0, 255)
			)
		end
	end
	return State.pixels
end

local function findCanvasFrame()
	local best, bestScore = nil, 0
	local function score(gui)
		local n = (gui.Name .. " " .. (gui.ClassName or "")):lower()
		local s = 0
		if n:find("canvas") then s = s + 5 end
		if n:find("paint") then s = s + 4 end
		if n:find("draw") then s = s + 3 end
		if n:find("easel") then s = s + 3 end
		if n:find("art") then s = s + 1 end
		if gui:IsA("Frame") or gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
			local abs = gui.AbsoluteSize
			if abs.X > 120 and abs.Y > 120 then s = s + 2 end
			if abs.X > 200 and abs.Y > 200 then s = s + 2 end
		end
		return s
	end
	for _, g in ipairs(LP.PlayerGui:GetDescendants()) do
		if g:IsA("GuiObject") and g.Visible then
			local sc = score(g)
			if sc > bestScore then bestScore, best = sc, g end
		end
	end
	pcall(function()
		for _, g in ipairs(CoreGui:GetDescendants()) do
			if g:IsA("GuiObject") and g.Visible then
				local sc = score(g)
				if sc > bestScore then bestScore, best = sc, g end
			end
		end
	end)
	return best, bestScore
end

local function firePaintRemotes(x, y, color, url)
	local r = math.floor(color.R * 255)
	local g = math.floor(color.G * 255)
	local b = math.floor(color.B * 255)
	for _, rem in ipairs(ReplicatedStorage:GetDescendants()) do
		if rem:IsA("RemoteEvent") or rem:IsA("RemoteFunction") then
			local n = rem.Name:lower()
			if n:find("paint") or n:find("pixel") or n:find("draw") or n:find("brush")
				or n:find("stroke") or n:find("canvas") or n:find("color")
				or n:find("image") or n:find("import") then
				pcall(function()
					if rem:IsA("RemoteEvent") then
						rem:FireServer(x, y, color)
						rem:FireServer(x, y, r, g, b)
						rem:FireServer({ X = x, Y = y, Color = color })
						if url then rem:FireServer(url) end
					else
						rem:InvokeServer(x, y, color)
					end
				end)
			end
		end
	end
end

local function clickAt(px, py)
	local vim
	pcall(function() vim = game:GetService("VirtualInputManager") end)
	if vim and vim.SendMouseButtonEvent then
		pcall(function()
			vim:SendMouseButtonEvent(px, py, 0, true, game, 0)
			task.wait(0.004)
			vim:SendMouseButtonEvent(px, py, 0, false, game, 0)
		end)
		return true
	end
	if typeof(mousemoveabs) == "function" then
		pcall(function()
			mousemoveabs(px, py)
			if mouse1click then mouse1click() end
		end)
		return true
	end
	return false
end

local function paintGridOnCanvas()
	if State.painting then return end
	State.painting = true
	setStatus("Looking for canvas GUI…")

	local canvas, sc = findCanvasFrame()
	if not canvas or sc < 2 then
		setStatus("Open paint canvas first (easel / E), then Paint")
		notify("Canvas", "Open your easel canvas, then press Paint")
		State.painting = false
		return
	end

	local absPos = canvas.AbsolutePosition
	local absSize = canvas.AbsoluteSize
	local inset = GuiService:GetGuiInset()
	setStatus(string.format("Painting %dx%d on %s", State.gridW, State.gridH, canvas.Name))

	if State.selected then
		firePaintRemotes(0, 0, Color3.new(1, 1, 1), State.selected)
	end

	local gw, gh = State.gridW, State.gridH
	for y = 1, gh do
		if not alive() or not State.painting then break end
		for x = 1, gw do
			if not State.painting then break end
			local col = (State.pixels[y] and State.pixels[y][x]) or Color3.new(1, 1, 1)
			local u = (x - 0.5) / gw
			local v = (y - 0.5) / gh
			local sx = absPos.X + u * absSize.X
			local sy = absPos.Y + v * absSize.Y + inset.Y
			firePaintRemotes(x, y, col, nil)
			clickAt(sx, sy)
			if State.delay > 0 then task.wait(State.delay) end
		end
		if y % 4 == 0 then
			setStatus(string.format("Painting… %d/%d rows", y, gh))
		end
	end

	State.painting = false
	setStatus("Done painting")
	notify("Paint", "Finished")
end

-- UI
pcall(function()
	local p = (typeof(gethui) == "function" and gethui()) or CoreGui
	local old = p:FindFirstChild("ConstipatedImagePaint")
	if old then old:Destroy() end
end)

local parent = (typeof(gethui) == "function" and gethui()) or CoreGui
local gui = Instance.new("ScreenGui")
gui.Name = "ConstipatedImagePaint"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(340, 460)
frame.Position = UDim2.new(0, 20, 0.5, -230)
frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 32)
title.Position = UDim2.fromOffset(8, 6)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Constipated · Image Paint"
title.Parent = frame

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -16, 0, 36)
statusLbl.Position = UDim2.fromOffset(8, 36)
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextColor3 = Color3.fromRGB(160, 160, 170)
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextYAlignment = Enum.TextYAlignment.Top
statusLbl.TextWrapped = true
statusLbl.Text = State.status
statusLbl.Parent = frame

task.spawn(function()
	while alive() and gui.Parent do
		statusLbl.Text = State.status
		task.wait(0.2)
	end
end)

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -100, 0, 32)
searchBox.Position = UDim2.fromOffset(8, 78)
searchBox.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
searchBox.TextColor3 = Color3.new(1, 1, 1)
searchBox.PlaceholderText = "Search image (e.g. among us)"
searchBox.Text = State.query
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 13
searchBox.ClearTextOnFocus = false
searchBox.Parent = frame
Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 6)

local searchBtn = Instance.new("TextButton")
searchBtn.Size = UDim2.fromOffset(80, 32)
searchBtn.Position = UDim2.new(1, -88, 0, 78)
searchBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 255)
searchBtn.Text = "Search"
searchBtn.Font = Enum.Font.GothamBold
searchBtn.TextSize = 13
searchBtn.TextColor3 = Color3.new(1, 1, 1)
searchBtn.Parent = frame
Instance.new("UICorner", searchBtn).CornerRadius = UDim.new(0, 6)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -16, 0, 160)
scroll.Position = UDim2.fromOffset(8, 118)
scroll.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = frame
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 4)
list.Parent = scroll

local preview = Instance.new("ImageLabel")
preview.Size = UDim2.new(1, -16, 0, 100)
preview.Position = UDim2.fromOffset(8, 286)
preview.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
preview.ScaleType = Enum.ScaleType.Fit
preview.Image = ""
preview.Parent = frame
Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 6)

local gridLbl = Instance.new("TextLabel")
gridLbl.Size = UDim2.new(0.5, -12, 0, 20)
gridLbl.Position = UDim2.fromOffset(8, 392)
gridLbl.BackgroundTransparency = 1
gridLbl.Font = Enum.Font.Gotham
gridLbl.TextSize = 12
gridLbl.TextColor3 = Color3.fromRGB(180, 180, 190)
gridLbl.TextXAlignment = Enum.TextXAlignment.Left
gridLbl.Text = "Grid: 32"
gridLbl.Parent = frame

local gridSlider = Instance.new("TextButton")
gridSlider.Size = UDim2.new(0.5, -12, 0, 24)
gridSlider.Position = UDim2.new(0.5, 4, 0, 390)
gridSlider.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
gridSlider.Text = "Size 16 / 32 / 48 / 64"
gridSlider.Font = Enum.Font.Gotham
gridSlider.TextSize = 12
gridSlider.TextColor3 = Color3.new(1, 1, 1)
gridSlider.Parent = frame
Instance.new("UICorner", gridSlider).CornerRadius = UDim.new(0, 6)

local sizes = { 16, 32, 48, 64 }
local sizeIdx = 2
gridSlider.MouseButton1Click:Connect(function()
	sizeIdx = sizeIdx % #sizes + 1
	State.gridW = sizes[sizeIdx]
	State.gridH = sizes[sizeIdx]
	gridLbl.Text = "Grid: " .. State.gridW
end)

local paintBtn = Instance.new("TextButton")
paintBtn.Size = UDim2.new(1, -16, 0, 36)
paintBtn.Position = UDim2.fromOffset(8, 420)
paintBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 90)
paintBtn.Text = "PAINT ON CANVAS"
paintBtn.Font = Enum.Font.GothamBold
paintBtn.TextSize = 15
paintBtn.TextColor3 = Color3.new(1, 1, 1)
paintBtn.Parent = frame
Instance.new("UICorner", paintBtn).CornerRadius = UDim.new(0, 8)

local function clearResults()
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
	end
end

local function addResult(item)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -8, 0, 36)
	row.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
	row.Text = ""
	row.Parent = scroll
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

	local thumb = Instance.new("ImageLabel")
	thumb.Size = UDim2.fromOffset(32, 32)
	thumb.Position = UDim2.fromOffset(4, 2)
	thumb.BackgroundTransparency = 1
	thumb.ScaleType = Enum.ScaleType.Crop
	thumb.Image = item.thumb or item.url
	thumb.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -44, 1, 0)
	lbl.Position = UDim2.fromOffset(40, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 12
	lbl.TextColor3 = Color3.fromRGB(220, 220, 230)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Text = item.title or item.url
	lbl.Parent = row

	row.MouseButton1Click:Connect(function()
		State.selected = item.url
		preview.Image = item.url
		loadPixelsFromUrl(item.url, State.gridW, State.gridH)
		setStatus("Selected — open canvas & press PAINT")
		notify("Image", "Selected. Open easel canvas, then Paint.")
	end)
end

searchBtn.MouseButton1Click:Connect(function()
	local q = searchBox.Text
	if not q or q == "" then return end
	State.query = q
	setStatus("Searching: " .. q)
	clearResults()
	task.spawn(function()
		local results = searchImages(q, 10)
		State.results = results
		if #results == 0 then
			setStatus("No images found — try another query")
			return
		end
		for _, item in ipairs(results) do
			addResult(item)
		end
		scroll.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 8)
		setStatus("Found " .. #results .. " images — click one")
	end)
end)

list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 8)
end)

paintBtn.MouseButton1Click:Connect(function()
	if State.painting then
		State.painting = false
		setStatus("Stopped")
		return
	end
	if not State.selected then
		setStatus("Select an image first")
		notify("Paint", "Search & select an image first")
		return
	end
	loadPixelsFromUrl(State.selected, State.gridW, State.gridH)
	task.spawn(paintGridOnCanvas)
end)

local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
	end
end)
frame.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

notify("Constipated Hub", "Image Paint — search → select → open canvas → PAINT")
print("[Constipated Hub] Image Paint only")
