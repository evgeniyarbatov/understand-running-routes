
function custom_tag_weights(profile, way, result, data)
local crossing = way:get_value_by_key('crossing')
local footway = way:get_value_by_key('footway')
local highway = way:get_value_by_key('highway')
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
