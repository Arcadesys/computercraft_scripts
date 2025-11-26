---@diagnostic disable: undefined-global, undefined-field
local arcade = require("arcade")

-- Configuration
-- Sides of the computer where levers are attached
-- P1: Bottom, P2: Top, P3: Left, P4: Right
local INPUT_SIDES = {"left", "right", "back", "bottom"} 
local PADDLE_SIZE = 6
local BALL_SPEED_START = 0.8
local MAX_SCORE = 10

local COLORS = {
    P1 = colors.red,    -- Bottom
    P2 = colors.blue,   -- Top
    P3 = colors.green,  -- Left
    P4 = colors.yellow, -- Right
    BALL = colors.white,
    BG = colors.black,
    TEXT = colors.white
}

local mon = nil
local W, H = 0, 0
local running = false
local winner = nil

local players = {}
local ball = {x=0, y=0, vx=0, vy=0}

local function createPlayer(id, side, color, isVertical, axisPos)
    return {
        id = id,
        side = side,
        color = color,
        vertical = isVertical,
        axisPos = axisPos, -- The fixed coordinate (Y for horiz, X for vert)
        pos = 1, -- The moving coordinate
        score = MAX_SCORE,
        alive = true
    }
end

local game = {
    name = "Warlords 4-Way",
    
    init = function(self, a)
        mon = peripheral.find("monitor")
        if not mon then 
            mon = term.current() 
        end
        
        -- Force scale for high res
        if mon.setTextScale then mon.setTextScale(0.5) end
        
        W, H = mon.getSize()
        H = H - 3 -- Reserve button space
        
        -- Initialize Players
        players = {
            createPlayer(1, INPUT_SIDES[1], COLORS.P1, false, H), -- Bottom
            createPlayer(2, INPUT_SIDES[2], COLORS.P2, false, 1), -- Top
            createPlayer(3, INPUT_SIDES[3], COLORS.P3, true, 1),  -- Left
            createPlayer(4, INPUT_SIDES[4], COLORS.P4, true, W)   -- Right
        }
        
        -- Center paddles
        players[1].pos = W/2 - PADDLE_SIZE/2
        players[2].pos = W/2 - PADDLE_SIZE/2
        players[3].pos = H/2 - PADDLE_SIZE/2
        players[4].pos = H/2 - PADDLE_SIZE/2
        
        a:setButtons({"Start", "Reset", "Quit"})
        self:resetBall()
    end,
    
    resetBall = function(self)
        ball.x = W/2
        ball.y = H/2
        local angle = math.random() * math.pi * 2
        ball.vx = math.cos(angle) * BALL_SPEED_START
        ball.vy = math.sin(angle) * BALL_SPEED_START
        -- Avoid too flat angles
        if math.abs(ball.vx) < 0.3 then ball.vx = (ball.vx < 0 and -0.5 or 0.5) end
        if math.abs(ball.vy) < 0.3 then ball.vy = (ball.vy < 0 and -0.5 or 0.5) end
    end,
    
    onTick = function(self, a, dt)
        if not running then 
            self:drawDirect()
            return 
        end
        
        -- 1. Update Paddles from Levers
        for _, p in ipairs(players) do
            if p.alive then
                local input = rs.getInput(p.side)
                -- Lever ON = +1 (Right/Down), OFF = -1 (Left/Up)
                local dir = input and 1 or -1
                
                local limit = p.vertical and H or W
                p.pos = p.pos + (dir * 1.5) -- Speed multiplier
                
                -- Clamp
                if p.pos < 1 then p.pos = 1 end
                if p.pos > limit - PADDLE_SIZE + 1 then p.pos = limit - PADDLE_SIZE + 1 end
            end
        end
        
        -- 2. Update Ball
        local nextX = ball.x + ball.vx
        local nextY = ball.y + ball.vy
        local hit = false
        
        -- Check boundaries/paddles
        -- Left Wall (P3)
        if nextX <= 1 then
            if self:checkPaddle(players[3], nextY) then
                ball.vx = math.abs(ball.vx) * 1.05
                hit = true
            else
                self:damage(players[3])
                ball.vx = math.abs(ball.vx) -- Bounce anyway
            end
        -- Right Wall (P4)
        elseif nextX >= W then
            if self:checkPaddle(players[4], nextY) then
                ball.vx = -math.abs(ball.vx) * 1.05
                hit = true
            else
                self:damage(players[4])
                ball.vx = -math.abs(ball.vx)
            end
        end
        
        -- Top Wall (P2)
        if nextY <= 1 then
            if self:checkPaddle(players[2], nextX) then
                ball.vy = math.abs(ball.vy) * 1.05
                hit = true
            else
                self:damage(players[2])
                ball.vy = math.abs(ball.vy)
            end
        -- Bottom Wall (P1)
        elseif nextY >= H then
            if self:checkPaddle(players[1], nextX) then
                ball.vy = -math.abs(ball.vy) * 1.05
                hit = true
            else
                self:damage(players[1])
                ball.vy = -math.abs(ball.vy)
            end
        end
        
        if not hit then
            ball.x = ball.x + ball.vx
            ball.y = ball.y + ball.vy
        else
            -- Nudge out of wall to prevent sticking
            ball.x = ball.x + ball.vx
            ball.y = ball.y + ball.vy
        end
        
        -- Clamp ball to field
        if ball.x < 1 then ball.x = 1 end
        if ball.x > W then ball.x = W end
        if ball.y < 1 then ball.y = 1 end
        if ball.y > H then ball.y = H end
        
        self:drawDirect()
    end,
    
    checkPaddle = function(self, p, ballPos)
        -- Check overlap
        return ballPos >= p.pos - 1 and ballPos <= p.pos + PADDLE_SIZE
    end,
    
    damage = function(self, p)
        if not p.alive then return end
        p.score = p.score - 1
        if p.score <= 0 then
            p.alive = false
            p.color = colors.gray
            self:checkWin()
        end
    end,
    
    checkWin = function(self)
        local alive = 0
        local last = nil
        for _, p in ipairs(players) do
            if p.alive then 
                alive = alive + 1 
                last = p
            end
        end
        if alive <= 1 then
            running = false
            winner = last
        end
    end,
    
    drawDirect = function(self)
        if not mon then return end
        mon.setBackgroundColor(COLORS.BG)
        for y=1, H do
            mon.setCursorPos(1, y)
            mon.write(string.rep(" ", W))
        end
        
        -- Draw Paddles
        for _, p in ipairs(players) do
            mon.setBackgroundColor(p.color)
            if p.vertical then
                for i=0, PADDLE_SIZE-1 do
                    local y = math.floor(p.pos + i)
                    if y >= 1 and y <= H then
                        mon.setCursorPos(p.axisPos, y)
                        mon.write(" ")
                    end
                end
            else
                for i=0, PADDLE_SIZE-1 do
                    local x = math.floor(p.pos + i)
                    if x >= 1 and x <= W then
                        mon.setCursorPos(x, p.axisPos)
                        mon.write(" ")
                    end
                end
            end
            
            -- Draw Score
            mon.setTextColor(p.color)
            mon.setBackgroundColor(COLORS.BG)
            if p.id == 1 then mon.setCursorPos(W/2, H-1) -- Bottom
            elseif p.id == 2 then mon.setCursorPos(W/2, 2) -- Top
            elseif p.id == 3 then mon.setCursorPos(2, H/2) -- Left
            elseif p.id == 4 then mon.setCursorPos(W-2, H/2) -- Right
            end
            mon.write(tostring(p.score))
        end
        
        -- Draw Ball
        mon.setBackgroundColor(COLORS.BALL)
        mon.setCursorPos(math.floor(ball.x), math.floor(ball.y))
        mon.write(" ")
        
        if winner then
            mon.setBackgroundColor(COLORS.BG)
            mon.setTextColor(winner.color)
            local msg = "WINNER: P" .. winner.id
            mon.setCursorPos(W/2 - #msg/2, H/2)
            mon.write(msg)
        end
    end,
    
    onButton = function(self, a, btn)
        if btn == "left" then running = true end
        if btn == "center" then 
            self:resetBall()
            for _, p in ipairs(players) do
                p.score = MAX_SCORE
                p.alive = true
                p.color = (p.id==1 and COLORS.P1) or (p.id==2 and COLORS.P2) or (p.id==3 and COLORS.P3) or (p.id==4 and COLORS.P4)
            end
            winner = nil
            running = false
        end
        if btn == "right" then a:requestQuit() end
    end,
    
    draw = function(self, a)
        self:drawDirect()
    end
}

arcade.start(game, {tickSeconds = 0.05})