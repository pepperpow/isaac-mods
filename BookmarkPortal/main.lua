-- Code by Pepperpow, twitter/github @pepperpow


-- TODO: Golden Effects are missing.
-- TODO: Cosmic shader?
-- TODO: Rewrite any examples of python like "if variable in table:"
-- TODO: Tie randomness to the current seed (?)

-- Register Mod

local modName = "BookmarkPortal"
local myMod = RegisterMod(modName, 1)
local myGame = Game()
local json = require("json")
-- local isGolden = TrinketType.TRINKET_GOLDEN_FLAG
-- local goldMask = TrinketType.TRINKET_ID_MASK

-- Definitions
-- put ids in a table (i'm sure indexing this way is slow...)
-- name -- pickup type, dropchance
local trinket_info = {
    ['Blank Bookmark'] = {
        Isaac.GetTrinketIdByName('Blank Bookmark'), nil, 10, nil},
    ['Gilded Bookmark'] = {
        Isaac.GetTrinketIdByName('Gilded Bookmark'), -- ID
        PickupVariant.PICKUP_COIN,   20, -- Item dropped when using book, chance
        {RoomType.ROOM_SHOP, RoomType.ROOM_ARCADE, RoomType.ROOM_DICE}}, -- Rooms free to teleport to once cleared
    ['Heart Bookmark'] = {
        Isaac.GetTrinketIdByName('Heart Bookmark'),
        PickupVariant.PICKUP_HEART, 20,
        {RoomType.ROOM_SACRIFICE, RoomType.ROOM_CURSE}},
    ['Charred Bookmark'] = {
        Isaac.GetTrinketIdByName('Charred Bookmark'),
        PickupVariant.PICKUP_BOMB, 10,
        {RoomType.ROOM_BOSS, RoomType.ROOM_MINIBOSS, RoomType.ROOM_CHALLENGE, RoomType.ROOM_BOSSRUSH}},
    ['Dusty Bookmark'] = {
        Isaac.GetTrinketIdByName('Dusty Bookmark'),
        PickupVariant.PICKUP_KEY, 10,
        {RoomType.ROOM_SECRET, RoomType.ROOM_SUPERSECRET, RoomType.ROOM_ULTRASECRET, RoomType.ROOM_BARREN, RoomType.ROOM_ISAACS}},
    ['Shiny Bookmark'] = {
        Isaac.GetTrinketIdByName('Shiny Bookmark'),
        PickupVariant.PICKUP_LIL_BATTERY, 5,
        {RoomType.ROOM_TREASURE, RoomType.ROOM_CHEST, RoomType.ROOM_LIBRARY}},
    ['Cosmic Bookmark'] = {
        Isaac.GetTrinketIdByName('Cosmic Bookmark'),
        nil, 10, {RoomType.ROOM_PLANETARIUM}},
}

local trinket_by_id = { }
for name, info in pairs(trinket_info) do 
    trinket_by_id[info[1]] = name
end
 

local badBookIds = {
    CollectibleType.COLLECTIBLE_HOW_TO_JUMP,
    CollectibleType.COLLECTIBLE_BLOOD_RIGHTS -- I don't think this will change anything or anything with cards, whatever
}

------
-- Save/Loading
-- Make sure to maintain gamestate
------
local GameState = {
    lastGoBackUse = -1,
    booksAcquired = 0,
    queuedItemId = -1,
    allowRerollAll = false,
    startWithCharred = false
}

if ModConfigMenu then

	ModConfigMenu.UpdateCategory(modName, {
		Info = {"Bookmark trinkets for teleporting",}
	})

	-- Settings
	ModConfigMenu.AddSetting(modName, "Bookmarking", 
		{
			Type = ModConfigMenu.OptionType.BOOLEAN,
			CurrentSetting = function()
				return GameState["startWithCharred"]
			end,
			Display = function()
				local onOff = "False"
				if GameState["startWithCharred"] then
					onOff = "True"
				end
				return 'Always Boss Bookmark effect: ' .. onOff
			end,
			OnChange = function(currentBool)
				GameState["startWithCharred"] = currentBool
			end,
			Info = {"Can always teleport from boss/arena rooms"}
		})

	-- Settings
	ModConfigMenu.AddSetting(modName, "Bookmarking", 
		{
			Type = ModConfigMenu.OptionType.BOOLEAN,
			CurrentSetting = function()
				return GameState["allowRerollAll"]
			end,
			Display = function()
				local onOff = "False"
				if GameState["allowRerollAll"] then
					onOff = "True"
				end
				return 'Rerolling non-Cosmic bookmarks: ' .. onOff
			end,
			OnChange = function(currentBool)
				GameState["allowRerollAll"] = currentBool
			end,
			Info = {"If FALSE, only allow blank bookmarks to be rerolled"}
		})
		
end

-- gist Uradamus/shuffle.lua
function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = 1 + (Random() % i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

function myMod:LoadGame(loadgame)
    -- print('Loading ', modName, '...')
    -- print('NewGame...', not loadgame)
    if myMod:HasData() then
        local my_string = myMod:LoadData()
        GameState = json.decode(my_string)
    end
    if not loadgame then
        GameState.lastGoBackUse = -1
        GameState.booksAcquired = 0
        GameState.queuedItemId = -1
    end
end

function myMod:SaveGame()
    -- print('Saving ', modName, '...')
    myMod:SaveData(json.encode(GameState))
    -- print('Save OK')
end

myMod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, myMod.LoadGame)
myMod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, myMod.SaveGame)
myMod:AddCallback(ModCallbacks.MC_POST_GAME_END, function() 
    myMod:LoadGame(true) 
    myMod:SaveGame()
end)

