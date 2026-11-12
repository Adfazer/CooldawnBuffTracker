-- Effective CDs picker: one tab per skillset, only skills with a base cooldown.
-- Checking a row creates a permanent custom entry (id/name/CD/icon/tree from
-- skillsets.tbl) and tracks it on the selected Target canvas; unchecking removes it.
local api = require("api")
local helpers = require("CooldawnBuffTracker/helpers")
local CbtWindow = require("CooldawnBuffTracker/util/cbt_window")

local M = {}

local PER_PAGE = 15
local COLORS = {
  text = { 0.87, 0.69, 0.00, 1 },
  muted = { 0.72, 0.74, 0.80, 1 },
  ok = { 0.55, 0.85, 0.55, 1 },
}

local win
local rows = {}
local treeButtons = {}
local countLabel
local statusLabel
local pageLabel
local page = 1
local tree = nil
local updating = false
local items = {}

local hooks = {}

local function setColor(widget, c)
  if widget and widget.style then
    widget.style:SetColor(c[1], c[2], c[3], c[4] or 1)
  end
end

local function trees()
  if hooks.trees then
    local ok, list = pcall(hooks.trees)
    if ok and type(list) == "table" and #list > 0 then return list end
  end
  return {}
end

local function refreshTreeButtons()
  for name, btn in pairs(treeButtons) do
    setColor(btn.textLabel, (name == tree) and COLORS.text or COLORS.muted)
  end
end

local function refresh()
  if not win or not win:IsVisible() then return end
  items = {}
  if hooks.skillsForTree and tree then
    local ok, list = pcall(hooks.skillsForTree, tree)
    if ok and type(list) == "table" then items = list end
  end
  local total = #items
  local pages = math.max(1, math.ceil(total / PER_PAGE))
  if page > pages then page = pages end
  if page < 1 then page = 1 end
  if countLabel then
    countLabel:SetText(tostring(tree or "") .. ": " .. tostring(total)
      .. " skills with a cooldown")
  end
  if pageLabel then pageLabel:SetText(page .. "/" .. pages) end

  updating = true
  for i = 1, PER_PAGE do
    local row = rows[i]
    local item = items[(page - 1) * PER_PAGE + i]
    if row then
      if item then
        row.skill = item
        if row.nameLabel then row.nameLabel:SetText(tostring(item.name or "")) end
        if row.cdLabel then
          row.cdLabel:SetText("CD " .. tostring(item.cd) .. "s")
        end
        if row.icon then
          F_SLOT.SetIconBackGround(row.icon, item.icon or "game/ui/icon/icon_buff_debuff.dds")
        end
        local picked = false
        if hooks.isPicked then
          local ok, v = pcall(hooks.isPicked, item.name)
          picked = (ok and v) and true or false
        end
        if row.checkbox then
          row.checkbox.skill = item
          row.checkbox:SetChecked(picked)
        end
        row:Show(true)
      else
        row.skill = nil
        if row.checkbox then row.checkbox.skill = nil end
        row:Show(false)
      end
    end
  end
  updating = false
end

local function setTree(name)
  tree = name
  page = 1
  refreshTreeButtons()
  refresh()
end

