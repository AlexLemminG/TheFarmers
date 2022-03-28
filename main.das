require daslib/media

require tiles
require fio
//require json
require daslib/json_boost

//options debugger            // uncomment for debug in VS Code
//require daslib/debug        // uncomment for debug in VS Code

var dbg_mode : bool = false
var dbg_mode_camera : bool = false
var dbg_spawn_items : bool = false
var draw_grid = false
var dbg_time_scale = 1.0

let game_name = "THE FARMERS"

var time_scale = 1.0
var player_sleep_time_scale_when_everyone_sleeps = 50.0
var player_sleep_time_scale = 10.0
var seconds_per_hour = 3600.0
var hours_per_second = 1.0 / seconds_per_hour
var dbg_camera_scale = -1.0
// tweakable settings

var night_percent = 0.0
var rain_percent = 0.0

//--------------------------------params_begin--------------------------------
let gamedays_per_hour = 18.0
let seconds_per_gameday = seconds_per_hour / gamedays_per_hour
let grass_grow_periods_add = 73 //prime only please
let grass_grow_periods_count = 11 //prime only please
let tree_grow_periods_add = 73 //prime only please
let tree_grow_periods_count = 11 //prime only please
let map_size_default = int2(40,40)
let npcHumansCount = 1
let npcHorsesCount = 2
let hunger_per_hour = gamedays_per_hour * 1.5
let health_loss_from_hunger_per_hour = gamedays_per_hour / 2.0 
let health_gain_from_no_hunger_per_hour = gamedays_per_hour / 3.0 
let health_per_sleep_in_bed = 0.5 / 3.0 //half heart
let hunger_speed_in_bed = 0.5 // twise as slow
let hunger_speed_freezing = 2.0 // twise as fast
let gamedays_to_grow_wool = 1.0
let grass_grow_one_period = seconds_per_gameday / float(grass_grow_periods_count)
let tree_grow_one_period = seconds_per_gameday / float(tree_grow_periods_count) * 3.0
let berries_grow_period = seconds_per_gameday * 5.0
let wheat_grow_period = seconds_per_gameday / 3.0
let initial_day_float = 1.0 + 9.0 / 24.0
let campfire_duration = seconds_per_gameday * 6.0 / 3.0
let good_health_and_no_hunger_to_new_human_duration = seconds_per_gameday / 3.0
let good_health_and_no_hunger_to_new_human_decrease_speed = 0.33
//--------------------------------params_end--------------------------------

var map_size = map_size_default
var map_size_f = float2(float(map_size.x),float(map_size.y))
var tiles : ImageHandle

var grid_ground = new Grid()
var grid_ground_decals = new Grid()
var grid_items = new Grid()
var player : Player?

var tileSizeY = 28.0
var tileSizeX = 18.0

var tileFloorSizeX = 18.0
var tileFloorSizeY = 14.0
var tileFloorHeightZ = 9.0
var tileZToY = tileFloorHeightZ / tileFloorSizeY
var topDownYToY = tileFloorSizeX / tileFloorSizeY

var characters : array<Character?>
var aiCharacters : array<AiCharacter?>

var seed : int4 = int4(0,0,0,0)//TODO move to world_state ? 

var sounds : table<string; SoundHandle>
var empty_sound : SoundHandle

var all_human_names : array<string>
var chest_items : array<TileKind>

def _assert(val : bool)
    if dbg_mode
        assert(val)

enum AiCommandKind
    NONE
    BRING_A_TILE_TO_B_TILE
    DO_DEFAULT_ACTION_ON_A_TILE
    MAKE_WHEAT_STACKS
    PLOW_GROUND
    PICK_A
    PLANT_WHEAT
    STAY_NEAR_A_TILE
    GO_TO_SLEEP
    EAT_SOMETHING
    MAKE_BREAD
    MAKE_FIRE

enum TutorialStateEnum
    NONE
    INITIAL
    WAITING_FOR_DIALOG_FINISH_1
    WAITING_FOR_MSG_BOX_TO_CLOSE_1
    WAITING_FOR_PLAYER_TO_BRING_FLINTSTONE
    WAITING_FOR_FIRST_CAMPFIRE_DIALOG_TO_FINISH
    WAITING_FOR_DIALOG_FINISH_1_5_FINISH
    WAITING_FOR_CHAR_TO_MAKE_CAMPFIRE
    WAITING_FOR_DIALOG_FINISH_2
    WAITING_FOR_MSG_BOX_TO_CLOSE_2
    WAITING_FOR_PLAYER_TO_MAKE_FIRE
    WAITING_FOR_DIALOG_START_3
    WAITING_FOR_DIALOG_FINISH_3
    WAITING_FOR_MSG_BOX_TO_CLOSE_3
    WAITING_FOR_PLAYER_TO_PLANT_WHEAT
    WAITING_FOR_DIALOG_START_4
    WAITING_FOR_DIALOG_FINISH_4
    WAITING_FOR_MSG_BOX_TO_CLOSE_4
    WAITING_FOR_PLAYER_TO_MAKE_BREAD
    FINISHED

struct TutorialState
    state : TutorialStateEnum
    player_planted_wheat : bool
    player_plowed_ground : bool

def update_tutorial_msg()
    _assert(ui_tutorial != null)
    if dialog_accept_pressed()
        ui_tutorial = null

def get_current_goal_str() : string
    if is_tutorial_finished()
        return "GROW A VILLAGE"

    let state = world_state.tutorial_state.state
    if state == TutorialStateEnum WAITING_FOR_PLAYER_TO_BRING_FLINTSTONE
        return "BRING FLINTSTONE TO {to_upper(aiCharacters[0].name)}"

    if state == TutorialStateEnum WAITING_FOR_PLAYER_TO_MAKE_FIRE
        return "START A FIRE"

    if state == TutorialStateEnum WAITING_FOR_PLAYER_TO_PLANT_WHEAT
        if !world_state.tutorial_state.player_plowed_ground
            return "PLOW GROUND"
        else
            return "PLANT WHEAT"

    if state == TutorialStateEnum WAITING_FOR_PLAYER_TO_MAKE_BREAD
        return "MAKE BREAD"

    return ""

def is_tutorial_finished() : bool
    return world_state.tutorial_state.state == TutorialStateEnum FINISHED || world_state.tutorial_state.state == TutorialStateEnum NONE

def update_tutorial(dt : float)
    if is_tutorial_finished()
        camera.scale = 3.0
        return

    let current_state = world_state.tutorial_state
    var npc = aiCharacters[0]
    npc.is_name_known = true
    if current_state.state == TutorialStateEnum INITIAL
        camera.scale = 6.0
        world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_DIALOG_FINISH_1
        var lines : array<string>
        var player_lines : array<string>

        push(lines, "WHAT A GREAT PLACE")
        push(player_lines, "LET'S MAKE A SETTLEMENT HERE")
        
        push(lines, "GREAT IDEA! I'LL BRING SOME WOOD FOR A CAMPFIRE")
        push(player_lines, "I'LL GET A FLINT STONE FROM THE CHEST THEN")

        make_tutorial_dialog(npc, lines, player_lines)
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_DIALOG_FINISH_1
        if current_dialog == null
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_MSG_BOX_TO_CLOSE_1
            npc.command = ai_command_bring_a_to_b(TileKind WOOD, TileKind GREEN_FLAG)
            //WARN player may think that all ai's actions are executed only once
            //TODO bugfix ai can accidentaly drop near flag and ignore do_once
            npc.command.do_once = true
            show_tutorial_msg("GET A FLINT STONE FROM THE CHEST")
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_MSG_BOX_TO_CLOSE_1
        if ui_tutorial == null
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_PLAYER_TO_BRING_FLINTSTONE
        return
        
    camera.scale = max(3.0, camera.scale - dt * 8.0)
    //TODO block ai dialog before end of parts of tutorial

    if current_state.state == TutorialStateEnum WAITING_FOR_PLAYER_TO_BRING_FLINTSTONE
        if length(npc.target_position - player.position) > 7.0
            npc.target_position = player.position + float2(random_float(-3.0, 3.0), random_float(-3.0, 3.0))
        if npc.command.kind != AiCommandKind NONE || player.carry_item != TileKind FLINT_STONE || current_dialog == null
            return
        npc.target_position = player.position
        if length(npc.position - player.position) < 1.0
            var lines : array<string>
            var player_lines : array<string>

            push(lines, "GREAT NOW WE CAN MAKE A CAMPFIRE")
            push(player_lines, "<CONTINUE>")

            current_dialog = null
            make_tutorial_dialog(npc, lines, player_lines)
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_FIRST_CAMPFIRE_DIALOG_TO_FINISH
        return
    
    if current_state.state == TutorialStateEnum WAITING_FOR_FIRST_CAMPFIRE_DIALOG_TO_FINISH
        if current_dialog == null
            var dialog = make_dialog(npc)//TODO special dialog
            dialog.tutorial_make_campfire_only = true
            dialog.tutorial_do_once = true
            dialog.had_greeting = true
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_DIALOG_FINISH_1_5_FINISH
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_DIALOG_FINISH_1_5_FINISH
        if current_dialog == null
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_CHAR_TO_MAKE_CAMPFIRE
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_CHAR_TO_MAKE_CAMPFIRE
        if npc.command.kind != AiCommandKind NONE
            return
        npc.target_position = player.position
        if length(npc.position - player.position) < 1.0
            var lines : array<string>
            var player_lines : array<string>

            push(lines, "THE CAMPFIRE IS READY FOR SOME FIRE")
            push(player_lines, "I'LL USE MY FLINT STONE THEN")

            make_tutorial_dialog(npc, lines, player_lines)
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_DIALOG_FINISH_2
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_DIALOG_FINISH_2
        if current_dialog == null
            show_tutorial_msg("START THE CAMPFIRE")
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_MSG_BOX_TO_CLOSE_2
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_MSG_BOX_TO_CLOSE_2
        if ui_tutorial == null
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_PLAYER_TO_MAKE_FIRE
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_PLAYER_TO_MAKE_FIRE
        var fires_count = items_count_cache[TileKind CAMPFIRE]
        if fires_count != 0
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_DIALOG_START_3
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_DIALOG_START_3
        npc.target_position = player.position
        if length(npc.position - player.position) < 1.0
            var lines : array<string>
            var player_lines : array<string>

            push(lines, "NOW WE HAVE A PLACE TO GATHER IN THE EVENING")
            push(player_lines, "YEAH IT'S SO WARM AROUND IT")
            
            push(lines, "NOW IT'S TIME TO PLANT SOME WHEAT")
            push(player_lines, "I'LL START PLOWING GROUND THEN")
            
            push(lines, "TALK TO ME IF YOU WANT ME TO DO ANYTHING")
            push(player_lines, "<CONTINUE>")
            
            push(lines, "YOU SHOULDN'T TRY TO DO EVERYTHING BY YOURSELF")
            push(player_lines, "SURE THING")

            make_tutorial_dialog(npc, lines, player_lines)
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_DIALOG_FINISH_3
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_DIALOG_FINISH_3
        if current_dialog == null
            show_tutorial_msg("PLANT WHEAT")
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_MSG_BOX_TO_CLOSE_3
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_MSG_BOX_TO_CLOSE_3
        if ui_tutorial == null
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_PLAYER_TO_PLANT_WHEAT
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_PLAYER_TO_PLANT_WHEAT
        if current_state.player_planted_wheat
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_DIALOG_START_4
            pass
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_DIALOG_START_4
        npc.target_position = player.position
        if length(npc.position - player.position) < 1.0
            var lines : array<string>
            var player_lines : array<string>

            push(lines, "DID YOU PLANT THE WHEAT?")
            push(player_lines, "YES, IT SHOULD BE FULLY GROWN BY TOMORROW")
            
            push(lines, "CAN'T WAIT TO MAKE SOME BREAD OUT OF IT")
            push(player_lines, "I NEED TO CHECK MY CRAFTBOOK FOR THE RECIPE")

            make_tutorial_dialog(npc, lines, player_lines)
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_DIALOG_FINISH_4
        return
    
    if current_state.state == TutorialStateEnum WAITING_FOR_DIALOG_FINISH_4
        if current_dialog == null
            var msgs : array<string>
            push(msgs, "            MAKE A BREAD")
            push(msgs, "(CHECK THE CRAFTBOOK IN THE PAUSE MENU)")
            show_tutorial_msgs(msgs)
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_MSG_BOX_TO_CLOSE_4
        return

    if current_state.state == TutorialStateEnum WAITING_FOR_MSG_BOX_TO_CLOSE_4
        if ui_tutorial == null
            world_state.tutorial_state.state = TutorialStateEnum WAITING_FOR_PLAYER_TO_MAKE_BREAD
        return
    if current_state.state == TutorialStateEnum WAITING_FOR_PLAYER_TO_MAKE_BREAD
        var bread_count = items_count_cache[TileKind BREAD]
        if bread_count != 0
            var msgs : array<string>
            push(msgs, "THIS IS THE END OF THE TUTORIAL")
            push(msgs, " ")
            push(msgs, "YOUR GOAL NOW IS TO")
            push(msgs, "GROW THE SETTLEMENT AS BIG AS POSSIBLE")
            push(msgs, " ")
            push(msgs, "NEW PEOPLE WILL COME TO THE VILLAGE")
            push(msgs, "IF EVERYONE IS HEALTHY AND WELL FED")
            show_tutorial_msgs(msgs)

            world_state.good_health_and_no_hunger_duration = 0.0
            spawn_new_villager()
            world_state.tutorial_state.state = TutorialStateEnum FINISHED
        return
    
struct WorldState
    next_free_human_name : int = 0
    next_chest_item : int = 0
    day_float : float = initial_day_float
    wheat_grow_timer : float = 0.0
    wheat_grow_timer_watered : float = wheat_grow_period / 2.0
    grass_grow_timer : float = 0.0
    grass_grow_idx : int = 0
    tree_grow_timer : float = 0.0
    tree_grow_idx : int = 0
    max_population : int = 0
    good_health_and_no_hunger_duration : float = 0.0
    tutorial_state : TutorialState

def get_realtime_since_world_started() : float
    return (world_state.day_float - initial_day_float) * seconds_per_gameday

var world_state = WorldState()

var rain_sound_original : SoundHandle
var rain_sound : SoundHandle
var prev_rain_volume = -1.0
def update_rain_loop()
    var volume = rain_percent
    volume = 1.0
    if rain_sound_original.duration == 0.0
        rain_sound_original <- create_managed_sound("sounds/RAIN_LOOP.wav")
        var data : array<float2>
        get_sound_data(rain_sound_original, data)
        resize(data, rain_sound_original.samples)
        rain_sound <- create_managed_sound(44100, data)
        rain_sound |> play_sound_loop(0.1)

    volume = rain_percent
    if prev_rain_volume == volume || abs(prev_rain_volume - volume) < 0.01 && volume > 0.0 
        return
    prev_rain_volume = volume
    var data : array<float2>
    resize(data, rain_sound_original.samples)
    get_sound_data(rain_sound_original, data)
    for s in data
        s *= volume
    set_sound_data(rain_sound, data)

var ambient_sound : SoundHandle
def update_ambient_loop()
    if ambient_sound.duration == 0.0
        ambient_sound <- create_managed_sound("sounds/AMBIENT.mp3")
        ambient_sound |> play_sound_loop(0.02)

def play_sound(str : string; pos : float2; volumeMult : float = 1.0; pitchMult : float = 1.0)
    var snd = sounds[str]
    if snd.duration == 0.0
        try
            snd <- create_managed_sound("sounds/{str}.wav")
        recover
            pass
        sounds[str] = snd

    let dist_multi = 0.5
    let delta_pos = pos - player.position
    var volume = volumeMult / max(1.0, length_sq(delta_pos * dist_multi))
    var pitch = pitchMult
    var pan = clamp(-delta_pos.x * 0.5, -0.5, 0.5)
    snd |> play_sound(volume, pitch, pan)

def random_float(min : float; max : float) : float
    return random_float(seed) * (max-min) + min

def play_sound(kind : SoundKind; pos : int2)
    play_sound(kind, float2(pos))

def play_sound(kind : SoundKind; pos : float2)
    var str = "{kind}"
    var volume = 1.0
    var pitch = 1.0
    if kind == SoundKind FOOTSTEP
        str = "FOOTSTEP ({(random_int(seed) % 8) + 1})"
        volume = 0.2
    elif kind == SoundKind CHOP
        pitch = random_float(0.9, 1.1)
    elif kind == SoundKind FIRE_PUT_OUT
        volume = 0.3
    elif kind == SoundKind PICK || kind == SoundKind DROP
        volume = 0.3
        pitch = random_float(1.5, 1.6)
    elif kind == SoundKind GENERIC_ACTION
        volume = 0.3
        pitch = random_float(0.7, 0.75)
    elif kind == SoundKind WHOOSH
        volume = 0.3
        pitch = random_float(0.7, 0.75)
    elif kind == SoundKind EAT_BREAD
        volume = 0.5
        pitch = random_float(0.9, 1.1)
    elif kind == SoundKind DROP_WOOD
        volume = 0.3
        pitch = random_float(0.9, 1.1)
    elif kind == SoundKind PUT_WOOD_TO_STOVE
        volume = 0.3
        pitch = random_float(0.9, 1.1)
    elif kind == SoundKind SHEAR_SHEEP
        volume = 0.3
        pitch = random_float(0.9, 1.1)
    elif kind == SoundKind EAT_GRASS
        volume = 0.4
        str = "{SoundKind EAT_APPLE}"
        pitch = random_float(1.9, 2.1)
    elif kind == SoundKind UI_BLOCKED || kind == SoundKind UI_MOVE || kind == SoundKind UI_CLICK
        volume = 0.2

    play_sound(str, pos, volume, pitch)

def get_pick_sound(kind : TileKind) : SoundKind
    return SoundKind PICK

def get_drop_sound(kind : TileKind) : SoundKind
    if kind == TileKind WOOD || kind == TileKind FENCE
        return SoundKind DROP_WOOD
    return SoundKind DROP



let dbg_pathfinding = false

struct SavedGrid
    height : int
    width : int
    tiles : array<TileKind>
    tiles_saved_float : array<float>

struct SavedCharacter
    position : float2
    kind : TileKind
    carry_item : TileKind
    ai_command : AiCommand
    name : string
    is_name_known : bool
    leash : LeashKind
    leash_to_ground_pos : float2
    is_wearing_cloth : bool
    saved_float : float
    hunger : float
    health : float
    anim : Anim

def save_character(c : Character?) : JsonValue?
    var ch : SavedCharacter
    ch.position = c.position
    ch.kind = c.kind
    ch.carry_item = c.carry_item
    ch.ai_command = c.command
    ch.name = c.name
    ch.is_name_known = c.is_name_known
    ch.is_wearing_cloth = c.is_wearing_cloth
    ch.saved_float = c.saved_float
    ch.hunger = c.hunger
    ch.health = c.health
    ch.anim = c.anim
    ch.leash = c.leash
    ch.leash_to_ground_pos = c.leash_to_ground_pos
    return JV(ch)

def load_ai_command(var json : JsonValue?;var c : AiCommand)
    var str_kind = (json as _object)["kind"] as _string
    c.kind = str_to_ai_command_kind[str_kind]
    c.a_pos = load_float2((json as _object)["a_pos"])
    c.b_pos = load_float2((json as _object)["b_pos"])
    c.a_tile = str_to_tile_kind[(json as _object)["a_tile"] as _string]
    c.b_tile = str_to_tile_kind[(json as _object)["b_tile"] as _string]
    c.do_once = (json as _object)["do_once"] as _bool

def load_float2(var json : JsonValue?) : float2
    var p : float2
    p.x = float((json as _object)["x"] as _number)
    p.y = float((json as _object)["y"] as _number)
    return p

enum LeashKind
    NONE
    TO_GROUND
    TO_PLAYER

def load_character(var json : JsonValue?;var g : Character?)
    var j_obj <- (json as _object)

    g.position = load_float2(j_obj["position"])
    var str = j_obj["kind"] as _string
    g.kind = str_to_tile_kind[str]
    str = j_obj["carry_item"] as _string
    g.carry_item = str_to_tile_kind[str]
    g.name = j_obj["name"] as _string
    g.is_name_known = j_obj["is_name_known"] as _bool
    if key_exists(j_obj, "is_wearing_cloth")
        g.is_wearing_cloth = j_obj["is_wearing_cloth"] as _bool
    g.saved_float = float(j_obj["saved_float"] as _number)
    g.hunger = float(j_obj["hunger"] as _number)
    g.health = float(j_obj["health"] as _number)
    load_ai_command(j_obj["ai_command"], g.command)
    if key_exists(j_obj, "anim")
        g.anim = from_JV(j_obj["anim"], type<Anim>)
    if key_exists(j_obj, "leash")
        g.leash = from_JV(j_obj["leash"], type<LeashKind>)
        if g.leash == LeashKind TO_PLAYER
            g.leash = LeashKind NONE
    if key_exists(j_obj, "leash_to_ground_pos")
        g.leash_to_ground_pos = load_float2(j_obj["leash_to_ground_pos"])
    pass


def generate_default_ground_grid(width : int; height : int) : Grid?
    var grid = new Grid()
    grid.width = width
    grid.height = height

    for x in range(0, width)
        for y in range(0, height)
            var tile = Tile()
            tile.position = int2(x,y)
            tile.kind = TileKind SOIL  
            tile.z = float(random_int(seed) % int(tileFloorHeightZ) / 3) / tileFloorHeightZ
            var tint = lerp(random_float(seed), 1.0, 0.8)
            //tint = 1.0
            //tile.z = 0.0
            tile.color = make_color(tint)

            push_clone(grid.tiles, tile)

    return grid

def generate_default_grid_decals(width : int; height : int; var ground_grid : Grid?) : Grid?
    var grid = new Grid()
    grid.width = width
    grid.height = height
    for x in range(0, width)
        for y in range(0, height)
            var tile = Tile()
            tile.position = int2(x,y)
            tile.kind = TileKind NONE  
            tile.color = ground_grid->getTileInt(tile.position).color
            tile.z = ground_grid->getTileInt(tile.position).z
            push_clone(grid.tiles, tile)
    return grid

def generate_default_grid(width : int; height : int; var ground_grid : Grid?) : Grid?
    var grid = new Grid()
    grid.width = width
    grid.height = height
    for x in range(0, width)
        for y in range(0, height)
            var tile = Tile()
            tile.position = int2(x,y)
            tile.kind = TileKind NONE  
            tile.z = ground_grid->getTileInt(tile.position).z
            push_clone(grid.tiles, tile)
    return grid

def save_grid(g : Grid?) : JsonValue?
    var grid : SavedGrid
    grid.height = g.height
    grid.width = g.width
    for k in g.tiles
        if k.anim.kind == AnimKind PICK
            push(grid.tiles, TileKind NONE)
        else
            push(grid.tiles, k.kind)
    for k in g.tiles
        push(grid.tiles_saved_float, k.saved_float)
    return JV(grid)

var str_to_tile_kind : table<string; TileKind>
var str_to_ai_command_kind : table<string; AiCommandKind>
def load_grid(var json : JsonValue?; is_ground : bool; is_decals : bool) : Grid?
    var grid : SavedGrid
    //var h : Grid?
    var heightF <- (json as _object)["height"] as _number
    grid.height = roundi(heightF)
    var widthF <- (json as _object)["width"] as _number
    grid.width = roundi(widthF)
    
    var tilesJson <- (json as _object)["tiles"] as _array
    for t in tilesJson
        var s <- t as _string
        push(grid.tiles, str_to_tile_kind[s])
    
    var i = 0
    var tileFloatsJson <- (json as _object)["tiles_saved_float"] as _array
    for t in tileFloatsJson
        push(grid.tiles_saved_float, float(t as _number))

    var g : Grid?
    if is_ground
        g = generate_default_ground_grid(grid.height, grid.width)
        map_size.x = g.width
        map_size.y = g.height
        map_size_f = float2(float(map_size.x),float(map_size.y))
    else
        if is_decals
            g = generate_default_grid_decals(grid.height, grid.width, grid_ground)
        else
            g = generate_default_grid(grid.height, grid.width, grid_ground)
    
    for idx in range(length(grid.tiles))
        g.tiles[idx].kind = grid.tiles[idx]
        g.tiles[idx].saved_float = grid.tiles_saved_float[idx]

    return g

