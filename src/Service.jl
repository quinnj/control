module Service

using Random
using ..Model, ..Mapper

pick!(A) = splice!(A, rand(1:length(A)))

function createNewGame(params)
    game = Model.Game()
    game.numPlayers = params.numPlayers
    game.whoseturn = rand(0:game.numPlayers-1)
    game.players = Vector{Union{Nothing, Model.Player}}(undef, game.numPlayers)
    fill!(game.players, nothing)
    deck, roles = generateDeckAndRoles(game.numPlayers)
    game.roles = roles
    game.outRole = game.numPlayers != 6 ? pick!(roles) : Model.Good
    game.hands = [[Model.Card(pick!(deck), false) for i = 1:5] for i = 1:game.numPlayers]
    return calculateFields!(Mapper.createNewGame(game))
end

function getGame(gameId)
    return Mapper.getGame(gameId)
end

function getActiveGames()
    return Mapper.getActiveGames()
end

function deleteGame(gameId)
    Mapper.deleteGame(gameId)
    return
end

function rematch(gameId)
    game = Mapper.getGame(gameId)
    return createNewGame((numPlayers=game.numPlayers,))
end

function joinGame(gameId, params)
    game = Mapper.getGame(gameId)
    game.players[params.playerId+1] = Model.Player(params.name)
    if all(!isnothing, game.players)
        game.nextExpectedAction = Model.PickACard
    end
    Mapper.updateGame(game)
    return calculateFields!(game)
end



function calculateFields!(game)
    # pikasFound
    game.pikasFound = numPikas(game.picks)
    # whoWon
    game.whoWon = game.pikasFound == game.numPlayers ? Model.Good : Model.Bad
    return game
end

function currentRoundPicks(game)
    return filter(game.picks) do pick
        pick.roundPicked == game.currentRound
    end
end

function resolvePick!(game, pick)
    push!(game.picks, pick)
    cardType = pick.cardType
    # for almost all actions, the person picked gets to pick next
    whoseturn = game.whoseturn
    game.whoseturn = pick.pickedPlayerId
    if length(game.picks) > 1
        if game.picks[end-1].cardType == Model.DualBall
            game.whoseturn = whoseturn
        end
        picks = currentRoundPicks(game)
        if any(x -> x.cardType == Model.OldRodForFun, picks) && length(picks) < game.numPlayers
            game.whoseturn = whoseturn
        end
    end
    # default next action is pick a card
    game.nextExpectedAction = Model.PickACard
    # go to next round if last pick by default
    currentRound = game.currentRound
    game.currentRound += game.numPlayers == pick.roundPickNumber
    if cardType in Model.Energies
        nothing
    elseif cardType == Model.Pikachu
        if numPikas(game.picks) == game.numPlayers
            game.finished = true
        end
    elseif cardType == Model.Mewtwo
        game.finished = true
    elseif cardType == Model.WarpPoint
        game.nextExpectedAction = Model.WarpPointSteal
    elseif cardType == Model.PeekingRedCard
        game.nextExpectedAction = Model.PubliclyPeek
    elseif cardType == Model.Ghastly
        pickedPlayerHand = game.hands[pick.pickedPlayerId+1]
        append!(game.discard, splice!(pickedPlayerHand, 1:length(pickedPlayerHand)))
    elseif cardType == Model.EscapeRope
        pickedPlayerHand = game.hands[pick.pickedPlayerId+1]
        if !isempty(pickedPlayerHand)
            game.nextExpectedAction = Model.EscapeACard
        end
    elseif cardType == Model.ReverseValley
        pickedPlayerHand = game.hands[pick.pickedPlayerId+1]
        pickingPlayerHand = game.hands[pick.pickingPlayerId+1]
        game.hands[pick.pickedPlayerId+1] = pickingPlayerHand
        game.hands[pick.pickingPlayerId+1] = pickedPlayerHand
    elseif cardType == Model.RepeatBall
        game.whoseturn = pick.pickingPlayerId
    elseif cardType == Model.RescueStretcher
        if !isempty(game.discard)
            game.nextExpectedAction = Model.RescueDiscarded
        end
    elseif cardType == Model.Switch
        pikaPick = findlast(x -> x.cardType == Model.Pikachu, game.picks)
        if pikaPick !== nothing
            game.currentRound = currentRound
            # swap picks
            pikaPick.cardType, pick.cardType = pick.cardType, pikaPick.cardType
            push!(game.discard, Model.Card(pick.cardType, false))
            pop!(game.picks)
        end
    elseif cardType == Model.SuperScoopUp
        if game.currentRound > 1
            game.nextExpectedAction = Model.ScoopOldCard
        end
    elseif cardType == Model.OldRodForFun
        nothing
    elseif cardType == Model.DualBall
        nothing
    elseif cardType == Model.DetectivePikachu
        game.privateActionResolution = game.roles[game.picks[end].pickedPlayerId+1]
    elseif cardType == Model.EnergySearch
        if game.numPlayers == 6
            game.nextExpectedAction = Model.EnergySearchSomeone
        else
            game.privateActionResolution = game.outRole
        end
    elseif cardType == Model.MrMime
        nothing
    else
        error("can't resolvePick! for unknown cardType = $cardType")
    end
    if game.currentRound > currentRound
        discarded = splice!(game.discard, 1:length(game.discard))
        # deal out new hands
        cards = append!(collect(Iterators.flatten(game.hands)), discarded)
        game.hands = [[pick!(cards) for i = 1:(6 - game.currentRound)] for i = 1:game.numPlayers]
    end
