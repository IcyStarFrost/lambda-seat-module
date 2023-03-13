local collisionPly = GetConVar( "lambdaplayers_lambda_noplycollisions" )
local isentity = isentity
local IsValid = IsValid
local tracetbl2 = {}
local tracetable = {} -- Recycled table


local seatmodels = {
    [ "models/nova/airboat_seat.mdl" ] = true,
    [ "models/nova/jeep_seat.mdl" ] = true,
    [ "models/nova/chair_office01.mdl" ] = true,
    [ "models/nova/chair_office02.mdl" ] = true,
    [ "models/nova/chair_plastic01.mdl" ] = true,
    [ "models/nova/chair_wood01.mdl" ] = true,
    [ "models/props_phx/carseat2.mdl" ] = true,
    [ "models/nova/jalopy_seat.mdl" ] = true
}

local allowsitting = CreateLambdaConvar( "lambdaplayers_seat_allowsitting", 1, true, false, false, "If Lambda players are allowed to sit on the ground and props", 0, 1, { type = "Bool", name = "Allow Sitting", category = "Lambda Server Settings" } )

-- Returns if the simfphys vehicle is open
local function IsSimfphysOpen( veh )
    if veh:OnFire() then return false end
    local driverseat = veh:GetDriverSeat()
    local passengerseats = veh:GetPassengerSeats()
    if IsValid( driverseat:GetDriver() ) or IsValid( veh.l_lambdaseated ) then return false end

    local opencount = 0

    for k, pod in pairs( passengerseats ) do
        if !IsValid( pod:GetDriver() ) and !IsValid( veh.l_lambdaseated ) then opencount = opencount + 1 end
    end

    if opencount == 0 then return false end

    return true
end

-- The Seat Module is a more advanced form of the Zeta's Vehicle System.
-- This module will allow Lambdas to sit on the ground, on entities, and drive vehicles.
-- I'll be honest this a bit messy but it works

