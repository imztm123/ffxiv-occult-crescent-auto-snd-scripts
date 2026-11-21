-- ===== 基础配置区 =====
local NORTH_HORN_MAP_ID = 1346   -- 北岛地图ID（填 0 则在岛内启动时自动记录）
local NPC_NAME = "杰弗瑞"      -- 岛外营地负责传送进新月岛的 NPC 名字
local MENU_STEPS = { 0 }      -- 第一层菜单选第1项（索引0）；第二层确认弹窗同样自动选第1项“是”
local REENTER_DELAY = 10.0    -- 被踢出岛后等待 10 秒再开始找 NPC

-- ===== 白银币定时回营地兑换配置区 =====
local ENABLE_COIN_EXCHANGE = true          -- 是否开启定时回营地找鉴定师兑换
local EXCHANGE_INTERVAL_MIN = 150.0      -- 每隔 2.5 小时（150分钟）回营地兑换一次（设为 0 可关闭）
local MAX_BUY_ATTEMPTS = 15              -- 单次兑换最多尝试购买次数（币不够会自动停止）
local APPRAISER_NAME = "调查队的古钱鉴定师" -- 营地兑换 NPC 名字
local APPRAISER_HAS_SUBMENU = true         -- 对话后先进入二级分类菜单
local APPRAISER_MENU_CHOICE = 1            -- 第2项：十二城邦白银币（其他）
local SHOP_OTHER_TAB_INDEX = 3             -- 顶部第4个标签：其他
local FIXATIVE_ROW_INDEX = 13              -- “其他”列表第14行：终极固定剂

-- ===== 防卡死与阵亡配置区 =====
local IDLE_STAGE1_TIMEOUT = 20.0  -- 第1步：发呆满 20 秒触发原地重启
local IDLE_STAGE2_TIMEOUT = 8.0   -- 第2步：原地重启后过 8 秒仍未移动，触发「返回」回营地再重开

local POST_FIGHT_RAISE_WAIT = 8.0 -- 周围战斗结束后，若有活人再多等几秒看是否有人拉复活
local EMPTY_FIELD_WAIT = 3.0      -- 周围既没战斗也没活人时，等几秒直接回出生点
local MAX_DEAD_WAIT = 240.0       -- 单次躺尸最长等待上限（4分钟）

local SHOUT_HELP_CMD = "/sh 999"   -- 阵亡且附近有活人时自动发送的求救喊话
local SHOUT_THANKS_CMD = "/sh 谢谢" -- 被其他玩家拉起复活后自动发送的感谢喊话

local BOCCHI_CMD_ON = "/bocchiillegal on"
local BOCCHI_CMD_OFF = "/bocchiillegal off"
local BMR_AI_ON = "/bmrai on"
local BMR_AI_OFF = "/bmrai off"

-- ===== 基础工具函数 =====
local function ToNum(v)
    if v == nil then return nil end
    if type(v) == "number" then return v end
    return tonumber(tostring(v))
end

local function ToBool(v)
    if v == nil then return false end
    if type(v) == "boolean" then return v end
    return tostring(v) == "true"
end

local function ExtractStr(seStr)
    if seStr == nil then return "" end
    if type(seStr) == "string" then return seStr end
    local ok1, t1 = pcall(function() return seStr:ExtractText() end)
    if ok1 and t1 ~= nil and tostring(t1) ~= "" then return tostring(t1) end
    local ok2, t2 = pcall(function() return seStr.TextValue end)
    if ok2 and t2 ~= nil and tostring(t2) ~= "" then return tostring(t2) end
    return tostring(seStr)
end

local function CleanStr(raw)
    if raw == nil then return "" end
    local s = ExtractStr(raw)
    if s == "" or s == "nil" or string.find(s, "Dalamud%.") then return "" end
    return s:gsub("[%c]", " ")
end

