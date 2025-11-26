local cards = {}

cards.SUITS = {"S", "H", "D", "C"}
cards.RANKS = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}
cards.SUIT_COLORS = {S=colors.gray, H=colors.red, D=colors.red, C=colors.gray}
cards.SUIT_SYMBOLS = {S="\6", H="\3", D="\4", C="\5"}

function cards.createDeck()
    local deck = {}
    for s=1,4 do
        for r=1,13 do
            table.insert(deck, {suit=cards.SUITS[s], rank=r, rankStr=cards.RANKS[r]})
        end
    end
    return deck
end

function cards.shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

function cards.getCardString(card)
    return card.rankStr .. cards.SUIT_SYMBOLS[card.suit]
end

function cards.evaluateHand(hand)
    -- Sort by rank
    local sorted = {}
    for _, c in ipairs(hand) do table.insert(sorted, c) end
    table.sort(sorted, function(a,b) return a.rank < b.rank end)

    local flush = true
    local suit = sorted[1].suit
    for i=2,5 do
        if sorted[i].suit ~= suit then flush = false break end
    end

    local straight = true
    for i=1,4 do
        if sorted[i+1].rank ~= sorted[i].rank + 1 then
            straight = false
            break
        end
    end
    -- Special case: A, 2, 3, 4, 5 (A is 13)
    -- Sorted would be 2,3,4,5,A (ranks 1,2,3,4,13)
    if not straight and sorted[5].rank == 13 and sorted[1].rank == 1 and sorted[2].rank == 2 and sorted[3].rank == 3 and sorted[4].rank == 4 then
        straight = true
    end

    local counts = {}
    for _, c in ipairs(sorted) do
        counts[c.rank] = (counts[c.rank] or 0) + 1
    end
    local countsArr = {}
    for r, c in pairs(counts) do table.insert(countsArr, {rank=r, count=c}) end
    table.sort(countsArr, function(a,b) return a.count > b.count end)

    -- Ranks: 1=2, 2=3, 3=4, 4=5, 5=6, 6=7, 7=8, 8=9, 9=10, 10=J, 11=Q, 12=K, 13=A
    if straight and flush and sorted[1].rank == 9 then return "ROYAL_FLUSH", 250 end
    if straight and flush then return "STRAIGHT_FLUSH", 50 end
    if countsArr[1].count == 4 then return "FOUR_OF_A_KIND", 25 end
    if countsArr[1].count == 3 and countsArr[2].count == 2 then return "FULL_HOUSE", 9 end
    if flush then return "FLUSH", 6 end
    if straight then return "STRAIGHT", 4 end
    if countsArr[1].count == 3 then return "THREE_OF_A_KIND", 3 end
    if countsArr[1].count == 2 and countsArr[2].count == 2 then return "TWO_PAIR", 2 end
    if countsArr[1].count == 2 and (countsArr[1].rank >= 10 or countsArr[1].rank == 13) then -- J, Q, K, A (10,11,12,13)
        return "JACKS_OR_BETTER", 1
    end
    
    return "NONE", 0
end

return cards