local function Initialize( self )
    if CLIENT then return end 

    self.l_currentseatsit = nil -- The current vehicle, seat, or spot we are sitting at
    self.l_wasseatsitting = false -- If we were sitting a tick ago
    self.l_isseatsitting = false -- If we are sitting

    function self:StopSitting() -- Makes the lambda stop sitting
        self.l_isseatsitting = false
    end

    function self:IsSitting() -- If the Lambda is sitting
        return self.l_isseatsitting
    end

    function self:GetVehicle() -- Returns the vehicle. Basically just whatever self.l_currentseatsit is
        return self.l_currentseatsit
    end

    function self:ExitVehicle() self:ResetSitInfo() end

    function self:EnterVehicle( ent ) self:Sit( ent ) end

    function self:ResetSitInfo()
        local newstate = self:GetState() == "SitState" and "Idle" or self:GetState() == "DriveState" and "Idle" or self:GetState()
        self.l_seatnormvector = nil
        self:SetParent()
        self:SetState( newstate )
        self:SetAngles( Angle( 0, self:GetAngles()[ 2 ], 0 ) )
        self:SetPoseParameter( "vehicle_steer", 0 )
        self.l_vehicleattachment = nil
        self.l_isseatsitting = false
        self.l_wasseatsitting = false
        self.l_UpdateAnimations = true

        self:SetMoveType( MOVETYPE_CUSTOM )
        self:SetSolidMask( MASK_PLAYERSOLID )

        self.loco:SetVelocity( Vector() )
        self.l_FallVelocity = 0

        -- If we were in a vehicle or chair, find a place to exit if possible
        if isentity( self.l_currentseatsit ) and IsValid( self.l_currentseatsit ) then 
            self.l_currentseatsit.l_lambdaseated = nil

            self.l_currentseatsit:SetSaveValue( "m_hNPCDriver", NULL )

            if self:IsDrivingSimfphys() then
                self.l_currentseatsit:GetDriverSeat().l_lambdaseated = nil
                self.l_currentseatsit:SetActive( false )
                self.l_currentseatsit:StartEngine()
                self.l_currentseatsit:SetDriver( NULL )
                self.l_currentseatsit.PressedKeys[ "W" ] = false
                self.l_currentseatsit.PressedKeys[ "S" ] = false
            elseif self.l_invehicle then
                self.l_currentseatsit:SetThrottle( 0 )
                self.l_currentseatsit:SetSteering( 0, 0 )
            end


            self:SetPoseParameter( "vehicle_steer", 0 )

            if self.l_currentseatsit.l_seatmoduleexitfunc then
                self.GetVehicle_UseDriverSeat = true
                self.l_currentseatsit.l_seatmoduleexitfunc( self, self.l_currentseatsit )
                self.GetVehicle_UseDriverSeat = false
                
            else
                local exitpos = self.l_invehicle and self.l_currentseatsit:CheckExitPoint( self.l_currentseatsit:GetAngles().y, 192 )

                if !exitpos then 
                    local dirs = {
                        self.l_currentseatsit:GetRight() * 128,
                        self.l_currentseatsit:GetRight() * -128,
                        self.l_currentseatsit:GetForward() * 128,
                        self.l_currentseatsit:GetForward() * -128
                    }
                    for i = 1, #dirs do
                        exitpos = self.l_currentseatsit:GetPos() + dirs[ i ]
                        tracetable.start = self.l_currentseatsit:GetPos()
                        tracetable.endpos = exitpos
                        tracetable.filter = { self, self.l_currentseatsit }

                        local tr = util.TraceLine( tracetable )
                        if !tr.Hit then break end
                    end
                end

                if exitpos then self:SetPos( exitpos ) end
            end
        end

        if !collisionPly:GetBool() then
            self:SetCollisionGroup( COLLISION_GROUP_PLAYER )
        else
            self:SetCollisionGroup( COLLISION_GROUP_PASSABLE_DOOR )
        end
    end

    function self:Sit( sitarg, endtime ) -- Makes the lambda sit in a seat/spot/vehicle for a given amount of time or forever if nil
        if isentity( sitarg ) and IsValid( sitarg ) and sitarg.IsSimfphyscar and !IsSimfphysOpen( sitarg ) or isentity( sitarg ) and IsValid( sitarg ) and !sitarg.IsSimfphyscar and sitarg:IsVehicle() and ( IsValid( sitarg:GetDriver() ) or IsValid( sitarg.l_lambdaseated ) or IsValid( sitarg:GetInternalVariable( "m_hNPCDriver" ) ) ) then return end
        self:ResetSitInfo()

        self.l_currentseatsit = sitarg
        self.l_isseatsitting = true
        self.l_wasseatsitting = true

        self.l_sitendtime = endtime and CurTime() + endtime or nil

        -- The arg is a entity
        if isentity( sitarg ) and IsValid( sitarg ) then 

            if sitarg.IsSimfphyscar then 
                local enteredseat = false
                local driverseat = sitarg:GetDriverSeat()
                local passengerseats = sitarg:GetPassengerSeats()

                if IsValid( driverseat:GetDriver() ) or IsValid( driverseat.l_lambdaseated ) then

                    for k, pod in pairs( passengerseats ) do
                        if !IsValid( driverseat:GetDriver() ) and !IsValid( driverseat.l_lambdaseated ) then 
                            enteredseat = true
                            self.l_currentseatsit = pod 
                            break 
                        end
                    end
                elseif !IsValid( driverseat:GetDriver() ) and !IsValid( driverseat.l_lambdaseated ) then
                    enteredseat = true
                end

                if !enteredseat then
                    self.l_currentseatsit = nil
                    self.l_isseatsitting = false
                    return
                end

            end

            -- Get the position and angles
            local attach = sitarg:GetAttachment( sitarg:LookupAttachment( "vehicle_feet_passenger0" ) )
            local pos = self:IsDrivingSimfphys() and IsValid( sitarg:GetDriverSeat() ) and sitarg:GetDriverSeat():GetPos() or attach and attach.Pos or sitarg:GetPos()
            local ang = self:IsDrivingSimfphys() and IsValid( sitarg:GetDriverSeat() ) and sitarg:GetDriverSeat():GetAngles() + Angle( 0, 90, 0 ) or attach and attach.Ang or sitarg:GetAngles()

            self:SetMoveType( MOVETYPE_NONE )
            self:SetSolidMask( MASK_SOLID_BRUSHONLY ) -- This fixes the issues where the Nextbot doesn't actually set its position because it is in another entity. Remember this for any critical set pos moments!
            
            self.l_invehicle = self:IsDrivingSimfphys() or sitarg:IsVehicle() and sitarg:GetMaxSpeed() > 0 -- If we are in a vehicle that actually drives
            sitarg:SetSaveValue( "m_hNPCDriver", self ) -- Set the NPC driver so no one can enter the vehicle. Doesn't work on simfphys tho
            sitarg.l_lambdaseated = self
            if self:IsDrivingSimfphys() then sitarg:GetDriverSeat().l_lambdaseated = self end

            if !self.l_invehicle and !seatmodels[ sitarg:GetModel() ] then
                tracetbl2.start = sitarg:WorldSpaceCenter() + Vector( 0, 0, ( sitarg:GetModelRadius() / 2 ) + 10 )
                tracetbl2.endpos = sitarg:GetPos()
                tracetbl2.filter = self
                local result = util.TraceLine( tracetbl2 )
                if result.Entity == sitarg then 
                    self.l_seatnormvector = sitarg:WorldToLocal( result.HitPos )
                end
            end

            if self:IsDrivingSimfphys() then
                sitarg:GetDriverSeat().l_lambdaseated = self
                
                if !sitarg.l_seatmoduleexitfunc then
                    local hookTbl = hook.GetTable().PlayerLeaveVehicle
                    if hookTbl and isfunction( hookTbl.simfphysVehicleExit ) then
                        sitarg.l_seatmoduleexitfunc = hookTbl.simfphysVehicleExit
                    end
                end

                sitarg:SetActive( true )
                sitarg:StartEngine()
                sitarg:SetDriver( self )
            end

            self:SetState( !self.l_invehicle and "SitState" or "DriveState" ) -- Set our state depending on the situation

            -- Get into position
            self:SetPos( pos )
            self:SetAngles( ang )

            self:SetParent( sitarg ) 
        else
            self:SetState( "SitState" ) -- Sit on the ground
        end

        self:CancelMovement()
    end

    function self:SitState()
        self.l_nextseatlook = self.l_nextseatlook or CurTime() + math.Rand( 0.5, 6 )
        if CurTime() > self.l_nextseatlook then
            self:LookTo( self:GetPos() + VectorRand( -400, 400 ), 3, isentity( self.l_currentseatsit ) )
            self.l_nextseatlook = CurTime() + math.Rand( 0.5, 6 )
        end
    end

    function self:GetInfoNum()
        return 0
    end

    -- The pathfinding generator for vehicles
    function self:VehiclePathGenerator()
        local jumpPenalty = 10
        local stepHeight = 30
        local jumpHeight = 0
        local deathHeight = -self.loco:GetDeathDropHeight()
        local bit_band = bit.band
    
        return function( area, fromArea, ladder, elevator, length )
            if !IsValid( fromArea ) then return 0 end
            if !self.loco:IsAreaTraversable( area ) or bit_band( area:GetAttributes(), NAV_MESH_AVOID ) == NAV_MESH_AVOID then return -1 end
            if area:GetSizeX() < 70 and area:GetSizeY() < 70 then return -1 end
    
            local dist = ( length > 0 and length or fromArea:GetCenter():Distance( area:GetCenter() ) )
            local cost = ( fromArea:GetCostSoFar() + dist )
    
            local deltaZ = fromArea:ComputeAdjacentConnectionHeightChange( area )
            if deltaZ > jumpHeight or deltaZ < deathHeight then return -1 end
            if deltaZ > stepHeight then cost = cost + ( dist * jumpPenalty ) end
    
            return cost
        end
    end

    function self:IsDrivingSimfphys()
        return isentity( self.l_currentseatsit ) and IsValid( self.l_currentseatsit ) and self.l_currentseatsit.IsSimfphyscar
    end

    local function ReplaceZ( self, vector )
        vector[ 3 ] = self:GetPos()[ 3 ]
        return vector
    end

    function self:DriveToOFFNAV( pos )

        while true do
            if self:GetRangeSquaredTo( ReplaceZ( self, pos ) ) <= ( 100 * 100 ) then break end

            if !IsValid( self.l_currentseatsit ) then break end

            self.loco:Approach( pos, 1 )
            if self.loco:IsStuck() then 
                self.loco:ClearStuck()
                break
            end

            if GetConVar( "developer" ):GetBool() then
                debugoverlay.Cross( pos, 40, 0.1, color_white, false )
            end

            

            if self:IsDrivingSimfphys() then
                self.l_currentseatsit.PressedKeys[ "W" ] = false
                self.l_currentseatsit.PressedKeys[ "A" ] = false
                self.l_currentseatsit.PressedKeys[ "S" ] = false                
                self.l_currentseatsit.PressedKeys[ "D" ] = false
            else
                self.l_currentseatsit:SetHandbrake( false )
            end

            local loca = self:WorldToLocalAngles( ( pos - self:GetPos() ):Angle() )

            local locathrottle = loca + Angle( 0, 90, 0 )
            if locathrottle.y < 0 or locathrottle.y > 180 then
                if self:IsDrivingSimfphys() then 
                    self.l_currentseatsit.PressedKeys[ "S" ] = true 
                    self.l_currentseatsit:PlayerSteerVehicle( self, 0, 1 )
                else
                    self.l_currentseatsit:SetThrottle( -1 )
                    self.l_currentseatsit:SetSteering( 1, 0 )     
                end
                self:SetPoseParameter( "vehicle_steer", 1 )
            else
                local steerMath = math.Clamp( -loca.y / 5, -1, 1 )
                if self:IsDrivingSimfphys() then 
                    self.l_currentseatsit.PressedKeys[ "W" ] = true 
                    self.l_currentseatsit:PlayerSteerVehicle( self, ( ( steerMath < 0) and -steerMath or 0 ), ( ( steerMath > 0 ) and steerMath or 0 ) )
                else
                    self.l_currentseatsit:SetThrottle( 1 )
                    self.l_currentseatsit:SetSteering( steerMath, 0 )
                end
                self:SetPoseParameter( "vehicle_steer", steerMath )
            end

            coroutine.yield()
        end

        if IsValid( self.l_currentseatsit ) then 
            if self:IsDrivingSimfphys() then 
                self.l_currentseatsit.PressedKeys[ "W" ] = false
                self.l_currentseatsit.PressedKeys[ "S" ] = false
            else
                self.l_currentseatsit:SetHandbrake( true )
                self.l_currentseatsit:SetThrottle( 0 )
                self.l_currentseatsit:SetSteering( 0, 0 )
            end

            self:SetPoseParameter( "vehicle_steer", 0 )
        end

    end

    -- Drive a vehicle to a position
    function self:DriveTo( pos )
        local path = Path( "Follow" )
        path:SetGoalTolerance( 200 )

        path:Compute( self, ( !isvector( pos ) and pos:GetPos() or pos ), self:VehiclePathGenerator() )

        if !path:IsValid() then self:DriveToOFFNAV( pos ) return end 

        while path:IsValid() do

            if !IsValid( self.l_currentseatsit ) then break end

            local goalpos
            local curseg = path:GetCurrentGoal()

            if !curseg then break end

            goalpos = curseg.pos

            path:Update( self )

            if self.loco:IsStuck() then 
                self.loco:ClearStuck()
                break
            end

            if GetConVar( "developer" ):GetBool() then
                debugoverlay.Cross( goalpos, 40, 0.1, color_white, false )
                path:Draw()
            end

            

            if self:IsDrivingSimfphys() then
                self.l_currentseatsit.PressedKeys[ "W" ] = false
                self.l_currentseatsit.PressedKeys[ "A" ] = false
                self.l_currentseatsit.PressedKeys[ "S" ] = false                
                self.l_currentseatsit.PressedKeys[ "D" ] = false
            else
                self.l_currentseatsit:SetHandbrake( false )
            end

            local loca = self:WorldToLocalAngles( ( goalpos - self:GetPos() ):Angle() )

            local locathrottle = loca + Angle( 0, 90, 0 )
            if locathrottle.y < 0 or locathrottle.y > 180 then
                if self:IsDrivingSimfphys() then 
                    self.l_currentseatsit.PressedKeys[ "S" ] = true 
                    self.l_currentseatsit:PlayerSteerVehicle( self, 0, 1 )
                else
                    self.l_currentseatsit:SetThrottle( -1 )
                    self.l_currentseatsit:SetSteering( 1, 0 )     
                end
                self:SetPoseParameter( "vehicle_steer", 1 )
            else
                local steerMath = math.Clamp( -loca.y / 5, -1, 1 )
                if self:IsDrivingSimfphys() then 
                    self.l_currentseatsit.PressedKeys[ "W" ] = true 
                    self.l_currentseatsit:PlayerSteerVehicle( self, ( ( steerMath < 0) and -steerMath or 0 ), ( ( steerMath > 0 ) and steerMath or 0 ) )
                else
                    self.l_currentseatsit:SetThrottle( 1 )
                    self.l_currentseatsit:SetSteering( steerMath, 0 )
                end
                self:SetPoseParameter( "vehicle_steer", steerMath )
            end

            coroutine.yield()
        end

        if IsValid( self.l_currentseatsit ) then 
            if self:IsDrivingSimfphys() then 
                self.l_currentseatsit.PressedKeys[ "W" ] = false
                self.l_currentseatsit.PressedKeys[ "S" ] = false
            else
                self.l_currentseatsit:SetHandbrake( true )
                self.l_currentseatsit:SetThrottle( 0 )
                self.l_currentseatsit:SetSteering( 0, 0 )
            end

            self:SetPoseParameter( "vehicle_steer", 0 )
        end

    end

    function self:DriveState()
        self:DriveTo( self:GetRandomPosition() )
    end

    -- Prevent Players from picking up lambdas that are sitting
    self:Hook( "PhysgunPickup", "sitmodule_preventpickup", function( ply, ent )
        if ent == self and self.l_isseatsitting then return false end
    end, true )

    -- If the vehicle is attacked, hurt the lambda a bit
