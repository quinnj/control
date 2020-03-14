module Model

using StructTypes

struct Card
    type::String
    value::Int
    burnable::Bool
end

Base.string(c::Card) = "$(c.type) ($(c.value))"
StructTypes.StructType(::Type{Card}) = StructTypes.Struct()

const Rift = Card("Rift", 1, false)
const Balls = Card("Balls", 2, false)
const Deflector = Card("Deflector", 3, false)
const Reactor = Card("Reactor", 5, false)
const Wormhole = Card("Wormhole", 4, true)
const Anomaly = Card("Anomaly", 4, true)
const Rewind = Card("Rewind", 5, true)
const DarkEnergy = Card("DarkEnergy", 6, true)
const FutureShift = Card("FutureShift", 6, true)
const Singularity = Card("Singularity", 7, true)
const Antimatter = Card("Antimatter", 8, true)
const Timestop = Card("Timestop", 9, false)
const Nova = Card("Nova", 10, false)

const Silvers = [Rift, Balls, Deflector, Reactor]
const CardTypes = [Rift, Balls, Deflector, Reactor, Wormhole, Anomaly, Rewind, DarkEnergy, FutureShift, Singularity, Antimatter, Timestop, Nova]
const Deck = collect(Iterators.flatten([fill(x, 4) for x in CardTypes]))

struct Player
    playerId::Int # index into game.hands, game.decks, etc.
    name::String
    # avatar
end
StructTypes.StructType(::Type{Player}) = StructTypes.Struct()

@enum Action begin
    WaitingPlayers
    TakeTurn
    DeflectorResolve # pick opp card -> discard or draw from opp deck

    RewindResolve # pick install -> bottom of deck
    DarkEnergyResolve # pick silver -> install of another, resolve Rift, Balls
    FutureShiftResolve # 2 peeks from opp decks, pick one to install, diffuse opp card, or burn & resolve
    SingularityResolve # all copper -> discard
    AntimatterResolve # pick opp card -> discard, opp picks card -> discard
    TimestopResolve # cancel currently played card
end

mutable struct Pick
    pickingPlayerId::Int
    pickedPlayerId::Int
    cardNumberPicked::Int
    roundPicked::Int
    roundPickNumber::Int
    cardType::CardType
end
Pick() = Pick(0, 0, 0, 0, 0, FireEnergy)
Pick(a, b, c) = Pick(a, b, c, 0, 0, FireEnergy)
StructTypes.StructType(::Type{Pick}) = StructTypes.Mutable()

mutable struct Game
    # core fields
    gameId::Int
    numPlayers::Int # 2 or 4
    players::Vector{Union{Nothing, Player}}
    whoseturn::Int # playerId
    actionturn::Int # playerId
    finished::Bool
    lastAction::Action
    nextExpectedAction::Action
    # joined fields
    hands::Vector{Vector{Card}} # length == numPlayers
    decks::Vector{Vector{Card}}
    installs::Vector{Vector{Card}}
    discard::Vector{Card}
    burningCard::Union{Nothing, Card}
    usedPass::Vector{Bool}
    
    # calculated fields
    teammate::Dict{Int, Int}
    points::Vector{Int}
    pikasFound::Int
    whoWon::Role
end

Game() = Game(0, 0, Union{Nothing, Player}[], 0, WaitingPlayers, WaitingPlayers, 1, false, Pick[], Card[], Vector{Card}[], Role[], Good, nothing, nothing, 0, Good)

StructTypes.StructType(::Type{Game}) = StructTypes.Mutable()
StructTypes.excludes(::Type{Game}) = (:roles, :outRole)

function Base.copy(game::Game)
    g = Game()
    for f in fieldnames(Game)
        if f != :privateActionResolution && isdefined(game, f)
            setfield!(g, f, getfield(game, f))
        end
    end
    return g
end

end # module