def load_world_state(var json : JsonValue?) : WorldState
    var state = from_JV(json, type<WorldState>)
    
    return state

def save_world_state(state : WorldState) : JsonValue?
    return JV(state)

def has_file(name : string):bool
    var file = fopen(name, "r")
    if file == null
        return false
    fclose(file)
    return true

def get_save_slot_file(slot : int) : string
    return "save_{slot}.sav"

def has_save(slot : int) : bool
    return has_file(get_save_slot_file(slot))

def save(slot : int)
    _assert(-1 <= slot && slot <= save_slots_count)
    var file = fopen(get_save_slot_file(slot), "w")
    if file == null
        return

    var json : JsonValue?
    var grid : SavedGrid
    grid.height = grid_ground.height
    grid.width = grid_ground.width

    for k in grid_ground.tiles
        push(grid.tiles, k.kind)
    
    var t : table<string; JsonValue?>
    json = JV(t)
    (json as _object)["ground"] = save_grid(grid_ground)
    (json as _object)["items"] = save_grid(grid_items)
    (json as _object)["decals"] = save_grid(grid_ground_decals)
    var arr : array<JsonValue?>
    (json as _object)["characters"] = JV(arr)   
    for character in characters
        push((json as _object)["characters"] as _array, save_character(character))

    (json as _object)["world_state"] = save_world_state(world_state)

    fwrite(file, "{write_json(json)}")

    fclose(file)
    game_log("game saved")

var dbg_msg : array<string>

def log(str : string)
    push(dbg_msg, str)
    if length(dbg_msg) > 10
        erase(dbg_msg, 0)

struct GameMsg
    str : string
    time_after_start : float

var game_msg : array<GameMsg>
def game_log(str : string)
    var msg : GameMsg
    msg.str = str
    msg.time_after_start = get_time_after_start()
    push(game_msg, msg)

def load(slot : int)
    var file = fopen(get_save_slot_file(slot), "r")
    if file == null
        return

    clear(game_msg)
    //clear_game method
    current_dialog = null
    ui_tutorial = null

    seed = int4(0,0,0,0)

    clear(str_to_tile_kind)
    for e in each_enum(type<TileKind>)
        str_to_tile_kind["{e}"] =  e
        pass

    clear(str_to_ai_command_kind)
    for e in each_enum(type<AiCommandKind>)
        str_to_ai_command_kind["{e}"] =  e
        pass
    
    var strJson : string
    var c : __context
    while !feof(file)
        strJson += fgets(file) 
    var errorStr : string
    var json = read_json(strJson, errorStr)

    grid_ground = load_grid((json as _object)["ground"], true, false)
    grid_items = load_grid((json as _object)["items"], false, false)
    grid_ground_decals = load_grid((json as _object)["decals"], false, true)

    var isFirst = true
    clear(characters)
    clear(aiCharacters)
    for js in (json as _object)["characters"] as _array
        var character : Character?
        if isFirst
            player = new Player()
            push(characters, player)
            character = player
            isFirst = false
            load_character(js, character)
        else
            var aiChar = new AiCharacter()
            push(characters, aiChar)
            push(aiCharacters, aiChar)
            character = aiChar
            load_character(js, character)
            
            aiChar.target_position = aiChar.position

    world_state = load_world_state((json as _object)["world_state"])

    fclose(file)
    game_log("game loaded")

def color_to_float4_fix(c: uint): float4
    let b = c & 0xFF
    let g = (c >> 8u) & 0xFF
    let r = (c >> 16u) & 0xFF
    let a = (c >> 24u) & 0xFF
    return float4(r, g, b, a) / 255.0

def color_to_float3_fix(c: uint): float3
    let b = c & 0xFF
    let g = (c >> 8u) & 0xFF
    let r = (c >> 16u) & 0xFF
    return float3(r, g, b) / 255.0

def lerp_colors_fix(a, b: uint; t: float): uint
    let f1 = color_to_float4_fix(a)
    let f2 = color_to_float4_fix(b)
    return make_color(lerp(f1, f2, t))


class Character
    fixed_seed : int4 = int4(random_int(seed), random_int(seed), random_int(seed), random_int(seed))
    command : AiCommand
    saved_float : float
    position : float2
    velocity : float2
    name : string
    is_name_known : bool
    is_wearing_cloth : bool
    is_highlighted : bool
    z : float
    speed : float
    kind : TileKind
    health : float = 1.0
    hunger : float = 0.0
    isRunning : bool = false
    mirrorX : bool
    leash : LeashKind
    leash_to_ground_pos : float2
    color : uint = 0xFFFFFFFF
    anim : Anim
    carry_item : TileKind = TileKind NONE
    next_footstep_time : float


def GetPreferedSpeed(character : Character) : float
    if character.kind == TileKind SHEEP || character.kind == TileKind SHEEP_SHEARED
        return 0.2
    elif character.kind == TileKind HORSE
        return 2.0
    else
        return GetMaxSpeed(character) / 2.0

def GetMaxSpeed(character : Character) : float
    if character.kind == TileKind HORSE || character.kind == TileKind HUMAN_ON_HORSE
        return 4.0
    elif character.kind == TileKind SHEEP || character.kind == TileKind SHEEP_SHEARED
        return 2.0
    else
        return 2.0

class Player : Character
    speed2 : float



struct AiCommand
    kind : AiCommandKind
    a_tile : TileKind
    b_tile : TileKind
    a_pos : float2
    b_pos : float2
    do_once : bool

def is_human(kind : TileKind) : bool
    return kind == TileKind HUMAN || kind == TileKind CHILD_A || kind == TileKind CHILD_B || kind == TileKind HUMAN_ON_HORSE

def get_current_hour_float() : float
    var time_float = world_state.day_float - float(trunci(world_state.day_float))
    return time_float * 24.0

def get_current_day() : int
    return int(world_state.day_float)

def get_current_hour() : int
    return int(get_current_hour_float())

def is_evening_time() : bool
    return get_current_hour_float() >= 19.0 && get_current_hour_float() < 22.0

def is_night_time(hours_offset = 0.0) : bool
    let hours = (get_current_hour_float() + hours_offset) % 24.0
    return hours >= 22.0 || hours < 6.0

def is_morning_time() : bool
    return get_current_hour_float() >= 6.0 && get_current_hour_float() < 10.0

def is_day_time() : bool
    return get_current_hour_float() >= 10.0 && get_current_hour_float() < 19.0

def is_player_must_sleep_time() : bool
    return get_current_hour_float() >= 23.0 || get_current_hour_float() < 6.0

def is_sleep_action_on_bed() : bool
    return is_night_time()

def angle_radius_to_point(angle_rad : float; radius : float)
    return float2(sin(angle_rad), cos(angle_rad)) * radius

def any_eatable_on_level() : bool
    if items_count_cache[TileKind BREAD_1] > 0
        return true
    if items_count_cache[TileKind BREAD_2] > 0
        return true
    if items_count_cache[TileKind BREAD_3] > 0
        return true
    if items_count_cache[TileKind BREAD_4] > 0
        return true
    if items_count_cache[TileKind BREAD_5] > 0
        return true
    if items_count_cache[TileKind BREAD_6] > 0
        return true
    if items_count_cache[TileKind BUSH_WITH_BERRIES] > 0
        return true
    return false

def is_eatable(kind : TileKind) : bool
    return is_bread(kind) || kind == TileKind BUSH_WITH_BERRIES

class AiCharacter : Character
    target_position : float2
    dbg_str : string
    idle_time_left : float

    def fixed_random_int4() : int4
        return fixed_seed

    def fixed_random_float(idx : int = 0) : float
        var s = fixed_random_int4()
        for i in range(idx)
            random_float(s) 
        return random_float(s) 

    def get_current_commands_list() : array<AiCommand>
        var result : array<AiCommand>
        var is_baker = command.kind == AiCommandKind MAKE_BREAD || command.kind == AiCommandKind BRING_A_TILE_TO_B_TILE && command.a_tile == TileKind FLOUR && command.b_tile == TileKind STOVE_WITH_COAL_FIRED
        if is_baker
            push(result, command)
        if is_night_time(fixed_random_float())
            var cmd : AiCommand
            cmd.kind = AiCommandKind GO_TO_SLEEP
            push(result, cmd)
        if hunger > 1.5 / 3.0
            var cmd : AiCommand
            cmd.kind = AiCommandKind EAT_SOMETHING
            push(result, cmd)
        var will_be_freezing = will_be_freezing_without_fire(self)
        if will_be_freezing && !is_wearing_cloth && is_human(kind)
            var cmd : AiCommand
            cmd.a_tile = TileKind CLOTH
            cmd.kind = AiCommandKind DO_DEFAULT_ACTION_ON_A_TILE
            push(result, cmd)
        if is_evening_time() && is_human(kind) || will_be_freezing
            var cmd : AiCommand
            cmd.a_tile = TileKind CAMPFIRE
            cmd.kind = AiCommandKind STAY_NEAR_A_TILE
            push(result, cmd)
        if command.kind != AiCommandKind NONE && !is_baker
            push(result, command)

        return <- result

    def Think(dt : float)
        dbg_str = "" 

        if anim.kind == AnimKind SLEEP || anim.kind == AnimKind SLEEP_IN_BED && !is_night_time(fixed_random_float())
            set_character_animation(self, AnimKind NONE)

        var any_command_exec = false
        for cmd in get_current_commands_list()
            if process_command(dt, cmd)
                dbg_ai("{cmd} success")
                any_command_exec = true
                break
            dbg_ai("{cmd} failed")

        if !any_command_exec
            dbg_ai("no commands to exec found")
            if length(target_position - position) < 1.0
                target_position = random_wander_pos(position)
                return
            while !is_walkable_for_a_star(grid_ground->getIntPos(target_position), is_human(kind))
                target_position = random_wander_pos(position)

        var preferedSpeed = GetPreferedSpeed(self)
        if leash != LeashKind NONE
            var leash_length = 1.0
            var leash_to_ground_distance = 2.0
            if leash == LeashKind TO_PLAYER
                if is_human(kind)
                    var delta = position - player.position
                    if length(delta) < 0.01
                        delta = float2(0.0,1.0)
                    delta = normalize(delta) / 3.0 * 2.0
                    target_position = player.position + delta
                else
                    var delta = player.position - position
                    if length(delta) > 1.0
                        target_position = position + clampLength(delta, length(delta) - leash_length)
                    preferedSpeed = min(length(delta), GetMaxSpeed(self))
            else
                var delta = target_position - leash_to_ground_pos
                var delta_l = length(delta)
                if delta_l > leash_to_ground_distance
                    target_position = leash_to_ground_pos + delta / delta_l * leash_to_ground_distance
                preferedSpeed /= 4.0

        var immediateTargetPos : float2
        immediateTargetPos = target_position
        if !is_walkable_for_a_star(grid_ground->getIntPos(position), is_human(kind)) && leash != LeashKind TO_PLAYER
            immediateTargetPos = float2(get_nearest_walkable(position, is_human(kind)))
        elif length(target_position - position) > 1.0
            var path : array<int2>
            path <- a_star(grid_ground->getIntPos(position), grid_ground->getIntPos(target_position), is_human(kind))
            if length(path) > 1
                //TODO relax path a little to remove zig-zags
                immediateTargetPos = float2(path[1]) + (grid_items->getTileInt(path[1]).kind == TileKind NONE ? float2(0.0) : float2(0.15, 0.35))
            elif leash != LeashKind TO_PLAYER
                immediateTargetPos = target_position
                if command.kind == AiCommandKind NONE
                    target_position = random_wander_pos(position)
        dbg_ai("moving to {target_position} (immediate {immediateTargetPos})") 
        velocity = lerp(velocity, clampLength((immediateTargetPos - position)*2.0, 1.f) * preferedSpeed, 3.0 * dt)
        
    def process_command(dt : float; cmd : AiCommand) : bool
        if idle_time_left > 0.0
            idle_time_left -= dt
            return true
        if cmd.kind == AiCommandKind MAKE_WHEAT_STACKS
            if item_is(carry_item, TileKind WHEAT_COLLECTED_6)
                var nearest_empty_pos = find_nearest_empty_pos(grid_items->getIntPos(position))
                if nearest_empty_pos == invalid_tile_pos
                    return false
                drop_carry_item(self, nearest_empty_pos)
                return true
            if _process_command(ai_command_pick_a(TileKind WHEAT_COLLECTED_NOT_6))
                return true
            return false
        elif cmd.kind == AiCommandKind PLANT_WHEAT
            if !item_is(carry_item, TileKind WHEAT_COLLECTED_ANY)
                if _process_command(ai_command_pick_a(TileKind WHEAT_COLLECTED_ANY))
                    return true
                return false
            else
                //TODO use pos and do_default command
                return _process_command(cmd)

        var result = _process_command(cmd)
        if !result && cmd.kind == AiCommandKind BRING_A_TILE_TO_B_TILE && is_flag(cmd.b_tile) && cmd.a_tile == TileKind WHEAT_STACK
            result = process_command(dt, ai_command_make_wheat_stacks())
        return result

    def dbg_ai(msg : string)
        dbg_str += "{msg}\n"


    def ai_util_drop_current_item_if_any() : bool
        if carry_item != TileKind NONE
            var nearest_empty_pos = find_nearest_empty_pos(grid_items->getIntPos(position))
            if nearest_empty_pos == invalid_tile_pos
                return false
            drop_carry_item(self, nearest_empty_pos)
        return true

    //true if in process of doing command
    //false if cant do it
    def _process_command(cmd : AiCommand) : bool
        dbg_ai("checking {cmd}")
        let intPos = grid_items->getIntPos(position)
        if cmd.kind == AiCommandKind BRING_A_TILE_TO_B_TILE
            var is_drop_command = is_flag(cmd.b_tile)
            var drop_excluding_half_size : int
            var drop_flag_pos : int2

            var nearest_tile_b_pos = find_nearest_item(cmd.b_tile, intPos)
            if nearest_tile_b_pos == invalid_tile_pos
                dbg_ai("no {cmd.b_tile} found")
                return false

            if is_drop_command
                drop_flag_pos = nearest_tile_b_pos
                nearest_tile_b_pos = find_nearest_empty_pos(nearest_tile_b_pos)
                if nearest_tile_b_pos == invalid_tile_pos
                    dbg_ai("no empty tiles near {cmd.b_tile} found")
                    return false
                var max_distance_to_flag = 3
                if max(abs(nearest_tile_b_pos.x - drop_flag_pos.x), abs(nearest_tile_b_pos.y - drop_flag_pos.y)) > max_distance_to_flag
                    dbg_ai("empty tiles near {cmd.b_tile} are too far from it")
                    return false
                var delta = abs(nearest_tile_b_pos - drop_flag_pos)
                drop_excluding_half_size = max(delta.x, delta.y)
                
            if !item_is(carry_item, cmd.a_tile)
                var nearest_tile_a_pos :int2 
                if is_drop_command
                    nearest_tile_a_pos = find_nearest_item_excluding_rect(cmd.a_tile, intPos, drop_excluding_half_size, drop_flag_pos)
                else
                    nearest_tile_a_pos = find_nearest_item(cmd.a_tile, intPos)

                if nearest_tile_a_pos == invalid_tile_pos
                    dbg_ai("no {cmd.a_tile} found")
                    return false
                if length(float2(nearest_tile_a_pos - intPos)) > 0.8
                    target_position = float2(nearest_tile_a_pos)
                    dbg_ai("moving to {cmd.a_tile} at {nearest_tile_a_pos}")
                    return true
                pick(self, grid_items->getTileInt(nearest_tile_a_pos))
                idle_time_left = 0.5
                return true

            if length(float2(nearest_tile_b_pos - intPos)) > 0.8
                dbg_ai("moving to {cmd.b_tile} at {nearest_tile_b_pos}")
                target_position = float2(nearest_tile_b_pos)
                return true

            if is_drop_command
                if cmd.do_once
                    //TODO less hacky
                    command.kind = AiCommandKind NONE
                drop_carry_item(self, nearest_tile_b_pos)
            else
                var tile = grid_items->getTileInt(nearest_tile_b_pos)
                if !can_craft(self, tile)
                    _assert(false)
                    return false
                craft(self, tile)
                if cmd.do_once
                    //TODO less hacky
                    command.kind = AiCommandKind NONE
                //HACK
                if carry_item == TileKind BREAD_6 
                    ai_util_drop_current_item_if_any()
                return true
        elif cmd.kind == AiCommandKind PICK_A
            if carry_item != cmd.a_tile || is_collected_wheat(cmd.a_tile)
                let nearest_tile_a_pos = find_nearest_item(cmd.a_tile, intPos)
                if nearest_tile_a_pos == invalid_tile_pos
                    dbg_ai("no {cmd.a_tile} found")
                    return false
                if length(float2(nearest_tile_a_pos - intPos)) > 0.8
                    target_position = float2(nearest_tile_a_pos)
                    return true
                pick(self, grid_items->getTileInt(nearest_tile_a_pos))
                return true
        elif cmd.kind == AiCommandKind DO_DEFAULT_ACTION_ON_A_TILE
            let nearest_tile_a_pos = find_nearest_item(cmd.a_tile, intPos)
            if nearest_tile_a_pos == invalid_tile_pos
                dbg_ai("no {cmd.a_tile} found")
                return false

            if !ai_util_drop_current_item_if_any()
                return false

            if length(float2(nearest_tile_a_pos - intPos)) > 0.8
                target_position = float2(nearest_tile_a_pos)
                dbg_ai("setting target_position to nearest {cmd.a_tile} at {nearest_tile_a_pos}")
                return true
            var hint : AltActionCallHint
            hint.is_sleep = true
            var res = do_alt_action(self, nearest_tile_a_pos, hint)
            if res.is_valid
                idle_time_left = 0.5
                dbg_ai("doing alt_action with {cmd.a_tile} at {nearest_tile_a_pos}")
            else
                dbg_ai("failed to do alt_action with {cmd.a_tile} at {nearest_tile_a_pos}")
                log("failed to do alt_action with {cmd.a_tile} at {nearest_tile_a_pos}")
                //_assert(false)
                return false
            if cmd.do_once
                //TODO less hacky
                command.kind = AiCommandKind NONE
            return true
        elif cmd.kind == AiCommandKind PLOW_GROUND
            var nearest_non_plowed = find_nearest_non_plowed_ground(grid_items->getIntPos(position))
            if nearest_non_plowed == invalid_tile_pos
                dbg_ai("no non-plowed soil found")
                return false
            if length(float2(nearest_non_plowed - intPos)) > 0.8
                target_position = float2(nearest_non_plowed)
                dbg_ai("setting target_position to nearest non-plowed soil at {nearest_non_plowed}")
                return true
            idle_time_left = 0.5
            var res = do_alt_action(self, nearest_non_plowed)
        elif cmd.kind == AiCommandKind PLANT_WHEAT
            var nearest_plowed = find_nearest_plowed_ground(grid_items->getIntPos(position))
            if nearest_plowed == invalid_tile_pos
                dbg_ai("no plowed soil found")
                return false
            if length(float2(nearest_plowed - intPos)) > 0.8
                target_position = float2(nearest_plowed)
                dbg_ai("setting target_position to nearest plowed soil at {nearest_plowed}")
                return true
            idle_time_left = 0.5
            var res = do_alt_action(self, nearest_plowed)
        elif cmd.kind == AiCommandKind STAY_NEAR_A_TILE
            var nearest_tile = find_nearest_item(cmd.a_tile, grid_items->getIntPos(position), 20)
            if nearest_tile == invalid_tile_pos
                dbg_ai("no {cmd.a_tile} found")
                return false
            var delta_pos = angle_radius_to_point(fixed_random_float(0) * PI * 2.0, lerp(0.4, 0.6, fixed_random_float(1)))
            var nearest_tile_float = float2(nearest_tile) + delta_pos
            if length(nearest_tile_float - position) > 0.2
                target_position = nearest_tile_float
                dbg_ai("setting target_position to nearest {cmd.a_tile} at {nearest_tile}")
                return true
            return true //continue staying
        elif cmd.kind == AiCommandKind GO_TO_SLEEP
            if anim.kind == AnimKind SLEEP_IN_BED || anim.kind == AnimKind SLEEP
                return true 
            var is_going_to_bed = false
            if is_human(kind)
                var go_to_bed_result = _process_command(ai_command_do_default_action_on_a(TileKind BED))
                if go_to_bed_result
                    return true
            
            var nearest_sleep_pos = find_nearest_empty_pos(intPos)
            if nearest_sleep_pos == invalid_tile_pos
                dbg_ai("no sleep pos found")
                return false

            var delta_pos = is_going_to_bed ? float2(0.0,0.0) : float2(fixed_random_float(0), fixed_random_float(1)) - float2(0.5, 0.5)
            var nearest_sleep_pos_float = float2(nearest_sleep_pos) + delta_pos
            if length(nearest_sleep_pos_float - position) > 0.5
                target_position = nearest_sleep_pos_float
                dbg_ai("setting target_position to nearest empty pos at {nearest_sleep_pos}")
                return true

            set_character_animation(self, AnimKind SLEEP)
            target_position = position
            velocity = float2(0.0,0.0)
            return true //continue sleeping
        elif cmd.kind == AiCommandKind EAT_SOMETHING
            var eat_grass = !is_human(kind)
            var nearest_eat_pos = invalid_tile_pos
            if eat_grass
                nearest_eat_pos = find_nearest_t(intPos, $(pos)=>grid_items->getTileInt(pos).kind == TileKind NONE && grid_ground_decals->getTileInt(pos).kind == TileKind NONE && grid_ground->getTileInt(pos).kind == TileKind GRASS && is_walkable_for_a_star(pos, is_human(kind)))
            else
                if any_eatable_on_level()
                    nearest_eat_pos = find_nearest_item(TileKind BREAD, intPos, 20)
                    if nearest_eat_pos == invalid_tile_pos
                        nearest_eat_pos = find_nearest_t(intPos, $(pos)=>is_eatable(grid_items->getTileInt(pos).kind), 10)

            if nearest_eat_pos == invalid_tile_pos
                dbg_ai("found nothing to eat")
                return false

            var nearest_eat_pos_float = float2(nearest_eat_pos)
            if length(nearest_eat_pos_float - position) > 0.3
                target_position = nearest_eat_pos_float
                dbg_ai("setting target_position to nearest food at {nearest_eat_pos}")
                return true

            if !eat_grass
                if !ai_util_drop_current_item_if_any()
                    return false
                var hint : AltActionCallHint
                hint.is_eat = true
                var res = do_alt_action(self, nearest_eat_pos, hint)
                if res.is_valid
                    idle_time_left = 0.5
                    dbg_ai("doing alt_action with {grid_items->getTileInt(nearest_eat_pos).kind} at {nearest_eat_pos}")
                else
                    dbg_ai("failed to do alt_action with {grid_items->getTileInt(nearest_eat_pos).kind} at {nearest_eat_pos}")
                    _assert(false)
                    return false
                return true     
            else
                //eat_grass_action
                play_sound(SoundKind EAT_GRASS, position)
                var tile = grid_ground_decals->getTileInt(nearest_eat_pos)
                tile.kind = TileKind DECAL_SMALL
                grid_ground_decals->setTile(tile)
                hunger = max(0.0, hunger - 1.0 / 3.0)
                return true
        elif cmd.kind == AiCommandKind MAKE_BREAD
            if !is_bread(carry_item)
                return _process_command(ai_command_bring_a_to_b(TileKind FLOUR, TileKind STOVE_WITH_COAL_FIRED))
            else
                ai_util_drop_current_item_if_any()
            return true
        elif cmd.kind == AiCommandKind MAKE_FIRE
            if _process_command(ai_command_bring_a_to_b(TileKind FLINT_STONE, TileKind STOVE_WITH_COAL))
                return true
            if _process_command(ai_command_bring_a_to_b(TileKind WOOD, TileKind STOVE))
                return true
            if _process_command(ai_command_bring_a_to_b(TileKind FLINT_STONE, TileKind CAMPFIRE_NO_FIRE))
                return true
            return _process_command(ai_command_bring_a_to_b(TileKind WOOD, TileKind CAMPFIRE_NO_WOOD))
            
        return false