--[[     self:Hook( "PostEntityTakeDamage", "sitmodule_vehicledamage", function( ent, info )
        if ent == self.l_currentseatsit then
            info:SetDamage( info:GetDamage() / 3 )
            self:TakeDamageInfo( info )
        end
    end , true ) ]]

    -- Remove parent before it is removed
    self:Hook( "EntityRemoved", "sitmodule_vehicleremoved", function( ent )
        if ent == self.l_currentseatsit then
            self:SetParent()
        end
    end, true )

end

-- Remove ourselves from the vehicle's m_hNPCDriver internal var
local function OnRemove( self )
    if isentity( self.l_currentseatsit ) and IsValid( self.l_currentseatsit ) then 
        self.l_currentseatsit:SetSaveValue( "m_hNPCDriver", NULL )
        self.l_currentseatsit.l_lambdaseated = nil

        if self:IsDrivingSimfphys() then
            self.l_currentseatsit:GetDriverSeat().l_lambdaseated = nil
            self.l_currentseatsit:SetActive( false )
            self.l_currentseatsit:StartEngine()
            self.l_currentseatsit:SetDriver( NULL )
            self.l_currentseatsit.PressedKeys[ "W" ] = false
            self.l_currentseatsit.PressedKeys[ "S" ] = false
        elseif self.l_invehicle then
            self.l_currentseatsit:SetThrottle( 0 )
            self.l_currentseatsit:SetSteering( 0, 0 )
        end
    end
