-- ===== 基础配置区 =====
local TARGET_LIST = { "新月白焰", "新月扎戈斧龙", "新月哭泣鬼"}
local ATTACK_RANGE = 2.5      -- 脱战接近怪时的停步距离（近战 2.5 左右，远程/法系可改成 15~20）
local PULL_SKILL = "自动攻击"  -- 到位后的开怪技能（默认普攻，也可改成 "飞刀"、"投盾" 等远程开怪技）
local RETURN_DELAY = 2.0      -- 周围没怪持续多少秒后返回起始点
local HOME_TOLERANCE = 2.0    -- 距离起始点多少米以内算作“已回到原点”（避免原地微调抽搐）
local SCAN_INTERVAL = 0.6     -- 周围没怪时的扫描间隔（秒）
local MOVE_INTERVAL = 0.25    -- 追怪时的状态检测间隔（秒）
local CHASE_IN_COMBAT = false -- 进战后是否继续追怪（保持 false 可完全把位移交给 BossMod 躲技能）

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

local function CalcDist(x1, y1, z1, x2, y2, z2)
    if x1 == nil or x2 == nil then return 9999 end
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ===== 状态采集（整块受 pcall 保护） =====
local function GetTickState()
    local st = {
        navReady = true,
        isMoving = false,
        inCombat = false,
        bmMoving = false,
        hasTarget = false,
        targetAlive = false,
        targetName = "",
        tx = nil, ty = nil, tz = nil,
        px = nil, py = nil, pz = nil,
        dist = 9999
    }

    -- 1. 导航状态
    if IPC ~= nil and IPC.vnavmesh ~= nil then
        local okR, r = pcall(function() return IPC.vnavmesh.IsReady() end)
        if okR and r ~= nil then st.navReady = ToBool(r) end

        local okM, m = pcall(function() return IPC.vnavmesh.IsRunning() end)
        if okM and m ~= nil then st.isMoving = ToBool(m) end
    end

    -- 2. BossMod 是否正在控制位移
    if IPC ~= nil and IPC.BossMod ~= nil then
        local okBM, bm = pcall(function() return IPC.BossMod.IsMoving() end)
        if okBM and bm ~= nil then st.bmMoving = ToBool(bm) end
    end

    -- 3. 战斗状态（Condition 26 = InCombat）
    if Svc ~= nil and Svc.Condition ~= nil then
        local okC, c = pcall(function() return Svc.Condition[26] end)
        if okC and c ~= nil then st.inCombat = ToBool(c) end
    end

    -- 4. 目标信息
    local t = nil
    if Svc ~= nil and Svc.Targets ~= nil then
        local okT, obj = pcall(function() return Svc.Targets.Target end)
        if okT then t = obj end
    end
    if t == nil and Entity ~= nil then
        local okT2, obj2 = pcall(function() return Entity.Target end)
        if okT2 then t = obj2 end
    end

    if t ~= nil then
        st.hasTarget = true
        local okName, nameVal = pcall(function()
            if t.Name ~= nil and t.Name.TextValue ~= nil then
                return t.Name.TextValue
            end
            return t.Name
        end)
        if okName and nameVal ~= nil then
            st.targetName = tostring(nameVal)
        end

        local okTargetable, canTarget = pcall(function() return t.IsTargetable end)
        local okDead, isDead = pcall(function() return t.IsDead end)
        local alive = true
        if okTargetable and canTarget ~= nil and not ToBool(canTarget) then
            alive = false
        end
        if okDead and isDead ~= nil and ToBool(isDead) then
            alive = false
        end
        st.targetAlive = alive

        local okPos, x, y, z = pcall(function()
            local p = t.Position
            return ToNum(p.X), ToNum(p.Y), ToNum(p.Z)
        end)
        if okPos and x ~= nil and y ~= nil and z ~= nil then
            st.tx, st.ty, st.tz = x, y, z
        end
    end

    -- 5. 玩家坐标
    local pObj = nil
    if Svc ~= nil and Svc.Objects ~= nil then
        local okP, obj = pcall(function() return Svc.Objects.LocalPlayer end)
        if okP then pObj = obj end
    end
    if pObj == nil and Svc ~= nil and Svc.ClientState ~= nil then
        local okP2, obj2 = pcall(function() return Svc.ClientState.LocalPlayer end)
        if okP2 then pObj = obj2 end
    end
    if pObj == nil and Entity ~= nil then
        local okP3, obj3 = pcall(function() return Entity.Player end)
        if okP3 then pObj = obj3 end
    end

    if pObj ~= nil then
        local okPPos, px, py, pz = pcall(function()
            local pos = pObj.Position
            return ToNum(pos.X), ToNum(pos.Y), ToNum(pos.Z)
        end)
        if okPPos and px ~= nil and py ~= nil and pz ~= nil then
            st.px, st.py, st.pz = px, py, pz
        end
    end

    -- 6. 计算与目标的三维距离
    st.dist = CalcDist(st.tx, st.ty, st.tz, st.px, st.py, st.pz)

    return st
