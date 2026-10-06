local ADDON_NAME, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local WIDTH = 250
Widgets.WIDTH = WIDTH

function Widgets.Slider(parent, o)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(WIDTH, 40)
    local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(o.label)

    local step = o.step or 1
    local refreshing = false
    local function Fmt(v)
        return o.format and o.format(v) or tostring(v)
    end
    local function Commit(v)
        if refreshing then
            return
        end
        v = math.floor(v / step + 0.5) * step
        if o.get() ~= v then
            o.set(v)
        end
    end

    if MinimalSliderWithSteppersMixin and CreateMinimalSliderFormatter then
        local s = CreateFrame("Frame", nil, c, "MinimalSliderWithSteppersTemplate")
        s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
        s:SetWidth(WIDTH - 10)
        local right = MinimalSliderWithSteppersMixin.Label.Right
        local formatters = { [right] = CreateMinimalSliderFormatter(right, Fmt) }
        s:Init(o.get(), o.min, o.max, math.floor((o.max - o.min) / step + 0.5), formatters)
        s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            Commit(v)
        end, s)
        function c:Refresh()
            refreshing = true
            local v = o.get()
            if s.SetValue then
                s:SetValue(v)
            else
                s.Slider:SetValue(v)
            end
            refreshing = false
        end
        function c:SetEnabledState(enabled)
            c:SetAlpha(enabled and 1 or 0.5)
            if s.SetEnabled then
                s:SetEnabled(enabled)
            end
        end
    else
        local slider = CreateFrame("Slider", nil, c, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -6)
        slider:SetWidth(WIDTH - 60)
        slider:SetMinMaxValues(o.min, o.max)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        if slider.Low then slider.Low:SetText("") end
        if slider.High then slider.High:SetText("") end
        if slider.Text then slider.Text:SetText("") end
        local valueText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        slider:SetScript("OnValueChanged", function(_, v)
            valueText:SetText(Fmt(math.floor(v / step + 0.5) * step))
            Commit(v)
        end)
        function c:Refresh()
            refreshing = true
            slider:SetValue(o.get())
            refreshing = false
        end
        function c:SetEnabledState(enabled)
            c:SetAlpha(enabled and 1 or 0.5)
            slider:SetEnabled(enabled)
        end
        slider:SetValue(o.get())
    end
    return c
end

function Widgets.Checkbox(parent, o)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(WIDTH, 26)
    local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", 0, 0)
    local text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(o.label)

    local refreshing = false
    cb:SetScript("OnClick", function(self)
        if not refreshing then
            o.set(self:GetChecked() and true or false)
        end
    end)
    function c:Refresh()
        refreshing = true
        cb:SetChecked(o.get() and true or false)
        refreshing = false
    end
    function c:SetEnabledState(enabled)
        cb:SetEnabled(enabled)
        text:SetAlpha(enabled and 1 or 0.5)
    end
    return c
end

function Widgets.Dropdown(parent, o)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(WIDTH, 28)
    local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(o.label)

    local function List()
        return type(o.options) == "function" and o.options() or o.options
    end
    local function TextFor(value)
        for _, opt in ipairs(List()) do
            if opt.value == value then
                return opt.text
            end
        end
        return tostring(value)
    end

    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, c, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetWidth(140)
        dd:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        dd:SetupMenu(function(_, root)
            for _, opt in ipairs(List()) do
                root:CreateRadio(opt.text, function()
                    return o.get() == opt.value
                end, function()
                    o.set(opt.value)
                end, opt.value)
            end
        end)
        function c:Refresh()
            dd:GenerateMenu()
        end
        function c:SetEnabledState(enabled)
            c:SetAlpha(enabled and 1 or 0.5)
            dd:SetEnabled(enabled)
        end
    else

        local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        btn:SetSize(140, 22)
        btn:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        btn:SetScript("OnClick", function()
            local list, current = List(), o.get()
            for i, opt in ipairs(list) do
                if opt.value == current then
                    o.set(list[i % #list + 1].value)
                    return
                end
            end
            o.set(list[1].value)
        end)
        function c:Refresh()
            btn:SetText(TextFor(o.get()))
        end
        function c:SetEnabledState(enabled)
            c:SetAlpha(enabled and 1 or 0.5)
            btn:SetEnabled(enabled)
        end
    end
    return c
end

function Widgets.Button(parent, o)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(WIDTH, 28)
    local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    btn:SetSize(WIDTH - 10, 24)
    btn:SetPoint("LEFT", 0, 0)
    btn:SetText(o.text)
    btn:SetScript("OnClick", o.onClick)
    function c:Refresh() end
    function c:SetEnabledState(enabled)
        btn:SetEnabled(enabled)
    end
    return c
end

function Widgets.Stack(content, widgets, spacing)
    spacing = spacing or 2
    local y = 0
    for _, w in ipairs(widgets) do
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + w:GetHeight() + spacing
    end
    content:SetHeight(math.max(y, 1))
    return y
end