local function CalcDist(x1, y1, z1, x2, y2, z2)
    if x1 == nil or x2 == nil then return 9999 end
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function IsAddonReady(addonName)
    if Addons == nil or Addons.GetAddon == nil then return false end
    local okA, addon = pcall(function() return Addons.GetAddon(addonName) end)
    if okA and addon ~= nil then
        local okR, rdy = pcall(function() return addon.Ready end)
        if okR and ToBool(rdy) then return true end
    end
    return false
end

local function GetYesnoKind()
    if Addons == nil or Addons.GetAddon == nil then return "UNKNOWN" end
    local okA, addon = pcall(function() return Addons.GetAddon("SelectYesno") end)
    if not okA or addon == nil then return "UNKNOWN" end
    local okR, rdy = pcall(function() return ToBool(addon.Ready) end)
    if not okR or not rdy then return "UNKNOWN" end

    local buf = ""
    pcall(function()
        for idx = 0, 3 do
            local okV, val = pcall(function() return addon:GetAtkValue(idx) end)
            if not okV or val == nil then break end
            local okS, vs = pcall(function() return val.ValueString end)
            if okS and vs ~= nil then
                local c = CleanStr(vs)
                if c ~= "" and c ~= "nil" then buf = buf .. " " .. c end
            end
        end
    end)

    if string.find(buf, "救助") or string.find(buf, "接受") then return "RAISE" end
    if string.find(buf, "开始地点") or string.find(buf, "即将回到") or string.find(buf, "返回") or string.find(buf, "确定") or string.find(buf, "换取") then
        return "RETURN"
    end
    return "UNKNOWN"
end