var item_is_table : table<TileKind; array<TileKind>>
var item_is_inversed_table : table<TileKind; array<TileKind>>
def init_item_is_inversed()
    clear(item_is_table)
    clear(item_is_inversed_table)
    for e1 in each_enum(type<TileKind>)
        for e2 in each_enum(type<TileKind>)
            if item_is(e1,e2)
                push(item_is_inversed_table[e2], e1)
                push(item_is_table[e1], e2)

    //log("{item_is_inversed_table[TileKind WHEAT_COLLECTED_ANY]}")

def item_is(item : TileKind; other : TileKind) : bool
    if other == TileKind TREE
        if int(item) >= int(TileKind TREE_GREEN) && int(item) <= int(TileKind TREE_RED)
            return true
    if other == TileKind WHEAT_COLLECTED_NOT_6
        if int(item) >= int(TileKind WHEAT_COLLECTED_1) && int(item) <= int(TileKind WHEAT_COLLECTED_5)
            return true
    if other == TileKind WHEAT_STACK
        if item == TileKind WHEAT_COLLECTED_6
            return true
    if other == TileKind WHEAT_COLLECTED_ANY
        if int(item) >= int(TileKind WHEAT_COLLECTED_1) && int(item) <= int(TileKind WHEAT_COLLECTED_6)
            return true
    if other == TileKind BREAD
        if int(item) >= int(TileKind BREAD_1) && int(item) <= int(TileKind BREAD_6)
            return true
    return item == other

var dbg_highlighted_tiles : array<int2>
def dbg_highlight(pos : int2)
    push(dbg_highlighted_tiles, pos)

let nearest_search_radius = 15
def find_nearest_item_excluding_rect(kind : TileKind; pos : int2; excluding_half_size : int; excluding_center : int2) : int2
    let radius = nearest_search_radius
    //PERF
    var nearest = invalid_tile_pos
    var nearest_dist = float(radius * radius)
    var checked = 0
    for dx in range(-radius, radius+1)
        for dy in range(-radius, radius+1)
            let item_pos = pos + int2(dx,dy)
            if abs(item_pos.x - excluding_center.x) <= excluding_half_size && abs(item_pos.y - excluding_center.y) <= excluding_half_size
                continue
            checked += 1
            //dbg_highlight(item_pos)
            if item_is(grid_items->getTileInt(item_pos).kind, kind) && length(float2(int2(dx,dy))) < nearest_dist 
                nearest_dist = length(float2(dx,dy))
                nearest = item_pos

    return nearest

def find_nearest_t(pos : int2; predicate:block<(arg:int2):bool>; max_distance : int = nearest_search_radius) : int2
    if invoke(predicate, pos)
        return pos

    //PERF try quadtree in emergency situation
    var max_count = (max_distance * 2 + 1) * (max_distance * 2 + 1)

    var current_pos = pos
    var current_radius = 1
    var t = 1
    while current_radius <= max_distance
        for i in range(t)
            current_pos.y -= 1
            if invoke(predicate, current_pos)
                return current_pos
        for i in range(t)
            current_pos.x += 1
            if invoke(predicate, current_pos)
                return current_pos
        t++
        for i in range(t)
            current_pos.y += 1
            if invoke(predicate, current_pos)
                return current_pos
        for i in range(t)
            current_pos.x -= 1
            if invoke(predicate, current_pos)
                return current_pos
        t++
        current_radius++

    return invalid_tile_pos

def find_nearest_item(kind : TileKind; pos : int2; max_distance : int = nearest_search_radius) : int2
    if items_count_cache[kind] == 0
        return invalid_tile_pos
    return find_nearest_t(pos, $(item_pos)=>item_is(grid_items->getTileInt(item_pos).kind, kind), max_distance)

def find_nearest_plowed_ground(pos : int2) : int2
    return find_nearest_t(pos, $(item_pos)=>is_ground_prepared2(item_pos) && is_ground_prepared1(item_pos) && grid_items->getTileInt(item_pos).kind == TileKind NONE )

def find_nearest_non_plowed_ground(pos : int2) : int2
    return find_nearest_t(pos, $(item_pos)=>!is_ground_prepared2(item_pos) && is_ground_prepared1(item_pos) && grid_items->getTileInt(item_pos).kind == TileKind NONE )

def find_nearest_empty_pos(pos : int2) : int2
    return find_nearest_t(pos, $(item_pos)=>grid_items->getTileInt(item_pos).kind == TileKind NONE && is_walkable_for_a_star(item_pos, false))

def get_known_name(character : Character) : string
    return is_human(character.kind) && character.is_name_known ? character.name : readable_tile_name(character.kind)

def die(var character : Character)
    if character.anim.kind == AnimKind DEATH
        return
    game_log("{get_known_name(character)} DIED")
    set_character_animation(character, AnimKind DEATH)

def ai_command_do_default_action_on_a(a : TileKind) : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind DO_DEFAULT_ACTION_ON_A_TILE
    command.a_tile = a
    return command

def ai_command_make_wheat_stacks() : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind MAKE_WHEAT_STACKS
    return command

def ai_command_plow_ground() : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind PLOW_GROUND
    return command

def ai_command_plant_wheat() : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind PLANT_WHEAT
    return command

def ai_command_pick_a(a : TileKind) : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind PICK_A
    command.a_tile = a
    return command

def ai_command_bring_a_to_b(a : TileKind; b : TileKind) : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind BRING_A_TILE_TO_B_TILE
    command.a_tile = a
    command.b_tile = b
    return command

def init_level_default()
    clear(characters)
    clear(aiCharacters)
    player = null
    ui_tutorial = null
    current_dialog = null
    seed = int4(0,0,0,0)

    world_state = WorldState()
    world_state.tutorial_state.state = TutorialStateEnum INITIAL

    map_size = map_size_default
    map_size_f = float2(map_size)

    grid_ground = generate_default_ground_grid(map_size.x, map_size.y)
    grid_items = generate_default_grid(map_size.x, map_size.y, grid_ground)
    grid_ground_decals = generate_default_grid_decals(map_size.x, map_size.y, grid_ground)

    for x in range(0, map_size.x)
        for y in range(0, map_size.y)
            var idx = grid_ground->getIdxInt(int2(x,y))

            var tile = grid_ground.tiles[idx]
            tile.kind = random_float(seed) > 0.02 ? TileKind GRASS : TileKind SOIL    
            grid_ground.tiles[idx] = tile

            
            var decalTile = grid_ground_decals.tiles[idx] 
            if random_float(seed) > 0.95
                if random_float(seed) > 0.2
                    decalTile.kind = TileKind DECAL_SMALL
                else
                    decalTile.kind = TileKind DECAL_BIG
            grid_ground_decals.tiles[idx] = decalTile

            var item_tile = grid_items.tiles[idx]
            if tile.kind == TileKind GRASS
                if random_float(seed) > 0.8
                    var r = random_float(seed)
                    if r > 0.5
                        item_tile.kind = random_float(seed) > 0.2 ? TileKind TREE_GREEN : TileKind TREE_GREEN_SMALL
                    elif r > 0.125/2.0
                        item_tile.kind = random_float(seed) > 0.2 ? TileKind TREE_YELLOW : TileKind TREE_YELLOW_SMALL
                    else
                        item_tile.kind = random_float(seed) > 0.2 ? TileKind TREE_RED : TileKind TREE_RED_SMALL
                elif random_float(seed) > (length(float2(tile.position) - map_size_f / 2.0) / map_size_f.x * 2.0 / 10.0 + 0.9) 
                    item_tile.kind = TileKind BUSH_WITH_BERRIES
            else
                if random_float(seed) > 0.1
                    var decal_tile = grid_ground_decals->getTileInt(item_tile.position)
                    decal_tile.kind = TileKind DECAL_PREPARED_SOIL
                    grid_ground_decals->setTile(decal_tile)
                    item_tile.kind = TileKind WHEAT_FULL
            if random_float(seed) > 0.96
                item_tile.kind = TileKind STONE
            grid_items.tiles[idx] = item_tile


    //water
    for x in range(map_size.x)
        var t = float(x) / 10.0
        var y = sin(t)*0.5 + sin(t*2.0)*0.3 - t*0.2
        y *= 10.0
        y += float(map_size.y) / 6.0 * 5.0
        var y_min = int(y)
        var y_max = y_min + 1
        for y in range(y_min-1, y_max+2)
            var tile = grid_ground->getTileInt(int2(x,y))
            if y >= y_min && y <= y_max
                tile.kind = TileKind WATER
            else
                tile.color = lerp_colors_fix(tile.color, 0xff000000, 0.2)
            grid_ground->setTile(tile)

            
            var item = grid_items->getTileInt(tile.position)
            item.kind = TileKind NONE
            grid_items->setTile(item)

            var decal = grid_ground_decals->getTileInt(tile.position)
            decal.kind = TileKind NONE
            decal.color = tile.color
            grid_ground_decals->setTile(decal)
        
        //HACK deleting wheat and berries to remove temptation to cross the river early on
        for y in range(y_max+1, map_size.y)
            var item = grid_items->getTileInt(int2(x,y))
            if item.kind == TileKind BUSH_WITH_BERRIES || item.kind == TileKind WHEAT_FULL
                item.kind = TileKind NONE
                grid_items->setTile(item)

                var decal = grid_ground_decals->getTileInt(int2(x,y))
                decal.kind = TileKind NONE
                grid_ground_decals->setTile(decal)

                var ground = grid_ground->getTileInt(int2(x,y))
                ground.kind = TileKind GRASS
                grid_ground->setTile(ground)


    player = new Player()
    player.position = float2(float(grid_ground.width), float(grid_ground.height )) / 2.0
    player.kind = TileKind HUMAN
    push(characters, player)

    camera.position = player.position - float2(6.0,3.0)

    var green_flag_tile = grid_items->getTileInt(get_int_pos(player.position) + int2(2,2))
    green_flag_tile.kind = TileKind GREEN_FLAG
    grid_items->setTile(green_flag_tile)

    var wood_tile = grid_items->getTileInt(green_flag_tile.position + int2(-1,-3))
    wood_tile.kind = TileKind WOOD
    grid_items->setTile(wood_tile)

    var stone_tile = grid_items->getTileInt(green_flag_tile.position + int2(-2,1))
    stone_tile.kind = TileKind STONE
    grid_items->setTile(stone_tile)


    for i in range(0, npcHumansCount)
        var npc = new AiCharacter()

        npc.position = player.position
        npc.position += float2((random_float(seed) - 0.5) * 2.0 * 1.0, (random_float(seed) - 0.5) * 2.0 * 1.0)
        if i == 0
            npc.position = player.position + float2(1.0, 0.0)
        npc.target_position = npc.position
        var r = random_float(seed)
        if r > 0.666
            npc.kind = TileKind HUMAN
        elif r > 0.333
            npc.kind = TileKind CHILD_A
        else
            npc.kind = TileKind CHILD_B

        npc.name = all_human_names[world_state.next_free_human_name]
        world_state.next_free_human_name = (world_state.next_free_human_name + 1) % length(all_human_names)

        push(characters, npc)
        push(aiCharacters, npc)

    for i in range(0, npcHorsesCount)
        var npc = new AiCharacter()
        npc.position = float2(random_float(seed) * float(map_size.x), random_float(seed) * float(map_size.y))
        npc.target_position = npc.position
        npc.kind = TileKind HORSE
        push(characters, npc)
        push(aiCharacters, npc)

    var chest_poses : array<float2>
    push(chest_poses, float2(34,37))
    push(chest_poses, float2(15,16))
    push(chest_poses, float2(2,25))
    push(chest_poses, float2(21,2))
    push(chest_poses, float2(38,32))
    for pos in chest_poses
        var tile = grid_items->getTile(pos)
        tile.kind = TileKind CHEST_IRON
        grid_items->setTile(tile)

    var sheep_poses : array<float2>
    push(sheep_poses, float2(35,29))
    push(sheep_poses, float2(35,29))
    for pos in sheep_poses
        var npc = new AiCharacter()
        npc.position = pos
        npc.target_position = npc.position
        npc.kind = TileKind SHEEP
        push(characters, npc)
        push(aiCharacters, npc)

    if dbg_mode && dbg_spawn_items
        var itemsList : array<TileKind>
        push(itemsList, TileKind STONE)
        push(itemsList, TileKind FLINT_STONE)
        push(itemsList, TileKind CAMPFIRE)
        push(itemsList, TileKind WOOD)
        push(itemsList, TileKind WHEAT_FULL)
        push(itemsList, TileKind BUCKET_EMPTY)
        push(itemsList, TileKind BUCKET_WITH_WATER)
        // push(itemsList, TileKind WHEAT_COLLECTED_1)
        push(itemsList, TileKind WHEAT_COLLECTED_2)
        // push(itemsList, TileKind WHEAT_COLLECTED_3)
        // push(itemsList, TileKind WHEAT_COLLECTED_4)
        push(itemsList, TileKind WHEAT_COLLECTED_5)
        // push(itemsList, TileKind WHEAT_COLLECTED_6)
        push(itemsList, TileKind COAL)
        push(itemsList, TileKind FENCE)
        push(itemsList, TileKind FENCE)
        push(itemsList, TileKind BUSH)
        push(itemsList, TileKind BUSH_WITH_BERRIES)
        push(itemsList, TileKind RED_FLAG)
        push(itemsList, TileKind GREEN_FLAG)
        push(itemsList, TileKind BLUE_FLAG)
        push(itemsList, TileKind BED)
        push(itemsList, TileKind SHEEP_SHEARS)
        push(itemsList, TileKind WOOL)
        push(itemsList, TileKind WOOL)
        push(itemsList, TileKind WOOL)
        push(itemsList, TileKind WOOL)
        push(itemsList, TileKind BREAD_1)
        push(itemsList, TileKind BREAD_2)
        push(itemsList, TileKind BREAD_3)
        push(itemsList, TileKind BREAD_4)
        push(itemsList, TileKind BREAD_5)
        push(itemsList, TileKind BREAD_6)

        for i in range(length(itemsList))
            var tile = grid_items->getTileInt(int2(i - length(itemsList) / 2 + grid_ground.width / 2, 1 + grid_ground.height / 2))
            tile.kind = itemsList[i]
            grid_items->setTile(tile)

            
        var groundTilesList : array<TileKind>
        push(groundTilesList, TileKind GRASS)
        push(groundTilesList, TileKind SOIL)
        push(groundTilesList, TileKind WATER)
        push(groundTilesList, TileKind WATER)
        push(groundTilesList, TileKind WATER)
        push(groundTilesList, TileKind WATER)
        
        for i in range(length(groundTilesList))
            var tile = grid_ground->getTileInt(int2(i - length(groundTilesList) / 2 + grid_ground.width / 2, 4 + grid_ground.height / 2))
            tile.kind = groundTilesList[i]
            grid_ground->setTile(tile)

def pos_to_map_normalized(pos : int2) : float2
    return float2(float(pos.x) / map_size_f.x, float(pos.y) / map_size_f.y)

enum PauseMenuStateKind
    PAUSE
    SAVE
    LOAD
    QUIT
    DEATH
    RESTART
    CRAFTBOOK
    MAIN_MENU
// 'initialize' runs once when game starts and every hot-reload

var is_first_launch = false

[export]
def initialize
    set_window_title(game_name)
    set_resolution(960, 640)//TODO
    set_resolution(900, 700)//TODO
    set_resolution(1280, 720)

    init_item_is_inversed()
    //set_antialiasing(4)
    set_vsync_enabled(true)
    
    var empty_sound_raw : array<float>
    empty_sound = create_managed_sound(44100, empty_sound_raw)

    tiles <- create_managed_image("tiles.png") 
    //set_image_smooth(tiles, true)
    //set_image_clamp(tiles, true)
    //set_image_use_mipmap(tiles)
    camera.scale = 6.0
    //camera.scale = 0.6


    push(all_human_names, "Margaux"             )
    push(all_human_names, "Noël"                )
    push(all_human_names, "Margot"              )
    push(all_human_names, "Jérôme"              )
    push(all_human_names, "Gilles"              )
    push(all_human_names, "Margaret"            )
    push(all_human_names, "Renée"               )
    push(all_human_names, "Émilie"              )
    push(all_human_names, "Danielle"            )
    push(all_human_names, "Thierry"             )
    push(all_human_names, "Guy Morel"           )
    push(all_human_names, "Isaac"               )
    push(all_human_names, "Luc"                 )
    push(all_human_names, "Françoise"           )
    push(all_human_names, "Odette Lombard"      )
    push(all_human_names, "Claire Fernandes"    )
    push(all_human_names, "Roland"              )
    push(all_human_names, "Zoé"                 )
    push(all_human_names, "Jacques Lecoq"       )
    push(all_human_names, "Valérie"             )
    push(all_human_names, "Alain"               )
    push(all_human_names, "Benoît"              )
    push(all_human_names, "Anouk"               )
    push(all_human_names, "Joseph"              )
    push(all_human_names, "Nathalie"            )
    push(all_human_names, "Lucas Vidal"         )
    push(all_human_names, "Christiane"          )
    push(all_human_names, "Astrid"              )

    push(chest_items, TileKind FLINT_STONE)
    push(chest_items, TileKind SHEEP_SHEARS)
    push(chest_items, TileKind RED_FLAG)
    push(chest_items, TileKind FLINT_STONE)
    push(chest_items, TileKind BLUE_FLAG)

    register_all_craft_rules()

    init_level_default()

    is_first_launch = !has_file("global_save.sav")
    
    var file_global_save = fopen("global_save.sav", "w")
    if file_global_save != null
        fwrite(file_global_save, "\{\}")
        fclose(file_global_save)
    else
        _assert(false)

    act(0.001)
    pause_menu = new PauseMenuState()
    pause_menu.kind = PauseMenuStateKind MAIN_MENU
    pause_menu.is_main_menu = true

class Camera
    position : float2
    scale : float

    offset : float2

    def pixelToScreen(pos : float2) : float2
        var result = pos * camera.scale + camera.offset
        result.y = -result.y
        return result

    def worldToScreen(pos : float2) : float2
        return pixelToScreen(pos * float2(tileFloorSizeX, tileFloorSizeY)) 

    def updateOffsetAndScale()
        var width = get_screen_width()
        var height = get_screen_height()
        offset = -position
        offset.x *= tileFloorSizeX * scale
        offset.y *= tileFloorSizeY * scale
        offset.x +=  float(width) / 2.0
        offset.y -=  float(height) / 2.0
        offset = float2(int2(offset))

var camera = new Camera()

def clampLength(vec : float2; maxLength : float) : float2
    var len = length(vec)
    if len <= maxLength
        return vec
    return vec / len * maxLength

def is_ground_prepared1(pos : int2) : bool
    var groundTile = grid_ground->getTileInt(pos)
    return groundTile.kind == TileKind SOIL

def is_ground_prepared2(pos : int2) : bool
    var decalsTile = grid_ground_decals->getTileInt(pos)
    return decalsTile.kind == TileKind DECAL_PREPARED_SOIL || decalsTile.kind == TileKind DECAL_PREPARED_AND_WATERED_SOIL 

def can_prepare_ground_for_seeds1(pos : int2) : bool
    var groundTile = grid_ground->getTileInt(pos)
    return groundTile.kind == TileKind GRASS

def prepare_ground_for_seeds1(pos : int2)
    var groundTile = grid_ground->getTileInt(pos)
    groundTile.kind = TileKind SOIL
    grid_ground->setTile(groundTile)

    var decalsTile = grid_ground_decals->getTileInt(pos)
    decalsTile.kind = TileKind NONE
    decalsTile.color = groundTile.color
    grid_ground_decals->setTile(decalsTile)

def prepare_ground_for_seeds2(pos : int2)
    var groundTile = grid_ground->getTileInt(pos)
    
    var decalsTile = grid_ground_decals->getTileInt(pos)
    decalsTile.kind = TileKind DECAL_PREPARED_SOIL
    grid_ground_decals->setTile(decalsTile)
    world_state.tutorial_state.player_plowed_ground = true

def unprepare_ground_for_seeds2(pos : int2)
    var groundTile = grid_ground->getTileInt(pos)
    
    var decalsTile = grid_ground_decals->getTileInt(pos)
    decalsTile.kind = TileKind NONE
    grid_ground_decals->setTile(decalsTile)

def open_chest(var chest : Tile)
    play_sound(SoundKind GENERIC_ACTION, chest.position)
    var idx = world_state.next_chest_item % length(chest_items)
    world_state.next_chest_item = (world_state.next_chest_item + 1) % length(chest_items)
    var item = chest_items[idx]
    chest.kind = item
    chest.anim.kind = AnimKind APPEAR_FROM_CHEST
    chest.anim.t = 0.0
    chest.anim.stopT = 0.5
    grid_items->setTile(chest)

def cut_tree(var tree : Tile)
    if tree.anim.kind != AnimKind NONE
        return

    play_sound(SoundKind CHOP, tree.position)
    
    var isFinalHit = tree.saved_float >= 3.0
    if isFinalHit
        play_sound(SoundKind TREE_FALL, tree.position)
        tree.anim.kind = AnimKind TREE_FALL
        tree.anim.t = 0.0
        tree.anim.stopT = 1.0
        grid_items->setTile(tree)
    else
        tree.saved_float += 1.0
        tree.anim.kind = AnimKind SQUASH_AND_STRETCH
        tree.anim.t = 0.0
        tree.anim.stopT = 0.2
        grid_items->setTile(tree)

def drop_carry_item(var character : Character; pos : int2)
    if character.carry_item != TileKind NONE
        drop(character.carry_item, pos)
        character.carry_item = TileKind NONE

def drop(kind : TileKind; pos : int2)
    var tile = grid_items->getTileInt(pos)
    tile.anim.kind = AnimKind NONE
    tile.kind = kind
    grid_items->setTile(tile)

    play_sound(get_drop_sound(kind), pos)

def item_count_per_tile(kind : TileKind) : int
    if kind == TileKind WHEAT_FULL
        return 2
    return 1

def get_wheat_count(a: TileKind) : int
    return int(a) - int(TileKind WHEAT_COLLECTED_1) + 1

def get_wheat_from_count(a: int) : TileKind
    if a == 0
        return TileKind NONE
    if a == 1
        return TileKind WHEAT_COLLECTED_1
    if a == 2
        return TileKind WHEAT_COLLECTED_2
    if a == 3
        return TileKind WHEAT_COLLECTED_3
    if a == 4
        return TileKind WHEAT_COLLECTED_4
    if a == 5
        return TileKind WHEAT_COLLECTED_5
    if a == 6
        return TileKind WHEAT_COLLECTED_6
    _assert(false)
    return TileKind NONE

def add_wheat(a : TileKind; b : TileKind) : TileKind
    var s = get_wheat_count(a) + get_wheat_count(b)
    return get_wheat_from_count(min(s, 6))

def add_bread(a : TileKind; b : TileKind) : TileKind
    var s = get_bread_count(a) + get_bread_count(b)
    return get_bread_from_count(min(s, 6))

def add_wheat_reminder(a : TileKind; b : TileKind) : TileKind
    var s = get_wheat_count(a) + get_wheat_count(b)
    return get_wheat_from_count(s - min(s, 6))

def add_bread_reminder(a : TileKind; b : TileKind) : TileKind
    var s = get_bread_count(a) + get_bread_count(b)
    return get_bread_from_count(s - min(s, 6))

def is_collected_wheat(kind : TileKind) : bool
    return int(kind) >= int(TileKind WHEAT_COLLECTED_1) && int(kind) <= int(TileKind WHEAT_COLLECTED_6)

def pick(var character : Character; var tile : Tile)
    //if tile.anim.kind != AnimKind NONE
    //    return
    var kind = tile.kind

    play_sound(get_pick_sound(tile.kind), tile.position)

    if tile.kind == TileKind WHEAT_FULL
        unprepare_ground_for_seeds2(tile.position)
    
    if is_big_item(tile.kind)
        if character.carry_item != TileKind NONE
            if is_collected_wheat(kind) && is_collected_wheat(character.carry_item)
                tile.kind = add_wheat_reminder(kind, character.carry_item)
                character.carry_item = add_wheat(kind, character.carry_item)
            elif is_bread(kind) && is_bread(character.carry_item)
                tile.kind = add_bread_reminder(kind, character.carry_item)
                character.carry_item = add_bread(kind, character.carry_item)
            else
                tile.kind = character.carry_item
                drop_carry_item(character, tile.position)
                character.carry_item = kind
        else
            character.carry_item = kind
            tile.kind = TileKind NONE
    else
        _assert(false)
        tile.anim.kind = AnimKind PICK
        tile.anim.t = 0.0
        tile.anim.stopT = 0.5


    grid_items->setTile(tile)