end

local function IsTargetInList(name)
    for _, mob in ipairs(TARGET_LIST) do
        if name == mob then
            return true
        end
    end
    return false
end

local function TryIpcMoveTarget()
    local t = Svc.Targets.Target
    if t == nil then return false end
    local res = IPC.vnavmesh.PathfindAndMoveTo(t.Position, false)
    return res ~= nil
end

local function TryIpcStop()
    IPC.vnavmesh.Stop()
    return true
end

-- 位移控制权与状态变量
local scriptOwnedMove = false
local isReturningHome = false
local lastX, lastY, lastZ = 0, 0, 0
local pullCooldown = 0
local noMobElapsed = 0

-- 记录起始挂机点坐标
local homeX, homeY, homeZ = nil, nil, nil

local function StartScriptMove(tx, ty, tz, useTargetObj)
    scriptOwnedMove = true
    if useTargetObj then
        local ok, moved = pcall(TryIpcMoveTarget)
        if ok and moved then
            return
        end
    end
    yield(string.format("/vnav moveto %.2f %.2f %.2f", tx, ty, tz))
end

local function StopScriptMove()
    if not scriptOwnedMove then
        return
    end
    scriptOwnedMove = false
    local ok = pcall(TryIpcStop)
    if not ok then
        yield("/vnav stop")
    end
end

-- ===== 启动并记录起始坐标 =====
local okInit, initSt = pcall(GetTickState)
if okInit and initSt.px ~= nil then
    homeX, homeY, homeZ = initSt.px, initSt.py, initSt.pz
    yield(string.format("/echo [自动刷怪] 脚本已启动，已记录起始点 (%.1f, %.1f, %.1f)", homeX, homeY, homeZ))
else
    yield("/echo [自动刷怪] 脚本已启动，开始检索附近目标...")
end

