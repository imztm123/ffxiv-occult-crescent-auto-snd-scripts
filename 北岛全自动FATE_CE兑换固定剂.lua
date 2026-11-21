-- ===== 基础配置区 =====
local NORTH_HORN_MAP_ID = 1346   -- 填 0 表示在北岛内启动时自动记录地图ID；记下聊天框打印的数字后建议填回这里
local NPC_NAME = "杰弗瑞"      -- 岛外营地负责传送进新月岛的 NPC 名字
local MENU_STEPS = { 0 }      -- 第一层菜单选第1项（索引0）；第二层确认弹窗同样自动选第1项“是”
local REENTER_DELAY = 10.0    -- 被踢出岛后等待 10 秒再开始找 NPC

-- ===== 白银币自动兑换配置区（已实机验证校准） =====
local ENABLE_COIN_EXCHANGE = true          -- 是否开启白银币满额自动回营地兑换
local SILVER_COIN_THRESHOLD = 8000         -- 十二城邦白银币达到多少时触发回营地兑换
local FIXATIVE_UNIT_COST = 1200            -- 单个终极固定剂消耗的白银币数量
local APPRAISER_NAME = "调查队的古钱鉴定师" -- 营地兑换 NPC 名字
local APPRAISER_HAS_SUBMENU = true         -- 对话后先进入二级分类菜单
local APPRAISER_MENU_CHOICE = 1            -- 第2项：十二城邦白银币（其他）（0=780装备, 1=其他）
local SHOP_OTHER_TAB_INDEX = 3             -- 顶部第4个标签：其他（0=武器, 1=防具, 2=饰品, 3=其他）
local FIXATIVE_ROW_INDEX = 13              -- “其他”列表第14行：终极固定剂（从0开始数）

-- ===== 防卡死与阵亡配置区 =====
local IDLE_STAGE1_TIMEOUT = 20.0  -- 第1步：发呆满 20 秒触发原地重启
local IDLE_STAGE2_TIMEOUT = 8.0   -- 第2步：原地重启后过 8 秒仍未移动，触发「返回」回营地再重开

local POST_FIGHT_RAISE_WAIT = 8.0 -- 周围战斗结束后，若有活人再多等几秒看是否有人拉复活
local EMPTY_FIELD_WAIT = 3.0      -- 周围既没战斗也没活人时，等几秒直接回出生点
local MAX_DEAD_WAIT = 240.0       -- 单次躺尸最长等待上限（4分钟，防止极端卡死被系统强踢）

local SHOUT_HELP_CMD = "/sh 999"   -- 阵亡且附近有活人时自动发送的求救喊话
local SHOUT_THANKS_CMD = "/sh 谢谢" -- 被其他玩家拉起复活后自动发送的感谢喊话

local BOCCHI_CMD_ON = "/bocchiillegal on"
local BOCCHI_CMD_OFF = "/bocchiillegal off"
local BMR_AI_ON = "/bmrai on"
local BMR_AI_OFF = "/bmrai off"

-- ===== 安全类型转换 =====
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
    if ok1 and t1 ~= nil and tostring(t1) ~= "" then
        return tostring(t1)
    end
    local ok2, t2 = pcall(function() return seStr.TextValue end)
    if ok2 and t2 ~= nil and tostring(t2) ~= "" then
        return tostring(t2)
    end
    return tostring(seStr)
end

local function CalcDist(x1, y1, z1, x2, y2, z2)
    if x1 == nil or x2 == nil then return 9999 end
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function IsAddonOpen(addonName)
    if Addons ~= nil and Addons.GetAddon ~= nil then
        local okA, addon = pcall(function() return Addons.GetAddon(addonName) end)
        if okA and addon ~= nil then
            local okR, rdy = pcall(function() return addon.Ready end)
            if okR and ToBool(rdy) then
                return true
            end
        end
    end
    return false
end