def get_bread_count(kind : TileKind) : int
    _assert(is_bread(kind))
    return int(kind) - int(TileKind BREAD_1) + 1

def is_bread(kind : TileKind) : bool
    return int(kind) >= int(TileKind BREAD_1) && int(kind) <= int(TileKind BREAD_6)

def is_big_item(kind : TileKind) : bool
    if kind == TileKind WOOD || kind == TileKind FLINT_STONE || is_collected_wheat(kind) || kind == TileKind COAL || is_flag(kind)
        return true
    if kind == TileKind BED || kind == TileKind SHEEP_SHEARS || kind == TileKind WOOL || kind == TileKind STOVE || kind == TileKind STOVE_WITH_COAL || kind == TileKind STONE || kind == TileKind FLOUR
        return true
    if is_bread(kind) || kind == TileKind CAMPFIRE_NO_FIRE || kind == TileKind CAMPFIRE_NO_WOOD || kind == TileKind FENCE
        return true
    if kind == TileKind CLOTH
        return true
    return false

def is_pickable(kind : TileKind) : bool
    if kind == TileKind WOOD || kind == TileKind FLINT_STONE || is_collected_wheat(kind) || kind == TileKind COAL || is_flag(kind)
        return true
    if kind == TileKind BED || kind == TileKind SHEEP_SHEARS || kind == TileKind WOOL || kind == TileKind STOVE || kind == TileKind STOVE_WITH_COAL || kind == TileKind STONE || kind == TileKind FLOUR
        return true
    if is_bread(kind) || kind == TileKind CAMPFIRE_NO_FIRE || kind == TileKind CAMPFIRE_NO_WOOD || kind == TileKind FENCE
        return true
    if kind == TileKind CLOTH
        return true
    return false
var prev_horse : AiCharacter?
var prev_leashed : AiCharacter?

def is_on_horse(character : Character):bool
    return character.kind == TileKind HUMAN_ON_HORSE

def mount_horse(var horse : AiCharacter?)
    if prev_horse != null
        unleash(prev_horse)
        prev_horse = null
        
    player.kind = TileKind HUMAN_ON_HORSE
    player.mirrorX = horse.mirrorX

    var idx = find_index(characters, horse)
    erase(characters, idx)

    idx = find_index(aiCharacters, horse)
    erase(aiCharacters, idx)
    

def unmount_horse(var character : Character)
    var npc = new AiCharacter()
    npc.position = character.position
    npc.position.y += 0.1
    npc.target_position = npc.position
    npc.kind = TileKind HORSE
    npc.z = character.z
    npc.mirrorX = character.mirrorX
    npc.leash = LeashKind TO_GROUND
    npc.leash_to_ground_pos = npc.position
    //WARN player only stuff
    prev_horse = npc
    
    character.kind = TileKind HUMAN

    push(characters, npc)
    push(aiCharacters, npc)

def unleash(var npc : AiCharacter?)
    npc.leash = LeashKind NONE

def leash_to_player(var npc : AiCharacter?)
    if prev_leashed != null
        unleash(prev_leashed)
        prev_leashed = null
    
    npc.leash = LeashKind TO_PLAYER
    prev_leashed = npc

def get_nearest_npc(pos : float2) : AiCharacter?
    var nearestDist = 0.5
    var nearestNpc : AiCharacter?
    for npc in aiCharacters
        var dist = length(npc.position - pos)
        if dist < nearestDist
            nearestDist = dist
            nearestNpc = npc

    return nearestNpc

def _craft(var character : Character; _itemTile : Tile; exec : bool) : bool
    var itemTile = _itemTile
    var kind = itemTile.kind 
    var result = false

    var character_pos = character.position
    var groundTile = grid_ground->getTileInt(itemTile.position)
    var groundDecalTile = grid_ground_decals->getTileInt(itemTile.position)
    var groundKind = groundTile.kind

    if kind == TileKind STOVE_WITH_COAL_FIRED && character.carry_item == TileKind FLOUR
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            character.carry_item = TileKind BREAD_6
            itemTile.saved_float += 1.0
            if itemTile.saved_float >= 3.0
                kind = TileKind STOVE
        result = true
    // elif kind == TileKind CAMPFIRE && character.carry_item == TileKind BUCKET_WITH_WATER
    //     if exec
    //         play_sound(SoundKind DROP_WATER, character_pos)
    //         play_sound(SoundKind FIRE_PUT_OUT, character_pos)
    //         kind = TileKind CAMPFIRE_NO_WOOD
    //         character.carry_item = TileKind BUCKET_EMPTY
    //     result = true
    // elif kind == TileKind STOVE_WITH_COAL_FIRED && character.carry_item == TileKind BUCKET_WITH_WATER
    //     if exec
    //         play_sound(SoundKind DROP_WATER, character_pos)
    //         play_sound(SoundKind FIRE_PUT_OUT, character_pos)
    //         kind = TileKind STOVE_WITH_COAL
    //         character.carry_item = TileKind BUCKET_EMPTY
    //     result = true
    // elif groundDecalTile.kind == TileKind DECAL_PREPARED_SOIL && character.carry_item == TileKind BUCKET_WITH_WATER
    //     if exec
    //         play_sound(SoundKind DROP_WATER, character_pos)
    //         groundDecalTile.kind = TileKind DECAL_PREPARED_AND_WATERED_SOIL
    //         grid_ground_decals->setTile(groundDecalTile)
    //         character.carry_item = TileKind BUCKET_EMPTY
    //     result = true
    // elif groundKind == TileKind WATER && character.carry_item == TileKind BUCKET_EMPTY
    //     if exec
    //         play_sound(SoundKind PICK_WATER, character_pos)
    //         character.carry_item = TileKind BUCKET_WITH_WATER
    //     result = true
    elif kind == TileKind NONE && groundKind == TileKind WATER && character.carry_item == TileKind WOOD
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            character.carry_item = TileKind NONE
            groundKind = TileKind WOODEN_PLANE
            kind = TileKind NONE
        result = true
    elif is_collected_wheat(kind) && is_collected_wheat(character.carry_item)
        var sum = add_wheat(kind, character.carry_item)
        var reminder = add_wheat_reminder(kind, character.carry_item)
        if sum == character.carry_item
            result = false
        else
            result = true
            if exec
                play_sound(get_pick_sound(kind), character_pos)
                character.carry_item = sum
                kind = reminder
    elif is_bread(kind) && is_bread(character.carry_item)
        var sum = add_bread(kind, character.carry_item)
        var reminder = add_bread_reminder(kind, character.carry_item)
        if sum == character.carry_item
            result = false
        else
            result = true
            if exec
                play_sound(get_pick_sound(kind), character_pos)
                character.carry_item = sum
                kind = reminder
    elif is_collected_wheat(character.carry_item) && is_ground_prepared1(itemTile.position) && is_ground_prepared2(itemTile.position) && itemTile.kind == TileKind NONE
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            character.carry_item = get_wheat_from_count(get_wheat_count(character.carry_item) - 1)
            kind = TileKind PLANTED_SEEDS
            world_state.tutorial_state.player_planted_wheat = true //TODO only if player
        result = true
    elif kind == TileKind BUSH_WITH_BERRIES && character.carry_item == TileKind NONE
        if exec
            play_sound(SoundKind EAT_APPLE, character_pos)
            kind = TileKind BUSH
            itemTile.saved_float = 0.0
            character.hunger = max(0.0, character.hunger - 1.0 / 3.0)
        result = true
    elif (kind == TileKind BUSH || kind == TileKind TREE_GREEN_SMALL || kind == TileKind TREE_RED_SMALL || kind == TileKind TREE_YELLOW_SMALL) && character.carry_item == TileKind NONE
        if exec
            play_sound(SoundKind BREAK_SMALL_TREE, character_pos)
            kind = TileKind NONE
            itemTile.anim.kind = AnimKind NONE
        result = true
    elif kind == TileKind WHEAT_FULL && character.carry_item == TileKind NONE
        if exec
            play_sound(SoundKind WHOOSH, character_pos)
            kind = TileKind WHEAT_COLLECTED_2
            unprepare_ground_for_seeds2(itemTile.position)
        result = true
    else
        for rule in all_craft_rules
            if rule.is_craftbook_only
                continue
            if rule.ground_tile_before == itemTile.kind && rule.carry_tile_before == character.carry_item
                if exec
                    play_sound(rule.sound, character_pos)
                    kind = rule.ground_tile_after
                    character.carry_item = rule.carry_tile_after
                    itemTile.anim.kind = AnimKind NONE
                    itemTile.saved_float = 0.0
                result = true
                break

    if result && exec
        itemTile.kind = kind
        grid_items->setTile(itemTile)

        if groundTile.kind != groundKind
            groundTile.kind = groundKind
        grid_ground->setTile(groundTile)
    
    return result

struct CraftRule
    ground_tile_before : TileKind
    carry_tile_before : TileKind
    ground_tile_after : TileKind
    carry_tile_after : TileKind
    sound : SoundKind
    is_craftbook_only : bool
    in_craftbook : bool

var all_craft_rules : array<CraftRule>
def register_craft_rule_craftbook_only(ground_tile_before : TileKind; carry_tile_before : TileKind; ground_tile_after : TileKind; carry_tile_after : TileKind; sound : SoundKind = SoundKind GENERIC_ACTION)
    register_craft_rule(ground_tile_before, carry_tile_before, ground_tile_after, carry_tile_after, sound, true, true)

def register_craft_rule_not_in_craftbook(ground_tile_before : TileKind; carry_tile_before : TileKind; ground_tile_after : TileKind; carry_tile_after : TileKind; sound : SoundKind = SoundKind GENERIC_ACTION)
    register_craft_rule(ground_tile_before, carry_tile_before, ground_tile_after, carry_tile_after, sound, false, false)

def register_craft_rule(ground_tile_before : TileKind; carry_tile_before : TileKind; ground_tile_after : TileKind; carry_tile_after : TileKind; sound : SoundKind = SoundKind GENERIC_ACTION; is_craftbook_only : bool = false; in_craftbook : bool = true)
    _assert(!is_craftbook_only || in_craftbook)
    var rule : CraftRule
    rule.ground_tile_before = ground_tile_before
    rule.carry_tile_before = carry_tile_before
    rule.ground_tile_after = ground_tile_after
    rule.carry_tile_after = carry_tile_after
    rule.is_craftbook_only = is_craftbook_only
    rule.in_craftbook = in_craftbook
    rule.sound = sound
    push(all_craft_rules, rule)

def register_all_craft_rules()
	register_craft_rule(TileKind STONE, TileKind WOOD, TileKind CAMPFIRE_NO_FIRE, TileKind NONE, SoundKind PUT_WOOD_TO_STOVE)
	register_craft_rule(TileKind CAMPFIRE_NO_WOOD, TileKind WOOD, TileKind CAMPFIRE_NO_FIRE, TileKind NONE, SoundKind PUT_WOOD_TO_STOVE)
	
	register_craft_rule(TileKind CAMPFIRE_NO_FIRE, TileKind FLINT_STONE, TileKind CAMPFIRE, TileKind FLINT_STONE)
	
	register_craft_rule(TileKind WOOD, TileKind WOOL, TileKind BED, TileKind NONE)
	register_craft_rule(TileKind WOOL, TileKind WOOL, TileKind CLOTH, TileKind NONE)
	register_craft_rule(TileKind STONE, TileKind STONE, TileKind STOVE, TileKind NONE)
	//register_craft_rule(TileKind STOVE, TileKind COAL, TileKind STOVE_WITH_COAL, TileKind NONE, SoundKind PUT_WOOD_TO_STOVE)
	register_craft_rule(TileKind STOVE, TileKind WOOD, TileKind STOVE_WITH_COAL, TileKind NONE, SoundKind PUT_WOOD_TO_STOVE)
	
	register_craft_rule(TileKind STOVE_WITH_COAL, TileKind FLINT_STONE, TileKind STOVE_WITH_COAL_FIRED, TileKind FLINT_STONE)
	register_craft_rule_craftbook_only(TileKind STOVE_WITH_COAL_FIRED, TileKind FLOUR, TileKind STOVE_WITH_COAL_FIRED, TileKind BREAD_6)
	register_craft_rule(TileKind WHEAT_COLLECTED_6, TileKind STONE, TileKind FLOUR, TileKind STONE)
//	register_craft_rule_craftbook_only(TileKind CAMPFIRE, TileKind BUCKET_WITH_WATER, TileKind CAMPFIRE_NO_WOOD, TileKind BUCKET_EMPTY)
//	register_craft_rule_craftbook_only(TileKind STOVE_WITH_COAL_FIRED, TileKind BUCKET_WITH_WATER, TileKind STOVE_WITH_COAL, TileKind BUCKET_EMPTY)
//	register_craft_rule_craftbook_only(TileKind DECAL_PREPARED_SOIL, TileKind BUCKET_WITH_WATER, TileKind DECAL_PREPARED_AND_WATERED_SOIL, TileKind BUCKET_EMPTY, SoundKind DROP_WATER)
	
//	register_craft_rule_craftbook_only(TileKind WATER, TileKind BUCKET_EMPTY, TileKind WATER, TileKind BUCKET_WITH_WATER)
	register_craft_rule_craftbook_only(TileKind WATER, TileKind WOOD, TileKind WOODEN_PLANE, TileKind NONE)
	register_craft_rule_craftbook_only(TileKind DECAL_PREPARED_SOIL, TileKind WHEAT_COLLECTED_1, TileKind PLANTED_SEEDS, TileKind NONE)
	//register_craft_rule_craftbook_only(TileKind WHEAT_COLLECTED_2, TileKind WHEAT_COLLECTED_2, TileKind NONE, TileKind WHEAT_COLLECTED_4)
	//register_craft_rule_not_in_craftbook(TileKind WHEAT_FULL, TileKind NONE, TileKind WHEAT_COLLECTED_2, TileKind NONE, SoundKind WHOOSH)//TODO not realy craft
	register_craft_rule(TileKind WOOD, TileKind WOOD, TileKind FENCE, TileKind NONE, SoundKind DROP_WOOD)
    pass

def can_combine(a : TileKind; b : TileKind) : bool
    unsafe
        var character : Character
        character.carry_item = a
        var tile : Tile
        tile.kind = b
        return can_craft(character, tile)

def can_craft(var character : Character; itemTile : Tile) : bool
    return _craft(character, itemTile, false)

def craft(var character : Character; itemTile : Tile)
    _craft(character, itemTile, true)

struct AltActionCallHint
    is_eat : bool
    is_sleep : bool

def do_alt_action(var character : Character; at_pos : int2) : AltActionResult
    var hint : AltActionCallHint
    return _alt_action(character, at_pos, true, hint)

def do_alt_action(var character : Character; at_pos : int2; hint : AltActionCallHint) : AltActionResult
    return _alt_action(character, at_pos, true, hint)

def can_do_alt_action(var character : Character; at_pos : int2) : bool
    let result = _alt_action(character, at_pos, false)
    return result.is_valid

let invalid_tile_pos = int2(-9999,-9999)

def get_highlight_kind(kind : TileKind) : TileKind
    if kind == TileKind HORSE
        return TileKind HORSE_HIGHLIGHT
    elif kind == TileKind CHILD_A
        return TileKind CHILD_A_HIGHLIGHT
    elif kind == TileKind CHILD_B
        return TileKind CHILD_B_HIGHLIGHT
    elif kind == TileKind HUMAN
        return TileKind HUMAN_HIGHLIGHT
    elif kind == TileKind SHEEP
        return TileKind SHEEP_HIGHLIGHT
    elif kind == TileKind SHEEP_SHEARED
        return TileKind SHEEP_SHEARED_HIGHLIGHT
    _assert(false)
    return TileKind NONE

def clear_alt_action_highlight()
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, false)
        highlightedAltActionNpc = null

    if highlightedAltActionTilePos != invalid_tile_pos
        set_highlighted(highlightedAltActionTilePos, false)
        highlightedAltActionTilePos = invalid_tile_pos

def draw_alt_action_highlight()
    let result = _alt_action(*player, invalid_tile_pos, false)
    if !result.is_valid
        return

    if result.has_target_item_pos
        var color = result.is_drop_action || result.is_pick_action ? 0xa0ffffff : 0xffffffff
        draw_tile_highlight(grid_ground->getTile(player.position), color)
        
    highlightedAltActionNpc = result.target_char
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, true)

def highlight_alt_action()
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, false)
        highlightedAltActionNpc = null

    if highlightedAltActionTilePos != invalid_tile_pos
        set_highlighted(highlightedAltActionTilePos, false)
        highlightedAltActionTilePos = invalid_tile_pos

    var result = _alt_action(*player, invalid_tile_pos ,false)
    highlightedAltActionNpc = result.target_char
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, true)

    if result.has_target_item_pos
        highlightedAltActionTilePos = result.target_item_pos
        set_highlighted(result.target_item_pos, true)

var highlightedAltActionTilePos : int2
def set_highlighted(tilePos : int2; is_highlighted : bool)
    var tile = grid_items->getTileInt(tilePos)
    if is_highlighted
        if tile.color == 0xffffff80
            return
        tile.color = 0xffffff80
    else
        if tile.color == 0xffffffff
            return
        tile.color = 0xffffffff
    grid_items->setTile(tile)

var highlightedAltActionNpc : Character?
def set_highlighted(var character : Character?; is_highlighted : bool)
    character.is_highlighted = is_highlighted
    return
    if is_highlighted
        character.color = 0xffffff80
    else
        character.color = 0xffffffff

struct AltActionResult
    is_valid : bool
    target_char : AiCharacter?
    has_target_item_pos : bool
    target_item_pos : int2
    is_drop_action : bool
    is_pick_action : bool

def is_sleeping(character : Character) : bool
    return (character.anim.kind == AnimKind SLEEP || character.anim.kind == AnimKind SLEEP_IN_BED)

def can_make_dialog(character : AiCharacter) : bool
    return is_human(character.kind) && !is_dead(character) && !is_sleeping(character) && (!character.command.do_once || character.command.kind == AiCommandKind NONE)

def make_tutorial_dialog(character : AiCharacter?; character_lines : array<string>; player_lines : array<string>) : TutorialDialogState?
    if current_dialog != null
        _assert(false)
        return null

    var dialog = new TutorialDialogState()
    dialog.character = character
    dialog.character.leash = LeashKind TO_PLAYER
    dialog.character_lines := character_lines
    dialog.player_lines := player_lines
    current_dialog = dialog
    return dialog

def make_dialog(character : AiCharacter?) : DialogState?
    if current_dialog != null
        _assert(false)
        return null

    var dialog = new DialogState()
    dialog.character = character
    dialog.character.leash = LeashKind TO_PLAYER
    current_dialog = dialog
    return dialog

def get_bread_from_count(count : int) : TileKind
    if count == 0
        return TileKind NONE
    if count == 1
        return TileKind BREAD_1
    if count == 2
        return TileKind BREAD_2
    if count == 3
        return TileKind BREAD_3
    if count == 4
        return TileKind BREAD_4
    if count == 5
        return TileKind BREAD_5
    if count == 6
        return TileKind BREAD_6
    _assert(false)
    return TileKind NONE

def _alt_action(var character : Character; _at_pos : int2; exec : bool) : AltActionResult
    var hint : AltActionCallHint
    return _alt_action(character, _at_pos, exec, hint)

def _alt_action(var character : Character; _at_pos : int2; exec : bool; hint : AltActionCallHint) : AltActionResult
    var at_pos = _at_pos
    var pos_only = at_pos != invalid_tile_pos
    if at_pos == invalid_tile_pos
        at_pos = grid_items->getIntPos(character.position)

    var result : AltActionResult
    if is_dead(character)
        return result
    if is_on_horse(character)
        result.is_valid = true
        if exec
            unmount_horse(character)
        return result
    
    //WARN changing player only static vars 
    if !pos_only && prev_leashed != null
        result.is_valid = true
        if exec
            unleash(prev_leashed)
            prev_leashed = null
        return result

    
    var npc = get_nearest_npc(character.position)

    //WARN doing player only stuff 
    if !pos_only && npc != null
        if npc.kind == TileKind HORSE && !is_sleeping(*npc) && !is_dead(*npc)
            result.is_valid = true
            result.target_char = npc
            if exec
                mount_horse(npc)
            return result
        elif (npc.kind == TileKind SHEEP || npc.kind == TileKind SHEEP_SHEARED) && !is_sleeping(*npc)
            result.target_char = npc
            result.is_valid = true

            var is_shearing = character.carry_item == TileKind SHEEP_SHEARS && npc.kind == TileKind SHEEP
            var shearing_wool_pos = invalid_tile_pos
            if is_shearing
                shearing_wool_pos = find_nearest_empty_pos(get_int_pos(character.position))
                result.is_valid = shearing_wool_pos != invalid_tile_pos

            if exec && result.is_valid
                if is_shearing
                    play_sound(SoundKind SHEAR_SHEEP, npc.position)
                    npc.kind = TileKind SHEEP_SHEARED
                    var tile = grid_items->getTileInt(shearing_wool_pos)
                    _assert(tile.kind == TileKind NONE)
                    tile.kind = TileKind WOOL
                    npc.saved_float = world_state.day_float
                    grid_items->setTile(tile)
                else
                    leash_to_player(npc)
            return result
        elif can_make_dialog(*npc)
            result.target_char = npc
            result.is_valid = true
            if exec
                make_dialog(npc)
            return result


    var item = grid_items->getTile(character.position)
    if can_craft(character, item)
        result.is_valid = true
        result.target_item_pos = item.position
        result.has_target_item_pos = true
        if exec
            craft(character, item)
        return result


    //old action begin
    if is_on_horse(character) || is_dead(character)
        return result
    var groundTile = grid_ground->getTile(character.position)
    result.has_target_item_pos = true
    result.target_item_pos = groundTile.position

    if character.carry_item != TileKind NONE
        var on_empty_tile = item.kind == TileKind NONE && groundTile.kind != TileKind WATER
        if !on_empty_tile
            return result
        if exec
            drop_carry_item(character, groundTile.position)
        result.is_valid = true
        result.is_drop_action = true
        return result

    if item.kind == TileKind BED && (is_sleep_action_on_bed() || hint.is_sleep)
        if exec
            item.kind = TileKind BED_OCCUPIED
            set_character_animation(character, AnimKind SLEEP_IN_BED)
            character.position = float2(item.position) - float2(0.0, 0.001)
            grid_items->setTile(item)
        result.is_valid = true
        return result
    elif is_bread(item.kind) && (character.hunger > 1.0 / 3.0 || hint.is_eat)
        if exec
            item.kind = get_bread_from_count(get_bread_count(item.kind)-1)
            play_sound(SoundKind EAT_BREAD, character.position)
            grid_items->setTile(item)
            character.hunger -= 1.0 / 3.0
        result.is_valid = true
        return result

    if item.kind == TileKind CLOTH && !character.is_wearing_cloth
        if exec
            item.kind = TileKind NONE
            character.is_wearing_cloth = true
            play_sound(SoundKind GENERIC_ACTION, item.position)
            grid_items->setTile(item)
        result.is_valid = true
        return result

    if is_pickable(item.kind)
        if exec
            pick(character, item)
        result.is_valid = true
        result.is_pick_action = true
        return result
    elif character.carry_item != TileKind NONE
        var on_empty_tile = item.kind == TileKind NONE
        if !on_empty_tile
            return result
        if exec
            drop_carry_item(character, grid_items->getTile(character.position).position)
        result.is_valid = true
        return result
    if item.kind == TileKind CHEST_IRON
        if exec
            open_chest(item)
        result.is_valid = true
        return result
    elif item.kind == TileKind NONE
        if is_ground_prepared1(item.position) && is_ground_prepared2(item.position)
            pass
        else
            if is_ground_prepared1(item.position)
                if exec
                    play_sound(SoundKind GENERIC_ACTION, item.position)
                    prepare_ground_for_seeds2(item.position)
                result.is_valid = true
                return result
            elif can_prepare_ground_for_seeds1(item.position)
                if exec
                    play_sound(SoundKind GENERIC_ACTION, item.position)
                    prepare_ground_for_seeds1(item.position)
                result.is_valid = true
                return result
    elif int(item.kind) >= int(TileKind TREE_GREEN) && int(item.kind) <= int(TileKind TREE_RED)
        if exec
            cut_tree(item)
        result.is_valid = true
        return result
    //old action end

    return result


