-- Foot profile

api_version = 2

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers")
find_access_tag = require("lib/access").find_access_tag

function setup()
  local walking_speed = 5
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
    local barrier = node:get_value_by_key("barrier")
    if barrier then
      --  make an exception for rising bollard barriers
      local bollard = node:get_value_by_key("bollard")
      local rising_bollard = bollard and "rising" == bollard

      if profile.barrier_blacklist[barrier] and not rising_bollard then
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key("highway")
  if "traffic_signals" == tag then
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
  local name = way:get_value_by_key('name')
  local oneway = way:get_value_by_key('oneway')
  local surface = way:get_value_by_key('surface')
  if crossing == 'uncontrolled' then
      result.forward_rate = result.forward_speed * 100.0
      result.backward_rate = result.backward_speed * 100.0
  end
  if crossing == 'traffic_signals' then
      result.forward_rate = result.forward_speed * 92.8212478920742
      result.backward_rate = result.backward_speed * 92.8212478920742
  end
  if crossing == 'marked' then
      result.forward_rate = result.forward_speed * 91.65261382799324
      result.backward_rate = result.backward_speed * 91.65261382799324
  end
  if crossing == 'unmarked' then
      result.forward_rate = result.forward_speed * 22.70320404721754
      result.backward_rate = result.backward_speed * 22.70320404721754
  end
  if crossing == 'zebra' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if footway == 'sidewalk' then
      result.forward_rate = result.forward_speed * 100.0
      result.backward_rate = result.backward_speed * 100.0
  end
  if footway == 'crossing' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if highway == 'service' then
      result.forward_rate = result.forward_speed * 100.0
      result.backward_rate = result.backward_speed * 100.0
  end
  if highway == 'residential' then
      result.forward_rate = result.forward_speed * 63.39966528530443
      result.backward_rate = result.backward_speed * 63.39966528530443
  end
  if highway == 'footway' then
      result.forward_rate = result.forward_speed * 55.47840293273829
      result.backward_rate = result.backward_speed * 55.47840293273829
  end
  if highway == 'tertiary' then
      result.forward_rate = result.forward_speed * 7.44588779088301
      result.backward_rate = result.backward_speed * 7.44588779088301
  end
  if highway == 'primary' then
      result.forward_rate = result.forward_speed * 7.106630538731272
      result.backward_rate = result.backward_speed * 7.106630538731272
  end
  if highway == 'secondary' then
      result.forward_rate = result.forward_speed * 3.7219477207523113
      result.backward_rate = result.backward_speed * 3.7219477207523113
  end
  if highway == 'primary_link' then
      result.forward_rate = result.forward_speed * 2.4832642652215493
      result.backward_rate = result.backward_speed * 2.4832642652215493
  end
  if highway == 'steps' then
      result.forward_rate = result.forward_speed * 2.3254701944532994
      result.backward_rate = result.backward_speed * 2.3254701944532994
  end
  if highway == 'pedestrian' then
      result.forward_rate = result.forward_speed * 1.5286101370736374
      result.backward_rate = result.backward_speed * 1.5286101370736374
  end
  if highway == 'path' then
      result.forward_rate = result.forward_speed * 1.4497131016895124
      result.backward_rate = result.backward_speed * 1.4497131016895124
  end
  if highway == 'secondary_link' then
      result.forward_rate = result.forward_speed * 1.3708160663053874
      result.backward_rate = result.backward_speed * 1.3708160663053874
  end
  if highway == 'tertiary_link' then
      result.forward_rate = result.forward_speed * 1.142014663691425
      result.backward_rate = result.backward_speed * 1.142014663691425
  end
  if highway == 'trunk_link' then
      result.forward_rate = result.forward_speed * 1.142014663691425
      result.backward_rate = result.backward_speed * 1.142014663691425
  end
  if highway == 'track' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Minh Khai' then
      result.forward_rate = result.forward_speed * 100.0
      result.backward_rate = result.backward_speed * 100.0
  end
  if name == 'Đường Số 1 Times City' then
      result.forward_rate = result.forward_speed * 65.29520295202953
      result.backward_rate = result.backward_speed * 65.29520295202953
  end
  if name == 'Đường Số 4' then
      result.forward_rate = result.forward_speed * 53.42250922509225
      result.backward_rate = result.backward_speed * 53.42250922509225
  end
  if name == 'Đường Số 5 Times City' then
      result.forward_rate = result.forward_speed * 45.93357933579336
      result.backward_rate = result.backward_speed * 45.93357933579336
  end
  if name == 'Đường Số 7 Times City' then
      result.forward_rate = result.forward_speed * 32.23431734317343
      result.backward_rate = result.backward_speed * 32.23431734317343
  end
  if name == 'Phố Kim Ngưu' then
      result.forward_rate = result.forward_speed * 32.05166051660517
      result.backward_rate = result.backward_speed * 32.05166051660517
  end
  if name == 'Ngõ 13 Đường Lĩnh Nam' then
      result.forward_rate = result.forward_speed * 23.83210332103321
      result.backward_rate = result.backward_speed * 23.83210332103321
  end
  if name == 'Đường Số 2 Times City' then
      result.forward_rate = result.forward_speed * 21.457564575645755
      result.backward_rate = result.backward_speed * 21.457564575645755
  end
  if name == 'Đường Số 3 Times City' then
      result.forward_rate = result.forward_speed * 21.274907749077492
      result.backward_rate = result.backward_speed * 21.274907749077492
  end
  if name == 'Đường Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 17.987084870848708
      result.backward_rate = result.backward_speed * 17.987084870848708
  end
  if name == 'Phố Đinh Tiên Hoàng' then
      result.forward_rate = result.forward_speed * 17.07380073800738
      result.backward_rate = result.backward_speed * 17.07380073800738
  end
  if name == 'Đường Đại Cồ Việt' then
      result.forward_rate = result.forward_speed * 16.525830258302584
      result.backward_rate = result.backward_speed * 16.525830258302584
  end
  if name == 'Phố Lê Thái Tổ' then
      result.forward_rate = result.forward_speed * 16.343173431734318
      result.backward_rate = result.backward_speed * 16.343173431734318
  end
  if name == 'Phố Quang Trung' then
      result.forward_rate = result.forward_speed * 15.79520295202952
      result.backward_rate = result.backward_speed * 15.79520295202952
  end
  if name == 'Phố Chùa Quỳnh' then
      result.forward_rate = result.forward_speed * 15.247232472324724
      result.backward_rate = result.backward_speed * 15.247232472324724
  end
  if name == 'Phố Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 15.064575645756458
      result.backward_rate = result.backward_speed * 15.064575645756458
  end
  if name == 'Phố Nhà Chung' then
      result.forward_rate = result.forward_speed * 13.785977859778598
      result.backward_rate = result.backward_speed * 13.785977859778598
  end
  if name == 'Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 13.2380073800738
      result.backward_rate = result.backward_speed * 13.2380073800738
  end
  if name == 'Phố Hồng Mai' then
      result.forward_rate = result.forward_speed * 12.324723247232471
      result.backward_rate = result.backward_speed * 12.324723247232471
  end
  if name == 'Ngõ 622 Phố Minh Khai' then
      result.forward_rate = result.forward_speed * 11.411439114391143
      result.backward_rate = result.backward_speed * 11.411439114391143
  end
  if name == 'Phố Thanh Nhàn' then
      result.forward_rate = result.forward_speed * 11.228782287822876
      result.backward_rate = result.backward_speed * 11.228782287822876
  end
  if name == 'Vinhomes Times City' then
      result.forward_rate = result.forward_speed * 10.863468634686347
      result.backward_rate = result.backward_speed * 10.863468634686347
  end
  if name == 'Phố Hàng Đào' then
      result.forward_rate = result.forward_speed * 10.31549815498155
      result.backward_rate = result.backward_speed * 10.31549815498155
  end
  if name == 'Phố Nguyễn Văn Viên' then
      result.forward_rate = result.forward_speed * 10.132841328413283
      result.backward_rate = result.backward_speed * 10.132841328413283
  end
  if name == 'Đường Số 1' then
      result.forward_rate = result.forward_speed * 9.767527675276751
      result.backward_rate = result.backward_speed * 9.767527675276751
  end
  if name == 'Phố Võ Thị Sáu' then
      result.forward_rate = result.forward_speed * 9.40221402214022
      result.backward_rate = result.backward_speed * 9.40221402214022
  end
  if name == 'Phố Phan Chu Trinh' then
      result.forward_rate = result.forward_speed * 9.219557195571957
      result.backward_rate = result.backward_speed * 9.219557195571957
  end
  if name == 'Phố Gia Ngư' then
      result.forward_rate = result.forward_speed * 8.306273062730627
      result.backward_rate = result.backward_speed * 8.306273062730627
  end
  if name == 'Phố Nhà Thờ' then
      result.forward_rate = result.forward_speed * 7.940959409594096
      result.backward_rate = result.backward_speed * 7.940959409594096
  end
  if name == 'Phố Nguyễn Khắc Cần' then
      result.forward_rate = result.forward_speed * 7.940959409594096
      result.backward_rate = result.backward_speed * 7.940959409594096
  end
  if name == 'Ngõ E8 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 7.392988929889299
      result.backward_rate = result.backward_speed * 7.392988929889299
  end
  if name == 'Phố Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 7.392988929889299
      result.backward_rate = result.backward_speed * 7.392988929889299
  end
  if name == 'Phố Quỳnh Lôi' then
      result.forward_rate = result.forward_speed * 7.210332103321033
      result.backward_rate = result.backward_speed * 7.210332103321033
  end
  if name == 'Ngõ 364 Minh Khai' then
      result.forward_rate = result.forward_speed * 6.845018450184502
      result.backward_rate = result.backward_speed * 6.845018450184502
  end
  if name == 'Bộ Giáo dục và Đào tạo' then
      result.forward_rate = result.forward_speed * 6.662361623616236
      result.backward_rate = result.backward_speed * 6.662361623616236
  end
  if name == 'Ngõ 4 Quỳnh Lôi' then
      result.forward_rate = result.forward_speed * 6.662361623616236
      result.backward_rate = result.backward_speed * 6.662361623616236
  end
  if name == 'Đường Tam Trinh' then
      result.forward_rate = result.forward_speed * 6.297047970479705
      result.backward_rate = result.backward_speed * 6.297047970479705
  end
  if name == 'Phố Hàng Ngang' then
      result.forward_rate = result.forward_speed * 5.931734317343174
      result.backward_rate = result.backward_speed * 5.931734317343174
  end
  if name == 'Phố Hàng Bồ' then
      result.forward_rate = result.forward_speed * 5.931734317343174
      result.backward_rate = result.backward_speed * 5.931734317343174
  end
  if name == 'Phố Hàng Bạc' then
      result.forward_rate = result.forward_speed * 5.931734317343174
      result.backward_rate = result.backward_speed * 5.931734317343174
  end
  if name == 'Ngõ 583' then
      result.forward_rate = result.forward_speed * 5.931734317343174
      result.backward_rate = result.backward_speed * 5.931734317343174
  end
  if name == 'Ngõ 641 Phố Kim Ngưu' then
      result.forward_rate = result.forward_speed * 5.3837638376383765
      result.backward_rate = result.backward_speed * 5.3837638376383765
  end
  if name == 'Phố Cao Đạt' then
      result.forward_rate = result.forward_speed * 5.3837638376383765
      result.backward_rate = result.backward_speed * 5.3837638376383765
  end
  if name == 'Phố Cầu Gỗ' then
      result.forward_rate = result.forward_speed * 5.3837638376383765
      result.backward_rate = result.backward_speed * 5.3837638376383765
  end
  if name == 'Ngõ 88 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 5.2011070110701105
      result.backward_rate = result.backward_speed * 5.2011070110701105
  end
  if name == 'Phố Lý Quốc Sư' then
      result.forward_rate = result.forward_speed * 5.018450184501845
      result.backward_rate = result.backward_speed * 5.018450184501845
  end
  if name == 'Ngõ 172' then
      result.forward_rate = result.forward_speed * 5.018450184501845
      result.backward_rate = result.backward_speed * 5.018450184501845
  end
  if name == 'Ngõ 469 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 5.018450184501845
      result.backward_rate = result.backward_speed * 5.018450184501845
  end
  if name == 'Ngõ 84 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 5.018450184501845
      result.backward_rate = result.backward_speed * 5.018450184501845
  end
  if name == 'Ngõ 622 Minh Khai' then
      result.forward_rate = result.forward_speed * 4.8357933579335795
      result.backward_rate = result.backward_speed * 4.8357933579335795
  end
  if name == 'Ngõ 487 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 4.8357933579335795
      result.backward_rate = result.backward_speed * 4.8357933579335795
  end
  if name == 'Ngõ 461 Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 4.8357933579335795
      result.backward_rate = result.backward_speed * 4.8357933579335795
  end
  if name == 'Phố Lê Thanh Nghị' then
      result.forward_rate = result.forward_speed * 4.6531365313653135
      result.backward_rate = result.backward_speed * 4.6531365313653135
  end
  if name == 'Phố Hàng Trống' then
      result.forward_rate = result.forward_speed * 4.6531365313653135
      result.backward_rate = result.backward_speed * 4.6531365313653135
  end
  if name == 'Ngách 13/21 Lĩnh Nam' then
      result.forward_rate = result.forward_speed * 4.6531365313653135
      result.backward_rate = result.backward_speed * 4.6531365313653135
  end
  if name == 'Phố Yên Lạc' then
      result.forward_rate = result.forward_speed * 4.470479704797048
      result.backward_rate = result.backward_speed * 4.470479704797048
  end
  if name == 'Phố Hai Bà Trưng' then
      result.forward_rate = result.forward_speed * 4.470479704797048
      result.backward_rate = result.backward_speed * 4.470479704797048
  end
  if name == 'Ngõ E4 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 4.287822878228782
      result.backward_rate = result.backward_speed * 4.287822878228782
  end
  if name == 'Phố Phạm Sư Mạnh' then
      result.forward_rate = result.forward_speed * 4.287822878228782
      result.backward_rate = result.backward_speed * 4.287822878228782
  end
  if name == 'Ngõ 260 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 4.105166051660516
      result.backward_rate = result.backward_speed * 4.105166051660516
  end
  if name == 'Phố Yên Bái 2' then
      result.forward_rate = result.forward_speed * 4.105166051660516
      result.backward_rate = result.backward_speed * 4.105166051660516
  end
  if name == 'Ngõ 31 Đại Cồ Việt' then
      result.forward_rate = result.forward_speed * 3.922509225092251
      result.backward_rate = result.backward_speed * 3.922509225092251
  end
  if name == 'Ngõ 174 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 3.922509225092251
      result.backward_rate = result.backward_speed * 3.922509225092251
  end
  if name == 'Ranh giới khu phố cổ Hà Nội' then
      result.forward_rate = result.forward_speed * 3.7398523985239858
      result.backward_rate = result.backward_speed * 3.7398523985239858
  end
  if name == 'Ngõ Hòa Bình 7' then
      result.forward_rate = result.forward_speed * 3.7398523985239858
      result.backward_rate = result.backward_speed * 3.7398523985239858
  end
  if name == 'Ngõ Xóm Hà Hồi' then
      result.forward_rate = result.forward_speed * 3.7398523985239858
      result.backward_rate = result.backward_speed * 3.7398523985239858
  end
  if name == 'Ngõ 180 Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 3.5571955719557193
      result.backward_rate = result.backward_speed * 3.5571955719557193
  end
  if name == 'Phố Bạch Mai' then
      result.forward_rate = result.forward_speed * 3.5571955719557193
      result.backward_rate = result.backward_speed * 3.5571955719557193
  end
  if name == 'Phố Hàng Gai' then
      result.forward_rate = result.forward_speed * 3.5571955719557193
      result.backward_rate = result.backward_speed * 3.5571955719557193
  end
  if name == 'Ngõ Phan Chu Trinh' then
      result.forward_rate = result.forward_speed * 3.374538745387454
      result.backward_rate = result.backward_speed * 3.374538745387454
  end
  if name == 'Phố Chùa Vua' then
      result.forward_rate = result.forward_speed * 3.374538745387454
      result.backward_rate = result.backward_speed * 3.374538745387454
  end
  if name == 'Cầu vượt Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 3.374538745387454
      result.backward_rate = result.backward_speed * 3.374538745387454
  end
  if name == 'Ngõ 536 Phố Minh Khai' then
      result.forward_rate = result.forward_speed * 3.374538745387454
      result.backward_rate = result.backward_speed * 3.374538745387454
  end
  if name == 'Vân Hồ 3' then
      result.forward_rate = result.forward_speed * 3.374538745387454
      result.backward_rate = result.backward_speed * 3.374538745387454
  end
  if name == 'Ngõ 187' then
      result.forward_rate = result.forward_speed * 3.1918819188191883
      result.backward_rate = result.backward_speed * 3.1918819188191883
  end
  if name == 'Ngõ 190 Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 3.1918819188191883
      result.backward_rate = result.backward_speed * 3.1918819188191883
  end
  if name == 'Ngõ 257' then
      result.forward_rate = result.forward_speed * 3.1918819188191883
      result.backward_rate = result.backward_speed * 3.1918819188191883
  end
  if name == 'Phố Quỳnh Mai' then
      result.forward_rate = result.forward_speed * 3.1918819188191883
      result.backward_rate = result.backward_speed * 3.1918819188191883
  end
  if name == 'Ngõ 189 Phố Thanh Nhàn' then
      result.forward_rate = result.forward_speed * 3.1918819188191883
      result.backward_rate = result.backward_speed * 3.1918819188191883
  end
  if name == 'Ngõ 42 Phố Võ Thị Sáu' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Phố Bà Triệu' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Phố Lý Thường Kiệt' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Ngõ Tràng Tiền' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Ngõ 647 Phố Kim Ngưu' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Ngõ 102 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Ngõ 27 Đại Cồ Việt' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Ngõ Hòa Bình 3' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Ngõ 44 Phố Võ Thị Sáu' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Phố Trần Nhân Tông' then
      result.forward_rate = result.forward_speed * 3.0092250922509227
      result.backward_rate = result.backward_speed * 3.0092250922509227
  end
  if name == 'Ngõ 158 Phố Hồng Mai' then
      result.forward_rate = result.forward_speed * 2.8265682656826567
      result.backward_rate = result.backward_speed * 2.8265682656826567
  end
  if name == 'Ngõ 279 Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 2.8265682656826567
      result.backward_rate = result.backward_speed * 2.8265682656826567
  end
  if name == 'Ngách 10 Ngõ 156 Phố Hồng Mai' then
      result.forward_rate = result.forward_speed * 2.8265682656826567
      result.backward_rate = result.backward_speed * 2.8265682656826567
  end
  if name == 'Ngõ 54 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 2.8265682656826567
      result.backward_rate = result.backward_speed * 2.8265682656826567
  end
  if name == 'Ngõ 34 Vĩnh Tuy' then
      result.forward_rate = result.forward_speed * 2.643911439114391
      result.backward_rate = result.backward_speed * 2.643911439114391
  end
  if name == 'Cầu Vượt Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 2.643911439114391
      result.backward_rate = result.backward_speed * 2.643911439114391
  end
  if name == 'Ngõ Hòa Bình 2' then
      result.forward_rate = result.forward_speed * 2.643911439114391
      result.backward_rate = result.backward_speed * 2.643911439114391
  end
  if name == 'Phố Trần Hưng Đạo' then
      result.forward_rate = result.forward_speed * 2.643911439114391
      result.backward_rate = result.backward_speed * 2.643911439114391
  end
  if name == 'Ngõ 254 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 2.643911439114391
      result.backward_rate = result.backward_speed * 2.643911439114391
  end
  if name == 'Hòa Bình Green City' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Phố Tràng Thi' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Ngõ 100 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Phố Lê Đại Hành' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Phố Lạc Nghiệp' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Cầu Kim Ngưu S3' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Ngõ Hòa Bình 4' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Ngõ 93 Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Ngõ 88 Chùa Quỳnh' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Ngõ Quỳnh' then
      result.forward_rate = result.forward_speed * 2.461254612546125
      result.backward_rate = result.backward_speed * 2.461254612546125
  end
  if name == 'Ngõ 10 Phố 8 Tháng 3' then
      result.forward_rate = result.forward_speed * 2.2785977859778597
      result.backward_rate = result.backward_speed * 2.2785977859778597
  end
  if name == 'Ngõ 624 Phố Minh Khai' then
      result.forward_rate = result.forward_speed * 2.2785977859778597
      result.backward_rate = result.backward_speed * 2.2785977859778597
  end
  if name == 'Phố 8 Tháng 3' then
      result.forward_rate = result.forward_speed * 2.2785977859778597
      result.backward_rate = result.backward_speed * 2.2785977859778597
  end
  if name == 'Ngõ 124 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 2.2785977859778597
      result.backward_rate = result.backward_speed * 2.2785977859778597
  end
  if name == 'Phố Hàng Khay' then
      result.forward_rate = result.forward_speed * 2.2785977859778597
      result.backward_rate = result.backward_speed * 2.2785977859778597
  end
  if name == 'Ngõ 302 Phố Minh Khai' then
      result.forward_rate = result.forward_speed * 2.2785977859778597
      result.backward_rate = result.backward_speed * 2.2785977859778597
  end
  if name == 'Ngách 624/12 Phố Minh Khai' then
      result.forward_rate = result.forward_speed * 2.2785977859778597
      result.backward_rate = result.backward_speed * 2.2785977859778597
  end
  if name == 'Ngõ 254D Minh Khai' then
      result.forward_rate = result.forward_speed * 2.2785977859778597
      result.backward_rate = result.backward_speed * 2.2785977859778597
  end
  if name == 'Ngõ 308 Phố Minh Khai' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ 327 Thanh Nhàn' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngách 17 Ngõ 295 Phố Bạch Mai' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ 343 Phố Kim Ngưu' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Phố Hàng Dầu' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ 66 Đại Cồ Việt' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ 8 Quỳnh Lôi' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ 250 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ 203 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ 102+104' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Phố Mạc Thị Bưởi' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ Hòa Bình 1' then
      result.forward_rate = result.forward_speed * 2.095940959409594
      result.backward_rate = result.backward_speed * 2.095940959409594
  end
  if name == 'Ngõ 13' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Phố Bùi Ngọc Dương' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Phố Lê Văn Hưu' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Phố Hoa Lư' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Cầu Kim Ngưu S2' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Cầu Mai Động' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ 158 Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Phố Hàm Long' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ 254 Minh Khai' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ 168 Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ 331 Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Phố Hàn Thuyên' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ 459 Phố Bạch Mai' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ 9 Minh Khai' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ 89 Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ 40 Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ Hòa Bình 5' then
      result.forward_rate = result.forward_speed * 1.9132841328413284
      result.backward_rate = result.backward_speed * 1.9132841328413284
  end
  if name == 'Ngõ Hòa Bình 6' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 505 Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Phố Nguyễn Công Trứ' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 260 Phố Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 186 Phố Hồng Mai' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 296 Phố Minh Khai' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Phố Thọ Lão' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 285' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 22 phố Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 74 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 17 Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Cầu Kim Ngưu S4' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Phố Đông Mác' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 4 Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Phố Vĩnh Tuy' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 9 Quỳnh Lôi' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Phố Vân Hồ 3' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 1 Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 44 Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ 40' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngách 204/3' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Phố Dương Văn Bé' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Ngõ Tân Lập' then
      result.forward_rate = result.forward_speed * 1.7306273062730626
      result.backward_rate = result.backward_speed * 1.7306273062730626
  end
  if name == 'Cầu Lạc Trung' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Phố Nguyễn Cao' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 153 Phố Thanh Nhàn' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 30 Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 433 Phố Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 40 Võ Thị Sáu' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 101 Thanh Nhàn' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 116 Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 30 Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngách 14 Ngõ 156 Phố Hồng Mai' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Phố Nguyễn Du' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 164 Hồng Mai' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 252' then
      result.forward_rate = result.forward_speed * 1.547970479704797
      result.backward_rate = result.backward_speed * 1.547970479704797
  end
  if name == 'Ngõ 84 Phố Võ Thị Sáu' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 96 Lò Đúc' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Phố Hoà Mã' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 433 Bạch Mai' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 506 Bạch Mai' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 37 Hồng Mai' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 281 Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 269' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Phố Lê Lai' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Cầu vượt Ô Đông Mác' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Phố Trần Nguyên Hãn' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngách 121/3 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 100 Nguyễn Văn Viên' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Phố Đinh Lễ' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Phố Tô Hiến Thành' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Phố Tuệ Tĩnh' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Phố Tràng Tiền' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Phố Phạm Đình Hổ' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 121 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 150 Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 1.3653136531365313
      result.backward_rate = result.backward_speed * 1.3653136531365313
  end
  if name == 'Ngõ 19 Nguyễn Công Trứ' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 19 Lạc Trung' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 15 Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Phố Nguyễn Xí' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 132 Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Phố Ngô Quyền' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 159' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 108 Phố Lò Đúc' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Phố Thợ Nhuộm' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Phố Hồ Hoàn Kiếm' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 16 phố Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Phố Trần Xuân Soạn' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 19 Phố Hồng Mai' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Phố Lò Sũ' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 216' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 27 Tạ Quang Bửu' then
      result.forward_rate = result.forward_speed * 1.1826568265682658
      result.backward_rate = result.backward_speed * 1.1826568265682658
  end
  if name == 'Ngõ 203 Phố Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Hồ Xuân Hương' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 29 Hồng Mai' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 325 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 34 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Huế' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Báo Khánh' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 18 Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 156 Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 61 Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 51 Nguyễn Đình Chiểu' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 424 Trần Khát Chân' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ Giếng Mứt' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Ngô Văn Sở' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Lương Văn Can' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Lạc Trung' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Không gian Văn hoá Việt' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngách 1 Ngõ 203 Phố Kim Ngưu' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngách 295/75' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngách 295/85' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngách 90 Ngõ 13 Đường Lĩnh Nam' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 1 Đồng Nhân' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Trường Tiểu học Bạch Mai' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Trần Quốc Toản' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Ngõ 110' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if name == 'Phố Yec Xanh' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if oneway == 'yes' then
      result.forward_rate = result.forward_speed * 100.0
      result.backward_rate = result.backward_speed * 100.0
  end
  if oneway == 'no' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
  if surface == 'asphalt' then
      result.forward_rate = result.forward_speed * 100.0
      result.backward_rate = result.backward_speed * 100.0
  end
  if surface == 'concrete' then
      result.forward_rate = result.forward_speed * 9.15934065934066
      result.backward_rate = result.backward_speed * 9.15934065934066
  end
  if surface == 'paving_stones' then
      result.forward_rate = result.forward_speed * 5.181662087912088
      result.backward_rate = result.backward_speed * 5.181662087912088
  end
  if surface == 'concrete:plates' then
      result.forward_rate = result.forward_speed * 4.365728021978022
      result.backward_rate = result.backward_speed * 4.365728021978022
  end
  if surface == 'unpaved' then
      result.forward_rate = result.forward_speed * 1.1699862637362637
      result.backward_rate = result.backward_speed * 1.1699862637362637
  end
  if surface == 'metal' then
      result.forward_rate = result.forward_speed * 1.0
      result.backward_rate = result.backward_speed * 1.0
  end
end

return {
  setup = setup,
  process_way =  process_way,
  process_node = process_node,
  process_turn = process_turn
}