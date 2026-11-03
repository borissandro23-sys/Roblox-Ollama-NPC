-- Roblox Ollama AI Coding Agent
-- Install as a local Studio plugin. The model only proposes source; Apply is always manual.

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local TOOLBAR = plugin:CreateToolbar("Ollama AI")
local OPEN_BUTTON = TOOLBAR:CreateButton(
    "OllamaAgent",
    "Open the Gemma coding agent",
    "rbxassetid://4458901886",
    "Ollama Agent"
)
OPEN_BUTTON.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
    Enum.InitialDockState.Right,
    false,
    false,
    520,
    680,
    380,
    420
)
local widget = plugin:CreateDockWidgetPluginGui("RobloxOllamaCodingAgent", widgetInfo)
widget.Title = "Ollama AI Coding Agent"

local function make(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local root = make("Frame", {
    Name = "Root",
    BackgroundColor3 = Color3.fromRGB(35, 37, 44),
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
}, widget)

local padding = make("UIPadding", {
    PaddingTop = UDim.new(0, 12),
    PaddingBottom = UDim.new(0, 12),
    PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 12),
}, root)

local layout = make("UIListLayout", {
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, root)

local function label(text, order, height)
    return make("TextLabel", {
        LayoutOrder = order,
        Size = UDim2.new(1, 0, 0, height or 22),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Color3.fromRGB(225, 228, 235),
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    }, root)
end

local function textBox(name, placeholder, order, height, multiLine)
    return make("TextBox", {
        Name = name,
        LayoutOrder = order,
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Color3.fromRGB(24, 26, 32),
        BorderColor3 = Color3.fromRGB(67, 73, 86),
        ClearTextOnFocus = false,
        Text = "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = Color3.fromRGB(140, 146, 158),
        TextColor3 = Color3.fromRGB(240, 242, 247),
        TextSize = 14,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = false,
        MultiLine = multiLine == true,
    }, root)
end

label("Gemma 4:12B через Ollama. Выбери Script / LocalScript / ModuleScript в Explorer.", 1, 38)

local urlBox = textBox("BridgeURL", "http://127.0.0.1:8000", 2, 30, false)
urlBox.Text = "http://127.0.0.1:8000"

local tokenBox = textBox("ApiKey", "API-ключ из OLLAMA_BRIDGE_TOKEN (не сохраняется)", 3, 30, false)
tokenBox.TextEditable = true

local selectedLabel = label("Выбранный скрипт: ничего не выбрано", 4, 26)
local promptBox = textBox("Prompt", "Например: Создай систему двойного прыжка с проверкой на сервере...", 5, 100, true)

local askButton = make("TextButton", {
    Name = "AskGemma",
    LayoutOrder = 6,
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Color3.fromRGB(54, 112, 190),
    BorderSizePixel = 0,
    Text = "Спросить Gemma",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 15,
    Font = Enum.Font.GothamBold,
}, root)

local statusLabel = label("Готов. Мост должен работать на этом ПК.", 7, 34)

local messageBox = textBox("Explanation", "Ответ агента появится здесь.", 8, 66, true)
messageBox.TextEditable = false

label("Предпросмотр Luau — проверь код перед применением:", 9, 22)
local codeBox = textBox("CodePreview", "-- Здесь появится предложенный код", 10, 260, true)
codeBox.ClearTextOnFocus = false

local applyButton = make("TextButton", {
    Name = "ApplyCode",
    LayoutOrder = 11,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = Color3.fromRGB(44, 135, 91),
    BorderSizePixel = 0,
    Text = "Применить к выбранному скрипту",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 14,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = true,
}, root)

local pendingTarget = nil
local pendingCode = nil
local busy = false

local function getSelectedScript()
    local items = Selection:Get()
    if #items ~= 1 then
        return nil, "Выбери ровно один Script, LocalScript или ModuleScript в Explorer."
    end
    local target = items[1]
    if not (target:IsA("Script") or target:IsA("LocalScript") or target:IsA("ModuleScript")) then
        return nil, "Выбранный объект не является скриптом."
    end
    return target
end

local function updateSelection()
    local target, reason = getSelectedScript()
    if target then
        selectedLabel.Text = "Выбранный скрипт: " .. target:GetFullName() .. " (" .. target.ClassName .. ")"
    else
        selectedLabel.Text = "Выбранный скрипт: " .. reason
    end
end

Selection.SelectionChanged:Connect(updateSelection)
updateSelection()

local function setBusy(value, status)
    busy = value
    askButton.Active = not value
    askButton.AutoButtonColor = not value
    askButton.Text = value and "Gemma думает..." or "Спросить Gemma"
    statusLabel.Text = status or ""
end

askButton.MouseButton1Click:Connect(function()
    if busy then return end
    local target, reason = getSelectedScript()
    if not target then
        statusLabel.Text = reason
        return
    end
    local prompt = string.sub(promptBox.Text, 1, 6000)
    if prompt:gsub("%s", "") == "" then
        statusLabel.Text = "Сначала напиши задачу для агента."
        return
    end
    local baseUrl = urlBox.Text:gsub("%s+$", ""):gsub("/+$", "")
    local token = tokenBox.Text
    if baseUrl == "" or token == "" then
        statusLabel.Text = "Укажи адрес моста и API-ключ."
        return
    end
    if not (baseUrl:match("^http://127%.0%.0%.1:%d+$") or baseUrl:match("^http://localhost:%d+$")) then
        statusLabel.Text = "Для Studio используй локальный адрес http://127.0.0.1:8000."
        return
    end

    pendingTarget = target
    pendingCode = nil
    codeBox.Text = "-- Ожидание ответа Ollama..."
    messageBox.Text = ""
    setBusy(true, "Отправляю запрос локальному мосту...")

    local payload = {
        prompt = prompt,
        script_type = target.ClassName,
        script_name = target:GetFullName(),
        source = target.Source,
    }

    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url = baseUrl .. "/agent",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["X-API-Key"] = token,
            },
            Body = HttpService:JSONEncode(payload),
        })
    end)

    if not ok then
        codeBox.Text = "-- Запрос не выполнен."
        setBusy(false, "Ошибка HTTP. Проверь, что Python-мост запущен и HTTP Requests разрешены.")
        return
    end
    if not response.Success then
        codeBox.Text = "-- Сервер вернул ошибку."
        setBusy(false, "Ошибка моста: HTTP " .. tostring(response.StatusCode) .. " — " .. string.sub(response.Body, 1, 300))
        return
    end

    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)
    if not decodeOk or type(data) ~= "table" then
        setBusy(false, "Мост вернул некорректный JSON.")
        return
    end

    messageBox.Text = tostring(data.message or "Ответ получен.")
    local generated = tostring(data.code or "")
    if generated == "" then
        pendingCode = nil
        codeBox.Text = "-- Модель не предложила код. Посмотри пояснение выше."
        setBusy(false, "Ответ готов; код не предложен.")
        return
    end
    pendingCode = generated
    codeBox.Text = generated
    setBusy(false, "Предпросмотр готов. Код ещё НЕ применён.")
end)

applyButton.MouseButton1Click:Connect(function()
    if not pendingCode or pendingCode == "" then
        statusLabel.Text = "Сначала запроси код у Gemma."
        return
    end
    local current, reason = getSelectedScript()
    if not current then
        statusLabel.Text = reason
        return
    end
    if current ~= pendingTarget or not current:IsDescendantOf(game) then
        statusLabel.Text = "Выбор изменился. Выбери исходный скрипт и запроси код заново."
        return
    end
    if #pendingCode > 24000 then
        statusLabel.Text = "Код слишком большой для применения."
        return
    end

    ChangeHistoryService:SetWaypoint("Before Ollama Agent edit")
    current.Source = pendingCode
    ChangeHistoryService:SetWaypoint("After Ollama Agent edit")
    statusLabel.Text = "Код применён к " .. current:GetFullName() .. ". Можно отменить через Ctrl+Z."
end)

OPEN_BUTTON.Click:Connect(function()
    widget.Enabled = not widget.Enabled
end)