-- ===== 主循环 =====
while true do
    if pullCooldown > 0 then
        pullCooldown = pullCooldown - MOVE_INTERVAL
    end

    local ok, st = pcall(GetTickState)
    if not ok then
        yield("/echo [脚本异常] " .. tostring(st))
        yield("/wait 2.0")
    elseif not st.navReady then
        yield("/wait 1.0")
    else
        -- 兜底记录起始点（防止刚切图加载完才读取到坐标）
        if homeX == nil and st.px ~= nil then
            homeX, homeY, homeZ = st.px, st.py, st.pz
            yield(string.format("/echo [自动刷怪] 已记录起始点 (%.1f, %.1f, %.1f)", homeX, homeY, homeZ))
        end

        if not st.isMoving then
            scriptOwnedMove = false
        end

        if st.inCombat then
            -- 战斗中：重置无怪计时与回程状态，完全把位移交给 BossMod 躲技能
            noMobElapsed = 0
            isReturningHome = false
            pullCooldown = 0

            if not CHASE_IN_COMBAT then
                StopScriptMove()
                yield("/wait " .. MOVE_INTERVAL)
            else
                if st.bmMoving then
                    scriptOwnedMove = false
                elseif st.hasTarget and st.targetAlive and st.dist > ATTACK_RANGE + 1.5 then
                    if st.tx ~= nil and st.ty ~= nil and st.tz ~= nil then
                        local movedDist = CalcDist(st.tx, st.ty, st.tz, lastX, lastY, lastZ)
                        if not st.isMoving or movedDist > 1.5 then
                            lastX, lastY, lastZ = st.tx, st.ty, st.tz
                            StartScriptMove(st.tx, st.ty, st.tz, true)
                        end
                    end
                else
                    StopScriptMove()
                end
                yield("/wait " .. MOVE_INTERVAL)
            end

        elseif st.hasTarget and st.targetAlive and IsTargetInList(st.targetName) then
            -- 脱战且已锁定目标：重置无怪计时，若正在回程则立刻取消并转向追怪
            noMobElapsed = 0
            if isReturningHome then
                isReturningHome = false
                StopScriptMove()
            end

            if st.dist > ATTACK_RANGE then
                pullCooldown = 0
                if st.tx ~= nil and st.ty ~= nil and st.tz ~= nil then
                    local movedDist = CalcDist(st.tx, st.ty, st.tz, lastX, lastY, lastZ)
                    if not st.isMoving or movedDist > 1.5 then
                        lastX, lastY, lastZ = st.tx, st.ty, st.tz
                        StartScriptMove(st.tx, st.ty, st.tz, true)
                    end
                end
                yield("/wait " .. MOVE_INTERVAL)
            else
                StopScriptMove()
                if pullCooldown <= 0 then
                    pullCooldown = 1.2
                    yield("/facetarget")
                    yield("/action " .. PULL_SKILL)
                end
                yield("/wait " .. MOVE_INTERVAL)
            end

        else
            -- 脱战且当前没有有效目标：先停掉追怪位移（若不是在回程途中）
            pullCooldown = 0
            if not isReturningHome then
                StopScriptMove()
            end
            if st.hasTarget and not st.targetAlive then
                yield("/cleartarget")
            end

            local bestName = nil
            local bestDist = 9999

            for _, mob in ipairs(TARGET_LIST) do
                yield("/target " .. mob)
                yield("/wait 0.06")
                local okScan, scanSt = pcall(GetTickState)
                if okScan and scanSt.hasTarget and scanSt.targetAlive and scanSt.targetName == mob then
                    if scanSt.dist < bestDist then
                        bestDist = scanSt.dist
                        bestName = mob
                    end
                end
            end

            if bestName ~= nil then
                -- 发现新怪：清零无怪计时，取消回程，锁定目标准备开打
                noMobElapsed = 0
                if isReturningHome then
                    isReturningHome = false
                    StopScriptMove()
                end
                yield("/target " .. bestName)
                yield("/wait 0.06")
                lastX, lastY, lastZ = 0, 0, 0
            else
                -- 周围依然没怪：累计无怪时间，满 2 秒后自动走回起始点
                yield("/wait " .. SCAN_INTERVAL)
                noMobElapsed = noMobElapsed + SCAN_INTERVAL + (0.06 * #TARGET_LIST)

                if noMobElapsed >= RETURN_DELAY and homeX ~= nil and st.px ~= nil then
                    local distHome = CalcDist(st.px, st.py, st.pz, homeX, homeY, homeZ)
                    if distHome > HOME_TOLERANCE then
                        if not isReturningHome or not st.isMoving then
                            isReturningHome = true
                            StartScriptMove(homeX, homeY, homeZ, false)
                        end
                    else
                        if isReturningHome then
                            isReturningHome = false
                            StopScriptMove()
                        end
                    end
                end
            end
        end
    end
end