def update_env(dt : float)
    world_state.day_float += dt * gamedays_per_hour / seconds_per_hour
    var day_percent = get_current_hour_float() / 24.0

    var day_percent_radians = (day_percent + 4.0 / 24.0) * PI * 2.0

    night_percent = saturate(0.5 + sign(sin(day_percent_radians))*pow(sin(day_percent_radians), 1.0/2.0) * 0.5)

    var x = world_state.day_float + 4.0
    var rain_amount = sin(x)*0.25+sin(x*2.0)*0.25+sin(x*4.0)*0.25+sin(x*8.0)*0.25
    var is_rainy = rain_amount > 0.1
    rain_percent = lerp(rain_percent, is_rainy ? 1.0 : 0.0, dt)

def set_character_animation(var ch : Character; anim : AnimKind)
    if ch.anim.kind != anim
        handle_anim_finished(ch)
    ch.anim.kind = anim
    ch.anim.t = 0.0
    ch.anim.stopT = 0.5

def handle_anim_finished(var ch : Character)
    if ch.anim.kind == AnimKind DEATH
        ch.anim.t = ch.anim.stopT//hacky
        return
    if ch.anim.kind == AnimKind SLEEP_IN_BED
        var item = grid_items->getTile(ch.position)
        if item.kind == TileKind BED_OCCUPIED
            item.kind = TileKind BED
        else
            _assert(false)
        grid_items->setTile(item)
        ch.position = float2(item.position) + float2(0.0, -0.3)
        ch.health = min(1.0, ch.health + health_per_sleep_in_bed)
        
    ch.anim.kind = AnimKind NONE

def handle_anim_finished(var tile : Tile&)
    if tile.anim.kind == AnimKind TREE_FALL
        tile.kind = TileKind WOOD
        play_sound(SoundKind TREE_FALL_END, tile.position)
    tile.anim.kind = AnimKind NONE

def get_nearest_walkable(pos : float2; is_human : bool) : int2
    var minDist = 10.0
    var posInt = grid_ground->getIntPos(pos)
    var bestPos = posInt
    for dx in range(-1, 2)
        for dy in range(-1, 2)
            if is_walkable_for_a_star(posInt + int2(dx,dy), is_human)
                var dist = length(pos - float2(posInt + int2(dx,dy)))
                if dist < minDist
                    bestPos = posInt + int2(dx,dy)
                    minDist = dist
    return bestPos

def random_wander_pos(char_pos : float2) : float2
    let diameter = 10.0
    return float2(clamp((random_float(seed) - 0.5) * diameter + char_pos.x, 0.0, float(map_size.x-1)), clamp((random_float(seed) - 0.5) * diameter + char_pos.y, 0.0, float(map_size.y-1)))

def get_int_pos(pos : float2) : int2
    return grid_items->getIntPos(pos)



var pause_menu : PauseMenuState?

def ui_draw_pause_menu_text(str : string; x_mid : int; var y : int&; color = 0xffffffff)
    var text_pos = int2(x_mid - int(get_text_size(str).x / 2.0), y)
    text_out(text_pos.x,text_pos.y, str, color)
    y += text_height * ui_count_lines(str)

def ui_count_lines(str : string) : int
    if length(str) == 0
        return 0
    var count = 1
    var was_space = false
    for ch in str
        if was_space
            count++
            was_space = false
        if ch == '\n'
            was_space = true
    return count

class SimpleGenericMenu
    idx_selected : int
    header_str : string
    options_str : array<string>
    footer_str : string

def ui_draw_simple_menu(menu : SimpleGenericMenu)
    var size = int2(300,320) - int2(0,30 + 30*4 + 30)
    size.y = 0

    var top_bar_height = 40
    var bottom_bar_height = 5
    var footer_padding = 30
    var header_padding = 30
    var bottom_padding = 30
    var top_padding = 30
    //size += int2(0, 30)


    size.y += top_bar_height
    if ui_count_lines(menu.header_str) > 0
        size.y += header_padding
    size.y += bottom_padding
    size.y += top_padding
    size.y += ui_count_lines(menu.header_str) * text_height
    if ui_count_lines(menu.footer_str) > 0
        size.y += footer_padding
    size.y += ui_count_lines(menu.footer_str) * text_height
    size.y += length(menu.options_str) * text_height

    size.x = max(size.x, int(get_text_size(menu.header_str).x)+20)
    for option in menu.options_str
        size.x = max(size.x, int(get_text_size(option).x)+20)


    var top = int2(get_screen_width() / 2 - size.x / 2, get_screen_height() / 2 - 200)
    if top.y + size.y > get_screen_height() - 50
        top.y = get_screen_height() / 2 - size.y / 2

    fill_rect(top.x, top.y, size.x , size.y ,0xa0000000)
    fill_rect(top.x, top.y, size.x , top_bar_height ,0xffffffff)
    fill_rect(top.x, top.y + size.y - bottom_bar_height, size.x , bottom_bar_height ,0xffffffff)

    var y = top.y
    var x_mid = get_screen_width() / 2

    var texture_rect = get_tile_texture_rect(TileKind UI_GAME_LOGO)
    var logo_size = texture_rect.zw * 2.0
    draw_image_transformed(tiles, float(x_mid),float(y + 10), texture_rect, 0xff303030, logo_size, 0.0, 0.5f,0.3f)
    //ui_draw_pause_menu_text("[{game_name}]", x_mid, y, 0xff000000)
    y += top_bar_height

    y += top_padding

    if length(menu.header_str) > 0
        ui_draw_pause_menu_text(menu.header_str, x_mid, y)
        y += header_padding

    for i in range(length(menu.options_str))
        var str = menu.options_str[i]
        if menu.idx_selected == i
            str = "*{str}*" 
        ui_draw_pause_menu_text(str, x_mid, y)

    if menu.footer_str != ""
        y += footer_padding
        ui_draw_pause_menu_text(menu.footer_str, x_mid, y)

def ui_draw_pause_menu()
    ui_draw_simple_menu(*pause_menu)

def dialog_up_pressed() : bool
    return get_key_down(VK_UP) || get_key_down(VK_W)
def dialog_down_pressed() : bool
    return get_key_down(VK_DOWN) || get_key_down(VK_S)
def dialog_accept_pressed() : bool
    return get_key_down(VK_SPACE) || get_key_down(VK_RETURN)
def dialog_back_pressed() : bool
    return get_key_down(VK_ESCAPE)

class PauseMenuState : SimpleGenericMenu
    kind : PauseMenuStateKind
    is_death : bool
    is_main_menu : bool

var save_slots_count = 3
def update_pause_menu(with_input : bool)
    clear(pause_menu.options_str)
    pause_menu.header_str = ""
    pause_menu.footer_str = ""
    
    if pause_menu.kind == PauseMenuStateKind PAUSE
        pause_menu.header_str = "PAUSE"
        push(pause_menu.options_str, "CONTINUE")
        push(pause_menu.options_str, "CRAFTBOOK")
        push(pause_menu.options_str, "RESTART")
        push(pause_menu.options_str, "SAVE")
        push(pause_menu.options_str, "LOAD")
        push(pause_menu.options_str, "QUIT")
        pause_menu.footer_str = "[wasd] move\n[space] interact\n[f6] quicksave\n[f7] load quicksave"
    elif pause_menu.kind == PauseMenuStateKind QUIT
        pause_menu.header_str = "DO YOU REALLY WANT TO QUIT?"
        push(pause_menu.options_str, "NO")
        push(pause_menu.options_str, "YES")
    elif pause_menu.kind == PauseMenuStateKind SAVE
        pause_menu.header_str = "SAVE"
        push(pause_menu.options_str, "<BACK>")
        for i in range(1, save_slots_count+1)
            var is_empty = !has_save(i)
            if is_empty
                push(pause_menu.options_str, "SLOT {i} <EMPTY>")
            else
                push(pause_menu.options_str, "SLOT {i}")
    elif pause_menu.kind == PauseMenuStateKind LOAD
        pause_menu.header_str = "LOAD"
        push(pause_menu.options_str, "<BACK>")
        for i in range(0, save_slots_count+1)
            var is_empty = !has_save(i)
            var str = "SLOT {i}"
            if i == 0
                str = "QUICKSAVE"
            if is_empty
                push(pause_menu.options_str, "{str} <EMPTY>")
            else
                push(pause_menu.options_str, "{str}")
    elif pause_menu.kind == PauseMenuStateKind DEATH
        pause_menu.header_str = "YOU DIED FROM HUNGER\nDAY: {get_current_day()}\nMAX POPULATION: {world_state.max_population}"
        push(pause_menu.options_str, "RESTART")
        push(pause_menu.options_str, "LOAD")
        push(pause_menu.options_str, "QUIT")
    elif pause_menu.kind == PauseMenuStateKind RESTART
        pause_menu.header_str = "SKIP TUTORIAL?"
        push(pause_menu.options_str, "<BACK>")
        push(pause_menu.options_str, "NO")
        push(pause_menu.options_str, "YES")
    elif pause_menu.kind == PauseMenuStateKind CRAFTBOOK
        pause_menu.header_str = "CRAFTBOOK"
        push(pause_menu.options_str, "<BACK>")
        
        for rule in all_craft_rules
            if !rule.in_craftbook
                continue
            var str_before = ""
            if rule.ground_tile_before != TileKind NONE && rule.carry_tile_before !=  TileKind NONE
                str_before = " + "
            if rule.ground_tile_before != TileKind NONE
                str_before = readable_tile_name_for_craft(rule.ground_tile_before) + str_before
            if rule.carry_tile_before != TileKind NONE
                str_before = str_before + readable_tile_name_for_craft(rule.carry_tile_before)

            var carry_tile_after = rule.carry_tile_after
            var ground_tile_after = rule.ground_tile_after
            if carry_tile_after == rule.carry_tile_before || carry_tile_after == TileKind BUCKET_EMPTY
                carry_tile_after = TileKind NONE
            if ground_tile_after == rule.ground_tile_before
                ground_tile_after = TileKind NONE
            var str_after = ""
            if ground_tile_after != TileKind NONE && carry_tile_after !=  TileKind NONE
                str_after = " + "
            if ground_tile_after != TileKind NONE
                str_after = readable_tile_name_for_craft(ground_tile_after) + str_after
            if carry_tile_after != TileKind NONE
                str_after = str_after + readable_tile_name_for_craft(carry_tile_after)

            var str = str_after + " = " + str_before
            push(pause_menu.options_str, str)
    elif pause_menu.kind == PauseMenuStateKind MAIN_MENU
        pause_menu.header_str = ""
        push(pause_menu.options_str, "NEW GAME")
        push(pause_menu.options_str, "LOAD")
        push(pause_menu.options_str, "QUIT")
        pause_menu.footer_str = "[wasd] move\n[space] interact\n[f6] quicksave\n[f7] load quicksave"


    var prev_sel = pause_menu.idx_selected
    var tried_to_move_selected = false
    if dialog_up_pressed() && with_input
        pause_menu.idx_selected--
        tried_to_move_selected = true
    if dialog_down_pressed() && with_input
        pause_menu.idx_selected++
        tried_to_move_selected = true

    pause_menu.idx_selected = clamp(pause_menu.idx_selected, 0, length(pause_menu.options_str)-1)
    if tried_to_move_selected
        if prev_sel == pause_menu.idx_selected
            play_sound(SoundKind UI_BLOCKED, player.position)
        else
            play_sound(SoundKind UI_MOVE, player.position)
    
    if dialog_back_pressed() && with_input
        if pause_menu.kind == PauseMenuStateKind MAIN_MENU || pause_menu.kind == PauseMenuStateKind DEATH
            play_sound(SoundKind UI_MOVE, player.position)
            pause_menu.idx_selected = 2
            return
        else
            pause_menu.idx_selected = 0
    elif !(dialog_accept_pressed() && with_input)
        return

    if pause_menu.kind != PauseMenuStateKind CRAFTBOOK
        play_sound(SoundKind UI_CLICK, player.position)

    if pause_menu.kind == PauseMenuStateKind PAUSE
        if pause_menu.idx_selected == 0
            pause_menu = null
            return
        elif pause_menu.idx_selected == 1
            pause_menu.kind = PauseMenuStateKind CRAFTBOOK
        elif pause_menu.idx_selected == 2
            pause_menu.kind = PauseMenuStateKind RESTART
        elif pause_menu.idx_selected == 3
            pause_menu.kind = PauseMenuStateKind SAVE
        elif pause_menu.idx_selected == 4
            pause_menu.kind = PauseMenuStateKind LOAD
        elif pause_menu.idx_selected == 5
            pause_menu.kind = PauseMenuStateKind QUIT
        else
            _assert(false)
        pause_menu.idx_selected = 0
        return
    elif pause_menu.kind == PauseMenuStateKind QUIT
        if pause_menu.idx_selected == 0
            pause_menu.kind = pause_menu.is_death ? PauseMenuStateKind DEATH : PauseMenuStateKind PAUSE
            pause_menu.idx_selected = pause_menu.is_death ? 2 : 5
            if pause_menu.is_main_menu
                pause_menu.kind = PauseMenuStateKind MAIN_MENU
                pause_menu.idx_selected = 2
        elif pause_menu.idx_selected == 1
            schedule_quit_game()
            pause_menu.idx_selected = 0
        pass
    elif pause_menu.kind == PauseMenuStateKind SAVE
        if pause_menu.idx_selected == 0
            pause_menu.kind = PauseMenuStateKind PAUSE
            pause_menu.idx_selected = 3
        else
            var slot = pause_menu.idx_selected
            save(slot)
            pause_menu = null
    elif pause_menu.kind == PauseMenuStateKind LOAD
        if pause_menu.idx_selected == 0
            pause_menu.kind = pause_menu.is_death ? PauseMenuStateKind DEATH : PauseMenuStateKind PAUSE
            pause_menu.idx_selected = pause_menu.is_death ? 1 : 4
            if pause_menu.is_main_menu
                pause_menu.kind = PauseMenuStateKind MAIN_MENU
                pause_menu.idx_selected = 1
        else
            var slot = pause_menu.idx_selected - 1
            var has = has_save(slot)
            if has
                load(slot)
                pause_menu = null
    elif pause_menu.kind == PauseMenuStateKind DEATH
        if pause_menu.idx_selected == 0
            pause_menu.kind = PauseMenuStateKind RESTART
            pause_menu.idx_selected = 1
        elif pause_menu.idx_selected == 1
            pause_menu.kind = PauseMenuStateKind LOAD
            pause_menu.idx_selected = 0
        elif pause_menu.idx_selected == 2
            pause_menu.kind = PauseMenuStateKind QUIT
            pause_menu.idx_selected = 0
        else
            _assert(false)
    elif pause_menu.kind == PauseMenuStateKind RESTART
        if pause_menu.idx_selected == 0
            pause_menu.kind = pause_menu.is_death ? PauseMenuStateKind DEATH : PauseMenuStateKind PAUSE
            pause_menu.idx_selected = pause_menu.is_death ? 0 : 2
            if pause_menu.is_main_menu
                pause_menu.kind = PauseMenuStateKind MAIN_MENU
                pause_menu.idx_selected = 0
        elif pause_menu.idx_selected == 1
            init_level_default()
            world_state.tutorial_state.state = TutorialStateEnum INITIAL
            pause_menu = null
            return
        elif pause_menu.idx_selected == 2
            init_level_default()
            world_state.tutorial_state.state = TutorialStateEnum NONE
            pause_menu = null
            return
    elif pause_menu.kind == PauseMenuStateKind CRAFTBOOK
        if pause_menu.idx_selected == 0
            pause_menu.kind = PauseMenuStateKind PAUSE
            pause_menu.idx_selected = 1
            play_sound(SoundKind UI_CLICK, player.position)
        else
            pass//TODO need sound ?
    elif pause_menu.kind == PauseMenuStateKind MAIN_MENU
        if pause_menu.idx_selected == 0
            if is_first_launch
                init_level_default()
                world_state.tutorial_state.state = TutorialStateEnum INITIAL
                pause_menu = null
                return
            else
                pause_menu.kind = PauseMenuStateKind RESTART
                pause_menu.idx_selected = 1
        elif pause_menu.idx_selected == 1
            pause_menu.kind = PauseMenuStateKind LOAD
            pause_menu.idx_selected = 1
        elif pause_menu.idx_selected == 2
            schedule_quit_game()
        else
            pass//TODO need sound ?


def will_be_freezing_without_fire(character : Character) : bool
    return calc_coldness_without_fire(character) > 0.5

def is_freezing(character : Character) : bool
    return calc_coldness(character) > 0.5

var prev_captured_bed_bugfix = -1
def captured_bed_bugfix()
    if prev_captured_bed_bugfix == int(world_state.day_float) || !is_day_time()
        return
    prev_captured_bed_bugfix = int(world_state.day_float)
    for item in grid_items.tiles
        if item.kind == TileKind BED_OCCUPIED
            item.kind = TileKind BED

var ui_tutorial : TutorialMessageBox?
class TutorialMessageBox : SimpleGenericMenu
    ff : int

def show_tutorial_msg(msg : string)
    _assert(ui_tutorial == null)
    ui_tutorial = new TutorialMessageBox()
    ui_tutorial.header_str = msg
    push(ui_tutorial.options_str, "CONTINUE")

def show_tutorial_msgs(msgs : array<string>)
    _assert(ui_tutorial == null)
    ui_tutorial = new TutorialMessageBox()

    var combined_msg = ""
    for s in msgs
        combined_msg += s + "\n"

    ui_tutorial.header_str = combined_msg
    push(ui_tutorial.options_str, "CONTINUE")

let text_height = 21
def ui_draw_tutorial_msg()
    ui_draw_simple_menu(*ui_tutorial)

def is_immortal(character : Character?) : bool
    var is_tutorial_npc = !is_tutorial_finished() && length(aiCharacters) > 0 && character == aiCharacters[0]
    return is_tutorial_npc || !is_human(character.kind)

def spawn_new_villager()
    var new_character = new AiCharacter()

    for i in range(100)
        new_character.position = player.position + float2((random_float(seed)-0.5) * 2.0 * 5.0, (random_float(seed)-0.5) * 2.0 * 5.0)
        if is_walkable_for_a_star(get_int_pos(new_character.position), true)
            break
    new_character.target_position = new_character.position
    var r = random_float(seed)
    if r > 0.66666666
        new_character.kind = TileKind CHILD_A
    elif r > 0.33333333
        new_character.kind = TileKind CHILD_B
    else
        new_character.kind = TileKind HUMAN

    if is_human(new_character.kind)
        new_character.name = all_human_names[world_state.next_free_human_name]
        world_state.next_free_human_name = (world_state.next_free_human_name + 1) % length(all_human_names)

    new_character.anim.kind = AnimKind CHAR_JOINED
    new_character.anim.t = 0.0
    new_character.anim.stopT = 0.5

    push(characters, new_character)
    push(aiCharacters, new_character)

    game_log("NEW VILLAGER ARRIVED")

var dbg_fix_camera : bool
var dbg_fix_camera_pos : float2