-- 安全读取窗口中所有字符串类型的 AtkValue（兼容枚举数字与边界终止，防止越界读取）
local function ReadAddonStringsSafe(addonName, hardCap)
    if Addons == nil or Addons.GetAddon == nil then return nil end
    local okA, addon = pcall(function() return Addons.GetAddon(addonName) end)
    if not okA or addon == nil then return nil end
    local okR, rdy = pcall(function() return ToBool(addon.Ready) end)
    if not okR or not rdy then return nil end

    local strs = {}
    pcall(function()
        local rawCount = ToNum(addon.AtkValuesCount)
        local maxIdx = hardCap or 35
        if rawCount ~= nil then
            if rawCount <= 0 then return end
            maxIdx = math.min(rawCount - 1, hardCap or 45)
        end

        for idx = 0, maxIdx do
            local okV, val = pcall(function() return addon:GetAtkValue(idx) end)
            -- 读到 nil 说明已到达当前窗口 AtkValue 数组末尾，立刻停止避免越界
            if not okV or val == nil then
                break
            end

            local vTypeStr = tostring(val.Type or "")
            local vTypeNum = ToNum(vTypeStr)
            -- 底层 ValueType 枚举中 0~7 为空值/布尔/整数/浮点，>=8 为各类字符串类型
            local isStringType = (vTypeStr == "")
                or (string.find(vTypeStr, "String") ~= nil)
                or (vTypeNum ~= nil and vTypeNum >= 8)

            if isStringType then
                local okS, vs = pcall(function() return val.ValueString end)
                if okS and vs ~= nil then
                    local clean = ExtractStr(vs):gsub("[%c]", " ")
                    if clean ~= "" and clean ~= "nil" then
                        table.insert(strs, clean)
                    end
                end
            end
        end
    end)

    return strs
end

local CE_KEYWORDS = {
    "已入选",
    "遭遇战",
    "距开始还有",
    "已申请",
    "即将开始",
    "准备中"
}

-- 一次性从 MKDInfo 面板安全提取白银币数量和 CE 等待状态
local function ReadMkdPanelInfo()
    local strs = ReadAddonStringsSafe("MKDInfo", 45)
    if strs == nil then
        return nil, false, ""
    end

    local silverVal = nil
    local waitingCe = false
    local ceReason = ""

    for _, s in ipairs(strs) do
        if silverVal == nil then
            local curStr = string.match(s, "(%d+)%s*/%s*9999")
            if curStr ~= nil then
                silverVal = tonumber(curStr)
            end
        end

        if not waitingCe then
            for _, kw in ipairs(CE_KEYWORDS) do
                if string.find(s, kw) then
                    waitingCe = true
                    ceReason = "MKDInfo:" .. kw
                    break
                end
            end
        end
    end

    return silverVal, waitingCe, ceReason
end

-- 区分 SelectYesno 弹窗当前是“玩家救助”还是“返回开始地点/确认换取”
local function GetSelectYesnoType()
    local strs = ReadAddonStringsSafe("SelectYesno", 6)
    if strs == nil then return "UNKNOWN" end

    local textBuf = table.concat(strs, " ")
    if string.find(textBuf, "救助") or string.find(textBuf, "接受") then
        return "RAISE"
    elseif string.find(textBuf, "开始地点") or string.find(textBuf, "即将回到") or string.find(textBuf, "返回") or string.find(textBuf, "确定") or string.find(textBuf, "换取") then
        return "RETURN"
    end
    return "UNKNOWN"
end