end


local function Think( self )
    if CLIENT then return end


    -- We are currently sitting either on the ground or on/driving a entity
    if self.l_isseatsitting and ( self:GetState() == "SitState" or self:GetState() == "DriveState" ) and self:Alive() then
        self.l_wasseatsitting = true
        self.l_UpdateAnimations = false

        -- If they aren't valid, abort. Or if the simfphys vehicle is on fire, abort. Or if the time is up
        if isentity( self.l_currentseatsit ) and !IsValid( self.l_currentseatsit ) or IsValid( self.l_currentseatsit ) and ( self:IsDrivingSimfphys() and self.l_currentseatsit:OnFire() or self.l_currentseatsit:GetOwner().IsSimfphyscar and self.l_currentseatsit:GetOwner():OnFire() ) or ( self.l_sitendtime and CurTime() > self.l_sitendtime ) then 
            self.l_isseatsitting = false
            return
        end

        local attach
        if isentity( self.l_currentseatsit ) and IsValid( self.l_currentseatsit ) then -- Get the entity's attachment for us
            attach = self.l_currentseatsit:GetAttachment( self.l_currentseatsit:LookupAttachment( "vehicle_feet_passenger0" ) )
        end

        local pos, ang
        -- Get the positions and angles
        if isentity( self.l_currentseatsit ) and IsValid( self.l_currentseatsit ) then 
            local seat = self.l_currentseatsit
            pos = self:IsDrivingSimfphys() and seat:GetDriverSeat():GetPos() or attach and attach.Pos or seat:GetPos()
            ang = self:IsDrivingSimfphys() and seat:GetDriverSeat():GetAngles() + Angle( 0, 90, 0 ) or attach and attach.Ang or seat:GetAngles()

            if self.l_seatnormvector then pos = pos + seat:GetForward() * self.l_seatnormvector[ 1 ] + seat:GetRight() * self.l_seatnormvector[ 2 ] + seat:GetUp() * self.l_seatnormvector[ 3 ] end

            if !self.l_PoseOnly then self.Face = nil end -- Preventing facing in vehicles
            self.loco:SetVelocity( Vector() )
        end

        -- Set our position and angles if possible
        if pos then self:SetPos( pos ) end
        if ang then self:SetAngles( ang ) end

        if !self.l_currentseatsit and self:GetActivity() != ACT_GMOD_SHOWOFF_DUCK_02 then -- Sitting on ground
            self:SetActivity( ACT_GMOD_SHOWOFF_DUCK_02 )
        elseif isentity( self.l_currentseatsit ) and IsValid( self.l_currentseatsit ) and self.l_invehicle and self:GetActivity() != ACT_DRIVE_JEEP then -- Sitting in a vehicle
            self:SetActivity( ACT_DRIVE_JEEP )
        elseif isentity( self.l_currentseatsit ) and IsValid( self.l_currentseatsit ) and !self.l_invehicle and self:GetActivity() != ACT_GMOD_SIT_ROLLERCOASTER then -- Sitting in a chair
            self:SetActivity( ACT_GMOD_SIT_ROLLERCOASTER )
        end

    elseif self.l_wasseatsitting then -- We aren't sitting/driving anymore. Reset to normal operations
        self:ResetSitInfo()
    end

