-- array of arrays detailing custom object data.
local custom_object = gm.variable_global_get("custom_object")
-- indexed by custom object id minus 800, then the array within can be indexed following this enum: (courtesy of sarn)
-- (add one to these indices if you're using lua-style indexing, of course)
--
-- enum KEY_CUSTOM_OBJECT {
--     base = 0,
--     obj_depth = 1,
--     obj_sprite = 2,
--     identifier = 3,
--     namespace = 4,
--
--     on_create = 5,
--     on_destroy = 6,
--     on_step = 7,
--     on_draw = 8
-- }

-- wrapping it this way avoids duplicating stuff when hotloading. relies on global vars persisting through hotloads.
if not evilmando_obj_id then
	-- create custom object. this returns a fake object id, which gets resolved by the game's many functions that handle these custom objects
	-- look for _w suffixed object_ functions, and _mod_ prefixed versions of functions like instance_nearest.
	-- instance_create also exists to handle these object ids.
	evilmando_obj_id = gm.object_add_w("kitty", "Evilmando", gm.constants.pEnemyClassic)
end
evilmando_obj_array		= custom_object[evilmando_obj_id - 799] -- custom obj ids start at 800, subtracts by 799 here because of lua 1-based indexing
-- callbacks. these can be intercepted in callback_execute
-- i only use the init hook, but the others are provided for completion/experimentation
evilmando_obj_init		= evilmando_obj_array[6] -- on_create
evilmando_obj_destroy	= evilmando_obj_array[7] -- on_destroy
evilmando_obj_step		= evilmando_obj_array[8] -- on_step
evilmando_obj_draw		= evilmando_obj_array[9] -- on_draw

-- for some reason writing to the array with lua syntax throws an error idk why, so i use array_set here. note this makes the indexing 0-based
-- set "obj_sprite", which is used to show your killer in the defeat screen. this is VERY IMPORTANT for custom enemies as otherwise they will be unable to deal damage to you and cause many errors.
gm.array_set(evilmando_obj_array, 2, gm.constants.sCommandoIdle) -- obj_sprite

local callbacks = {
	-- this init code is directly based on the imp init code that dee provided in the rorr modding disc.
    [evilmando_obj_init] = function(self, other, result, args)
		-- setup sprites.
		-- im not sure if player palettes are intended to be used this way.
		-- evilmando interacts incorrectly with elite effect displays, using a player skin depending on the elite affix
		self.sprite_palette		= gm.constants.sCommandoPalette
		self.sprite_idle		= gm.constants.sCommandoIdle
		self.sprite_walk		= gm.constants.sCommandoWalk
		self.sprite_death		= gm.constants.sCommandoDeath
		self.sprite_jump		= gm.constants.sCommandoJump
		self.sprite_jump_peak	= gm.constants.sCommandoJumpPeak
		self.sprite_fall		= gm.constants.sCommandoFall
		self.sprite_climb		= gm.constants.sCommandoClimb
		--self.sprite_spawn -- animation used when spawning in. not used by evilmando but you should set it on your own custom enemies

		-- setup sfx.
		--self.sound_spawn
		self.sound_hit = gm.constants.wPlayer_TakeDamage
		self.sound_death = gm.constants.wPlayer_TakeHeavyDamage

		-- allows the ai to jump up tiles and climb ropes.
		self.can_jump = true
		self.can_rope = true

		-- VERY IMPORTANT. this sets the collision mask used for the object's physical interactions with everything.
		-- if you fail to set this, the enemy will exhibit very glitchy behaviour and have difficulties moving.
		gm._mod_instance_set_mask(self, gm.constants.sPMask)

		-- setup stats.
		self.pHmax_base = 2.8 -- movement speed. 2.8 is the same as survivors'
		-- this function handles scaling the stats based on the current difficulty scaling.
		-- args are: base damage, health, knockback cap, and value (gold and exp reward)
		self:enemy_stats_init(6, 110, 28, 40)

		-- setup skills.
		-- z/x/c/v_range variables tell the ai the distance it can be from its target to use the skill.
		-- use small values for melee skills, and higher values for ranged skills. a lemurian's z_range is 68.
		--
		-- evilmando uses commando's skills for simplicity.
		-- he doesn't have commando's primary because skills that use strafing or half sprites are broken when used by enemies, so i have opted to instead make his primary Full Metal Jacket
		self.z_range = 1500
		-- actor_skill_set takes the actor instance id, skill slot, and skill id.
		gm.actor_skill_set(self.id, 0, 2) -- 0: primary skill slot, 2: commando FMJ

		self.x_range = 100
		gm.actor_skill_set(self.id, 1, 6) -- 1: secondary skill slot, 6: commando knife
		-- randomise if he gets the roll or slide
		if math.random() > 0.2 then
			self.c_range = 200
			gm.actor_skill_set(self.id, 2, 3) -- 2: utility skill slot, 3: commando roll
		else
			self.c_range = 900
			gm.actor_skill_set(self.id, 2, 7) -- 2: utility skill slot, 7: commando slide
		end
		-- randomise if he gets the suppressive fire or shotgun
		if math.random() > 0.5 then
			self.v_range = 700
			gm.actor_skill_set(self.id, 3, 4) -- 3: special skill slot, 4: commando suppressive fire
		else
			self.v_range = 72
			gm.actor_skill_set(self.id, 3, 8) -- 3: special skill slot, 8: commando shotgun
		end

		-- no idea what this does but you should include it at the end of your enemy init code. some mods depend on it to modify newly spawned actors.
		self:init_actor_late()
    end,
    -- these callbacks aren't used by evilmando, but here they are if you wanna do something with them
    --[evilmando_obj_step] = function(self, other, result, args)
    --end,
    --[evilmando_obj_destroy] = function(self, other, result, args)
    --end,
    --[evilmando_obj_draw] = function(self, other, result, args)
    --end,
}

-- uses the above table to actually run the custom code.
gm.pre_script_hook(gm.constants.callback_execute, function(self, other, result, args)
	if callbacks[args[1].value] then
		callbacks[args[1].value](self, other, result, args)
		return false
	end
end)


local evilmando_setup = false

-- this is where setup is done for evilmando to actually appear and work in-game
gm.post_script_hook(gm.constants.__input_system_tick, function(self, other, result, args)
	if evilmando_setup then return end
	evilmando_setup = true

	-- setup evilmando's monster spawn card
	local monster_cards = gm.variable_global_get("class_monster_card")

	-- find the card, or create it if it doesn't exist. makes hotloading easier
	local evilmando_card = gm.monster_card_find("evilmando")
	if not evilmando_card then
		-- this returns an index into class_monster_card, as usual
		evilmando_card = gm.monster_card_create("kitty", "evilmando")
	end

	-- fetch the actual array
	local evilmando_card_arr = monster_cards[evilmando_card + 1]
	gm.array_set(evilmando_card_arr, 3, 120) -- set director credit cost.
	gm.array_set(evilmando_card_arr, 4, evilmando_obj_id) -- enemy's object id, this is what the director tries to actually spawn
	gm.array_set(evilmando_card_arr, 5, false) -- "is_boss"
	gm.array_set(evilmando_card_arr, 6, false) -- "is_new_enemy", makes this enemy not spawn if new enemies are disabled in lobby config
	gm.array_set(evilmando_card_arr, 8, true) -- "can_be_blighted", true by default. self-explanatory.

	 -- ds_list of indices into class_elite. filled out by default with every common elite type. use gm.ds_list_* functions to modify the list.
	local evilmando_elite_list = gm.array_get(evilmando_card_arr, 7)

	-- loop through every stage in the game, and add evilmando's spawn card to them.
	local stages = gm.variable_global_get("class_stage")
	for i=1, #stages do
		local stage = stages[i]
		local list = stage[5] -- ds_list of spawn cards

		--gm.ds_list_clear(list)

		-- make sure we don't add it if it's already there
		if gm.ds_list_find_index(list, evilmando_card) == -1 then
			gm.ds_list_add(list, evilmando_card)
		end
	end

	-- load evilmando's name and subtitle
	gm.translate_load_file(gm.variable_global_get("_language_map"), _ENV["!plugins_mod_folder_path"].."/english.json")

	print("Evilmando is coming..")
end)

local funny_mode = false

gui.add_to_menu_bar(function()
	funny_mode = ImGui.Checkbox("Funny Mode", funny_mode)
end)

gm.pre_script_hook(gm.constants.director_spawn_monster_card, function(self, other, result, args)
	if not funny_mode then return end
	args[3].value = gm.monster_card_find("evilmando")
end)