[export]
def act(_dt: float)
    camera->updateOffsetAndScale()

    var is_rapid_timescale = false
    if player.anim.kind == AnimKind SLEEP || player.anim.kind == AnimKind SLEEP_IN_BED
        var is_anyone_awake = false
        for ch in characters
            if ch.anim.kind != AnimKind SLEEP && ch.anim.kind != AnimKind SLEEP_IN_BED && ch.anim.kind != AnimKind DEATH
                is_anyone_awake = true
                break

        if is_anyone_awake
            time_scale = max(dbg_time_scale, player_sleep_time_scale)
        else
            time_scale = max(dbg_time_scale, player_sleep_time_scale_when_everyone_sleeps)
            is_rapid_timescale = true
    else
        time_scale = dbg_time_scale


    var dt = min(_dt, 0.03333333) * time_scale
    if !is_rapid_timescale
        dt = min(dt, 0.15)
    if dbg_mode
        set_window_title("{game_name} {int(1.0/_dt)}fps, dt={dt}")

    //log("time_scale={time_scale}; dt = {dt}")

    if pause_menu != null
        update_pause_menu(true)
        if pause_menu != null
            update_pause_menu(false)
        return

    if is_dead(*player)
        //TODO some delay for animation (and maybe no pause at all)
        pause_menu = new PauseMenuState()
        pause_menu.is_death = true
        pause_menu.kind = PauseMenuStateKind DEATH
        update_pause_menu(false)
        return

    if get_key_down(VK_ESCAPE)
        play_sound(SoundKind UI_CLICK, player.position)
        pause_menu = new PauseMenuState()
        update_pause_menu(false)
        return

    if get_key_down(VK_F6)
        save(0)
    if get_key_down(VK_F7)
        load(0)

    update_tutorial(dt)
    if ui_tutorial != null
        //HACK camera is broken it tutorial for some reason
        camera.position = lerp(camera.position, player.position, saturate(dt * 3.0)) 
        camera->updateOffsetAndScale()
    
        update_tutorial_msg()
        return

    clear(items_count_cache)
    for t in grid_items.tiles
        for e in item_is_table[t.kind]
            items_count_cache[e]++

    update_rain_loop()
    update_ambient_loop()

    update_env(dt)

    captured_bed_bugfix()
    
    population = 0
    avg_hunger = 0.0
    avg_health = 0.0
    for c in characters
        if is_human(c.kind) && !is_dead(*c)
            population += 1
            avg_hunger += c.hunger
            avg_health += c.health
    if population > 0
        avg_hunger /= float(population)
        avg_health /= float(population)   

    world_state.max_population = max(world_state.max_population, population)

    if avg_hunger * 3.0 <= 2.0 && avg_health * 3.0 >= 1.5
        world_state.good_health_and_no_hunger_duration += dt
    else
        world_state.good_health_and_no_hunger_duration = max(0.0, world_state.good_health_and_no_hunger_duration - dt * good_health_and_no_hunger_to_new_human_decrease_speed)
    if world_state.good_health_and_no_hunger_duration >= good_health_and_no_hunger_to_new_human_duration && is_tutorial_finished()
        world_state.good_health_and_no_hunger_duration = 0.0
        spawn_new_villager()

    var player_can_move = !is_dead(*player)

    player.velocity = float2(0.0)
    if current_dialog != null
        if current_dialog->update()
            current_dialog.character.leash = LeashKind NONE

            current_dialog = null
        player_can_move = false

    if !is_dead(*player)
        if player_can_move && is_player_must_sleep_time() || is_sleeping(*player) && is_sleep_action_on_bed()
            //TODO some message
            player_can_move = false
            if player.anim.kind == AnimKind SLEEP_IN_BED
                set_character_animation(*player, AnimKind SLEEP_IN_BED)
            else
                set_character_animation(*player, AnimKind SLEEP)
            player.velocity = float2(0.0,0.0)
        else
            set_character_animation(*player, AnimKind NONE)

    if player_can_move
        if get_key(VK_W)
            player.velocity.y += 1.0
        if get_key(VK_S)
            player.velocity.y -= 1.0
        if get_key(VK_D)
            player.velocity.x += 1.0
        if get_key(VK_A)
            player.velocity.x -= 1.0

        if get_key_down(VK_SPACE)
            if can_do_alt_action(*player, invalid_tile_pos)
                do_alt_action(*player, invalid_tile_pos)

                
    if dbg_mode
        if get_key_down(VK_HOME)
            dbg_time_scale = min(10.0, dbg_time_scale + 1.0)
            log("dbg_time_scale = {dbg_time_scale}")
        elif get_key_down(VK_END)
            dbg_time_scale = max(1.0, dbg_time_scale - 1.0)
            log("dbg_time_scale = {dbg_time_scale}")

        if get_key_down(VK_F1)
            dbg_camera_scale = -1.0
        if get_key_down(VK_F2)
            dbg_camera_scale = 1.0
        if dbg_camera_scale > 0.0
            camera.scale = dbg_camera_scale
        if get_key_down(VK_F3)
            log("{get_int_pos(player.position)}")
        if get_key_down(VK_F8)
            heap_report()
        if get_key_down(VK_F9)
            if !is_dead(*player)
                die(*player)
        if get_key_down(VK_F10)
            spawn_new_villager()
    if get_key_down(VK_F11) && dbg_mode_camera
        dbg_fix_camera = !dbg_fix_camera
    if get_key_down(VK_F12) && dbg_mode_camera
        dbg_fix_camera_pos = camera.position
        

    player.velocity = clampLength(player.velocity, 1.0) * GetMaxSpeed(*player)
    if get_key(VK_LSHIFT) && dbg_mode
        //todo less running on horse + some penalty
        player.velocity *= 2.5
        player.isRunning = true
    else
        player.isRunning = false

    for ch in characters
        if ch.health == 0.0 && !is_immortal(ch)
            die(*ch)
            continue

        if ch.kind == TileKind SHEEP_SHEARED
            if world_state.day_float > ch.saved_float + gamedays_to_grow_wool
                ch.kind = TileKind SHEEP

        if ch.next_footstep_time < 0.0
            play_sound(SoundKind FOOTSTEP, ch.position)
            ch.next_footstep_time = 1.0
        ch.next_footstep_time -= dt * ch.speed * 1.0

        var hunger_speed = hunger_per_hour * hours_per_second
        if is_freezing(*ch)
            hunger_speed *= hunger_speed_freezing
        if ch.anim.kind == AnimKind SLEEP_IN_BED
            hunger_speed *= hunger_speed_in_bed
        if ch.isRunning && !is_on_horse(*ch)
            hunger_speed *= 2.0
        ch.hunger = min(1.0, ch.hunger + dt * hunger_speed)

        if ch.hunger == 1.0
            ch.health = max(0.0, ch.health - dt * health_loss_from_hunger_per_hour * hours_per_second)
        else
            ch.health = min(1.0, ch.health + dt * health_gain_from_no_hunger_per_hour * hours_per_second)

        if ch.anim.kind == AnimKind SLEEP || ch.anim.kind == AnimKind SLEEP_IN_BED
            ch.anim.t = 0.0
            ch.speed = 0.0
            ch.velocity = float2(0.0,0.0)
            continue

        if !is_rapid_timescale
            ch.position += ch.velocity * dt
        ch.speed = lerp(ch.speed, length(ch.velocity), dt*5.0)
        ch.z = lerp(ch.z, grid_ground->getHeight(ch.position), dt * 8.0)

        if ch.velocity.x < -0.1
            ch.mirrorX = false
        elif ch.velocity.x > 0.1
            ch.mirrorX = true
        var phys_steps_count = ch.kind == TileKind HUMAN_ON_HORSE ? 4 : 1
        for i in range(phys_steps_count)
            for x in range(int(ch.position.x), int(ch.position.x+2.0))
                for y in range(int(ch.position.y), int(ch.position.y+2.0))
                    var tileToCollide = grid_items->getTile(float2(float(x), float(y)))
                    var tileToCollide2 = grid_ground->getTile(float2(float(x), float(y)))
                    ch.position.x = clamp(ch.position.x, -0.5,map_size_f.x - 0.6)
                    ch.position.y = clamp(ch.position.y, -0.5,map_size_f.y - 0.6)
                    processCollision(ch.position, tileToCollide)
                    processCollision(ch.position, tileToCollide2)

    camera.position = lerp(camera.position, player.position, saturate(dt * 3.0))
    if dbg_fix_camera
        camera.position = dbg_fix_camera_pos
    camera->updateOffsetAndScale()

    for ch in characters
        if ch.anim.kind == AnimKind NONE
            continue
        ch.anim.t += dt
        if ch.anim.t >= ch.anim.stopT && !is_rapid_timescale
            handle_anim_finished(*ch)

    //TODO separate array for such things for optimization
    for tile in grid_items.tiles
        if tile.anim.kind == AnimKind NONE
            continue
        tile.anim.t += dt
        if tile.anim.t >= tile.anim.stopT
            handle_anim_finished(tile)
        grid_items->setTile(tile)

    world_state.wheat_grow_timer += dt
    if world_state.wheat_grow_timer > wheat_grow_period
        world_state.wheat_grow_timer -= wheat_grow_period
        //TODO separate array for such things for optimization
        for tile in grid_items.tiles
            if tile.kind == TileKind PLANTED_SEEDS
                tile.kind = TileKind WHEAT_SMALL
            elif tile.kind == TileKind WHEAT_SMALL
                tile.kind = TileKind WHEAT_MEDIUM
            elif tile.kind == TileKind WHEAT_MEDIUM
                tile.kind = TileKind WHEAT_FULL
            else
                continue
            grid_items->setTile(tile)
    world_state.wheat_grow_timer_watered += dt
    if world_state.wheat_grow_timer_watered > wheat_grow_period
        world_state.wheat_grow_timer_watered -= wheat_grow_period
        //TODO separate array for such things for optimization
        for tile in grid_items.tiles
            if grid_ground_decals->getTileInt(tile.position).kind != TileKind DECAL_PREPARED_AND_WATERED_SOIL
                continue
            if tile.kind == TileKind PLANTED_SEEDS
                tile.kind = TileKind WHEAT_SMALL
            elif tile.kind == TileKind WHEAT_SMALL
                tile.kind = TileKind WHEAT_MEDIUM
            elif tile.kind == TileKind WHEAT_MEDIUM
                tile.kind = TileKind WHEAT_FULL
            else
                continue
            grid_items->setTile(tile)

    world_state.grass_grow_timer += dt
    if world_state.grass_grow_timer > grass_grow_one_period
        world_state.grass_grow_timer -= grass_grow_one_period
        world_state.grass_grow_idx = (world_state.grass_grow_idx + grass_grow_periods_add) % grass_grow_periods_count
        var currentIdx = world_state.grass_grow_idx
        for tile in grid_ground_decals.tiles
            var idx = tile.position.x + tile.position.y * grid_items.width
            if (idx % grass_grow_periods_count) != world_state.grass_grow_idx
                continue
            if grid_ground->getTileInt(tile.position).kind != TileKind GRASS
                continue
            if tile.kind == TileKind DECAL_SMALL
                tile.kind = TileKind NONE

    world_state.tree_grow_timer += dt
    if world_state.tree_grow_timer > tree_grow_one_period
        world_state.tree_grow_timer -= tree_grow_one_period
        world_state.tree_grow_idx = (world_state.tree_grow_idx + tree_grow_periods_add) % tree_grow_periods_count
        var currentIdx = world_state.tree_grow_idx
        for tile in grid_items.tiles
            var idx = tile.position.x + tile.position.y * grid_items.width
            if (idx % tree_grow_periods_count) != world_state.tree_grow_idx
                continue
            var kind = tile.kind
            if tile.kind == TileKind TREE_GREEN_SMALL
                kind = TileKind TREE_GREEN
                tile.saved_float = 0.0
            if tile.kind == TileKind TREE_RED_SMALL
                kind = TileKind TREE_RED
                tile.saved_float = 0.0
            if tile.kind == TileKind TREE_YELLOW_SMALL
                kind = TileKind TREE_YELLOW
                tile.saved_float = 0.0
            if tile.kind == TileKind NONE
                let free_radius = 2
                var ground_tile = grid_ground->getTileInt(tile.position)
                var can_appear = (ground_tile.kind == TileKind GRASS || ground_tile.kind == TileKind SOIL) && grid_ground_decals->getTileInt(tile.position).kind != TileKind DECAL_PREPARED_SOIL
                for dx in range(-free_radius, free_radius+1)
                    if !can_appear
                        break
                    for dy in range(-free_radius, free_radius+1)
                        if grid_items->getTileInt(tile.position + int2(dx,dy)).kind != TileKind NONE
                            can_appear = false
                            break
                if can_appear
                    var r = random_float(seed)
                    if r > 0.5
                        kind = TileKind TREE_GREEN_SMALL
                    elif r > 0.125/2.0
                        kind = TileKind TREE_YELLOW_SMALL
                    else
                        kind = TileKind TREE_RED_SMALL

                    ground_tile.kind = TileKind GRASS
                    grid_ground->setTile(ground_tile)

            if tile.kind != kind
                tile.kind = kind
                grid_items->setTile(tile)

    //TODO this is ridiculous
    for tile in grid_items.tiles
        if tile.kind == TileKind CAMPFIRE
            tile.saved_float += dt * (1.0 + rain_percent)
            if tile.saved_float >= campfire_duration
                tile.kind = TileKind CAMPFIRE_NO_WOOD
        elif tile.kind == TileKind BUSH
            tile.saved_float += dt * (1.0 + rain_percent)
            if tile.saved_float >= berries_grow_period
                tile.kind = TileKind BUSH_WITH_BERRIES

    if rain_percent > 0.5
        var t = get_realtime_since_world_started()
        //TODO way too hacky
        if (t - dt) % 5.0 > 2.5 && t % 5.0 < 2.5
            for tile in grid_ground_decals.tiles
                if tile.kind == TileKind DECAL_PREPARED_SOIL
                    tile.kind = TileKind DECAL_PREPARED_AND_WATERED_SOIL
    //log("{calc_coldness(*player)}")
    for ch in aiCharacters
        if !is_dead(*ch)
            ch->Think(dt)
        else
            ch->ai_util_drop_current_item_if_any()


def get_tile_texture_rect(kind : TileKind) : float4
    var x = 1
    var y = 0 
    if kind == TileKind GRASS
        x = 4
        y = 0
    elif kind == TileKind HUMAN
        x = 19
        y = 2
    elif kind == TileKind CHILD_A
        x = 17
        y = 2
    elif kind == TileKind CHILD_B
        x = 18
        y = 2
    elif kind == TileKind TILE_SELECTION
        x = 1
        y = 5
    elif kind == TileKind NONE
        x = 0
        y = 5
    elif kind == TileKind TREE_GREEN
        x = 9
        y = 4
    elif kind == TileKind TREE_YELLOW
        x = 11
        y = 4
    elif kind == TileKind TREE_RED
        x = 10
        y = 4
    elif kind == TileKind TREE_GREEN_SMALL
        x = 5
        y = 7
    elif kind == TileKind TREE_RED_SMALL
        x = 6
        y = 7
    elif kind == TileKind TREE_YELLOW_SMALL
        x = 7
        y = 7
    elif kind == TileKind CHEST_IRON
        x = 19
        y = 4
    elif kind == TileKind FENCE_H
        x = 17
        y = 3
    elif kind == TileKind FENCE_V
        x = 13
        y = 6
    elif kind == TileKind FENCE
        x = 15
        y = 6
    elif kind == TileKind DECAL_PREPARED_SOIL || kind == TileKind DECAL_PREPARED_AND_WATERED_SOIL
        x = 13
        y = 5
    elif kind == TileKind DECAL_SMALL
        x = 18
        y = 0
    elif kind == TileKind DECAL_BIG
        x = 18
        y = 1
    elif kind == TileKind HEART_EMPTY
        x = 2
        y = 5
    elif kind == TileKind HEART_HALF
        x = 3
        y = 5
    elif kind == TileKind HEART_FULL
        x = 4
        y = 5
    elif kind == TileKind HUNGER_EMPTY
        x = 5
        y = 5
    elif kind == TileKind HUNGER_HALF
        x = 6
        y = 5
    elif kind == TileKind HUNGER_FULL
        x = 7
        y = 5
    elif kind == TileKind PLANTED_SEEDS
        x = 9
        y = 5
    elif kind == TileKind WHEAT_SMALL
        x = 10
        y = 5
    elif kind == TileKind WHEAT_MEDIUM
        x = 11
        y = 5
    elif kind == TileKind WHEAT_FULL
        x = 12
        y = 5
    elif kind == TileKind WOOD
        x = 8
        y = 5
    elif kind == TileKind HORSE
        x = 16
        y = 2
    elif kind == TileKind HUMAN_ON_HORSE
        x = 14
        y = 5
    elif kind == TileKind SHEEP
        x = 15
        y = 5
    elif kind == TileKind UI_BORDER
        x = 0
        y = 6
    elif kind == TileKind UI_NIGHT
        x = 1
        y = 6
    elif kind == TileKind UI_DAY
        x = 2
        y = 6
    elif kind == TileKind UI_RAIN
        x = 3
        y = 6
    elif kind == TileKind CAMPFIRE
        x = 4
        y = 6
    elif kind == TileKind CAMPFIRE_2
        x = 5
        y = 6
    elif kind == TileKind CAMPFIRE_3
        x = 6
        y = 6
    elif kind == TileKind CAMPFIRE_NO_WOOD
        x = 8
        y = 7
    elif kind == TileKind CAMPFIRE_NO_FIRE
        x = 9
        y = 7
    elif kind == TileKind FLINT_STONE
        x = 8
        y = 6
    elif kind == TileKind STONE
        x = 7
        y = 6
    elif kind == TileKind BUCKET_EMPTY
        x = 16
        y = 4
    elif kind == TileKind BUCKET_WITH_WATER
        x = 15
        y = 4
    elif kind == TileKind WATER
        x = 0
        y = 3
    elif kind == TileKind WATER_2
        x = 1
        y = 3
    elif kind == TileKind WATER_3
        x = 2
        y = 3
    elif kind == TileKind WATER_4
        x = 3
        y = 3
    elif kind == TileKind WOODEN_PLANE
        x = 7
        y = 4
    elif kind == TileKind WHEAT_COLLECTED_1
        x = 9
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_2
        x = 10
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_3
        x = 10
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_4
        x = 10
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_5
        x = 10
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_6
        x = 11
        y = 6
    elif kind == TileKind COAL
        x = 12
        y = 6
    elif kind == TileKind BUSH
        x = 13
        y = 4
    elif kind == TileKind BUSH_WITH_BERRIES
        x = 14
        y = 6
    elif is_flag(kind)
        x = 16
        y = 6
    elif kind == TileKind BED || kind == TileKind BED_OCCUPIED
        x = 17
        y = 6
    elif kind == TileKind SHEEP_SHEARS
        x = 18
        y = 6
    elif kind == TileKind SHEEP_SHEARED
        x = 16
        y = 5
    elif kind == TileKind WOOL
        x = 17
        y = 5
    elif kind == TileKind STOVE
        x = 0
        y = 7
    elif kind == TileKind STOVE_WITH_COAL
        x = 1
        y = 7
    elif kind == TileKind STOVE_WITH_COAL_FIRED
        x = 2
        y = 7
    elif kind == TileKind FLOUR
        x = 3
        y = 7
    elif is_bread(kind)
        x = 4
        y = 7
    elif kind == TileKind HORSE_HIGHLIGHT
        x = 10
        y = 7
    elif kind == TileKind CHILD_A_HIGHLIGHT
        x = 11
        y = 7
    elif kind == TileKind CHILD_B_HIGHLIGHT
        x = 12
        y = 7
    elif kind == TileKind HUMAN_HIGHLIGHT
        x = 13
        y = 7
    elif kind == TileKind SHEEP_HIGHLIGHT
        x = 14
        y = 7
    elif kind == TileKind SHEEP_SHEARED_HIGHLIGHT
        x = 15
        y = 7
    elif kind == TileKind RAIN_EFFECT
        x = 16
        y = 7
    elif kind == TileKind CLOTH
        x = 17
        y = 7
    elif kind == TileKind UI_SNOWFLAKE
        x = 18
        y = 7
    elif kind == TileKind CHILD_A_CLOTH
        x = 0
        y = 8
    elif kind == TileKind CHILD_B_CLOTH
        x = 1
        y = 8
    elif kind == TileKind HUMAN_CLOTH
        x = 2
        y = 8
    elif kind == TileKind UI_GAME_LOGO
        x = 3
        y = 8
        return float4(float(x)*tileSizeX,float(y)*tileSizeY,tileSizeX*3.0,tileSizeY)
    elif kind == TileKind HUMAN_ON_HORSE_CLOTH
        x = 6
        y = 8

    return float4(float(x)*tileSizeX,float(y)*tileSizeY,tileSizeX,tileSizeY)

def get_cloth_tile(character : TileKind) : TileKind
    if character == TileKind HUMAN
        return TileKind HUMAN_CLOTH
    if character == TileKind CHILD_A
        return TileKind CHILD_A_CLOTH
    if character == TileKind CHILD_B
        return TileKind CHILD_B_CLOTH
    if character == TileKind HUMAN_ON_HORSE
        return TileKind HUMAN_ON_HORSE_CLOTH
    _assert(false)
    return TileKind NONE

def processCollisionCircle(var deltaPos : float2&; radius : float; center : float2)
    deltaPos -= center
    processCollisionCircle(deltaPos, radius)
    deltaPos += center
def processCollisionCircle(var deltaPos : float2&; radius : float)
    var deltaPosIso = float2(deltaPos.x, deltaPos.y * topDownYToY)
    var len = length(deltaPosIso)
    if len < radius
        if len < 0.001
            deltaPos = float2(1.0,0.0)
            len = 1.0
        deltaPosIso = deltaPosIso / len * radius
        deltaPos.x = deltaPosIso.x
        deltaPos.y = deltaPosIso.y / topDownYToY
        if deltaPos.x == 0.0
            deltaPos.x = 0.01
        if deltaPos.y == 0.0
            deltaPos.y = 0.01

def processCollisionRect(var deltaPos : float2&; halfSizeX : float; halfSizeY : float)
    var deltaDelta = float2(0.0)
    var changedX = false
    if deltaPos.x > 0.0 && deltaPos.x < halfSizeX
        deltaDelta.x = halfSizeX - deltaPos.x
        changedX = true
    if deltaPos.x < 0.0 && deltaPos.x > -halfSizeX
        deltaDelta.x = -halfSizeX - deltaPos.x
        changedX = true

    if changedX
        if deltaPos.y > 0.0 && deltaPos.y < halfSizeY
            deltaDelta.y = halfSizeY - deltaPos.y
            changedX = false
        if deltaPos.y < 0.0 && deltaPos.y > -halfSizeY
            deltaDelta.y = -halfSizeY - deltaPos.y
            changedX = false

        if !changedX
            deltaDelta *= 1.01
            if abs(deltaDelta.x) > abs(deltaDelta.y)
                deltaPos.y += deltaDelta.y
            else
                deltaPos.x += deltaDelta.x

def processCollision(var charPos : float2&; tile : Tile)
    var deltaPos = charPos - float2(tile.position)
    if tile.kind == TileKind TREE_GREEN || tile.kind == TileKind TREE_YELLOW || tile.kind == TileKind TREE_RED
        processCollisionCircle(deltaPos, 0.3)
    elif tile.kind == TileKind TREE_GREEN_SMALL || tile.kind == TileKind TREE_YELLOW_SMALL || tile.kind == TileKind TREE_RED_SMALL
        processCollisionCircle(deltaPos, 0.25)
    elif tile.kind == TileKind CHEST_IRON || tile.kind == TileKind WOOD || tile.kind == TileKind WHEAT_COLLECTED_6 || tile.kind == TileKind STOVE || tile.kind == TileKind STOVE_WITH_COAL || tile.kind == TileKind STOVE_WITH_COAL_FIRED || tile.kind == TileKind FLOUR
        deltaPos.y -= 0.12
        processCollisionCircle(deltaPos, 0.4)
        deltaPos.y += 0.12
    elif tile.kind == TileKind CAMPFIRE_NO_FIRE || tile.kind == TileKind CAMPFIRE_NO_WOOD || tile.kind == TileKind CAMPFIRE
        deltaPos.y -= 0.12
        processCollisionCircle(deltaPos, 0.45)
        deltaPos.y += 0.12
    elif tile.kind == TileKind FENCE
        if grid_items->getTileInt(tile.position + int2(1, 0)).kind == TileKind FENCE
            deltaPos.x -= 0.5
            processCollisionRect(deltaPos, 0.55, 0.15)
            deltaPos.x += 0.5
        if grid_items->getTileInt(tile.position + int2(0, 1)).kind == TileKind FENCE
            deltaPos.y -= 0.5
            processCollisionRect(deltaPos, 0.15, 0.55)
            deltaPos.y += 0.5
    elif tile.kind == TileKind WATER
        let offset = 0.25
        let radius = 0.4
        processCollisionCircle(deltaPos, radius, float2(offset,offset))
        processCollisionCircle(deltaPos, radius, float2(-offset,offset))
        processCollisionCircle(deltaPos, radius, float2(offset,-offset))
        processCollisionCircle(deltaPos, radius, float2(-offset,-offset))
    elif tile.kind == TileKind BED || tile.kind == TileKind BED_OCCUPIED
        processCollisionCircle(deltaPos, 0.45)
    elif tile.kind == TileKind WOOL || is_bread(tile.kind)
        processCollisionCircle(deltaPos, 0.3)
    
    charPos = float2(tile.position) + deltaPos

def apply_anim(anim : Anim; var pos : float2&; var size : float2&; var angle : float&; var mirrorX : bool&)
    if anim.kind == AnimKind NONE
        return
    
    if anim.kind == AnimKind SQUASH_AND_STRETCH
        var t = (anim.t / anim.stopT) * PI * 2.0
        size.x *= 1.0 + sin(t) * 0.1
        size.y /= 1.0 + sin(t) * 0.1
        //angle = sin(t/3.0) * 0.1
    elif anim.kind == AnimKind TREE_FALL
        var t = (anim.t / anim.stopT)

        var tSize = min(t * PI * 2.0 * 4.0, PI*2.0)
        size.x *= 1.0 + sin(tSize) * 0.1
        size.y /= 1.0 + sin(tSize) * 0.1

        var tAngle = t * PI / 2.0
        angle = tAngle * sin(tAngle)*sin(tAngle)

        var percent = 0.7
        var tSize2 = max(0.0, (t - percent) * (1.0 / (1.0 - percent))) * PI/2.0
        pos.y += sin(tSize2)*0.2
    elif anim.kind == AnimKind PICK
        var t = (anim.t / anim.stopT) * PI * 0.5
        pos.y += sin(t)*0.2
    elif anim.kind == AnimKind APPEAR_FROM_CHEST
        var t = (anim.t / anim.stopT) * PI * 0.5
        pos.y += (1.0 - sin(t)*1.0) * 0.2
    elif anim.kind == AnimKind DEATH
        var t = saturate(anim.t / anim.stopT)
        var tAngle = t * PI / 2.0
        angle = tAngle * sin(tAngle)*sin(tAngle)
    elif anim.kind == AnimKind SLEEP || anim.kind == AnimKind SLEEP_IN_BED
        angle = PI / 2.0
        var offset = get_realtime_since_world_started() % 1.0
        var z_count = 3
        if anim.kind == AnimKind SLEEP_IN_BED
            pos += float2(0.2, 0.4)
            mirrorX = true
        for i in range(z_count)
            var p = pos + float2(float(i)+offset,(float(i)+offset)*0.5) * 0.2 + float2(0.2, 0.0)
            p.y += sin((float(i)+offset) * 4.0) * 0.03
            if mirrorX
                p.x -= 0.5
            else
                p.x += 0.5
            var clip_space_pos = camera->worldToScreen(p)
            var t = (float(i)+offset) / float(z_count)
            var text_color = lerp_colors_fix(0xffffffff, 0x00ffffff, t)
            text_color = lerp_colors_fix(0x00ffffff, text_color, t*10.0)
            text_out(clip_space_pos.x,clip_space_pos.y, "z", text_color)
    elif anim.kind == AnimKind CHAR_JOINED
        var t = saturate(anim.t / anim.stopT)
        //angle = sin(t * PI * 2.0 * 1.0) * 0.2
        size *= (1.0 + sin(t * PI) * 0.3)
        var tmid = (t - 0.5) * 2.0
        pos.y += (1.0 - tmid * tmid) * 1.2


    

def calc_light_from_items(intpos : int2) : float
    var light = 0.0
    for dx in range(-2, +3)
        for dy in range(-2, +3)
            if grid_items->getTileInt(int2(intpos.x + dx,intpos.y + dy)).kind == TileKind CAMPFIRE
                light += 0.4 / (float(dx*dx + dy*dy) + 1.0) * (0.9 + sin(get_time_after_start()*7.0+float(intpos.x + dx)) * 0.05 + sin(get_time_after_start()*6.0 + float(intpos.y + dy)) * 0.05)
    
    for dx in range(-1, +2)
        for dy in range(0, +2)
            if grid_items->getTileInt(int2(intpos.x + dx,intpos.y + dy)).kind == TileKind STOVE_WITH_COAL_FIRED
                light += 0.2 / (float(dx*dx + dy*dy) + 1.0) * (0.9 + sin(get_time_after_start()*7.0+float(intpos.x + dx)) * 0.05 + sin(get_time_after_start()*6.0 + float(intpos.y + dy)) * 0.05)
    return light