------
-- Main Mod Functions
------
-- Spawn Functions
------
-- Test Function to spawn bookmarks
function myMod:debugSpawnBookmarks()
    local myLevel = myGame:GetLevel()
    local myRoom = myLevel:GetCurrentRoom()
    local me = Isaac.GetPlayer()
    for name,info in pairs(trinket_info) do
        local myId = info[1]
        local myPos = myRoom:FindFreePickupSpawnPosition(me.Position)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, myId, myPos, Vector(0,0), nil)
    end
end

-- Spawn single bookmark
function myMod:spawnBookmark()
    local me = Isaac.GetPlayer()
    local myRoom = myGame:GetLevel():GetCurrentRoom()
    local myPos = myRoom:FindFreePickupSpawnPosition(me.Position)
    local randomId = trinket_info['Blank Bookmark'][1]
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, randomId, myPos, Vector(0,0), nil)
end

-- roll spawning for bookmark
-- on update, if itemqueue is not empty and itemqueue tag is book AND hasn't been acquired, roll chance to queue bookmark
function myMod:rollBookmarkSpawn(player, cache)
    if not player:IsItemQueueEmpty() and not player.QueuedItem.Touched then
        if GameState.queuedItemId == -1 then
            if player.QueuedItem.Item:IsCollectible() and player.QueuedItem.Item:HasTags(ItemConfig.TAG_BOOK) then
                -- print('FRESH BOOK')
                GameState.queuedItemId = player.QueuedItem.Item.ID
            else
                GameState.queuedItemId = -1
            end
        end
    else
        if GameState.queuedItemId ~= -1 then
            if (Random() % 100) < (20 + 20 * GameState.booksAcquired) then 
                GameState.booksAcquired = 0
                myMod:spawnBookmark()
            else
                GameState.booksAcquired = GameState.booksAcquired + 1
            end
        end
        GameState.queuedItemId = -1
    end
end

-- reroll any bookmark when dropped (can't just say in [] because this ain't python)
function myMod:validRerollBookmark(subtype)
    -- print(GameState.allowRerollAll, subtype, name, info)
    local name = trinket_by_id[subtype]
    if name ~= nil then
        if GameState.allowRerollAll then
            return name ~= 'Cosmic Bookmark'
        else
            return name == 'Blank Bookmark'
        end
    else
        return false
    end
end

function myMod:rerollBlankBookmark(pickup)
    if pickup.Touched and PickupVariant.PICKUP_TRINKET then
        if myMod:validRerollBookmark(pickup.SubType) then
            local myRoomDesc = myGame:GetLevel():GetCurrentRoomDesc() 
            -- print(my_target_type)
            for name, info in pairs(trinket_info) do
                tid, my_rooms = info[1], info[4]
                if my_rooms ~= nil then
                    for _,validType in ipairs(my_rooms) do
                        -- print(tid, validType)
                        if myRoomDesc.Data.Type == validType then
                            pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, tid)
                        end
                    end
                end
            end
            pickup.Touched = false
        end
    end
end

