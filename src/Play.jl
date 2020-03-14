module Play

using REPL.TerminalMenus
using ..Client, ..Model

radio(msg, opts) = request(msg, RadioMenu(opts))

function turnradio(msg, opts, f=string)
    ret = radio(msg, push!(map(f, opts), "start turn over"))
    return ret == length(opts) ? nothing : opts[ret]
end

function play(name::String, loc=false)
    # whether we play against a local or remote server
    Client.setServer!(loc)
    games = Dict{Int, Model.Game}()
    while true
        activeGames = Client.getActiveGames()
        for game in activeGames
            games[game.gameId] = game
        end
        opts = ["refresh games", "create new game"]
        if !isempty(games)
            push!(opts, "join game ($(length(games)))")
            push!(opts, "delete game")
        end
        ret = radio("\e[2Jcontrol lobby\nwadya want", opts)
        if ret == 1
            continue
        elseif ret == 2
            while true
                print("\e[2J# players: ")
                N = readline()
                N == "q" && break
                try
                    n = parse(Int, N)
                    if n == 2 || n == 4
                        game = Client.createNewGame(n)
                        games[game.gameId] = game
                        break
                    else
                        println("enter 2 or 4")
                    end
                catch e
                    println("enter 2 or 4 dummy or 'q' to go back")
                end
            end
        elseif ret == 3
            gameIds = collect(keys(games))
            opts = ["gameId: $i" for i in gameIds]
            push!(opts, "go back")
            ret = radio("\e[2Jwhich game", opts)
            if ret != length(opts)
                gameId = gameIds[ret]
                game = Ref{Model.Game}(games[gameId])
                Client.websocket(gameId, game)
                playerId = findfirst(isnothing, game[].players) - 1
                if playerId !== nothing
                    Client.joinGame(gameId, playerId, name)
                end
                gameLoop(game, playerId)
            end
        elseif ret == 4
            gameIds = collect(keys(games))
            opts = ["gameId: $i" for i in gameIds]
            push!(opts, "go back")
            ret = radio("\e[2Jwhich game", opts)
            if ret != length(opts)
                Client.deleteGame(gameIds[ret])
                delete!(games, gameIds[ret])
            end
        end
    end
end

teammate(n, id) = n == 2 ? 0 : (id == 0 ? 2 : id == 1 ? 3 : id == 2 ? 0 : 1)
opponents(n, id) = n == 2 ? (id == 0 ? (1,) : (0,)) : (id == 0 ? (1, 3) : id == 1 ? (0, 2) : id == 2 ? (1, 3) : (0, 2))
havetimestop(game, playerId) = any(x -> x.type == "Timestop", game.game.hands[playerId+1])