def calc_light(pos : float2) : float
    var light = 1.0 - night_percent * 0.4 - rain_percent * 0.2
    light += calc_light_from_items(get_int_pos(pos))
    return min(1.0, light)

def calc_coldness_without_fire(character : Character) : float
    var base = calc_coldness_without_fire(character.position)
    var bed = 0.0
    if character.anim.kind == AnimKind SLEEP_IN_BED
        bed = -0.6
    var cloth = 0.0
    if character.is_wearing_cloth
        cloth = -0.6
    return base + bed + cloth

def calc_coldness(character : Character) : float
    var base = calc_coldness(character.position)
    var bed = 0.0
    if character.anim.kind == AnimKind SLEEP_IN_BED
        bed = -0.3
    var cloth = 0.0
    if character.is_wearing_cloth
        cloth = -0.6
    return base + bed + cloth

def calc_coldness_without_fire(pos : float2) : float
    var rain = rain_percent * 0.4
    var night = night_percent * 0.6
    return rain + night

def calc_coldness(pos : float2) : float
    var fire = calc_light_from_items(get_int_pos(pos)) * 1.5
    return calc_coldness_without_fire(pos) - fire

def get_pivot(kind : TileKind) : float2
    if kind == TileKind TREE_GREEN || kind == TileKind TREE_YELLOW || kind == TileKind TREE_RED
        return float2(0.5,1.0)
    elif kind == TileKind HUMAN || kind == TileKind CHILD_A || kind == TileKind CHILD_B || kind == TileKind HUMAN_CLOTH || kind == TileKind CHILD_A_CLOTH || kind == TileKind CHILD_B_CLOTH
        return float2(0.5,1.0)
    elif kind == TileKind HUMAN_ON_HORSE ||  kind == TileKind HORSE || kind == TileKind SHEEP || kind == TileKind SHEEP_SHEARED || kind == TileKind HUMAN_ON_HORSE_CLOTH
        return float2(0.7,1.0)
    else
        return float2(0.5,0.5)

struct IntPosWithDist
    pos : int2
    dist : int
    expectedDist : float

def dist(from : int2; to : int2) : float
    return length(float2(from - to))

def insert_sorted(var arr : array<IntPosWithDist>; val : IntPosWithDist)
    var i = length(arr)
    while i > 0
        if arr[i-1].expectedDist > val.expectedDist
            push(arr, val, i)
            break
        i--
    if i == 0
        push(arr, val, 0)

def is_fence(kind : TileKind) : bool
    return kind == TileKind FENCE_H || kind == TileKind FENCE_V || kind == TileKind FENCE

def is_walkable_for_a_star(pos : int2; is_human : bool) : bool
    if grid_ground->getTileInt(pos).kind == TileKind WATER
        return false
    var item = grid_items->getTileInt(pos).kind
    if item == TileKind FENCE
        return false
    if !is_human && grid_items->getTileInt(pos + int2(-1, 0)).kind == TileKind FENCE && grid_items->getTileInt(pos + int2(1, 0)).kind == TileKind FENCE
        return false
    if !is_human && grid_items->getTileInt(pos + int2(0, -1)).kind == TileKind FENCE && grid_items->getTileInt(pos + int2(0, 1)).kind == TileKind FENCE
        return false
    if !grid_ground->is_valid(pos)
        return false

    return true

def a_star(from : int2; to : int2; is_human : bool) : array<int2>
    var result : array<int2>
    if from == to
        push(result, to)
        return <- result
    var r : table<int2; int>

    var wip : array<IntPosWithDist>
    var posWithDist : IntPosWithDist
    posWithDist.pos = from
    posWithDist.dist = 0
    posWithDist.expectedDist = dist(from, to)
    push(wip, posWithDist)
    r[from] = 0

    var found_path = false
    var iterations = 0
    let max_iteration = 500
    while !found_path && length(wip) > 0 && iterations < max_iteration
        iterations++
        var current = wip[length(wip)-1]
        pop(wip)
        for dd in range(0, 4)
            let dx = (dd - 1) % 2
            let dy = (dd - 2) % 2
            posWithDist.pos = current.pos + int2(dx,dy)
            posWithDist.dist = current.dist + 1
            posWithDist.expectedDist = float(posWithDist.dist) + dist(posWithDist.pos, to)
            if key_exists(r, posWithDist.pos) && r[posWithDist.pos] <= posWithDist.dist || !is_walkable_for_a_star(posWithDist.pos, is_human)
                continue
            r[posWithDist.pos] = posWithDist.dist
            insert_sorted(wip, posWithDist)
            var screenPos = camera->worldToScreen(float2(posWithDist.pos))
            //text_out(screenPos.x,screenPos.y, "{posWithDist.dist}", 0xffffffff)
            //push(result, posWithDist.pos)
            if posWithDist.pos == to
                found_path = true
                break

        //push(result, current.pos)
        //found_path = true
    iterations = 0
    if found_path
        var currentPos = to
        var currentDist = r[to]
        push(result, currentPos)
        while currentPos != from && iterations < max_iteration
            iterations++
            var minPos : int2
            var minDist = 100000.0
            var dx : int
            var dy : int
            for dd in range(0, 4)
                if iterations % 2 == 0
                    dx = dd / 2 * (dd == 3 ? 1 : -1)
                    dy = (dd == 0 ? 1 : -1) * (dd/2 - 1)
                else
                    dy = dd / 2 * (dd == 3 ? 1 : -1)
                    dx = (dd == 0 ? 1 : -1) * (dd/2 - 1)
                let pos = currentPos + int2(dx, dy)
                if key_exists(r, pos) && r[pos] < currentDist
                    currentPos = pos
                    currentDist = r[pos]
                    break
            
            //var screenPos = camera->worldToScreen(float2(currentPos))
            //text_out(screenPos.x,screenPos.y, "{r[currentPos]}", 0xffffffff)
            push(result, currentPos, 0)
        
        pass

    //log("{length(result)}")
    return <- result

def frac(f : float) : float
    return f - float(int(f))

def is_flag(kind : TileKind) : bool
    return int(kind) >= int(TileKind RED_FLAG) && int(kind) <= int(TileKind BLUE_FLAG)

def get_tile_pos_offset(kind : TileKind) : float2
    if kind == TileKind PLANTED_SEEDS || kind == TileKind WHEAT_SMALL || kind == TileKind WHEAT_MEDIUM || kind == TileKind WHEAT_FULL
        return float2(0.0, -1.0)
    elif kind == TileKind FENCE_H
        return float2(0.5, 0.0)
    elif kind == TileKind BED || kind == TileKind BED_OCCUPIED
        return float2(0.0, -1.0/7.0)
    return float2(0.0, 0.0)

var items_count_cache : table<TileKind; int>

def get_flag_color(kind : TileKind) : uint        
    if kind == TileKind RED_FLAG
        return 0xffff0000
    elif kind == TileKind GREEN_FLAG
        return 0xff00ff00
    elif kind == TileKind BLUE_FLAG
        return 0xff0000ff
    else
        _assert(false)
        return 0xffffffff

def draw_tile(tile : TileFloat)
    var pos = tile.position
    pos.y += tile.z * tileZToY + tile.offsetY
    var kind = tile.kind
    var color = tile.color
    var pivot = get_pivot(kind)

    var angle = 0.0
    var size = float2(1.0,1.0)
    var mirrorX = tile.mirrorX
    apply_anim(tile.anim, pos, size, angle, mirrorX)

    if kind == TileKind DECAL_PREPARED_AND_WATERED_SOIL
        color = lerp_colors_fix(color, 0xff000000, 0.2)
    
    if is_flag(kind)
        color = get_flag_color(kind)

    if kind == TileKind WATER
        pos.y -= tile.z * tileZToY + 0.2
        let mult = 1.0
        let t = (get_realtime_since_world_started())*mult
        let f = frac(t)
        if f > 0.75
            kind = TileKind WATER_4
        elif f > 0.5
            kind = TileKind WATER_3
        elif f > 0.25
            kind = TileKind WATER_2
        color = 0xffffffff

    if kind == TileKind CAMPFIRE
        let mult = 1.5
        let t = (get_realtime_since_world_started() + (pos.x*3.156345 + pos.y*4.842756))*mult
        let f = frac(t)
        mirrorX = frac(t*0.5) > 0.5
        if f > 0.333
            kind = TileKind CAMPFIRE_2
        if f > 0.666
            kind = TileKind CAMPFIRE_3
    elif kind == TileKind STOVE_WITH_COAL_FIRED
        let mult = 1.5
        let t = (get_realtime_since_world_started() + (pos.x*3.156345 + pos.y*4.842756))*mult
        let f = frac(t)
        mirrorX = frac(t*0.5) > 0.5
    else
        color = lerp_colors_fix(0xff000080, color, calc_light(tile.position))//TODO smooth tile.pos for character

    if mirrorX
        size.x = -size.x
        angle = -angle

    size *= float2(tileSizeX,tileSizeY) * camera.scale
    var texture_rect = get_tile_texture_rect(kind)

    pos += get_tile_pos_offset(kind)

    var offset_from_pivot = float2((0.5 - pivot.x), (0.5 - pivot.y) * tileSizeY / tileFloorSizeY)
    if !mirrorX
        offset_from_pivot.x = -offset_from_pivot.x

    var clip_space_pos = camera->worldToScreen(pos + offset_from_pivot)
    if is_collected_wheat(kind)
        text_out(clip_space_pos.x+20.0,clip_space_pos.y + 20.0, "{get_wheat_count(kind)}", color)

    draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, angle, pivot.x, pivot.y)

    if is_bread(kind)
        for i in range(get_bread_count(kind)-1)
            color = lerp_colors_fix(0xff000000, tile.color, calc_light(tile.position) * (1.0 - float(i + 1) / 24.0))
            clip_space_pos = camera->worldToScreen(pos + offset_from_pivot + float2(0.0, float(i+1)*2.0 / 7.0))
            if i % 2 == 0
                clip_space_pos.x += 1.0
            else 
                clip_space_pos.x -= 1.0
            draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, angle, pivot.x, pivot.y)

struct TileWithPriority
    tile : TileFloat
    sub_y_priority : int
    priority : int

var drawTilesQueue : array<TileWithPriority>

def add_to_draw_queue(tile : TileFloat; priority : int; sub_y_priority : int = 0)
    var t : TileWithPriority
    t.tile = tile
    t.priority = priority
    t.sub_y_priority = sub_y_priority
    push(drawTilesQueue, t)

def draw_item_tile(tile : TileFloat; priority : int = 0; sub_y_priority : int = 0)
    var t = tile
    t.offsetY = 1.0
    add_to_draw_queue(t, priority, sub_y_priority)

def is_dead(character : Character) : bool
    return character.anim.kind == AnimKind DEATH

def draw_leash(from : float2; to : float2)
    let subdiv = 16
    var prev_pos = from
    var tension = saturate(length(to-from) / 3.0)
    for i in range(1, subdiv)
        var t = float(i) / float(subdiv - 1)
        var new_pos = lerp(from, to, t)
        new_pos.y -= (1.0 - pow(abs(t-0.5)*2.0, 2.0)) * 0.25 * (1.0-tension)

        var from_pos = camera->worldToScreen(prev_pos)
        var to_pos = camera->worldToScreen(new_pos)
        line(from_pos.x, from_pos.y, to_pos.x, to_pos.y, 0xff333333)
        prev_pos = new_pos


def draw_character(character : Character?)
    var tile = TileFloat()
    
    var runningOffset = min(character.speed, 1.0) * 0.1 * abs(sin(10.0 * get_realtime_since_world_started() * (character.isRunning ? 2.0 : 1.0)))
    if is_dead(*character)
        runningOffset = 0.0
    var picOffsetY = 0.9
    var zOffset = character.z * tileZToY
    var pos = character.position
    var anim : Anim
    tile.mirrorX = character.mirrorX
    tile.position = pos
    tile.offsetY = picOffsetY + runningOffset + zOffset
    tile.kind = character.kind
    tile.color = character.color
    tile.anim = character.anim

    if character.leash != LeashKind NONE && !is_human(character.kind)
        var from_pos = character.position
        from_pos += float2(0.0, 0.4)
        var to_pos = character.leash == LeashKind TO_PLAYER ? player.position : character.leash_to_ground_pos
        to_pos += float2(0.0, 0.2)
        draw_leash(from_pos, to_pos)
    
    if character.carry_item != TileKind NONE
        var carryTile = tile
        carryTile.anim.kind = AnimKind NONE
        carryTile.kind = character.carry_item
        carryTile.z += 1.2
        add_to_draw_queue(carryTile, 0)

    if character.is_name_known
        var name_pos = character.position
        name_pos += float2(0.0, 0.0)
        var clip_space_pos = camera->worldToScreen(name_pos)
        var pp = player.position
        var cp = character.position
        var distance_from_player = length(pp - cp)
        var color = lerp_colors_fix(0xffffffff, 0x00ffffff, (distance_from_player - 5.0) / 4.0)
        text_out(clip_space_pos.x,clip_space_pos.y, "{character.name}", color)

    add_to_draw_queue(tile, 0)
    if character.is_highlighted
        var high = tile
        high.color = 0x60ffffff
        high.kind = get_highlight_kind(tile.kind)
        add_to_draw_queue(high, 0, -2)
    if character.is_wearing_cloth
        var cloth = tile
        cloth.color = 0xffffffff
        cloth.kind = get_cloth_tile(tile.kind)
        add_to_draw_queue(cloth, 0, -1)

def draw_tile_highlight(tile : Tile; color : uint = 0xffffffff)
    var t = Tile()
    t.position = tile.position
    t.z = tile.z
    t.color = color
    t.kind = TileKind TILE_SELECTION
    add_to_draw_queue(to_tile_float(t), 1, -1)

def draw_grid(color : uint)
    var cameraPosX = int(camera.position.x)
    var cameraPosY = int(camera.position.y)
    for x in range(cameraPosX-20,cameraPosX+20)
        for y in range(cameraPosY-20,cameraPosY+20)
            var pos1A = float2(float(x-100), float(y))
            var pos1B = float2(float(x+100), float(y))
            var pos2A = float2(float(x), float(y-100))
            var pos2B = float2(float(x), float(y+100))
            pos1A = camera->worldToScreen(pos1A)
            pos2A = camera->worldToScreen(pos2A)
            pos1B = camera->worldToScreen(pos1B)
            pos2B = camera->worldToScreen(pos2B)
            line(pos1A.x, pos1A.y, pos1B.x, pos1B.y, color)
            line(pos2A.x, pos2A.y, pos2B.x, pos2B.y, color)

var ui_scale = 3.0
var ui_tile_size = float2(tileSizeX,tileSizeY) * ui_scale

//return new y
def draw_character_stats(character : Character?; _pos : float2; invertX : bool) : float
    let max_health = 6
    let max_hunger = 6
    var time = get_time_after_start()

    var texture_rect : float4 
    var health = ceili(character.health * float(max_health))
    var hunger = max_hunger - floori(character.hunger * float(max_hunger))
    var color = 0xffffffff
    var deltaX = 16.0
    var size = ui_tile_size 
    var pos = _pos
    if invertX
        deltaX = -deltaX
        //size.x = -size.x
        pos.x = float(get_screen_width()) / ui_scale - pos.x

    var is_loosing_health = hunger == 0
    if is_loosing_health && health > 0 && time % 1.0 > 0.5
        health = health - 1

    if pause_menu != null
        var clip_space_pos = float2(pos.x - 0.5, pos.y)*ui_scale
        clip_space_pos.x -= 28.0
        clip_space_pos.x += invertX ? -8.0 : 8.0
        text_out(clip_space_pos.x, clip_space_pos.y, "HEALTH", 0xffffffff)
        pos.y += 5.0

    for i in range(0, max_health / 2)
        if health >= i * 2 + 2
            texture_rect = get_tile_texture_rect(TileKind HEART_FULL)
        elif health == i * 2 + 1
            texture_rect = get_tile_texture_rect(TileKind HEART_HALF)
        else
            texture_rect = get_tile_texture_rect(TileKind HEART_EMPTY)

        var clip_space_pos = float2(pos.x + deltaX * float(i), pos.y)*ui_scale

        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0.0, 0.5f,0.5f)

    pos.y += 14.0
    pos.y += 2.0
    
    if pause_menu != null
        var clip_space_pos = float2(pos.x - 0.5, pos.y)*ui_scale
        clip_space_pos.x -= 28.0
        clip_space_pos.x += invertX ? -8.0 : 8.0
        text_out(clip_space_pos.x, clip_space_pos.y, "HUNGER", 0xffffffff)
        pos.y += 5.0
    //hunger
    for i in range(0, max_hunger / 2)
        var blinkFreq = 2.0
        var isBlinking = player.isRunning && !is_on_horse(*player) && ((time * blinkFreq) - float(floori(time * blinkFreq))) > 0.5
        isBlinking = isBlinking && (max(0, hunger - 1) / 2 == i)
        color = isBlinking ?  0x33ffffff : 0xffffffff
        if hunger >= i * 2 + 2
            texture_rect = get_tile_texture_rect(TileKind HUNGER_FULL)
        elif hunger == i * 2 + 1
            texture_rect = get_tile_texture_rect(TileKind HUNGER_HALF)
        else
            texture_rect = get_tile_texture_rect(TileKind HUNGER_EMPTY)
        var clip_space_pos = float2(pos.x - 0.5 + deltaX * float(i), pos.y)*ui_scale
        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0.0, 0.5f,0.5f)
        
    pos.y += 14.0
    if is_freezing(*character)
        pos.y += 3.0
        var snowflake_scale = 2.0/3.0
        var clip_space_pos = float2(pos.x, pos.y) * ui_scale

        texture_rect = get_tile_texture_rect(TileKind UI_SNOWFLAKE)
        var blink_period = 1.0
        var c = lerp_colors_fix(0x00ffffff, 0xffffffff, sin(get_time_after_start() * 2.0 * PI / blink_period) * 0.2 + 0.8)
        //if get_time_after_start() % blink_period > blink_period / 2.0
        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, c, size * snowflake_scale, 0.0, 0.5f,0.5f)
        var text_pos = float2(clip_space_pos.x + size.x * snowflake_scale - 15.0, clip_space_pos.y + 5.0)
        if invertX
            text_pos.x -= 120.0
        text_out(text_pos.x, text_pos.y, "FREEZING", c)
        pos.y += 14.0 * snowflake_scale

    pos.y += 3.0
    return pos.y * ui_scale

def draw_tile_kind_info(kind : TileKind; _pos : float2)
    var color = 0xffffffff
    if is_flag(kind)
        color = get_flag_color(kind)
    var pos = _pos 
    pos.x = float(get_screen_width()) / ui_scale - pos.x
    pos -= get_tile_pos_offset(kind) * float2(tileSizeX, tileSizeY) * 0.5
    var size = ui_tile_size 
    var texture_rect = get_tile_texture_rect(kind)
    var clip_space_pos = float2(pos.x - 1.0,0.0 + pos.y)*ui_scale
    draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0.0, 0.5f,0.5f)

    pos = _pos
    pos.y += 44.0
    var tile_name = readable_tile_name(kind)
    text_out(get_screen_width() - int(get_text_size(tile_name).x) - 10, int(pos.y), tile_name, 0xffffffff)

var avg_hunger = 0.0
var avg_health = 0.0
var population = 0

def ui_draw_world_state(var y : int&)
    var hour_float = get_current_hour_float()
    var hour = int(hour_float)
    var minute_delta = 15
    var minute = int((hour_float - float(hour)) * 60.0 / float(minute_delta)) * minute_delta
    var minute_str = "{minute}"
    if minute == 0
        minute_str = "00"
    var day = int(world_state.day_float)
    var time_str : string
    text_out(10,y, "{hour}:{minute_str} day {day}", 0xffffffff)
    y += 20

    var weather_state = ""
    if is_morning_time()
        weather_state = "morning"
    elif is_day_time()
        weather_state = "day"
    elif is_evening_time()
        weather_state = "evening"
    else
        verify(is_night_time())
        weather_state = "night"
    if rain_percent > 0.5
        weather_state += ", rainy"
    text_out(10,y, "{weather_state}", 0xffffffff)
    y += 20

    if is_tutorial_finished()
        text_out(10,y, "population: {population}", 0xffffffff)
        y += 20     
        if population > 0
            //var s = format("", avg_hunger)
            var avg_hunger_str = "{roundi(avg_hunger*30.0)/10}.{roundi(avg_hunger*30.0)%10}"
            var avg_health_str = "{roundi(avg_health*30.0)/10}.{roundi(avg_health*30.0)%10}"
            text_out(10,y, "average hunger: {avg_hunger_str}/3", 0xffffffff)
            y += 20    
            text_out(10,y, "average health: {avg_health_str}/3", 0xffffffff)
            y += 20
            
            var new_human_percent = world_state.good_health_and_no_hunger_duration / good_health_and_no_hunger_to_new_human_duration
            text_out(10,y, "new villager: {int(new_human_percent * 100.0)}%", 0xffffffff)
            y += 20

def draw_ui_character_stats(var pos : float2&; var y : int&)
    y = int(draw_character_stats(player, pos, false))

    let alt_action_result = _alt_action(*player, invalid_tile_pos, false)
    if alt_action_result.is_valid
        var npc = alt_action_result.target_char
        if current_dialog != null
            npc = current_dialog.character
        if npc != null
            draw_character_stats(npc, float2(10.0,0.0), true)
            if npc.is_name_known
                text_out(get_screen_width() - int(get_text_size(npc.name).x) - 10, y, npc.name, 0xffffffff)
            clear(dbg_msg)
            log(npc.dbg_str)
        elif alt_action_result.has_target_item_pos
            var target_item = grid_items->getTileInt(alt_action_result.target_item_pos).kind
            if target_item != TileKind NONE
                draw_tile_kind_info(target_item, float2(10.0,0.0))

def draw_ui()
    var pos = float2(10.0,0.0)
    var y = int(pos.x)

    var is_in_main_menu = pause_menu != null && pause_menu.is_main_menu

    if !is_in_main_menu
        draw_ui_character_stats(pos, y)
        ui_draw_world_state(y)
        
    if dbg_mode
        for i in range(length(dbg_msg))
            text_out(10,y, dbg_msg[length(dbg_msg) - i-1], 0xffffffff)
            y += ui_count_lines(dbg_msg[length(dbg_msg) - i-1]) * text_height

    var last_msg_time = get_time_after_start()
    if length(game_msg) > 0
        last_msg_time = game_msg[length(game_msg) - 1].time_after_start
    
    var fade_in_time = 0.2
    var first_msg_appear_t = saturate((get_time_after_start() - last_msg_time) / fade_in_time)
    var fade_out_time = 1.0
    var no_erase_count = 3

    if !is_in_main_menu
        text_out(10,y, "-------", 0xffffffff)
        y += 20

        y -= 20
        y += roundi(20.0 * first_msg_appear_t)
        for i in range(length(game_msg))
            let msg = game_msg[length(game_msg) - i-1]
            var fade_t = (get_time_after_start() - msg.time_after_start) / fade_out_time
            fade_t = 1.0 - saturate((fade_t - 0.5) * 2.0)
            if i < no_erase_count
                if fade_t <= 0.99
                    fade_t = 1.0
                    game_msg[length(game_msg) - i-1].time_after_start = get_time_after_start() - fade_out_time / 2.0
            fade_t *= (saturate((get_time_after_start() - msg.time_after_start) / fade_in_time) - 0.5) * 2.0
            var text_color = lerp_colors_fix(0x00ffffff, 0xffffffff, fade_t)
            text_out(10,y, msg.str, text_color)
            y += 20

        var num_erased = 0
        var ii = length(game_msg)-1
        while ii >= no_erase_count
            if game_msg[ii].time_after_start + fade_out_time < get_time_after_start()
                erase(game_msg, ii)
            ii--

    if true
        var current_goal = get_current_goal_str()
        if !empty(current_goal)
            var text_size = get_text_size(current_goal)
            var text_pos = int2(get_screen_width() / 2 - int(text_size.x / 2.0) , 20)
            let border_inc = 5.0
            fill_rect(float(text_pos.x) - border_inc, float(text_pos.y) - border_inc, text_size.x + border_inc * 2.0, text_size.y + border_inc * 2.0 ,0xa0000000)
            text_out(text_pos.x, text_pos.y, current_goal, 0xffffffff)


    if pause_menu != null
        ui_draw_pause_menu()
    elif ui_tutorial != null
        ui_draw_tutorial_msg()
    elif current_dialog != null
        ui_draw_dialog(*current_dialog)

