--[[
  EstencelWeaponFix v0.2 (UE4SS Lua Mod / 参加者全員に導入)

  直すもの:
    サブ武器(AddWeapons)の「名前」と「中身」がずれて、武器Bの枠にAの武器が入る不具合

  原因:
    chelTPC_C の UpdateLoadedWeapons_mc_2(TargetArray) は、イベントに入った時点で
    共有変数 K2Node_CustomEvent_TargetArray を上書きしてから「読み込み中なら予約(Queue)」の判定をする。
    非同期読み込みの途中で次の呼び出しが来ると、読み込み完了時に新しいリストの名前で登録されてしまう。
    (例: Aを読み込み中にリストが変わる → Aの武器が「B」として登録 → Bは読み込み済み扱いで直らない)

  対策(事後修復):
    1. UpdateLoadedWeapons_mc_2 の実行後に QueueOfUpdateLoadedWeapons が空でなければ
       「読み込み中に上書きされた」と判定(予約された時だけ Queue に値が入るため)
    2. そのキャラの読み込み(予約分を含む)がすべて終わり、かつ攻撃・回避などのモンタージュを
       再生していない状態が続いたら、読み込み済みのサブ武器をいったん全部破棄して、最新のリストで読み込み直す

  注意: UE4SS では BP 関数のフックは「実行後」に呼ばれる。
]]

local UEHelpers = require("UEHelpers")

------------------------------------------------------------
-- 定数
------------------------------------------------------------
local POLL_MS    = 500   -- 読み込み完了・動作中かの監視間隔(ミリ秒)
local SAFE_TICKS = 3     -- 「読み込み完了」かつ「モンタージュ再生なし」がこの回数続いたら修復

local CHEL = "/Game/Mannequins/chel/chelTPC.chelTPC_C"

local function log(s) print("[WeaponFix] " .. s .. "\n") end

------------------------------------------------------------
-- 状態(キャラごと)
------------------------------------------------------------
-- state[addr] = { pawn = UObject, names = {string...}, dirty = bool, stable = int, waitingLogged = bool }
local state = {}

local function charName(p)
  local ok, n = pcall(function() return p:GetFullName() end)
  return ok and n or "?"
end