function gameLoop(game, playerId)
    # wait for all players to arrive
    while game.game.nextExpectedAction == Model.WaitingPlayers
        wait(game.cond)
    end
    errorText = ""
    while true
        if game.game.nextExpectedAction == Model.ResolveDeflector
            if game.game.actionturn == playerId
                ret = radio("\e[2Jdeflect how", ["make discard", "draw"])
                if ret == 1
                    if game.game.numPlayers == 2
                        game.game = Client.resolveDeflector(game.game.gameId, true, opponents(playerId)[1])
                    else
                        pickedPlayerId = turnradio("\e[2Jdeflect who", opponents(playerId), x->"$(game.game.players[x+1].name) ($(length(game.game.hands[x+1])))")
                        pickedPlayerId === nothing && continue
                        game.game = Client.resolveDeflector(game.game.gameId, true, pickedPlayerId)
                    end
                else
                    if game.game.numPlayers == 2
                        game.game = Client.resolveDeflector(game.game.gameId, false, opponents(playerId)[1])
                    else

                    end
                end
            else
                p = game.game.players[game.game.actionturn+1].name
                println("\e[2Jwaiting on $p to resolve their deflector")
                wait(game.cond)
            end
        if game.game.nextExpectedAction == Model.TakeTurn
            if game.game.whoseturn == playerId
                hand = game.game.hands[playerId+1]
                opts = String[]
                length(hand) < 7 && length(game.game.decks[playerId+1]) > 0 && push!(opts, "draw")
                any(x -> x.burnable, hand) && push!(opts, "burn")
                length(hand) > 0 && push!(opts, "install")
                length(hand) > 0 && push!(opts, "diffuse")
                !game.game.usedPass[playerId+1] && push!(opts, "pass")
                if isempty(opts)
                    game.game = Client.cantPlay(game.game.id)
                end
                rets = opts[radio("\e[2Jyour turn bucko", opts)]
                if rets == "draw"
                    game.game = Client.drawACard(game.game.gameId)
                elseif rets == "diffuse"
                    diffusingCard = turnradio("\e[2Jdiffuse with", hand)
                    diffusingCard === nothing && continue
                    opps = opponents(game.game.numPlayers, playerId)
                    potentials = [(i, game.game.players[i+1].name) for i in opps if length(game.game.installs[i+1]) > 0 && any(x -> x.value <= diffusingCard.value, game.game.installs[i+1])]
                    if isempty(potentials)
                        errorText = "baddos don't have cards you can diffuse w/ $diffusingCard"
                        continue
                    end
                    if length(potentials) == 1
                        pickedPlayerId = potentials[1][1]
                    else
                        pickedPlayer = turnradio("\e[2Jdiffuse who", potentials, x->x[2])
                        pickedPlayer === nothing && continue
                        pickedPlayerId = pickedPlayer[1]
                    end
                    potentialDiffused = filter(x -> x.value <= diffusingCard.value && x.type != "Reactor", game.game.installs[pickedPlayerId+1])
                    cardDiffused = turnradio("\e[2Jdiffuse what", potentialDiffused)
                    cardDiffused === nothing && continue
                    game.game = Client.diffuseACard(game.game.gameId, diffusingCard, pickedPlayerId, cardDiffused)
                elseif rets == "install"
                    installedCard = turnradio("\e[2Jinstall what", hand)
                    installedCard === nothing && continue
                    if installedCard.type == "Rift"
                        # pick from opp deck or destroy nova
                        oppDecks = [i for i in opponents(playerId) if !isempty(game.game.decks[i])]
                        novas = [i for i in opponents(playerId) if any(x -> x.type == "Nova", game.game.installs[i])]
                        if isempty(oppDecks) && isempty(novas)
                            # no-op rift
                            game.game = Client.installACard(game.game.gameId, installedCard, )
                        elseif !isempty(novas)
                            # must destroy opp nova
                            if length(novas) == 1
                                # easy, no choice
                                game.game = Client.resolveRift(game.game.gameId, installedCard, false, novas[1])
                            else
                                pickedPlayerId = turnradio("\e[2Jwhose nova", novas, x->game.game.players[x].name)
                                pickedPlayerId === nothing && continue
                                game.game = Client.resolveRift(game.game.gameId, false, pickedPlayerId)
                            end
                        elseif !isempty(oppDecks)
                            # must pick from opp deck
                            if length(oppDecks) == 1
                                # easy, no choice
                                game.game = Client.resolveRift(game.game.gameId, true, oppDecks[1])
                            else
                                pickedPlayerId = turnradio("\e[2Jrift who", oppDecks, x->game.game.players[x].name)
                                pickedPlayerId === nothing && continue
                                game.game = Client.resolveRift(game.game.gameId, true, pickedPlayerId)
                            end
                        else
                            # get to choose
                            choice = turnradio("\e[2Jnova or pick", ["nova", "pick"])
                            choice === nothing && continue
                            if choice == "nova"
                                if length(novas) == 1
                                    # easy, no choice
                                    game.game = Client.resolveRift(game.game.gameId, installedCard, false, novas[1])
                                else
                                    pickedPlayerId = turnradio("\e[2Jwhose nova", novas, x->game.game.players[x].name)
                                    pickedPlayerId === nothing && continue
                                    game.game = Client.resolveRift(game.game.gameId, false, pickedPlayerId)
                                end
                            else
                                if length(oppDecks) == 1
                                    # easy, no choice
                                    game.game = Client.resolveRift(game.game.gameId, true, oppDecks[1])
                                else
                                    pickedPlayerId = turnradio("\e[2Jrift who", oppDecks, x->game.game.players[x].name)
                                    pickedPlayerId === nothing && continue
                                    game.game = Client.resolveRift(game.game.gameId, true, pickedPlayerId)
                                end
                            end
                        end
                    elseif installedCard.type == "Balls"
                        potentialChains = [x for x in hand if x.value <= 6]
                        if isempty(potentialChains)
                            # easy, nothing else to chain
                            game.game = Client.installACard(game.game.gameId, installedCard)
                        else
                            chain = [installedCard]
                            while !isempty(potentialChains)
                                nextChain = radio("\e[2Jchain w/ balls?", [map(string, potentialChains)..., "no"])
                                nextChain == length(potentialChains) + 1 && break
                                push!(chain, splice!(potentialChains, nextChain))
                                chainTotal = sum(x->x.value, chain)
                                filter!(x -> chainTotal + x.value <= 10, potentialChains)
                            end
                            game.game = Client.resolveBalls(game.game.gameId, chain)
                        end
                    else
                        game.game = Client.installACard(game.game.gameId, installedCard)
                    end
                elseif rets == "burn"
                    burnedCard = turnradio("\e[2Jburn what", filter(x -> x.burnable, hand))
                    burnedCard === nothing && continue
                    # ping client that a burn has started to allow timestopping
                    # need server to broadcast the burning, then sleep a little
                    # before returning from beginBurn to allow others to timestop
                    game.game = Client.beginBurn(game.game.gameId, burnedCard)
                    if burnedCard.type == "Wormhole"
                        card = turnradio("\e[2Jworm a card", filter(x -> x.type != "Wormhole", game.game.burn))
                        card === nothing && continue
                        game.game = Client.wormhole(game.game.gameId, card)
                    elseif burnedCard.type == "Anomaly"
                        game.game = Client.anomaly(game.game.gameId)
                    elseif burnedCard.type == "Rewind"
                        rewindable = collect(Iterator.flatten([[PlayersCard(i-1, game.game.players[i].name, x) for x in game.game.installs[i]] for i = 1:game.game.numPlayers if i != (playerId + 1)]))
                        rewind = turnradio("\e[2Jrewind a card", rewindable)
                        rewind === nothing && continue
                        if game.game.numPlayers == 2
                            receivingPlayerId = playerId
                        else
                            receivingPlayerId = turnradio("\e[2Jrewind where", ["you", game.game.players[teammate(game.game.numPlayers, playerId)].name])
                            receivingPlayerId === nothing && continue
                        end
                        game.game = Client.rewind(game.game.gameId, rewind.playerId, rewind.card, receivingPlayerId)
                    elseif burnedCard.type == "DarkEnergy"
                        # choose silver, choose where to move, resolve rift, resolve balls
                    elseif burnedCard.type == "FutureShift"
                        # choose where to shift, see two cards, pick one, then diffuse, install, or burn
                    elseif burnedCard.type == "Singularity"
                        game.game = Client.singularity(game.game.gameId)
                    elseif burnedCard.type == "Antimatter"

                    end
                elseif rets == "pass"
                    game.game = Client.pass(game.game.gameId)
                end
            else
                p = game.game.players[game.game.whoseturn+1].name
                if game.game.burningCard !== nothing && havetimestop(game, playerId)
                    ret = radio("\e[2J$p is playing $(game.game.burningCard), timestop their face?", ["yes", "no"])
                    if ret == 1
                        Client.playTimestop(game.game.gameId, playerId)
                    else
                        println("\e[2Jwaiting on $p to finish their turn")
                        wait(game.cond)
                    end
                else
                    println("\e[2Jwaiting on $p to take their turn")
                    wait(game.cond)
                end
            end
        elseif 
    end
end

struct PlayersCard
    playerId::Int
    name::String
    card::Model.Card
end

Base.string(p::PlayersCard) = "$name's $card"

end # module