var current_dialog : DialogStateGeneric?


enum DialogFirstAction
    NONE
    WHAT_ARE_YOU_DOING
    PUT
    BRING
    MAKE
    CUT
    PLOW
    PLANT

def dialog_first_action_readable(action : DialogFirstAction) : string
    if action == DialogFirstAction WHAT_ARE_YOU_DOING
        return "WHAT ARE YOU DOING?"
    return replace("{action}", "_", " ")

class DialogStateGeneric
    character : AiCharacter?
    show_char_name : bool = true

    i_current_option : int = 1
    ui_message : string
    ui_options : array<string>
    ui_blocked_options : array<string>
    ui_prev_options_offset : int

    def update() : bool
        return false

class TutorialDialogState : DialogStateGeneric
    current_line_idx : int
    character_lines : array<string>
    player_lines : array<string>

    def override update() : bool
        _assert(current_line_idx < length(character_lines))
        _assert(length(player_lines) == length(character_lines))

        clear(ui_options)
        i_current_option = 0

        ui_message = character_lines[current_line_idx]
        push(ui_options, player_lines[current_line_idx])

        if dialog_down_pressed() || dialog_up_pressed()
            play_sound(SoundKind UI_BLOCKED, player.position)


        if !dialog_accept_pressed()
            return false

        play_sound(SoundKind UI_CLICK, player.position)

        current_line_idx = min(current_line_idx + 1, length(character_lines))
        
        return current_line_idx == length(character_lines)

class DialogState : DialogStateGeneric
    had_greeting : bool

    first_action : DialogFirstAction
    first_action_tile_kind : TileKind
    second_action_tile_kind : TileKind

    to_pressed : bool

    finished : bool

    tutorial_do_once : bool
    tutorial_make_campfire_only : bool
    
    def override update() : bool
        var still_running = update_dialog(self)
        if finished
            var command = ai_command_from_dialog(self)
            if tutorial_do_once
                command.do_once = true
            character.command = command
        return still_running

def ai_command_to_str(command : AiCommand)
    //TODO more generic and less manual way
    if command.kind == AiCommandKind NONE
        return "NOTHING SPECIAL"
    elif command.kind == AiCommandKind BRING_A_TILE_TO_B_TILE
        if command.a_tile == TileKind FLINT_STONE && command.b_tile == TileKind WOOD
            return "I MAKE FIRE"
        elif command.a_tile == TileKind WOOD && command.b_tile == TileKind WOOD
            return "I MAKE FENCES"
        else
            return "I BRING {readable_tile_name(command.a_tile)} TO {readable_tile_name(command.b_tile)}"
    elif command.kind == AiCommandKind DO_DEFAULT_ACTION_ON_A_TILE
        if item_is(command.a_tile, TileKind TREE)
            return "I CUT TREES"
        elif item_is(command.a_tile, TileKind WHEAT_FULL)
            return "I CUT WHEAT"
        else
            return "I DO {command.a_tile}"
    elif command.kind == AiCommandKind MAKE_WHEAT_STACKS
        return "I MAKE WHEAT STACKS"
    elif command.kind == AiCommandKind PLOW_GROUND
        return "I PLOW GROUND"
    elif command.kind == AiCommandKind PLANT_WHEAT
        return "I PLANT WHEAT"
    elif command.kind == AiCommandKind MAKE_FIRE
        return "I MAKE FIRE"
    elif command.kind == AiCommandKind MAKE_BREAD
        return "I MAKE BREAD"

    _assert(false)
    return "SOMETHING IMPORTANT"


def ai_command_from_dialog(dialog : DialogState) : AiCommand
    //TODO more generic and less manual way
    if dialog.first_action == DialogFirstAction PUT || dialog.first_action == DialogFirstAction BRING
        return ai_command_bring_a_to_b(dialog.first_action_tile_kind, dialog.second_action_tile_kind)
    elif dialog.first_action == DialogFirstAction CUT
        return ai_command_do_default_action_on_a(dialog.first_action_tile_kind)
    elif dialog.first_action == DialogFirstAction MAKE
        if dialog.first_action_tile_kind == TileKind FIRE
            var cmd : AiCommand
            cmd.kind = AiCommandKind MAKE_FIRE
            return cmd
        elif dialog.first_action_tile_kind == TileKind FENCE
            return ai_command_bring_a_to_b(TileKind WOOD, TileKind WOOD)
        elif dialog.first_action_tile_kind == TileKind WHEAT_STACK
            return ai_command_make_wheat_stacks()
        elif dialog.first_action_tile_kind == TileKind BREAD
            var cmd : AiCommand
            cmd.kind = AiCommandKind MAKE_BREAD
            return cmd
    elif dialog.first_action == DialogFirstAction PLOW
        _assert(dialog.first_action_tile_kind == TileKind SOIL)
        return ai_command_plow_ground()
    elif dialog.first_action == DialogFirstAction PLANT
        return ai_command_plant_wheat()
        
            
    _assert(false)
    var command : AiCommand
    return command

def readable_tile_name_for_craft(kind : TileKind) : string
    if kind == TileKind DECAL_PREPARED_SOIL
        return "SOIL"
    elif kind == TileKind DECAL_PREPARED_AND_WATERED_SOIL
        return "WATERED SOIL"
    elif kind == TileKind CAMPFIRE_NO_WOOD
        return "EMPTY CAMPFIRE"
    elif kind == TileKind CAMPFIRE
        return "STARTED CAMPFIRE"
    elif kind == TileKind BREAD_6
        return "BREAD"
    return readable_tile_name(kind)

def readable_tile_name(kind : TileKind) : string
    var str = ""
    if kind == TileKind WHEAT_COLLECTED_6
        str = "WHEAT STACK"
    elif is_collected_wheat(kind)
        str = "WHEAT"
    elif kind == TileKind WHEAT_FULL
        str = "WHEAT"
    elif kind == TileKind WHEAT_MEDIUM || kind == TileKind WHEAT_SMALL
        str = "YOUNG WHEAT"
    elif kind == TileKind CAMPFIRE || kind == TileKind CAMPFIRE_NO_FIRE || kind == TileKind CAMPFIRE_NO_WOOD
        str = "CAMPFIRE"
    elif kind == TileKind BUCKET_EMPTY
        return "BUCKET"
    elif kind == TileKind STOVE
        return "EMPTY STOVE"
    elif kind == TileKind STOVE_WITH_COAL_FIRED
        return "TURNED ON STOVE"
    elif is_human(kind)
        return "VILLAGER"
    else
        str = replace("{kind}", "_", " ")
    return str;

//returns true if dialog finished
def update_dialog(var dialog_state : DialogState) : bool
    clear(dialog_state.ui_options)
    clear(dialog_state.ui_blocked_options)

    dialog_state.ui_message = ""

    var bringable_items : array<TileKind>
    var puttable_items : array<TileKind>
    push(bringable_items, TileKind WHEAT_STACK)
    push(bringable_items, TileKind BREAD)
    for e in each_enum(type<TileKind>)
        if is_big_item(e) && !is_collected_wheat(e) && !is_bread(e) && !is_flag(e) && e != TileKind CAMPFIRE && e != TileKind CAMPFIRE_NO_WOOD && e != TileKind CAMPFIRE_NO_FIRE && e != TileKind STOVE && e != TileKind STOVE_WITH_COAL && e != TileKind STOVE_WITH_COAL_FIRED && e != TileKind FENCE
            push(bringable_items, e)

    for e1 in each_enum(type<TileKind>)
        for e2 in each_enum(type<TileKind>)
            let e = e1
            if is_big_item(e) && !is_collected_wheat(e) && !is_bread(e) && !is_flag(e) && e != TileKind CAMPFIRE && e != TileKind CAMPFIRE_NO_WOOD && e != TileKind CAMPFIRE_NO_FIRE && e != TileKind STOVE && e != TileKind STOVE_WITH_COAL && e != TileKind STOVE_WITH_COAL_FIRED && e != TileKind FENCE
                if can_combine(e1, e2)
                    push(puttable_items, e1)
                    break

    var bringtoable_flags : array<TileKind>
    for e in each_enum(type<TileKind>)
        if is_flag(e) && items_count_cache[e] > 0
            push(bringtoable_flags, e)

    
    
    var makeable_items : array<TileKind>
    push(makeable_items, TileKind FIRE)
    push(makeable_items, TileKind FENCE)
    push(makeable_items, TileKind WHEAT_STACK)
    push(makeable_items, TileKind BREAD)

    var cutable_items : array<TileKind>
    push(cutable_items, TileKind TREE)
    push(cutable_items, TileKind WHEAT_FULL)

    var plantable_items : array<TileKind>
    push(plantable_items, TileKind WHEAT_FULL)

    var plowable_items : array<TileKind>
    push(plowable_items, TileKind SOIL)

    var has_second = dialog_state.first_action == DialogFirstAction PUT || dialog_state.first_action == DialogFirstAction BRING
    var has_first = dialog_state.first_action != DialogFirstAction WHAT_ARE_YOU_DOING

    var first_tile_source_array : array<TileKind>
    if dialog_state.first_action == DialogFirstAction PUT
        first_tile_source_array <- puttable_items
    elif dialog_state.first_action == DialogFirstAction BRING
        first_tile_source_array <- bringable_items
    elif dialog_state.first_action == DialogFirstAction CUT
        first_tile_source_array <- cutable_items
    elif dialog_state.first_action == DialogFirstAction MAKE
        first_tile_source_array <- makeable_items
    elif dialog_state.first_action == DialogFirstAction PLOW
        first_tile_source_array <- plowable_items
    elif dialog_state.first_action == DialogFirstAction PLANT
        first_tile_source_array <- plantable_items
    
    push(dialog_state.ui_options, "<BACK>")
    if !dialog_state.had_greeting
        push(dialog_state.ui_options, "HI, {to_upper(dialog_state.character.name)}")
    elif dialog_state.first_action == DialogFirstAction NONE
        for e in each_enum(type<DialogFirstAction>)
            if e == DialogFirstAction NONE
                continue
            push(dialog_state.ui_options, dialog_first_action_readable(e))
            if dialog_state.tutorial_make_campfire_only && e != DialogFirstAction PUT
                push(dialog_state.ui_blocked_options, dialog_first_action_readable(e))
    elif dialog_state.first_action_tile_kind == TileKind NONE && has_first
        for e in first_tile_source_array
            push(dialog_state.ui_options, "{readable_tile_name(e)}")
            if dialog_state.tutorial_make_campfire_only && e != TileKind WOOD
                push(dialog_state.ui_blocked_options, "{readable_tile_name(e)}")

    elif !dialog_state.to_pressed && has_second && has_first
        if dialog_state.first_action == DialogFirstAction PUT
            push(dialog_state.ui_options, "ON")
        else
            push(dialog_state.ui_options, "TO")
    elif dialog_state.second_action_tile_kind == TileKind NONE && has_second && has_first
        if dialog_state.first_action == DialogFirstAction PUT
            for e in each_enum(type<TileKind>)
                if can_combine(dialog_state.first_action_tile_kind, e)
                    push(dialog_state.ui_options, "{readable_tile_name(e)}")
                    if dialog_state.tutorial_make_campfire_only && e != TileKind STONE
                        push(dialog_state.ui_blocked_options, "{readable_tile_name(e)}")
        else
            _assert(dialog_state.first_action == DialogFirstAction BRING)
            for e in bringtoable_flags
                if e != dialog_state.first_action_tile_kind
                    push(dialog_state.ui_options, "{readable_tile_name(e)}")
                    if dialog_state.tutorial_make_campfire_only
                        push(dialog_state.ui_blocked_options, "{readable_tile_name(e)}")
    else
        push(dialog_state.ui_options, "<DONE>")
    
    if dialog_state.tutorial_make_campfire_only
        if dialog_state.first_action == DialogFirstAction NONE
            push(dialog_state.ui_blocked_options, "<BACK>")
        
        pass

    //elif dialog_state.first_action_tile_kind
    dialog_state.show_char_name = true
    if dialog_state.first_action != DialogFirstAction NONE
        dialog_state.show_char_name = false
        dialog_state.ui_message += "{dialog_state.first_action}"
    if dialog_state.first_action_tile_kind != TileKind NONE
        dialog_state.ui_message += " {readable_tile_name(dialog_state.first_action_tile_kind)}"
    if dialog_state.to_pressed
        if dialog_state.first_action == DialogFirstAction PUT
            dialog_state.ui_message += " ON"
        if dialog_state.first_action == DialogFirstAction BRING
            dialog_state.ui_message += " TO"
    if dialog_state.second_action_tile_kind != TileKind NONE
        dialog_state.ui_message += " {readable_tile_name(dialog_state.second_action_tile_kind)}"

    if dialog_state.first_action == DialogFirstAction WHAT_ARE_YOU_DOING
        dialog_state.ui_message = ai_command_to_str(dialog_state.character.command)


    if dialog_state.ui_message == ""
        if !dialog_state.had_greeting
            if dialog_state.character.is_name_known
                dialog_state.ui_message = "HI, HOW CAN I HELP?"
            else
                dialog_state.ui_message = "HI, MY NAME IS {dialog_state.character.name}. HOW CAN I HELP?"
        else
            dialog_state.ui_message = "HOW CAN I HELP?"
            if dialog_state.tutorial_make_campfire_only
                dialog_state.ui_message = "WHAT SHOULD I DO?"

    if dialog_state.ui_message == ""
        _assert(false)
        dialog_state.ui_message = "???"
    
    var tried_to_move = false
    var prev_opt = dialog_state.i_current_option
    if dialog_up_pressed()
        dialog_state.i_current_option -= 1
        tried_to_move = true
    if dialog_down_pressed()
        dialog_state.i_current_option += 1
        tried_to_move = true
    dialog_state.i_current_option = clamp(dialog_state.i_current_option, 0, length(dialog_state.ui_options)-1)
    if tried_to_move
        if prev_opt != dialog_state.i_current_option
            play_sound(SoundKind UI_MOVE, player.position)
        else
            play_sound(SoundKind UI_BLOCKED, player.position)

    if !dialog_accept_pressed()
        return false
    
    if find_index(dialog_state.ui_blocked_options, dialog_state.ui_options[dialog_state.i_current_option]) != -1
        play_sound(SoundKind UI_BLOCKED, player.position)
        return false
    play_sound(SoundKind UI_CLICK, player.position)

    if !dialog_state.had_greeting
        dialog_state.character.is_name_known = true
        if 0 == dialog_state.i_current_option
            return true
        else
            dialog_state.had_greeting = true
    elif dialog_state.first_action == DialogFirstAction NONE
        if 0 == dialog_state.i_current_option
            return true
        else
            var idx = 0
            for e in each_enum(type<DialogFirstAction>)
                if dialog_state.i_current_option == idx
                    dialog_state.first_action = e
                    break
                idx++
    elif dialog_state.first_action_tile_kind == TileKind NONE && has_first
        if 0 == dialog_state.i_current_option
            dialog_state.first_action = DialogFirstAction NONE
        else
            for i in range(length(first_tile_source_array))
                if dialog_state.i_current_option == i + 1
                    dialog_state.first_action_tile_kind = first_tile_source_array[i]
                    break
    elif !dialog_state.to_pressed && has_second
        if 0 == dialog_state.i_current_option
            dialog_state.first_action_tile_kind = TileKind NONE
        else
            dialog_state.to_pressed = true
    elif dialog_state.second_action_tile_kind == TileKind NONE && has_second
        if 0 == dialog_state.i_current_option
            dialog_state.to_pressed = false
        else
            var idx = 1
            if dialog_state.first_action == DialogFirstAction PUT
                for e in each_enum(type<TileKind>)
                    if can_combine(dialog_state.first_action_tile_kind, e)
                        if dialog_state.i_current_option == idx
                            dialog_state.second_action_tile_kind = e
                        idx++
            else
                _assert(dialog_state.first_action == DialogFirstAction BRING)
                for e in bringtoable_flags
                    if dialog_state.i_current_option == idx
                        dialog_state.second_action_tile_kind = e
                    idx++
    else
        if 0 == dialog_state.i_current_option
            dialog_state.second_action_tile_kind = TileKind NONE
            if !has_second
                dialog_state.first_action_tile_kind = TileKind NONE
            if !has_first
                dialog_state.first_action = DialogFirstAction NONE
        else
            dialog_state.finished = dialog_state.first_action != DialogFirstAction WHAT_ARE_YOU_DOING
            return true

    dialog_state.i_current_option = 1
    dialog_state.ui_prev_options_offset = 1
    return false

def draw_rain()
    if rain_percent <= 0.0
        return
    var color = lerp_colors_fix(0x00868686, 0xFF6E6E6E, rain_percent)
    var size = float2(1.0,1.0)
    size *= float2(tileSizeX,tileSizeY) * camera.scale
    var texture_rect = get_tile_texture_rect(TileKind RAIN_EFFECT)
    var countX = 26
    var countY = 12
    var offset = get_realtime_since_world_started() * float2(0.0, 1.0) * 120.0 * 5.0

    var orig_pos = camera->worldToScreen(float2(0.0,0.0))
    offset += orig_pos

    offset.x = ((offset.x % size.x) + size.x) % size.x
    offset.y = (offset.y % size.y)

    for x in range(-2, countX-2)
        for y in range(-2, countY-2)
            var pos = float2(float(x) * size.x + offset.x, float(y) * size.y + offset.y)
            draw_image_region(tiles, pos.x, pos.y,texture_rect, color, size)

def ui_draw_dialog(var dialog_state : DialogStateGeneric)
    var main_text_pos = int2(get_screen_width() / 2, get_screen_height() - 300)
    var msg = dialog_state.ui_message
    if dialog_state.show_char_name
        msg = dialog_state.character.name + ": " + msg 
    main_text_pos.x -= int(get_text_size(msg).x / 2.0)
    text_out(main_text_pos.x,main_text_pos.y, msg, 0xffffffff)
    
    var options_text_pos = int2(get_screen_width() / 2 - 100, get_screen_height() - 250)
    var max_options_visible = 5
    var y_offset = 30
    var i_first = max(dialog_state.i_current_option - 1, 0)
    var i_last = min(dialog_state.i_current_option + 1, length(dialog_state.ui_options) - 1)

    if i_last == length(dialog_state.ui_options) - 1 || dialog_state.ui_prev_options_offset + max_options_visible <= i_last
        i_first = max(0, i_last - max_options_visible + 1)
    elif i_first == 0 || dialog_state.ui_prev_options_offset >= i_first
        i_last = min(i_first + max_options_visible - 1, length(dialog_state.ui_options) - 1)
    else
        i_first = dialog_state.ui_prev_options_offset
        i_last = min(i_first + max_options_visible - 1, length(dialog_state.ui_options) - 1)

    dialog_state.ui_prev_options_offset = i_first

    for i in range(i_first, i_last + 1)
        var y = options_text_pos.y + y_offset * (i - i_first)
        var option = dialog_state.ui_options[i]
        if dialog_state.i_current_option == i
            option = "[*] " + option
        else
            option = "[ ] " + option
        var is_blocked = find_index(dialog_state.ui_blocked_options, dialog_state.ui_options[i]) != -1
        var color = is_blocked ? 0x80ffffff : 0xffffffff
        text_out(options_text_pos.x,y, option, color)
    if i_first > 0
        text_out(options_text_pos.x,options_text_pos.y - y_offset, "    ▲", 0xffffffff)
    if i_last < length(dialog_state.ui_options) - 1
        text_out(options_text_pos.x,options_text_pos.y + y_offset * max_options_visible, "    ▼", 0xffffffff)
        

    pass

var camFSizeX = 42.0
var camFSizeY = 32.0

def get_min_culled() : int2
    var p = int2(floori(camera.position.x - camFSizeX / camera.scale), floori(camera.position.y - camFSizeY / camera.scale))
    p.x = clamp(p.x, 0, grid_ground.width)
    p.y = clamp(p.y, 0, grid_ground.height)
    return p

def get_max_culled() : int2
    var p = int2(ceili(camera.position.x + camFSizeX / camera.scale), ceili(camera.position.y + camFSizeY / camera.scale))
    p.x = clamp(p.x, 0, grid_ground.width)
    p.y = clamp(p.y, 0, grid_ground.height)
    return p

def is_culled(pos : float2) : bool
    return abs(camera.position.x - pos.x) * camera.scale > camFSizeX || abs(camera.position.y - pos.y) * camera.scale > camFSizeY

def is_culled(pos : int2) : bool
    return abs(camera.position.x - float(pos.x)) * camera.scale > camFSizeX || abs(camera.position.y - float(pos.y)) * camera.scale > camFSizeY

def draw_item_fence(tile : Tile)
    var u = grid_items->getTileInt(tile.position + int2(0,1))
    var d = grid_items->getTileInt(tile.position + int2(0,-1))
    var l = grid_items->getTileInt(tile.position + int2(-1,0))
    var r = grid_items->getTileInt(tile.position + int2(1,0))

    var t = to_tile_float(tile)
    if r.kind == TileKind FENCE
        t.kind = TileKind FENCE_H
        draw_item_tile(t, 0, 1)

    if u.kind == TileKind FENCE
        t.kind = TileKind FENCE_V
        draw_item_tile(t)

    if u.kind != TileKind FENCE && d.kind != TileKind FENCE && l.kind != TileKind FENCE && r.kind != TileKind FENCE
        draw_item_tile(t)


[export]
def draw
    clear(drawTilesQueue)
    enable_alpha_blend()
    fill_rect(0, 0, get_screen_width(), get_screen_height(), 0xff204020)
    if draw_grid
        draw_grid(0xffffffff)

    var time = get_time_after_start()

    var min_culled = get_min_culled()
    var max_culled = get_max_culled()
    
    for ix in range(min_culled.x, max_culled.x + 1)
        var iy = max_culled.y
        while iy >= min_culled.y
            draw_tile(to_tile_float(grid_ground->getTileInt(int2(ix, iy))))
            draw_tile(to_tile_float(grid_ground_decals->getTileInt(int2(ix, iy))))
            iy -= 1

    for ix in range(min_culled.x, max_culled.x)
        var iy = max_culled.y
        while iy >= min_culled.y
            var tile = grid_items->getTileInt(int2(ix, iy))
            if tile.kind == TileKind FENCE
                draw_item_fence(tile)
            elif tile.kind != TileKind NONE
                draw_item_tile(to_tile_float(tile))
            iy -= 1
            
    for ch in characters
        if is_culled(ch.position)
            continue
        draw_character(ch)

    if dbg_mode
        if dbg_pathfinding
            for ch in aiCharacters
                if length(ch.target_position - ch.position) > 1.0
                    var path : array<int2>
                    path <- a_star(grid_ground->getIntPos(ch.position), grid_ground->getIntPos(ch.target_position))
            var path <- a_star(get_int_pos(player.position), int2(grid_ground.width / 2, grid_ground.height / 2+5))
            for pos in path
                draw_tile_highlight(grid_ground->getTileInt(pos))

        for pos in dbg_highlighted_tiles
            draw_tile_highlight(grid_ground->getTileInt(pos))
    clear(dbg_highlighted_tiles)

    clear_alt_action_highlight()
    if can_do_alt_action(*player, invalid_tile_pos)
        draw_alt_action_highlight()

    sort(drawTilesQueue, $(a,b)=>a.priority==b.priority && (a.tile.position.y>b.tile.position.y || a.tile.position.y==b.tile.position.y && a.sub_y_priority>b.sub_y_priority) || a.priority>b.priority)

    for tile in drawTilesQueue
        draw_tile(tile.tile)

    if draw_grid
        draw_grid(0x08ffffff)

    draw_rain()

    draw_ui()