end

hook.Add( "LambdaOnRemove", "lambdaseatmodule_remove", OnRemove )
hook.Add( "LambdaOnThink", "lambdaseatmodule_think", Think )
hook.Add( "LambdaOnInitialize", "lambdaseatmodule_init", Initialize )




-- Now we actually make use the of the seat module

-- Random sitting
AddUActionToLambdaUA( function( self )
    if allowsitting:GetBool() and !self:InCombat() and !self:IsSitting() and math.random( 0, 100 ) < 50 then 
        local nearent = math.random( 1, 3 ) == 1 and self:GetClosestEntity( nil, 100, function( ent ) return ent:GetClass() == "prop_physics" and self:CanSee( ent ) end ) or nil
        self:Sit( nearent, math.Rand( 5, 60 ) ) 
    end
end )


-- Vehicle driving
LambdaCreatePersonalityType( "Vehicle", function( self )
    local hassimfphys = false
    local nearent = self:GetClosestEntity( nil, 3000, function( ent ) 
        if ent.IsSimfphyscar and IsSimfphysOpen( ent ) and self:CanSee( ent ) then hassimfphys = true return true end
        if !ent.IsSimfphyscar and !hassimfphys and ent:IsVehicle() and !IsValid( ent:GetInternalVariable( "m_hNPCDriver" ) ) and !IsValid( ent.l_lambdaseated ) then return true end
    end )

    if IsValid( nearent ) then
        self:MoveToPos( nearent:GetPos() + ( self:GetPos() - nearent:GetPos() ):GetNormalized() * 100, { autorun = true } )
        if !IsValid( nearent ) then return end
        if self:IsInRange( nearent, 200 ) then self:Sit( nearent, math.Rand( 10, 90 ) )  end
    end
end )
