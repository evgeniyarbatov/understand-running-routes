
-- Foot profile

api_version = 2

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require('lib/way_handlers')
find_access_tag = require('lib/access').find_access_tag

function setup()
walking_speed = 5
  return {
    properties = {
      weight_name                   = 'duration',
      max_speed_for_map_matching    = 40/3.6, -- kmph -> m/s
      call_tagless_node_function    = false,
      traffic_light_penalty         = 2,
      u_turn_penalty                = 2,
      continue_straight_at_waypoint = false,
      use_turn_restrictions         = false,
    },

    default_mode            = mode.walking,
    default_speed           = walking_speed,
    oneway_handling         = 'specific',     -- respect 'oneway:foot' but not 'oneway'

    barrier_blacklist = Set {
      'yes',
      'wall',
      'fence'
    },

    access_tag_whitelist = Set {
      'yes',
      'foot',
      'permissive',
      'designated'
    },

    access_tag_blacklist = Set {
      'no',
      'agricultural',
      'forestry',
      'private',
      'delivery',
    },

    restricted_access_tag_list = Set { },

    restricted_highway_whitelist = Set { },

    construction_whitelist = Set {},

    access_tags_hierarchy = Sequence {
      'foot',
      'access'
    },

    -- tags disallow access to in combination with highway=service
    service_access_tag_blacklist = Set { },

    restrictions = Sequence {
      'foot'
    },

    -- list of suffixes to suppress in name change instructions
    suffix_list = Set {
      'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'North', 'South', 'West', 'East'
    },

    avoid = Set {
      'impassable',
      'proposed'
    },

    speeds = Sequence {
      highway = {
        primary         = walking_speed,
        primary_link    = walking_speed,
        secondary       = walking_speed,
        secondary_link  = walking_speed,
        tertiary        = walking_speed,
        tertiary_link   = walking_speed,
        unclassified    = walking_speed,
        residential     = walking_speed,
        road            = walking_speed,
        living_street   = walking_speed,
        service         = walking_speed,
        track           = walking_speed,
        path            = walking_speed,
        steps           = walking_speed,
        pedestrian      = walking_speed,
        footway         = walking_speed,
        pier            = walking_speed,
      },

      railway = {
        platform        = walking_speed
      },

      amenity = {
        parking         = walking_speed,
        parking_entrance= walking_speed
      },

      man_made = {
        pier            = walking_speed
      },

      leisure = {
        track           = walking_speed
      }
    },

    route_speeds = {
      ferry = 5
    },

    bridge_speeds = {
    },

    surface_speeds = {
      fine_gravel =   walking_speed*0.75,
      gravel =        walking_speed*0.75,
      pebblestone =   walking_speed*0.75,
      mud =           walking_speed*0.5,
      sand =          walking_speed*0.5
    },

    tracktype_speeds = {
    },

    smoothness_speeds = {
    }
  }
end

function process_node(profile, node, result)
  -- parse access and barrier tags
  local access = find_access_tag(node, profile.access_tags_hierarchy)
  if access then
    if profile.access_tag_blacklist[access] then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key('barrier')
    if barrier then
      --  make an exception for rising bollard barriers
      local bollard = node:get_value_by_key('bollard')
      local rising_bollard = bollard and 'rising' == bollard

      if profile.barrier_blacklist[barrier] and not rising_bollard then
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key('highway')
  if 'traffic_signals' == tag then
    -- Direction should only apply to vehicles
    result.traffic_lights = true
  end
end