end

function takeAction(gameId, action, body)
    game = Mapper.getGame(gameId)
    game.nextExpectedAction === action || error("expected $(game.nextExpectedAction) to be taken; $action was attempted")
    game.lastAction = action
    if action == Model.PickACard || action == Model.WooperJumpedOut
        if rand(1:50) == 1
            game.nextExpectedAction = Model.WooperJumpedOut
        else
            pick = Model.Pick(body.pickingPlayerId, body.pickedPlayerId, body.cardNumberPicked)
            pick.roundPicked = game.currentRound
            pick.roundPickNumber = length(currentRoundPicks(game)) + 1
            pick.cardType = splice!(game.hands[pick.pickedPlayerId+1], pick.cardNumberPicked+1).cardType
            resolvePick!(game, pick)
        end
    elseif action == Model.WarpPointSteal
        card = splice!(game.hands[body.pickedPlayerId+1], body.cardNumberPicked+1)
        lastPick = game.picks[end]
        insert!(game.hands[lastPick.pickedPlayerId+1], lastPick.cardNumberPicked+1, card)
        card.sidewaysForNew = true
        game.privateActionResolution = card.cardType
        game.nextExpectedAction = Model.PickACard
    elseif action == Model.PubliclyPeek
        card = game.hands[body.pickedPlayerId+1][body.cardNumberPicked+1]
        card.sidewaysForNew = true
        game.publicActionResolution = card.cardType
        game.nextExpectedAction = Model.PickACard
    elseif action == Model.EscapeACard
        lastPick = game.picks[end]
        hand = game.hands[lastPick.pickedPlayerId+1]
        card = splice!(hand, findfirst(x -> x.cardType == body.cardType, hand))
        push!(game.discard, card)
        game.nextExpectedAction = Model.PickACard
    elseif action == Model.RescueDiscarded
        card = game.discard[body.cardNumberPicked+1]
        lastPick = game.picks[end]
        lastPickCardType, lastPick.cardType = lastPick.cardType, card.cardType
        game.discard[body.cardNumberPicked+1] = Model.Card(lastPickCardType, false)
        resolvePick!(game, lastPick)
    elseif action == Model.ScoopOldCard
        lastPick = game.picks[end]
        scooped = game.picks[body.pickNumber+1]
        insert!(game.hands[lastPick.pickedPlayerId+1], lastPick.cardNumberPicked+1, scooped.card)
        scooped.card = lastPick.card
        pop!(game.picks)
        game.nextExpectedAction = Model.PickACard
    elseif action == Model.EnergySearchSomeone
        game.privateActionResolution = (playerId=body.pickedPlayerId, role=game.roles[body.pickedPlayerId+1])
        game.nextExpectedAction = Model.PickACard
    else
        error("unsupported action = $action")
    end
    Mapper.updateGame(game)
    return calculateFields!(game)
end

function getRoleAndHand(gameId, playerId)
    game = Mapper.getGame(gameId)
    hand = game.hands[playerId+1]
    return (hand=shuffle!([x.cardType for x in hand]), role=game.roles[playerId+1])
end

function getDiscard(gameId)
    game = Mapper.getGame(gameId)
    return (discard=[x.cardType for x in game.discard],)
end



function init()
    println("initializing Service")
    # force compilation of key methods
    game = createNewGame((numPlayers=5,))
    joinGame(game.gameId, (playerId=1, name=""))
    game.nextExpectedAction = Model.PickACard
    takeAction(game.gameId, Model.PickACard, (pickingPlayerId=1, pickedPlayerId=2, cardNumberPicked=1))
    game.finished = true
    println("initialized Service")
    return
end

end # module