-- ===== 状态采集（整块受 pcall 保护，不含 yield） =====
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
        silverCoins = nil,
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

    -- 1. 基础角色状态
    if Svc ~= nil and Svc.Condition ~= nil then
        local ok45, c45 = pcall(function() return Svc.Condition[45] end)
        local ok51, c51 = pcall(function() return Svc.Condition[51] end)
        if (ok45 and ToBool(c45)) or (ok51 and ToBool(c51)) then
            st.isLoading = true
        end

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

    -- 2. 当前地图 TerritoryType
    if Svc ~= nil and Svc.ClientState ~= nil then
        local okT, tid = pcall(function() return ToNum(Svc.ClientState.TerritoryType) end)
        if okT and tid ~= nil then
            st.territoryId = tid
        end
    end

    -- 3. 当前地图活跃 FATE 数量
    if Svc ~= nil and Svc.Fates ~= nil then
        local okF, fCount = pcall(function() return ToNum(Svc.Fates.Count) end)
        if okF and fCount ~= nil then
            st.activeFateCount = fCount
        end
    end

    -- 4. 导航状态
    if IPC ~= nil and IPC.vnavmesh ~= nil then
        local okR, r = pcall(function() return IPC.vnavmesh.IsReady() end)
        if okR and r ~= nil then st.navReady = ToBool(r) end

        local okM, m = pcall(function() return IPC.vnavmesh.IsRunning() end)
        if okM and m ~= nil then st.isMoving = ToBool(m) end
    end

    -- 5. 玩家坐标与血量
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
        if okPos and px ~= nil then
            st.px, st.py, st.pz = px, py, pz
        end

        local okDead, deadFlag = pcall(function() return pObj.IsDead end)
        if okDead and ToBool(deadFlag) then st.isDead = true end

        local okHp, hp = pcall(function() return ToNum(pObj.CurrentHp) end)
        if okHp and hp ~= nil and hp <= 0 then st.isDead = true end
    end

    -- 6. 扫描周围实体
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

    -- 7. 安全读取新月岛信息面板 (MKDInfo) 的白银币数量与 CE 倒计时
    local coins, mkdCe, mkdReason = ReadMkdPanelInfo()
    st.silverCoins = coins
    if not st.waitingCE and mkdCe then
        st.waitingCE = true
        st.ceReason = mkdReason
    end

    -- 8. 当前选中目标
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
            if tObj.Name ~= nil then
                return ExtractStr(tObj.Name)
            end
            return ""
        end)
        if okName and nameVal ~= nil then
            st.targetName = tostring(nameVal)
        end

        local okTPos, tx, ty, tz = pcall(function()
            local pos = tObj.Position
            return ToNum(pos.X), ToNum(pos.Y), ToNum(pos.Z)
        end)
        if okTPos and tx ~= nil then
            st.tx, st.ty, st.tz = tx, ty, tz
        end
    end

    st.distToTarget = CalcDist(st.px, st.py, st.pz, st.tx, st.ty, st.tz)

    -- 9. 对话与兑换商店窗口状态
    st.uiTalk = IsAddonOpen("Talk")
    st.uiSelectString = IsAddonOpen("SelectString")
    st.uiSelectIconString = IsAddonOpen("SelectIconString")
    st.uiSelectYesno = IsAddonOpen("SelectYesno")
    if st.uiSelectYesno then
        st.yesnoType = GetSelectYesnoType()
    end
    st.uiDutyConfirm = IsAddonOpen("ContentsFinderConfirm")
    st.uiShopCurrency = IsAddonOpen("ShopExchangeCurrency")

    return st
end

local function TryIpcMoveTarget()
    local t = Svc.Targets.Target
    if t == nil then return false end
    local res = IPC.vnavmesh.PathfindAndMoveTo(t.Position, false)
    return res ~= nil
end

local function MoveToCurrentTarget(tx, ty, tz)
    local ok, moved = pcall(TryIpcMoveTarget)
    if ok and moved then
        return
    end
    yield(string.format("/vnav moveto %.2f %.2f %.2f", tx, ty, tz))
end

local function StopNav()
    if IPC ~= nil and IPC.vnavmesh ~= nil then
        local ok = pcall(function() IPC.vnavmesh.Stop() end)
        if ok then return end
    end
    yield("/vnav stop")
end

-- ===== 运行期状态变量 =====
local targetNorthHornId = NORTH_HORN_MAP_ID
local hasStartedBocchi = false
local hasStoppedBocchiOutside = false
local outsideWaitElapsed = 0
local menuStepIdx = 1