-- main entry point for processsing a way
function process_way(profile, way, result)
  -- the intial filtering of ways based on presence of tags
  -- affects processing times significantly, because all ways
  -- have to be checked.
  -- to increase performance, prefetching and intial tag check
  -- is done in directly instead of via a handler.

  -- in general we should  try to abort as soon as
  -- possible if the way is not routable, to avoid doing
  -- unnecessary work. this implies we should check things that
  -- commonly forbids access early, and handle edge cases later.

  -- data table for storing intermediate values during processing
  local data = {
    -- prefetch tags
    highway = way:get_value_by_key('highway'),
    bridge = way:get_value_by_key('bridge'),
    route = way:get_value_by_key('route'),
    leisure = way:get_value_by_key('leisure'),
    man_made = way:get_value_by_key('man_made'),
    railway = way:get_value_by_key('railway'),
    platform = way:get_value_by_key('platform'),
    amenity = way:get_value_by_key('amenity'),
    public_transport = way:get_value_by_key('public_transport')
  }

  -- perform an quick initial check and abort if the way is
  -- obviously not routable. here we require at least one
  -- of the prefetched tags to be present, ie. the data table
  -- cannot be empty
  if next(data) == nil then     -- is the data table empty?
    return
  end

  local handlers = Sequence {
    -- set the default mode for this profile. if can be changed later
    -- in case it turns we're e.g. on a ferry
    WayHandlers.default_mode,

    -- check various tags that could indicate that the way is not
    -- routable. this includes things like status=impassable,
    -- toll=yes and oneway=reversible
    WayHandlers.blocked_ways,

    -- determine access status by checking our hierarchy of
    -- access tags, e.g: motorcar, motor_vehicle, vehicle
    WayHandlers.access,

    -- check whether forward/backward directons are routable
    WayHandlers.oneway,

    -- check whether forward/backward directons are routable
    WayHandlers.destinations,

    -- check whether we're using a special transport mode
    WayHandlers.ferries,
    WayHandlers.movables,

    -- compute speed taking into account way type, maxspeed tags, etc.
    WayHandlers.speed,
    WayHandlers.surface,

    -- handle turn lanes and road classification, used for guidance
    WayHandlers.classification,

    -- handle various other flags
    WayHandlers.roundabouts,
    WayHandlers.startpoint,

    -- set name, ref and pronunciation
    WayHandlers.names,

    -- set weight properties of the way
    WayHandlers.weights,

    custom_tag_weights
  }

  WayHandlers.run(profile, way, result, data, handlers)
end

function process_turn (profile, turn)
  turn.duration = 0.

  if turn.direction_modifier == direction_modifier.u_turn then
     turn.duration = turn.duration + profile.properties.u_turn_penalty
  end

  if turn.has_traffic_light then
     turn.duration = profile.properties.traffic_light_penalty
  end
  if profile.properties.weight_name == 'routability' then
      -- penalize turns from non-local access only segments onto local access only tags
      if not turn.source_restricted and turn.target_restricted then
          turn.weight = turn.weight + 3000
      end
  end
end