------
-- Activated Functions
------
-- Function to activate Go Back
function myMod:checkGoBack(myItem, rng)
    -- If we're usinmg Go Back, teleport back without giving Go Back again
    if myItem == Isaac.GetItemIdByName('Go Back') then
        local myLevel = myGame:GetLevel() 
        local my_last_room = myLevel:GetPreviousRoomIndex()
        myGame:StartRoomTransition(my_last_room, Direction.NO_DIRECTION, RoomTransitionAnim.TELEPORT)
        GameState.lastGoBackUse = myLevel:GetCurrentRoomIndex()
    elseif myItem == Isaac.GetItemIdByName('Go Back (Back) (Back)') then
        local me = Isaac.GetPlayer()
        me:UseActiveItem(Isaac.GetItemIdByName('Glowing Hour Glass'), UseFlag.USE_NOANIM)
    elseif myItem == Isaac.GetItemIdByName('Go To Start') then
        local me = Isaac.GetPlayer()
        me:UseCard(Card.CARD_FOOL)
    elseif myItem == Isaac.GetItemIdByName('Invoke Bookmark') then
        local me = Isaac.GetPlayer()
        local myLevel = myGame:GetLevel() 
        local my_targets = {myLevel:GetStartingRoomIndex()}
        for name, info in pairs(trinket_info) do
            tid, my_rooms = info[1], info[4]
            -- TODO: Don't repeat this code in freeTeleport
            local alwaysCharred = GameState.startWithCharred and name == 'Charred Bookmark'
            if alwaysCharred or (me:HasTrinket(tid) and my_rooms ~= nil) then
                for i = 0, myLevel:GetRooms().Size-1, 1 do
                    local roomdesc = myLevel:GetRooms():Get(i)
                    if roomdesc.Clear then
                        for _,validType in ipairs(my_rooms) do
                            if roomdesc.Data.Type == validType then
                                my_targets[#my_targets+1] = roomdesc.GridIndex
                            end
                        end
                    end
                end
            end
        end
        if #my_targets > 1 then
            -- get our current index in a sorted cycle of rooms
            -- cycle in accordance to grid index
            current_index = myLevel:GetCurrentRoomIndex()
            my_targets[#my_targets+1] = current_index
            table.sort(my_targets, function (a, b)
                return a < b
            end)
            -- don't really care if we put our currentindex twice, just use the last one
            -- then advance by one
            local tbl_index = 0
            for i,num in ipairs(my_targets) do
                if num == current_index then
                    tbl_index = i
                end
            end
            next_room = my_targets[1 + (tbl_index % #my_targets)]
            myGame:StartRoomTransition(next_room, Direction.NO_DIRECTION, RoomTransitionAnim.TELEPORT)
            GameState.lastGoBackUse = myLevel:GetCurrentRoomIndex()
        end
    -- Else, try checking for book buffs from bookmarks
    else
        myMod:buffBooks(myItem, rng)
    end
end

-- Function to activate book spawns
function myMod:buffBooks(myItem, rng)
    -- use caching to prevent excessive checks (?)
    -- Otherwise, check if the book we use is good and if we have a valid trinket(s)
    -- On valid trinket, check its drop type, then roll its drop chance
    local myLevel = myGame:GetLevel()
    local me = Isaac.GetPlayer()
    local myItemDef = Isaac.GetItemConfig():GetCollectible(myItem) 
    local isValidBook = myItemDef:HasTags(ItemConfig.TAG_BOOK)

    for _,id in pairs(badBookIds) do
        isValidBook = isValidBook and myItem ~= id
    end

    local multiplier = 1
    if me:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_BOX) then
        multiplier = multiplier + 1
    end

    if isValidBook then
        for name,info in pairs(trinket_info) do
            tid, my_variant = info[1], info[2]
            if me:HasTrinket(tid) and my_variant ~= nil then
                if (Random() % 100) < info[3]*multiplier then
                    local myRoom = myLevel:GetCurrentRoom()
                    local myPos = myRoom:FindFreePickupSpawnPosition(me.Position)
                    Isaac.Spawn(EntityType.ENTITY_PICKUP, my_variant, 0, myPos, Vector(0,0), nil)
                end
            end
        end
    end
end

-- Function get valid trinket
function myMod:validTrinket(me)
    local hasValidTrinket = false
    for name, info in pairs(trinket_info) do
        hasValidTrinket = hasValidTrinket or me:HasTrinket(info[1]) 
    end
    return hasValidTrinket
end

-- Function to give Go Back item if holding bookmark, otherwise do nothing
function myMod:onTransition()
    local myLevel = myGame:GetLevel()
    local my_last_room = myLevel:GetPreviousRoomIndex()
    local me = Isaac.GetPlayer() -- make this last player on the floor
    if myLevel.LeaveDoor == DoorSlot.NO_DOOR_SLOT and my_last_room ~= GameState.lastGoBackUse then
        hasValidTrinket = myMod:validTrinket(me)
        if hasValidTrinket then
            if me:HasTrinket(trinket_info['Cosmic Bookmark'][1]) or me:HasTrinket(trinket_info['Cosmic Bookmark'][1]) then
                me:SetPocketActiveItem(Isaac.GetItemIdByName('Go Back (Back) (Back)'), ActiveSlot.SLOT_POCKET2, true)
            else
                me:SetPocketActiveItem(Isaac.GetItemIdByName('Go Back'), ActiveSlot.SLOT_POCKET2, true)
            end
        end
    else
        -- Reset go back usage...
        GameState.lastGoBackUse = -1
        myMod:freeTeleport()
    end
end

function myMod:freeTeleport()
    -- if we're in the start room, check for finished rooms of our category
    -- if we're in a category room, give Go To Start
    local myLevel = myGame:GetLevel()
    local myRoom = myLevel:GetCurrentRoom()
    local me = Isaac.GetPlayer() -- make this last player on the floor
    local hasValidTrinket = myMod:validTrinket(me) or GameState.startWithCharred
    if hasValidTrinket and myRoom:IsClear() then
        myRoomData = myLevel:GetCurrentRoomDesc().Data
        sid, variant, roomType = myRoomData.StageID, myRoomData.Variant, myRoomData.Type
        isStart = sid == 0 and variant == 2 -- probably a function for this
        -- print(GameState.startWithCharred)

        for name,info in pairs(trinket_info) do
            tid, my_rooms = info[1], info[4]
            local alwaysCharred = GameState.startWithCharred and name == 'Charred Bookmark'
            if alwaysCharred or (me:HasTrinket(tid) and my_rooms ~= nil) then
                local check_level = False
                for _,validType in ipairs(my_rooms) do
                    check_level = check_level or roomType == validType
                end
                if check_level or isStart then
                    for i = 0, myLevel:GetRooms().Size-1, 1 do
                        local this_room_type = myLevel:GetRooms():Get(i).Data.Type
                        for _,validType in ipairs(my_rooms) do
                            if this_room_type == validType then
                                me:SetPocketActiveItem(Isaac.GetItemIdByName('Invoke Bookmark'), ActiveSlot.SLOT_POCKET2, true)
                                return -- break super early
                            end
                        end
                    end
                end
            end
        end
    end
end

-------
-- debug
-------
function renderInfo()
    me = Isaac.GetPlayer() -- make this last player on the floor
    Isaac.RenderText(GameState.lastGoBackUse, 70, 30, 10, 10, 10, 100)
    Isaac.RenderText(GameState.queuedItemId, 90, 30, 10, 10, 10, 100)
    if myGame:GetLevel():GetCurrentRoom():IsClear() then
        Isaac.RenderText('CLEAR', 50, 40, 10, 10, 10, 100)
    end
    Isaac.RenderText(myGame:GetLevel():GetCurrentRoomDesc().ListIndex, 70, 40, 10, 10, 10, 100)
    Isaac.RenderText(myGame:GetLevel():GetCurrentRoomDesc().Data.Type, 50, 80, 10, 10, 10, 100)
    Isaac.RenderText(myGame:GetLevel():GetCurrentRoomDesc().Data.Subtype, 70, 80, 10, 10, 10, 100)
    Isaac.RenderText(myGame:GetLevel():GetCurrentRoomDesc().Data.StageID, 50, 70, 10, 10, 10, 100)
    Isaac.RenderText(myGame:GetLevel():GetCurrentRoomDesc().Data.Variant, 90, 80, 10, 10, 10, 100)
end

-- myMod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, myMod.debugSpawnBookmarks)
myMod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, myMod.rollBookmarkSpawn)
myMod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, myMod.rerollBlankBookmark)
myMod:AddCallback(ModCallbacks.MC_USE_ITEM, myMod.checkGoBack)
myMod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, myMod.onTransition)
myMod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, myMod.freeTeleport)
-- myMod:AddCallback(ModCallbacks.MC_POST_RENDER, renderInfo)

-- Shade logic removed
-- reference VortexStreet modding of isaac (temp)
-- function myMod:GetShaderParams(shaderName)
-- 	if shaderName == 'VortexStreetXXXBookmark' then
-- 		local params = { Enabled = 1, Time = Isaac.GetFrameCount() }
-- 		return params;
-- 	end
-- end

-- myMod:AddCallback(ModCallbacks.MC_GET_SHADER_PARAMS, myMod.GetShaderParams)