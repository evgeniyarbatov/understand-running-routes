
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
  local crossing = way:get_value_by_key('crossing')
  local footway = way:get_value_by_key('footway')
  local highway = way:get_value_by_key('highway')
  local oneway = way:get_value_by_key('oneway')
  local surface = way:get_value_by_key('surface')
  if crossing == 'uncontrolled' then
     result.forward_speed = walking_speed * 100.0
     result.backward_speed = walking_speed * 100.0
  elseif crossing == 'traffic_signals' then
     result.forward_speed = walking_speed * 92.8212478920742
     result.backward_speed = walking_speed * 92.8212478920742
  elseif crossing == 'marked' then
     result.forward_speed = walking_speed * 91.65261382799324
     result.backward_speed = walking_speed * 91.65261382799324
  elseif crossing == 'unmarked' then
     result.forward_speed = walking_speed * 22.70320404721754
     result.backward_speed = walking_speed * 22.70320404721754
  elseif footway == 'sidewalk' then
     result.forward_speed = walking_speed * 100.0
     result.backward_speed = walking_speed * 100.0
  elseif highway == 'service' then
     result.forward_speed = walking_speed * 100.0
     result.backward_speed = walking_speed * 100.0
  elseif highway == 'residential' then
     result.forward_speed = walking_speed * 63.39966528530443
     result.backward_speed = walking_speed * 63.39966528530443
  elseif highway == 'footway' then
     result.forward_speed = walking_speed * 55.47840293273829
     result.backward_speed = walking_speed * 55.47840293273829
  elseif highway == 'tertiary' then
     result.forward_speed = walking_speed * 7.44588779088301
     result.backward_speed = walking_speed * 7.44588779088301
  elseif highway == 'primary' then
     result.forward_speed = walking_speed * 7.106630538731272
     result.backward_speed = walking_speed * 7.106630538731272
  elseif highway == 'secondary' then
     result.forward_speed = walking_speed * 3.7219477207523113
     result.backward_speed = walking_speed * 3.7219477207523113
  elseif highway == 'primary_link' then
     result.forward_speed = walking_speed * 2.4832642652215493
     result.backward_speed = walking_speed * 2.4832642652215493
  elseif highway == 'steps' then
     result.forward_speed = walking_speed * 2.3254701944532994
     result.backward_speed = walking_speed * 2.3254701944532994
  elseif highway == 'pedestrian' then
     result.forward_speed = walking_speed * 1.5286101370736374
     result.backward_speed = walking_speed * 1.5286101370736374
  elseif highway == 'path' then
     result.forward_speed = walking_speed * 1.4497131016895124
     result.backward_speed = walking_speed * 1.4497131016895124
  elseif highway == 'secondary_link' then
     result.forward_speed = walking_speed * 1.3708160663053874
     result.backward_speed = walking_speed * 1.3708160663053874
  elseif highway == 'tertiary_link' then
     result.forward_speed = walking_speed * 1.142014663691425
     result.backward_speed = walking_speed * 1.142014663691425
  elseif highway == 'trunk_link' then
     result.forward_speed = walking_speed * 1.142014663691425
     result.backward_speed = walking_speed * 1.142014663691425
  elseif oneway == 'yes' then
     result.forward_speed = walking_speed * 100.0
     result.backward_speed = walking_speed * 100.0
  elseif surface == 'asphalt' then
     result.forward_speed = walking_speed * 100.0
     result.backward_speed = walking_speed * 100.0
  elseif surface == 'concrete' then
     result.forward_speed = walking_speed * 9.15934065934066
     result.backward_speed = walking_speed * 9.15934065934066
  elseif surface == 'paving_stones' then
     result.forward_speed = walking_speed * 5.181662087912088
     result.backward_speed = walking_speed * 5.181662087912088
  elseif surface == 'concrete:plates' then
     result.forward_speed = walking_speed * 4.365728021978022
     result.backward_speed = walking_speed * 4.365728021978022
  elseif surface == 'unpaved' then
     result.forward_speed = walking_speed * 1.1699862637362637
     result.backward_speed = walking_speed * 1.1699862637362637
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