-- 岛内防卡死与智能复活监控变量
local idleSeconds = 0
local restartStage = 0
local lastCheckX, lastCheckY, lastCheckZ = nil, nil, nil
local wasDead = false
local deadTotalElapsed = 0
local noFightAfterDeathElapsed = 0
local announcedWaitingFight = false
local announcedWaitingCE = false
local hasShoutedHelp = false
local wasRaisedByPlayer = false
local deathX, deathY, deathZ = nil, nil, nil

-- 白银币自动兑换状态变量
local lastLoggedCoins = nil
local exchangeRetryCooldown = 0

yield("/echo [新月岛守望] 内存安全加固版全自动挂机已启动...")

while true do
    local ok, st = pcall(GetTickState)
    if not ok then
        yield("/echo [脚本异常] " .. tostring(st))
        yield("/wait 2.0")
    elseif st.isLoading or st.territoryId == 0 then
        menuStepIdx = 1
        idleSeconds = 0
        lastCheckX, lastCheckY, lastCheckZ = nil, nil, nil
        if wasDead then
            wasRaisedByPlayer = false
            deathX, deathY, deathZ = nil, nil, nil
        end
        yield("/wait 1.0")
    else
        -- 首次在岛内启动时自动锁定北岛地图ID
        if targetNorthHornId == 0 then
            targetNorthHornId = st.territoryId
            yield(string.format("/echo [新月岛守望] 已自动锁定北岛地图ID: %d（建议填回脚本顶部配置区）", targetNorthHornId))
        end

        if st.territoryId == targetNorthHornId then
            -- ===== 情况A：当前处于新月岛北岛内 =====
            outsideWaitElapsed = 0
            hasStoppedBocchiOutside = false
            menuStepIdx = 1

            if exchangeRetryCooldown > 0 then
                exchangeRetryCooldown = math.max(0, exchangeRetryCooldown - 1.0)
            end

            if st.silverCoins ~= nil and (lastLoggedCoins == nil or math.abs(st.silverCoins - lastLoggedCoins) >= 600) then
                lastLoggedCoins = st.silverCoins
                yield(string.format("/echo [新月岛守望] 当前十二城邦白银币: %d / 9999", st.silverCoins))
            end

            if not hasStartedBocchi then
                yield("/wait 3.0")
                yield(BMR_AI_ON)
                yield("/wait 0.3")
                yield(BOCCHI_CMD_ON)
                hasStartedBocchi = true
                wasDead = false
                deadTotalElapsed = 0
                noFightAfterDeathElapsed = 0
                announcedWaitingFight = false
                announcedWaitingCE = false
                hasShoutedHelp = false
                wasRaisedByPlayer = false
                deathX, deathY, deathZ = nil, nil, nil
                idleSeconds = 0
                restartStage = 0
                lastCheckX, lastCheckY, lastCheckZ = st.px, st.py, st.pz
                yield("/echo [新月岛守望] 已进入新月岛北岛，自动开启 BMR AI 与 BOCCHI！")
            elseif st.isDead then
                -- ===== 阵亡智能决策分支 =====
                if not wasDead then
                    deathX, deathY, deathZ = st.px, st.py, st.pz
                end
                wasDead = true
                idleSeconds = 0
                restartStage = 0
                announcedWaitingCE = false
                deadTotalElapsed = deadTotalElapsed + 1.0

                if st.uiSelectYesno and st.yesnoType == "RAISE" then
                    wasRaisedByPlayer = true
                    yield("/echo [新月岛守望] 检测到玩家救助弹窗，立即接受复活！")
                    yield("/wait 0.5")
                    yield("/callback SelectYesno true 0")
                    yield("/wait 2.0")
                else
                    if not hasShoutedHelp and deadTotalElapsed >= 2.0 and st.alivePlayersNearby > 0 then
                        yield(SHOUT_HELP_CMD)
                        hasShoutedHelp = true
                        yield("/echo [新月岛守望] 检测到附近有其他玩家，已在喊话频道发送求救...")
                    end

                    if st.bossFightingNearby and deadTotalElapsed < MAX_DEAD_WAIT then
                        noFightAfterDeathElapsed = 0
                        if not announcedWaitingFight then
                            yield("/echo [新月岛守望] 阵亡但周围战斗仍在进行，等待打完结算奖励或等人拉起...")
                            announcedWaitingFight = true
                        end
                        yield("/wait 1.0")
                    else
                        noFightAfterDeathElapsed = noFightAfterDeathElapsed + 1.0
                        local graceWait = (st.alivePlayersNearby > 0) and POST_FIGHT_RAISE_WAIT or EMPTY_FIELD_WAIT

                        if (noFightAfterDeathElapsed >= graceWait or deadTotalElapsed >= MAX_DEAD_WAIT) and st.uiSelectYesno then
                            wasRaisedByPlayer = false
                            deathX, deathY, deathZ = nil, nil, nil
                            yield("/echo [新月岛守望] 战斗已结束且无人救助，确认返回开始地点...")
                            yield("/callback SelectYesno true 0")
                            noFightAfterDeathElapsed = 0
                            yield("/wait 2.0")
                        else
                            yield("/wait 1.0")
                        end
                    end
                end

            elseif wasDead then
                -- ===== 刚复活站稳后的处理 =====
                local revivedInPlace = (deathX ~= nil and st.px ~= nil and CalcDist(st.px, st.py, st.pz, deathX, deathY, deathZ) < 25.0)
                local shouldSayThanks = wasRaisedByPlayer or revivedInPlace

                wasDead = false
                deadTotalElapsed = 0
                noFightAfterDeathElapsed = 0
                announcedWaitingFight = false
                announcedWaitingCE = false
                hasShoutedHelp = false
                wasRaisedByPlayer = false
                deathX, deathY, deathZ = nil, nil, nil

                yield("/wait 2.5")
                if shouldSayThanks then
                    yield(SHOUT_THANKS_CMD)
                    yield("/wait 0.3")
                    yield("/echo [新月岛守望] 已被玩家拉起，已发送感谢喊话并重启插件...")
                else
                    yield("/echo [新月岛守望] 已返回出生点复活，自动重启 BMR AI 与 BOCCHI...")
                end

                yield(BMR_AI_OFF)
                yield("/wait 0.3")
                yield(BMR_AI_ON)
                yield("/wait 0.3")
                yield(BOCCHI_CMD_OFF)
                yield("/wait 1.2")
                yield(BOCCHI_CMD_ON)
                idleSeconds = 0
                restartStage = 0
                lastCheckX, lastCheckY, lastCheckZ = st.px, st.py, st.pz
                yield("/wait 1.0")

            elseif ENABLE_COIN_EXCHANGE
                and exchangeRetryCooldown <= 0
                and st.silverCoins ~= nil
                and st.silverCoins >= SILVER_COIN_THRESHOLD
                and not st.inCombat
                and not st.isCasting
                and not st.waitingCE then

                -- ===== 白银币达到 8000 以上：自动回营地找调查队的古钱鉴定师兑换终极固定剂 =====
                yield(string.format("/echo [新月岛守望] 检测到十二城邦白银币已达 %d，暂停挂机回营地兑换终极固定剂...", st.silverCoins))
                yield(BOCCHI_CMD_OFF)
                yield("/wait 0.3")
                yield(BMR_AI_OFF)
                StopNav()
                yield("/wait 0.5")

                -- 步骤 1：判断是否已在营地范围内，否则读条「返回」
                local atCamp = false
                yield("/target " .. APPRAISER_NAME)
                yield("/wait 0.4")
                local okT1, stT1 = pcall(GetTickState)
                if okT1 and stT1.hasTarget and stT1.targetName == APPRAISER_NAME and stT1.distToTarget <= 45.0 then
                    atCamp = true
                else
                    local preRetX, preRetY, preRetZ = st.px, st.py, st.pz
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
                                    if okL and not stL.isLoading and stL.territoryId ~= 0 then
                                        break
                                    end
                                end
                                atCamp = true
                                break
                            elseif preRetX ~= nil and stW.px ~= nil and CalcDist(stW.px, stW.py, stW.pz, preRetX, preRetY, preRetZ) > 15.0 then
                                atCamp = true
                                break
                            elseif step >= 2 and not stW.isCasting then
                                break
                            end
                        end
                    end
                end

                if not atCamp then
                    yield("/echo [新月岛守望] 「返回」技能冷却中，暂先继续刷怪，45秒后再尝试回营地兑换...")
                    exchangeRetryCooldown = 45.0
                    yield(BMR_AI_ON)
                    yield("/wait 0.3")
                    yield(BOCCHI_CMD_ON)
                    idleSeconds = 0
                    restartStage = 0
                    lastCheckX, lastCheckY, lastCheckZ = st.px, st.py, st.pz
                else
                    -- 步骤 2：vnav 导航至“调查队的古钱鉴定师”并打开货币交易窗口
                    yield("/wait 1.5")
                    local openedShop = false
                    local clickedSubmenu = false

                    for attempt = 1, 30 do
                        local okS, stS = pcall(GetTickState)
                        if not okS then break end

                        if stS.uiShopCurrency then
                            openedShop = true
                            break
                        elseif (stS.uiSelectString or stS.uiSelectIconString) and APPRAISER_HAS_SUBMENU and not clickedSubmenu then
                            if stS.uiSelectString then
                                yield(string.format("/callback SelectString true %d", APPRAISER_MENU_CHOICE))
                            else
                                yield(string.format("/callback SelectIconString true %d", APPRAISER_MENU_CHOICE))
                            end
                            clickedSubmenu = true
                            yield("/wait 0.8")
                        elseif stS.uiTalk then
                            yield("/callback Talk true 0")
                            yield("/wait 0.4")
                        elseif stS.hasTarget and stS.targetName == APPRAISER_NAME and stS.tx ~= nil then
                            if stS.distToTarget > 3.0 then
                                if not stS.isMoving then
                                    MoveToCurrentTarget(stS.tx, stS.ty, stS.tz)
                                end
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

                    -- 步骤 3：切换到顶部第4个标签“其他”(操作码 1 3)，购买第14行“终极固定剂”(索引13)，并轮询点击确认弹窗的“是”
                    if openedShop then
                        yield("/wait 0.4")
                        yield(string.format("/callback ShopExchangeCurrency true 1 %d", SHOP_OTHER_TAB_INDEX))
                        yield("/wait 0.8")

                        local boughtCount = 0
                        local failStreak = 0

                        for _ = 1, 10 do
                            local okB, stB = pcall(GetTickState)
                            if not okB or (stB.silverCoins ~= nil and stB.silverCoins < FIXATIVE_UNIT_COST) then
                                break
                            end

                            yield(string.format("/callback ShopExchangeCurrency true 0 %d 1", FIXATIVE_ROW_INDEX))

                            local confirmed = false
                            for _ = 1, 8 do
                                yield("/wait 0.3")
                                local okY2, stY2 = pcall(GetTickState)
                                if okY2 and stY2.uiSelectYesno then
                                    yield("/wait 0.2")
                                    yield("/callback SelectYesno true 0")
                                    confirmed = true
                                    yield("/wait 0.8")
                                    break
                                end
                            end

                            if confirmed then
                                boughtCount = boughtCount + 1
                                failStreak = 0
                            else
                                failStreak = failStreak + 1
                                if failStreak == 1 then
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

                        yield("/wait 0.6")
                        local okEnd, stEnd = pcall(GetTickState)
                        local remainCoins = (okEnd and stEnd.silverCoins) or 0
                        lastLoggedCoins = remainCoins
                        yield(string.format("/echo [新月岛守望] 本次共兑换 %d 个终极固定剂，当前剩余白银币 %d，恢复挂机！", boughtCount, remainCoins))
                    else
                        yield("/echo [新月岛守望] 未能打开鉴定师兑换窗口，60秒后重试并先恢复挂机...")
                        exchangeRetryCooldown = 60.0
                    end

                    yield("/wait 1.0")
                    yield(BMR_AI_ON)
                    yield("/wait 0.3")
                    yield(BOCCHI_CMD_ON)
                    idleSeconds = 0
                    restartStage = 0
                    lastCheckX, lastCheckY, lastCheckZ = nil, nil, nil
                end

            else
                -- ===== 正常存活状态下的两段式健康检查（1秒巡检一次） =====
                deadTotalElapsed = 0
                noFightAfterDeathElapsed = 0
                announcedWaitingFight = false
                hasShoutedHelp = false
                wasRaisedByPlayer = false
                deathX, deathY, deathZ = nil, nil, nil

                local movedDist = CalcDist(st.px, st.py, st.pz, lastCheckX, lastCheckY, lastCheckZ)
                if st.px ~= nil and (lastCheckX == nil or movedDist > 1.5) then
                    lastCheckX, lastCheckY, lastCheckZ = st.px, st.py, st.pz
                end

                if st.inCombat or st.isCasting then
                    idleSeconds = 0
                    restartStage = 0
                    announcedWaitingCE = false
                elseif st.waitingCE then
                    idleSeconds = 0
                    restartStage = 0
                    if not announcedWaitingCE then
                        yield("/echo [新月岛守望] 检测到正在等待 CE（" .. st.ceReason .. "），暂停发呆重启...")
                        announcedWaitingCE = true
                    end
                elseif movedDist > 1.5 then
                    idleSeconds = 0
                    restartStage = 0
                    announcedWaitingCE = false
                elseif st.activeFateCount == 0 then
                    idleSeconds = 0
                    announcedWaitingCE = false
                else
                    announcedWaitingCE = false
                    idleSeconds = idleSeconds + 1.0

                    if restartStage == 0 and idleSeconds >= IDLE_STAGE1_TIMEOUT then
                        yield(string.format("/echo [新月岛守望] 检测到角色发呆 %.0f 秒（第1步），原地重启 BMR AI 与 BOCCHI...", idleSeconds))
                        yield(BMR_AI_ON)
                        yield("/wait 0.3")
                        yield(BOCCHI_CMD_OFF)
                        yield("/wait 1.2")
                        yield(BOCCHI_CMD_ON)
                        idleSeconds = 0
                        restartStage = 1
                        lastCheckX, lastCheckY, lastCheckZ = st.px, st.py, st.pz

                    elseif restartStage == 1 and idleSeconds >= IDLE_STAGE2_TIMEOUT then
                        yield(string.format("/echo [新月岛守望] 重启后 %.0f 秒仍未移动（第2步），关闭插件并「返回」起始营地...", idleSeconds))
                        yield(BOCCHI_CMD_OFF)
                        yield("/wait 0.3")
                        yield(BMR_AI_OFF)
                        yield("/wait 0.5")
                        local preRetX, preRetY, preRetZ = st.px, st.py, st.pz
                        yield("/gaction 返回")

                        for _ = 1, 5 do
                            yield("/wait 0.4")
                            local okY, stY = pcall(GetTickState)
                            if okY and stY.uiSelectYesno then
                                yield("/callback SelectYesno true 0")
                                break
                            end
                        end

                        local returnedCamp = false
                        for step = 1, 10 do
                            yield("/wait 1.0")
                            local okW, stW = pcall(GetTickState)
                            if okW then
                                if stW.isLoading then
                                    while true do
                                        yield("/wait 1.0")
                                        local okL, stL = pcall(GetTickState)
                                        if okL and not stL.isLoading and stL.territoryId ~= 0 then
                                            break
                                        end
                                    end
                                    returnedCamp = true
                                    break
                                elseif preRetX ~= nil and stW.px ~= nil and CalcDist(stW.px, stW.py, stW.pz, preRetX, preRetY, preRetZ) > 15.0 then
                                    returnedCamp = true
                                    break
                                elseif step >= 2 and not stW.isCasting then
                                    break
                                end
                            end
                        end

                        if returnedCamp then
                            yield("/wait 2.0")
                            yield("/echo [新月岛守望] 已回到起始营地，重新开启 BMR AI 与 BOCCHI...")
                            yield(BMR_AI_ON)
                            yield("/wait 0.3")
                            yield(BOCCHI_CMD_ON)
                            idleSeconds = 0
                            restartStage = 0
                            lastCheckX, lastCheckY, lastCheckZ = nil, nil, nil
                        else
                            yield("/echo [新月岛守望] 「返回」技能冷却中或未触发，重新拉起插件（每20秒兜底检测）...")
                            yield(BMR_AI_ON)
                            yield("/wait 0.3")
                            yield(BOCCHI_CMD_ON)
                            idleSeconds = 0
                            restartStage = 2
                            lastCheckX, lastCheckY, lastCheckZ = st.px, st.py, st.pz
                        end

                    elseif restartStage == 2 and idleSeconds >= IDLE_STAGE1_TIMEOUT then
                        yield("/echo [新月岛守望] 「返回」冷却中，再次尝试原地重启插件...")
                        yield(BMR_AI_ON)
                        yield("/wait 0.3")
                        yield(BOCCHI_CMD_OFF)
                        yield("/wait 1.2")
                        yield(BOCCHI_CMD_ON)
                        idleSeconds = 0
                        lastCheckX, lastCheckY, lastCheckZ = st.px, st.py, st.pz
                    end
                end

                yield("/wait 1.0")
            end

        else
            -- ===== 情况B：确认已离开北岛（身处岛外营地） =====
            hasStartedBocchi = false
            wasDead = false
            deadTotalElapsed = 0
            noFightAfterDeathElapsed = 0
            announcedWaitingFight = false
            announcedWaitingCE = false
            hasShoutedHelp = false
            wasRaisedByPlayer = false
            deathX, deathY, deathZ = nil, nil, nil
            idleSeconds = 0
            restartStage = 0
            lastCheckX, lastCheckY, lastCheckZ = nil, nil, nil

            if not hasStoppedBocchiOutside then
                yield(BOCCHI_CMD_OFF)
                yield("/wait 0.3")
                yield(BMR_AI_OFF)
                hasStoppedBocchiOutside = true
                yield("/echo [新月岛守望] 检测到已离开北岛，10秒后自动找杰弗瑞重新入岛...")
            end

            if outsideWaitElapsed < REENTER_DELAY then
                yield("/wait 1.0")
                outsideWaitElapsed = outsideWaitElapsed + 1.0
            elseif st.uiDutyConfirm then
                yield("/callback ContentsFinderConfirm true 8")
                yield("/wait 1.5")
            elseif st.uiSelectYesno then
                yield("/callback SelectYesno true 0")
                yield("/wait 0.8")
            elseif st.uiSelectString then
                local choice = MENU_STEPS[menuStepIdx] or MENU_STEPS[#MENU_STEPS] or 0
                yield(string.format("/callback SelectString true %d", choice))
                if menuStepIdx < #MENU_STEPS then
                    menuStepIdx = menuStepIdx + 1
                end
                yield("/wait 0.8")
            elseif st.uiSelectIconString then
                local choice = MENU_STEPS[menuStepIdx] or MENU_STEPS[#MENU_STEPS] or 0
                yield(string.format("/callback SelectIconString true %d", choice))
                if menuStepIdx < #MENU_STEPS then
                    menuStepIdx = menuStepIdx + 1
                end
                yield("/wait 0.8")
            elseif st.uiTalk then
                yield("/callback Talk true 0")
                yield("/wait 0.4")
            elseif not st.navReady then
                yield("/wait 1.0")
            elseif st.hasTarget and st.targetName == NPC_NAME and st.tx ~= nil then
                if st.distToTarget > 3.0 then
                    menuStepIdx = 1
                    if not st.isMoving then
                        MoveToCurrentTarget(st.tx, st.ty, st.tz)
                    end
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
                menuStepIdx = 1
                yield("/target " .. NPC_NAME)
                yield("/wait 0.4")
            end
        end
    end
end