-- ===== 状态采集 =====
local function GetTickState()
    local st = {
        isLoading = false,
        territoryId = 0,
        navReady = true,
        isMoving = false,
        inCombat = false,
        isCasting = false,
        isDead = false,
        waitingCE = false,
        ceReason = "",
        activeFateCount = -1,
        bossFightingNearby = false,
        alivePlayersNearby = 0,
        px = nil, py = nil, pz = nil,
        hasTarget = false,
        targetName = "",
        tx = nil, ty = nil, tz = nil,
        distToTarget = 9999,
        uiTalk = false,
        uiSelectString = false,
        uiSelectIconString = false,
        uiSelectYesno = false,
        yesnoType = "NONE",
        uiDutyConfirm = false,
        uiShopCurrency = false
    }

    if Svc ~= nil and Svc.Condition ~= nil then
        local ok45, c45 = pcall(function() return Svc.Condition[45] end)
        local ok51, c51 = pcall(function() return Svc.Condition[51] end)
        if (ok45 and ToBool(c45)) or (ok51 and ToBool(c51)) then st.isLoading = true end

        local ok26, c26 = pcall(function() return Svc.Condition[26] end)
        if ok26 and ToBool(c26) then st.inCombat = true end

        local ok27, c27 = pcall(function() return Svc.Condition[27] end)
        if ok27 and ToBool(c27) then st.isCasting = true end

        local ok2, c2 = pcall(function() return Svc.Condition[2] end)
        if ok2 and ToBool(c2) then st.isDead = true end

        local ok43, c43 = pcall(function() return Svc.Condition[43] end)
        if ok43 and ToBool(c43) then
            st.waitingCE = true
            st.ceReason = "副本排队中"
        end
    end

    if Svc ~= nil and Svc.ClientState ~= nil then
        local okT, tid = pcall(function() return ToNum(Svc.ClientState.TerritoryType) end)
        if okT and tid ~= nil then st.territoryId = math.floor(tid) end
    end

    if Svc ~= nil and Svc.Fates ~= nil then
        local okF, fCount = pcall(function() return ToNum(Svc.Fates.Count) end)
        if okF and fCount ~= nil then st.activeFateCount = math.floor(fCount) end
    end

    if IPC ~= nil and IPC.vnavmesh ~= nil then
        local okR, r = pcall(function() return IPC.vnavmesh.IsReady() end)
        if okR and r ~= nil then st.navReady = ToBool(r) end

        local okM, m = pcall(function() return IPC.vnavmesh.IsRunning() end)
        if okM and m ~= nil then st.isMoving = ToBool(m) end
    end

    local pObj = nil
    if Svc ~= nil and Svc.Objects ~= nil then
        local okP, obj = pcall(function() return Svc.Objects.LocalPlayer end)
        if okP then pObj = obj end
    end
    if pObj == nil and Svc ~= nil and Svc.ClientState ~= nil then
        local okP2, obj2 = pcall(function() return Svc.ClientState.LocalPlayer end)
        if okP2 then pObj = obj2 end
    end

    if pObj ~= nil then
        local okPos, px, py, pz = pcall(function()
            local pos = pObj.Position
            return ToNum(pos.X), ToNum(pos.Y), ToNum(pos.Z)
        end)
        if okPos and px ~= nil then st.px, st.py, st.pz = px, py, pz end

        local okDead, deadFlag = pcall(function() return pObj.IsDead end)
        if okDead and ToBool(deadFlag) then st.isDead = true end

        local okHp, hp = pcall(function() return ToNum(pObj.CurrentHp) end)
        if okHp and hp ~= nil and hp <= 0 then st.isDead = true end

        if not st.waitingCE then
            pcall(function()
                local statuses = pObj.StatusList
                if statuses ~= nil then
                    local len = ToNum(statuses.Length) or 0
                    for i = 0, len - 1 do
                        local s = statuses[i]
                        if s ~= nil and ToNum(s.StatusId) ~= 0 then
                            local sName = ExtractStr(s.GameData.Value.Name)
                            if string.find(sName, "遭遇") or string.find(sName, "参战") or string.find(sName, "申请") or string.find(sName, "紧急") then
                                st.waitingCE = true
                                st.ceReason = "状态(" .. sName .. ")"
                                break
                            end
                        end
                    end
                end
            end)
        end
    end

    if st.px ~= nil and Svc ~= nil and Svc.Objects ~= nil then
        pcall(function()
            local objLen = ToNum(Svc.Objects.Length) or 0
            for i = 0, objLen - 1 do
                local obj = Svc.Objects[i]
                if obj ~= nil then
                    local kindStr = tostring(obj.ObjectKind or "")
                    local opos = obj.Position
                    local ox, oy, oz = ToNum(opos.X), ToNum(opos.Y), ToNum(opos.Z)
                    local d = CalcDist(st.px, st.py, st.pz, ox, oy, oz)

                    if (kindStr == "Player" or kindStr == "1") and d > 0.5 and d <= 65.0 then
                        local pDead = ToBool(obj.IsDead)
                        local pHp = ToNum(obj.CurrentHp) or 0
                        if not pDead and pHp > 0 then
                            st.alivePlayersNearby = st.alivePlayersNearby + 1
                        end
                    elseif kindStr == "BattleNpc" or kindStr == "2" then
                        local canTarget = ToBool(obj.IsTargetable)
                        local objDead = ToBool(obj.IsDead)
                        local curHp = ToNum(obj.CurrentHp) or 0
                        local maxHp = ToNum(obj.MaxHp) or 0
                        local flagsStr = tostring(obj.StatusFlags or "")
                        local objName = ExtractStr(obj.Name)

                        if not st.waitingCE and not canTarget and not objDead and maxHp > 0 and objName ~= "" and d <= 40.0 then
                            st.waitingCE = true
                            st.ceReason = "场内待战首领(" .. objName .. ")"
                        end

                        if canTarget and not objDead and curHp > 0 and d <= 65.0 then
                            if (maxHp > 0 and curHp < maxHp) or string.find(flagsStr, "InCombat") then
                                st.bossFightingNearby = true
                            end
                        end
                    end
                end
            end
        end)
    end

    local tObj = nil
    if Svc ~= nil and Svc.Targets ~= nil then
        local okTO, obj = pcall(function() return Svc.Targets.Target end)
        if okTO then tObj = obj end
    end
    if tObj == nil and Entity ~= nil then
        local okTO2, obj2 = pcall(function() return Entity.Target end)
        if okTO2 then tObj = obj2 end
    end

    if tObj ~= nil then
        st.hasTarget = true
        local okName, nameVal = pcall(function()
            return (tObj.Name ~= nil) and ExtractStr(tObj.Name) or ""
        end)
        if okName and nameVal ~= nil then st.targetName = tostring(nameVal) end

        local okTPos, tx, ty, tz = pcall(function()
            local pos = tObj.Position
            return ToNum(pos.X), ToNum(pos.Y), ToNum(pos.Z)
        end)
        if okTPos and tx ~= nil then st.tx, st.ty, st.tz = tx, ty, tz end
    end

    st.distToTarget = CalcDist(st.px, st.py, st.pz, st.tx, st.ty, st.tz)

    st.uiTalk = IsAddonReady("Talk")
    st.uiSelectString = IsAddonReady("SelectString")
    st.uiSelectIconString = IsAddonReady("SelectIconString")
    st.uiSelectYesno = IsAddonReady("SelectYesno")
    if st.uiSelectYesno then
        st.yesnoType = GetYesnoKind()
    end
    st.uiDutyConfirm = IsAddonReady("ContentsFinderConfirm")
    st.uiShopCurrency = IsAddonReady("ShopExchangeCurrency")

    return st
