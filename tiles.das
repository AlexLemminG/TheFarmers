require math


enum TileKind
    NONE
    GRASS
    SOIL
    HUMAN
    CHILD_A
    CHILD_B
    WOOD
    TREE_GREEN
    TREE_YELLOW
    TREE_RED
    CHEST_IRON
    TILE_SELECTION
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
    GOLD
    HORSE
    SHEEP
    HUMAN_ON_HORSE

enum AnimKind
    NONE
    SQUASH_AND_STRETCH
    TREE_FALL
    PICK

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
        var idx = pos.x * height + pos.y
        if idx >= length(self.tiles) || idx < 0
            return -1
        return idx

    def getIdx(pos : float2) : int
        return getIdxInt(int2(roundi(pos.x), roundi(pos.y)))


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
