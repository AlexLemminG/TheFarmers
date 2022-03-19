require math

options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

enum TileKind
    NONE
    GRASS
    WATER
    WATER_2
    WATER_3
    WATER_4
    SOIL
    HUMAN
    CHILD_A
    CHILD_B
    WOOD
    TREE_GREEN
    TREE
    TREE_YELLOW
    TREE_RED
    CHEST_IRON
    TILE_SELECTION
    FENCE
    FENCE_H
    FENCE_V
    DECAL_SMALL
    DECAL_BIG
    DECAL_PREPARED_SOIL
    HEART_FULL
    HEART_HALF
    HEART_EMPTY
    HUNGER_FULL
    HUNGER_HALF
    HUNGER_EMPTY
    PLANTED_SEEDS
    WHEAT_SMALL
    WHEAT_MEDIUM
    WHEAT_FULL
    WHEAT_COLLECTED_1
    WHEAT_COLLECTED_2
    WHEAT_COLLECTED_3
    WHEAT_COLLECTED_4
    WHEAT_COLLECTED_5
    WHEAT_COLLECTED_6
    WHEAT_HAY //special
    WHEAT_COLLECTED_NOT_6 //special
    WHEAT //special
    GOLD
    HORSE
    SHEEP
    HUMAN_ON_HORSE
    UI_NIGHT
    UI_DAY
    UI_RAIN
    UI_BORDER
    CAMPFIRE
    CAMPFIRE_2
    CAMPFIRE_3
    FLINT_STONE
    BUCKET_EMPTY
    BUCKET_WITH_WATER
    WOODEN_PLANE
    COAL
    BUSH
    BUSH_WITH_BERRIES
    FLAG_RED
    FLAG_GREEN
    FLAG_BLUE

enum AnimKind
    NONE
    SQUASH_AND_STRETCH
    TREE_FALL
    PICK
    DEATH

struct Anim
    kind : AnimKind
    t : float
    stopT : float

struct TileBase
    z : float
    color : uint = 0xffffffff
    kind : TileKind
    anim : Anim
    info : int
    mirrorX : bool


struct Tile : TileBase
    position: int2
    
struct TileFloat : TileBase
    position: float2
    offsetY : float

def to_tile_float(tile : Tile) : TileFloat
    var result : TileFloat
    cast<TileBase>(result) = cast<TileBase>(tile)
    result.position = float2(float(tile.position.x), float(tile.position.y))
    return result

class Grid
    width : int
    height : int
    tiles : array<Tile>

    def getIdxInt(pos : int2) : int
        if pos.x >= width || pos.y >= height || pos.x < 0 || pos.y < 0
            return -1
        return pos.x * height + pos.y

    def getIdx(pos : float2) : int
        return getIdxInt(int2(roundi(pos.x), roundi(pos.y)))

    def getIntPos(pos : float2) : int2
        return int2(roundi(pos.x), roundi(pos.y))

    def setTile(tile : Tile)
        var idx = getIdxInt(tile.position)
        if idx != -1
            self.tiles[idx] = tile

    def getTileInt(pos : int2) : Tile
        var idx = getIdxInt(pos)
        if idx == -1
            var fakeTile : Tile
            fakeTile.position.x = pos.x
            fakeTile.position.y = pos.y
            return fakeTile
        else
            return self.tiles[idx]
    
    def getTile(pos : float2) : Tile
        var idx = getIdx(pos)
        if idx == -1
            var fakeTile : Tile
            fakeTile.position.x = roundi(pos.x)
            fakeTile.position.y = roundi(pos.y)
            return fakeTile
        else
            return self.tiles[idx]

    def getHeight(pos : float2) : float
        var idx = getIdx(pos)
        if idx != -1
            return self.tiles[idx].z
        else
            return 0.0

enum SoundKind
    EAT_APPLE
    CHOP
    TREE_FALL
    TREE_FALL_END
    PICK
    PICK_WATER
    DROP_WATER
    DROP
    FOOTSTEP
    GENERIC_ACTION
    FIRE_PUT_OUT