end

local function MoveToPos(tx, ty, tz)
    local ok, moved = pcall(function()
        local t = Svc.Targets.Target
        if t == nil then return false end
        return IPC.vnavmesh.PathfindAndMoveTo(t.Position, false) ~= nil
    end)
    if ok and moved then return end
    yield(string.format("/vnav moveto %.2f %.2f %.2f", tx, ty, tz))
end

local function StopNav()
    if IPC ~= nil and IPC.vnavmesh ~= nil then
        local ok = pcall(function() IPC.vnavmesh.Stop() end)
        if ok then return end
    end
    yield("/vnav stop")
end

-- ===== 状态上下文 =====
local ctx = {
    northHornId = NORTH_HORN_MAP_ID,
    startedBocchi = false,
    stoppedOutside = false,
    outsideWait = 0,
    menuStep = 1,
    idleSec = 0,
    restartStage = 0,
    lastX = nil, lastY = nil, lastZ = nil,
    wasDead = false,
    deadSec = 0,
    noFightSec = 0,
    announcedFight = false,
    announcedCE = false,
    shoutedHelp = false,
    raisedByPlayer = false,
    deathX = nil, deathY = nil, deathZ = nil,
    farmElapsedSec = 0
}

local function ResetHealthFlags()
    ctx.idleSec = 0
    ctx.restartStage = 0
    ctx.lastX, ctx.lastY, ctx.lastZ = nil, nil, nil
    ctx.wasDead = false
    ctx.deadSec = 0
    ctx.noFightSec = 0
    ctx.announcedFight = false
    ctx.announcedCE = false
    ctx.shoutedHelp = false
    ctx.raisedByPlayer = false
    ctx.deathX, ctx.deathY, ctx.deathZ = nil, nil, nil
end

local function RestartPlugins()
    yield(BMR_AI_OFF)
    yield("/wait 0.3")
    yield(BMR_AI_ON)
    yield("/wait 0.3")
    yield(BOCCHI_CMD_OFF)
    yield("/wait 1.2")
    yield(BOCCHI_CMD_ON)
end