function custom_tag_weights(profile, way, result, data)
  local foot = way:get_value_by_key('foot')
  local footway = way:get_value_by_key('footway')
  local highway = way:get_value_by_key('highway')
  local incline = way:get_value_by_key('incline')
  local lit = way:get_value_by_key('lit')
  local sidewalk = way:get_value_by_key('sidewalk')
  local surface = way:get_value_by_key('surface')
  local trail_visibility = way:get_value_by_key('trail_visibility')
  if foot == 'yes' then
     result.forward_speed = walking_speed * 74.65011418867482
     result.backward_speed = walking_speed * 74.65011418867482
  elseif foot == 'designated' then
     result.forward_speed = walking_speed * 19.8044152954266
     result.backward_speed = walking_speed * 19.8044152954266
  elseif foot == 'no' then
     result.forward_speed = walking_speed * 4.503132868770861
     result.backward_speed = walking_speed * 4.503132868770861
  elseif foot == 'permissive' then
     result.forward_speed = walking_speed * 0.69098787843298
     result.backward_speed = walking_speed * 0.69098787843298
  elseif foot == 'use_sidepath' then
     result.forward_speed = walking_speed * 0.2927914739122796
     result.backward_speed = walking_speed * 0.2927914739122796
  elseif foot == 'private' then
     result.forward_speed = walking_speed * 0.0585582947824559
     result.backward_speed = walking_speed * 0.0585582947824559
  elseif footway == 'crossing' then
     result.forward_speed = walking_speed * 66.43498898118325
     result.backward_speed = walking_speed * 66.43498898118325
  elseif footway == 'sidewalk' then
     result.forward_speed = walking_speed * 31.09001525682319
     result.backward_speed = walking_speed * 31.09001525682319
  elseif footway == 'yes' then
     result.forward_speed = walking_speed * 2.4749957619935583
     result.backward_speed = walking_speed * 2.4749957619935583
  elseif highway == 'footway' then
     result.forward_speed = walking_speed * 38.37061124049743
     result.backward_speed = walking_speed * 38.37061124049743
  elseif highway == 'residential' then
     result.forward_speed = walking_speed * 13.81003647229424
     result.backward_speed = walking_speed * 13.81003647229424
  elseif highway == 'service' then
     result.forward_speed = walking_speed * 9.453135299028869
     result.backward_speed = walking_speed * 9.453135299028869
  elseif highway == 'primary' then
     result.forward_speed = walking_speed * 7.237333567693457
     result.backward_speed = walking_speed * 7.237333567693457
  elseif highway == 'cycleway' then
     result.forward_speed = walking_speed * 6.860526431427692
     result.backward_speed = walking_speed * 6.860526431427692
  elseif highway == 'steps' then
     result.forward_speed = walking_speed * 6.505690556751769
     result.backward_speed = walking_speed * 6.505690556751769
  elseif highway == 'path' then
     result.forward_speed = walking_speed * 4.570022410686821
     result.backward_speed = walking_speed * 4.570022410686821
  elseif highway == 'secondary' then
     result.forward_speed = walking_speed * 4.009755240145889
     result.backward_speed = walking_speed * 4.009755240145889
  elseif highway == 'tertiary' then
     result.forward_speed = walking_speed * 2.660719778529683
     result.backward_speed = walking_speed * 2.660719778529683
  elseif highway == 'unclassified' then
     result.forward_speed = walking_speed * 1.9675264753702155
     result.backward_speed = walking_speed * 1.9675264753702155
  elseif highway == 'primary_link' then
     result.forward_speed = walking_speed * 1.2864173660851606
     result.backward_speed = walking_speed * 1.2864173660851606
  elseif highway == 'track' then
     result.forward_speed = walking_speed * 0.7986553587907017
     result.backward_speed = walking_speed * 0.7986553587907017
  elseif highway == 'trunk' then
     result.forward_speed = walking_speed * 0.4273410379223975
     result.backward_speed = walking_speed * 0.4273410379223975
  elseif highway == 'living_street' then
     result.forward_speed = walking_speed * 0.3910884562991607
     result.backward_speed = walking_speed * 0.3910884562991607
  elseif highway == 'pedestrian' then
     result.forward_speed = walking_speed * 0.3647229423913521
     result.backward_speed = walking_speed * 0.3647229423913521
  elseif highway == 'construction' then
     result.forward_speed = walking_speed * 0.3032034099397988
     result.backward_speed = walking_speed * 0.3032034099397988
  elseif highway == 'secondary_link' then
     result.forward_speed = walking_speed * 0.2867249637474184
     result.backward_speed = walking_speed * 0.2867249637474184
  elseif highway == 'motorway_link' then
     result.forward_speed = walking_speed * 0.2823307114294502
     result.backward_speed = walking_speed * 0.2823307114294502
  elseif highway == 'trunk_link' then
     result.forward_speed = walking_speed * 0.2010370435470404
     result.backward_speed = walking_speed * 0.2010370435470404
  elseif highway == 'tertiary_link' then
     result.forward_speed = walking_speed * 0.1120534341081864
     result.backward_speed = walking_speed * 0.1120534341081864
  elseif highway == 'road' then
     result.forward_speed = walking_speed * 0.046139649338665
     result.backward_speed = walking_speed * 0.046139649338665
  elseif highway == 'corridor' then
     result.forward_speed = walking_speed * 0.0285626400667926
     result.backward_speed = walking_speed * 0.0285626400667926
  elseif highway == 'proposed' then
     result.forward_speed = walking_speed * 0.0230698246693325
     result.backward_speed = walking_speed * 0.0230698246693325
  elseif highway == 'raceway' then
     result.forward_speed = walking_speed * 0.002197126158984
     result.backward_speed = walking_speed * 0.002197126158984
  elseif highway == 'bridleway' then
     result.forward_speed = walking_speed * 0.001098563079492
     result.backward_speed = walking_speed * 0.001098563079492
  elseif incline == 'down' then
     result.forward_speed = walking_speed * 55.92894863178108
     result.backward_speed = walking_speed * 55.92894863178108
  elseif incline == 'up' then
     result.forward_speed = walking_speed * 43.51896303408546
     result.backward_speed = walking_speed * 43.51896303408546
  elseif incline == '0%' then
     result.forward_speed = walking_speed * 0.3120499279884782
     result.backward_speed = walking_speed * 0.3120499279884782
  elseif incline == 'd' then
     result.forward_speed = walking_speed * 0.1680268843014882
     result.backward_speed = walking_speed * 0.1680268843014882
  elseif incline == 'up/down' then
     result.forward_speed = walking_speed * 0.0480076812289966
     result.backward_speed = walking_speed * 0.0480076812289966
  elseif incline == 'yes' then
     result.forward_speed = walking_speed * 0.0240038406144983
     result.backward_speed = walking_speed * 0.0240038406144983
  elseif lit == 'no' then
     result.forward_speed = walking_speed * 61.396262529592505
     result.backward_speed = walking_speed * 61.396262529592505
  elseif lit == 'yes' then
     result.forward_speed = walking_speed * 38.603737470407495
     result.backward_speed = walking_speed * 38.603737470407495
  elseif sidewalk == 'left' then
     result.forward_speed = walking_speed * 44.425134912649774
     result.backward_speed = walking_speed * 44.425134912649774
  elseif sidewalk == 'both' then
     result.forward_speed = walking_speed * 22.601298820085976
     result.backward_speed = walking_speed * 22.601298820085976
  elseif sidewalk == 'no' then
     result.forward_speed = walking_speed * 17.140766486783136
     result.backward_speed = walking_speed * 17.140766486783136
  elseif sidewalk == 'right' then
     result.forward_speed = walking_speed * 10.207628281350042
     result.backward_speed = walking_speed * 10.207628281350042
  elseif sidewalk == 'separate' then
     result.forward_speed = walking_speed * 3.3019299368883197
     result.backward_speed = walking_speed * 3.3019299368883197
  elseif sidewalk == 'none' then
     result.forward_speed = walking_speed * 2.3232415622427514
     result.backward_speed = walking_speed * 2.3232415622427514
  elseif surface == 'asphalt' then
     result.forward_speed = walking_speed * 60.87157630422573
     result.backward_speed = walking_speed * 60.87157630422573
  elseif surface == 'dirt' then
     result.forward_speed = walking_speed * 13.369346152575412
     result.backward_speed = walking_speed * 13.369346152575412
  elseif surface == 'concrete' then
     result.forward_speed = walking_speed * 10.252089734694552
     result.backward_speed = walking_speed * 10.252089734694552
  elseif surface == 'gravel' then
     result.forward_speed = walking_speed * 3.1849869494829353
     result.backward_speed = walking_speed * 3.1849869494829353
  elseif surface == 'paved' then
     result.forward_speed = walking_speed * 2.702613407341329
     result.backward_speed = walking_speed * 2.702613407341329
  elseif surface == 'paving_stones' then
     result.forward_speed = walking_speed * 2.4250834241913632
     result.backward_speed = walking_speed * 2.4250834241913632
  elseif surface == 'ground' then
     result.forward_speed = walking_speed * 2.1425975484851487
     result.backward_speed = walking_speed * 2.1425975484851487
  elseif surface == 'wood' then
     result.forward_speed = walking_speed * 1.1101199325998612
     result.backward_speed = walking_speed * 1.1101199325998612
  elseif surface == 'metal' then
     result.forward_speed = walking_speed * 0.908580301979053
     result.backward_speed = walking_speed * 0.908580301979053
  elseif surface == 'unpaved' then
     result.forward_speed = walking_speed * 0.8177222717811479
     result.backward_speed = walking_speed * 0.8177222717811479
  elseif surface == 'concrete:plates' then
     result.forward_speed = walking_speed * 0.5104569332936861
     result.backward_speed = walking_speed * 0.5104569332936861
  elseif surface == 'fine_gravel' then
     result.forward_speed = walking_speed * 0.308917302672878
     result.backward_speed = walking_speed * 0.308917302672878
  elseif surface == 'compacted' then
     result.forward_speed = walking_speed * 0.2808339115207982
     result.backward_speed = walking_speed * 0.2808339115207982
  elseif surface == 'sett' then
     result.forward_speed = walking_speed * 0.2197112366603892
     result.backward_speed = walking_speed * 0.2197112366603892
  elseif surface == 'grass' then
     result.forward_speed = walking_speed * 0.2031915948062246
     result.backward_speed = walking_speed * 0.2031915948062246
  elseif surface == 'unhewn_cobblestone' then
     result.forward_speed = walking_speed * 0.1998876664353916
     result.backward_speed = walking_speed * 0.1998876664353916
  elseif surface == 'pebblestone' then
     result.forward_speed = walking_speed * 0.1685003469124789
     result.backward_speed = walking_speed * 0.1685003469124789
  elseif surface == 'tartan' then
     result.forward_speed = walking_speed * 0.1552846334291472
     result.backward_speed = walking_speed * 0.1552846334291472
  elseif surface == 'turf' then
     result.forward_speed = walking_speed * 0.0941619585687382
     result.backward_speed = walking_speed * 0.0941619585687382
  elseif surface == 'grass_paver' then
     result.forward_speed = walking_speed * 0.0198235702249975
     result.backward_speed = walking_speed * 0.0198235702249975
  elseif surface == 'cobblestone' then
     result.forward_speed = walking_speed * 0.0115637492979152
     result.backward_speed = walking_speed * 0.0115637492979152
  elseif surface == 'concrete:lanes' then
     result.forward_speed = walking_speed * 0.0082598209270823
     result.backward_speed = walking_speed * 0.0082598209270823
  elseif surface == 'mud' then
     result.forward_speed = walking_speed * 0.0082598209270823
     result.backward_speed = walking_speed * 0.0082598209270823
  elseif surface == 'rock' then
     result.forward_speed = walking_speed * 0.0066078567416658
     result.backward_speed = walking_speed * 0.0066078567416658
  elseif surface == 'drain' then
     result.forward_speed = walking_speed * 0.0066078567416658
     result.backward_speed = walking_speed * 0.0066078567416658
  elseif surface == 'sand' then
     result.forward_speed = walking_speed * 0.0066078567416658
     result.backward_speed = walking_speed * 0.0066078567416658
  elseif surface == 'dirt/sand' then
     result.forward_speed = walking_speed * 0.0033039283708329
     result.backward_speed = walking_speed * 0.0033039283708329
  elseif surface == 'earth' then
     result.forward_speed = walking_speed * 0.0016519641854164
     result.backward_speed = walking_speed * 0.0016519641854164
  elseif surface == 'clay' then
     result.forward_speed = walking_speed * 0.0016519641854164
     result.backward_speed = walking_speed * 0.0016519641854164
  elseif trail_visibility == 'excellent' then
     result.forward_speed = walking_speed * 65.62130177514793
     result.backward_speed = walking_speed * 65.62130177514793
  elseif trail_visibility == 'good' then
     result.forward_speed = walking_speed * 33.49112426035503
     result.backward_speed = walking_speed * 33.49112426035503
  elseif trail_visibility == 'bad' then
     result.forward_speed = walking_speed * 0.8875739644970414
     result.backward_speed = walking_speed * 0.8875739644970414
  else
    result.forward_speed = walking_speed
    result.backward_speed = walking_speed
  end
end


return {
  setup = setup,
  process_way =  process_way,
  process_node = process_node,
  process_turn = process_turn
}