local function namesOf(arr)
  local t = {}
  arr:ForEach(function(_, e) t[#t + 1] = e:get():ToString() end)
  return t
end

------------------------------------------------------------
-- UE4SS の機能チェック(初回の修復時に1回だけ)
------------------------------------------------------------
local canPassArray = nil
local function checkArrayParam()
  if canPassArray ~= nil then return canPassArray end
  canPassArray = false
  pcall(function()
    local KSTR = StaticFindObject("/Script/Engine.Default__KismetStringLibrary")
    local r = KSTR:JoinStringArray({ "a", "b" }, "-")
    local s = type(r) == "string" and r or r:ToString()
    canPassArray = (s == "a-b")
  end)
  log("capability: pass Lua table as TArray param = " .. tostring(canPassArray))
  return canPassArray
end

------------------------------------------------------------
-- 行動中か(攻撃・回避などのモンタージュを再生中なら修復を待つ)
------------------------------------------------------------
local function inAction(p)
  local playing = false
  local ok = pcall(function()
    local anim = p.Mesh:GetAnimInstance()
    playing = anim:IsValid() and anim:IsAnyMontagePlaying()
  end)
  if not ok then return false end   -- 判定できない場合は待たない
  return playing
end

------------------------------------------------------------
-- 修復
------------------------------------------------------------
local function repair(st)
  local p = st.pawn
  if not checkArrayParam() then
    log("repair skipped: this UE4SS cannot pass arrays to functions (please update UE4SS)")
    return
  end
  if not st.names or #st.names == 0 then
    log("repair skipped: no weapon list recorded")
    return
  end

  -- 登録表(TMap<名前, 武器アクター>)から武器を集めて空にする
  local m = p.LoadedAdditionalWeapons
  local actors = {}
  local ok, err = pcall(function()
    m:ForEach(function(_, v) actors[#actors + 1] = v:get() end)
  end)
  if not ok then log("repair skipped: TMap iteration unsupported (" .. tostring(err) .. ")"); return end
  ok, err = pcall(function() m:Empty() end)
  if not ok then log("repair skipped: TMap:Empty unsupported (" .. tostring(err) .. ")"); return end

  for _, a in ipairs(actors) do
    pcall(function() if a:IsValid() then a:K2_DestroyActor() end end)
  end

  -- 最新のリストで読み込み直す
  local list = {}
  for _, n in ipairs(st.names) do list[#list + 1] = FName(n) end
  ok, err = pcall(function() p:UpdateLoadedWeapons_mc_2(list) end)
  log(("repaired %s: destroyed %d, reload %d weapons -> %s %s")
      :format(charName(p), #actors, #list, tostring(ok), tostring(err or "")))
end

------------------------------------------------------------
-- フック: UpdateLoadedWeapons_mc_2 の実行後
------------------------------------------------------------
local function onUpdateLoaded(self, TargetArray)
  local p = self:get()
  if not p:IsValid() then return end
  local addr = p:GetAddress()
  local st = state[addr]
  if not st then st = { pawn = p, stable = 0 }; state[addr] = st end
  st.pawn = p

  local ok, names = pcall(function() return namesOf(TargetArray:get()) end)
  if ok then st.names = names end

  local queued = false
  pcall(function() queued = p.QueueOfUpdateLoadedWeapons:GetArrayNum() > 0 end)
  if queued then
    st.dirty = true
    st.stable = 0
    log(("list changed during loading: %s -> [%s]"):format(charName(p), table.concat(st.names or {}, ", ")))
  end
end

------------------------------------------------------------
-- 監視: 読み込みがすべて終わったら修復
------------------------------------------------------------
LoopAsync(POLL_MS, function()
  ExecuteInGameThread(function()
    for addr, st in pairs(state) do
      local p = st.pawn
      if not (p and p:IsValid()) then
        state[addr] = nil
      elseif st.dirty then
        local busy = true
        pcall(function()
          busy = p.CurrentlyInLoadingOfAdditionalWeapons or p.QueueOfUpdateLoadedWeapons:GetArrayNum() > 0
        end)
        if busy then
          st.stable = 0
        elseif inAction(p) then
          st.stable = 0
          if not st.waitingLogged then
            st.waitingLogged = true
            log("waiting (in action): " .. charName(p))
          end
        else
          st.stable = st.stable + 1
          if st.stable >= SAFE_TICKS then   -- 読み込み完了・行動なしが続いたら修復
            st.dirty, st.stable, st.waitingLogged = false, 0, false
            repair(st)
          end
        end
      end
    end
  end)
  return false
end)

------------------------------------------------------------
-- フック登録
------------------------------------------------------------
local hooked = false
NotifyOnNewObject(CHEL, function()
  if hooked then return end
  hooked = true
  ExecuteInGameThread(function()
    local ok, err = pcall(RegisterHook, CHEL .. ":UpdateLoadedWeapons_mc_2", onUpdateLoaded)
    log(("hook UpdateLoadedWeapons_mc_2: %s %s"):format(tostring(ok), tostring(err or "")))
  end)

  -- 起動時の機能チェック(1人でも確認できるように、ゲーム開始の少し後に実行。何も変更しない)
  ExecuteWithDelay(10000, function()
    ExecuteInGameThread(function()
      checkArrayParam()
      local p = UEHelpers.GetPlayer()
      if not (p and p:IsValid()) then log("capability: TMap check skipped (no player)"); return end
      local n, okIter = 0, false
      okIter = pcall(function()
        p.LoadedAdditionalWeapons:ForEach(function() n = n + 1 end)
      end)
      local okEmpty = pcall(function() assert(p.LoadedAdditionalWeapons.Empty) end)
      log(("capability: TMap iterate = %s (%d entries), TMap:Empty exists = %s")
          :format(tostring(okIter), n, tostring(okEmpty)))
    end)
  end)
end)

log("loaded v0.2")