local function TryReturnToCamp(preX, preY, preZ)
    yield(BOCCHI_CMD_OFF)
    yield("/wait 0.3")
    yield(BMR_AI_OFF)
    yield("/wait 0.5")
    yield("/gaction 返回")

    for _ = 1, 5 do
        yield("/wait 0.4")
        local okY, stY = pcall(GetTickState)
        if okY and stY.uiSelectYesno then
            yield("/callback SelectYesno true 0")
            break
        end
    end

    for step = 1, 10 do
        yield("/wait 1.0")
        local okW, stW = pcall(GetTickState)
        if okW then
            if stW.isLoading then
                while true do
                    yield("/wait 1.0")
                    local okL, stL = pcall(GetTickState)
                    if okL and not stL.isLoading and stL.territoryId ~= 0 then return true end
                end
            elseif preX ~= nil and stW.px ~= nil and CalcDist(stW.px, stW.py, stW.pz, preX, preY, preZ) > 15.0 then
                return true
            elseif step >= 2 and not stW.isCasting then
                return false
            end
        end
    end
    return false
end

local function RunCoinExchange(st)
    yield("/echo [新月岛守望] 已挂机满 2.5 小时，关闭 BOCCHI 与 BMR AI，准备回营地兑换终极固定剂...")
    yield(BOCCHI_CMD_OFF)
    yield("/wait 0.3")
    yield(BMR_AI_OFF)
    StopNav()
    yield("/wait 0.5")

    local atCamp = false
    yield("/target " .. APPRAISER_NAME)
    yield("/wait 0.4")
    local okT1, stT1 = pcall(GetTickState)
    if okT1 and stT1.hasTarget and stT1.targetName == APPRAISER_NAME and stT1.distToTarget <= 45.0 then
        atCamp = true
    else
        atCamp = TryReturnToCamp(st.px, st.py, st.pz)
    end

    if not atCamp then
        yield("/echo [新月岛守望] 「返回」冷却中，重新打开 BOCCHI 与 BMR AI 继续挂机，5分钟后再试...")
        ctx.farmElapsedSec = math.max(0, (EXCHANGE_INTERVAL_MIN - 5.0) * 60.0)
        yield(BMR_AI_ON)
        yield("/wait 0.3")
        yield(BOCCHI_CMD_ON)
        ResetHealthFlags()
        return
    end

    yield("/wait 1.5")
    local openedShop = false
    local clickedSub = false

    for _ = 1, 30 do
        local okS, stS = pcall(GetTickState)
        if not okS then break end
        if stS.uiShopCurrency then
            openedShop = true
            break
        elseif (stS.uiSelectString or stS.uiSelectIconString) and APPRAISER_HAS_SUBMENU and not clickedSub then
            local cmd = stS.uiSelectString and "SelectString" or "SelectIconString"
            yield(string.format("/callback %s true %d", cmd, APPRAISER_MENU_CHOICE))
            clickedSub = true
            yield("/wait 0.8")
        elseif stS.uiTalk then
            yield("/callback Talk true 0")
            yield("/wait 0.4")
        elseif stS.hasTarget and stS.targetName == APPRAISER_NAME and stS.tx ~= nil then
            if stS.distToTarget > 3.0 then
                if not stS.isMoving then MoveToPos(stS.tx, stS.ty, stS.tz) end
                yield("/wait 0.5")
            else
                if stS.isMoving then
                    StopNav()
                    yield("/wait 0.3")
                end
                yield("/interact")
                yield("/wait 0.8")
            end
        else
            yield("/target " .. APPRAISER_NAME)
            yield("/wait 0.5")
        end
    end

    if openedShop then
        yield("/wait 0.4")
        yield(string.format("/callback ShopExchangeCurrency true 1 %d", SHOP_OTHER_TAB_INDEX))
        yield("/wait 0.8")

        local bought = 0
        local noConfirmStreak = 0
        for _ = 1, MAX_BUY_ATTEMPTS do
            yield(string.format("/callback ShopExchangeCurrency true 0 %d 1", FIXATIVE_ROW_INDEX))
            local gotYesno = false
            for _ = 1, 8 do
                yield("/wait 0.3")
                local okY2, stY2 = pcall(GetTickState)
                if okY2 and stY2.uiSelectYesno then
                    yield("/wait 0.2")
                    yield("/callback SelectYesno true 0")
                    gotYesno = true
                    yield("/wait 0.8")
                    break
                end
            end

            if gotYesno then
                bought = bought + 1
                noConfirmStreak = 0
            else
                noConfirmStreak = noConfirmStreak + 1
                if noConfirmStreak == 1 then
                    yield(string.format("/callback ShopExchangeCurrency true 1 %d", SHOP_OTHER_TAB_INDEX))
                    yield("/wait 0.7")
                else
                    break
                end
            end
        end

        for _ = 1, 3 do
            local okC, stC = pcall(GetTickState)
            if okC and stC.uiShopCurrency then
                yield("/callback ShopExchangeCurrency true -1")
                yield("/wait 0.4")
            else
                break
            end
        end

        yield("/echo [新月岛守望] 兑换完成（共确认 %d 次），重新打开 BOCCHI 与 BMR AI 并恢复防卡死检测！", bought)
    else
        yield("/echo [新月岛守望] 未能打开鉴定师兑换窗口，重新打开插件，5分钟后再试...")
        ctx.farmElapsedSec = math.max(0, (EXCHANGE_INTERVAL_MIN - 5.0) * 60.0)
    end

    if openedShop then
        ctx.farmElapsedSec = 0
    end

    yield("/wait 1.0")
    yield(BMR_AI_ON)
    yield("/wait 0.3")
    yield(BOCCHI_CMD_ON)
    ResetHealthFlags()
    local okAfter, stAfter = pcall(GetTickState)
    if okAfter and stAfter.px ~= nil then
        ctx.lastX, ctx.lastY, ctx.lastZ = stAfter.px, stAfter.py, stAfter.pz
    end