local function makeRow(index)
  -- emptywidget: кнопка-родитель перехватывает клики дочерних элементов
  local row = win:CreateChildWidget("emptywidget", "cbtEffRow" .. index, 0, true)
  row:SetExtent(604, 28)
  row:AddAnchor("TOPLEFT", win, 18, 142 + (index - 1) * 32)

  local bg = row:CreateColorDrawable(0.10, 0.11, 0.13, 0.92, "background")
  bg:AddAnchor("TOPLEFT", row, 0, 0)
  bg:AddAnchor("BOTTOMRIGHT", row, 0, 0)
  row.bg = bg

  local icon = CreateItemIconButton("cbtEffIcon" .. index, row)
  if icon then
    icon:SetExtent(24, 24)
    icon:AddAnchor("LEFT", row, 4, 0)
    icon:Show(true)
    row.icon = icon
  end

  local nameLabel = row:CreateChildWidget("label", "cbtEffName" .. index, 0, true)
  nameLabel:SetExtent(280, 18)
  nameLabel:AddAnchor("LEFT", row, 34, 0)
  nameLabel.style:SetAlign(ALIGN.LEFT)
  nameLabel.style:SetFontSize(13)
  setColor(nameLabel, COLORS.text)
  if nameLabel.Clickable then nameLabel:Clickable(false) end
  row.nameLabel = nameLabel

  local cdLabel = row:CreateChildWidget("label", "cbtEffCd" .. index, 0, true)
  cdLabel:SetExtent(70, 18)
  cdLabel:AddAnchor("LEFT", row, 322, 0)
  cdLabel.style:SetAlign(ALIGN.LEFT)
  cdLabel.style:SetFontSize(13)
  setColor(cdLabel, COLORS.muted)
  if cdLabel.Clickable then cdLabel:Clickable(false) end
  row.cdLabel = cdLabel

  local trackLabel = row:CreateChildWidget("label", "cbtEffTrack" .. index, 0, true)
  trackLabel:SetExtent(40, 18)
  trackLabel:AddAnchor("LEFT", row, 430, 0)
  trackLabel.style:SetAlign(ALIGN.LEFT)
  trackLabel.style:SetFontSize(12)
  setColor(trackLabel, COLORS.muted)
  trackLabel:SetText("Track")
  if trackLabel.Clickable then trackLabel:Clickable(false) end

  local box = CbtWindow.CheckButton("cbtEffCheck" .. index, row, function(checked, self)
    if updating then return end
    local skill = self.skill
    if not skill or not hooks.onToggle then return end
    local ok, msg = hooks.onToggle(skill, checked)
    if statusLabel then
      statusLabel:SetText(tostring(msg or ((ok and "Updated: ") or "Failed: ") .. tostring(skill.name)))
      setColor(statusLabel, ok and COLORS.ok or COLORS.muted)
    end
    refresh()
  end)
  if box then
    box:AddAnchor("LEFT", row, 474, 0)
    box:Show(true)
    row.checkbox = box
  end

  row:SetHandler("OnEnter", function(self)
    if self.bg then self.bg:SetColor(0.16, 0.18, 0.22, 0.95) end
  end)
  row:SetHandler("OnLeave", function(self)
    if self.bg then self.bg:SetColor(0.10, 0.11, 0.13, 0.92) end
  end)

  row:Show(false)
  return row
end

local function build()
  win = CbtWindow.Create("cbtEffPicker", "Effective CDs", 640, 660, function()
    if win then win:Show(false) end
  end)
  if not win then return end

  local list = trees()
  for i, name in ipairs(list) do
    local col = (i - 1) % 5
    local rowIdx = math.floor((i - 1) / 5)
    local btn = helpers.createButton("cbtEffTree" .. i, win, name, 18 + col * 122, 44 + rowIdx * 30)
    btn:SetExtent(112, 24)
    btn:Show(true)
    btn:SetHandler("OnClick", function() setTree(name) end)
    treeButtons[name] = btn
  end

  countLabel = helpers.createLabel("cbtEffCount", win, "", 18, 104, 13)
  countLabel:SetExtent(600, 16)
  setColor(countLabel, COLORS.text)
  countLabel:Show(true)

  statusLabel = helpers.createLabel("cbtEffStatus", win,
    "Pick skills to track with effective cooldowns (Target only)", 18, 122, 12)
  statusLabel:SetExtent(600, 16)
  setColor(statusLabel, COLORS.muted)
  statusLabel:Show(true)

  for i = 1, PER_PAGE do
    rows[i] = makeRow(i)
  end

  local prev = helpers.createButton("cbtEffPrev", win, "<", 18, 626)
  prev:SetExtent(56, 24)
  prev:Show(true)
  prev:SetHandler("OnClick", function()
    if page > 1 then page = page - 1; refresh() end
  end)

  pageLabel = helpers.createLabel("cbtEffPage", win, "1/1", 82, 630, 13)
  pageLabel:SetExtent(60, 18)
  setColor(pageLabel, COLORS.text)
  pageLabel:Show(true)

  local nxt = helpers.createButton("cbtEffNext", win, ">", 146, 626)
  nxt:SetExtent(56, 24)
  nxt:Show(true)
  nxt:SetHandler("OnClick", function() page = page + 1; refresh() end)

  local reload = helpers.createButton("cbtEffReload", win, "Reload tables", 300, 626)
  reload:SetExtent(120, 24)
  reload:Show(true)
  reload:SetHandler("OnClick", function()
    if hooks.onReload then
      local ok, msg = hooks.onReload()
      if statusLabel then statusLabel:SetText(tostring(msg or "Tables reloaded")) end
    end
    refresh()
  end)

  local close = helpers.createButton("cbtEffClose", win, "Close", 502, 626)
  close:SetExtent(120, 24)
  close:Show(true)
  close:SetHandler("OnClick", function() win:Show(false) end)
end

function M.setHooks(h)
  hooks = h or {}
end

function M.open()
  if not win then build() end
  if not win then return end
  local list = trees()
  if not tree or tree == "" then tree = list[1] end
  win:Show(true)
  if win.Raise then pcall(function() win:Raise() end) end
  setTree(tree)
end

function M.refresh()
  refresh()
end

function M.close()
  if win then win:Show(false) end
end

function M.Unload()
  if win then
    pcall(function() CbtWindow.Destroy(win) end)
    win = nil
  end
  rows = {}
  treeButtons = {}
  items = {}
end

return M