end

local function StepNorthHorn(st)
    ctx.outsideWait = 0
    ctx.stoppedOutside = false
    ctx.menuStep = 1

    if ENABLE_COIN_EXCHANGE and EXCHANGE_INTERVAL_MIN > 0 then
        ctx.farmElapsedSec = ctx.farmElapsedSec + 1.0
    end

    if not ctx.startedBocchi then
        yield("/wait 3.0")
        yield(BMR_AI_ON)
        yield("/wait 0.3")
        yield(BOCCHI_CMD_ON)
        ctx.startedBocchi = true
        ResetHealthFlags()
        ctx.lastX, ctx.lastY, ctx.lastZ = st.px, st.py, st.pz
        yield("/echo [新月岛守望] 已进北岛，开启 BMR AI 与 BOCCHI！")
        return
    end

    if st.isDead then
        if not ctx.wasDead then
            ctx.deathX, ctx.deathY, ctx.deathZ = st.px, st.py, st.pz
        end
        ctx.wasDead = true
        ctx.idleSec = 0
        ctx.restartStage = 0
        ctx.announcedCE = false
        ctx.deadSec = ctx.deadSec + 1.0

        if st.uiSelectYesno and st.yesnoType == "RAISE" then
            ctx.raisedByPlayer = true
            yield("/echo [新月岛守望] 检测到玩家救助，接受复活！")
            yield("/wait 0.5")
            yield("/callback SelectYesno true 0")
            yield("/wait 2.0")
            return
        end

        if not ctx.shoutedHelp and ctx.deadSec >= 2.0 and st.alivePlayersNearby > 0 then
            yield(SHOUT_HELP_CMD)
            ctx.shoutedHelp = true
        end

        if st.bossFightingNearby and ctx.deadSec < MAX_DEAD_WAIT then
            ctx.noFightSec = 0
            if not ctx.announcedFight then
                yield("/echo [新月岛守望] 周围仍在战斗，等待结算或拉起...")
                ctx.announcedFight = true
            end
            yield("/wait 1.0")
        else
            ctx.noFightSec = ctx.noFightSec + 1.0
            local waitLimit = (st.alivePlayersNearby > 0) and POST_FIGHT_RAISE_WAIT or EMPTY_FIELD_WAIT
            if (ctx.noFightSec >= waitLimit or ctx.deadSec >= MAX_DEAD_WAIT) and st.uiSelectYesno then
                ctx.raisedByPlayer = false
                ctx.deathX, ctx.deathY, ctx.deathZ = nil, nil, nil
                yield("/callback SelectYesno true 0")
                ctx.noFightSec = 0
                yield("/wait 2.0")
            else
                yield("/wait 1.0")
            end
        end
        return
    end

    if ctx.wasDead then
        local nearDeath = (ctx.deathX ~= nil and st.px ~= nil and CalcDist(st.px, st.py, st.pz, ctx.deathX, ctx.deathY, ctx.deathZ) < 25.0)
        local sayThanks = ctx.raisedByPlayer or nearDeath
        ResetHealthFlags()
        yield("/wait 2.5")
        if sayThanks then
            yield(SHOUT_THANKS_CMD)
            yield("/wait 0.3")
        end
        RestartPlugins()
        ctx.lastX, ctx.lastY, ctx.lastZ = st.px, st.py, st.pz
        yield("/wait 1.0")
        return
    end

    if ENABLE_COIN_EXCHANGE
        and EXCHANGE_INTERVAL_MIN > 0
        and ctx.farmElapsedSec >= (EXCHANGE_INTERVAL_MIN * 60.0)
        and not st.inCombat
        and not st.isCasting
        and not st.waitingCE then
        RunCoinExchange(st)
        return
    end

    ctx.deadSec = 0
    ctx.noFightSec = 0
    ctx.announcedFight = false
    ctx.shoutedHelp = false
    ctx.raisedByPlayer = false
    ctx.deathX, ctx.deathY, ctx.deathZ = nil, nil, nil

    local moved = CalcDist(st.px, st.py, st.pz, ctx.lastX, ctx.lastY, ctx.lastZ)
    if st.px ~= nil and (ctx.lastX == nil or moved > 1.5) then
        ctx.lastX, ctx.lastY, ctx.lastZ = st.px, st.py, st.pz
    end

    if st.inCombat or st.isCasting then
        ctx.idleSec = 0
        ctx.restartStage = 0
        ctx.announcedCE = false
    elseif st.waitingCE then
        ctx.idleSec = 0
        ctx.restartStage = 0
        if not ctx.announcedCE then
            yield("/echo [新月岛守望] 检测到正在等待 CE（" .. st.ceReason .. "），暂停发呆重启...")
            ctx.announcedCE = true
        end
    elseif moved > 1.5 then
        ctx.idleSec = 0
        ctx.restartStage = 0
        ctx.announcedCE = false
    elseif st.activeFateCount == 0 then
        ctx.idleSec = 0
        ctx.announcedCE = false
    else
        ctx.announcedCE = false
        ctx.idleSec = ctx.idleSec + 1.0

        if ctx.restartStage == 0 and ctx.idleSec >= IDLE_STAGE1_TIMEOUT then
            yield(string.format("/echo [新月岛守望] 发呆 %.0f 秒（第1步），原地重启插件...", ctx.idleSec))
            yield(BMR_AI_ON)
            yield("/wait 0.3")
            yield(BOCCHI_CMD_OFF)
            yield("/wait 1.2")
            yield(BOCCHI_CMD_ON)
            ctx.idleSec = 0
            ctx.restartStage = 1
            ctx.lastX, ctx.lastY, ctx.lastZ = st.px, st.py, st.pz

        elseif ctx.restartStage == 1 and ctx.idleSec >= IDLE_STAGE2_TIMEOUT then
            yield(string.format("/echo [新月岛守望] 重启后 %.0f 秒仍未动（第2步），「返回」营地...", ctx.idleSec))
            local retOk = TryReturnToCamp(st.px, st.py, st.pz)
            if retOk then
                yield("/wait 2.0")
                yield(BMR_AI_ON)
                yield("/wait 0.3")
                yield(BOCCHI_CMD_ON)
                ResetHealthFlags()
            else
                yield(BMR_AI_ON)
                yield("/wait 0.3")
                yield(BOCCHI_CMD_ON)
                ctx.idleSec = 0
                ctx.restartStage = 2
                ctx.lastX, ctx.lastY, ctx.lastZ = st.px, st.py, st.pz
            end

        elseif ctx.restartStage == 2 and ctx.idleSec >= IDLE_STAGE1_TIMEOUT then
            yield(BMR_AI_ON)
            yield("/wait 0.3")
            yield(BOCCHI_CMD_OFF)
            yield("/wait 1.2")
            yield(BOCCHI_CMD_ON)
            ctx.idleSec = 0
            ctx.lastX, ctx.lastY, ctx.lastZ = st.px, st.py, st.pz
        end
    end

    yield("/wait 1.0")
end

local function StepOutsideCamp(st)
    ctx.startedBocchi = false
    ResetHealthFlags()

    if not ctx.stoppedOutside then
        yield(BOCCHI_CMD_OFF)
        yield("/wait 0.3")
        yield(BMR_AI_OFF)
        ctx.stoppedOutside = true
        yield("/echo [新月岛守望] 已离开北岛，10秒后自动找杰弗瑞重新入岛...")
    end

    if ctx.outsideWait < REENTER_DELAY then
        yield("/wait 1.0")
        ctx.outsideWait = ctx.outsideWait + 1.0
    elseif st.uiDutyConfirm then
        yield("/callback ContentsFinderConfirm true 8")
        yield("/wait 1.5")
    elseif st.uiSelectYesno then
        yield("/callback SelectYesno true 0")
        yield("/wait 0.8")
    elseif st.uiSelectString then
        local ch = MENU_STEPS[ctx.menuStep] or MENU_STEPS[#MENU_STEPS] or 0
        yield(string.format("/callback SelectString true %d", ch))
        if ctx.menuStep < #MENU_STEPS then ctx.menuStep = ctx.menuStep + 1 end
        yield("/wait 0.8")
    elseif st.uiSelectIconString then
        local ch = MENU_STEPS[ctx.menuStep] or MENU_STEPS[#MENU_STEPS] or 0
        yield(string.format("/callback SelectIconString true %d", ch))
        if ctx.menuStep < #MENU_STEPS then ctx.menuStep = ctx.menuStep + 1 end
        yield("/wait 0.8")
    elseif st.uiTalk then
        yield("/callback Talk true 0")
        yield("/wait 0.4")
    elseif not st.navReady then
        yield("/wait 1.0")
    elseif st.hasTarget and st.targetName == NPC_NAME and st.tx ~= nil then
        if st.distToTarget > 3.0 then
            ctx.menuStep = 1
            if not st.isMoving then MoveToPos(st.tx, st.ty, st.tz) end
            yield("/wait 0.4")
        else
            if st.isMoving then
                StopNav()
                yield("/wait 0.3")
            end
            yield("/interact")
            yield("/wait 0.8")
        end
    else
        ctx.menuStep = 1
        yield("/target " .. NPC_NAME)
        yield("/wait 0.4")
    end
end

yield("/echo [新月岛守望] 全自动挂机已启动...")

while true do
    local ok, st = pcall(GetTickState)
    if not ok then
        yield("/echo [脚本异常] " .. tostring(st))
        yield("/wait 2.0")
    elseif st.isLoading or st.territoryId == 0 then
        ctx.menuStep = 1
        ctx.idleSec = 0
        ctx.lastX, ctx.lastY, ctx.lastZ = nil, nil, nil
        if ctx.wasDead then
            ctx.raisedByPlayer = false
            ctx.deathX, ctx.deathY, ctx.deathZ = nil, nil, nil
        end
        yield("/wait 1.0")
    else
        if ctx.northHornId == 0 then
            ctx.northHornId = st.territoryId
            yield(string.format("/echo [新月岛守望] 已自动锁定北岛地图ID: %d", math.floor(ctx.northHornId)))
        end

        if st.territoryId == ctx.northHornId then
            StepNorthHorn(st)
        else
            StepOutsideCamp(st)
        end
    end
end